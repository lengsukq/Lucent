#!/usr/bin/env python3
"""Coordinator and view-card builder for the Lumakey `ai-quota` plugin."""

from __future__ import annotations

import concurrent.futures
import datetime as dt
import json
import os
import re
import sys
import time
from pathlib import Path
from typing import Any

from cli_collectors import (
    build_cli_env,
    clamp_pct,
    collect_agy,
    collect_claude,
    collect_codex,
    collect_dsh,
)
from deepseek_client import query_deepseek_balances

PROVIDER_ORDER = ["codex", "claude", "agy", "dsh", "deepseek"]

PROVIDER_META: dict[str, dict[str, str]] = {
    "codex": {
        "name_zh": "OpenAI Codex CLI",
        "name_en": "OpenAI Codex CLI",
        "icon": "terminal.fill",
        "cli": "codex",
    },
    "claude": {
        "name_zh": "Claude Code",
        "name_en": "Claude Code",
        "icon": "sparkles.rectangle.stack.fill",
        "cli": "claude",
    },
    "agy": {
        "name_zh": "Antigravity (agy)",
        "name_en": "Antigravity (agy)",
        "icon": "bolt.horizontal.circle.fill",
        "cli": "agy",
    },
    "dsh": {
        "name_zh": "DSH (DeepSeek Harness)",
        "name_en": "DSH (DeepSeek Harness)",
        "icon": "cpu.fill",
        "cli": "dsh",
    },
    "deepseek": {
        "name_zh": "DeepSeek API 账户余额",
        "name_en": "DeepSeek API Balance",
        "icon": "yensign.circle.fill",
        "cli": "",
    },
}


def format_compact_tokens(count: int) -> str:
    n = max(0, int(count))
    if n >= 1_000_000_000:
        return f"{n / 1_000_000_000:.2f}B"
    if n >= 1_000_000:
        return f"{n / 1_000_000:.2f}M"
    if n >= 1_000:
        return f"{n / 1_000:.1f}k"
    return str(n)


def format_reset_countdown(reset_ts: float, is_en: bool, now: float | None = None) -> str:
    if reset_ts <= 0:
        return ""
    ref = now if now is not None else time.time()
    rem = int(reset_ts - ref)
    if rem <= 0:
        return "resetting" if is_en else "即将重置"
    days, rem2 = divmod(rem, 86400)
    hours, rem3 = divmod(rem2, 3600)
    mins = max(1, rem3 // 60) if days == 0 and hours == 0 else rem3 // 60
    if days > 0:
        return f"↻ {days}d {hours}h" if is_en else f"{days}天{hours}小时后重置"
    if hours > 0:
        return f"↻ {hours}h {mins}m" if is_en else f"{hours}h{mins:02d}m 后重置"
    return f"↻ {mins}m" if is_en else f"{mins} 分钟后重置"


def render_bar(used_pct: float, display_mode: str = "remaining", width: int = 10) -> str:
    u = clamp_pct(used_pct)
    shown = (100.0 - u) if display_mode == "remaining" else u
    filled = max(0, min(width, int(round((shown / 100.0) * width))))
    return "█" * filled + "░" * (width - filled)


def format_pct_label(used_pct: float, display_mode: str, is_en: bool) -> str:
    u = clamp_pct(used_pct)
    if display_mode == "used":
        pct_txt = f"{u:.0f}%" if abs(u - round(u)) < 0.15 else f"{u:.1f}%"
        return f"{pct_txt} used" if is_en else f"已用 {pct_txt}"
    rem = clamp_pct(100.0 - u)
    pct_txt = f"{rem:.0f}%" if abs(rem - round(rem)) < 0.15 else f"{rem:.1f}%"
    return f"{pct_txt} left" if is_en else f"剩余 {pct_txt}"


def severity_tint(max_used_pct: float | None, ok: bool = True) -> str:
    if not ok:
        return "slate"
    if max_used_pct is None:
        return "teal"
    if max_used_pct >= 90.0:
        return "red"
    if max_used_pct >= 70.0:
        return "orange"
    return "emerald"


def classify_window_label(seconds: int | float | None, fallback_zh: str, fallback_en: str, is_en: bool) -> str:
    if not seconds:
        return fallback_en if is_en else fallback_zh
    sec = float(seconds)
    if 14_000 <= sec <= 22_000:
        return "5h"
    if 500_000 <= sec <= 700_000:
        return "7d" if is_en else "周限"
    if 80_000 <= sec <= 95_000:
        return "24h" if is_en else "日限"
    return f"{max(1, int(round(sec / 3600.0)))}h"


def parse_enabled_providers(raw: str) -> list[str]:
    tokens = [t.strip().lower() for t in re.split(r"[,，\s]+", raw or "") if t.strip()]
    if not tokens:
        return list(PROVIDER_ORDER)
    alias_map = {
        "codex": "codex",
        "openai": "codex",
        "claude": "claude",
        "claudecode": "claude",
        "cc": "claude",
        "agy": "agy",
        "antigravity": "agy",
        "dsh": "dsh",
        "harness": "dsh",
        "deepseek": "deepseek",
        "ds": "deepseek",
    }
    out: list[str] = []
    for tok in tokens:
        mapped = alias_map.get(tok)
        if mapped and mapped not in out:
            out.append(mapped)
    return out or list(PROVIDER_ORDER)


def collect_all_snapshots(
    enabled_providers: list[str],
    cfg: dict[str, Any],
    data_dir: Path | None,
    user_home: Path | None = None,
    force_refresh: bool = False,
) -> tuple[dict[str, dict[str, Any]], str]:
    home = user_home or Path(os.environ.get("LUMAKEY_QUOTA_HOME") or os.environ.get("HOME") or ".")
    try:
        ttl = max(0, min(600, int(cfg.get("cacheTtlSeconds") if cfg.get("cacheTtlSeconds") is not None else 45)))
    except ValueError:
        ttl = 45

    raw_ds_key = str(cfg.get("deepseekApiKey") or "").strip()
    extra_paths = str(cfg.get("extraCliPaths") or "").strip()
    cache_sig = f"{','.join(enabled_providers)}:{'1' if raw_ds_key else '0'}"

    cache_file = (data_dir / "quota-snapshot.json") if data_dir else None
    if not force_refresh and ttl > 0 and cache_file and cache_file.is_file():
        try:
            cached = json.loads(cache_file.read_text(encoding="utf-8"))
            age = time.time() - float(cached.get("savedAt") or 0.0)
            if age <= ttl and cached.get("sig") == cache_sig and isinstance(cached.get("snapshots"), dict):
                return (cached["snapshots"], f"{int(age)}s cache")
        except Exception:
            pass

    env = build_cli_env(home=home, extra_paths=extra_paths)
    snapshots: dict[str, dict[str, Any]] = {}

    with concurrent.futures.ThreadPoolExecutor(max_workers=5) as pool:
        futs: dict[str, concurrent.futures.Future[dict[str, Any]]] = {}
        for pid in enabled_providers:
            if pid == "codex":
                futs[pid] = pool.submit(collect_codex, home, env)
            elif pid == "claude":
                futs[pid] = pool.submit(collect_claude, home, env)
            elif pid == "agy":
                futs[pid] = pool.submit(collect_agy, home, env)
            elif pid == "dsh":
                futs[pid] = pool.submit(collect_dsh, home, env)
            elif pid == "deepseek":
                futs[pid] = pool.submit(query_deepseek_balances, raw_ds_key)

        for pid, fut in futs.items():
            try:
                snapshots[pid] = fut.result(timeout=4.2)
            except Exception as exc:
                snapshots[pid] = {"provider": pid, "installed": False, "error": str(exc)[:60], "windows": []}

    if cache_file:
        try:
            cache_file.parent.mkdir(parents=True, exist_ok=True)
            cache_file.write_text(
                json.dumps({"savedAt": time.time(), "sig": cache_sig, "snapshots": snapshots}, ensure_ascii=False),
                encoding="utf-8",
            )
        except OSError:
            pass

    return (snapshots, "live")

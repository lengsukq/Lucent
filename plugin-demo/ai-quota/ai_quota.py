#!/usr/bin/env python3
"""Entry point and PluginViewPayload / Custom HUD JSON presenter for `ai-quota`."""

from __future__ import annotations

import datetime as dt
import json
import os
import sys
from pathlib import Path
from typing import Any

from cli_collectors import clamp_pct
from quota_core import (
    PROVIDER_META,
    classify_window_label,
    collect_all_snapshots,
    format_compact_tokens,
    format_pct_label,
    format_reset_countdown,
    parse_enabled_providers,
    render_bar,
    severity_tint,
)


def _summarize_windows_short(windows: list[dict[str, Any]], display_mode: str, is_en: bool) -> str:
    if not windows:
        return ""
    parts: list[str] = []
    for w in windows[:2]:
        lbl = classify_window_label(w.get("window_seconds"), w.get("default_zh", ""), w.get("default_en", ""), is_en)
        u = clamp_pct(float(w["used_pct"]))
        val = (100.0 - u) if display_mode == "remaining" else u
        parts.append(f"{lbl} {val:.0f}%")
    return " · ".join(parts)


def _format_cli_item(snap: dict[str, Any], display_mode: str, is_en: bool) -> tuple[dict[str, Any], str]:
    pid = snap["provider"]
    meta = PROVIDER_META[pid]
    title_base = meta["name_en"] if is_en else meta["name_zh"]
    windows: list[dict[str, Any]] = snap.get("windows") or []
    installed = bool(snap.get("installed"))
    ver = str(snap.get("cliVersion") or "")
    plan = str(snap.get("plan") or "")

    header_tags = [x for x in (plan, ver) if x]
    full_title = f"{title_base} ({' · '.join(header_tags)})" if header_tags else title_base

    if pid == "dsh":
        calls = int(snap.get("todayCalls") or 0)
        toks = int(snap.get("todayTokens") or 0)
        hit = float(snap.get("cacheHitPct") or 0.0)
        cost = float(snap.get("todayCostCny") or 0.0)
        profs = snap.get("profiles") or []

        if not installed:
            sub = "dsh CLI not detected on this Mac" if is_en else "未在本机检测到 dsh CLI"
            metric_txt = "Not installed" if is_en else "未安装"
            badge_txt = "OFFLINE"
            tint = "slate"
        else:
            bits: list[str] = ["CLI Ready" if is_en else "CLI 已就绪"]
            if calls > 0 or toks > 0:
                bits.append(
                    f"Today {calls} calls ({format_compact_tokens(toks)} tok)"
                    if is_en
                    else f"今日 {calls} 次（{format_compact_tokens(toks)} tok）"
                )
            if hit > 0:
                bits.append(f"Cache {hit:.0f}%" if is_en else f"缓存命中 {hit:.0f}%")
            if cost > 0:
                bits.append(f"≈ ¥{cost:.2f}")
            if profs:
                bits.append(f"Profiles: {', '.join(profs[:3])}")
            if windows:
                w0 = windows[0]
                bits.insert(
                    0,
                    f"[{render_bar(w0['used_pct'], display_mode)}] {format_pct_label(w0['used_pct'], display_mode, is_en)}",
                )
            sub = " · ".join(bits)
            metric_txt = (
                f"¥{cost:.2f} · {format_compact_tokens(toks)}"
                if cost > 0
                else (f"{calls} 次 · {format_compact_tokens(toks)}" if calls > 0 else (ver or "Ready"))
            )
            badge_txt = f"≈ ¥{cost:.2f}" if cost > 0 else "CLI READY"
            tint = "emerald" if calls > 0 else "teal"

        return (
            {
                "id": f"aq-{pid}",
                "title": full_title,
                "subtitle": sub,
                "icon": meta["icon"],
                "tintColor": tint,
                "badge": badge_txt,
                "copyText": f"{full_title}: {sub}",
                "actions": [
                    {
                        "id": f"refresh-{pid}",
                        "label": "Refresh" if is_en else "实时刷新",
                        "style": "primary",
                        "commandArgs": ["--refresh", "--provider", pid],
                    }
                ],
            },
            metric_txt,
        )

    if not installed:
        cli_cmd = meta["cli"]
        sub = (
            f"Local '{cli_cmd}' CLI not detected in standard bin directories"
            if is_en
            else f"未在本机常用命令目录中检测到 {cli_cmd} CLI"
        )
        return (
            {
                "id": f"aq-{pid}",
                "title": full_title,
                "subtitle": sub,
                "icon": meta["icon"],
                "tintColor": "slate",
                "badge": "NOT FOUND",
                "actions": [
                    {
                        "id": f"refresh-{pid}",
                        "label": "Re-scan" if is_en else "重新扫描",
                        "commandArgs": ["--refresh", "--provider", pid],
                    }
                ],
            },
            "Not found" if is_en else "未安装",
        )

    lines: list[str] = []
    max_used: float | None = None
    for w in windows[:3]:
        u = clamp_pct(float(w["used_pct"]))
        max_used = u if max_used is None else max(max_used, u)
        lbl = classify_window_label(w.get("window_seconds"), w.get("default_zh", ""), w.get("default_en", ""), is_en)
        bar = render_bar(u, display_mode=display_mode, width=10)
        pct_str = format_pct_label(u, display_mode=display_mode, is_en=is_en)
        rst = format_reset_countdown(float(w.get("reset_ts") or 0.0), is_en=is_en)
        lines.append(f"{lbl} [{bar}] {pct_str}" + (f" ({rst})" if rst else ""))

    extra_bits: list[str] = []
    toks = int(snap.get("todayTokens") or 0)
    sess = int(snap.get("todaySessions") or 0)
    if toks > 0:
        extra_bits.append(
            f"Today {format_compact_tokens(toks)} tok ({sess} sess)"
            if is_en
            else f"今日 {format_compact_tokens(toks)} tok（{sess} 会话）"
        )
    if snap.get("cacheHitPct") and float(snap["cacheHitPct"]) > 0:
        extra_bits.append(
            f"Cache {float(snap['cacheHitPct']):.0f}%"
            if is_en
            else f"缓存 {float(snap['cacheHitPct']):.0f}%"
        )
    if snap.get("credits"):
        extra_bits.append(f"Credits {snap['credits']}")
    if snap.get("source"):
        extra_bits.append(str(snap["source"]))

    if not lines:
        lines.append(
            "CLI installed; run one session to populate live quota windows"
            if is_en
            else "已检测到本机 CLI（运行一次会话后自动生成活跃窗口配额记录）"
        )
    if extra_bits:
        lines.append(" · ".join(extra_bits))

    short_win = _summarize_windows_short(windows, display_mode=display_mode, is_en=is_en)
    metric_val = short_win or (
        f"Today {format_compact_tokens(toks)}"
        if (is_en and toks > 0)
        else (f"今日 {format_compact_tokens(toks)}" if toks > 0 else (ver or ("Installed" if is_en else "已安装")))
    )
    badge_val = short_win.upper() if short_win else (ver or "READY")
    subtitle_txt = "\n".join(lines)

    return (
        {
            "id": f"aq-{pid}",
            "title": full_title,
            "subtitle": subtitle_txt,
            "icon": meta["icon"],
            "tintColor": severity_tint(max_used, ok=True),
            "badge": badge_val[:22],
            "copyText": f"{full_title} — {subtitle_txt.replace(chr(10), ' | ')}",
            "actions": [
                {
                    "id": f"refresh-{pid}",
                    "label": "Refresh" if is_en else "实时刷新",
                    "style": "primary",
                    "commandArgs": ["--refresh", "--provider", pid],
                }
            ],
        },
        metric_val,
    )


def _format_deepseek_item(snap: dict[str, Any], is_en: bool) -> tuple[dict[str, Any], str]:
    meta = PROVIDER_META["deepseek"]
    title = meta["name_en"] if is_en else meta["name_zh"]

    if not snap.get("configured"):
        sub = (
            "Open plugin settings (⌘,) to save your DeepSeek API Key in Lumakey's encrypted vault"
            if is_en
            else "在插件设置 (⌘,) 填入 DeepSeek API Key（本机 AES-GCM 加密托管），即可实时查询 CNY / USD 余额"
        )
        return (
            {
                "id": "aq-deepseek-unconfigured",
                "title": title,
                "subtitle": sub,
                "icon": meta["icon"],
                "tintColor": "amber",
                "badge": "SET API KEY",
                "openURL": "lumakey://settings/plugin/ai-quota",
                "actions": [
                    {
                        "id": "refresh-deepseek",
                        "label": "Check Again" if is_en else "重新检测密钥",
                        "commandArgs": ["--refresh", "--provider", "deepseek"],
                    }
                ],
            },
            "Set Key (⌘,)" if is_en else "待填 Key (⌘,)",
        )

    accounts: list[dict[str, Any]] = snap.get("accounts") or []
    if not accounts:
        err = str(snap.get("error") or ("Request failed" if is_en else "余额请求失败"))
        return (
            {
                "id": "aq-deepseek-error",
                "title": title,
                "subtitle": f"Balance API error ({err})" if is_en else f"DeepSeek 余额接口查询失败（{err}）",
                "icon": "exclamationmark.triangle.fill",
                "tintColor": "red",
                "badge": "API ERROR",
                "actions": [
                    {
                        "id": "retry-deepseek",
                        "label": "Retry" if is_en else "重试查询",
                        "style": "primary",
                        "commandArgs": ["--refresh", "--provider", "deepseek"],
                    }
                ],
            },
            "API Error" if is_en else "查询异常",
        )

    acct_lines: list[str] = []
    headline_totals: list[str] = []
    any_low = False
    any_unavailable = False

    for acct in accounts:
        lbl = str(acct.get("label") or "DeepSeek")
        avail = bool(acct.get("isAvailable", True))
        if not avail:
            any_unavailable = True
        curs = acct.get("currencies") or []
        cur_parts: list[str] = []
        for c in curs:
            sym = c["symbol"]
            tot = float(c["total"])
            granted = float(c["granted"])
            topped = float(c["toppedUp"])
            if tot <= 0 and len(curs) > 1:
                continue
            if (c["currency"] == "CNY" and tot < 5.0) or (c["currency"] == "USD" and tot < 1.0):
                any_low = True
            headline_totals.append(f"{sym}{tot:.2f}")
            detail = (
                f"{sym}{tot:.2f} (Top-up {sym}{topped:.2f} · Grant {sym}{granted:.2f})"
                if is_en
                else f"{sym}{tot:.2f}（充值 {sym}{topped:.2f} · 赠金 {sym}{granted:.2f}）"
            )
            cur_parts.append(detail)
        if not cur_parts:
            cur_parts.append("¥0.00")
            headline_totals.append("¥0.00")
        prefix = f"[{lbl}] " if len(accounts) > 1 else ""
        state_str = ("Available" if avail else "Insufficient") if is_en else ("可用" if avail else "余额不足")
        acct_lines.append(f"{prefix}{' / '.join(cur_parts)} · {state_str}")

    metric_str = " · ".join(headline_totals[:2])
    tint = "red" if any_unavailable else ("orange" if any_low else "emerald")
    sub_txt = "\n".join(acct_lines)

    return (
        {
            "id": "aq-deepseek",
            "title": title,
            "subtitle": sub_txt,
            "icon": meta["icon"],
            "tintColor": tint,
            "badge": metric_str[:22],
            "copyText": f"{title}: {sub_txt.replace(chr(10), ' | ')}",
            "actions": [
                {
                    "id": "refresh-deepseek",
                    "label": "Refresh Balance" if is_en else "刷新余额",
                    "style": "primary",
                    "commandArgs": ["--refresh", "--provider", "deepseek"],
                }
            ],
        },
        metric_str,
    )


def _build_hud_telemetry(
    target_providers: list[str],
    snapshots: dict[str, dict[str, Any]],
    rows: list[dict[str, Any]],
    metric_map: dict[str, str],
    display_mode: str,
    status_summary: str,
    status_badge: str,
    cache_state: str,
    float_interval: int,
) -> dict[str, Any]:
    short_names = {
        "codex": "Codex",
        "claude": "Claude",
        "agy": "AGY",
        "dsh": "DSH",
        "deepseek": "DeepSeek",
    }
    row_by_pid = {str(r.get("id") or "").split("-")[1]: r for r in rows if "-" in str(r.get("id") or "")}
    providers_out: list[dict[str, Any]] = []
    for pid in target_providers:
        snap = snapshots.get(pid) or {}
        row = row_by_pid.get(pid) or {}
        wins = snap.get("windows") or []
        pct: float | None = None
        if wins:
            u = clamp_pct(float(wins[0]["used_pct"]))
            pct = (100.0 - u) if display_mode == "remaining" else u
        active = bool(snap.get("installed")) if pid != "deepseek" else bool(snap.get("configured") and snap.get("accounts"))
        providers_out.append(
            {
                "id": pid,
                "shortName": short_names.get(pid, pid.upper()),
                "title": str(row.get("title") or pid),
                "badge": str(row.get("badge") or ""),
                "shortValue": metric_map.get(pid, "—"),
                "primaryPercent": round(pct, 1) if pct is not None else None,
                "active": active,
                "detail": str(row.get("subtitle") or "").replace("\n", " · "),
            }
        )
    return {
        "ok": True,
        "updatedClock": dt.datetime.now().strftime("%H:%M:%S"),
        "cacheState": cache_state,
        "displayMode": display_mode,
        "intervalSeconds": float_interval,
        "statusSummary": status_summary,
        "statusBadge": status_badge,
        "providers": providers_out,
    }


def export_status_and_search_index(
    rows: list[dict[str, Any]],
    metric_map: dict[str, str],
    data_dir: Path | None,
    is_en: bool,
) -> tuple[str, str]:
    summary_parts: list[str] = []
    for pid, short_lbl in (("codex", "Codex"), ("claude", "Claude"), ("agy", "AGY"), ("deepseek", "DS")):
        val = metric_map.get(pid, "")
        if val and val not in {"未安装", "Not found", "待填 Key (⌘,)", "Set Key (⌘,)"}:
            summary_parts.append(f"{short_lbl}: {val}")
    if not summary_parts and metric_map.get("dsh") and metric_map["dsh"] not in {"未安装", "Not installed"}:
        summary_parts.append(f"DSH: {metric_map['dsh']}")

    summary = " · ".join(summary_parts[:3]) or (
        "Ready to inspect AI CLI quotas" if is_en else "实时监控 AI CLI 额度与余额"
    )
    active_cnt = len(summary_parts)
    badge = f"{active_cnt} LIVE" if active_cnt > 0 else "QUOTA"

    if data_dir:
        try:
            data_dir.mkdir(parents=True, exist_ok=True)
            idx_items = [
                {
                    "id": str(row.get("id") or ""),
                    "title": str(row.get("title") or ""),
                    "subtitle": str(row.get("subtitle") or "").replace("\n", " · "),
                    "copyText": str(row.get("copyText") or ""),
                    "icon": str(row.get("icon") or "gauge.medium"),
                    "tintColor": str(row.get("tintColor") or "emerald"),
                    "badge": str(row.get("badge") or ""),
                    "tags": ["quota", "usage", "limit", "额度", "余量", "余额", str(row.get("id") or "").removeprefix("aq-")],
                    "priority": 72,
                }
                for row in rows
            ]
            tmp_idx = data_dir / "search-index.json.tmp"
            tmp_idx.write_text(json.dumps({"version": 1, "items": idx_items}, ensure_ascii=False), encoding="utf-8")
            tmp_idx.replace(data_dir / "search-index.json")
            (data_dir / "status.json").write_text(
                json.dumps({"summary": summary, "badge": badge}, ensure_ascii=False),
                encoding="utf-8",
            )
        except OSError:
            pass

    return (summary, badge)


def dispatch(stdin_payload: dict[str, Any], argv: list[str], user_home: Path | None = None) -> dict[str, Any]:
    cfg = stdin_payload.get("config") if isinstance(stdin_payload.get("config"), dict) else {}
    query = str(stdin_payload.get("query") or "").strip().lower()
    locale = str(stdin_payload.get("locale") or os.environ.get("LUMAKEY_LOCALE") or "zh-Hans")
    is_en = locale.lower().startswith("en")
    raw_dd = str(stdin_payload.get("dataDir") or os.environ.get("LUMAKEY_DATA_DIR") or "").strip()
    data_dir = Path(raw_dd) if raw_dd else None

    enabled = parse_enabled_providers(str(cfg.get("enabledProviders") or "codex, claude, agy, dsh, deepseek"))
    display_mode = "used" if str(cfg.get("displayMode") or "remaining").lower() == "used" else "remaining"
    notify_on_refresh = str(cfg.get("notifyOnRefresh", "true")).lower() != "false"
    try:
        float_interval = max(15, min(300, int(cfg.get("floatingIntervalSeconds") or 30)))
    except ValueError:
        float_interval = 30

    force_refresh = False
    open_floating = False
    open_custom_hud = False
    raw_json_mode = False
    provider_filter: list[str] = []
    toast_msg: str | None = None

    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--json":
            raw_json_mode = True
            i += 1
            continue
        if arg == "--custom-hud":
            open_custom_hud = True
            toast_msg = "Opened frameless AI Quota Glass HUD" if is_en else "已打开无边框透明玻璃 AI 额度挂件"
            i += 1
            continue
        if arg == "--float-panel":
            open_floating = True
            toast_msg = "Opened pinned AI quota floating panel" if is_en else "已弹出独立置顶 AI 额度悬浮面板"
            i += 1
            continue
        if arg == "--refresh":
            force_refresh = True
            toast_msg = "Refreshed AI CLI quotas & balances" if is_en else "已实时刷新全部 CLI 额度与 API 余额"
            i += 1
            continue
        if arg == "--provider" and i + 1 < len(argv):
            raw_p = argv[i + 1].lower().strip()
            if raw_p == "deepseek-dsh":
                provider_filter = ["deepseek", "dsh"]
            elif raw_p in PROVIDER_META:
                provider_filter = [raw_p]
            i += 2
            continue
        i += 1

    target_providers = list(enabled)
    for pf in provider_filter:
        if pf not in target_providers:
            target_providers.append(pf)

    snapshots, cache_state = collect_all_snapshots(
        enabled_providers=target_providers,
        cfg=cfg,
        data_dir=data_dir,
        user_home=user_home,
        force_refresh=force_refresh,
    )

    all_rows: list[dict[str, Any]] = []
    metric_map: dict[str, str] = {}
    for pid in target_providers:
        snap = snapshots.get(pid) or {"provider": pid, "installed": False, "windows": []}
        if pid == "deepseek":
            row, m_val = _format_deepseek_item(snap, is_en=is_en)
        else:
            row, m_val = _format_cli_item(snap, display_mode=display_mode, is_en=is_en)
        all_rows.append(row)
        metric_map[pid] = m_val

    status_summary, status_badge = export_status_and_search_index(
        rows=all_rows,
        metric_map=metric_map,
        data_dir=data_dir,
        is_en=is_en,
    )

    if raw_json_mode:
        return _build_hud_telemetry(
            target_providers=target_providers,
            snapshots=snapshots,
            rows=all_rows,
            metric_map=metric_map,
            display_mode=display_mode,
            status_summary=status_summary,
            status_badge=status_badge,
            cache_state=cache_state,
            float_interval=float_interval,
        )

    visible_rows = all_rows
    if provider_filter:
        allowed_prefixes = tuple(f"aq-{p}" for p in provider_filter)
        visible_rows = [r for r in all_rows if str(r.get("id") or "").startswith(allowed_prefixes)]
    elif query:
        visible_rows = [
            r
            for r in all_rows
            if query in f"{r.get('title', '')} {r.get('subtitle', '')} {r.get('id', '')}".lower()
        ] or all_rows

    metrics = [
        {"key": "Codex CLI", "value": metric_map.get("codex", "—")},
        {"key": "Claude Code", "value": metric_map.get("claude", "—")},
        {"key": "AGY / DSH", "value": f"{metric_map.get('agy', '—')} | {metric_map.get('dsh', '—')}"},
        {"key": "DeepSeek Balance" if is_en else "DeepSeek 余额", "value": metric_map.get("deepseek", "—")},
    ]

    mode_desc = (
        ("Remaining %" if display_mode == "remaining" else "Used %")
        if is_en
        else ("剩余百分比口径" if display_mode == "remaining" else "已用百分比口径")
    )
    now_clock = dt.datetime.now().strftime("%H:%M:%S")
    subtitle = (
        f"Updated {now_clock} ({cache_state}) · {mode_desc} · Direct local CLI & Vault API"
        if is_en
        else f"更新于 {now_clock}（{cache_state}）· {mode_desc} · 本机 CLI 直连与加密密钥查询"
    )

    effect: dict[str, Any] = {
        "reloadSearchIndex": True,
        "statusSummary": status_summary,
        "statusBadge": status_badge,
    }
    if toast_msg:
        effect["toast"] = toast_msg
    if open_custom_hud:
        effect["openWindow"] = {
            "windowID": "hud",
            "title": "AI Quota Glass HUD",
            "htmlPath": "ui/widget.html",
            "width": 392,
            "height": 488,
            "minWidth": 320,
            "minHeight": 156,
            "resizable": True,
            "chrome": "frameless",
            "transparent": True,
            "pinOnTop": True,
        }
        effect["closeOverlay"] = True
    if open_floating:
        effect["openFloatingPanel"] = True
        effect["floatingPanelPinOnTop"] = True
        effect["floatingPanelIntervalSeconds"] = float_interval
        effect["floatingPanelArgs"] = ["--dashboard"]
        effect["closeOverlay"] = True
    if force_refresh and notify_on_refresh and not provider_filter:
        effect["notification"] = {
            "title": "AI Quota Radar" if is_en else "AI 额度雷达已刷新",
            "body": status_summary,
            "sound": False,
        }

    return {
        "schemaVersion": 2,
        "title": "AI Quota Radar · CLI & Balance" if is_en else "AI 额度雷达 · CLI 用量与余额面板",
        "subtitle": subtitle,
        "badge": status_badge if cache_state == "live" else cache_state.upper(),
        "effect": effect,
        "metrics": metrics,
        "items": visible_rows,
    }


def main() -> int:
    raw_stdin = sys.stdin.read()
    stdin_obj: dict[str, Any] = {}
    if raw_stdin.strip():
        try:
            stdin_obj = json.loads(raw_stdin)
        except json.JSONDecodeError:
            stdin_obj = {"query": raw_stdin.strip()}
    payload = dispatch(stdin_obj, sys.argv[1:])
    sys.stdout.write(json.dumps(payload, ensure_ascii=False) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

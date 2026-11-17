#!/usr/bin/env python3
"""DeepSeek official account balance client (`GET /user/balance`)."""

from __future__ import annotations

import json
import os
import re
import urllib.error
import urllib.request
from typing import Any


def parse_configured_keys(raw_cfg_key: str) -> list[tuple[str, str]]:
    entries: list[tuple[str, str]] = []
    for idx, chunk in enumerate(re.split(r"[,，\n]+", raw_cfg_key or "")):
        part = chunk.strip()
        if not part:
            continue
        if ":" in part and not part.startswith("sk-"):
            lbl, key_val = part.split(":", 1)
            if key_val.strip():
                entries.append((lbl.strip() or f"Account {idx + 1}", key_val.strip()))
        else:
            entries.append((f"Account {idx + 1}" if idx > 0 else "DeepSeek", part))
    return entries


def fetch_balance_once(url: str, api_key: str, timeout: float = 2.8) -> tuple[int, dict[str, Any] | None, str]:
    req = urllib.request.Request(
        url,
        headers={
            "Accept": "application/json",
            "Authorization": f"Bearer {api_key}",
            "User-Agent": "lumakey-ai-quota/1.0",
        },
        method="GET",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            status = getattr(resp, "status", 200)
            raw = resp.read(65_536).decode("utf-8", errors="replace")
            return (status, json.loads(raw) if raw.strip() else {}, "")
    except urllib.error.HTTPError as exc:
        return (exc.code, None, str(exc.reason))
    except Exception as exc:
        return (0, None, str(exc))


def query_deepseek_balances(raw_cfg_key: str) -> dict[str, Any]:
    key_entries = parse_configured_keys(raw_cfg_key)
    if not key_entries:
        return {
            "provider": "deepseek",
            "configured": False,
            "ok": False,
            "accounts": [],
            "error": "",
        }

    base_url = os.environ.get("LUMAKEY_DEEPSEEK_API_BASE", "https://api.deepseek.com").rstrip("/")
    accounts: list[dict[str, Any]] = []
    errors: list[str] = []

    for label, api_key in key_entries[:4]:
        code, body, err = fetch_balance_once(f"{base_url}/user/balance", api_key)
        if code == 200 and isinstance(body, dict):
            infos = body.get("balance_infos") if isinstance(body.get("balance_infos"), list) else []
            currencies: list[dict[str, Any]] = []
            for info in infos:
                if not isinstance(info, dict):
                    continue
                cur = str(info.get("currency") or "CNY").upper()
                sym = "¥" if cur == "CNY" else ("$" if cur == "USD" else f"{cur} ")
                try:
                    tot = float(info.get("total_balance") or 0.0)
                    granted = float(info.get("granted_balance") or 0.0)
                    topped = float(info.get("topped_up_balance") or 0.0)
                except (TypeError, ValueError):
                    tot, granted, topped = 0.0, 0.0, 0.0
                currencies.append(
                    {
                        "currency": cur,
                        "symbol": sym,
                        "total": tot,
                        "granted": granted,
                        "toppedUp": topped,
                    }
                )
            accounts.append(
                {
                    "label": label,
                    "isAvailable": bool(body.get("is_available", True)),
                    "currencies": currencies,
                }
            )
        else:
            errors.append(f"{label}: HTTP {code}" if code else f"{label}: {err[:36]}")

    return {
        "provider": "deepseek",
        "configured": True,
        "ok": len(accounts) > 0,
        "accounts": accounts,
        "error": "; ".join(errors),
    }

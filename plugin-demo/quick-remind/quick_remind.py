#!/usr/bin/env python3
"""Lumakey Official Store Plugin: Quick Remind (Natural Language Timers & Reminders Board)."""

from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
import re
import socket
import subprocess
import sys
from pathlib import Path
from typing import Any


def call_host_bridge(sock_path: str, token: str, capability: str, action: str, params: dict[str, Any]) -> dict[str, Any]:
    if not sock_path or not token:
        return {"ok": False, "error": "bridge_unavailable"}
    req = json.dumps({"token": token, "capability": capability, "action": action, "params": params}, ensure_ascii=False) + "\n"
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
            client.settimeout(3.0)
            client.connect(sock_path)
            client.sendall(req.encode("utf-8"))
            raw = client.recv(16384).decode("utf-8", errors="replace").strip()
        return json.loads(raw) if raw else {"ok": False}
    except Exception:  # noqa: BLE001
        return {"ok": False}


def parse_natural_reminder(raw: str, now: dt.datetime | None = None) -> tuple[dt.datetime, str, str] | None:
    """Parse phrases like '10m 喝水', '1.5h 开会', '明天 09:30 交周报', '18:30 拿快递 每天'.

    Returns `(due_dt, message, repeat_rule)`.
    """
    base = now or dt.datetime.now()
    text = raw.strip()
    for prefix in ("remind ", "timer ", "alarm ", "提醒 ", "提醒我 "):
        if text.lower().startswith(prefix):
            text = text[len(prefix):].strip()
            break
    if not text:
        return None

    repeat = "once"
    rep_patterns = [
        (r"\s*(?:每天|每日|daily|every\s*day)\s*$", "daily"),
        (r"\s*(?:工作日|weekdays?)\s*$", "weekdays"),
        (r"\s*(?:每周|weekly)\s*$", "weekly"),
    ]
    for pat, rule in rep_patterns:
        if re.search(pat, text, flags=re.IGNORECASE):
            repeat = rule
            text = re.sub(pat, "", text, flags=re.IGNORECASE).strip()
            break

    # 1. Relative duration: '10m 喝水', 'in 25 min stretch', '2小时后 看锅', '45s test'
    rel_m = re.match(
        r"^(?:in\s+)?(\d+(?:\.\d+)?)\s*(s|sec|secs|秒|m|min|mins|分钟|分|h|hr|hrs|hour|hours|小时)(?:后)?\s*(.*)$",
        text,
        flags=re.IGNORECASE,
    )
    if rel_m:
        val = float(rel_m.group(1))
        unit = rel_m.group(2).lower()
        body = rel_m.group(3).strip() or ("Time is up!" if unit.isascii() else "时间到啦")
        if unit in {"s", "sec", "secs", "秒"}:
            delta = dt.timedelta(seconds=max(5, int(val)))
        elif unit in {"h", "hr", "hrs", "hour", "hours", "小时"}:
            delta = dt.timedelta(seconds=int(val * 3600))
        else:
            delta = dt.timedelta(seconds=int(val * 60))
        return base + delta, body, repeat

    # 2. Clock time with optional day prefix: '明天 9:00 交周报', 'tomorrow 14:30 sync', '18:30 拿快递'
    clk_m = re.match(
        r"^(?:(今天|今晚|明天|后天|today|tonight|tomorrow)\s*)?(\d{1,2})[:：点时](\d{0,2})(?:分)?\s*(.*)$",
        text,
        flags=re.IGNORECASE,
    )
    if clk_m:
        day_word = (clk_m.group(1) or "").lower()
        hour = int(clk_m.group(2))
        minute = int(clk_m.group(3) or "0")
        body = clk_m.group(4).strip() or "Scheduled Reminder"
        if not (0 <= hour <= 23 and 0 <= minute <= 59):
            return None
        if day_word in {"今晚", "tonight"} and hour < 12:
            hour += 12
        day_offset = 0
        if day_word in {"明天", "tomorrow"}:
            day_offset = 1
        elif day_word == "后天":
            day_offset = 2

        target = base.replace(hour=hour, minute=minute, second=0, microsecond=0) + dt.timedelta(days=day_offset)
        if day_offset == 0 and target <= base:
            target += dt.timedelta(days=1)
        return target, body, repeat

    return None


def sync_to_apple_reminders(title: str, due_dt: dt.datetime, list_name: str = "") -> bool:
    script = """
    on run argv
        set remTitle to item 1 of argv
        set yr to (item 2 of argv) as integer
        set mo to (item 3 of argv) as integer
        set dy to (item 4 of argv) as integer
        set hr to (item 5 of argv) as integer
        set mn to (item 6 of argv) as integer
        set sc to (item 7 of argv) as integer
        set targetList to item 8 of argv

        set dueDate to current date
        set year of dueDate to yr
        set month of dueDate to mo
        set day of dueDate to dy
        set hours of dueDate to hr
        set minutes of dueDate to mn
        set seconds of dueDate to sc

        tell application "Reminders"
            if targetList is not "" and (exists list targetList) then
                tell list targetList to make new reminder with properties {name:remTitle, remind me date:dueDate}
            else
                tell default list to make new reminder with properties {name:remTitle, remind me date:dueDate}
            end if
        end tell
    end run
    """
    args = [
        "/usr/bin/osascript", "-e", script,
        title,
        str(due_dt.year), str(due_dt.month), str(due_dt.day),
        str(due_dt.hour), str(due_dt.minute), str(due_dt.second),
        list_name.strip(),
    ]
    try:
        res = subprocess.run(args, capture_output=True, text=True, timeout=3.5, check=False)
        return res.returncode == 0
    except Exception:  # noqa: BLE001
        return False


def load_reminders(data_dir: str) -> list[dict[str, Any]]:
    if not data_dir:
        return []
    p = Path(data_dir) / "reminders.json"
    if not p.exists():
        return []
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
        return data if isinstance(data, list) else []
    except Exception:  # noqa: BLE001
        return []


def save_reminders(data_dir: str, items: list[dict[str, Any]], is_en: bool) -> tuple[str, str]:
    open_items = [r for r in items if not r.get("done")]
    summary = f"{len(open_items)} active reminder(s)" if is_en else f"{len(open_items)} 条待办提醒"
    badge = str(len(open_items))
    if not data_dir:
        return summary, badge

    dd = Path(data_dir)
    dd.mkdir(parents=True, exist_ok=True)
    (dd / "reminders.json").write_text(json.dumps(items[:150], ensure_ascii=False, indent=2), encoding="utf-8")

    idx = []
    for r in open_items[:60]:
        rid = str(r.get("id") or "")
        idx.append({
            "id": f"rem-{rid}",
            "title": f"⏰ {r.get('title', '')}",
            "subtitle": f"Due {r.get('dueDisplay', '')} · {r.get('repeat', 'once')}",
            "keywords": ["remind", "提醒", str(r.get("title", "")).lower()],
            "icon": "bell.badge.fill",
            "commandArgs": ["--list"],
            "priority": 48,
        })
    (dd / "search-index.json").write_text(json.dumps({"items": idx}, ensure_ascii=False), encoding="utf-8")
    (dd / "status.json").write_text(json.dumps({"summary": summary, "badge": badge}, ensure_ascii=False), encoding="utf-8")
    return summary, badge


def advance_next_occurrence(due_iso: str, repeat: str, now: dt.datetime) -> dt.datetime:
    try:
        cur = dt.datetime.fromisoformat(due_iso)
    except ValueError:
        cur = now
    if repeat == "daily":
        nxt = cur + dt.timedelta(days=1)
        while nxt <= now:
            nxt += dt.timedelta(days=1)
        return nxt
    if repeat == "weekly":
        nxt = cur + dt.timedelta(days=7)
        while nxt <= now:
            nxt += dt.timedelta(days=7)
        return nxt
    if repeat == "weekdays":
        nxt = cur + dt.timedelta(days=1)
        while nxt <= now or nxt.weekday() >= 5:
            nxt += dt.timedelta(days=1)
        return nxt
    return cur


def format_relative(due_iso: str, now: dt.datetime, is_en: bool) -> tuple[str, bool]:
    try:
        due = dt.datetime.fromisoformat(due_iso)
    except ValueError:
        return ("Unknown", False)
    diff = int((due - now).total_seconds())
    stamp = due.strftime("%m-%d %H:%M")
    if diff <= 0:
        mins_ago = abs(diff) // 60
        label = (f"DUE ({mins_ago}m ago · {stamp})" if is_en else f"已到点（{mins_ago} 分钟前 · {stamp}）")
        return label, True
    if diff < 3600:
        mins = max(1, (diff + 59) // 60)
        return (f"in {mins} min ({stamp})" if is_en else f"{mins} 分钟后（{stamp}）"), False
    hours = diff // 3600
    rem_m = (diff % 3600) // 60
    return (f"in {hours}h {rem_m}m ({stamp})" if is_en else f"{hours} 小时 {rem_m} 分后（{stamp}）"), False


def execute_plugin(
    argv: list[str],
    stdin_obj: dict[str, Any],
    sock_path: str = "",
    token: str = "",
    now_override: dt.datetime | None = None,
    apple_sync_fn: Any = None,
) -> dict[str, Any]:
    now = now_override or dt.datetime.now()
    cfg = stdin_obj.get("config") if isinstance(stdin_obj.get("config"), dict) else {}
    query = str(stdin_obj.get("query") or "").strip()
    ctx = stdin_obj.get("context") if isinstance(stdin_obj.get("context"), dict) else {}
    if not query and str(ctx.get("text") or "").strip() and not argv:
        query = str(ctx["text"]).strip()

    locale = str(stdin_obj.get("locale") or os.environ.get("LUMAKEY_LOCALE") or "zh-Hans")
    is_en = locale.lower().startswith("en")
    data_dir = str(stdin_obj.get("dataDir") or os.environ.get("LUMAKEY_DATA_DIR") or "")
    sync_apple = str(cfg.get("syncAppleReminders", "true")).lower() != "false"
    apple_list = str(cfg.get("appleListName") or "")
    try:
        snooze_mins = max(1, int(float(cfg.get("snoozeMinutes") or 10)))
    except ValueError:
        snooze_mins = 10

    sync_cb = apple_sync_fn if apple_sync_fn is not None else sync_to_apple_reminders
    items_db = load_reminders(data_dir)
    flag = argv[0] if argv else ""
    toast: str | None = None

    if flag == "--pomo":
        query = "25m Pomodoro Focus Break" if is_en else "25m 番茄钟休息一下"
        flag = "--add"

    if flag == "--speak" and len(argv) >= 2:
        call_host_bridge(sock_path, token, "audio", "speak", {"text": argv[1], "language": "en-US" if is_en else "zh-CN"})
        toast = "Reading reminder aloud…" if is_en else "正在语音播报提醒…"

    elif flag == "--done" and len(argv) >= 2:
        rid = argv[1]
        for r in items_db:
            if str(r.get("id")) == rid:
                rep = str(r.get("repeat") or "once")
                if rep != "once" and not r.get("done"):
                    nxt = advance_next_occurrence(str(r.get("dueISO") or ""), rep, now)
                    r["dueISO"] = nxt.isoformat()
                    r["dueDisplay"] = nxt.strftime("%Y-%m-%d %H:%M")
                    toast = f"Scheduled next ({rep}): {r['dueDisplay']}" if is_en else f"已推进至下一周期 ({rep})：{r['dueDisplay']}"
                else:
                    r["done"] = not bool(r.get("done"))
                    toast = "Completed reminder" if is_en else ("已标记完成" if r["done"] else "已恢复为待办")
                break

    elif flag == "--snooze" and len(argv) >= 2:
        rid = argv[1]
        for r in items_db:
            if str(r.get("id")) == rid:
                nxt = now + dt.timedelta(minutes=snooze_mins)
                r["dueISO"] = nxt.isoformat()
                r["dueDisplay"] = nxt.strftime("%Y-%m-%d %H:%M")
                r["done"] = False
                if sync_apple:
                    sync_cb(str(r.get("title") or "Reminder"), nxt, apple_list)
                toast = f"Snoozed +{snooze_mins}m" if is_en else f"已推迟 {snooze_mins} 分钟（{nxt.strftime('%H:%M')}）"
                break

    elif flag == "--delete" and len(argv) >= 2:
        items_db = [r for r in items_db if str(r.get("id")) != argv[1]]
        toast = "Deleted reminder" if is_en else "已删除该条提醒"

    elif flag == "--clear-done":
        items_db = [r for r in items_db if not r.get("done")]
        toast = "Cleared completed reminders" if is_en else "已清理全部已完成提醒"

    elif flag in {"", "--add"} and query:
        parsed = parse_natural_reminder(query, now=now)
        if parsed is not None:
            due_dt, body, rep = parsed
            rid = hashlib.sha1(f"{due_dt.isoformat()}:{body}:{len(items_db)}".encode("utf-8")).hexdigest()[:8]
            synced_ok = sync_cb(body, due_dt, apple_list) if sync_apple else False
            items_db.insert(0, {
                "id": rid,
                "title": body,
                "dueISO": due_dt.isoformat(),
                "dueDisplay": due_dt.strftime("%Y-%m-%d %H:%M"),
                "repeat": rep,
                "done": False,
                "appleSynced": synced_ok,
            })
            toast = (
                f"Reminder set for {due_dt.strftime('%H:%M')}" + (" (Synced to Reminders.app)" if synced_ok else "")
                if is_en
                else f"已设定 {due_dt.strftime('%H:%M')} 提醒：{body}" + ("（已同步系统提醒事项）" if synced_ok else "")
            )
            query = ""

    summary, badge = save_reminders(data_dir, items_db, is_en)
    ordered = sorted(items_db, key=lambda r: (1 if r.get("done") else 0, str(r.get("dueISO") or "")))
    filter_q = query.lower() if flag == "--list" else ""
    if filter_q:
        ordered = [r for r in ordered if filter_q in str(r.get("title", "")).lower()]

    card_items: list[dict[str, Any]] = [
        {
            "id": "quick-pomo",
            "title": "Start 25-Min Pomodoro Focus Timer" if is_en else "🍅 一键开启 25 分钟番茄钟专注提醒",
            "subtitle": "Or type '10m drink water', '18:30 package', 'tomorrow 09:00 report' in search bar"
            if is_en
            else "也可直接在上方输入「10m 喝水」「18:30 拿快递」「明天 9:00 周报 每天」回车创建",
            "icon": "timer",
            "badge": "25 MIN",
            "commandArgs": ["--pomo"],
        }
    ]

    due_count = 0
    for r in ordered[:25]:
        rid = str(r.get("id") or "")
        done = bool(r.get("done"))
        rel_text, is_due = format_relative(str(r.get("dueISO") or ""), now, is_en)
        if is_due and not done:
            due_count += 1
        rep = str(r.get("repeat") or "once")
        rep_tag = "" if rep == "once" else f" · 🔁 {rep}"
        sync_tag = " ·  Reminders" if r.get("appleSynced") else ""
        card_items.append({
            "id": f"rem-{rid}",
            "title": ("✓ " if done else ("🔔 " if is_due else "⏰ ")) + str(r.get("title") or ""),
            "subtitle": ("Completed · " + str(r.get("dueDisplay", "")) if done else f"{rel_text}{rep_tag}{sync_tag}"),
            "icon": "checkmark.circle.fill" if done else ("bell.and.waves.left.and.right.fill" if is_due else "clock.fill"),
            "badge": "DONE" if done else ("DUE!" if is_due else rep.upper()),
            "copyText": str(r.get("title") or ""),
            "actions": [
                {
                    "id": f"done-{rid}",
                    "label": ("Reopen" if done else "Done") if is_en else ("恢复" if done else "知道了"),
                    "style": "primary",
                    "commandArgs": ["--done", rid],
                },
                {
                    "id": f"snz-{rid}",
                    "label": f"+{snooze_mins}m" if is_en else f"推迟{snooze_mins}分",
                    "commandArgs": ["--snooze", rid],
                },
                {
                    "id": f"spk-{rid}",
                    "label": "Speak" if is_en else "朗读",
                    "commandArgs": ["--speak", str(r.get("title") or "")],
                },
                {
                    "id": f"del-{rid}",
                    "label": "Delete" if is_en else "删除",
                    "style": "destructive",
                    "commandArgs": ["--delete", rid],
                },
            ],
        })

    if any(r.get("done") for r in items_db):
        card_items.append({
            "id": "clear-done-row",
            "title": "Clear Completed Reminders" if is_en else "清理已完成的提醒记录",
            "subtitle": "Keep your reminder board tidy" if is_en else "一键移除已完成的旧提醒",
            "icon": "trash",
            "badge": "CLEAN",
            "commandArgs": ["--clear-done"],
        })

    open_total = sum(1 for r in items_db if not r.get("done"))
    effect: dict[str, Any] = {"reloadSearchIndex": True, "statusSummary": summary, "statusBadge": badge}
    if toast:
        effect["toast"] = toast

    return {
        "schemaVersion": 2,
        "title": "Quick Remind · Timers & Reminders" if is_en else "闪电提醒 · 自然语言倒计时与提醒看板",
        "subtitle": summary,
        "badge": f"{due_count} DUE" if due_count > 0 else f"{open_total} ACTIVE",
        "effect": effect,
        "metrics": [
            {"key": "Active" if is_en else "待触发", "value": str(open_total)},
            {"key": "Due Now" if is_en else "已到点", "value": str(due_count)},
            {"key": "Snooze" if is_en else "默认推迟", "value": f"{snooze_mins} min"},
        ],
        "items": card_items,
    }


def main() -> int:
    raw = sys.stdin.read()
    stdin_obj = json.loads(raw) if raw.strip().startswith("{") else {}
    out = execute_plugin(
        sys.argv[1:],
        stdin_obj,
        sock_path=os.environ.get("LUMAKEY_BRIDGE_SOCK", ""),
        token=os.environ.get("LUMAKEY_BRIDGE_TOKEN", ""),
    )
    sys.stdout.write(json.dumps(out, ensure_ascii=False) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

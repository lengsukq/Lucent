#!/usr/bin/env python3
"""Lumakey Official Store Plugin: Screen Shield (Clean Screen, Do-Not-Touch & BRB Status Overlay)."""

from __future__ import annotations

import json
import os
import socket
import sys
from pathlib import Path
from typing import Any


def call_host_bridge(sock_path: str, token: str, action: str, params: dict[str, Any]) -> dict[str, Any]:
    if not sock_path or not token:
        return {"ok": False, "error": "bridge_unavailable", "message": "Host Bridge socket not injected"}
    req = json.dumps({"token": token, "capability": "systemControl", "action": action, "params": params}, ensure_ascii=False) + "\n"
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
            client.settimeout(3.5)
            client.connect(sock_path)
            client.sendall(req.encode("utf-8"))
            raw = client.recv(16384).decode("utf-8", errors="replace").strip()
        return json.loads(raw) if raw else {"ok": False, "message": "Empty Host Bridge response"}
    except Exception as exc:  # noqa: BLE001
        return {"ok": False, "error": "socket_error", "message": str(exc)}


def _bool_cfg(cfg: dict[str, Any], key: str, default: bool) -> bool:
    raw = str(cfg.get(key, "true" if default else "false")).strip().lower()
    return raw not in {"false", "0", "no", "off"}


def execute_plugin(
    argv: list[str],
    stdin_obj: dict[str, Any],
    sock_path: str = "",
    token: str = "",
    bridge_fn: Any = None,
) -> dict[str, Any]:
    cfg = stdin_obj.get("config") if isinstance(stdin_obj.get("config"), dict) else {}
    query = str(stdin_obj.get("query") or "").strip()
    locale = str(stdin_obj.get("locale") or os.environ.get("LUMAKEY_LOCALE") or "zh-Hans")
    is_en = locale.lower().startswith("en")
    data_dir = str(stdin_obj.get("dataDir") or os.environ.get("LUMAKEY_DATA_DIR") or "")

    invoke = bridge_fn if bridge_fn is not None else (lambda act, prm: call_host_bridge(sock_path, token, act, prm))

    block_input = _bool_cfg(cfg, "blockInput", True)
    keep_awake = _bool_cfg(cfg, "keepAwake", True)
    mute_audio = _bool_cfg(cfg, "muteAudio", False)
    try:
        hold_secs = max(1.0, min(5.0, float(cfg.get("holdSeconds") or 2.0)))
    except ValueError:
        hold_secs = 2.0

    custom_icon = str(cfg.get("customIcon") or "🐱").strip() or "🐱"
    custom_title = str(cfg.get("customTitle") or ("Do Not Touch Keyboard" if is_en else "请勿触碰键盘")).strip()
    custom_sub = str(cfg.get("customSubtitle") or ("Background task in progress" if is_en else "后台任务执行中，稍后即回")).strip()

    flag = argv[0] if argv else ""
    if flag == "--dismiss":
        resp = invoke("clearStatusScreen", {})
        if resp.get("ok"):
            return {
                "schemaVersion": 2,
                "title": "Status Screen Dismissed" if is_en else "已退出状态屏保护",
                "badge": "IDLE",
                "effect": {"closeOverlay": True, "toast": "Status screen closed" if is_en else "状态屏已关闭"},
            }

    target_preset: str | None = None
    override_title = ""
    if flag == "--preset" and len(argv) >= 2:
        target_preset = argv[1].lower()
    elif flag == "--custom":
        target_preset = "custom"
        override_title = query or custom_title
    elif query.lower() in {"clean", "清洁", "擦屏幕", "擦键盘"}:
        target_preset = "clean"
    elif query.lower() in {"busy", "勿碰", "请勿触碰", "跑任务"}:
        target_preset = "busy"
    elif query.lower() in {"brb", "马上回来", "暂离"}:
        target_preset = "brb"
    elif query:
        target_preset = "custom"
        override_title = query

    if target_preset is not None:
        params: dict[str, Any] = {
            "active": True,
            "preset": target_preset,
            "blockInput": block_input,
            "keepAwake": keep_awake,
            "muteAudio": mute_audio,
            "holdSeconds": hold_secs,
            "delaySeconds": 0.14,
        }
        if target_preset == "custom":
            params["icon"] = custom_icon
            params["title"] = override_title or custom_title
            params["subtitle"] = custom_sub
        resp = invoke("setStatusScreen", params)
        if not resp.get("ok"):
            return {
                "schemaVersion": 2,
                "title": "Grant 'systemControl' Permission First" if is_en else "请先在插件设置页授权「系统控制与状态屏」",
                "subtitle": str(resp.get("message") or ("Open Screen Shield settings to enable Host Bridge" if is_en else "授权 systemControl 后即可一键启动全屏防误触状态屏")),
                "badge": "GRANT",
                "items": [
                    {
                        "id": "open-shield-settings",
                        "title": "Open Screen Shield Settings →" if is_en else "打开状态屏插件设置并授权 systemControl →",
                        "subtitle": "lumakey://settings/plugin/screen-shield",
                        "icon": "lock.shield.fill",
                        "badge": "SETTINGS",
                        "openURL": "lumakey://settings/plugin/screen-shield",
                    }
                ],
            }
        return {
            "schemaVersion": 2,
            "title": "Activating Status Screen…" if is_en else "正在开启全屏状态屏…",
            "subtitle": f"Hold Esc for {int(hold_secs)}s to exit" if is_en else f"按住 Esc {int(hold_secs)} 秒即可安全退出",
            "badge": "ACTIVE",
            "effect": {
                "closeOverlay": True,
                "statusSummary": f"Shield ready (Esc {int(hold_secs)}s)",
                "statusBadge": "READY",
            },
        }

    st = invoke("status", {})
    bridge_ok = bool(st.get("ok"))
    sd = st.get("data") if bridge_ok and isinstance(st.get("data"), dict) else {}
    ax_ok = bool(sd.get("accessibilityTrusted", True))

    summary = f"Hold Esc {int(hold_secs)}s · Input Block {'ON' if block_input else 'OFF'}" if is_en else f"长按 Esc {int(hold_secs)} 秒退出 · 键鼠拦截{'开启' if block_input else '关闭'}"
    if data_dir:
        Path(data_dir).mkdir(parents=True, exist_ok=True)
        (Path(data_dir) / "status.json").write_text(json.dumps({"summary": summary, "badge": "READY"}, ensure_ascii=False), encoding="utf-8")

    items: list[dict[str, Any]] = []
    if not bridge_ok:
        items.append({
            "id": "grant-row",
            "title": "Grant 'systemControl' Bridge Permission First →" if is_en else "首次使用请点此授权「系统控制与状态屏 (systemControl)」→",
            "subtitle": "Required to display fullscreen status overlay & intercept touches" if is_en else "开启后即可一键盖住所有屏幕并拦截键盘误触",
            "icon": "lock.open.display",
            "badge": "SETUP",
            "openURL": "lumakey://settings/plugin/screen-shield",
        })

    items.extend([
        {
            "id": "p-clean",
            "title": "🧹 Cleaning Screen & Keyboard" if is_en else "🧹 清洁屏幕与键盘（防擦拭/宠物误触）",
            "subtitle": "Covers all displays & blocks accidental key/scroll events" if is_en else "盖住所有屏幕并临时拦下按键与滚轮，放心擦键盘",
            "icon": "sparkles",
            "badge": "CLEAN",
            "commandArgs": ["--preset", "clean"],
        },
        {
            "id": "p-busy",
            "title": "⚡ Task Running · Do Not Touch" if is_en else "⚡ 任务运行中 · 请勿触碰（跑编译/下载/备份）",
            "subtitle": "Keeps Mac awake while displaying a clear do-not-touch banner" if is_en else "联动开启防休眠常亮并展示勿碰告示，防止他人误操作",
            "icon": "bolt.shield.fill",
            "badge": "BUSY",
            "commandArgs": ["--preset", "busy"],
        },
        {
            "id": "p-brb",
            "title": "☕ Be Right Back" if is_en else "☕ 马上回来（暂时离开座位）",
            "subtitle": "Polite fullscreen away notice across all monitors" if is_en else "离开座位倒水或取快递时一键盖上暂离告示",
            "icon": "cup.and.saucer.fill",
            "badge": "BRB",
            "commandArgs": ["--preset", "brb"],
        },
        {
            "id": "p-custom",
            "title": f"{custom_icon} Custom: {custom_title}",
            "subtitle": (f"{custom_sub} · Or type any message in search bar and press Return" if is_en else f"{custom_sub} · 也可直接在搜索框输入临时告示语回车开启"),
            "icon": "text.bubble.fill",
            "badge": "CUSTOM",
            "commandArgs": ["--custom"],
        },
    ])

    return {
        "schemaVersion": 2,
        "title": "Screen Shield · Status Screen" if is_en else "状态屏 · 清洁屏幕与暂离防误触",
        "subtitle": summary + ("" if ax_ok else (" · Grant Accessibility for global key block" if is_en else " · 建议授予辅助功能以拦截全局按键")),
        "badge": "SHIELD",
        "metrics": [
            {"key": "Exit Key" if is_en else "退出方式", "value": f"Hold Esc {int(hold_secs)}s"},
            {"key": "Key Block" if is_en else "键鼠拦截", "value": "ON" if block_input else "OFF"},
            {"key": "Keep Awake" if is_en else "防休眠联动", "value": "ON" if keep_awake else "OFF"},
        ],
        "items": items,
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

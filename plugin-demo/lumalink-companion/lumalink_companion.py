#!/usr/bin/env python3
"""Lumakey Flagship Store Plugin: LumaLink Remote Companion v2.0.

Provides a complete, self-contained remote-control console directly inside the
Lumakey launcher without requiring any built-in sidebar page:
- Start/stop Bonjour LAN listener & VideoToolbox RDP sidecar
- Render & pop up crisp 380x380 pairing QR code window (`lumakey://image`)
- Rotate CSPRNG 6-digit pairing PIN (protected by 5-strike brute-force lockout)
- Switch Mac HiDPI display resolutions & restore native display modes inline
- Toggle physical screen privacy curtain & idle sleep prevention (Caffeine)
- Inspect paired phones & revoke individual encrypted tokens with confirmation
"""

from __future__ import annotations

import datetime as dt
import json
import os
import socket
import sys
import urllib.parse
from pathlib import Path
from typing import Any


def parse_cli_and_query(argv: list[str], query: str) -> tuple[str, str, dict[str, Any]]:
    """Return `(view_mode, bridge_action, bridge_params)`."""
    q = query.strip().lower()
    flag = argv[0] if argv else ""

    if flag == "--toggle":
        return ("main", "toggle", {"renderQR": True})
    if flag == "--toggle-rdp":
        return ("main", "toggleRdp", {"renderQR": True})
    if flag == "--regen-pin":
        return ("main", "regeneratePin", {"renderQR": True})
    if flag == "--curtain":
        return ("main", "toggleCurtain", {"renderQR": True})
    if flag == "--caffeine":
        return ("main", "toggleCaffeine", {"renderQR": True})
    if flag == "--qr":
        return ("qr_popup", "setEnabled", {"enabled": True, "renderQR": True})
    if flag == "--displays":
        return ("displays", "status", {"includeDisplays": True, "renderQR": False})
    if flag == "--set-mode" and len(argv) >= 3:
        try:
            disp_id = int(argv[1])
        except ValueError:
            disp_id = 0
        return ("displays", "setDisplayMode", {"displayID": disp_id, "modeKey": argv[2], "includeDisplays": True})
    if flag == "--restore-displays":
        return ("displays", "restoreDisplays", {"includeDisplays": True})
    if flag == "--devices":
        return ("devices", "status", {"renderQR": False})
    if flag == "--revoke" and len(argv) >= 2:
        return ("devices", "revokeDevice", {"deviceId": argv[1], "renderQR": False})

    if q in {"on", "start", "enable", "开启", "启动"}:
        return ("main", "setEnabled", {"enabled": True, "renderQR": True})
    if q in {"off", "stop", "disable", "关闭", "停用"}:
        return ("main", "setEnabled", {"enabled": False, "renderQR": False})
    if q in {"qr", "二维码", "扫码"}:
        return ("qr_popup", "setEnabled", {"enabled": True, "renderQR": True})
    if q in {"display", "displays", "hidpi", "分辨率", "屏幕"}:
        return ("displays", "status", {"includeDisplays": True, "renderQR": False})
    if q in {"device", "devices", "phone", "手机", "配对", "设备"}:
        return ("devices", "status", {"renderQR": False})
    if q in {"curtain", "黑屏", "幕布", "防窥"}:
        return ("main", "toggleCurtain", {"renderQR": True})
    if q in {"caffeine", "awake", "防休眠", "常亮"}:
        return ("main", "toggleCaffeine", {"renderQR": True})
    return ("main", "status", {"renderQR": True})


def call_host_bridge(sock_path: str, token: str, action: str, params: dict[str, Any]) -> dict[str, Any]:
    if not sock_path or not token:
        return {"ok": False, "error": "bridge_unavailable", "message": "Host Bridge socket not injected"}

    req_line = json.dumps(
        {"token": token, "capability": "lumaLinkStatus", "action": action, "params": params},
        ensure_ascii=False,
    ) + "\n"

    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
            client.settimeout(4.0)
            client.connect(sock_path)
            client.sendall(req_line.encode("utf-8"))
            chunks: list[bytes] = []
            while True:
                buf = client.recv(16384)
                if not buf:
                    break
                chunks.append(buf)
                if b"\n" in buf:
                    break
        raw = b"".join(chunks).decode("utf-8", errors="replace").strip()
        return json.loads(raw) if raw else {"ok": False, "message": "Empty Host Bridge response"}
    except Exception as exc:  # noqa: BLE001
        return {"ok": False, "error": "socket_error", "message": str(exc)}


def write_status_cache(data_dir: str, summary: str, badge: str) -> None:
    if not data_dir:
        return
    try:
        p = Path(data_dir)
        p.mkdir(parents=True, exist_ok=True)
        (p / "status.json").write_text(
            json.dumps({"summary": summary, "badge": badge}, ensure_ascii=False),
            encoding="utf-8",
        )
    except OSError:
        pass


def _format_paired_time(epoch_sec: float, is_en: bool) -> str:
    if epoch_sec <= 0:
        return "Unknown time" if is_en else "未知时间"
    stamp = dt.datetime.fromtimestamp(epoch_sec).strftime("%Y-%m-%d %H:%M")
    return f"Paired at {stamp}" if is_en else f"配对于 {stamp}"


def _build_displays_card(d: dict[str, Any], action_triggered: str, is_en: bool) -> dict[str, Any]:
    displays = d.get("displays") or []
    modified = bool(d.get("hasModifiedDisplays"))
    items: list[dict[str, Any]] = [
        {
            "id": "nav-back-main",
            "title": "← Back to LumaLink Console" if is_en else "← 返回流光随行主控台",
            "subtitle": "Return to service, QR pairing, privacy curtain & RDP controls"
            if is_en
            else "返回远控开关、扫码配对、隐私幕布与 RDP 主视图",
            "icon": "chevron.backward.circle",
            "badge": "BACK",
            "commandArgs": [],
        }
    ]
    if modified:
        items.append(
            {
                "id": "restore-native-displays",
                "title": "Restore Original Display Resolutions" if is_en else "一键恢复切换前的原生分辨率",
                "subtitle": "Revert all displays modified during remote session"
                if is_en
                else "还原远控期间调整过的全部显示器模式",
                "icon": "arrow.uturn.backward.circle.fill",
                "badge": "RESTORE",
                "commandArgs": ["--restore-displays"],
            }
        )

    for disp in displays:
        disp_id = disp.get("displayID", 0)
        disp_name = disp.get("name") or f"Display {disp_id}"
        for m in disp.get("modes") or []:
            mode_key = m.get("modeKey") or ""
            is_cur = bool(m.get("isCurrent"))
            label = m.get("label") or mode_key
            hz = m.get("refreshHz") or 60
            items.append(
                {
                    "id": f"mode-{disp_id}-{mode_key}",
                    "title": f"{disp_name} · {label}",
                    "subtitle": f"{mode_key} · {hz}Hz",
                    "icon": "checkmark.circle.fill" if is_cur else "display",
                    "badge": "CURRENT" if is_cur else ("HiDPI" if m.get("isHiDPI") else "STD"),
                    "commandArgs": [] if is_cur else ["--set-mode", str(disp_id), mode_key],
                }
            )

    toast = None
    if action_triggered == "setDisplayMode":
        toast = "Display resolution updated" if is_en else "已切换显示器分辨率"
    elif action_triggered == "restoreDisplays":
        toast = "Original display modes restored" if is_en else "已恢复原生显示分辨率"

    payload: dict[str, Any] = {
        "schemaVersion": 2,
        "title": "LumaLink · Display Resolution Switcher" if is_en else "流光随行 · 多屏 HiDPI 分辨率切换",
        "subtitle": f"{len(displays)} active display(s)" if is_en else f"检测到 {len(displays)} 台活跃显示器 · 点击条目立即切换",
        "badge": "DISPLAY",
        "items": items,
    }
    if toast:
        payload["effect"] = {"toast": toast}
    return payload


def _build_devices_card(d: dict[str, Any], action_triggered: str, is_en: bool) -> dict[str, Any]:
    devices = d.get("pairedDevices") or []
    items: list[dict[str, Any]] = [
        {
            "id": "nav-back-main",
            "title": "← Back to LumaLink Console" if is_en else "← 返回流光随行主控台",
            "subtitle": "Return to main LumaLink remote control overview"
            if is_en
            else "返回远控服务状态与快捷控制中心",
            "icon": "chevron.backward.circle",
            "badge": "BACK",
            "commandArgs": [],
        }
    ]

    if not devices:
        items.append(
            {
                "id": "empty-devices",
                "title": "No Paired Phones Yet" if is_en else "当前暂无已配对手机",
                "subtitle": "Enable LumaLink and scan the pairing QR code from your phone"
                if is_en
                else "启用远控服务后，在手机端扫码或输入 6 位配对码即可完成加密绑定",
                "icon": "iphone.slash",
                "badge": "EMPTY",
                "commandArgs": ["--qr"],
            }
        )
    else:
        for dev in devices:
            dev_id = str(dev.get("id") or "")
            dev_name = str(dev.get("name") or ("Mobile Device" if is_en else "移动设备"))
            paired_at = float(dev.get("pairedAt") or 0)
            items.append(
                {
                    "id": f"dev-{dev_id}",
                    "title": dev_name,
                    "subtitle": f"{_format_paired_time(paired_at, is_en)} · Token Vault Sealed",
                    "icon": "iphone.gen3",
                    "badge": "PAIRED",
                    "actions": [
                        {
                            "id": f"revoke-{dev_id}",
                            "label": "Revoke" if is_en else "解绑吊销",
                            "style": "destructive",
                            "commandArgs": ["--revoke", dev_id],
                            "confirmMessage": (
                                f"Revoke paired phone '{dev_name}' and delete its encrypted token?"
                                if is_en
                                else f"确认解绑「{dev_name}」并立即从保险箱吊销其配对凭证吗？"
                            ),
                        }
                    ],
                }
            )

    payload: dict[str, Any] = {
        "schemaVersion": 2,
        "title": "LumaLink · Paired Devices" if is_en else "流光随行 · 已配对手机管理",
        "subtitle": (
            f"{len(devices)} authorized device(s) · Tokens encrypted in LocalSecretVault"
            if is_en
            else f"共 {len(devices)} 台授权设备 · 令牌由本机 AES-GCM 保险箱密封"
        ),
        "badge": f"{len(devices)} DEV",
        "items": items,
    }
    if action_triggered == "revokeDevice":
        payload["effect"] = {"toast": "Paired device revoked" if is_en else "已吊销该设备的配对凭证"}
    return payload


def build_card_payload(
    resp: dict[str, Any],
    view_mode: str = "main",
    action_triggered: str = "status",
    locale: str = "zh-Hans",
    show_pair_uri: bool = True,
    pin_qr_on_top: bool = True,
) -> dict[str, Any]:
    is_en = locale.lower().startswith("en")
    if not resp.get("ok"):
        msg = resp.get("message") or (
            "Grant 'lumaLinkStatus' in Plugin Settings first."
            if is_en
            else "请先在插件独立设置页开启「LumaLink 状态」宿主桥接授权。"
        )
        return {
            "schemaVersion": 2,
            "title": "LumaLink · Authorization Required" if is_en else "流光随行 · 待开启宿主桥接授权",
            "subtitle": msg,
            "badge": "AUTH",
            "items": [
                {
                    "id": "grant-cap",
                    "title": "Open Plugin Settings to Grant lumaLinkStatus"
                    if is_en
                    else "打开插件设置开启 lumaLinkStatus 授权",
                    "subtitle": "Default least-privilege; once granted, manage all LumaLink features inline"
                    if is_en
                    else "默认最小权限关闭，授权后即可在浮窗内直接扫码配对、切分辨率与管理设备",
                    "icon": "lock.shield",
                    "badge": "GRANT",
                    "openURL": "lumakey://settings/plugin/lumalink-companion",
                }
            ],
        }

    d = resp.get("data") or {}
    if view_mode == "displays":
        return _build_displays_card(d, action_triggered=action_triggered, is_en=is_en)
    if view_mode == "devices":
        return _build_devices_card(d, action_triggered=action_triggered, is_en=is_en)

    enabled = bool(d.get("enabled"))
    listening = bool(d.get("isListening"))
    ip = d.get("localIPv4") or "127.0.0.1"
    port = int(d.get("port") or d.get("preferredPort") or 59480)
    pin = str(d.get("pairingPin") or "------")
    pair_uri = str(d.get("pairURI") or "")
    qr_path = str(d.get("qrImagePath") or "")
    connected = int(d.get("connectedDeviceCount") or 0)
    paired = int(d.get("pairedDeviceCount") or 0)
    rdp_on = bool(d.get("rdpEnabled"))
    rdp_running = bool(d.get("rdpRunning"))
    rdp_port = int(d.get("rdpPort") or 3389)
    curtain_on = bool(d.get("curtainActive"))
    caffeine_on = bool(d.get("caffeineActive"))
    ax_ok = bool(d.get("accessibilityTrusted", True))
    sr_ok = bool(d.get("screenRecordingTrusted", True))

    if enabled and listening:
        summary = f"Listening {ip}:{port} · {connected} active" if is_en else f"监听 {ip}:{port} · 在线 {connected} 台"
    elif enabled:
        summary = "Starting Bonjour listener…" if is_en else "正在启动局域网监听…"
    else:
        summary = "Stopped · Zero resident ports" if is_en else "已停用 · 零监听零端口占用"

    items: list[dict[str, Any]] = [
        {
            "id": "toggle-service",
            "title": ("Stop LumaLink Remote Service" if enabled else "Start LumaLink Remote Service")
            if is_en
            else ("停用流光随行远控服务" if enabled else "启用流光随行远控服务"),
            "subtitle": summary,
            "icon": "pause.circle" if enabled else "play.circle.fill",
            "badge": "ON" if enabled else "OFF",
            "commandArgs": ["--toggle"],
        }
    ]

    if enabled and show_pair_uri:
        uri_val = pair_uri or f"lumalink://pair?host={ip}&port={port}&pin={pin}"
        pin_item: dict[str, Any] = {
            "id": "pair-pin-qr",
            "title": (f"Pairing PIN: {pin}" if is_en else f"6 位动态防爆破配对码：{pin}"),
            "subtitle": uri_val,
            "icon": "qrcode.viewfinder",
            "badge": "PIN",
            "copyText": uri_val,
            "actions": [
                {
                    "id": "rotate-pin",
                    "label": "Rotate PIN" if is_en else "轮换配对码",
                    "commandArgs": ["--regen-pin"],
                }
            ],
        }
        if qr_path:
            encoded_qr = urllib.parse.quote(qr_path, safe="/")
            pin_flag = "1" if pin_qr_on_top else "0"
            pin_item["openURL"] = f"lumakey://image?path={encoded_qr}&pin={pin_flag}"
        items.append(pin_item)

    items.extend(
        [
            {
                "id": "switch-displays",
                "title": "Switch HiDPI Display Resolution →" if is_en else "切换多屏 HiDPI 分辨率与恢复 →",
                "subtitle": "Pick mobile-friendly HiDPI modes or restore native resolution"
                if is_en
                else "选择适合手机屏幕比例的 HiDPI 分辨率或一键还原原生模式",
                "icon": "display",
                "badge": "RESTORE" if d.get("hasModifiedDisplays") else "HiDPI",
                "commandArgs": ["--displays"],
            },
            {
                "id": "privacy-guards",
                "title": (
                    f"Privacy Curtain: {'ON' if curtain_on else 'OFF'} · Caffeine: {'ON' if caffeine_on else 'OFF'}"
                    if is_en
                    else f"物理防窥黑屏：{'已开启' if curtain_on else '关闭'} · 防休眠：{'已开启' if caffeine_on else '关闭'}"
                ),
                "subtitle": "Blank physical Mac screen or keep system awake during remote control"
                if is_en
                else "远控期间遮蔽物理显示器防窥，或阻止 Mac 空闲休眠断联",
                "icon": "eye.slash.fill" if curtain_on else "lock.display",
                "badge": "GUARD",
                "actions": [
                    {
                        "id": "act-curtain",
                        "label": ("Curtain Off" if curtain_on else "Curtain On") if is_en else ("关闭黑屏" if curtain_on else "开启黑屏"),
                        "commandArgs": ["--curtain"],
                    },
                    {
                        "id": "act-caffeine",
                        "label": ("Allow Sleep" if caffeine_on else "Keep Awake") if is_en else ("关闭防休眠" if caffeine_on else "开启防休眠"),
                        "commandArgs": ["--caffeine"],
                    },
                ],
            },
            {
                "id": "toggle-rdp",
                "title": ("Disable VideoToolbox RDP Engine" if rdp_on else "Enable VideoToolbox RDP Engine")
                if is_en
                else ("关闭 RDP VideoToolbox 硬件加速" if rdp_on else "开启 RDP VideoToolbox 硬件加速"),
                "subtitle": (
                    f"Port {rdp_port} · Sidecar: {'Running' if rdp_running else 'Idle'} · TCC AX:{'OK' if ax_ok else 'Missing'} SR:{'OK' if sr_ok else 'Missing'}"
                    if is_en
                    else f"端口 {rdp_port} · 侧车：{'运行中' if rdp_running else '待机'} · 辅助功能:{'已授' if ax_ok else '未授'} 录屏:{'已授' if sr_ok else '未授'}"
                ),
                "icon": "bolt.horizontal.circle",
                "badge": "RDP ON" if rdp_on else "RDP OFF",
                "commandArgs": ["--toggle-rdp"],
            },
            {
                "id": "manage-devices",
                "title": (f"Manage Paired Phones ({paired}) →" if is_en else f"管理已配对手机与解绑 ({paired} 台) →"),
                "subtitle": "Inspect authorized phones and revoke individual Vault tokens"
                if is_en
                else "查看已授权手机列表，支持二次确认吊销单台设备加密凭证",
                "icon": "iphone.gen3.radiowaves.left.and.right",
                "badge": f"{paired} DEV",
                "commandArgs": ["--devices"],
            },
        ]
    )

    effect: dict[str, Any] = {"statusSummary": summary, "statusBadge": "ON" if enabled else "OFF"}
    if view_mode == "qr_popup" and qr_path:
        if pin_qr_on_top:
            effect["pinImagePath"] = qr_path
        else:
            effect["openImagePath"] = qr_path
        effect["toast"] = "Pairing QR code ready" if is_en else "已生成并弹出扫码配对二维码"

    return {
        "schemaVersion": 2,
        "title": "LumaLink Remote Companion" if is_en else "流光随行 · LumaLink 远控控制台",
        "subtitle": summary,
        "badge": "ONLINE" if enabled else "IDLE",
        "effect": effect,
        "metrics": [
            {"key": "Service" if is_en else "服务状态", "value": ("Running" if enabled else "Stopped") if is_en else ("运行中" if enabled else "已关闭")},
            {"key": "Endpoint" if is_en else "局域网地址", "value": f"{ip}:{port}" if enabled else ("Idle" if is_en else "未监听")},
            {"key": "Paired" if is_en else "已配对手机", "value": f"{paired} ({connected} live)" if is_en else f"{paired} 台 ({connected} 在线)"},
            {"key": "Guards" if is_en else "幕布 / 防休眠", "value": f"{'ON' if curtain_on else 'OFF'} / {'ON' if caffeine_on else 'OFF'}"},
        ],
        "items": items,
    }


def main() -> int:
    raw_stdin = sys.stdin.read()
    stdin_obj: dict[str, Any] = {}
    if raw_stdin.strip():
        try:
            stdin_obj = json.loads(raw_stdin)
        except json.JSONDecodeError:
            stdin_obj = {}

    query = str(stdin_obj.get("query") or "")
    cfg = stdin_obj.get("config") if isinstance(stdin_obj.get("config"), dict) else {}
    show_pair_uri = str(cfg.get("showPairURIInCard", "true")).lower() != "false"
    pin_qr_on_top = str(cfg.get("pinQRWindowOnTop", "true")).lower() != "false"
    locale = str(stdin_obj.get("locale") or os.environ.get("LUMAKEY_LOCALE") or "zh-Hans")
    data_dir = str(stdin_obj.get("dataDir") or os.environ.get("LUMAKEY_DATA_DIR") or "")

    view_mode, action, params = parse_cli_and_query(sys.argv[1:], query)
    resp = call_host_bridge(
        os.environ.get("LUMAKEY_BRIDGE_SOCK", ""),
        os.environ.get("LUMAKEY_BRIDGE_TOKEN", ""),
        action,
        params,
    )
    payload = build_card_payload(
        resp,
        view_mode=view_mode,
        action_triggered=action,
        locale=locale,
        show_pair_uri=show_pair_uri,
        pin_qr_on_top=pin_qr_on_top,
    )
    eff = payload.get("effect") or {}
    if eff.get("statusSummary"):
        write_status_cache(data_dir, str(eff["statusSummary"]), str(eff.get("statusBadge", "IDLE")))
    sys.stdout.write(json.dumps(payload, ensure_ascii=False) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

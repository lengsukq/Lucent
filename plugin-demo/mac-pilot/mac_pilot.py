#!/usr/bin/env python3
"""Lumakey Official Store Plugin: Mac Pilot (System Controls, Settings Deep Links, Volumes & Finder)."""

from __future__ import annotations

import json
import os
import shutil
import socket
import subprocess
import sys
from pathlib import Path
from typing import Any

SYSTEM_PANES = [
    ("bluetooth", "蓝牙设置", "Bluetooth", "x-apple.systempreferences:com.apple.BluetoothSettings", "dot.radiowaves.left.and.right", ["蓝牙", "lanya", "bluetooth", "bt"]),
    ("displays", "显示器与分辨率", "Displays", "x-apple.systempreferences:com.apple.Displays-Settings.extension", "display", ["显示器", "xianshiqi", "display", "monitor", "分辨率"]),
    ("sound", "声音与输入输出", "Sound", "x-apple.systempreferences:com.apple.Sound-Settings.extension", "speaker.wave.3.fill", ["声音", "shengyin", "sound", "audio", "麦克风"]),
    ("network", "网络与代理", "Network", "x-apple.systempreferences:com.apple.Network-Settings.extension", "network", ["网络", "wangluo", "network", "proxy", "代理"]),
    ("wifi", "Wi-Fi 无线局域网", "Wi-Fi", "x-apple.systempreferences:com.apple.wifi-settings-extension", "wifi", ["wifi", "无线网", "wlan"]),
    ("battery", "电池与能耗", "Battery", "x-apple.systempreferences:com.apple.Battery-Settings.extension", "battery.100percent", ["电池", "dianchi", "battery", "电源"]),
    ("keyboard", "键盘与快捷键", "Keyboard", "x-apple.systempreferences:com.apple.Keyboard-Settings.extension", "keyboard", ["键盘", "jianpan", "keyboard"]),
    ("trackpad", "触控板与手势", "Trackpad", "x-apple.systempreferences:com.apple.Trackpad-Settings.extension", "rectangle.and.hand.point.up.left.fill", ["触控板", "chukongban", "trackpad"]),
    ("notifications", "通知与专注模式", "Notifications", "x-apple.systempreferences:com.apple.Notifications-Settings.extension", "bell.badge.fill", ["通知", "tongzhi", "notifications"]),
    ("accessibility", "隐私 › 辅助功能授权", "Privacy > Accessibility", "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility", "figure.wave.circle.fill", ["辅助功能", "fuzhugongneng", "accessibility", "ax权限"]),
    ("screen-recording", "隐私 › 屏幕录制授权", "Privacy > Screen Recording", "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture", "record.circle", ["屏幕录制", "录屏权限", "screen recording"]),
    ("full-disk", "隐私 › 完全磁盘访问权限", "Privacy > Full Disk Access", "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles", "externaldrive.badge.checkmark", ["完全磁盘访问", "磁盘权限", "full disk access"]),
    ("login-items", "通用 › 登录项与后台扩展", "General > Login Items", "x-apple.systempreferences:com.apple.LoginItems-Settings.extension", "person.badge.key.fill", ["登录项", "开机自启", "login items", "startup"]),
    ("storage", "通用 › 储存空间清理", "General > Storage", "x-apple.systempreferences:com.apple.settings.Storage", "internaldrive.fill", ["储存空间", "磁盘空间", "storage"]),
    ("wallpaper", "墙纸与屏幕保护程序", "Wallpaper", "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension", "photo.on.rectangle", ["壁纸", "墙纸", "wallpaper"]),
    ("security", "隐私与安全性总览", "Privacy & Security", "x-apple.systempreferences:com.apple.preference.security", "lock.shield.fill", ["隐私", "安全性", "仍要打开", "security", "gatekeeper"]),
]

FILE_TEMPLATES = {
    "md": ("Untitled", "# Untitled\n\n"),
    "txt": ("Untitled", ""),
    "json": ("data", "{\n  \n}\n"),
    "py": ("script", "#!/usr/bin/env python3\n\n"),
    "sh": ("run", "#!/usr/bin/env bash\nset -euo pipefail\n\n"),
}


def call_host_bridge(sock_path: str, token: str, capability: str, action: str, params: dict[str, Any]) -> dict[str, Any]:
    if not sock_path or not token:
        return {"ok": False, "error": "bridge_unavailable", "message": "Host Bridge socket not injected"}
    req = json.dumps({"token": token, "capability": capability, "action": action, "params": params}, ensure_ascii=False) + "\n"
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
            client.settimeout(4.0)
            client.connect(sock_path)
            client.sendall(req.encode("utf-8"))
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


def sync_panes_search_index(data_dir: str, enabled: bool, is_en: bool) -> None:
    if not data_dir:
        return
    dd = Path(data_dir)
    dd.mkdir(parents=True, exist_ok=True)
    if not enabled:
        (dd / "search-index.json").write_text(json.dumps({"items": []}, ensure_ascii=False), encoding="utf-8")
        return
    items = []
    for pid, zh_title, en_title, uri, icon, kws in SYSTEM_PANES:
        items.append({
            "id": f"pane-{pid}",
            "title": en_title if is_en else zh_title,
            "subtitle": "Open macOS System Settings pane" if is_en else f"直达 macOS 系统设置 · {en_title}",
            "keywords": kws,
            "icon": icon,
            "url": uri,
            "priority": 32,
        })
    (dd / "search-index.json").write_text(json.dumps({"items": items}, ensure_ascii=False), encoding="utf-8")


def format_bytes(num: int) -> str:
    val = float(max(0, num))
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if val < 1024.0 or unit == "TB":
            return f"{val:.1f} {unit}" if unit != "B" else f"{int(val)} B"
        val /= 1024.0
    return f"{val:.1f} TB"


def list_external_volumes(volumes_root: Path = Path("/Volumes")) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    if not volumes_root.exists():
        return out
    root_dev = os.stat("/").st_dev
    for entry in sorted(volumes_root.iterdir(), key=lambda p: p.name.lower()):
        if entry.name.startswith(".") or entry.is_symlink():
            continue
        try:
            st = entry.stat()
            if st.st_dev == root_dev:
                continue
            usage = shutil.disk_usage(entry)
            out.append({
                "name": entry.name,
                "path": str(entry),
                "total": usage.total,
                "free": usage.free,
            })
        except OSError:
            continue
    return out


def resolve_active_finder_dir(ctx: dict[str, Any]) -> Path:
    ctx_path = str(ctx.get("directory") or ctx.get("path") or "").strip()
    if ctx_path:
        p = Path(os.path.expanduser(ctx_path)).resolve()
        if p.is_dir():
            return p
        if p.exists():
            return p.parent

    try:
        res = subprocess.run(
            ["/usr/bin/osascript", "-e", 'tell application "Finder" to if (count of Finder windows) > 0 then get POSIX path of (target of front window as alias)'],
            capture_output=True, text=True, timeout=1.8, check=False,
        )
        out = res.stdout.strip()
        if out and Path(out).is_dir():
            return Path(out).resolve()
    except Exception:  # noqa: BLE001
        pass
    return (Path.home() / "Desktop").resolve()


def create_unique_blank_file(folder: Path, requested_name: str, default_ext: str) -> Path:
    folder.mkdir(parents=True, exist_ok=True)
    clean_req = requested_name.strip().replace("/", "_").replace(":", "_")
    ext = default_ext.lstrip(".").lower() or "md"
    stem_default, body = FILE_TEMPLATES.get(ext, ("Untitled", ""))
    if clean_req:
        if "." in clean_req and not clean_req.startswith("."):
            base_name = clean_req
            f_ext = Path(clean_req).suffix.lstrip(".").lower()
            _, body = FILE_TEMPLATES.get(f_ext, ("", ""))
        else:
            base_name = f"{clean_req}.{ext}"
    else:
        base_name = f"{stem_default}.{ext}"

    cand = folder / base_name
    idx = 2
    while cand.exists():
        cand = folder / f"{Path(base_name).stem}-{idx}{Path(base_name).suffix}"
        idx += 1
    cand.write_text(body, encoding="utf-8")
    if cand.suffix in {".py", ".sh"}:
        cand.chmod(0o755)
    return cand


def list_user_apps(filter_q: str = "") -> list[dict[str, Any]]:
    q = filter_q.strip().lower()
    try:
        res = subprocess.run(
            ["/bin/ps", "-axo", "pid=,rss=,comm="],
            capture_output=True, text=True, timeout=2.0, check=False,
        )
    except Exception:  # noqa: BLE001
        return []
    own_pid = os.getpid()
    seen: dict[str, dict[str, Any]] = {}
    for line in res.stdout.splitlines():
        parts = line.strip().split(None, 2)
        if len(parts) < 3:
            continue
        try:
            pid = int(parts[0])
            rss_kb = int(parts[1])
        except ValueError:
            continue
        comm = parts[2]
        if pid == own_pid or ".app/Contents/MacOS/" not in comm or "/System/Library/" in comm:
            continue
        app_name = comm.split(".app/Contents/MacOS/")[0].split("/")[-1]
        if app_name == "Lumakey":
            continue
        if q and q not in app_name.lower():
            continue
        prev = seen.get(app_name)
        if prev is None or rss_kb > prev["rssKB"]:
            seen[app_name] = {"pid": pid, "name": app_name, "rssKB": rss_kb}
    return sorted(seen.values(), key=lambda x: x["rssKB"], reverse=True)[:18]


def execute_plugin(
    argv: list[str],
    stdin_obj: dict[str, Any],
    sock_path: str = "",
    token: str = "",
    volumes_root: Path = Path("/Volumes"),
) -> dict[str, Any]:
    cfg = stdin_obj.get("config") if isinstance(stdin_obj.get("config"), dict) else {}
    query = str(stdin_obj.get("query") or "").strip()
    ctx = stdin_obj.get("context") if isinstance(stdin_obj.get("context"), dict) else {}
    locale = str(stdin_obj.get("locale") or os.environ.get("LUMAKEY_LOCALE") or "zh-Hans")
    is_en = locale.lower().startswith("en")
    data_dir = str(stdin_obj.get("dataDir") or os.environ.get("LUMAKEY_DATA_DIR") or "")

    sync_panes = str(cfg.get("syncSettingsPanesToSearch", "true")).lower() != "false"
    sync_panes_search_index(data_dir, sync_panes, is_en)

    flag = argv[0] if argv else ""
    toast: str | None = None

    if flag == "--sleep":
        subprocess.Popen(["/usr/bin/pmset", "sleepnow"])
        return {
            "schemaVersion": 2,
            "title": "Putting Mac to Sleep…" if is_en else "正在让 Mac 进入睡眠…",
            "badge": "SLEEP",
            "effect": {"closeOverlay": True, "toast": "Mac going to sleep" if is_en else "已发送睡眠指令"},
        }

    if flag == "--mute-toggle":
        call_host_bridge(sock_path, token, "systemControl", "setMute", {"muted": "toggle"})
        toast = "Toggled system mute" if is_en else "已切换系统静音状态"
        flag = "--audio"

    if flag == "--caffeine-toggle":
        call_host_bridge(sock_path, token, "systemControl", "setCaffeine", {})
        toast = "Toggled Keep-Awake (Caffeine)" if is_en else "已切换防休眠常亮保护"
        flag = "--audio"

    if flag == "--set-vol" and len(argv) >= 2:
        try:
            pct = max(0, min(100, int(argv[1])))
            call_host_bridge(sock_path, token, "systemControl", "setVolume", {"percent": pct})
            toast = f"Volume set to {pct}%" if is_en else f"系统音量已设为 {pct}%"
        except ValueError:
            pass
        flag = "--audio"

    if flag == "--panes":
        q = query.lower()
        rows = []
        for pid, zh_t, en_t, uri, icon, kws in SYSTEM_PANES:
            if q and not (q in zh_t.lower() or q in en_t.lower() or any(q in k for k in kws)):
                continue
            rows.append({
                "id": f"pane-{pid}",
                "title": en_t if is_en else zh_t,
                "subtitle": uri,
                "icon": icon,
                "badge": "SETTINGS",
                "openURL": uri,
            })
        return {
            "schemaVersion": 2,
            "title": "macOS System Settings Panes" if is_en else "macOS 系统设置分栏直达",
            "subtitle": f"{len(rows)} pane(s) synced to 0ms launcher search" if is_en else f"共 {len(rows)} 项高频分栏（已同步 ⌥Space 免前缀搜索）",
            "badge": "SETTINGS",
            "effect": {"reloadSearchIndex": True},
            "items": rows,
        }

    if flag in {"--finder", "--new-file", "--open-term"}:
        target_dir = Path(argv[1]).resolve() if (flag in {"--new-file", "--open-term"} and len(argv) >= 2) else resolve_active_finder_dir(ctx)
        def_ext = str(cfg.get("defaultNewFileExt") or "md")
        if flag == "--new-file":
            ext = argv[2] if len(argv) >= 3 else def_ext
            created = create_unique_blank_file(target_dir, query, ext)
            toast = f"Created {created.name}" if is_en else f"已新建文件：{created.name}"
        elif flag == "--open-term":
            subprocess.Popen(["/usr/bin/open", "-a", "Terminal", str(target_dir)])
            toast = "Opened in Terminal" if is_en else "已在终端打开该目录"

        items = [
            {
                "id": "copy-finder-path",
                "title": f"Copy Directory Path: {target_dir.name}" if is_en else f"复制当前目录路径：{target_dir.name}",
                "subtitle": str(target_dir),
                "icon": "doc.on.doc.fill",
                "badge": "PATH",
                "copyText": str(target_dir),
            },
            {
                "id": "open-in-term",
                "title": "Open Directory in Terminal" if is_en else "在「终端 (Terminal)」中打开此目录",
                "subtitle": str(target_dir),
                "icon": "terminal.fill",
                "badge": "TERM",
                "commandArgs": ["--open-term", str(target_dir)],
            },
        ]
        for ext, label in (("md", "Markdown (.md)"), ("txt", "Plain Text (.txt)"), ("json", "JSON (.json)"), ("py", "Python (.py)")):
            items.append({
                "id": f"mk-{ext}",
                "title": f"New {label} File Here" if is_en else f"在此目录新建空白 {label} 文件",
                "subtitle": (f"File name from search bar: '{query}'" if query else f"Creates Untitled.{ext} safely without overwriting")
                if is_en
                else (f"使用搜索框文件名「{query}」创建" if query else f"防重名安全创建 Untitled.{ext}"),
                "icon": "doc.badge.plus",
                "badge": f".{ext.upper()}",
                "commandArgs": ["--new-file", str(target_dir), ext],
            })
        eff: dict[str, Any] = {}
        if toast:
            eff["toast"] = toast
        return {
            "schemaVersion": 2,
            "title": f"Finder Helper · {target_dir.name}" if is_en else f"访达目录助手 · {target_dir.name}",
            "subtitle": str(target_dir),
            "badge": "FINDER",
            "effect": eff,
            "items": items,
        }

    if flag in {"--volumes", "--eject-one", "--eject-all"}:
        if flag == "--eject-one" and len(argv) >= 2:
            res = subprocess.run(["/usr/sbin/diskutil", "eject", argv[1]], capture_output=True, text=True, timeout=6.0, check=False)
            toast = ("Safely ejected volume" if res.returncode == 0 else (res.stderr.strip() or "Eject failed")) if is_en else ("已安全推出磁盘" if res.returncode == 0 else f"推出失败：{res.stderr.strip()[:48]}")
        elif flag == "--eject-all":
            for v in list_external_volumes(volumes_root):
                subprocess.run(["/usr/sbin/diskutil", "eject", v["path"]], capture_output=True, text=True, timeout=6.0, check=False)
            toast = "Ejected external volumes" if is_en else "已请求安全推出全部外置卷"

        vols = list_external_volumes(volumes_root)
        v_items: list[dict[str, Any]] = []
        if len(vols) >= 2:
            v_items.append({
                "id": "eject-all-btn",
                "title": f"Safely Eject All ({len(vols)} Volumes)" if is_en else f"一键安全推出全部外置磁盘 ({len(vols)} 个)",
                "subtitle": "Unmounts all non-root mounted volumes cleanly" if is_en else "依次安全卸载所有外置卷与 DMG 镜像",
                "icon": "eject.circle.fill",
                "badge": "EJECT ALL",
                "commandArgs": ["--eject-all"],
            })
        for v in vols:
            v_items.append({
                "id": f"vol-{v['name']}",
                "title": v["name"],
                "subtitle": f"{v['path']} · Free {format_bytes(v['free'])} / {format_bytes(v['total'])}",
                "icon": "externaldrive.fill",
                "badge": "EJECT",
                "commandArgs": ["--eject-one", v["path"]],
            })
        if not v_items:
            v_items.append({
                "id": "no-vols",
                "title": "No External Volumes Mounted" if is_en else "当前未检测到已挂载的外置磁盘或镜像",
                "subtitle": "/Volumes contains only system root volume" if is_en else "插入 U 盘、移动硬盘或挂载 DMG 后可在此一键安全推出",
                "icon": "checkmark.seal.fill",
                "badge": "CLEAN",
            })
        return {
            "schemaVersion": 2,
            "title": "External Disks & DMG Ejector" if is_en else "外置磁盘与镜像安全推出",
            "subtitle": f"{len(vols)} external volume(s)" if is_en else f"当前共 {len(vols)} 个外置挂载卷",
            "badge": f"{len(vols)} VOL",
            "effect": {"toast": toast} if toast else {},
            "items": v_items,
        }

    if flag in {"--apps", "--quit-app", "--kill-app"}:
        if flag == "--quit-app" and len(argv) >= 2:
            subprocess.run(["/usr/bin/osascript", "-e", f'tell application "{argv[1]}" to quit'], capture_output=True, timeout=3.0, check=False)
            toast = f"Sent Quit to {argv[1]}" if is_en else f"已通知「{argv[1]}」优雅退出"
        elif flag == "--kill-app" and len(argv) >= 2:
            try:
                os.kill(int(argv[1]), 9)
                toast = "Force terminated process" if is_en else "已强制结束该进程"
            except Exception:  # noqa: BLE001
                pass
        apps = list_user_apps(query)
        a_items = []
        for a in apps:
            mem_mb = a["rssKB"] / 1024.0
            a_items.append({
                "id": f"app-{a['pid']}",
                "title": a["name"],
                "subtitle": f"PID {a['pid']} · RAM {mem_mb:.0f} MB",
                "icon": "app.fill",
                "badge": f"{mem_mb:.0f} MB",
                "actions": [
                    {"id": f"q-{a['pid']}", "label": "Quit" if is_en else "退出", "commandArgs": ["--quit-app", a["name"]]},
                    {
                        "id": f"k-{a['pid']}",
                        "label": "Force Quit" if is_en else "强制退出",
                        "style": "destructive",
                        "commandArgs": ["--kill-app", str(a["pid"])],
                        "confirmMessage": f"Force quit {a['name']} (PID {a['pid']})?" if is_en else f"确认强制结束「{a['name']}」(PID {a['pid']})？未保存内容可能丢失。",
                    },
                ],
            })
        return {
            "schemaVersion": 2,
            "title": "Running Apps Manager" if is_en else "运行中应用管家",
            "subtitle": "Sorted by memory footprint" if is_en else "按实时物理内存占用排序 · 支持优雅退出与强退",
            "badge": f"{len(apps)} APPS",
            "effect": {"toast": toast} if toast else {},
            "items": a_items,
        }

    if query.isdigit() and 0 <= int(query) <= 100:
        call_host_bridge(sock_path, token, "systemControl", "setVolume", {"percent": int(query)})
        toast = f"Volume set to {query}%" if is_en else f"已将系统音量调节为 {query}%"

    st = call_host_bridge(sock_path, token, "systemControl", "status", {})
    sd = st.get("data") if st.get("ok") and isinstance(st.get("data"), dict) else {}
    vol = int(sd.get("volumePercent", 50))
    muted = bool(sd.get("isMuted", False))
    caf = bool(sd.get("caffeineActive", False))
    bridge_ok = bool(st.get("ok"))

    summary = f"Vol {vol}% {'(Muted)' if muted else ''} · Caffeine {'ON' if caf else 'OFF'}" if is_en else f"音量 {vol}%{'（已静音）' if muted else ''} · 防休眠{'开启' if caf else '关闭'}"
    if data_dir:
        Path(data_dir).mkdir(parents=True, exist_ok=True)
        (Path(data_dir) / "status.json").write_text(json.dumps({"summary": summary, "badge": "CAFFEINE" if caf else f"{vol}%"}, ensure_ascii=False), encoding="utf-8")

    main_items: list[dict[str, Any]] = []
    if not bridge_ok:
        main_items.append({
            "id": "grant-sys-bridge",
            "title": "Grant 'systemControl' Permission in Plugin Settings →" if is_en else "首次使用请点此开启「系统控制 (systemControl)」桥接权限 →",
            "subtitle": "Required to adjust macOS volume, mute & sleep prevention" if is_en else "授权后即可一键调节音量档位、静音与防休眠常亮",
            "icon": "lock.open.display",
            "badge": "GRANT",
            "openURL": "lumakey://settings/plugin/mac-pilot",
        })

    main_items.extend([
        {
            "id": "audio-row",
            "title": (f"System Audio: {'Muted' if muted else f'{vol}%'} (Type 0–100 to set)" if is_en else f"系统音量：{'已静音' if muted else f'{vol}%'}（搜索框直接输 0–100 可精准设音量）"),
            "subtitle": "Quick presets & mute toggle" if is_en else "一键切换静音或常用音量档位",
            "icon": "speaker.slash.fill" if muted else "speaker.wave.3.fill",
            "badge": "MUTED" if muted else f"{vol}%",
            "actions": [
                {"id": "m-tog", "label": ("Unmute" if muted else "Mute") if is_en else ("取消静音" if muted else "静音"), "commandArgs": ["--mute-toggle"]},
                {"id": "v-25", "label": "25%", "commandArgs": ["--set-vol", "25"]},
                {"id": "v-50", "label": "50%", "commandArgs": ["--set-vol", "50"]},
                {"id": "v-80", "label": "80%", "commandArgs": ["--set-vol", "80"]},
            ],
        },
        {
            "id": "caf-row",
            "title": (f"Keep Mac Awake (Caffeine): {'ACTIVE' if caf else 'OFF'}" if is_en else f"防休眠常亮保护 (Caffeine)：{'已开启' if caf else '未开启'}"),
            "subtitle": "Prevents idle display dimming & sleep during downloads or builds" if is_en else "跑编译、传大文件或阅读长文时阻止自动息屏睡眠",
            "icon": "cup.and.saucer.fill" if caf else "cup.and.saucer",
            "badge": "ON" if caf else "OFF",
            "commandArgs": ["--caffeine-toggle"],
        },
        {
            "id": "nav-finder",
            "title": "Finder Helper: New Blank File / Copy Path / Terminal →" if is_en else "访达助手：在当前窗口新建空白文件 / 复制路径 / 终端打开 →",
            "subtitle": "Supports .md, .txt, .json, .py with collision-safe naming" if is_en else "支持新建 .md / .txt / .json / .py，自动防重名",
            "icon": "doc.badge.plus",
            "badge": "FINDER",
            "commandArgs": ["--finder"],
        },
        {
            "id": "nav-panes",
            "title": "macOS System Settings Deep Links (16 Panes) →" if is_en else "直达 macOS 系统设置分栏（蓝牙 / 显示器 / 权限等 16 项）→",
            "subtitle": "Also searchable directly from ⌥Space without prefix" if is_en else "已同步 ⌥Space 免前缀索引，搜「蓝牙」「显示器」秒达",
            "icon": "gear.badge.checkmark",
            "badge": "16 PANES",
            "commandArgs": ["--panes"],
        },
        {
            "id": "nav-vols",
            "title": "Safely Eject External Disks & DMGs →" if is_en else "安全推出外置磁盘与 DMG 镜像 →",
            "subtitle": "Inspect free space and unmount cleanly" if is_en else "查看挂载卷剩余容量并一键安全推出",
            "icon": "eject.circle.fill",
            "badge": "VOLUMES",
            "commandArgs": ["--volumes"],
        },
        {
            "id": "nav-apps",
            "title": "Running Apps Manager (Quit / Force Quit) →" if is_en else "运行中应用管家（按内存排序 / 优雅退出 / 强退）→",
            "subtitle": "Inspect active GUI apps and reclaim RAM" if is_en else "查看前台应用内存占用并快速退出",
            "icon": "app.badge.checkmark",
            "badge": "APPS",
            "commandArgs": ["--apps"],
        },
    ])

    effect: dict[str, Any] = {"reloadSearchIndex": True, "statusSummary": summary, "statusBadge": "CAFFEINE" if caf else f"{vol}%"}
    if toast:
        effect["toast"] = toast

    return {
        "schemaVersion": 2,
        "title": "Mac Pilot · Desktop Control Center" if is_en else "桌面中控台 · Mac 快捷控制与访达助手",
        "subtitle": summary,
        "badge": "PILOT",
        "effect": effect,
        "metrics": [
            {"key": "Volume" if is_en else "当前音量", "value": "Muted" if muted else f"{vol}%"},
            {"key": "Caffeine" if is_en else "防休眠", "value": "ON" if caf else "OFF"},
            {"key": "Settings" if is_en else "设置直达", "value": "16 Panes"},
        ],
        "items": main_items,
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

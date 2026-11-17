import LumakeyFoundation; import LumakeySearch; import LumakeyMedia; import LumakeySystem
import Foundation

extension PluginStarterGallery {
    static let portManagerStarterTemplate = PluginStarterTemplate(
        id: "port-killer",
        name: "开发端口与监听进程管家",
        subtitle: "全量 LISTEN 端口表 · 内存与运行时长 · 二次确认优雅/强制释放",
        description: "自动扫描本机全部 TCP 监听端口，解析进程内存占用、运行时长与启动命令，支持按端口号或进程名过滤，并在卡片内带二次确认一键发送 SIGTERM / SIGKILL。",
        mode: .view,
        icon: "bolt.horizontal.circle.fill",
        accentColor: "orange",
        categoryTag: "开发排障",
        keywords: ["port", "lsof", "listen", "killport", "端口", "进程占用"],
        config: [
            PluginConfigField(
                key: "highlightDevPorts", label: "优先置顶常见开发端口 (3000/5173/8080 等)",
                type: .boolean, defaultValue: "true", section: "列表排序与安全"
            ),
            PluginConfigField(
                key: "maxListedPorts", label: "单页最多展示监听端口数",
                type: .number, control: .slider, defaultValue: "25",
                section: "列表排序与安全", minValue: 5, maxValue: 80, stepValue: 5
            )
        ],
        capabilities: [],
        resourceScopes: [.subprocess],
        commands: [
            PluginCommandSpec(
                id: "list-all-ports", title: "扫描本机全部 TCP 监听端口",
                subtitle: "汇总当前所有 LISTEN 端口、占用进程内存与可执行路径并支持一键释放",
                keywords: ["ports", "监听列表", "排查端口", "portcheck"],
                icon: "list.bullet.rectangle.portrait", arguments: ["--all"], passQuery: true
            )
        ],
        locales: [
            "en": PluginLocaleStrings(
                name: "Dev Port & Listener Manager",
                description: "Scan all active TCP LISTEN ports, inspect RSS memory & command paths, filter by port/process, and terminate via confirmed SIGTERM or SIGKILL.",
                categoryTag: "DevOps",
                commands: [
                    "list-all-ports": PluginCommandLocaleStrings(
                        title: "List All Active TCP Listening Ports",
                        subtitle: "Inspect listening PIDs, memory usage & release ports with confirmation"
                    )
                ]
            )
        ],
        scriptBody: #"""
        #!/bin/zsh
        set -euo pipefail
        PY_CODE="$(cat <<'PY'
        import json, os, re, signal, subprocess, sys, time

        DEV_PORTS = {3000, 3001, 4000, 4200, 5000, 5173, 5174, 5432, 6379, 8000, 8080, 8081, 8888, 9000, 27017}

        def run_out(cmd):
            try:
                return subprocess.run(cmd, capture_output=True, text=True, timeout=3.0).stdout or ""
            except Exception:
                return ""

        raw = sys.stdin.read()
        payload = json.loads(raw) if raw.strip().startswith("{") else {}
        cfg = payload.get("config") or {}
        query = str(payload.get("query") or "").strip()
        locale = str(payload.get("locale") or os.environ.get("LUMAKEY_LOCALE") or "zh-Hans")
        is_en = locale.lower().startswith("en")
        pin_dev = str(cfg.get("highlightDevPorts", "true")).lower() != "false"
        try:
            max_rows = max(5, min(80, int(cfg.get("maxListedPorts") or 25)))
        except ValueError:
            max_rows = 25

        args = sys.argv[1:]
        toast_msg = None
        if len(args) >= 3 and args[0] == "--kill":
            sig_name = args[1].upper()
            try:
                target_pid = int(args[2])
                target_port = args[3] if len(args) > 3 else ""
                sig = signal.SIGKILL if sig_name == "KILL" else signal.SIGTERM
                if target_pid > 1 and target_pid != os.getpid():
                    os.kill(target_pid, sig)
                    for _ in range(8):
                        time.sleep(0.05)
                        try:
                            os.kill(target_pid, 0)
                        except ProcessLookupError:
                            break
                    toast_msg = (
                        f"Sent SIG{sig_name} to PID {target_pid} (:{target_port})"
                        if is_en else f"已向 PID {target_pid} (端口 :{target_port}) 发送 SIG{sig_name} 释放信号"
                    )
            except Exception as exc:
                toast_msg = f"Kill failed: {exc}" if is_en else f"终止进程失败：{exc}"

        lsof_out = run_out(["/usr/sbin/lsof", "-nP", "-iTCP", "-sTCP:LISTEN"])
        entries_by_key = {}
        pids = set()
        for idx, line in enumerate(lsof_out.splitlines()):
            if idx == 0 or not line.strip():
                continue
            parts = line.split()
            if len(parts) < 9:
                continue
            proc_name, pid_s, user = parts[0], parts[1], parts[2]
            addr_col = parts[8]
            m_port = re.search(r":(\d+)$", addr_col)
            if not m_port or not pid_s.isdigit():
                continue
            port = int(m_port.group(1))
            pid = int(pid_s)
            host_part = addr_col[: m_port.start()]
            key = (port, pid)
            if key not in entries_by_key:
                entries_by_key[key] = {"port": port, "pid": pid, "proc": proc_name, "user": user, "binds": set()}
                pids.add(pid)
            entries_by_key[key]["binds"].add(host_part)

        ps_meta = {}
        if pids:
            ps_out = run_out(["/bin/ps", "-p", ",".join(str(x) for x in sorted(pids)), "-o", "pid=,rss=,etime=,command="])
            for pline in ps_out.splitlines():
                m = re.match(r"^\s*(\d+)\s+(\d+)\s+(\S+)\s+(.*)$", pline)
                if m:
                    p_id = int(m.group(1))
                    rss_mb = round(int(m.group(2)) / 1024.0, 1)
                    ps_meta[p_id] = (rss_mb, m.group(3), m.group(4).strip())

        rows = list(entries_by_key.values())
        q_clean = query.lstrip(":").lower()
        if q_clean:
            filtered = []
            for r in rows:
                cmd_full = ps_meta.get(r["pid"], (0.0, "", r["proc"]))[2]
                hay = f"{r['port']} {r['proc']} {r['pid']} {cmd_full}".lower()
                if q_clean in hay:
                    filtered.append(r)
            rows = filtered

        rows.sort(key=lambda r: (0 if (pin_dev and r["port"] in DEV_PORTS) else 1, r["port"], r["pid"]))
        total_matched = len(rows)
        shown = rows[:max_rows]

        items = []
        if not shown:
            empty_port = q_clean if q_clean.isdigit() else ""
            items.append({
                "id": "no-listen-hit",
                "title": (f"Port :{empty_port} is free" if empty_port else "No matching TCP LISTEN processes")
                if is_en else (f"端口 :{empty_port} 当前空闲可用" if empty_port else "未匹配到活跃的 TCP LISTEN 进程"),
                "subtitle": "Press Return to refresh active listeners" if is_en else "未检测到监听占用，回车可重新扫描全量端口",
                "icon": "checkmark.seal.fill",
                "badge": "FREE",
                "commandArgs": []
            })
        else:
            for r in shown:
                port, pid, proc = r["port"], r["pid"], r["proc"]
                rss_mb, etime, cmd_full = ps_meta.get(pid, (0.0, "-", proc))
                bind_scope = "0.0.0.0/*" if ("*" in r["binds"] or "0.0.0.0" in r["binds"] or "[::]" in r["binds"]) else "127.0.0.1"
                short_cmd = cmd_full if len(cmd_full) <= 68 else (cmd_full[:65] + "...")
                is_dev = port in DEV_PORTS
                items.append({
                    "id": f"listen-{port}-{pid}",
                    "title": f":{port} · {proc} (PID {pid})",
                    "subtitle": f"{bind_scope} · {rss_mb} MB · {etime} · {short_cmd}",
                    "icon": "hammer.circle.fill" if is_dev else "network",
                    "badge": "DEV" if is_dev else bind_scope,
                    "copyText": str(pid),
                    "actions": [
                        {
                            "id": f"term-{port}-{pid}",
                            "label": "SIGTERM" if is_en else "优雅释放",
                            "style": "primary",
                            "commandArgs": ["--kill", "TERM", str(pid), str(port)],
                            "confirmMessage": (
                                f"Send graceful SIGTERM to {proc} (PID {pid}) listening on port :{port}?"
                                if is_en else f"确认向占用端口 :{port} 的进程 {proc} (PID {pid}) 发送 SIGTERM 优雅退出信号吗？"
                            )
                        },
                        {
                            "id": f"kill-{port}-{pid}",
                            "label": "Force Kill" if is_en else "强杀",
                            "style": "destructive",
                            "commandArgs": ["--kill", "KILL", str(pid), str(port)],
                            "confirmMessage": (
                                f"Force-kill {proc} (PID {pid}) on port :{port} immediately with SIGKILL?"
                                if is_en else f"进程无响应时使用：确认立即使用 SIGKILL 强制终止 {proc} (PID {pid} · :{port}) 吗？"
                            )
                        }
                    ]
                })

        dev_count = sum(1 for r in rows if r["port"] in DEV_PORTS)
        lan_exposed = sum(1 for r in rows if ("*" in r["binds"] or "0.0.0.0" in r["binds"]))
        out = {
            "schemaVersion": 2,
            "title": "Dev Port & Listener Manager" if is_en else "开发端口与监听进程管家",
            "subtitle": (
                f"Showing {len(shown)}/{total_matched} listener(s)" + (f" matching '{query}'" if query else "")
                if is_en else f"共 {total_matched} 个监听端口（当前展示 {len(shown)} 个）" + (f" · 筛选「{query}」" if query else "")
            ),
            "badge": f"{total_matched} LISTEN",
            "metrics": [
                {"key": "Listening" if is_en else "活跃监听端口", "value": str(total_matched)},
                {"key": "Dev Ports" if is_en else "常见开发端口", "value": str(dev_count)},
                {"key": "LAN Exposed" if is_en else "全网卡暴露 (*)", "value": str(lan_exposed)},
                {"key": "Unique PIDs" if is_en else "驻留进程数", "value": str(len({r['pid'] for r in rows}))}
            ],
            "items": items
        }
        if toast_msg:
            out["effect"] = {"toast": toast_msg}
        print(json.dumps(out, ensure_ascii=False))
        PY
        )"
        exec /usr/bin/python3 -c "$PY_CODE" "$@"
        """#
    )
}

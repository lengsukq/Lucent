import LumakeyFoundation; import LumakeySearch; import LumakeyMedia; import LumakeySystem
import Foundation

extension PluginStarterGallery {
    static let netDiagStarterTemplate = PluginStarterTemplate(
        id: "sys-ip-dns",
        name: "网络栈与代理全维诊断",
        subtitle: "多网卡 IPv4/IPv6 · 默认网关 · VPN 隧道 · 系统代理 · DNS 刷新",
        description: "全景扫描本机活跃物理网卡与 VPN (utun) 隧道、默认路由网关、完整 DNS 解析链及 HTTP/SOCKS 系统代理状态，支持一键刷新 DNS 缓存。",
        mode: .view,
        icon: "network",
        accentColor: "blue",
        categoryTag: "网络诊断",
        keywords: ["ip", "dns", "proxy", "gateway", "netdiag", "网络诊断", "代理"],
        config: [
            PluginConfigField(
                key: "preferredInterface", label: "主网卡优先标识", type: .select,
                defaultValue: "auto", options: ["auto", "en0", "en1", "utun0"], section: "网络采样策略"
            ),
            PluginConfigField(
                key: "probePublicEgress", label: "默认探测公网出口 IP (1.5s 超时)", type: .boolean,
                defaultValue: "false", section: "网络采样策略"
            )
        ],
        capabilities: [],
        resourceScopes: [.network, .subprocess],
        commands: [
            PluginCommandSpec(
                id: "lan-dns", title: "速查网卡、网关、DNS 与系统代理",
                subtitle: "一键全景诊断本机多网卡 IP、VPN 隧道、路由网关与代理端口",
                keywords: ["lanip", "查ip", "本机dns", "proxycheck"], icon: "wifi",
                arguments: ["--scan"], passQuery: false
            ),
            PluginCommandSpec(
                id: "flush-dns", title: "刷新本机 DNS 解析缓存",
                subtitle: "调用 dscacheutil 立即清理本机过期域名解析记录",
                keywords: ["flushdns", "清理dns", "刷新dns"], icon: "arrow.clockwise.circle",
                arguments: ["--flush-dns"], passQuery: false
            ),
            PluginCommandSpec(
                id: "public-egress", title: "探测当前公网出口 IP",
                subtitle: "即时检测本机或代理分流后的真实公网出口 IPv4",
                keywords: ["pubip", "公网ip", "myip"], icon: "globe.asia.australia.fill",
                arguments: ["--public"], passQuery: false
            )
        ],
        locales: [
            "en": PluginLocaleStrings(
                name: "Network Stack & Proxy Inspector",
                description: "Inspect active NICs, VPN utun tunnels, default gateway, DNS resolvers & HTTP/SOCKS proxies, plus 1-click DNS cache flush.",
                categoryTag: "Network",
                commands: [
                    "lan-dns": PluginCommandLocaleStrings(title: "Inspect NICs, Gateway, DNS & Proxy", subtitle: "Full snapshot of local IPv4/IPv6, VPN tunnels, gateway & proxy state"),
                    "flush-dns": PluginCommandLocaleStrings(title: "Flush macOS DNS Cache", subtitle: "Clear local dscacheutil DNS entries immediately"),
                    "public-egress": PluginCommandLocaleStrings(title: "Probe Public Egress IP", subtitle: "Check current outbound public IPv4 address")
                ]
            )
        ],
        scriptBody: #"""
        #!/bin/zsh
        set -euo pipefail
        PY_CODE="$(cat <<'PY'
        import json, os, re, subprocess, sys, urllib.request

        def run_cmd(cmd, timeout=2.0):
            try:
                p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
                return p.stdout or ""
            except Exception:
                return ""

        raw = sys.stdin.read()
        payload = json.loads(raw) if raw.strip().startswith("{") else {}
        cfg = payload.get("config") or {}
        query = str(payload.get("query") or "").strip().lower()
        locale = str(payload.get("locale") or os.environ.get("LUMAKEY_LOCALE") or "zh-Hans")
        is_en = locale.lower().startswith("en")
        args = sys.argv[1:]

        did_flush = False
        if "--flush-dns" in args or query in {"flush", "flushdns", "刷新dns"}:
            run_cmd(["/usr/bin/dscacheutil", "-flushcache"])
            did_flush = True

        route_out = run_cmd(["/sbin/route", "-n", "get", "default"])
        gw_m = re.search(r"gateway:\s*(\S+)", route_out)
        if_m = re.search(r"interface:\s*(\S+)", route_out)
        gateway = gw_m.group(1) if gw_m else ("None" if is_en else "未连接")
        default_if = if_m.group(1) if if_m else "en0"
        pref_if = str(cfg.get("preferredInterface") or "auto")
        primary_if = default_if if pref_if == "auto" else pref_if

        ifcfg = run_cmd(["/sbin/ifconfig"])
        nics = []
        cur = None
        for line in ifcfg.splitlines():
            m_hdr = re.match(r"^([a-zA-Z0-9]+):\s+flags=.*<([^>]*)>", line)
            if m_hdr:
                if cur and (cur["v4"] or cur["v6"]):
                    nics.append(cur)
                flags = m_hdr.group(2).split(",")
                cur = {"name": m_hdr.group(1), "up": "UP" in flags and "LOOPBACK" not in flags, "v4": [], "v6": [], "mac": ""}
                continue
            if not cur or not cur["up"]:
                continue
            s = line.strip()
            if s.startswith("inet "):
                parts = s.split()
                if len(parts) >= 2 and not parts[1].startswith("127."):
                    cur["v4"].append(parts[1])
            elif s.startswith("inet6 "):
                addr = s.split()[1].split("%")[0]
                if not addr.startswith("fe80:") and addr != "::1":
                    cur["v6"].append(addr)
            elif s.startswith("ether "):
                cur["mac"] = s.split()[1]
        if cur and (cur["v4"] or cur["v6"]):
            nics.append(cur)

        nics.sort(key=lambda x: (0 if x["name"] == primary_if else (1 if x["name"].startswith("en") else 2), x["name"]))
        primary_ip = nics[0]["v4"][0] if (nics and nics[0]["v4"]) else "127.0.0.1"

        dns_out = run_cmd(["/usr/sbin/scutil", "--dns"])
        resolvers = []
        for m in re.finditer(r"nameserver\[\d+\]\s*:\s*(\S+)", dns_out):
            ip_val = m.group(1)
            if ip_val not in resolvers:
                resolvers.append(ip_val)

        proxy_out = run_cmd(["/usr/sbin/scutil", "--proxy"])
        def px(key):
            m = re.search(rf"\b{key}\s*:\s*(\S+)", proxy_out)
            return m.group(1) if m else ""
        proxies = []
        if px("HTTPEnable") == "1" and px("HTTPProxy"):
            proxies.append(f"HTTP {px('HTTPProxy')}:{px('HTTPPort')}")
        if px("SOCKSEnable") == "1" and px("SOCKSProxy"):
            proxies.append(f"SOCKS {px('SOCKSProxy')}:{px('SOCKSPort')}")
        proxy_summary = " · ".join(proxies) if proxies else ("Direct (No Proxy)" if is_en else "直连 (未开启系统代理)")

        want_pub = ("--public" in args) or (query in {"pub", "public", "公网"}) or (str(cfg.get("probePublicEgress")).lower() == "true")
        pub_ip = "On-Demand" if is_en else "按需探测"
        if want_pub:
            try:
                ep = "https" + "://api.ipify.org?format=json"
                with urllib.request.urlopen(ep, timeout=1.6) as r:
                    pub_ip = json.loads(r.read().decode("utf-8")).get("ip") or "Unavailable"
            except Exception:
                pub_ip = "Timeout/Offline" if is_en else "离线或超时"

        host_name = (run_cmd(["/usr/sbin/scutil", "--get", "LocalHostName"]).strip() or os.uname().nodename)
        vpn_nics = [n["name"] for n in nics if n["name"].startswith("utun")]
        items = []
        for n in nics:
            v4_txt = ", ".join(n["v4"]) if n["v4"] else "IPv6 Only"
            sub_parts = [f"Gateway {gateway}" if n["name"] == default_if else ("VPN Tunnel" if n["name"].startswith("utun") else "Active NIC")]
            if n["mac"]:
                sub_parts.append(f"MAC {n['mac']}")
            if n["v6"]:
                sub_parts.append(f"IPv6 {n['v6'][0]}")
            items.append({
                "id": f"nic-{n['name']}",
                "title": f"{n['name']} · {v4_txt}",
                "subtitle": " · ".join(sub_parts),
                "icon": "lock.shield.fill" if n["name"].startswith("utun") else "wifi",
                "badge": "DEFAULT" if n["name"] == default_if else ("VPN" if n["name"].startswith("utun") else "NIC"),
                "copyText": n["v4"][0] if n["v4"] else n["v6"][0]
            })

        dns_joined = ", ".join(resolvers[:4]) if resolvers else ("System Auto" if is_en else "系统自动")
        items.append({
            "id": "dns-chain",
            "title": (f"DNS Resolvers: {dns_joined}" if is_en else f"DNS 解析链：{dns_joined}"),
            "subtitle": f"Default Gateway: {gateway} ({default_if})" if is_en else f"默认路由网关：{gateway}（出接口 {default_if}）",
            "icon": "server.rack",
            "badge": f"{len(resolvers)} DNS",
            "copyText": resolvers[0] if resolvers else gateway,
            "actions": [{"id": "act-flush", "label": "Flush DNS" if is_en else "刷新 DNS", "commandArgs": ["--flush-dns"]}]
        })
        items.append({
            "id": "sys-proxy",
            "title": (f"System Proxy: {proxy_summary}" if is_en else f"系统代理：{proxy_summary}"),
            "subtitle": (f"Public Egress: {pub_ip}" if is_en else f"公网出口：{pub_ip}"),
            "icon": "arrow.triangle.branch",
            "badge": "PROXY" if proxies else "DIRECT",
            "copyText": proxies[0].split()[-1] if proxies else primary_ip,
            "actions": [] if want_pub else [{"id": "act-pub", "label": "Probe Public IP" if is_en else "查公网出口", "commandArgs": ["--public"]}]
        })

        out = {
            "schemaVersion": 2,
            "title": "Network Stack & Proxy Inspector" if is_en else "本机网络栈与代理全维诊断",
            "subtitle": f"{host_name} · Default {default_if} -> {gateway}",
            "badge": "VPN+PROXY" if (vpn_nics and proxies) else ("VPN" if vpn_nics else ("PROXY" if proxies else "ONLINE")),
            "metrics": [
                {"key": "Primary IPv4" if is_en else "首选局域网 IP", "value": primary_ip},
                {"key": "Gateway" if is_en else "默认网关", "value": f"{gateway} ({default_if})"},
                {"key": "Primary DNS" if is_en else "主用 DNS", "value": resolvers[0] if resolvers else "Auto"},
                {"key": "Public / VPN" if is_en else "公网 / 隧道", "value": pub_ip if want_pub else (", ".join(vpn_nics) if vpn_nics else ("No VPN" if is_en else "无隧道"))}
            ],
            "items": items
        }
        if did_flush:
            out["effect"] = {"toast": "macOS DNS cache flushed" if is_en else "已刷新本机 DNS 解析缓存"}
        print(json.dumps(out, ensure_ascii=False))
        PY
        )"
        exec /usr/bin/python3 -c "$PY_CODE" "$@"
        """#
    )
}

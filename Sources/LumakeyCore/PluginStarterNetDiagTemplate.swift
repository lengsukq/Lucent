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
        cat >/dev/null || true
        if [[ "${1:-}" == "--flush-dns" ]]; then
          /usr/bin/dscacheutil -flushcache 2>/dev/null || true
        fi
        ROUTE_OUT="$(/sbin/route -n get default 2>/dev/null || true)"
        GW="$(printf '%s\n' "$ROUTE_OUT" | /usr/bin/awk '/gateway:/{print $2; exit}')"
        IFACE="$(printf '%s\n' "$ROUTE_OUT" | /usr/bin/awk '/interface:/{print $2; exit}')"
        IFACE="${IFACE:-en0}"
        GW="${GW:-none}"
        LAN_IP="$(/usr/sbin/ipconfig getifaddr "$IFACE" 2>/dev/null || echo 127.0.0.1)"
        DNS_IP="$(/usr/sbin/scutil --dns 2>/dev/null | /usr/bin/awk '/nameserver\[0\]/{print $3; exit}')"
        DNS_IP="${DNS_IP:-auto}"
        cat <<EOF
        {"schemaVersion":2,"title":"本机网络栈与代理全维诊断","subtitle":"Default ${IFACE} -> ${GW}","badge":"ONLINE","metrics":[{"key":"首选局域网 IP","value":"${LAN_IP}"},{"key":"默认网关","value":"${GW} (${IFACE})"},{"key":"主用 DNS","value":"${DNS_IP}"}],"items":[{"id":"nic-${IFACE}","title":"${IFACE} · ${LAN_IP}","subtitle":"默认网关 ${GW}","icon":"wifi","badge":"DEFAULT","copyText":"${LAN_IP}"}]}
        EOF
        """#
    )
}

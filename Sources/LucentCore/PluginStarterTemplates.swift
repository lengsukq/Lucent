import Foundation

extension PluginStarterGallery {
    /// 官方内置精选模板：与宿主内置工具（`DevToolkitEngine` / `SystemPulse`）完全正交的三款预编译原生 Swift 扩展。
    public static let templates: [PluginStarterTemplate] = [
        netDiagStarterTemplate,
        portManagerStarterTemplate,
        inboxNoteStarterTemplate
    ]

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
        ]
    )

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
        ]
    )

    static let inboxNoteStarterTemplate = PluginStarterTemplate(
        id: "shell-note",
        name: "灵感速记与 Markdown 收件箱",
        subtitle: "结构化速记 · #标签检索 · 待办勾选/置顶/删除 · 免前缀索引同步",
        description: "支持从搜索框、剪贴板链接或 OCR 选区极速追加带时间戳的 Markdown 速记，内置 #标签过滤、置顶、完成勾选、二次确认删除及一键唤起原生阅读窗。",
        mode: .view,
        icon: "note.text.badge.plus",
        accentColor: "teal",
        categoryTag: "速记收件箱",
        keywords: ["note", "memo", "inbox", "速记", "灵感", "笔记"],
        config: [
            PluginConfigField(
                key: "notesPath", label: "Markdown 收件箱文件路径", type: .path,
                defaultValue: "~/Documents/Lucent-Notes.md",
                placeholder: "~/Documents/Lucent-Notes.md", section: "存储与标签",
                includeInBackup: true
            ),
            PluginConfigField(
                key: "defaultTag", label: "未带标签时的默认分类标签", type: .text,
                defaultValue: "#idea", placeholder: "#idea", section: "存储与标签"
            ),
            PluginConfigField(
                key: "maxShownNotes", label: "卡片最多展示记录条数", type: .select,
                defaultValue: "15", options: ["10", "15", "25", "40"], section: "存储与标签"
            )
        ],
        capabilities: [],
        resourceScopes: [.filesystem],
        accepts: [.text, .url],
        commands: [
            PluginCommandSpec(
                id: "recent-notes", title: "浏览与检索灵感收件箱",
                subtitle: "打开结构化速记卡片，支持按关键词/#标签筛选、置顶、勾选完成或阅读窗全文预览",
                keywords: ["notetail", "最近笔记", "收件箱", "notes"], icon: "tray.full.fill",
                arguments: ["--browse"], passQuery: true
            ),
            PluginCommandSpec(
                id: "open-notes-reader", title: "在独立阅读窗打开灵感笔记全文",
                subtitle: "直接唤起 Lucent 原生 Markdown 阅读器查看完整收件箱文档",
                keywords: ["readnotes", "打开笔记"], icon: "book.pages.fill",
                arguments: ["--open-reader"], passQuery: false
            )
        ],
        locales: [
            "en": PluginLocaleStrings(
                name: "Quick Capture & Markdown Inbox",
                description: "Capture timestamped thoughts, URLs & OCR text into a local Markdown inbox with #tag filtering, pinning, check-off, zero-prefix search index & native Reader view.",
                categoryTag: "Notes",
                commands: [
                    "recent-notes": PluginCommandLocaleStrings(title: "Browse & Search Markdown Inbox", subtitle: "Filter notes by #tag, pin, toggle done, or delete with confirmation"),
                    "open-notes-reader": PluginCommandLocaleStrings(title: "Open Full Inbox in Markdown Reader", subtitle: "Launch Lucent native Markdown reader for your inbox file")
                ]
            )
        ]
    )
}

import LucentFoundation
import LucentSearch
import Foundation

public struct UnitConversionResult: Sendable, Hashable {
    public let expression: String
    public let resultText: String
    public let badgeLabel: String
}

public enum SystemCommandKind: Sendable, Hashable {
    case openWelcome
    case openWorkspace
    case openSettings
    case openClipboard
    case openEverything
    case capturePin
    case captureOCR
    case recordGif
    case recordVideo
    case openTrash
    case emptyTrash
    case lockScreen
    case toggleMosEnabled
    case toggleMosReverse
    case toggleMosSmooth
    case openMosSettings
    case toggleSystemMonitor
    case openNetworkMonitor
    case openCacheManager
    case openBackupSettings
    case quickBackup
    case openSnippetsSettings
    case openScriptsSettings
    case openPluginsSettings
    case switchTheme(AppThemeID)
    case cycleTheme
    case switchLanguage(AppLanguageID)
    case cycleLanguage
    case reclaimMemory
    case inspectPort(Int)
    case openVolume(URL)
    case openPath(URL)
    case webSearch(engine: String, url: URL)
}

public struct CommandSuggestion: Identifiable, Sendable, Hashable {
    public let id: String
    public let score: Int
    public let title: String
    public let subtitle: String
    public let badgeLabel: String
    public let symbol: String
    public let command: SystemCommandKind
}

public enum UnitAndCommandEngine {
    public static func evaluate(_ raw: String) -> UnitConversionResult? {
        UnitConversionCatalog.evaluate(raw)
    }

    public static func matchCommands(query: String, volumes: [VolumeSummary]) -> [CommandSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.isEmpty {
            return [
                CommandSuggestion(id: "cmd:welcome", score: 420, title: L10n.pick("欢迎使用 流光 Lucent", "Welcome to Lucent"), subtitle: L10n.pick("查看全部快捷能力与全局热键指南", "Explore all quick actions & global hotkeys"), badgeLabel: L10n.pick("引导", "Guide"), symbol: "sparkles", command: .openWelcome),
                CommandSuggestion(id: "cmd:everything", score: 410, title: L10n.pick("全盘文件秒搜 (⌥F)", "Instant Disk File Search (⌥F)"), subtitle: L10n.pick("紧凑索引支持 ext: / video: / pic: / path:", "Compact index with ext: / video: / pic: / path: DSL"), badgeLabel: L10n.pick("秒搜", "Files"), symbol: "magnifyingglass", command: .openEverything),
                CommandSuggestion(id: "cmd:clipboard", score: 400, title: L10n.pick("剪贴板历史 (⌥C)", "Clipboard History (⌥C)"), subtitle: L10n.pick("自动记录文本、颜色色值、图片与文件路径", "Captures text, #HEX colors, images & file paths"), badgeLabel: L10n.pick("剪贴板", "Clips"), symbol: "doc.on.clipboard", command: .openClipboard),
                CommandSuggestion(id: "cmd:capture-pin", score: 390, title: L10n.pick("选区截图钉屏 (⌥A)", "Screenshot & Pin (⌥A)"), subtitle: L10n.pick("调用系统截图并悬浮置顶，悬停可 OCR/抠图", "Annotate, pin floating captures, OCR & subject cutout"), badgeLabel: L10n.pick("截图", "Capture"), symbol: "camera.viewfinder", command: .capturePin),
                CommandSuggestion(id: "cmd:workspace", score: 380, title: L10n.pick("双栏文件与外置 NTFS 工作台 · 附加 (⌥E)", "Dual-Pane File & NTFS Workspace (⌥E)"), subtitle: L10n.pick("侧边实时预览、只读看图/播片、NTFS 安全识别", "Live side preview, media player & safe read-only NTFS"), badgeLabel: L10n.pick("附加", "Files"), symbol: "folder.fill", command: .openWorkspace)
            ]
        }

        var items: [CommandSuggestion] = []
        if let directPath = resolveDirectLocalPath(trimmed) {
            items.append(CommandSuggestion(
                id: "cmd:path:\(directPath.path)",
                score: 9_680,
                title: L10n.pick("直接打开路径：\(directPath.lastPathComponent)", "Open Path: \(directPath.lastPathComponent)"),
                subtitle: directPath.path,
                badgeLabel: L10n.pick("路径", "Path"),
                symbol: "folder.badge.gearshape",
                command: .openPath(directPath)
            ))
        } else if let directURL = resolveDirectWebURL(trimmed) {
            items.append(CommandSuggestion(
                id: "cmd:url:\(directURL.absoluteString)",
                score: 9_650,
                title: L10n.pick("在浏览器打开 \(directURL.host ?? trimmed)", "Open \(directURL.host ?? trimmed) in Browser"),
                subtitle: directURL.absoluteString,
                badgeLabel: "URL",
                symbol: "safari.fill",
                command: .webSearch(engine: directURL.host ?? "URL", url: directURL)
            ))
        }

        if lower.hasPrefix("port ") {
            let arg = lower.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if let port = Int(arg), (1...65_535).contains(port) {
                items.append(CommandSuggestion(id: "cmd:port:\(port)", score: 9_600, title: L10n.pick("查看端口 \(port) 监听进程", "Inspect Process on Port \(port)"), subtitle: L10n.pick("调用系统 lsof 检测占用进程", "Probe TCP LISTEN PID via lsof"), badgeLabel: L10n.pick("端口", "Port"), symbol: "network", command: .inspectPort(port)))
            }
        }

        let webPrefixes: [(prefix: String, name: String, baseURL: String)] = [
            ("g ", "Google", "https://www.google.com/search?q="),
            ("gh ", "GitHub", "https://github.com/search?q="),
            ("bd ", "百度", "https://www.baidu.com/s?wd="),
            ("bili ", "哔哩哔哩", "https://search.bilibili.com/all?keyword="),
            ("yt ", "YouTube", "https://www.youtube.com/results?search_query="),
            ("zh ", "知乎", "https://www.zhihu.com/search?type=content&q="),
            ("ddg ", "DuckDuckGo", "https://duckduckgo.com/?q="),
            ("so ", "Stack Overflow", "https://stackoverflow.com/search?q="),
            ("v2 ", "V2EX", "https://www.google.com/search?q=site%3Av2ex.com%2Ft+")
        ]
        for engine in webPrefixes where lower.hasPrefix(engine.prefix) {
            let term = String(trimmed.dropFirst(engine.prefix.count)).trimmingCharacters(in: .whitespaces)
            if let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let url = URL(string: engine.baseURL + encoded), !term.isEmpty {
                items.append(CommandSuggestion(id: "cmd:web:\(engine.name)", score: 9_400, title: L10n.pick("用 \(engine.name) 搜索「\(term)」", "Search \(engine.name) for \"\(term)\""), subtitle: L10n.pick("在默认浏览器打开搜索结果", "Open search results in default browser"), badgeLabel: L10n.pick("网页", "Web"), symbol: "globe", command: .webSearch(engine: engine.name, url: url)))
            }
        }

        let diskKeywords = ["ntfs", "disk", "volumes", "磁盘", "外置", "硬盘"]
        if lower.count >= 2 && diskKeywords.contains(where: { $0.hasPrefix(lower) || lower.contains($0) }) {
            for vol in volumes where vol.mountPath != "/" {
                let url = URL(fileURLWithPath: vol.mountPath)
                items.append(CommandSuggestion(id: "cmd:vol:\(vol.mountPath)", score: 8_800, title: L10n.pick("打开磁盘 \(vol.name)", "Open Volume \(vol.name)"), subtitle: "\(vol.mountPath) · \(vol.capacityText)", badgeLabel: vol.formatKind.badgeText, symbol: "externaldrive.fill", command: .openVolume(url)))
            }
        }

        for item in commandCatalog {
            let exact = item.keywords.contains(lower)
            let prefix = lower.count >= 2 && item.keywords.contains(where: { $0.hasPrefix(lower) || lower.hasPrefix($0) })
            if exact || prefix {
                items.append(CommandSuggestion(id: "cmd:\(item.id)", score: exact ? 8_600 : 7_200, title: item.title, subtitle: item.subtitle, badgeLabel: item.badge, symbol: item.symbol, command: item.cmd))
            }
        }
        return items
    }

    public static func inspectListeningPort(_ port: Int) -> String {
        guard let result = try? ProcessSupervisor.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/sbin/lsof"),
            arguments: ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN"],
            timeoutSeconds: 3.0,
            maxOutputBytes: 32_768
        ) else {
            return L10n.pick("无法运行系统 lsof。", "Failed to invoke /usr/sbin/lsof.")
        }
        if result.timedOut {
            return L10n.pick("lsof 查询端口 \(port) 超时并已被自动终止。", "lsof query on port \(port) timed out and was terminated.")
        }
        let out = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? L10n.pick("端口 \(port) 当前无监听进程。", "No TCP LISTEN process found on port \(port).") : out
    }

    private static func resolveDirectLocalPath(_ raw: String) -> URL? {
        guard raw.hasPrefix("~/") || raw == "~" || raw.hasPrefix("/") else { return nil }
        let expanded = (raw as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded).standardizedFileURL
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func resolveDirectWebURL(_ raw: String) -> URL? {
        guard !raw.contains(where: \.isWhitespace) else { return nil }
        if raw.lowercased().hasPrefix("http://") || raw.lowercased().hasPrefix("https://") {
            guard let u = URL(string: raw), let h = u.host, h.contains(".") || h == "localhost" else { return nil }
            return u
        }
        if raw.contains("."), !raw.hasPrefix("."), !raw.hasSuffix("."),
           raw.range(of: #"^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+(:[0-9]{1,5})?(/.*)?$"#, options: .regularExpression) != nil {
            let suffix = raw.split(separator: "/").first?.split(separator: ".").last?.lowercased() ?? ""
            let fileExts: Set<String> = ["swift", "py", "js", "ts", "md", "txt", "json", "png", "jpg", "pdf", "zip", "dmg", "mp4", "mov"]
            guard !fileExts.contains(suffix) else { return nil }
            return URL(string: "https://" + raw)
        }
        return nil
    }

    private static var commandCatalog: [(keywords: [String], id: String, title: String, subtitle: String, badge: String, symbol: String, cmd: SystemCommandKind)] {
        [
            (["lock", "锁屏", "suoping"], "lock", L10n.pick("锁定屏幕", "Lock Screen"), L10n.pick("立即锁定当前 macOS 会话", "Lock the current macOS session immediately"), L10n.pick("系统", "System"), "lock.fill", .lockScreen),
            (["trash", "废纸篓", "feizhilou"], "trash", L10n.pick("打开废纸篓", "Open Trash"), L10n.pick("在访达中查看废纸篓内容", "Reveal Trash in Finder"), L10n.pick("系统", "System"), "trash", .openTrash),
            (["emptytrash", "清空废纸篓"], "emptytrash", L10n.pick("清空废纸篓", "Empty Trash"), L10n.pick("通过系统访达执行清空（需确认）", "Empty Trash via Finder (with confirmation)"), L10n.pick("系统", "System"), "trash.slash.fill", .emptyTrash),
            (["ocr", "识字", "shizi"], "ocr", L10n.pick("截图并离线 OCR 识字 (⌥O)", "Capture & Offline Vision OCR (⌥O)"), L10n.pick("调用 Vision 中英识别并复制", "Recognize CJK/English text offline & copy"), L10n.pick("视觉", "OCR"), "text.viewfinder", .captureOCR),
            (["screenshot", "截图", "jietu", "钉图"], "capture", L10n.pick("选区截图并钉在屏幕 (⌥A)", "Capture, Annotate & Pin (⌥A)"), L10n.pick("悬停工具条支持识别与主体抠图", "Hover toolbar supports OCR & subject cutout"), L10n.pick("截图", "Capture"), "camera.viewfinder", .capturePin),
            (["gif", "录屏", "动图", "record", "luping", "dongtu"], "gif-record", L10n.pick("区域 / 窗口 GIF 动图录制 (⌥G)", "Record Region / Window GIF (⌥G)"), L10n.pick("框选区域或吸附窗口录制高帧率轻量 GIF 并复制", "Capture high-FPS GIF89a and copy to clipboard"), L10n.pick("录屏", "GIF"), "record.circle.fill", .recordGif),
            (["video", "录像", "录屏", "mp4", "rec", "luxiang", "shipin"], "video-record", L10n.pick("区域 / 窗口视频录像 (⌥R)", "Record Region / Window Video (⌥R)"), L10n.pick("框选区域或吸附窗口录制流畅 MP4 视频（可选系统声音）", "Record smooth MP4 video of region or window with optional system audio"), L10n.pick("录像", "Video"), "video.circle.fill", .recordVideo),
            (["clipboard", "剪贴板", "jianqieban"], "clip", L10n.pick("打开剪贴板历史 (⌥C)", "Open Clipboard History (⌥C)"), L10n.pick("按类型筛选并回车复制", "Filter by category and press Return to copy"), L10n.pick("工具", "Tool"), "doc.on.clipboard.fill", .openClipboard),
            (["files", "workspace", "工作台", "gongzuotai"], "ws", L10n.pick("打开双栏文件工作台 (⌥E)", "Open Dual-Pane File Workspace (⌥E)"), L10n.pick("外置 NTFS 检测与侧边预览", "External NTFS guard & live side preview"), L10n.pick("附加", "Workspace"), "sidebar.squares.left", .openWorkspace),
            (["settings", "设置", "shezhi"], "settings", L10n.pick("流光设置与插件中心 (⌘,)", "Lucent Settings & Plugins (⌘,)"), L10n.pick("语言、外观、索引目录、MCP 与快捷键", "Language, theme, search scope, MCP & hotkeys"), L10n.pick("设置", "Settings"), "gearshape.fill", .openSettings),
            (["language", "lang", "语言", "切换语言", "多语言", "yuyan"], "cycle-lang", L10n.pick("切换界面语言（简体中文 / English）", "Switch Interface Language (简体中文 / English)"), L10n.pick("在简体中文与英文界面之间即时无感切换", "Instantly switch UI between Simplified Chinese and English"), L10n.pick("语言", "Language"), "globe", .cycleLanguage),
            (["english", "英文", "英语", "yingwen"], "lang-en", L10n.pick("切换为英文界面 (English)", "Switch Language to English"), L10n.pick("将 Lucent 全部窗口与菜单即时切换为英文", "Switch all Lucent windows & menus to English"), "EN", "globe", .switchLanguage(.english)),
            (["chinese", "中文", "简体中文", "zhongwen"], "lang-zh", L10n.pick("切换为简体中文界面", "Switch Language to 简体中文"), L10n.pick("将 Lucent 全部窗口与菜单即时切换为简体中文", "Switch all Lucent windows & menus to Simplified Chinese"), "ZH", "character.bubble.fill", .switchLanguage(.zhHans)),
            (["theme", "主题", "切换主题", "外观", "深浅色", "zhuti"], "cycle-theme", L10n.pick("切换界面主题（晴霜浅色 / 曜石暗色）", "Switch Theme (Light Frost / Obsidian Dark)"), L10n.pick("在「晴霜浅色」与「曜石暗色」液态玻璃外观间即时切换", "Toggle live between Light Frost and Obsidian Dark"), L10n.pick("主题", "Theme"), "paintpalette.fill", .cycleTheme),
            (["light frost", "light", "pure frost", "frost", "晴霜", "晴霜浅色", "浅色", "亮色", "凝霜", "凝霜留白", "留白", "qingshuang", "ningshuang"], "theme-frost", L10n.pick("启用「晴霜浅色」主题 (Light Frost)", "Activate Light Frost Theme"), L10n.pick("通透瓷白毛玻璃与柔和镜面高光，明晰纯粹", "Luminous porcelain glass with crisp specular highlights"), L10n.pick("主题", "Theme"), "sun.max.fill", .switchTheme(.pureFrost)),
            (["obsidian dark", "obsidian", "dark", "prism pulse", "prism", "曜石", "曜石暗色", "暗色", "深色", "霓彩", "霓彩流光", "极光", "yaoshi", "nicai"], "theme-prism", L10n.pick("启用「曜石暗色」主题 (Obsidian Dark)", "Activate Obsidian Dark Theme"), L10n.pick("深邃石墨液态玻璃与冷银折射边缘，沉静专注", "Deep graphite liquid glass with cool silver refraction"), L10n.pick("主题", "Theme"), "moon.stars.fill", .switchTheme(.prismPulse)),
            (["备份", "backup", "webdav", "导出", "云同步", "beifen"], "backup-settings", L10n.pick("打开导出、备份与 WebDAV 云同步", "Open Export, Backup & WebDAV Sync"), L10n.pick("导出 .lucentbackup 归档或同步至 WebDAV 云盘与私有 NAS", "Export .lucentbackup archive or sync via WebDAV"), L10n.pick("备份", "Backup"), "externaldrive.badge.icloud", .openBackupSettings),
            (["快速备份", "立即备份", "quick backup"], "quick-backup", L10n.pick("立即执行快速备份快照", "Run Quick Backup Now"), L10n.pick("已配置 WebDAV 时后台上传云快照，否则导出本地归档", "Uploads WebDAV snapshot if configured, else exports local archive"), L10n.pick("备份", "Backup"), "icloud.and.arrow.up.fill", .quickBackup),
            (["短语", "snippets", "snippet", "快捷短语", "duanyu"], "snippets-settings", L10n.pick("管理快捷短语词库 (Snippets)", "Manage Text Snippets"), L10n.pick("配置 ;date / ;sh / ;uuid / ;clip 等动态展开模板", "Configure ;date / ;sh / ;uuid / ;clip dynamic templates"), L10n.pick("短语", "Snippets"), "text.quote", .openSnippetsSettings),
            (["脚本", "脚本库", "快捷脚本", "scripts", "script", "jiaoben"], "scripts-settings", L10n.pick("管理脚本快捷库 (Quick Scripts)", "Manage Quick Scripts Library"), L10n.pick("编写或同步 Shell / Python / AppleScript / Swift / Node 快捷动作", "Author or sync Shell / Python / AppleScript / Swift / Shebang scripts"), L10n.pick("脚本", "Scripts"), "terminal.fill", .openScriptsSettings),
            (["插件", "plugins", "plugin", "mcp"], "plugins-settings", L10n.pick("打开插件市场与 MCP 扩展中心", "Open Plugin Center & MCP"), L10n.pick("安装精选原生插件、参数配置与 FSEvents 热重载", "Install starter plugins, configure secrets & FSEvents reload"), L10n.pick("插件", "Plugins"), "puzzlepiece.extension.fill", .openPluginsSettings),
            (["mos", "mouse", "鼠标", "滚轮", "平滑", "shubiao", "gunlun"], "mos-toggle", L10n.pick("切换鼠标平滑与滚轮方向", "Toggle Mouse Smooth Scroll & Wheel"), L10n.pick("开启/关闭物理鼠标独立滚轮优化", "Enable or disable physical mouse wheel optimization"), L10n.pick("鼠标", "Mouse"), "computermouse.fill", .toggleMosEnabled),
            (["mos reverse", "反转滚轮", "鼠标反转"], "mos-rev", L10n.pick("切换物理鼠标滚轮反转", "Toggle Physical Mouse Wheel Reversal"), L10n.pick("仅作用于外接鼠标，保留触控板自然滚动", "Reverses external mouse wheels only, keeping trackpad natural"), L10n.pick("鼠标", "Mouse"), "arrow.up.arrow.down", .toggleMosReverse),
            (["mos smooth", "平滑滚动"], "mos-smooth", L10n.pick("切换鼠标 120Hz 平滑滚动", "Toggle 120Hz Smooth Mouse Scroll"), L10n.pick("为物理鼠标滚轮启用高帧率像素插值", "Enable high-FPS pixel interpolation for mouse wheels"), L10n.pick("鼠标", "Mouse"), "waveform.path", .toggleMosSmooth),
            (["mos settings", "鼠标设置"], "mos-settings", L10n.pick("打开鼠标滚轮优化设置", "Open Mouse Wheel Settings"), L10n.pick("配置步长、平滑度、辅助权限与应用排除", "Configure step size, damping, Accessibility & excluded apps"), L10n.pick("鼠标", "Mouse"), "slider.horizontal.3", .openMosSettings),
            (["monitor", "cpu", "ram", "net", "power", "监控", "系统监控", "网速", "功耗", "频率", "脉搏"], "sys-monitor", L10n.pick("切换系统脉搏监控悬浮窗 (⌥M)", "Toggle System Pulse Floating Monitor (⌥M)"), L10n.pick("实时查看 CPU 频率、内存、功耗、网速，支持贴边隐藏与顶部精简展开", "Live CPU, frequency, memory, power & network monitor"), L10n.pick("监控", "Monitor"), "waveform.path.ecg", .toggleSystemMonitor),
            (["network", "traffic", "nettop", "流量", "网络监控", "去向", "连接", "wangluo"], "net-monitor", L10n.pick("打开本机网络流量与去向监控 (⌥N)", "Open Network Traffic Monitor (⌥N)"), L10n.pick("实时查看每个应用的上下行网速、远端 IP 域名与连接状态", "Inspect per-app bandwidth, remote endpoints & socket states"), L10n.pick("流量", "Network"), "network", .openNetworkMonitor),
            (["cache", "clean", "storage", "缓存", "清理缓存", "应用缓存", "huancun"], "app-cache", L10n.pick("打开本应用缓存与存储管理", "Open App Cache & Storage Manager"), L10n.pick("查看并一键清理剪贴板、截图钉屏、抠图与影院转封装缓存", "Inspect and clean temporary caches safely"), L10n.pick("缓存", "Cache"), "internaldrive.fill", .openCacheManager),
            (["memory", "mem", "内存", "释放内存", "gc"], "reclaim-mem", L10n.pick("立即释放空闲内存与子进程", "Free Idle Memory & Subprocesses"), L10n.pick("卸载空闲索引并回收可释放堆内存页", "Unload idle file index & reclaim free heap pages"), L10n.pick("内存", "Memory"), "memorychip", .reclaimMemory),
            (["welcome", "引导", "help"], "welcome", L10n.pick("打开欢迎引导页", "Open Welcome Guide"), L10n.pick("查看全部快捷能力概览", "View quick overview of all features"), L10n.pick("引导", "Guide"), "sparkles", .openWelcome)
        ]
    }
}

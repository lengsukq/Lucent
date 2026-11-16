import LumakeyFoundation; import LumakeySearch; import LumakeyMedia; import LumakeySystem
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
    case openPluginsSettings
    case switchTheme(AppThemeID)
    case cycleTheme
    case switchLanguage(AppLanguageID)
    case cycleLanguage
    case reclaimMemory
    case inspectPort(Int)
    case openVolume(URL)
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
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let base = evaluateBaseConversion(trimmed) { return base }
        return evaluateUnitConversion(trimmed)
    }

    public static func matchCommands(query: String, volumes: [VolumeSummary]) -> [CommandSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.isEmpty {
            return [
                CommandSuggestion(id: "cmd:welcome", score: 420, title: L10n.pick("欢迎使用 流光 Lumakey", "Welcome to Lumakey"), subtitle: L10n.pick("查看全部快捷能力与全局热键指南", "Explore all quick actions & global hotkeys"), badgeLabel: L10n.pick("引导", "Guide"), symbol: "sparkles", command: .openWelcome),
                CommandSuggestion(id: "cmd:everything", score: 410, title: L10n.pick("全盘文件秒搜 (⌥F)", "Instant Disk File Search (⌥F)"), subtitle: L10n.pick("紧凑索引支持 ext: / video: / pic: / path:", "Compact index with ext: / video: / pic: / path: DSL"), badgeLabel: L10n.pick("秒搜", "Files"), symbol: "magnifyingglass", command: .openEverything),
                CommandSuggestion(id: "cmd:clipboard", score: 400, title: L10n.pick("剪贴板历史 (⌥C)", "Clipboard History (⌥C)"), subtitle: L10n.pick("自动记录文本、颜色色值、图片与文件路径", "Captures text, #HEX colors, images & file paths"), badgeLabel: L10n.pick("剪贴板", "Clips"), symbol: "doc.on.clipboard", command: .openClipboard),
                CommandSuggestion(id: "cmd:capture-pin", score: 390, title: L10n.pick("选区截图钉屏 (⌥A)", "Screenshot & Pin (⌥A)"), subtitle: L10n.pick("调用系统截图并悬浮置顶，悬停可 OCR/抠图", "Annotate, pin floating captures, OCR & subject cutout"), badgeLabel: L10n.pick("截图", "Capture"), symbol: "camera.viewfinder", command: .capturePin),
                CommandSuggestion(id: "cmd:workspace", score: 380, title: L10n.pick("双栏文件与外置 NTFS 工作台 · 附加 (⌥E)", "Dual-Pane File & NTFS Workspace (⌥E)"), subtitle: L10n.pick("侧边实时预览、只读看图/播片、NTFS 安全识别", "Live side preview, media player & safe read-only NTFS"), badgeLabel: L10n.pick("附加", "Files"), symbol: "folder.fill", command: .openWorkspace)
            ]
        }

        var items: [CommandSuggestion] = []
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
            ("bili ", "哔哩哔哩", "https://search.bilibili.com/all?keyword=")
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

        let catalog: [(keywords: [String], id: String, title: String, subtitle: String, badge: String, symbol: String, cmd: SystemCommandKind)] = [
            (["lock", "锁屏", "suoping"], "lock", L10n.pick("锁定屏幕", "Lock Screen"), L10n.pick("立即锁定当前 macOS 会话", "Lock the current macOS session immediately"), L10n.pick("系统", "System"), "lock.fill", .lockScreen),
            (["trash", "废纸篓", "feizhilou"], "trash", L10n.pick("打开废纸篓", "Open Trash"), L10n.pick("在访达中查看废纸篓内容", "Reveal Trash in Finder"), L10n.pick("系统", "System"), "trash", .openTrash),
            (["emptytrash", "清空废纸篓"], "emptytrash", L10n.pick("清空废纸篓", "Empty Trash"), L10n.pick("通过系统访达执行清空（需确认）", "Empty Trash via Finder (with confirmation)"), L10n.pick("系统", "System"), "trash.slash.fill", .emptyTrash),
            (["ocr", "识字", "shizi"], "ocr", L10n.pick("截图并离线 OCR 识字 (⌥O)", "Capture & Offline Vision OCR (⌥O)"), L10n.pick("调用 Vision 中英识别并复制", "Recognize CJK/English text offline & copy"), L10n.pick("视觉", "OCR"), "text.viewfinder", .captureOCR),
            (["screenshot", "截图", "jietu", "钉图"], "capture", L10n.pick("选区截图并钉在屏幕 (⌥A)", "Capture, Annotate & Pin (⌥A)"), L10n.pick("悬停工具条支持识别与主体抠图", "Hover toolbar supports OCR & subject cutout"), L10n.pick("截图", "Capture"), "camera.viewfinder", .capturePin),
            (["gif", "录屏", "动图", "record", "luping", "dongtu"], "gif-record", L10n.pick("区域 / 窗口 GIF 动图录制 (⌥G)", "Record Region / Window GIF (⌥G)"), L10n.pick("框选区域或吸附窗口录制高帧率轻量 GIF 并复制", "Capture high-FPS GIF89a and copy to clipboard"), L10n.pick("录屏", "GIF"), "record.circle.fill", .recordGif),
            (["clipboard", "剪贴板", "jianqieban"], "clip", L10n.pick("打开剪贴板历史 (⌥C)", "Open Clipboard History (⌥C)"), L10n.pick("按类型筛选并回车复制", "Filter by category and press Return to copy"), L10n.pick("工具", "Tool"), "doc.on.clipboard.fill", .openClipboard),
            (["files", "workspace", "工作台", "gongzuotai"], "ws", L10n.pick("打开双栏文件工作台 (⌥E)", "Open Dual-Pane File Workspace (⌥E)"), L10n.pick("外置 NTFS 检测与侧边预览", "External NTFS guard & live side preview"), L10n.pick("附加", "Workspace"), "sidebar.squares.left", .openWorkspace),
            (["settings", "设置", "shezhi"], "settings", L10n.pick("流光设置与插件中心 (⌘,)", "Lumakey Settings & Plugins (⌘,)"), L10n.pick("语言、外观、索引目录、MCP 与快捷键", "Language, theme, search scope, MCP & hotkeys"), L10n.pick("设置", "Settings"), "gearshape.fill", .openSettings),
            (["language", "lang", "语言", "切换语言", "多语言", "yuyan"], "cycle-lang", L10n.pick("切换界面语言（简体中文 / English）", "Switch Interface Language (简体中文 / English)"), L10n.pick("在简体中文与英文界面之间即时无感切换", "Instantly switch UI between Simplified Chinese and English"), L10n.pick("语言", "Language"), "globe", .cycleLanguage),
            (["english", "英文", "英语", "yingwen"], "lang-en", L10n.pick("切换为英文界面 (English)", "Switch Language to English"), L10n.pick("将 Lumakey 全部窗口与菜单即时切换为英文", "Switch all Lumakey windows & menus to English"), "EN", "globe", .switchLanguage(.english)),
            (["chinese", "中文", "简体中文", "zhongwen"], "lang-zh", L10n.pick("切换为简体中文界面", "Switch Language to 简体中文"), L10n.pick("将 Lumakey 全部窗口与菜单即时切换为简体中文", "Switch all Lumakey windows & menus to Simplified Chinese"), "ZH", "character.bubble.fill", .switchLanguage(.zhHans)),
            (["theme", "主题", "切换主题", "外观", "zhuti"], "cycle-theme", L10n.pick("切换界面主题（凝霜留白 / 霓彩流光）", "Switch Theme (Pure Frost / Prism Pulse)"), L10n.pick("在纯净磨砂「凝霜留白」与活力光谱「霓彩流光」之间即时切换", "Toggle live between Pure Frost and Prism Pulse"), L10n.pick("主题", "Theme"), "paintpalette.fill", .cycleTheme),
            (["pure frost", "frost", "凝霜", "凝霜留白", "留白", "ningshuang"], "theme-frost", L10n.pick("启用「凝霜留白」主题 (Pure Frost)", "Activate Pure Frost Theme"), L10n.pick("纯净磨砂与克制留白，零背景弥散杂光，清爽耐看", "Clean frosted surface with zero ambient glow"), L10n.pick("主题", "Theme"), "circle.lefthalf.filled", .switchTheme(.pureFrost)),
            (["prism pulse", "prism", "霓彩", "霓彩流光", "极光", "nicai"], "theme-prism", L10n.pick("启用「霓彩流光」主题 (Prism Pulse)", "Activate Prism Pulse Theme"), L10n.pick("活力光谱渐变与通透棱镜高光，灵动鲜明", "Vibrant prism gradients & specular glass highlights"), L10n.pick("主题", "Theme"), "sparkles", .switchTheme(.prismPulse)),
            (["备份", "backup", "webdav", "导出", "云同步", "beifen"], "backup-settings", L10n.pick("打开导出、备份与 WebDAV 云同步", "Open Export, Backup & WebDAV Sync"), L10n.pick("导出 .lumakeybackup 归档或同步至 WebDAV 云盘与私有 NAS", "Export .lumakeybackup archive or sync via WebDAV"), L10n.pick("备份", "Backup"), "externaldrive.badge.icloud", .openBackupSettings),
            (["快速备份", "立即备份", "quick backup"], "quick-backup", L10n.pick("立即执行快速备份快照", "Run Quick Backup Now"), L10n.pick("已配置 WebDAV 时后台上传云快照，否则导出本地归档", "Uploads WebDAV snapshot if configured, else exports local archive"), L10n.pick("备份", "Backup"), "icloud.and.arrow.up.fill", .quickBackup),
            (["短语", "snippets", "snippet", "快捷短语", "duanyu"], "snippets-settings", L10n.pick("管理快捷短语词库 (Snippets)", "Manage Text Snippets"), L10n.pick("配置 ;date / ;sh / ;uuid / ;clip 等动态展开模板", "Configure ;date / ;sh / ;uuid / ;clip dynamic templates"), L10n.pick("短语", "Snippets"), "text.quote", .openSnippetsSettings),
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
        for item in catalog {
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

    private static func evaluateBaseConversion(_ trimmed: String) -> UnitConversionResult? {
        let normalized = trimmed.lowercased()
            .replacingOccurrences(of: " 转 ", with: " to ")
            .replacingOccurrences(of: " in ", with: " to ")
        let parts = normalized.components(separatedBy: " to ")
        guard parts.count == 2 else { return nil }
        let lhs = parts[0].trimmingCharacters(in: .whitespaces)
        let target = parts[1].trimmingCharacters(in: .whitespaces)
        let number: Int64? = lhs.hasPrefix("0x") ? Int64(lhs.dropFirst(2), radix: 16) : Int64(lhs)
        guard let number else { return nil }
        let badge = L10n.pick("进制", "Base")
        switch target {
        case "hex", "16": return UnitConversionResult(expression: trimmed, resultText: "0x" + String(number, radix: 16, uppercase: true), badgeLabel: badge)
        case "bin", "2": return UnitConversionResult(expression: trimmed, resultText: "0b" + String(number, radix: 2), badgeLabel: badge)
        case "oct", "8": return UnitConversionResult(expression: trimmed, resultText: "0o" + String(number, radix: 8), badgeLabel: badge)
        case "dec", "10": return UnitConversionResult(expression: trimmed, resultText: String(number), badgeLabel: badge)
        default: return nil
        }
    }

    private static func evaluateUnitConversion(_ trimmed: String) -> UnitConversionResult? {
        let normalized = trimmed.lowercased()
            .replacingOccurrences(of: " 转 ", with: " to ")
            .replacingOccurrences(of: " in ", with: " to ")
        let parts = normalized.components(separatedBy: " to ")
        guard parts.count == 2 else { return nil }
        let lhsTokens = parts[0].split(whereSeparator: \.isWhitespace).map(String.init)
        guard lhsTokens.count == 2, let value = Double(lhsTokens[0]) else { return nil }
        let u1 = lhsTokens[1], u2 = parts[1].trimmingCharacters(in: .whitespaces)

        if let a = lengthUnit(u1), let b = lengthUnit(u2) {
            return formatMeasurement(Measurement(value: value, unit: a).converted(to: b).value, unitLabel: u2, expr: trimmed)
        }
        if let a = massUnit(u1), let b = massUnit(u2) {
            return formatMeasurement(Measurement(value: value, unit: a).converted(to: b).value, unitLabel: u2, expr: trimmed)
        }
        if let a = dataUnit(u1), let b = dataUnit(u2) {
            return formatMeasurement(Measurement(value: value, unit: a.unit).converted(to: b.unit).value, unitLabel: b.label, expr: trimmed)
        }
        if let a = tempUnit(u1), let b = tempUnit(u2) {
            return formatMeasurement(Measurement(value: value, unit: a.unit).converted(to: b.unit).value, unitLabel: b.label, expr: trimmed)
        }
        return nil
    }

    private static func formatMeasurement(_ val: Double, unitLabel: String, expr: String) -> UnitConversionResult {
        let num = val.rounded() == val && abs(val) < 1e9 ? String(Int64(val)) : String(format: "%.4g", val)
        return UnitConversionResult(expression: expr, resultText: "\(num) \(unitLabel)", badgeLabel: L10n.pick("换算", "Unit"))
    }

    private static func lengthUnit(_ s: String) -> UnitLength? {
        ["km": .kilometers, "m": .meters, "cm": .centimeters, "mm": .millimeters, "mi": .miles, "ft": .feet, "in": .inches][s]
    }
    private static func massUnit(_ s: String) -> UnitMass? {
        ["kg": .kilograms, "g": .grams, "lb": .pounds, "oz": .ounces][s]
    }
    private static func dataUnit(_ s: String) -> (unit: UnitInformationStorage, label: String)? {
        switch s {
        case "tb": (.tebibytes, "TB")
        case "gb": (.gibibytes, "GB")
        case "mb": (.mebibytes, "MB")
        case "kb": (.kibibytes, "KB")
        default: nil
        }
    }
    private static func tempUnit(_ s: String) -> (unit: UnitTemperature, label: String)? {
        switch s {
        case "c", "°c", "摄氏度": (.celsius, "°C")
        case "f", "°f", "华氏度": (.fahrenheit, "°F")
        case "k", "K": (.kelvin, "K")
        default: nil
        }
    }
}

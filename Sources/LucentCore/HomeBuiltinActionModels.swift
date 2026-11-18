import LucentFoundation
import Foundation

public enum HomeBuiltinActionID: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case files, clipboard, screenshotPin, gifRecord, ocr
    case networkMonitor, fileWorkspace, systemPulse, toggleMos, pluginsList
    case scripts, snippets, backupSync, cacheCleanup, reclaimMemory, settingsCenter

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .files: L10n.pick("全盘文件", "All Files")
        case .clipboard: L10n.pick("剪贴板库", "Clipboard")
        case .screenshotPin: L10n.pick("截图钉屏", "Capture & Pin")
        case .gifRecord: L10n.pick("动图录屏", "GIF Recorder")
        case .ocr: L10n.pick("离线识字", "Offline OCR")
        case .networkMonitor: L10n.pick("网络流量", "Network Monitor")
        case .fileWorkspace: L10n.pick("双栏文件台", "File Workspace")
        case .systemPulse: L10n.pick("系统脉搏", "System Pulse")
        case .toggleMos: L10n.pick("鼠标平滑", "Smooth Mouse")
        case .pluginsList: L10n.pick("插件列表", "Plugins")
        case .scripts: L10n.pick("脚本快捷库", "Quick Scripts")
        case .snippets: L10n.pick("快捷短语", "Snippets")
        case .backupSync: L10n.pick("备份同步", "Backup & Sync")
        case .cacheCleanup: L10n.pick("缓存清理", "Cache Cleanup")
        case .reclaimMemory: L10n.pick("释放内存", "Reclaim RAM")
        case .settingsCenter: L10n.pick("设置中心", "Settings")
        }
    }

    public var subtitle: String {
        switch self {
        case .files: L10n.pick("极速检索 / ext:md", "Instant search / ext:md")
        case .clipboard: L10n.pick("历史记录与粘贴", "Clipboard history")
        case .screenshotPin: L10n.pick("选区标注悬浮置顶", "Annotate & pin on screen")
        case .gifRecord: L10n.pick("区域/窗口高帧率 GIF", "Region or window GIF")
        case .ocr: L10n.pick("Vision OCR / 抠图", "Offline OCR & cutout")
        case .networkMonitor: L10n.pick("本机进程 · 远端去向", "Per-process live traffic")
        case .fileWorkspace: L10n.pick("双栏整理与批量重命名", "Dual-pane file manager")
        case .systemPulse: L10n.pick("切换桌面脉搏悬浮窗", "Toggle desktop pulse HUD")
        case .toggleMos: L10n.pick("切换物理鼠标平滑滚轮", "Toggle smooth mouse wheel")
        case .pluginsList: L10n.pick("浏览已装与内置扩展", "Browse enabled plugins")
        case .scripts: L10n.pick("自制脚本与快捷操作", "Custom scripts & quick actions")
        case .snippets: L10n.pick("管理动态短语模板", "Manage text snippets")
        case .backupSync: L10n.pick("加密备份与 WebDAV", "Encrypted backup & WebDAV")
        case .cacheCleanup: L10n.pick("查看与清理应用缓存", "Inspect & clean caches")
        case .reclaimMemory: L10n.pick("立即卸载空闲索引缓存", "Unload idle index & caches")
        case .settingsCenter: L10n.pick("偏好设置与插件中心", "Preferences & MCP center")
        }
    }

    public var symbolName: String {
        switch self {
        case .files: "magnifyingglass"
        case .clipboard: "doc.on.clipboard.fill"
        case .screenshotPin: "camera.viewfinder"
        case .gifRecord: "record.circle.fill"
        case .ocr: "text.viewfinder"
        case .networkMonitor: "network"
        case .fileWorkspace: "sidebar.squares.left"
        case .systemPulse: "waveform.path.ecg"
        case .toggleMos: "computermouse.fill"
        case .pluginsList: "puzzlepiece.extension.fill"
        case .scripts: "terminal.fill"
        case .snippets: "text.quote"
        case .backupSync: "externaldrive.badge.icloud"
        case .cacheCleanup: "internaldrive.fill"
        case .reclaimMemory: "memorychip"
        case .settingsCenter: "gearshape.fill"
        }
    }

    public var defaultAccentColor: String {
        switch self {
        case .files: "cyan"
        case .clipboard, .cacheCleanup: "orange"
        case .screenshotPin, .systemPulse: "mint"
        case .gifRecord: "pink"
        case .ocr, .pluginsList: "purple"
        case .networkMonitor, .backupSync: "blue"
        case .fileWorkspace, .reclaimMemory, .scripts: "teal"
        case .toggleMos, .snippets: "indigo"
        case .settingsCenter: "slate"
        }
    }

    public var defaultHotKeyHint: String? {
        switch self {
        case .files: "⌥F"
        case .clipboard: "⌥C"
        case .screenshotPin: "⌥A"
        case .gifRecord: "⌥G"
        case .ocr: "⌥O"
        case .networkMonitor: "⌥N"
        case .fileWorkspace: "⌥E"
        case .systemPulse: "⌥M"
        case .settingsCenter: "⌘,"
        default: nil
        }
    }
}

public enum HomePluginLaunchBehavior: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case auto, scoped, runInline, openWindow

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .auto: L10n.pick("智能默认", "Smart Default")
        case .scoped: L10n.pick("进入专属列表", "Scoped List")
        case .runInline: L10n.pick("直接内联运行", "Run Inline")
        case .openWindow: L10n.pick("打开独立悬浮窗", "Open Floating Window")
        }
    }
}

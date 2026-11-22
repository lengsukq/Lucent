import LucentFoundation
import Foundation

public enum PluginMode: String, Codable, Sendable, Hashable, CaseIterable {
    case script, view
}

public enum PluginKind: String, Codable, Sendable, Hashable {
    case builtin, external
}

public enum PluginCapability: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case clipboard
    case selection
    case window
    case floatingWindow
    case screenCapture
    case notifications
    case audio
    case ocr
    case everythingSearch
    case displayInfo
    case systemControl
    case fileShelf
    case audioDevices
    case windowControl
    case lumaLinkStatus
    case contextRouter

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .clipboard: L10n.pick("读写剪贴板", "Clipboard Read/Write")
        case .selection: L10n.pick("读取选区与划词翻译", "Selected Text & Auto-Paste")
        case .window: L10n.pick("自定义独立窗口", "Custom Plugin Window")
        case .floatingWindow: L10n.pick("桌面置顶悬浮窗", "Floating Desktop Widget")
        case .screenCapture: L10n.pick("屏幕截图与取色", "Screen Capture & Color Picker")
        case .notifications: L10n.pick("发送系统通知", "System Notifications")
        case .audio: L10n.pick("语音朗读与播放音频", "Speech & Audio Playback")
        case .ocr: L10n.pick("图片文字识别 (OCR)", "Offline Text Recognition (OCR)")
        case .everythingSearch: L10n.pick("搜索本地文件", "Local File Search")
        case .displayInfo: L10n.pick("读取屏幕分辨率", "Display Info")
        case .systemControl: L10n.pick("系统音量与防休眠控制", "System & Screen Shield Control")
        case .fileShelf: L10n.pick("文件中转站", "File Shelf")
        case .audioDevices: L10n.pick("切换默认音频设备", "Switch Default Audio Devices")
        case .windowControl: L10n.pick("控制应用窗口布局", "Window Layout & Workspace Control")
        case .lumaLinkStatus: L10n.pick("读取远程控制状态", "LumaLink Remote Status")
        case .contextRouter: L10n.pick("跨插件联动路由", "Cross-Plugin Routing")
        }
    }

    public var summary: String {
        switch self {
        case .clipboard: L10n.pick("读取最近复制的内容，或帮你把结果自动写回剪贴板", "Read clipboard content or copy plugin results back for you")
        case .selection: L10n.pick("在划词翻译或按下快捷键时读取当前选中的文字（需系统「辅助功能」权限）", "Read highlighted text on screen or paste results back (requires Accessibility)")
        case .window: L10n.pick("允许插件打开独立的自定义交互窗口", "Allow plugin to open custom interactive windows")
        case .floatingWindow: L10n.pick("允许在桌面弹出置顶透明悬浮小挂件", "Allow pinned, translucent desktop widgets")
        case .screenCapture: L10n.pick("在触发截图指令时框选屏幕画面或取色（需系统「屏幕录制」权限）", "Capture screen regions or pick pixel colors when triggered (requires Screen Recording)")
        case .notifications: L10n.pick("在任务完成或倒计时结束时弹出 macOS 右上角横幅提醒", "Post macOS Notification Center banners when tasks finish or alerts fire")
        case .audio: L10n.pick("用于单词/译文语音朗读，或播放提示音效", "Speak words/translations aloud or play alert sounds")
        case .ocr: L10n.pick("离线识别截图或图片里的中英文文字（本地计算，不上传云端）", "Extract text and barcodes from images offline using Apple Vision")
        case .everythingSearch: L10n.pick("查询 Lucent 已建立的本机文件名索引", "Query Lucent's local filename index")
        case .displayInfo: L10n.pick("查看当前连接的显示器数量和屏幕尺寸", "Read connected displays and screen resolutions")
        case .systemControl: L10n.pick("按指令调节系统音量、防休眠或开启清洁防误触遮罩", "Adjust volume, keep awake, or show the screen-cleaning shield")
        case .fileShelf: L10n.pick("打开中转站并放入用户选中的文件", "Open the shelf and add files selected by the user")
        case .audioDevices: L10n.pick("查看并切换系统默认麦克风与扬声器", "Read and switch the system default microphone and speakers")
        case .windowControl: L10n.pick("读取并调整当前桌面应用窗口的位置与尺寸，支持分屏与多屏工作区布局（需系统「辅助功能」权限）", "Inspect and arrange application windows across displays for snapping and workspaces (requires Accessibility)")
        case .lumaLinkStatus: L10n.pick("查看 LumaLink 局域网远程服务状态（不含敏感凭证）", "Read redacted LumaLink remote-control connection status")
        case .contextRouter: L10n.pick("查询支持当前文件/链接/文本的其他已装插件，并经宿主安全转交上下文（不读取其他插件私有数据）", "Discover installed plugins matching files, links, or text and route context through the host without exposing private plugin data")
        }
    }

    public var symbolName: String {
        switch self {
        case .clipboard: "doc.on.clipboard"
        case .selection: "text.cursor"
        case .window: "macwindow"
        case .floatingWindow: "macwindow.on.rectangle"
        case .screenCapture: "viewfinder.rectangular"
        case .notifications: "bell.badge.fill"
        case .audio: "speaker.wave.3.fill"
        case .ocr: "text.viewfinder"
        case .everythingSearch: "magnifyingglass"
        case .displayInfo: "display"
        case .systemControl: "speaker.wave.2.fill"
        case .fileShelf: "tray.full"
        case .audioDevices: "headphones"
        case .windowControl: "rectangle.split.2x2"
        case .lumaLinkStatus: "ipad.and.iphone"
        case .contextRouter: "arrow.triangle.branch"
        }
    }

    public var tccNote: String {
        if let tcc = PluginHostTCCBroker.requiredTCC(for: self) {
            return L10n.pick(
                "需系统「\(tcc.title)」权限（由 Lucent 宿主统一代申） · 默认关闭",
                "Backed by macOS \(tcc.title) (requested by Lucent host) · Off by default"
            )
        }
        return L10n.pick("经宿主容器/桥接隔离管控 · 默认关闭", "Brokered by Lucent host container/bridge · Off by default")
    }
}

public struct BuiltinPluginMetadata: Sendable, Hashable {
    public let categoryBadge: String
    public let requiredPermissions: [LucentPermission]
    public let settingsTarget: String
    public let statusSummary: String

    public var requiredTCCPermissions: [String] { requiredPermissions.map(\.title) }

    public init(
        categoryBadge: String = "BUILTIN",
        requiredPermissions: [LucentPermission],
        settingsTarget: String,
        statusSummary: String
    ) {
        self.categoryBadge = categoryBadge; self.requiredPermissions = requiredPermissions
        self.settingsTarget = settingsTarget; self.statusSummary = statusSummary
    }
}

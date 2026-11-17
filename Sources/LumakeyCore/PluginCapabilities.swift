import LumakeyFoundation; import LumakeySearch; import LumakeyMedia; import LumakeySystem
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
    case lumaLinkStatus

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
        case .lumaLinkStatus: L10n.pick("读取远程控制状态", "LumaLink Remote Status")
        }
    }

    public var summary: String {
        switch self {
        case .clipboard: L10n.pick("读取最近复制的内容，或帮你把结果自动写回剪贴板", "Read clipboard content or copy plugin results back for you")
        case .selection: L10n.pick("在划词翻译或按下快捷键时读取当前选中的文字（需系统「辅助功能」权限）", "Read highlighted text on screen or paste results back (requires Accessibility)")
        case .window: L10n.pick("允许插件打开独立的自定义交互窗口", "Allow plugin to open custom interactive windows")
        case .floatingWindow: L10n.pick("允许在桌面弹出置顶透明小挂件（如 AI 额度监控小窗）", "Allow pinned, translucent desktop widgets (e.g. AI Quota HUD)")
        case .screenCapture: L10n.pick("在触发截图指令时框选屏幕画面或取色（需系统「屏幕录制」权限）", "Capture screen regions or pick pixel colors when triggered (requires Screen Recording)")
        case .notifications: L10n.pick("在任务完成或倒计时结束时弹出 macOS 右上角横幅提醒", "Post macOS Notification Center banners when tasks finish or alerts fire")
        case .audio: L10n.pick("用于单词/译文语音朗读，或播放提示音效", "Speak words/translations aloud or play alert sounds")
        case .ocr: L10n.pick("离线识别截图或图片里的中英文文字（本地计算，不上传云端）", "Extract text and barcodes from images offline using Apple Vision")
        case .everythingSearch: L10n.pick("查询 Lumakey 已建立的本机文件名索引", "Query Lumakey's local filename index")
        case .displayInfo: L10n.pick("查看当前连接的显示器数量和屏幕尺寸", "Read connected displays and screen resolutions")
        case .systemControl: L10n.pick("按指令调节系统音量、防休眠或开启清洁防误触遮罩", "Adjust volume, keep awake, or show the screen-cleaning shield")
        case .lumaLinkStatus: L10n.pick("查看 LumaLink 局域网远程服务状态（不含敏感凭证）", "Read redacted LumaLink remote-control connection status")
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
        case .lumaLinkStatus: "ipad.and.iphone"
        }
    }

    public var tccNote: String {
        if let tcc = PluginHostTCCBroker.requiredTCC(for: self) {
            return L10n.pick(
                "需系统「\(tcc.title)」权限（由 Lumakey 宿主统一代申） · 默认关闭",
                "Backed by macOS \(tcc.title) (requested by Lumakey host) · Off by default"
            )
        }
        return L10n.pick("经宿主容器/桥接隔离管控 · 默认关闭", "Brokered by Lumakey host container/bridge · Off by default")
    }
}

public struct BuiltinPluginMetadata: Sendable, Hashable {
    public let categoryBadge: String
    public let requiredPermissions: [LumakeyPermission]
    public let settingsTarget: String
    public let statusSummary: String

    public var requiredTCCPermissions: [String] { requiredPermissions.map(\.title) }

    public init(
        categoryBadge: String = "BUILTIN",
        requiredPermissions: [LumakeyPermission],
        settingsTarget: String,
        statusSummary: String
    ) {
        self.categoryBadge = categoryBadge; self.requiredPermissions = requiredPermissions
        self.settingsTarget = settingsTarget; self.statusSummary = statusSummary
    }
}

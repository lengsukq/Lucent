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
        case .clipboard: L10n.pick("剪贴板读写", "Clipboard Read/Write")
        case .selection: L10n.pick("划词读取与焦点回填", "Selection & Active Paste-Back")
        case .window: L10n.pick("独立自由窗口画布", "Custom Canvas Window")
        case .floatingWindow: L10n.pick("置顶与无边框自由浮窗", "Pinned & Frameless Floating HUD")
        case .screenCapture: L10n.pick("屏幕截图与取色代理", "Screen Capture & Color Picker")
        case .notifications: L10n.pick("系统通知投递代理", "System Notification Delivery")
        case .audio: L10n.pick("宿主音频与语音朗读", "Host Audio & Speech")
        case .ocr: L10n.pick("离线 Vision OCR", "Offline Vision OCR")
        case .everythingSearch: L10n.pick("全盘文件索引检索", "Disk File Index Search")
        case .displayInfo: L10n.pick("显示器与分辨率信息", "Display & Resolution Info")
        case .systemControl: L10n.pick("系统控制与状态屏", "System & Status Screen Control")
        case .lumaLinkStatus: L10n.pick("LumaLink 远控状态", "LumaLink Status")
        }
    }

    public var summary: String {
        switch self {
        case .clipboard: L10n.pick("通过宿主桥读取剪贴板文本，或将文本/图片写入系统剪贴板", "Read clipboard text or write text/images to macOS pasteboard")
        case .selection: L10n.pick("由宿主代申辅助功能权限，读取前台选中文本或将结果自动粘贴回原窗口", "Read frontmost selected text or auto-paste back via host Accessibility")
        case .window: L10n.pick("允许打开不限 UI 样式的自定义 HTML/CSS/Canvas 独立窗口", "Open unrestricted custom HTML/CSS/Canvas plugin windows")
        case .floatingWindow: L10n.pick("允许打开全局置顶、无边框透明背景、不抢焦点的自由悬浮窗与穿透层", "Open pinned, frameless, transparent HUD floating windows")
        case .screenCapture: L10n.pick("由宿主代申屏幕录制权限，执行交互选区截图、主屏快照与像素取色", "Capture screen regions, display snapshots & pixel colors via host TCC")
        case .notifications: L10n.pick("由宿主代申系统通知权限并投递原生 macOS 横幅提醒", "Request notification access & post native macOS banners via host")
        case .audio: L10n.pick("复用宿主音频引擎播放本地音频文件或执行系统语音朗读", "Play local audio files or run macOS speech synthesis")
        case .ocr: L10n.pick("复用宿主 VisionService 离线识别图片中英文字与条码", "Offline CJK/English OCR & barcode detection via VisionService")
        case .everythingSearch: L10n.pick("复用宿主内存索引按 DSL 极速检索全盘与外置盘文件", "Query the in-memory file index across local & external drives")
        case .displayInfo: L10n.pick("读取活跃显示器列表、当前模式与支持的分辨率", "Inspect active displays, current modes & supported resolutions")
        case .systemControl: L10n.pick("调节系统音量/静音/防休眠与全屏状态屏告示遮罩", "Adjust volume, mute, sleep-prevention & fullscreen status screen shield")
        case .lumaLinkStatus: L10n.pick("读取 LumaLink 监听端口、连接数与 RDP 引擎状态（脱敏）", "Read redacted LumaLink port, connection count & RDP state")
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

import LumakeyFoundation; import LumakeySearch; import LumakeyMedia; import LumakeySystem
import Foundation

public enum PluginMode: String, Codable, Sendable, Hashable, CaseIterable {
    case script, view
}

public enum PluginKind: String, Codable, Sendable, Hashable {
    case builtin, external
}

public enum PluginCapability: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case clipboard, selection, audio, ocr, everythingSearch, displayInfo, systemControl, lumaLinkStatus

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .clipboard: L10n.pick("剪贴板读写", "Clipboard Read/Write")
        case .selection: L10n.pick("跨应用选中文本读取", "Frontmost Text Selection")
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
        case .clipboard: L10n.pick("通过宿主桥读取或写入系统剪贴板文本", "Read or write system clipboard text via Host Bridge")
        case .selection: L10n.pick("复用宿主辅助功能权限读取当前前台应用选中的文本", "Read selected text in the frontmost app via host Accessibility")
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
        case .audio: "speaker.wave.3.fill"
        case .ocr: "text.viewfinder"
        case .everythingSearch: "magnifyingglass"
        case .displayInfo: "display"
        case .systemControl: "speaker.wave.2.fill"
        case .lumaLinkStatus: "ipad.and.iphone"
        }
    }

    public var tccNote: String {
        L10n.pick("经临时 Host Bridge 复用 Lumakey 宿主权限 · 默认关闭", "Reuses Lumakey host permissions via ephemeral Host Bridge · Off by default")
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

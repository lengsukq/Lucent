import Foundation
import LucentFoundation
import LucentMedia
import UniformTypeIdentifiers

public enum CaptureExportFormat: String, CaseIterable, Codable, Identifiable, Sendable {
    case png, jpeg, heic

    public var id: String { rawValue }

    public var displayLabel: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        case .heic: return "HEIC"
        }
    }

    public var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .heic: return "heic"
        }
    }

    public var utType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .heic: return .heic
        }
    }
}

public enum CaptureDoubleClickAction: String, CaseIterable, Codable, Identifiable, Sendable {
    case copyAndFinish
    case pinToScreen

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .copyAndFinish: return L10n.pick("复制到剪贴板并完成", "Copy & Finish")
        case .pinToScreen: return L10n.pick("直接钉到屏幕", "Pin to Screen")
        }
    }
}

public enum ScreenshotToolbarItemID: String, CaseIterable, Codable, Identifiable, Sendable {
    case toolMove = "tool.move"
    case toolRect = "tool.rect"
    case toolEllipse = "tool.ellipse"
    case toolArrow = "tool.arrow"
    case toolLine = "tool.line"
    case toolPen = "tool.pen"
    case toolHighlighter = "tool.highlighter"
    case toolMosaic = "tool.mosaic"
    case toolBlur = "tool.blur"
    case toolSpotlight = "tool.spotlight"
    case toolCounter = "tool.counter"
    case toolText = "tool.text"
    case actionUndoRedo = "action.undoRedo"
    case actionClear = "action.clear"
    case actionLongShot = "action.longShot"
    case actionOCR = "action.ocr"
    case actionCutout = "action.cutout"
    case actionPin = "action.pin"
    case actionSave = "action.save"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .toolMove: return L10n.pick("移动 (V)", "Move (V)")
        case .toolRect: return L10n.pick("矩形 (1)", "Rect (1)")
        case .toolEllipse: return L10n.pick("椭圆 (2)", "Ellipse (2)")
        case .toolArrow: return L10n.pick("箭头 (3)", "Arrow (3)")
        case .toolLine: return L10n.pick("直线 (4)", "Line (4)")
        case .toolPen: return L10n.pick("画笔 (5)", "Pen (5)")
        case .toolHighlighter: return L10n.pick("荧光笔 (6)", "Marker (6)")
        case .toolMosaic: return L10n.pick("马赛克 (7)", "Mosaic (7)")
        case .toolBlur: return L10n.pick("高斯模糊 (B)", "Blur (B)")
        case .toolSpotlight: return L10n.pick("聚光灯 (8)", "Spotlight (8)")
        case .toolCounter: return L10n.pick("序号 (9)", "Step (9)")
        case .toolText: return L10n.pick("文字 (0)", "Text (0)")
        case .actionUndoRedo: return L10n.pick("撤销 / 重做", "Undo / Redo")
        case .actionClear: return L10n.pick("清空标注", "Clear")
        case .actionLongShot: return L10n.pick("长截图 (S)", "Long Shot (S)")
        case .actionOCR: return "OCR (O)"
        case .actionCutout: return L10n.pick("主体抠图", "Cutout")
        case .actionPin: return L10n.pick("钉图 (P)", "Pin (P)")
        case .actionSave: return L10n.pick("保存 (⌘S)", "Save (⌘S)")
        }
    }

    public static func forTool(_ tool: AnnotationToolKind) -> ScreenshotToolbarItemID {
        switch tool {
        case .move: return .toolMove
        case .rect: return .toolRect
        case .ellipse: return .toolEllipse
        case .arrow: return .toolArrow
        case .line: return .toolLine
        case .pen: return .toolPen
        case .highlighter: return .toolHighlighter
        case .mosaic: return .toolMosaic
        case .blur: return .toolBlur
        case .spotlight: return .toolSpotlight
        case .counter: return .toolCounter
        case .text: return .toolText
        }
    }
}

public enum CaptureFileNameFormatter {
    public static let defaultTemplate = "Lucent-{date}_{time}"

    public static func formatBaseName(
        template: String,
        appName: String? = nil,
        date: Date = Date()
    ) -> String {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        let active = trimmed.isEmpty ? defaultTemplate : trimmed
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: date)
        let dateStr = String(format: "%04d-%02d-%02d", comps.year ?? 2026, comps.month ?? 1, comps.day ?? 1)
        let timeStr = String(format: "%02d-%02d-%02d", comps.hour ?? 0, comps.minute ?? 0, comps.second ?? 0)
        let msStr = String(format: "%03d", (comps.nanosecond ?? 0) / 1_000_000)
        let unixMs = String(Int64(date.timeIntervalSince1970 * 1000))
        let safeApp = sanitizeSegment(appName ?? "Screen")

        let expanded = active
            .replacingOccurrences(of: "{date}", with: dateStr)
            .replacingOccurrences(of: "{time}", with: timeStr)
            .replacingOccurrences(of: "{ms}", with: msStr)
            .replacingOccurrences(of: "{unix}", with: unixMs)
            .replacingOccurrences(of: "{app}", with: safeApp)
        let cleaned = sanitizeSegment(expanded)
        return cleaned.isEmpty ? "Lucent-\(dateStr)_\(timeStr)" : cleaned
    }

    public static func uniqueFileURL(
        in directory: URL,
        baseName: String,
        format: CaptureExportFormat,
        overwriteExisting: Bool = false
    ) -> URL {
        let ext = format.fileExtension
        let primary = directory.appendingPathComponent("\(baseName).\(ext)", isDirectory: false)
        if overwriteExisting || !FileManager.default.fileExists(atPath: primary.path) {
            return primary
        }
        for idx in 1...999 {
            let candidate = directory.appendingPathComponent("\(baseName)-\(idx).\(ext)", isDirectory: false)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return directory.appendingPathComponent("\(baseName)-\(UUID().uuidString.prefix(6)).\(ext)", isDirectory: false)
    }

    private static func sanitizeSegment(_ raw: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let filtered = raw.unicodeScalars.map { forbidden.contains($0) ? "-" : Character($0) }
        return String(filtered).trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    }
}

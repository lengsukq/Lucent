import CoreGraphics
import Foundation
import LucentFoundation
import LucentSearch

public enum AnnotationToolKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case move, rect, ellipse, arrow, line, pen, highlighter, mosaic, blur, spotlight, counter, text

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .move: return L10n.pick("移动 (V)", "Move (V)")
        case .rect: return L10n.pick("矩形 (1)", "Rect (1)")
        case .ellipse: return L10n.pick("椭圆 (2)", "Ellipse (2)")
        case .arrow: return L10n.pick("箭头 (3)", "Arrow (3)")
        case .line: return L10n.pick("直线 (4)", "Line (4)")
        case .pen: return L10n.pick("画笔 (5)", "Pen (5)")
        case .highlighter: return L10n.pick("荧光笔 (6)", "Marker (6)")
        case .mosaic: return L10n.pick("马赛克 (7)", "Mosaic (7)")
        case .blur: return L10n.pick("高斯模糊 (B)", "Blur (B)")
        case .spotlight: return L10n.pick("聚光灯 (8)", "Spotlight (8)")
        case .counter: return L10n.pick("序号 (9)", "Step (9)")
        case .text: return L10n.pick("文字 (0)", "Text (0)")
        }
    }

    public var shortTitle: String {
        switch self {
        case .move: return L10n.pick("移动", "Move")
        case .rect: return L10n.pick("矩形", "Rect")
        case .ellipse: return L10n.pick("椭圆", "Ellipse")
        case .arrow: return L10n.pick("箭头", "Arrow")
        case .line: return L10n.pick("直线", "Line")
        case .pen: return L10n.pick("画笔", "Pen")
        case .highlighter: return L10n.pick("荧光笔", "Marker")
        case .mosaic: return L10n.pick("马赛克", "Mosaic")
        case .blur: return L10n.pick("模糊", "Blur")
        case .spotlight: return L10n.pick("聚光灯", "Spotlight")
        case .counter: return L10n.pick("序号", "Step")
        case .text: return L10n.pick("文字", "Text")
        }
    }

    public var shortcutHint: String {
        switch self {
        case .move: return "V"
        case .rect: return "1"
        case .ellipse: return "2"
        case .arrow: return "3"
        case .line: return "4"
        case .pen: return "5"
        case .highlighter: return "6"
        case .mosaic: return "7"
        case .blur: return "B"
        case .spotlight: return "8"
        case .counter: return "9"
        case .text: return "0"
        }
    }

    public var symbolName: String {
        switch self {
        case .move: return "arrow.up.and.down.and.arrow.left.and.right"
        case .rect: return "rectangle"
        case .ellipse: return "circle"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .pen: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .mosaic: return "checkerboard.rectangle"
        case .blur: return "drop.halffull"
        case .spotlight: return "flashlight.on.fill"
        case .counter: return "1.circle"
        case .text: return "textformat"
        }
    }

    public static func fromShortcutKeyCode(_ keyCode: UInt16) -> AnnotationToolKind? {
        switch keyCode {
        case 9, 46: return .move       // V or M
        case 18: return .rect          // 1
        case 19: return .ellipse       // 2
        case 20: return .arrow         // 3
        case 21: return .line          // 4
        case 23: return .pen           // 5
        case 22: return .highlighter   // 6
        case 26: return .mosaic        // 7
        case 11: return .blur          // B
        case 28: return .spotlight     // 8
        case 25: return .counter       // 9
        case 29: return .text          // 0
        default: return nil
        }
    }
}

public enum AnnotationLineStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case solid, dashed, dashDot

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .solid: return L10n.pick("实线", "Solid")
        case .dashed: return L10n.pick("虚线", "Dash")
        case .dashDot: return L10n.pick("点划", "Dash-Dot")
        }
    }

    public func dashPattern(for lineWidth: CGFloat) -> [CGFloat] {
        let unit = max(2.0, lineWidth)
        switch self {
        case .solid: return []
        case .dashed: return [unit * 2.6, unit * 1.6]
        case .dashDot: return [unit * 2.8, unit * 1.4, unit * 0.4, unit * 1.4]
        }
    }
}

public struct AnnotationRGBColor: Codable, Equatable, Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
        self.alpha = min(max(alpha, 0), 1)
    }

    public init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6, let val = UInt32(cleaned, radix: 16) else { return nil }
        self.init(
            red: Double((val >> 16) & 0xFF) / 255.0,
            green: Double((val >> 8) & 0xFF) / 255.0,
            blue: Double(val & 0xFF) / 255.0
        )
    }

    public var hexString: String {
        String(
            format: "#%02X%02X%02X",
            Int(round(red * 255)),
            Int(round(green * 255)),
            Int(round(blue * 255))
        )
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    public var relativeLuminance: Double {
        0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    public static let presets: [AnnotationRGBColor] = [
        AnnotationRGBColor(red: 1.0, green: 0.23, blue: 0.19),
        AnnotationRGBColor(red: 1.0, green: 0.58, blue: 0.0),
        AnnotationRGBColor(red: 1.0, green: 0.80, blue: 0.0),
        AnnotationRGBColor(red: 0.20, green: 0.78, blue: 0.35),
        AnnotationRGBColor(red: 0.0, green: 0.48, blue: 1.0),
        AnnotationRGBColor(red: 1.0, green: 1.0, blue: 1.0)
    ]
}

public struct AnnotationGradientPreset: Codable, Equatable, Hashable, Sendable {
    public let start: AnnotationRGBColor
    public let mid: AnnotationRGBColor
    public let end: AnnotationRGBColor

    public init(start: AnnotationRGBColor, mid: AnnotationRGBColor, end: AnnotationRGBColor) {
        self.start = start
        self.mid = mid
        self.end = end
    }

    public static let presets: [AnnotationGradientPreset] = [
        AnnotationGradientPreset(
            start: AnnotationRGBColor(red: 1.0, green: 0.24, blue: 0.42),
            mid: AnnotationRGBColor(red: 1.0, green: 0.52, blue: 0.24),
            end: AnnotationRGBColor(red: 1.0, green: 0.78, blue: 0.18)
        ),
        AnnotationGradientPreset(
            start: AnnotationRGBColor(red: 0.98, green: 0.62, blue: 0.16),
            mid: AnnotationRGBColor(red: 0.26, green: 0.84, blue: 0.52),
            end: AnnotationRGBColor(red: 0.08, green: 0.72, blue: 0.88)
        ),
        AnnotationGradientPreset(
            start: AnnotationRGBColor(red: 0.08, green: 0.68, blue: 0.96),
            mid: AnnotationRGBColor(red: 0.38, green: 0.46, blue: 1.0),
            end: AnnotationRGBColor(red: 0.76, green: 0.32, blue: 0.98)
        ),
        AnnotationGradientPreset(
            start: AnnotationRGBColor(red: 0.68, green: 0.28, blue: 0.98),
            mid: AnnotationRGBColor(red: 0.96, green: 0.30, blue: 0.66),
            end: AnnotationRGBColor(red: 1.0, green: 0.36, blue: 0.34)
        )
    ]
}

public enum AnnotationStrokeSize: String, CaseIterable, Codable, Identifiable, Sendable {
    case small, medium, large

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .small: return L10n.pick("细", "S")
        case .medium: return L10n.pick("中", "M")
        case .large: return L10n.pick("粗", "L")
        }
    }

    public var lineWidth: CGFloat {
        switch self {
        case .small: return 2.5
        case .medium: return 5.0
        case .large: return 9.0
        }
    }

    public var mosaicBrushRadius: CGFloat {
        switch self {
        case .small: return 10
        case .medium: return 18
        case .large: return 28
        }
    }

    public var fontSize: CGFloat {
        switch self {
        case .small: return 14
        case .medium: return 18
        case .large: return 24
        }
    }
}

public struct ScreenshotAnnotation: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var tool: AnnotationToolKind
    public var color: AnnotationRGBColor
    public var gradient: AnnotationGradientPreset?
    public var strokeSize: AnnotationStrokeSize
    public var customScale: CGFloat
    public var lineStyle: AnnotationLineStyle
    public var isFilled: Bool
    public var cornerRadius: CGFloat
    public var points: [CGPoint]
    public var text: String
    public var counterIndex: Int

    public init(
        id: UUID = UUID(),
        tool: AnnotationToolKind,
        color: AnnotationRGBColor,
        gradient: AnnotationGradientPreset? = nil,
        strokeSize: AnnotationStrokeSize,
        customScale: CGFloat = 1.0,
        lineStyle: AnnotationLineStyle = .solid,
        isFilled: Bool = false,
        cornerRadius: CGFloat = 0,
        points: [CGPoint],
        text: String = "",
        counterIndex: Int = 1
    ) {
        self.id = id
        self.tool = tool
        self.color = color
        self.gradient = gradient
        self.strokeSize = strokeSize
        self.customScale = min(max(customScale, 0.4), 3.5)
        self.lineStyle = lineStyle
        self.isFilled = isFilled
        self.cornerRadius = max(0, cornerRadius)
        self.points = points
        self.text = text
        self.counterIndex = counterIndex
    }

    public var effectiveLineWidth: CGFloat { max(1.2, strokeSize.lineWidth * customScale) }
    public var effectiveFontSize: CGFloat { min(max(10, strokeSize.fontSize * customScale), 72) }
    public var effectiveMosaicRadius: CGFloat { min(max(6, strokeSize.mosaicBrushRadius * customScale), 56) }
    public var effectiveBlurRadius: CGFloat { min(max(6, 14 * customScale), 42) }
    public var effectiveCounterRadius: CGFloat { min(max(10, (12 + strokeSize.lineWidth * 0.4) * customScale), 34) }
}

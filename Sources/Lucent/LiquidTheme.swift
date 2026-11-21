import AppKit
import LucentCore
import SwiftUI

enum LiquidRadii {
    static let panel: CGFloat = 28
    static let windowPanel: CGFloat = 24
    static let bento: CGFloat = 22
    static let searchBar: CGFloat = 20
    static let card: CGFloat = 18
    static let row: CGFloat = 14
    static let control: CGFloat = 12
    static let pill: CGFloat = 10
}

enum LiquidMotion {
    static var pressSpring: Animation {
        SystemDisplayPreferences.shared.reduceMotion
            ? .linear(duration: 0.01)
            : .spring(response: 0.21, dampingFraction: 0.80)
    }
}

enum LiquidColors {
    static var isPrism: Bool { ThemeManager.currentSnapshot == .prismPulse }
    static var isDark: Bool { ThemeManager.resolvedIsDarkSnapshot }

    private static func srgb(_ hex: UInt32, alpha: CGFloat = 1.0) -> NSColor {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        return NSColor(srgbRed: r, green: g, blue: b, alpha: alpha)
    }

    static var primaryNSColor: NSColor {
        dynamicColor(name: "LucentTextPrimary", light: srgb(0x1D1D1F), dark: srgb(0xF5F5F7))
    }

    static var secondaryNSColor: NSColor {
        dynamicColor(name: "LucentTextSecondary", light: srgb(0x48484F), dark: srgb(0xAEAEB2))
    }

    static var placeholderNSColor: NSColor {
        dynamicColor(
            name: "LucentPlaceholder",
            light: srgb(0x63636A, alpha: 0.85),
            dark: srgb(0x98989F, alpha: 0.80)
        )
    }

    static var textPrimary: Color { Color(nsColor: primaryNSColor) }
    static var textSecondary: Color { Color(nsColor: secondaryNSColor) }
    static var textTertiary: Color { textSecondary.opacity(0.74) }

    static var accentPrimary: Color {
        Color(nsColor: dynamicColor(
            name: "LucentAccentPrimary",
            light: srgb(0x0071E3),
            dark: srgb(0x0A84FF)
        ))
    }

    static var accentShadowColor: Color {
        Color(nsColor: dynamicColor(
            name: "LucentAccentShadow",
            light: srgb(0x0071E3, alpha: 0.20),
            dark: srgb(0x0A84FF, alpha: 0.30)
        ))
    }

    static var canvasBase: Color {
        Color(nsColor: dynamicColor(
            name: "LucentCanvasBase",
            light: srgb(0xF5F5F7),
            dark: srgb(0x141417)
        ))
    }

    static var solidCardSurface: Color {
        Color(nsColor: dynamicColor(
            name: "LucentSolidCard",
            light: srgb(0xFFFFFF),
            dark: srgb(0x222226)
        ))
    }

    static var shellTint: Color {
        Color(nsColor: dynamicColor(
            name: "LucentShellTint",
            light: NSColor.white.withAlphaComponent(0.68),
            dark: srgb(0x1A1A1E, alpha: 0.58)
        ))
    }

    static var cardSurface: Color {
        Color(nsColor: dynamicColor(
            name: "LucentCardSurface",
            light: NSColor.white.withAlphaComponent(0.88),
            dark: srgb(0x242428, alpha: 0.66)
        ))
    }

    static var elevatedSurface: Color {
        Color(nsColor: dynamicColor(
            name: "LucentElevatedSurface",
            light: NSColor.white.withAlphaComponent(0.96),
            dark: srgb(0x2E2E33, alpha: 0.82)
        ))
    }

    static var inputFieldSurface: Color {
        Color(nsColor: dynamicColor(
            name: "LucentInputSurface",
            light: NSColor.white.withAlphaComponent(0.92),
            dark: srgb(0x18181C, alpha: 0.76)
        ))
    }

    static var inputFieldBorder: Color {
        Color(nsColor: dynamicColor(
            name: "LucentInputBorder",
            light: NSColor.black.withAlphaComponent(0.10),
            dark: NSColor.white.withAlphaComponent(0.16)
        ))
    }

    static var pillSurface: Color {
        Color(nsColor: dynamicColor(
            name: "LucentPillSurface",
            light: NSColor.black.withAlphaComponent(0.05),
            dark: NSColor.white.withAlphaComponent(0.085)
        ))
    }

    static var pillBorder: Color {
        Color(nsColor: dynamicColor(
            name: "LucentPillBorder",
            light: NSColor.black.withAlphaComponent(0.09),
            dark: NSColor.white.withAlphaComponent(0.15)
        ))
    }

    static var subtleRim: Color {
        Color(nsColor: dynamicColor(
            name: "LucentSubtleRim",
            light: NSColor.black.withAlphaComponent(0.14),
            dark: NSColor.white.withAlphaComponent(0.22)
        ))
    }

    static var highlightGlow: Color {
        Color(nsColor: dynamicColor(
            name: "LucentHighlightGlow",
            light: srgb(0x0071E3, alpha: 0.12),
            dark: srgb(0x0A84FF, alpha: 0.24)
        ))
    }

    static var selectedRowFill: Color {
        Color(nsColor: dynamicColor(
            name: "LucentSelectedRowFill",
            light: srgb(0x0071E3, alpha: 0.11),
            dark: srgb(0x0A84FF, alpha: 0.22)
        ))
    }

    static var specularRimGradient: LinearGradient {
        let top = Color(nsColor: dynamicColor(
            name: "LucentShellRimTop",
            light: NSColor.white.withAlphaComponent(0.92),
            dark: NSColor.white.withAlphaComponent(0.32)
        ))
        let mid = Color(nsColor: dynamicColor(
            name: "LucentShellRimMid",
            light: NSColor.black.withAlphaComponent(0.08),
            dark: srgb(0xB8DCFF, alpha: 0.15)
        ))
        let bottom = Color(nsColor: dynamicColor(
            name: "LucentShellRimBot",
            light: NSColor.black.withAlphaComponent(0.13),
            dark: NSColor.white.withAlphaComponent(0.10)
        ))
        return LinearGradient(colors: [top, mid, bottom], startPoint: .top, endPoint: .bottom)
    }

    static var softCardRimGradient: LinearGradient {
        let top = Color(nsColor: dynamicColor(
            name: "LucentCardRimTop",
            light: NSColor.white.withAlphaComponent(0.86),
            dark: NSColor.white.withAlphaComponent(0.24)
        ))
        let bottom = Color(nsColor: dynamicColor(
            name: "LucentCardRimBot",
            light: NSColor.black.withAlphaComponent(0.095),
            dark: NSColor.white.withAlphaComponent(0.09)
        ))
        return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }

    static var hoverCardRimGradient: LinearGradient {
        let top = Color(nsColor: dynamicColor(
            name: "LucentHoverRimTop",
            light: srgb(0x0071E3, alpha: 0.34),
            dark: NSColor.white.withAlphaComponent(0.36)
        ))
        let bottom = Color(nsColor: dynamicColor(
            name: "LucentHoverRimBot",
            light: srgb(0x0071E3, alpha: 0.16),
            dark: srgb(0x0A84FF, alpha: 0.26)
        ))
        return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }

    static var selectedRowRimGradient: LinearGradient {
        let top = Color(nsColor: dynamicColor(
            name: "LucentRowRimTop",
            light: srgb(0x0071E3, alpha: 0.44),
            dark: srgb(0x0A84FF, alpha: 0.58)
        ))
        let bottom = Color(nsColor: dynamicColor(
            name: "LucentRowRimBot",
            light: srgb(0x0071E3, alpha: 0.22),
            dark: srgb(0x0A84FF, alpha: 0.28)
        ))
        return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }

    static var accentGradient: LinearGradient {
        let top = Color(nsColor: dynamicColor(
            name: "LucentAccentGradTop",
            light: srgb(0x0A7CF0),
            dark: srgb(0x1484FF)
        ))
        let bottom = Color(nsColor: dynamicColor(
            name: "LucentAccentGradBot",
            light: srgb(0x0066D6),
            dark: srgb(0x006FE0)
        ))
        return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }

    static var specularTopSheen: LinearGradient {
        let top = Color(nsColor: dynamicColor(
            name: "LucentTopSheen",
            light: NSColor.white.withAlphaComponent(0.32),
            dark: NSColor.white.withAlphaComponent(0.09)
        ))
        return LinearGradient(colors: [top, .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.38))
    }

    static func dynamicColor(name: String, light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: NSColor.Name(name)) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
    }

    static func color(fromHex hex: String) -> Color? {
        guard let c = rgbComponents(fromHex: hex) else { return nil }
        return Color(.sRGB, red: Double(c.r) / 255.0, green: Double(c.g) / 255.0, blue: Double(c.b) / 255.0, opacity: 1.0)
    }

    static func rgbComponents(fromHex hex: String) -> (r: Int, g: Int, b: Int, luminance: Double)? {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        let r = Int((value >> 16) & 0xFF), g = Int((value >> 8) & 0xFF), b = Int(value & 0xFF)
        let lum = (0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)) / 255.0
        return (r, g, b, lum)
    }
}

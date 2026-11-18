import AppKit
import LucentCore
import SwiftUI

enum LiquidRadii {
    private static var isPrism: Bool { ThemeManager.currentSnapshot == .prismPulse }

    static var panel: CGFloat { isPrism ? 28 : 24 }
    static var windowPanel: CGFloat { isPrism ? 24 : 20 }
    static var bento: CGFloat { isPrism ? 22 : 16 }
    static var searchBar: CGFloat { isPrism ? 22 : 16 }
    static var card: CGFloat { isPrism ? 18 : 14 }
    static var row: CGFloat { isPrism ? 14 : 11 }
    static var control: CGFloat { isPrism ? 12 : 10 }
    static var pill: CGFloat { isPrism ? 10 : 8 }
}

enum LiquidMotion {
    static var pressSpring: Animation {
        ThemeManager.currentSnapshot == .prismPulse
            ? Animation.spring(response: 0.23, dampingFraction: 0.70)
            : Animation.spring(response: 0.20, dampingFraction: 0.86)
    }
}

enum LiquidColors {
    static var isPrism: Bool { ThemeManager.currentSnapshot == .prismPulse }

    static var primaryNSColor: NSColor {
        isPrism
            ? dynamicColor(
                name: "LumaPrismTextPrimary",
                light: NSColor(srgbRed: 0.08, green: 0.07, blue: 0.18, alpha: 1.0),
                dark: NSColor(srgbRed: 0.98, green: 0.98, blue: 1.0, alpha: 1.0)
            )
            : dynamicColor(
                name: "LumaFrostTextPrimary",
                light: NSColor(srgbRed: 0.07, green: 0.08, blue: 0.11, alpha: 1.0),
                dark: NSColor(srgbRed: 0.95, green: 0.96, blue: 0.98, alpha: 1.0)
            )
    }

    static var secondaryNSColor: NSColor {
        isPrism
            ? dynamicColor(
                name: "LumaPrismTextSecondary",
                light: NSColor(srgbRed: 0.26, green: 0.24, blue: 0.42, alpha: 0.95),
                dark: NSColor(srgbRed: 0.82, green: 0.84, blue: 0.95, alpha: 0.94)
            )
            : dynamicColor(
                name: "LumaFrostTextSecondary",
                light: NSColor(srgbRed: 0.32, green: 0.35, blue: 0.40, alpha: 0.94),
                dark: NSColor(srgbRed: 0.72, green: 0.75, blue: 0.80, alpha: 0.92)
            )
    }

    static var placeholderNSColor: NSColor {
        isPrism
            ? dynamicColor(
                name: "LumaPrismPlaceholder",
                light: NSColor(srgbRed: 0.34, green: 0.31, blue: 0.52, alpha: 0.82),
                dark: NSColor(srgbRed: 0.78, green: 0.80, blue: 0.94, alpha: 0.76)
            )
            : dynamicColor(
                name: "LumaFrostPlaceholder",
                light: NSColor(srgbRed: 0.44, green: 0.47, blue: 0.52, alpha: 0.82),
                dark: NSColor(srgbRed: 0.62, green: 0.65, blue: 0.70, alpha: 0.74)
            )
    }

    static var textPrimary: Color { Color(nsColor: primaryNSColor) }
    static var textSecondary: Color { Color(nsColor: secondaryNSColor) }
    static var textTertiary: Color { textSecondary.opacity(0.72) }

    static var accentPrimary: Color {
        isPrism
            ? Color(red: 0.44, green: 0.42, blue: 0.98)
            : Color(nsColor: dynamicColor(
                name: "LumaFrostAccent",
                light: NSColor(srgbRed: 0.0, green: 0.478, blue: 1.0, alpha: 1.0),
                dark: NSColor(srgbRed: 0.24, green: 0.60, blue: 1.0, alpha: 1.0)
            ))
    }

    static var accentShadowColor: Color {
        isPrism ? Color(red: 0.52, green: 0.36, blue: 0.98).opacity(0.28) : Color.black.opacity(0.08)
    }

    static var canvasBase: Color {
        isPrism
            ? Color(nsColor: dynamicColor(
                name: "LumaPrismCanvas",
                light: NSColor(calibratedRed: 0.965, green: 0.955, blue: 1.0, alpha: 1),
                dark: NSColor(calibratedRed: 0.075, green: 0.068, blue: 0.145, alpha: 1)
            ))
            : Color(nsColor: dynamicColor(
                name: "LumaFrostCanvas",
                light: NSColor(calibratedRed: 0.965, green: 0.968, blue: 0.976, alpha: 1),
                dark: NSColor(calibratedRed: 0.11, green: 0.115, blue: 0.128, alpha: 1)
            ))
    }

    static var solidCardSurface: Color {
        isPrism
            ? Color(nsColor: dynamicColor(
                name: "LumaPrismSolid",
                light: NSColor(calibratedRed: 0.975, green: 0.968, blue: 1.0, alpha: 0.96),
                dark: NSColor(calibratedRed: 0.135, green: 0.125, blue: 0.225, alpha: 0.95)
            ))
            : Color(nsColor: dynamicColor(
                name: "LumaFrostSolid",
                light: NSColor(calibratedWhite: 0.995, alpha: 0.97),
                dark: NSColor(calibratedRed: 0.155, green: 0.16, blue: 0.178, alpha: 0.96)
            ))
    }

    static var shellTint: Color {
        isPrism
            ? Color(nsColor: dynamicColor(
                name: "LumaPrismShell",
                light: NSColor(calibratedRed: 0.98, green: 0.965, blue: 1.0, alpha: 0.54),
                dark: NSColor(calibratedRed: 0.085, green: 0.075, blue: 0.17, alpha: 0.50)
            ))
            : Color(nsColor: dynamicColor(
                name: "LumaFrostShell",
                light: NSColor(calibratedWhite: 0.99, alpha: 0.78),
                dark: NSColor(calibratedRed: 0.12, green: 0.125, blue: 0.14, alpha: 0.72)
            ))
    }

    static var cardSurface: Color {
        isPrism
            ? Color(nsColor: dynamicColor(
                name: "LumaPrismCard",
                light: NSColor(calibratedWhite: 1.0, alpha: 0.56),
                dark: NSColor(calibratedRed: 0.15, green: 0.14, blue: 0.25, alpha: 0.46)
            ))
            : Color(nsColor: dynamicColor(
                name: "LumaFrostCard",
                light: NSColor(calibratedWhite: 1.0, alpha: 0.84),
                dark: NSColor(calibratedRed: 0.17, green: 0.175, blue: 0.195, alpha: 0.66)
            ))
    }

    static var elevatedSurface: Color {
        isPrism
            ? Color(nsColor: dynamicColor(
                name: "LumaPrismElevated",
                light: NSColor(calibratedWhite: 1.0, alpha: 0.74),
                dark: NSColor(calibratedRed: 0.18, green: 0.17, blue: 0.29, alpha: 0.58)
            ))
            : Color(nsColor: dynamicColor(
                name: "LumaFrostElevated",
                light: NSColor(calibratedWhite: 1.0, alpha: 0.92),
                dark: NSColor(calibratedRed: 0.20, green: 0.208, blue: 0.23, alpha: 0.78)
            ))
    }

    static var inputFieldSurface: Color {
        isPrism
            ? Color(nsColor: dynamicColor(
                name: "LumaPrismInput",
                light: NSColor(calibratedWhite: 1.0, alpha: 0.72),
                dark: NSColor(calibratedRed: 0.11, green: 0.10, blue: 0.20, alpha: 0.64)
            ))
            : Color(nsColor: dynamicColor(
                name: "LumaFrostInput",
                light: NSColor(calibratedWhite: 1.0, alpha: 0.90),
                dark: NSColor(calibratedRed: 0.14, green: 0.145, blue: 0.165, alpha: 0.80)
            ))
    }

    static var inputFieldBorder: Color {
        isPrism
            ? Color(nsColor: dynamicColor(name: "LumaPrismInputBorder", light: NSColor.systemIndigo.withAlphaComponent(0.18), dark: NSColor.white.withAlphaComponent(0.24)))
            : Color(nsColor: dynamicColor(name: "LumaFrostInputBorder", light: NSColor.black.withAlphaComponent(0.09), dark: NSColor.white.withAlphaComponent(0.15)))
    }

    static var pillSurface: Color {
        isPrism
            ? Color(nsColor: dynamicColor(name: "LumaPrismPill", light: NSColor.systemIndigo.withAlphaComponent(0.065), dark: NSColor.white.withAlphaComponent(0.12)))
            : Color(nsColor: dynamicColor(name: "LumaFrostPill", light: NSColor.black.withAlphaComponent(0.048), dark: NSColor.white.withAlphaComponent(0.095)))
    }

    static var pillBorder: Color {
        isPrism
            ? Color(nsColor: dynamicColor(name: "LumaPrismPillBorder", light: NSColor.systemPurple.withAlphaComponent(0.16), dark: NSColor.white.withAlphaComponent(0.22)))
            : Color(nsColor: dynamicColor(name: "LumaFrostPillBorder", light: NSColor.black.withAlphaComponent(0.085), dark: NSColor.white.withAlphaComponent(0.14)))
    }

    static var subtleRim: Color {
        Color(nsColor: dynamicColor(name: "LumaSubtleRim", light: NSColor.black.withAlphaComponent(0.12), dark: NSColor.white.withAlphaComponent(0.20)))
    }

    static var highlightGlow: Color {
        isPrism
            ? Color(nsColor: dynamicColor(name: "LumaPrismGlow", light: NSColor.systemPurple.withAlphaComponent(0.15), dark: NSColor.systemPink.withAlphaComponent(0.24)))
            : Color(nsColor: dynamicColor(name: "LumaFrostGlow", light: NSColor.systemBlue.withAlphaComponent(0.11), dark: NSColor.systemBlue.withAlphaComponent(0.22)))
    }

    static var selectedRowFill: Color {
        isPrism
            ? Color(nsColor: dynamicColor(
                name: "LumaPrismRowFill",
                light: NSColor(calibratedRed: 0.92, green: 0.90, blue: 1.0, alpha: 0.82),
                dark: NSColor(calibratedRed: 0.28, green: 0.20, blue: 0.48, alpha: 0.44)
            ))
            : Color(nsColor: dynamicColor(
                name: "LumaFrostRowFill",
                light: NSColor(calibratedRed: 0.89, green: 0.94, blue: 1.0, alpha: 0.86),
                dark: NSColor(calibratedRed: 0.16, green: 0.29, blue: 0.48, alpha: 0.42)
            ))
    }

    static var specularRimGradient: LinearGradient {
        let top = Color(nsColor: isPrism
            ? dynamicColor(name: "LumaPrismShellRimTop", light: NSColor.systemIndigo.withAlphaComponent(0.20), dark: NSColor.white.withAlphaComponent(0.32))
            : dynamicColor(name: "LumaFrostShellRimTop", light: NSColor.black.withAlphaComponent(0.10), dark: NSColor.white.withAlphaComponent(0.20)))
        let bottom = Color(nsColor: isPrism
            ? dynamicColor(name: "LumaPrismShellRimBot", light: NSColor.systemPurple.withAlphaComponent(0.23), dark: NSColor(srgbRed: 0.68, green: 0.66, blue: 1.0, alpha: 0.22))
            : dynamicColor(name: "LumaFrostShellRimBot", light: NSColor.black.withAlphaComponent(0.13), dark: NSColor.white.withAlphaComponent(0.12)))
        return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }

    static var softCardRimGradient: LinearGradient {
        let top = Color(nsColor: isPrism
            ? dynamicColor(name: "LumaPrismCardRimTop", light: NSColor.systemIndigo.withAlphaComponent(0.16), dark: NSColor.white.withAlphaComponent(0.24))
            : dynamicColor(name: "LumaFrostCardRimTop", light: NSColor.black.withAlphaComponent(0.08), dark: NSColor.white.withAlphaComponent(0.15)))
        let bottom = Color(nsColor: isPrism
            ? dynamicColor(name: "LumaPrismCardRimBot", light: NSColor.systemPurple.withAlphaComponent(0.19), dark: NSColor(srgbRed: 0.58, green: 0.72, blue: 1.0, alpha: 0.18))
            : dynamicColor(name: "LumaFrostCardRimBot", light: NSColor.black.withAlphaComponent(0.105), dark: NSColor.white.withAlphaComponent(0.11)))
        return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }

    static var hoverCardRimGradient: LinearGradient {
        let top = Color(nsColor: isPrism
            ? dynamicColor(name: "LumaPrismHoverRimTop", light: NSColor.systemIndigo.withAlphaComponent(0.36), dark: NSColor.white.withAlphaComponent(0.38))
            : dynamicColor(name: "LumaFrostHoverRimTop", light: NSColor.systemBlue.withAlphaComponent(0.34), dark: NSColor.white.withAlphaComponent(0.30)))
        let bottom = accentPrimary.opacity(0.28)
        return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }

    static var selectedRowRimGradient: LinearGradient {
        isPrism
            ? LinearGradient(colors: [.cyan.opacity(0.54), .purple.opacity(0.44)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [accentPrimary.opacity(0.42), accentPrimary.opacity(0.26)], startPoint: .top, endPoint: .bottom)
    }

    static var accentGradient: LinearGradient {
        isPrism
            ? LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.80, blue: 0.98),
                    Color(red: 0.48, green: 0.36, blue: 0.99),
                    Color(red: 0.98, green: 0.36, blue: 0.62)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            : LinearGradient(
                colors: [Color(red: 0.04, green: 0.52, blue: 1.0), Color(red: 0.0, green: 0.42, blue: 0.92)],
                startPoint: .top, endPoint: .bottom
            )
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

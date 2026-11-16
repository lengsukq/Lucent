import AppKit
import LumakeyCore
import SwiftUI

extension IconCache {
    func pluginIcon(for url: URL, pointSize: CGFloat = 32) -> NSImage? {
        let bucket = Int(pointSize.rounded())
        let key = "plugicon:\(bucket):\(url.standardizedFileURL.path)" as NSString
        if let cached = customPluginCache.object(forKey: key) {
            return cached
        }
        guard let raw = NSImage(contentsOf: url) else { return nil }
        raw.size = NSSize(width: pointSize, height: pointSize)
        customPluginCache.setObject(raw, forKey: key)
        return raw
    }

    private static let pluginImageCache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 128
        return c
    }()

    private var customPluginCache: NSCache<NSString, NSImage> {
        Self.pluginImageCache
    }
}

enum PluginVisualPalette {
    static func colors(accentColor: String?, isBuiltin: Bool, mode: PluginMode = .view) -> (top: Color, bottom: Color) {
        if let raw = accentColor?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            switch raw.lowercased() {
            case "cyan", "sky": return (.cyan, .blue)
            case "blue": return (.blue, .indigo)
            case "indigo": return (.indigo, .purple)
            case "purple", "violet": return (.purple, .indigo)
            case "mint": return (.mint, .teal)
            case "teal": return (.teal, .blue)
            case "green", "emerald": return (.green, .teal)
            case "orange", "amber": return (.orange, .pink)
            case "pink", "rose": return (.pink, .purple)
            case "red": return (.red, .orange)
            case "slate", "gray", "neutral": return (Color(white: 0.42), Color(white: 0.24))
            default:
                if let hexColor = LiquidColors.color(fromHex: raw) {
                    return (hexColor, hexColor.opacity(0.78))
                }
            }
        }
        if isBuiltin { return (.cyan, .blue) }
        return mode == .view ? (.teal, .indigo) : (.indigo, .blue)
    }

    static func tint(from raw: String?, fallback: Color = .cyan) -> Color {
        guard let cleaned = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !cleaned.isEmpty else {
            return fallback
        }
        return colors(accentColor: cleaned, isBuiltin: false).top
    }
}

struct PluginIconBadge: View {
    let symbol: String
    var customIconURL: URL? = nil
    var accentColor: String? = nil
    var isBuiltin: Bool = false
    var mode: PluginMode = .view
    var size: CGFloat = 32
    @ObservedObject private var themeManager = ThemeManager.shared

    init(plugin: PluginDescriptor, size: CGFloat = 32) {
        self.symbol = plugin.symbolIconName
        self.customIconURL = plugin.customIconURL
        self.accentColor = plugin.manifest.accentColor
        self.isBuiltin = plugin.isBuiltin
        self.mode = plugin.manifest.mode
        self.size = size
    }

    init(
        symbol: String,
        customIconURL: URL? = nil,
        accentColor: String? = nil,
        isBuiltin: Bool = false,
        mode: PluginMode = .view,
        size: CGFloat = 32
    ) {
        self.symbol = symbol
        self.customIconURL = customIconURL
        self.accentColor = accentColor
        self.isBuiltin = isBuiltin
        self.mode = mode
        self.size = size
    }

    var body: some View {
        if let url = customIconURL, let nsImg = IconCache.shared.pluginIcon(for: url, pointSize: size) {
            let ratio: CGFloat = themeManager.current == .prismPulse ? 0.31 : 0.25
            let shape = RoundedRectangle(cornerRadius: size * ratio, style: .continuous)
            ZStack {
                shape.fill(LiquidColors.elevatedSurface)
                Image(nsImage: nsImg)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size * 0.76, height: size * 0.76)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
            }
            .frame(width: size, height: size)
            .overlay { shape.strokeBorder(LiquidColors.softCardRimGradient, lineWidth: 0.85) }
            .shadow(color: .black.opacity(0.12), radius: 3, y: 1.5)
        } else {
            let pair = PluginVisualPalette.colors(accentColor: accentColor, isBuiltin: isBuiltin, mode: mode)
            SquircleBadge(symbol: symbol, topColor: pair.top, bottomColor: pair.bottom, size: size)
        }
    }
}

struct PluginItemLeadingBadge: View {
    let rawIcon: String?
    var tintColor: String? = nil
    var bundleDirectory: URL? = nil
    var dataDirectory: URL? = nil
    var size: CGFloat = 26

    var body: some View {
        let resolvedURL = PluginIconResolver.resolveItemIconURL(
            rawIcon: rawIcon, bundleDirectory: bundleDirectory, dataDirectory: dataDirectory
        )
        let tint = PluginVisualPalette.tint(from: tintColor, fallback: .cyan)
        let shape = RoundedRectangle(cornerRadius: max(7, size * 0.28), style: .continuous)

        if let url = resolvedURL, let nsImg = IconCache.shared.pluginIcon(for: url, pointSize: size) {
            ZStack {
                shape.fill(LiquidColors.pillSurface)
                Image(nsImage: nsImg)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size * 0.74, height: size * 0.74)
            }
            .frame(width: size, height: size)
            .overlay { shape.strokeBorder(LiquidColors.pillBorder, lineWidth: 0.65) }
        } else if let hex = tintColor, LiquidColors.color(fromHex: hex) != nil, (rawIcon == nil || rawIcon?.isEmpty == true) {
            shape.fill(tint)
                .frame(width: size, height: size)
                .overlay { shape.strokeBorder(.white.opacity(0.45), lineWidth: 0.75) }
        } else {
            let sym = (rawIcon?.isEmpty == false && !PluginIconResolver.looksLikeRelativeFilePath(rawIcon))
                ? (rawIcon ?? "sparkles")
                : "sparkles"
            Image(systemName: sym)
                .font(.system(size: size * 0.50, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(tint.opacity(0.12), in: shape)
                .overlay { shape.strokeBorder(tint.opacity(0.24), lineWidth: 0.65) }
        }
    }
}

import Foundation

public enum PluginWindowChromeStyle: String, Codable, Sendable, Hashable, CaseIterable {
    case standard, frameless, hud
}

public struct PluginManifestWindowDefaults: Codable, Sendable, Hashable, Equatable {
    public let entryHtml: String?
    public let title: String?
    public let width: Int?
    public let height: Int?
    public let minWidth: Int?
    public let minHeight: Int?
    public let resizable: Bool?
    public let chrome: PluginWindowChromeStyle?
    public let transparent: Bool?
    public let pinOnTop: Bool?
    public let clickThrough: Bool?
    public let showInDock: Bool?
    public let opacity: Double?

    public init(
        entryHtml: String? = nil, title: String? = nil, width: Int? = nil, height: Int? = nil,
        minWidth: Int? = nil, minHeight: Int? = nil, resizable: Bool? = nil,
        chrome: PluginWindowChromeStyle? = nil, transparent: Bool? = nil,
        pinOnTop: Bool? = nil, clickThrough: Bool? = nil, showInDock: Bool? = nil, opacity: Double? = nil
    ) {
        self.entryHtml = entryHtml; self.title = title; self.width = width; self.height = height
        self.minWidth = minWidth; self.minHeight = minHeight; self.resizable = resizable
        self.chrome = chrome; self.transparent = transparent; self.pinOnTop = pinOnTop
        self.clickThrough = clickThrough; self.showInDock = showInDock; self.opacity = opacity
    }
}

public struct PluginWindowLaunchEffect: Codable, Sendable, Hashable, Equatable {
    public let windowID: String?
    public let title: String?
    public let htmlPath: String?
    public let html: String?
    public let width: Int?
    public let height: Int?
    public let minWidth: Int?
    public let minHeight: Int?
    public let resizable: Bool?
    public let chrome: PluginWindowChromeStyle?
    public let transparent: Bool?
    public let pinOnTop: Bool?
    public let clickThrough: Bool?
    public let showInDock: Bool?
    public let opacity: Double?
    public let x: Int?
    public let y: Int?
    public let initialStateJSON: String?

    public init(
        windowID: String? = nil, title: String? = nil, htmlPath: String? = nil, html: String? = nil,
        width: Int? = nil, height: Int? = nil, minWidth: Int? = nil, minHeight: Int? = nil,
        resizable: Bool? = nil, chrome: PluginWindowChromeStyle? = nil, transparent: Bool? = nil,
        pinOnTop: Bool? = nil, clickThrough: Bool? = nil, showInDock: Bool? = nil, opacity: Double? = nil,
        x: Int? = nil, y: Int? = nil, initialStateJSON: String? = nil
    ) {
        self.windowID = windowID; self.title = title; self.htmlPath = htmlPath; self.html = html
        self.width = width; self.height = height; self.minWidth = minWidth; self.minHeight = minHeight
        self.resizable = resizable; self.chrome = chrome; self.transparent = transparent
        self.pinOnTop = pinOnTop; self.clickThrough = clickThrough; self.showInDock = showInDock
        self.opacity = opacity; self.x = x; self.y = y; self.initialStateJSON = initialStateJSON
    }
}

/// 外部插件自由画布窗口规范（不限制窗口 UI 形态，仅通过 `window` / `floatingWindow` 权限收口安全边界）。
public struct PluginCustomWindowSpec: Codable, Sendable, Hashable, Equatable {
    public static let minOpacity: Double = 0.15
    public static let maxConcurrentWindowsPerPlugin: Int = 4

    public let pluginID: String
    public let windowID: String
    public let title: String?
    public let htmlPath: String?
    public let html: String?
    public let width: Int
    public let height: Int
    public let minWidth: Int
    public let minHeight: Int
    public let resizable: Bool
    public let chrome: PluginWindowChromeStyle
    public let transparent: Bool
    public let pinOnTop: Bool
    public let clickThrough: Bool
    public let showInDock: Bool
    public let opacity: Double
    public let x: Int?
    public let y: Int?
    public let initialStateJSON: String?

    public init(
        pluginID: String, windowID: String = "main", title: String? = nil,
        htmlPath: String? = nil, html: String? = nil,
        width: Int = 520, height: Int = 560, minWidth: Int = 220, minHeight: Int = 120,
        resizable: Bool = true, chrome: PluginWindowChromeStyle = .standard,
        transparent: Bool = false, pinOnTop: Bool = false, clickThrough: Bool = false,
        showInDock: Bool? = nil, opacity: Double = 1.0, x: Int? = nil, y: Int? = nil,
        initialStateJSON: String? = nil
    ) {
        self.pluginID = pluginID
        self.windowID = Self.sanitizeWindowID(windowID)
        self.title = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.htmlPath = htmlPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.html = html
        let clampedW = Self.clampWidth(width), clampedH = Self.clampHeight(height)
        self.width = clampedW; self.height = clampedH
        self.minWidth = min(clampedW, max(160, minWidth))
        self.minHeight = min(clampedH, max(80, minHeight))
        self.resizable = resizable; self.chrome = chrome; self.transparent = transparent
        self.pinOnTop = pinOnTop || chrome == .hud || clickThrough
        self.clickThrough = clickThrough
        self.showInDock = showInDock ?? (chrome == .standard)
        self.opacity = min(max(opacity, Self.minOpacity), 1.0)
        self.x = x; self.y = y; self.initialStateJSON = initialStateJSON
    }

    public func withShowInDock(_ enabled: Bool) -> PluginCustomWindowSpec {
        PluginCustomWindowSpec(
            pluginID: pluginID, windowID: windowID, title: title, htmlPath: htmlPath, html: html,
            width: width, height: height, minWidth: minWidth, minHeight: minHeight,
            resizable: resizable, chrome: chrome, transparent: transparent, pinOnTop: pinOnTop,
            clickThrough: clickThrough, showInDock: enabled, opacity: opacity, x: x, y: y,
            initialStateJSON: initialStateJSON
        )
    }

    public var requiresFloatingCapability: Bool {
        pinOnTop || transparent || clickThrough || chrome != .standard
    }

    public var requiredCapability: PluginCapability {
        requiresFloatingCapability ? .floatingWindow : .window
    }

    public func isSatisfied(by granted: Set<PluginCapability>) -> Bool {
        requiresFloatingCapability
            ? granted.contains(.floatingWindow)
            : (granted.contains(.window) || granted.contains(.floatingWindow))
    }

    public static func resolve(
        plugin: PluginDescriptor,
        launch: PluginWindowLaunchEffect? = nil,
        baseSpec: PluginCustomWindowSpec? = nil
    ) -> PluginCustomWindowSpec {
        let def = plugin.manifest.window
        let chrome = launch?.chrome ?? baseSpec?.chrome ?? def?.chrome ?? .standard
        return PluginCustomWindowSpec(
            pluginID: plugin.id,
            windowID: launch?.windowID ?? baseSpec?.windowID ?? "main",
            title: launch?.title ?? baseSpec?.title ?? def?.title ?? plugin.displayName,
            htmlPath: launch?.htmlPath ?? baseSpec?.htmlPath ?? def?.entryHtml,
            html: launch?.html ?? baseSpec?.html,
            width: launch?.width ?? baseSpec?.width ?? def?.width ?? 520,
            height: launch?.height ?? baseSpec?.height ?? def?.height ?? 560,
            minWidth: launch?.minWidth ?? baseSpec?.minWidth ?? def?.minWidth ?? 220,
            minHeight: launch?.minHeight ?? baseSpec?.minHeight ?? def?.minHeight ?? 120,
            resizable: launch?.resizable ?? baseSpec?.resizable ?? def?.resizable ?? true,
            chrome: chrome,
            transparent: launch?.transparent ?? baseSpec?.transparent ?? def?.transparent ?? false,
            pinOnTop: launch?.pinOnTop ?? baseSpec?.pinOnTop ?? def?.pinOnTop ?? (chrome == .hud),
            clickThrough: launch?.clickThrough ?? baseSpec?.clickThrough ?? def?.clickThrough ?? false,
            showInDock: launch?.showInDock ?? baseSpec?.showInDock ?? def?.showInDock ?? (chrome == .standard),
            opacity: launch?.opacity ?? baseSpec?.opacity ?? def?.opacity ?? 1.0,
            x: launch?.x ?? baseSpec?.x,
            y: launch?.y ?? baseSpec?.y,
            initialStateJSON: launch?.initialStateJSON ?? baseSpec?.initialStateJSON
        )
    }

    public static func fromBridgeParams(
        pluginID: String, params: [String: Any], defaults: PluginManifestWindowDefaults? = nil
    ) -> PluginCustomWindowSpec {
        let chrome = (params["chrome"] as? String).flatMap(PluginWindowChromeStyle.init(rawValue:)) ?? defaults?.chrome ?? .standard
        return PluginCustomWindowSpec(
            pluginID: pluginID,
            windowID: (params["windowID"] as? String) ?? (params["id"] as? String) ?? "main",
            title: (params["title"] as? String) ?? defaults?.title,
            htmlPath: (params["htmlPath"] as? String) ?? (params["htmlFile"] as? String) ?? defaults?.entryHtml,
            html: params["html"] as? String,
            width: (params["width"] as? NSNumber)?.intValue ?? defaults?.width ?? 520,
            height: (params["height"] as? NSNumber)?.intValue ?? defaults?.height ?? 560,
            minWidth: (params["minWidth"] as? NSNumber)?.intValue ?? defaults?.minWidth ?? 220,
            minHeight: (params["minHeight"] as? NSNumber)?.intValue ?? defaults?.minHeight ?? 120,
            resizable: (params["resizable"] as? Bool) ?? defaults?.resizable ?? true,
            chrome: chrome,
            transparent: (params["transparent"] as? Bool) ?? defaults?.transparent ?? false,
            pinOnTop: (params["pinOnTop"] as? Bool) ?? defaults?.pinOnTop ?? (chrome == .hud),
            clickThrough: (params["clickThrough"] as? Bool) ?? defaults?.clickThrough ?? false,
            showInDock: (params["showInDock"] as? Bool) ?? defaults?.showInDock ?? (chrome == .standard),
            opacity: (params["opacity"] as? NSNumber)?.doubleValue ?? defaults?.opacity ?? 1.0,
            x: (params["x"] as? NSNumber)?.intValue,
            y: (params["y"] as? NSNumber)?.intValue,
            initialStateJSON: params["initialStateJSON"] as? String
        )
    }

    public static func parseDeepLink(url: URL, queryMap: [String: String]) -> PluginCustomWindowSpec? {
        let parts = url.path.split(separator: "/").map(String.init)
        guard let rawID = (parts.first ?? queryMap["id"])?.trimmingCharacters(in: .whitespacesAndNewlines),
              PluginSystem.isSafePluginID(rawID) else { return nil }
        let rawHtmlPath = queryMap["html"] ?? queryMap["path"]
        if let p = rawHtmlPath, !isSafeRelativeAssetPath(p) { return nil }
        let chrome = queryMap["chrome"].flatMap(PluginWindowChromeStyle.init(rawValue:)) ?? .standard
        let parseBool: (String?) -> Bool? = { raw in
            guard let v = raw?.lowercased() else { return nil }
            return v == "1" || v == "true" || v == "yes"
        }
        return PluginCustomWindowSpec(
            pluginID: rawID,
            windowID: parts.count >= 2 ? parts[1] : (queryMap["window"] ?? "main"),
            title: queryMap["title"], htmlPath: rawHtmlPath,
            width: queryMap["w"].flatMap(Int.init) ?? queryMap["width"].flatMap(Int.init) ?? 520,
            height: queryMap["h"].flatMap(Int.init) ?? queryMap["height"].flatMap(Int.init) ?? 560,
            resizable: parseBool(queryMap["resizable"]) ?? true, chrome: chrome,
            transparent: parseBool(queryMap["transparent"]) ?? false,
            pinOnTop: parseBool(queryMap["pin"]) ?? (chrome == .hud),
            clickThrough: parseBool(queryMap["clickThrough"]) ?? false,
            showInDock: parseBool(queryMap["showInDock"]) ?? (chrome == .standard),
            opacity: queryMap["opacity"].flatMap(Double.init) ?? 1.0,
            x: queryMap["x"].flatMap(Int.init), y: queryMap["y"].flatMap(Int.init),
            initialStateJSON: queryMap["state"]
        )
    }

    public static func resolveSafeHTMLFileURL(relativePath: String, bundleDirectory: URL) -> URL? {
        guard isSafeRelativeAssetPath(relativePath) else { return nil }
        let root = bundleDirectory.resolvingSymlinksInPath().standardizedFileURL
        let candidate = root.appendingPathComponent(relativePath).resolvingSymlinksInPath().standardizedFileURL
        guard candidate.path.hasPrefix(root.path + "/"),
              FileManager.default.fileExists(atPath: candidate.path) else { return nil }
        return candidate
    }

    public static func validateManifestWindowDefaults(_ defaults: PluginManifestWindowDefaults?, in directoryURL: URL) -> [String] {
        guard let defaults, let entryHtml = defaults.entryHtml, !entryHtml.isEmpty else { return [] }
        if !isSafeRelativeAssetPath(entryHtml) {
            return ["window.entryHtml 路径不合法或包含越界目录段：\(entryHtml)"]
        }
        if resolveSafeHTMLFileURL(relativePath: entryHtml, bundleDirectory: directoryURL) == nil {
            return ["window.entryHtml 文件不存在：\(entryHtml)"]
        }
        return []
    }

    public static func isSafeRelativeAssetPath(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("/"), !trimmed.hasPrefix("~"), !trimmed.contains("\\") else { return false }
        let segments = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        return !segments.isEmpty && segments.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    public static func sanitizeWindowID(_ raw: String) -> String {
        let filtered = raw.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }
        let clean = String(String.UnicodeScalarView(filtered).prefix(40))
        return clean.isEmpty ? "main" : clean
    }

    public static func clampWidth(_ raw: Int) -> Int { min(max(raw, 180), 2400) }
    public static func clampHeight(_ raw: Int) -> Int { min(max(raw, 96), 1600) }
}

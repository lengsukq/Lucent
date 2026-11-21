import Foundation
import LucentFoundation
import LucentSearch

public enum OverlayActionSection: String, Sendable, CaseIterable, Hashable {
    case primary
    case pipeline
    case manage

    public var title: String {
        switch self {
        case .primary: L10n.pick("常用操作", "Actions")
        case .pipeline: L10n.pick("发送到插件与脚本", "Send To Plugins & Scripts")
        case .manage: L10n.pick("整理与设置", "Organize & Settings")
        }
    }
}

public enum OverlayActionKind: Sendable, Hashable {
    case executePrimary
    case executeSecondary
    case copyValue
    case pastePlainText
    case revealInFinder
    case addToFileShelf(pluginID: String, urls: [URL])
    case openInWorkspace(directoryURL: URL)
    case pinOnScreen(imageURL: URL)
    case recognizeOCR(imageURL: URL)
    case toggleClipboardPin(entryID: UUID)
    case deleteClipboardEntry(entryID: UUID)
    case sendToPlugin(pluginID: String, context: PluginContextPayload)
    case sendToScript(scriptID: String, inputText: String)
    case pinToHomeBento
    case pinToHomeDock
    case openSettings
    case resetSearchAffinity
}

public struct OverlayContextAction: Identifiable, Sendable, Hashable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let symbol: String
    public let shortcutHint: String?
    public let section: OverlayActionSection
    public let isDestructive: Bool
    public let kind: OverlayActionKind

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        symbol: String,
        shortcutHint: String? = nil,
        section: OverlayActionSection = .primary,
        isDestructive: Bool = false,
        kind: OverlayActionKind
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.shortcutHint = shortcutHint
        self.section = section
        self.isDestructive = isDestructive
        self.kind = kind
    }
}

/// Pure, deterministic `⌘K` context action resolver that chains any launcher candidate into
/// native actions, File Shelf, matching `accepts` plugins, and Quick Scripts.
public enum OverlayActionCatalog {
    public static func contextPayload(for candidate: LauncherCandidate) -> PluginContextPayload? {
        switch candidate.kind {
        case .fileHit(let hit):
            return PluginContextMatcher.payloadFromFiles([hit.url], source: "everything")
        case .clipboard(let entry):
            return PluginContextMatcher.payloadFromClipboard(entry)
        case .calculator(_, let result, _):
            return PluginContextMatcher.payloadFromText(result, source: "calculator")
        case .devTool(let tool):
            if let pngURL = tool.previewImageURL {
                return PluginContextMatcher.payloadFromFiles([pngURL], source: "devtool")
            }
            return PluginContextMatcher.payloadFromText(tool.copyText, source: "devtool")
        case .snippet(let match):
            return PluginContextMatcher.payloadFromText(match.expandedText, source: "snippet")
        case .pluginItem(let entry):
            let payloadText = entry.url ?? entry.copyText ?? entry.title
            return PluginContextMatcher.payloadFromText(payloadText, source: "plugin-item")
        default:
            return nil
        }
    }

    public static func scriptInputText(for candidate: LauncherCandidate) -> String? {
        switch candidate.kind {
        case .fileHit(let hit): return hit.url.path
        case .clipboard(let entry):
            if let text = entry.textValue, !text.isEmpty { return text }
            if let first = entry.fileURLs.first { return first.path }
            return nil
        case .calculator(_, let result, _): return result
        case .devTool(let tool): return tool.previewImageURL?.path ?? tool.copyText
        case .snippet(let match): return match.expandedText
        case .pluginItem(let entry): return entry.url ?? entry.copyText ?? entry.title
        default: return nil
        }
    }

    public static func actions(
        for candidate: LauncherCandidate,
        plugins: [PluginDescriptor],
        scripts: [ScriptRecord],
        canPinToHome: Bool = true,
        affinityClickCount: Int = 0
    ) -> [OverlayContextAction] {
        var out: [OverlayContextAction] = []
        let shelfPlugin = plugins.first { $0.isValid && $0.isEnabled && $0.grantedCapabilities.contains(.fileShelf) }

        appendPrimaryActions(for: candidate, shelfPlugin: shelfPlugin, into: &out)
        appendPipelineActions(for: candidate, plugins: plugins, scripts: scripts, shelfPluginID: shelfPlugin?.id, into: &out)
        appendManageActions(for: candidate, canPinToHome: canPinToHome, affinityClickCount: affinityClickCount, into: &out)
        return out
    }

    private static func appendPrimaryActions(
        for candidate: LauncherCandidate,
        shelfPlugin: PluginDescriptor?,
        into out: inout [OverlayContextAction]
    ) {
        switch candidate.kind {
        case .fileHit(let hit):
            out.append(.init(id: "primary", title: hit.isDirectory ? L10n.pick("在文件工作台打开", "Open in File Workspace") : L10n.pick("打开文件", "Open File"), symbol: hit.isDirectory ? "folder.fill" : "arrow.up.forward.app", shortcutHint: "↩", kind: .executePrimary))
            out.append(.init(id: "finder", title: L10n.pick("在访达中显示", "Reveal in Finder"), symbol: "folder", shortcutHint: "⌘R", kind: .revealInFinder))
            out.append(.init(id: "copy", title: L10n.pick("复制完整路径", "Copy Full Path"), symbol: "doc.on.doc", shortcutHint: "⌘C", kind: .copyValue))
            if let shelf = shelfPlugin {
                out.append(.init(id: "shelf", title: L10n.pick("放入\(shelf.displayName)", "Add to \(shelf.displayName)"), symbol: "tray.and.arrow.down.fill", kind: .addToFileShelf(pluginID: shelf.id, urls: [hit.url])))
            }
            if !hit.isDirectory {
                let parent = hit.url.deletingLastPathComponent()
                out.append(.init(id: "workspace-dir", title: L10n.pick("在文件台打开所在目录", "Open Parent in Workspace"), symbol: "sidebar.squares.left", kind: .openInWorkspace(directoryURL: parent)))
            }
            if hit.mediaKind == .image {
                out.append(.init(id: "pin-screen", title: L10n.pick("钉在屏幕最上层", "Pin on Screen"), symbol: "pin.fill", kind: .pinOnScreen(imageURL: hit.url)))
                out.append(.init(id: "ocr", title: L10n.pick("离线文字 / 条码识别 (OCR)", "Offline OCR / Barcodes"), symbol: "text.viewfinder", kind: .recognizeOCR(imageURL: hit.url)))
            }

        case .clipboard(let entry):
            out.append(.init(id: "primary", title: L10n.pick("粘贴到原窗口", "Paste to Frontmost App"), symbol: "arrow.turn.down.left", shortcutHint: "↩", kind: .executePrimary))
            out.append(.init(id: "copy", title: L10n.pick("仅复制到剪贴板", "Copy Only"), symbol: "doc.on.doc", shortcutHint: "⌘C", kind: .copyValue))
            if entry.textValue != nil {
                out.append(.init(id: "plain", title: L10n.pick("纯文本粘贴", "Paste as Plain Text"), symbol: "text.alignleft", shortcutHint: "⌥↩", kind: .pastePlainText))
            }
            if let shelf = shelfPlugin, !entry.fileURLs.isEmpty {
                out.append(.init(id: "shelf", title: L10n.pick("放入\(shelf.displayName)", "Add to \(shelf.displayName)"), symbol: "tray.and.arrow.down.fill", kind: .addToFileShelf(pluginID: shelf.id, urls: entry.fileURLs)))
            }
            if case .image(let imgURL, _) = entry.payloadKind {
                out.append(.init(id: "pin-screen", title: L10n.pick("钉在屏幕最上层", "Pin on Screen"), symbol: "pin.fill", shortcutHint: "⌘↩", kind: .pinOnScreen(imageURL: imgURL)))
                out.append(.init(id: "ocr", title: L10n.pick("离线文字 / 条码识别 (OCR)", "Offline OCR / Barcodes"), symbol: "text.viewfinder", kind: .recognizeOCR(imageURL: imgURL)))
            }
            if !entry.fileURLs.isEmpty {
                out.append(.init(id: "finder", title: L10n.pick("在访达中显示", "Reveal in Finder"), symbol: "folder", shortcutHint: "⌘R", kind: .revealInFinder))
            }
            out.append(.init(id: "clip-pin", title: entry.isPinned ? L10n.pick("取消永久收藏", "Unpin Item") : L10n.pick("永久收藏此条目", "Pin Permanently"), symbol: entry.isPinned ? "pin.slash" : "pin.fill", section: .manage, kind: .toggleClipboardPin(entryID: entry.id)))
            out.append(.init(id: "clip-del", title: L10n.pick("删除此历史条目", "Delete Clipboard Item"), symbol: "trash", shortcutHint: "⌘⌫", section: .manage, isDestructive: true, kind: .deleteClipboardEntry(entryID: entry.id)))

        case .app:
            out.append(.init(id: "primary", title: L10n.pick("启动应用", "Launch App"), symbol: "play.fill", shortcutHint: "↩", kind: .executePrimary))
            out.append(.init(id: "finder", title: L10n.pick("在访达中显示", "Reveal in Finder"), symbol: "folder", shortcutHint: "⌘↩", kind: .revealInFinder))
            out.append(.init(id: "copy", title: L10n.pick("复制应用路径", "Copy App Path"), symbol: "doc.on.doc", shortcutHint: "⌘C", kind: .copyValue))

        case .calculator, .devTool, .snippet:
            out.append(.init(id: "primary", title: L10n.pick("复制结果", "Copy Result"), symbol: "doc.on.doc", shortcutHint: "↩", kind: .executePrimary))
            if case .devTool(let tool) = candidate.kind, let qrURL = tool.previewImageURL {
                out.append(.init(id: "pin-screen", title: L10n.pick("钉在屏幕最上层", "Pin QR on Screen"), symbol: "pin.fill", shortcutHint: "⌘↩", kind: .pinOnScreen(imageURL: qrURL)))
            }

        case .plugin, .pluginCommand, .pluginItem, .script:
            out.append(.init(id: "primary", title: L10n.pick("执行", "Run"), symbol: "play.fill", shortcutHint: "↩", kind: .executePrimary))
            out.append(.init(id: "copy", title: L10n.pick("复制内容 / 路径", "Copy Value / Path"), symbol: "doc.on.doc", shortcutHint: "⌘C", kind: .copyValue))
            out.append(.init(id: "settings", title: L10n.pick("打开设置 / 编辑", "Open Settings / Edit"), symbol: "slider.horizontal.3", shortcutHint: "⌘,", section: .manage, kind: .openSettings))

        case .command:
            out.append(.init(id: "primary", title: L10n.pick("执行命令", "Run Command"), symbol: "bolt.fill", shortcutHint: "↩", kind: .executePrimary))
        }
    }

    private static func appendPipelineActions(
        for candidate: LauncherCandidate,
        plugins: [PluginDescriptor],
        scripts: [ScriptRecord],
        shelfPluginID: String?,
        into out: inout [OverlayContextAction]
    ) {
        if let ctx = contextPayload(for: candidate) {
            let matched = PluginContextMatcher.matchingPlugins(in: plugins, for: ctx)
                .filter { $0.id != shelfPluginID || (ctx.filePaths ?? []).isEmpty }
            for plugin in matched.prefix(6) {
                out.append(.init(
                    id: "plugin:\(plugin.id)",
                    title: L10n.pick("发送到「\(plugin.displayName)」", "Send to “\(plugin.displayName)”"),
                    subtitle: plugin.manifest.localizedDescription(),
                    symbol: "puzzlepiece.extension.fill",
                    section: .pipeline,
                    kind: .sendToPlugin(pluginID: plugin.id, context: ctx)
                ))
            }
        }
        if let input = scriptInputText(for: candidate), !input.isEmpty {
            let eligibleScripts = scripts.filter(\.isEnabled).prefix(6)
            for script in eligibleScripts {
                out.append(.init(
                    id: "script:\(script.id)",
                    title: L10n.pick("用脚本「\(script.displayTitle)」处理", "Run Script “\(script.displayTitle)”"),
                    subtitle: script.runtime.title,
                    symbol: "terminal.fill",
                    section: .pipeline,
                    kind: .sendToScript(scriptID: script.id, inputText: input)
                ))
            }
        }
    }

    private static func appendManageActions(
        for candidate: LauncherCandidate,
        canPinToHome: Bool,
        affinityClickCount: Int,
        into out: inout [OverlayContextAction]
    ) {
        if canPinToHome {
            out.append(.init(id: "pin-bento", title: L10n.pick("钉到启动页 · Bento 磁贴", "Pin to Home · Bento Tile"), symbol: "square.grid.3x2.fill", section: .manage, kind: .pinToHomeBento))
            out.append(.init(id: "pin-dock", title: L10n.pick("钉到启动页 · 混合高频坞", "Pin to Home · Omni Dock"), symbol: "dock.rectangle", section: .manage, kind: .pinToHomeDock))
        }
        if affinityClickCount > 0 {
            out.append(.init(
                id: "reset-affinity",
                title: L10n.pick("重置此项搜索热度（已选 \(affinityClickCount) 次）", "Reset Search Affinity (\(affinityClickCount) clicks)"),
                symbol: "arrow.counterclockwise",
                section: .manage,
                isDestructive: true,
                kind: .resetSearchAffinity
            ))
        }
    }
}

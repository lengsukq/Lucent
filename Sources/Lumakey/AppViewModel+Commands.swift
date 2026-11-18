import AppKit
import Foundation
import LumakeyCore

extension AppViewModel {
    func executeCandidate(_ candidate: LauncherCandidate) {
        switch candidate.kind {
        case .app(let app):
            launchApp(app)
        case .calculator(_, let result, _):
            copyPlainText(result, message: "已复制结果：\(result)")
            if !isOverlayPinned { onHideOverlayRequest?() }
        case .devTool(let tool):
            if let pngURL = tool.previewImageURL {
                _ = DevToolkitEngine.copyQRImageToPasteboard(at: pngURL)
                capturePasteboardOnceIfChanged()
                serviceMessage = L10n.translate("二维码图片已复制到剪贴板，可直接 ⌘V 粘贴")
            } else {
                copyPlainText(tool.copyText, message: "已复制 \(tool.badge)：\(tool.title)")
            }
            if !isOverlayPinned { onHideOverlayRequest?() }
        case .snippet(let match):
            copyPlainText(match.expandedText, message: "已展开并复制短语：\(match.snippet.title)")
            if !isOverlayPinned { onHideOverlayRequest?() }
        case .script(let match):
            runScript(match.script, query: match.trailingQuery)
        case .fileHit(let hit): executeEverythingHit(hit)
        case .clipboard(let entry): executeClipboardEntry(entry, autoPaste: true)
        case .plugin(let plugin):
            let queryArg = scopedPluginID == plugin.id
                ? overlayQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                : stripMatchedPluginKeyword(from: overlayQuery, plugin: plugin)
            runPlugin(plugin, query: queryArg, showInline: true)
        case .pluginCommand(let regCmd): executePluginRegisteredCommand(regCmd, rawQuery: overlayQuery)
        case .pluginItem(let entry): executePluginSearchEntry(entry)
        case .command(let cmd): executeSystemCommand(cmd.command)
        }
    }

    func quickExecuteCandidate(at index: Int) {
        if tryExecuteHomeShortcut(at: index) { return }
        guard index >= 0, index < displayedCandidates.count else { return }
        overlaySelectedIndex = index; executeCandidate(displayedCandidates[index])
    }

    func copySelectedCandidateValue() {
        guard let selected = selectedCandidate else { return }
        switch selected.kind {
        case .calculator(_, let result, _): copyPlainText(result, message: "已复制计算结果：\(result)")
        case .devTool(let tool):
            if let pngURL = tool.previewImageURL {
                _ = DevToolkitEngine.copyQRImageToPasteboard(at: pngURL)
                capturePasteboardOnceIfChanged()
                serviceMessage = L10n.translate("已复制二维码 PNG 图片")
            } else {
                copyPlainText(tool.copyText, message: "已复制 \(tool.badge)")
            }
        case .snippet(let match): copyPlainText(match.expandedText, message: "已复制展开短语：\(match.snippet.title)")
        case .script(let match):
            let p = ScriptLibraryStore.shared.scriptURL(for: match.script).path
            copyPlainText(p, message: "已复制脚本路径：\(match.script.displayTitle)")
        case .clipboard(let entry):
            _ = ClipboardService.copyToPasteboard(entry); lastPasteboardChangeCount = NSPasteboard.general.changeCount
            serviceMessage = L10n.translate("已复制剪贴板项：\(entry.title)")
        case .fileHit(let hit): copyPlainText(hit.url.path, message: "已复制路径：\(hit.name)")
        case .app(let app): copyPlainText(app.url.path, message: "已复制应用路径：\(app.displayName)")
        case .plugin(let plugin): copyPlainText(plugin.directoryURL.path, message: "已复制插件目录路径")
        case .pluginCommand(let regCmd): copyPlainText(regCmd.command.title, message: "已复制子功能名称：\(regCmd.command.title)")
        case .pluginItem(let entry): copyPlainText(entry.copyText ?? entry.url ?? entry.title, message: "已复制：\(entry.title)")
        case .command(let cmd): copyPlainText(cmd.title, message: "已复制命令标题")
        }
    }

    func executeSecondaryCandidateAction() {
        guard let selected = selectedCandidate else { return }
        switch selected.kind {
        case .app(let app):
            NSWorkspace.shared.activateFileViewerSelecting([app.url])
            if !isOverlayPinned { onHideOverlayRequest?() }
        case .fileHit(let hit):
            if [.markdown, .text, .image, .video].contains(hit.mediaKind) {
                NSWorkspace.shared.activateFileViewerSelecting([hit.url])
            } else {
                openMediaWindow(for: hit.url, kind: hit.mediaKind)
            }
        case .clipboard(let clip):
            if case .image(let url, _) = clip.payloadKind { openMediaWindow(for: url, kind: .image, pinOnTop: true) }
            else if case .video(let url) = clip.payloadKind { openMediaWindow(for: url, kind: .video, pinOnTop: true) }
            else if !clip.fileURLs.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(clip.fileURLs) }
            else { executeClipboardEntry(clip) }
        case .devTool(let tool):
            if let url = tool.previewImageURL { openMediaWindow(for: url, kind: .image, pinOnTop: true) }
            else { copyPlainText(tool.copyText, message: "已复制 \(tool.badge)") }
        case .snippet: openRoute(.settings(.snippets))
        case .script(let match): openScriptSettings(selecting: match.script.id)
        case .plugin(let plugin): openPluginSettings(id: plugin.id)
        case .pluginCommand(let regCmd): togglePluginCommandQuickButton(regCmd)
        case .pluginItem(let entry):
            if let args = entry.commandArgs, !args.isEmpty,
               let plugin = plugins.first(where: { $0.id == entry.pluginID }) {
                runPlugin(plugin, query: "", arguments: args, showInline: true)
            } else {
                openPluginSettings(id: entry.pluginID)
            }
        default: executeCandidate(selected)
        }
    }

    func openMediaWindow(for url: URL, kind: PreviewMediaKind, siblings: [URL]? = nil, pinOnTop: Bool = false) {
        PreviewPlaybackRegistry.shared.pauseAll()
        switch kind {
        case .markdown, .text:
            openRoute(.documentReader(url, siblings ?? MediaClassifier.siblingMediaURLs(around: url, matching: [.markdown, .text])))
        case .image:
            openRoute(.imageViewer(url, siblings ?? MediaClassifier.siblingMediaURLs(around: url, matching: [.image]), pinOnTop))
        case .video:
            openRoute(.videoPlayer(url, siblings ?? MediaClassifier.siblingMediaURLs(around: url, matching: [.video]), pinOnTop))
        default:
            NSWorkspace.shared.open(url)
            if !isOverlayPinned { onHideOverlayRequest?() }
        }
    }

    func launchApp(_ app: InstalledAppItem) {
        AppUsageTrackerController.shared.recordLumakeyLaunch(app)
        appLaunchCounts[app.id, default: 0] += 1
        NSWorkspace.shared.open(app.url)
        if !isOverlayPinned { onHideOverlayRequest?() }
    }

    func startGifRecording() {
        let preferredTargetApp = resolveOverlayTargetApp?()
        onHideOverlayRequest?()
        GifCaptureController.shared.startInteractiveCapture(preferredTargetApp: preferredTargetApp)
    }

    func executeEverythingHit(_ hit: EverythingSearchHit) {
        if hit.isDirectory {
            navigate(pane: activePane, to: hit.url); openRoute(.workspace)
        } else if [.markdown, .text, .image, .video].contains(hit.mediaKind) {
            openMediaWindow(for: hit.url, kind: hit.mediaKind)
        } else {
            NSWorkspace.shared.open(hit.url)
            if !isOverlayPinned { onHideOverlayRequest?() }
        }
    }

    func revealSelectedInFinder() {
        guard let selected = selectedCandidate else { return }
        switch selected.kind {
        case .fileHit(let hit): NSWorkspace.shared.activateFileViewerSelecting([hit.url])
        case .app(let app): NSWorkspace.shared.activateFileViewerSelecting([app.url])
        case .script(let match):
            NSWorkspace.shared.activateFileViewerSelecting([ScriptLibraryStore.shared.scriptURL(for: match.script)])
        case .clipboard(let clip): if !clip.fileURLs.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(clip.fileURLs) }
        case .devTool(let tool): if let url = tool.previewImageURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        case .plugin(let plugin): NSWorkspace.shared.activateFileViewerSelecting([plugin.directoryURL])
        case .pluginCommand(let regCmd):
            if let plugin = plugins.first(where: { $0.id == regCmd.pluginID }), !plugin.isBuiltin {
                NSWorkspace.shared.activateFileViewerSelecting([plugin.directoryURL])
            }
        case .pluginItem(let entry):
            if let plugin = plugins.first(where: { $0.id == entry.pluginID }) {
                NSWorkspace.shared.activateFileViewerSelecting([plugin.directoryURL])
            }
        default: break
        }
    }

    func executeSystemCommand(_ command: SystemCommandKind) {
        switch command {
        case .openWelcome: openRoute(.settings(.about))
        case .openWorkspace: openRoute(.workspace)
        case .openSettings: openRoute(.settings(.general))
        case .openClipboard: prepareOverlay(filter: .clipboard)
        case .openEverything: prepareOverlay(filter: .files)
        case .capturePin: captureAndPinScreenshot()
        case .captureOCR: captureAndAnalyzeOCR()
        case .recordGif: startGifRecording()
        case .openTrash: NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))
        case .emptyTrash: runAppleScript("tell application \"Finder\" to empty the trash")
        case .lockScreen: runAppleScript("tell application \"System Events\" to keystroke \"q\" using {command down, control down}")
        case .toggleMosEnabled:
            var next = mosConfig; next.enabled.toggle(); applyMosConfig(next)
            serviceMessage = L10n.translate(next.enabled ? "鼠标平滑滚轮已开启" : "鼠标平滑滚轮已关闭")
        case .toggleMosReverse:
            var next = mosConfig; next.reverseWheelDirection.toggle(); applyMosConfig(next)
            serviceMessage = L10n.translate(next.reverseWheelDirection ? "已开启物理鼠标滚轮反转" : "已恢复默认滚轮方向")
        case .toggleMosSmooth:
            var next = mosConfig; next.smoothScroll.toggle(); applyMosConfig(next)
            serviceMessage = L10n.translate(next.smoothScroll ? "已开启 120Hz 平滑滚动" : "已关闭平滑滚动")
        case .openMosSettings: openRoute(.settings(.mos))
        case .toggleSystemMonitor:
            SystemPulseWindowController.shared.toggleFloatingWidget()
            if !isOverlayPinned { onHideOverlayRequest?() }
        case .openNetworkMonitor: openRoute(.networkMonitor)
        case .openCacheManager: openRoute(.settings(.cache))
        case .openBackupSettings: openRoute(.settings(.backup))
        case .quickBackup: BackupCoordinator.triggerQuickBackup(viewModel: self)
        case .openSnippetsSettings: openRoute(.settings(.snippets))
        case .openScriptsSettings: openRoute(.settings(.scripts))
        case .openPluginsSettings: openRoute(.settings(.plugins))
        case .switchTheme(let theme): setAppTheme(theme)
        case .cycleTheme: cycleAppTheme()
        case .switchLanguage(let lang): setAppLanguage(lang)
        case .cycleLanguage: cycleAppLanguage()
        case .reclaimMemory: reclaimAllIdleMemoryNow()
        case .inspectPort(let port):
            Task {
                let text = await Task.detached(priority: .userInitiated) { UnitAndCommandEngine.inspectListeningPort(port) }.value
                self.inlineResultTitle = L10n.pick("端口 :\(port) 监听探测", "Port :\(port) Listener Probe")
                self.inlineResultBody = text
            }
        case .openVolume(let url): navigate(pane: activePane, to: url); openRoute(.workspace)
        case .openPath(let url):
            var isDir: ObjCBool = false
            _ = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue {
                navigate(pane: activePane, to: url); openRoute(.workspace)
            } else {
                let kind = MediaClassifier.classify(url: url, isDirectory: false)
                openMediaWindow(for: url, kind: kind)
            }
        case .webSearch(let engine, let url):
            NSWorkspace.shared.open(url)
            serviceMessage = L10n.pick("已在浏览器打开 \(engine)", "Opened \(engine) in browser")
        }
    }

    private func copyPlainText(_ value: String, message: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        serviceMessage = L10n.translate(message)
    }

    func executePluginSearchEntry(_ entry: PluginSearchEntry) {
        PluginSystem.recordPluginUsage(id: entry.pluginID)
        if let rawURL = entry.url, let url = URL(string: rawURL) {
            handlePluginOpenURL(url)
            serviceMessage = L10n.pick("已打开：\(entry.title)", "Opened: \(entry.title)")
            if !isOverlayPinned && url.scheme != "lumakey" { onHideOverlayRequest?() }
        } else if let args = entry.commandArgs, !args.isEmpty,
                  let plugin = plugins.first(where: { $0.id == entry.pluginID }) {
            runPlugin(plugin, query: "", arguments: args, showInline: true)
        } else {
            copyPlainText(entry.copyText ?? entry.title, message: "已复制：\(entry.title)")
        }
    }

    func stripMatchedPluginKeyword(from raw: String, plugin: PluginDescriptor) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        for kw in plugin.effectiveKeywordsLowercased.sorted(by: { $0.count > $1.count }) {
            if lower == kw { return "" }
            if lower.hasPrefix(kw + " ") {
                return String(trimmed.dropFirst(kw.count + 1)).trimmingCharacters(in: .whitespaces)
            }
        }
        return trimmed
    }

    private func runAppleScript(_ source: String) {
        if let script = NSAppleScript(source: source) { var err: NSDictionary?; script.executeAndReturnError(&err) }
    }
}

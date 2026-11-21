import AppKit
import Foundation
import LucentCore

extension AppViewModel {
    func toggleOverlayActionMenu() {
        if actionMenu.isPresented {
            closeOverlayActionMenu()
            return
        }
        guard let candidate = selectedCandidate else { return }
        let canPin = homeLaunchItem(from: candidate) != nil
        let affinityClicks = SearchAffinityStore.shared.clickCount(for: candidate)
        let actions = OverlayActionCatalog.actions(
            for: candidate,
            plugins: plugins,
            scripts: scripts,
            canPinToHome: canPin,
            affinityClickCount: affinityClicks
        )
        actionMenu.open(candidateTitle: overlayActionHeaderTitle(for: candidate), actions: actions)
    }

    func closeOverlayActionMenu() {
        actionMenu.close()
    }

    func executeOverlayAction(_ action: OverlayContextAction) {
        let targetCandidate = selectedCandidate
        closeOverlayActionMenu()
        guard let candidate = targetCandidate else { return }

        switch action.kind {
        case .executePrimary:
            executeCandidate(candidate)
        case .executeSecondary:
            executeSecondaryCandidateAction()
        case .copyValue:
            copySelectedCandidateValue()
        case .pastePlainText:
            if case .clipboard(let entry) = candidate.kind {
                executeClipboardEntry(entry, autoPaste: true, plainTextOnly: true)
            }
        case .revealInFinder:
            revealSelectedInFinder()
        case .addToFileShelf(let pluginID, let urls):
            guard !urls.isEmpty else { return }
            if FileShelfPanels.shared.open(pluginID: pluginID, urls: urls, takeFocus: false, expandIfTucked: true) {
                PluginSystem.recordPluginUsage(id: pluginID)
                serviceMessage = L10n.pick("已放入文件中转站（\(urls.count) 项）", "Added \(urls.count) item(s) to File Shelf")
                if !isOverlayPinned { onHideOverlayRequest?() }
            }
        case .openInWorkspace(let dirURL):
            navigate(pane: activePane, to: dirURL)
            openRoute(.workspace)
        case .pinOnScreen(let imgURL):
            PinWindowController.shared.pinImage(at: imgURL)
            serviceMessage = L10n.pick("已钉在屏幕最上层", "Pinned on screen")
            if !isOverlayPinned { onHideOverlayRequest?() }
        case .recognizeOCR(let imgURL):
            presentOCRForImage(at: imgURL)
        case .toggleClipboardPin(let entryID):
            if let entry = clipboardItems.first(where: { $0.id == entryID }) {
                toggleClipboardPin(entry)
            }
        case .deleteClipboardEntry(let entryID):
            if let entry = clipboardItems.first(where: { $0.id == entryID }) {
                deleteClipboardEntry(entry)
            }
        case .sendToPlugin(let pluginID, let context):
            if let plugin = plugins.first(where: { $0.id == pluginID }) {
                runPluginWithContext(plugin, context: context)
            }
        case .sendToScript(let scriptID, let inputText):
            if let script = scripts.first(where: { $0.id == scriptID }) {
                runScript(script, query: inputText)
            }
        case .pinToHomeBento:
            pinCandidateToHome(candidate, destination: .bento)
        case .pinToHomeDock:
            pinCandidateToHome(candidate, destination: .dock)
        case .openSettings:
            handleOverlayKeyAction(.openSettings)
        case .resetSearchAffinity:
            resetSearchAffinity(for: candidate)
        }
    }

    private func presentOCRForImage(at url: URL) {
        latestCaptureURL = url
        Task { [weak self] in
            do {
                let analysis = try await Task.detached(priority: .userInitiated) {
                    try VisionService.analyzeTextAndBarcodes(at: url)
                }.value
                guard let self else { return }
                let combined = ([analysis.recognizedText] + analysis.barcodes).filter { !$0.isEmpty }.joined(separator: "\n")
                self.serviceMessage = combined.isEmpty
                    ? L10n.pick("未检测到文本", "No text detected")
                    : L10n.pick("离线 OCR 识别完成", "Offline OCR completed")
                OCRResultWindowController.shared.present(imageURL: url, analysis: analysis) { [weak self] in
                    self?.captureAndAnalyzeOCR()
                }
            } catch {
                self?.serviceMessage = error.localizedDescription
            }
        }
    }

    private func overlayActionHeaderTitle(for candidate: LauncherCandidate) -> String {
        switch candidate.kind {
        case .app(let app): return app.displayName
        case .fileHit(let hit): return hit.name
        case .clipboard(let entry): return entry.title
        case .calculator(_, let result, _): return result
        case .devTool(let tool): return tool.title
        case .snippet(let match): return match.snippet.title
        case .script(let match): return match.script.displayTitle
        case .plugin(let plugin): return plugin.displayName
        case .pluginCommand(let cmd): return cmd.localizedTitle
        case .pluginItem(let entry): return entry.title
        case .command(let cmd): return cmd.title
        }
    }
}

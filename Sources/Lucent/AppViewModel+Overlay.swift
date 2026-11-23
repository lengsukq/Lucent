import AppKit
import Foundation
import LucentCore

extension AppViewModel {
    private var shouldPreCaptureSelectionForOverlay: Bool {
        scripts.contains(where: \.isEnabled)
            || plugins.contains { $0.isValid && $0.isEnabled && $0.grantedCapabilities.contains(.selection) }
    }

    func prepareOverlay(filter: OmniFilter) {
        runtime.indexUnloadTask?.cancel(); runtime.indexUnloadTask = nil
        runtime.queryIdleClearTask?.cancel(); runtime.queryIdleClearTask = nil
        if !isOverlayVisible && !skipNextSelectionCapture {
            lastCapturedSelection = shouldPreCaptureSelectionForOverlay
                ? PluginSelectionReader.captureFrontmostSelection(allowCopyFallback: false, enableManualAccessibility: false)
                : nil
        }
        isOverlayVisible = true
        if filter != .plugins { scopedPluginID = nil }
        omniFilter = filter
        resetOverlaySelection()
        inlineResultBody = nil; inlinePluginViewPayload = nil; activeInlinePlugin = nil
        capturePasteboardOnceIfChanged()
        refreshInstalledAppsIfNeeded()
        triggerStalePluginIndexRefreshIfNeeded()
        IconCache.shared.prewarmDockIcons(cachedDockApps)
        if everythingIndex == nil && !isIndexingEverything && scopedPluginID == nil {
            rebuildEverythingIndex(scope: everythingScope)
        }
        refreshDisplayedCandidates(resetSelection: true)
        bumpFocusToken()
    }

    func setOmniFilter(_ filter: OmniFilter) { prepareOverlay(filter: filter) }

    func resetOverlaySelection() {
        overlaySelectedIndex = 0; userMovedOverlaySelection = false; anchoredOverlayCandidateID = nil
    }

    func selectOverlayCandidate(at index: Int, userInitiated: Bool) {
        guard !displayedCandidates.isEmpty else { resetOverlaySelection(); return }
        let clamped = min(max(0, index), min(displayedCandidates.count, 50) - 1)
        overlaySelectedIndex = clamped
        if userInitiated {
            userMovedOverlaySelection = true
            anchoredOverlayCandidateID = displayedCandidates[clamped].id
        }
        syncOverlayPreviewToSelection()
    }

    func bumpFocusToken() { focusToken += 1 }
    func showOverlay(filter: OmniFilter) { onShowOverlayRequest?(filter) }
    func recenterFloatingPanel() { onRecenterFloatingPanel?() }
    func openRoute(_ route: WindowRoute) {
        if case .workspace = route {} else { PreviewPlaybackRegistry.shared.pauseAll() }
        onRouteRequest?(route)
    }

    func setDockIconVisible(_ visible: Bool) {
        showDockIcon = visible
        updateGeneralPreferences { $0.showDockIcon = visible }
        onDockVisibilityChanged?(visible)
    }

    func handleOverlayHidden() {
        isOverlayVisible = false
        closeOverlayActionMenu()
        runtime.cancelOverlaySessionTasks()
        previewState = .empty; displayedCandidates = []
        resetOverlaySelection(); scopedPluginID = nil
        inlinePluginViewPayload = nil; activeInlinePlugin = nil; lastCapturedSelection = nil

        runtime.queryIdleClearTask?.cancel(); runtime.queryIdleClearTask = nil
        switch generalPreferences.queryClearPolicy {
        case .immediatelyOnHide:
            if !overlayQuery.isEmpty { overlayQuery = "" }
            inlineResultBody = nil
        case .afterIdle30s where !overlayQuery.isEmpty || inlineResultBody != nil:
            runtime.queryIdleClearTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self, !self.isOverlayVisible else { return }
                if !self.overlayQuery.isEmpty { self.overlayQuery = "" }
                self.inlineResultBody = nil
            }
        default: break
        }

        runtime.indexUnloadTask?.cancel()
        runtime.indexUnloadTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(90))
            guard !Task.isCancelled, let self, !self.isOverlayVisible, self.everythingIndex != nil else { return }
            self.runtime.fsEventApplyTask?.cancel()
            self.runtime.fsEventApplyTask = nil
            self.everythingIndex = nil; self.displayedCandidates = []
            MemoryStats.reclaimFreeHeapPages()
        }
    }

    func handleOverlayQueryChanged() {
        closeOverlayActionMenu()
        resetOverlaySelection()
        if isOverlayVisible, everythingIndex == nil, !isIndexingEverything,
           LauncherEngine.shouldWakeEverythingIndex(for: overlayQuery, filter: omniFilter, scopedPluginID: scopedPluginID) {
            rebuildEverythingIndex(scope: everythingScope)
        }
        refreshDisplayedCandidates(resetSelection: true)
    }

    func refreshDisplayedCandidates(resetSelection: Bool = false) {
        guard isOverlayVisible else { return }
        runtime.searchTask?.cancel()
        if resetSelection { resetOverlaySelection() }
        let trimmed = overlayQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentFilter = omniFilter
        let scopedClipboard = currentFilter == .clipboard
            ? ClipboardService.filter(clipboardItems, query: "", category: clipboardCategory) : clipboardItems

        let smartRankingEnabled = generalPreferences.enableSmartSearchRanking
        let affinitySnapshot = smartRankingEnabled ? SearchAffinityStore.shared.boosts(forQuery: trimmed) : [:]

        if let activeScope = scopedPluginID,
           let scopedPlugin = plugins.first(where: { $0.id == activeScope && $0.isValid && ($0.isBuiltin || $0.isEnabled) }) {
            let scopedRanked = LauncherEngine.rankCandidates(
                query: trimmed, filter: .plugins, apps: [], plugins: [scopedPlugin],
                pluginCommands: pluginCommands, pluginSearchEntries: pluginSearchEntries,
                affinityBoosts: affinitySnapshot, scopedPluginID: activeScope
            )
            applyRefreshedCandidates(Array(scopedRanked.prefix(50)))
            return
        }

        if trimmed.isEmpty {
            let emptyHits: [LauncherCandidate] = switch currentFilter {
            case .all: []
            case .clipboard:
                scopedClipboard.prefix(50).enumerated().map { idx, item in
                    LauncherCandidate(id: "clip:\(item.id.uuidString)", score: 9_300 - idx, kind: .clipboard(item))
                }
            case .plugins:
                Array(LauncherEngine.rankCandidates(
                    query: "", filter: .plugins, apps: [], plugins: plugins,
                    pluginCommands: pluginCommands, pluginSearchEntries: pluginSearchEntries,
                    scripts: scripts, affinityBoosts: affinitySnapshot
                ).prefix(50))
            case .files:
                (everythingIndex?.search(queryText: "", limit: 40) ?? []).enumerated().map { idx, hit in
                    LauncherCandidate(id: "file:\(hit.id)", score: 9_400 - idx, kind: .fileHit(hit))
                }
            }
            applyRefreshedCandidates(emptyHits)
            return
        }

        let appsSnapshot = installedApps, pluginsSnapshot = plugins, commandsSnapshot = pluginCommands
        let entriesSnapshot = pluginSearchEntries, scriptsSnapshot = scripts
        let volumesSnapshot = cachedVolumes, indexSnapshot = everythingIndex, countsSnapshot = appLaunchCounts
        let usageBoostsSnapshot = AppUsageTrackerController.shared.rankingBoosts(for: appsSnapshot)
        let clipTextSnapshot = clipboardItems.first(where: { $0.textValue != nil })?.textValue
            ?? NSPasteboard.general.string(forType: .string)

        runtime.searchTask = Task {
            try? await Task.sleep(for: .milliseconds(10))
            guard !Task.isCancelled else { return }
            let ranked = await Task.detached(priority: .userInitiated) {
                LauncherEngine.rankCandidates(
                    query: trimmed, filter: currentFilter, apps: appsSnapshot,
                    plugins: pluginsSnapshot, pluginCommands: commandsSnapshot,
                    pluginSearchEntries: entriesSnapshot, scripts: scriptsSnapshot, clipboardItems: scopedClipboard,
                    volumes: volumesSnapshot, everythingIndex: indexSnapshot,
                    launchCounts: countsSnapshot, usageBoosts: usageBoostsSnapshot,
                    affinityBoosts: affinitySnapshot, clipboardText: clipTextSnapshot
                )
            }.value
            guard !Task.isCancelled else { return }
            self.applyRefreshedCandidates(Array(ranked.prefix(50)))
        }
    }

    private func applyRefreshedCandidates(_ nextCandidates: [LauncherCandidate]) {
        let prevSelectedID = selectedCandidate?.id
        let resolved = LauncherSelectionAnchor.resolve(
            candidates: nextCandidates, currentIndex: overlaySelectedIndex,
            userMovedSelection: userMovedOverlaySelection, anchoredID: anchoredOverlayCandidateID
        )
        if displayedCandidates != nextCandidates { displayedCandidates = nextCandidates }
        if overlaySelectedIndex != resolved.index { overlaySelectedIndex = resolved.index }
        anchoredOverlayCandidateID = resolved.anchoredID
        if selectedCandidate?.id != prevSelectedID || prevSelectedID == nil { syncOverlayPreviewToSelection() }
    }

    func handleOverlayKeyAction(_ action: OverlayKeyAction) {
        if actionMenu.isPresented {
            switch action {
            case .moveUp: actionMenu.moveUp(); return
            case .moveDown: actionMenu.moveDown(); return
            case .submit:
                if let selected = actionMenu.selectedAction { executeOverlayAction(selected) }
                return
            case .escape, .toggleActionMenu:
                closeOverlayActionMenu(); return
            default:
                closeOverlayActionMenu()
            }
        }
        switch action {
        case .moveUp: selectOverlayCandidate(at: overlaySelectedIndex - 1, userInitiated: true)
        case .moveDown: selectOverlayCandidate(at: overlaySelectedIndex + 1, userInitiated: true)
        case .submit: if let candidate = selectedCandidate { executeCandidate(candidate) }
        case .toggleActionMenu: toggleOverlayActionMenu()
        case .pasteSubmit:
            guard let candidate = selectedCandidate else { return }
            if case .clipboard(let entry) = candidate.kind { executeClipboardEntry(entry, autoPaste: true) }
            else { executeCandidate(candidate) }
        case .plainTextSubmit:
            guard let candidate = selectedCandidate else { return }
            if case .clipboard(let entry) = candidate.kind { executeClipboardEntry(entry, autoPaste: true, plainTextOnly: true) }
            else { executeCandidate(candidate) }
        case .deleteBackwardWhenEmpty:
            if scopedPluginID != nil {
                scopedPluginID = nil; inlinePluginViewPayload = nil; activeInlinePlugin = nil
                refreshDisplayedCandidates(resetSelection: true)
            }
        case .escape:
            if inlinePluginViewPayload != nil { inlinePluginViewPayload = nil; activeInlinePlugin = nil }
            else if inlineResultBody != nil { inlineResultBody = nil }
            else if !overlayQuery.isEmpty { overlayQuery = "" }
            else if scopedPluginID != nil { scopedPluginID = nil; refreshDisplayedCandidates(resetSelection: true) }
            else if omniFilter != .all { setOmniFilter(.all) }
            else { onHideOverlayRequest?() }
        case .cycleMode:
            if scopedPluginID == nil, let selected = selectedCandidate, case .plugin(let plugin) = selected.kind {
                enterPluginScopedOverlay(plugin, initialQuery: stripMatchedPluginKeyword(from: overlayQuery, plugin: plugin))
            } else {
                scopedPluginID = nil; setOmniFilter(omniFilter.next)
            }
        case .togglePreview:
            showOverlayLens.toggle(); syncOverlayPreviewToSelection()
        case .revealInFinder:
            revealSelectedInFinder()
        case .openSettings:
            if let scopedID = scopedPluginID { openPluginSettings(id: scopedID) }
            else if let selected = selectedCandidate, case .script(let m) = selected.kind { openScriptSettings(selecting: m.script.id) }
            else if let selected = selectedCandidate, case .plugin(let p) = selected.kind { openPluginSettings(id: p.id) }
            else if let selected = selectedCandidate, case .pluginCommand(let c) = selected.kind { openPluginSettings(id: c.pluginID) }
            else if let selected = selectedCandidate, case .pluginItem(let e) = selected.kind { openPluginSettings(id: e.pluginID) }
            else { openRoute(.settings(.general)) }
        }
    }

    func syncOverlayPreviewToSelection() {
        guard effectiveLensVisible else { return }
        if let selected = selectedCandidate, case .fileHit(let hit) = selected.kind {
            startPreview(for: fileEntry(from: hit))
        } else {
            runtime.previewTask?.cancel(); previewState = .empty
        }
    }

    func resetSearchAffinity(for candidate: LauncherCandidate) {
        SearchAffinityStore.shared.resetItem(for: candidate)
        refreshDisplayedCandidates(resetSelection: false)
        serviceMessage = L10n.pick("已重置该项的搜索频率热度", "Reset search affinity for item")
    }

    func clearAllSearchAffinity() {
        SearchAffinityStore.shared.clearAll()
        SearchAffinityStore.shared.flush()
        refreshDisplayedCandidates(resetSelection: false)
        serviceMessage = L10n.pick("已清空全部搜索频率学习记录", "Cleared all learned search preferences")
    }

    func fileEntry(from hit: EverythingSearchHit) -> FileEntry {
        FileEntry(
            url: hit.url, name: hit.name, isDirectory: hit.isDirectory,
            sizeBytes: hit.sizeBytes, modifiedAt: hit.modifiedAt,
            extensionLowercased: hit.url.pathExtension.lowercased(), mediaKind: hit.mediaKind
        )
    }
}

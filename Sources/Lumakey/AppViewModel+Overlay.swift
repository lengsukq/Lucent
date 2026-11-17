import AppKit
import Foundation
import LumakeyCore

extension AppViewModel {
    func prepareOverlay(filter: OmniFilter) {
        indexUnloadTask?.cancel()
        indexUnloadTask = nil
        if !isOverlayVisible && !skipNextSelectionCapture {
            lastCapturedSelection = PluginSelectionReader.captureFrontmostSelection()
        }
        isOverlayVisible = true
        if filter != .plugins { scopedPluginID = nil }
        omniFilter = filter
        resetOverlaySelection()
        inlineResultBody = nil
        inlinePluginViewPayload = nil
        activeInlinePlugin = nil
        capturePasteboardOnceIfChanged()
        triggerStalePluginIndexRefreshIfNeeded()
        IconCache.shared.prewarmDockIcons(cachedDockApps)
        let hasQuery = !overlayQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if everythingIndex == nil && !isIndexingEverything && (filter == .files || (hasQuery && scopedPluginID == nil)) {
            rebuildEverythingIndex(scope: everythingScope)
        }
        refreshDisplayedCandidates(resetSelection: true)
        bumpFocusToken()
    }

    func setOmniFilter(_ filter: OmniFilter) {
        prepareOverlay(filter: filter)
    }

    func resetOverlaySelection() {
        overlaySelectedIndex = 0
        userMovedOverlaySelection = false
        anchoredOverlayCandidateID = nil
    }

    func selectOverlayCandidate(at index: Int, userInitiated: Bool) {
        guard !displayedCandidates.isEmpty else {
            resetOverlaySelection()
            return
        }
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
        onDockVisibilityChanged?(visible)
    }

    func handleOverlayHidden() {
        isOverlayVisible = false
        searchTask?.cancel(); previewTask?.cancel(); hashTask?.cancel(); pluginRunTask?.cancel()
        previewState = .empty; displayedCandidates = []
        resetOverlaySelection()
        scopedPluginID = nil
        inlinePluginViewPayload = nil; activeInlinePlugin = nil
        lastCapturedSelection = nil

        indexUnloadTask?.cancel()
        indexUnloadTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(90))
            guard !Task.isCancelled, let self, !self.isOverlayVisible, self.everythingIndex != nil else { return }
            self.stopIndexWatcher()
            self.everythingIndex = nil
            self.displayedCandidates = []
            MemoryStats.reclaimFreeHeapPages()
        }
    }

    func handleOverlayQueryChanged() {
        resetOverlaySelection()
        if isOverlayVisible, scopedPluginID == nil, everythingIndex == nil, !isIndexingEverything,
           !overlayQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rebuildEverythingIndex(scope: everythingScope)
        }
        refreshDisplayedCandidates(resetSelection: true)
    }

    func refreshDisplayedCandidates(resetSelection: Bool = false) {
        guard isOverlayVisible else { return }
        searchTask?.cancel()
        if resetSelection {
            resetOverlaySelection()
        }
        let trimmed = overlayQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentFilter = omniFilter
        let activeScope = scopedPluginID
        let scopedClipboard = currentFilter == .clipboard
            ? ClipboardService.filter(clipboardItems, query: "", category: clipboardCategory)
            : clipboardItems

        if let activeScope,
           let scopedPlugin = plugins.first(where: { $0.id == activeScope && $0.isValid && ($0.isBuiltin || $0.isEnabled) }) {
            let scopedRanked = LauncherEngine.rankCandidates(
                query: trimmed, filter: .plugins, apps: [], plugins: [scopedPlugin],
                pluginCommands: pluginCommands, pluginSearchEntries: pluginSearchEntries, scopedPluginID: activeScope
            )
            applyRefreshedCandidates(Array(scopedRanked.prefix(50)))
            return
        }

        if trimmed.isEmpty {
            let emptyHits: [LauncherCandidate]
            switch currentFilter {
            case .all:
                emptyHits = []
            case .clipboard:
                emptyHits = scopedClipboard.prefix(50).enumerated().map { idx, item in
                    LauncherCandidate(id: "clip:\(item.id.uuidString)", score: 9_300 - idx, kind: .clipboard(item))
                }
            case .plugins:
                let ranked = LauncherEngine.rankCandidates(
                    query: "", filter: .plugins, apps: [], plugins: plugins,
                    pluginCommands: pluginCommands, pluginSearchEntries: pluginSearchEntries
                )
                emptyHits = Array(ranked.prefix(50))
            case .files:
                emptyHits = (everythingIndex?.search(queryText: "", limit: 40) ?? []).enumerated().map { idx, hit in
                    LauncherCandidate(id: "file:\(hit.id)", score: 9_400 - idx, kind: .fileHit(hit))
                }
            }
            applyRefreshedCandidates(emptyHits)
            return
        }

        let appsSnapshot = installedApps
        let pluginsSnapshot = plugins
        let pluginCommandsSnapshot = pluginCommands
        let pluginEntriesSnapshot = pluginSearchEntries
        let volumesSnapshot = cachedVolumes
        let indexSnapshot = everythingIndex
        let countsSnapshot = appLaunchCounts
        let usageBoostsSnapshot = AppUsageTrackerController.shared.rankingBoosts(for: appsSnapshot)
        let clipTextSnapshot = clipboardItems.first(where: { $0.textValue != nil })?.textValue
            ?? NSPasteboard.general.string(forType: .string)

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(10))
            guard !Task.isCancelled else { return }
            let ranked = await Task.detached(priority: .userInitiated) {
                LauncherEngine.rankCandidates(
                    query: trimmed, filter: currentFilter, apps: appsSnapshot,
                    plugins: pluginsSnapshot, pluginCommands: pluginCommandsSnapshot,
                    pluginSearchEntries: pluginEntriesSnapshot,
                    clipboardItems: scopedClipboard, volumes: volumesSnapshot,
                    everythingIndex: indexSnapshot, launchCounts: countsSnapshot,
                    usageBoosts: usageBoostsSnapshot, clipboardText: clipTextSnapshot
                )
            }.value
            guard !Task.isCancelled else { return }
            self.applyRefreshedCandidates(Array(ranked.prefix(50)))
        }
    }

    private func applyRefreshedCandidates(_ nextCandidates: [LauncherCandidate]) {
        let prevSelectedID = selectedCandidate?.id
        let resolved = LauncherSelectionAnchor.resolve(
            candidates: nextCandidates,
            currentIndex: overlaySelectedIndex,
            userMovedSelection: userMovedOverlaySelection,
            anchoredID: anchoredOverlayCandidateID
        )
        let listChanged = displayedCandidates != nextCandidates
        if listChanged {
            displayedCandidates = nextCandidates
        }
        if overlaySelectedIndex != resolved.index {
            overlaySelectedIndex = resolved.index
        }
        anchoredOverlayCandidateID = resolved.anchoredID
        if selectedCandidate?.id != prevSelectedID || prevSelectedID == nil {
            syncOverlayPreviewToSelection()
        }
    }

    func handleOverlayKeyAction(_ action: OverlayKeyAction) {
        switch action {
        case .moveUp:
            selectOverlayCandidate(at: overlaySelectedIndex - 1, userInitiated: true)
        case .moveDown:
            selectOverlayCandidate(at: overlaySelectedIndex + 1, userInitiated: true)
        case .submit:
            guard let candidate = selectedCandidate else { return }
            executeCandidate(candidate)
        case .pasteSubmit:
            guard let candidate = selectedCandidate else { return }
            if case .clipboard(let entry) = candidate.kind {
                executeClipboardEntry(entry, autoPaste: true)
            } else {
                executeCandidate(candidate)
            }
        case .plainTextSubmit:
            guard let candidate = selectedCandidate else { return }
            if case .clipboard(let entry) = candidate.kind {
                executeClipboardEntry(entry, autoPaste: true, plainTextOnly: true)
            } else {
                executeCandidate(candidate)
            }
        case .deleteBackwardWhenEmpty:
            if scopedPluginID != nil {
                scopedPluginID = nil
                inlinePluginViewPayload = nil
                activeInlinePlugin = nil
                refreshDisplayedCandidates(resetSelection: true)
            }
        case .escape:
            if inlinePluginViewPayload != nil {
                inlinePluginViewPayload = nil
                activeInlinePlugin = nil
            } else if inlineResultBody != nil {
                inlineResultBody = nil
            } else if !overlayQuery.isEmpty {
                overlayQuery = ""
            } else if scopedPluginID != nil {
                scopedPluginID = nil
                refreshDisplayedCandidates(resetSelection: true)
            } else if omniFilter != .all {
                setOmniFilter(.all)
            } else {
                onHideOverlayRequest?()
            }
        case .cycleMode:
            if scopedPluginID == nil,
               let selected = selectedCandidate,
               case .plugin(let plugin) = selected.kind {
                let initialQ = stripMatchedPluginKeyword(from: overlayQuery, plugin: plugin)
                enterPluginScopedOverlay(plugin, initialQuery: initialQ)
            } else {
                scopedPluginID = nil
                setOmniFilter(omniFilter.next)
            }
        case .togglePreview:
            showOverlayLens.toggle()
            syncOverlayPreviewToSelection()
        case .revealInFinder:
            revealSelectedInFinder()
        case .openSettings:
            if let scopedID = scopedPluginID {
                openPluginSettings(id: scopedID)
            } else if let selected = selectedCandidate, case .plugin(let plugin) = selected.kind {
                openPluginSettings(id: plugin.id)
            } else if let selected = selectedCandidate, case .pluginCommand(let regCmd) = selected.kind {
                openPluginSettings(id: regCmd.pluginID)
            } else if let selected = selectedCandidate, case .pluginItem(let entry) = selected.kind {
                openPluginSettings(id: entry.pluginID)
            } else {
                openRoute(.settings(.general))
            }
        }
    }

    func syncOverlayPreviewToSelection() {
        guard effectiveLensVisible else { return }
        if let selected = selectedCandidate, case .fileHit(let hit) = selected.kind {
            startPreview(for: fileEntry(from: hit))
        } else {
            previewTask?.cancel()
            previewState = .empty
        }
    }

    func fileEntry(from hit: EverythingSearchHit) -> FileEntry {
        FileEntry(
            url: hit.url, name: hit.name, isDirectory: hit.isDirectory,
            sizeBytes: hit.sizeBytes, modifiedAt: hit.modifiedAt,
            extensionLowercased: hit.url.pathExtension.lowercased(), mediaKind: hit.mediaKind
        )
    }
}

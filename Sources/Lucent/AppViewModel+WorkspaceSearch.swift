import AppKit
import Foundation
import LucentCore

extension AppViewModel {
    func navigate(pane: PaneSide, to url: URL, pushHistory: Bool = true) {
        let changed = (pane == .left ? leftPane : rightPane).currentDirectory.standardizedFileURL.path != url.standardizedFileURL.path
        mutatePane(pane) { state in
            if pushHistory, state.currentDirectory != url { state.history.append(state.currentDirectory) }
            state.currentDirectory = url; state.diagnostic = nil; state.recursiveSearchHits = []
        }
        if changed && activePane == pane { clearWorkspaceSelection() }
        refreshDirectory(pane: pane); refreshWorkspaceSubfolderSearch(for: pane)
    }

    func goBack(pane: PaneSide) {
        guard let previous = (pane == .left ? leftPane : rightPane).history.last else { return }
        mutatePane(pane) { $0.history.removeLast() }
        navigate(pane: pane, to: previous, pushHistory: false)
    }

    func addTab(pane: PaneSide) {
        let newTab = WorkspaceTab(directoryURL: (pane == .left ? leftPane : rightPane).currentDirectory)
        mutatePane(pane) { state in state.tabs.append(newTab); state.activeTabID = newTab.id; state.recursiveSearchHits = [] }
        refreshDirectory(pane: pane); refreshWorkspaceSubfolderSearch(for: pane)
    }

    func selectTab(_ tabID: UUID, in pane: PaneSide) {
        mutatePane(pane) { $0.activeTabID = tabID; $0.recursiveSearchHits = [] }
        if activePane == pane { clearWorkspaceSelection() }
        refreshDirectory(pane: pane); refreshWorkspaceSubfolderSearch(for: pane)
    }

    func closeTab(_ tabID: UUID, in pane: PaneSide) {
        mutatePane(pane) { state in
            guard state.tabs.count > 1, let idx = state.tabs.firstIndex(where: { $0.id == tabID }) else { return }
            state.tabs.remove(at: idx)
            if state.activeTabID == tabID { state.activeTabID = state.tabs[max(0, idx - 1)].id }
            state.recursiveSearchHits = []
        }
        if activePane == pane { clearWorkspaceSelection() }
        refreshDirectory(pane: pane); refreshWorkspaceSubfolderSearch(for: pane)
    }

    func focusWorkspaceSearchField() {
        workspaceSearchFocusToken &+= 1
    }

    func updateWorkspaceFilterText(_ text: String, in pane: PaneSide) {
        activePane = pane
        mutatePane(pane) { state in
            state.filterText = text
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                state.recursiveSearchHits = []
                state.isSearchingSubfolders = false
            }
        }
        refreshWorkspaceSubfolderSearch(for: pane)
    }

    func toggleWorkspaceRecursiveSearch(in pane: PaneSide) {
        activePane = pane
        mutatePane(pane) { state in
            state.recursiveSearch.toggle()
            if !state.recursiveSearch {
                state.recursiveSearchHits = []
                state.isSearchingSubfolders = false
            }
        }
        refreshWorkspaceSubfolderSearch(for: pane)
    }

    func clearWorkspaceFilter(in pane: PaneSide) {
        activePane = pane
        workspaceRuntime.replaceSearchTask(nil, for: pane)
        mutatePane(pane) { state in
            state.mediaFilter = .all
            state.filterText = ""
            state.recursiveSearchHits = []
            state.isSearchingSubfolders = false
        }
    }

    func refreshWorkspaceSubfolderSearch(for pane: PaneSide) {
        workspaceRuntime.replaceSearchTask(nil, for: pane)
        let state = pane == .left ? leftPane : rightPane
        let query = state.filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, state.recursiveSearch else {
            mutatePane(pane) {
                $0.recursiveSearchHits = []
                $0.isSearchingSubfolders = false
            }
            return
        }

        let dirURL = state.currentDirectory
        let dirPath = dirURL.standardizedFileURL.path
        let mediaFilter = state.mediaFilter
        let includeHidden = state.showHidden
        mutatePane(pane) { $0.isSearchingSubfolders = true }

        let task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(70))
            guard !Task.isCancelled else { return }
            let found = await Task.detached(priority: .userInitiated) {
                WorkspaceSearchMatcher.searchDirectoryRecursively(
                    rootURL: dirURL,
                    queryText: query,
                    mediaFilter: mediaFilter,
                    includeHidden: includeHidden,
                    limit: 260
                )
            }.value
            guard !Task.isCancelled, let self else { return }
            let latest = pane == .left ? self.leftPane : self.rightPane
            guard latest.currentDirectory.standardizedFileURL.path == dirPath,
                  latest.filterText.trimmingCharacters(in: .whitespacesAndNewlines) == query,
                  latest.recursiveSearch else { return }
            self.mutatePane(pane) {
                $0.recursiveSearchHits = found
                $0.isSearchingSubfolders = false
            }
        }
        workspaceRuntime.replaceSearchTask(task, for: pane)
    }

    func stepWorkspaceSelection(by delta: Int) -> Bool {
        let visible = activePaneState.visibleEntries
        guard !visible.isEmpty else { return false }
        let currentIdx = selectedEntry.flatMap { sel in visible.firstIndex(where: { $0.id == sel.id }) }
        let nextIdx: Int
        if let currentIdx {
            nextIdx = min(max(0, currentIdx + delta), visible.count - 1)
        } else {
            nextIdx = delta >= 0 ? 0 : visible.count - 1
        }
        let target = visible[nextIdx]
        selectedEntryIDs = [target.id]
        selectionAnchorID = target.id
        selectedEntry = target
        startPreview(for: target)
        return true
    }

    func openQuickDirectorySearchFromWorkspace() {
        let targetDir = activePaneState.currentDirectory.standardizedFileURL
        let targetPath = targetDir.path
        let dirTitle = targetDir.lastPathComponent.isEmpty ? targetPath : targetDir.lastPathComponent

        let indexCoversDirectory: Bool = {
            guard let existing = everythingIndex, !existing.nodes.isEmpty else { return false }
            return existing.rootPaths.contains { root in
                targetPath == root || targetPath.hasPrefix(root == "/" ? "/" : root + "/")
            }
        }()

        let targetScope: EverythingScope = indexCoversDirectory ? everythingScope : .volume(name: dirTitle, mountPath: targetPath)
        let nextQuery: String
        if case .volume(_, let mountPath) = targetScope,
           URL(fileURLWithPath: mountPath).standardizedFileURL.path == targetPath {
            nextQuery = ""
        } else {
            let homePath = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
            let pathToken: String = if targetPath == homePath {
                "~"
            } else if targetPath.hasPrefix(homePath + "/") {
                "~" + String(targetPath.dropFirst(homePath.count))
            } else {
                targetPath
            }
            nextQuery = pathToken.contains(" ") ? "path:\"\(pathToken)\" " : "path:\(pathToken) "
        }

        if !indexCoversDirectory {
            loadOrBuildEverythingIndex(scope: targetScope, forceRebuild: false)
        }
        showOverlay(filter: .files)
        overlayQuery = nextQuery
        refreshDisplayedCandidates(resetSelection: true)
        bumpFocusToken()
    }
}

import AppKit
import Foundation
import LucentCore

extension AppViewModel {
    func executeClipboardEntry(
        _ entry: ClipboardEntry,
        autoPaste: Bool = false,
        plainTextOnly: Bool = false
    ) {
        let targetApp = resolveOverlayTargetApp?()
        let wroteOK = plainTextOnly
            ? ClipboardService.copyPlainTextToPasteboard(entry)
            : ClipboardService.copyToPasteboard(entry)
        guard wroteOK else {
            serviceMessage = L10n.pick("源媒体文件已被移除，无法写入剪贴板", "Source media file no longer exists")
            return
        }
        let changeCount = NSPasteboard.general.changeCount
        lastPasteboardChangeCount = changeCount
        clipboardItems = ClipboardService.promote(entry, in: clipboardItems)
        if !plainTextOnly && !entry.fileURLs.isEmpty {
            workspaceClipboard = WorkspaceClipboardState(urls: entry.fileURLs, mode: .copy, pasteboardChangeCount: changeCount)
        }
        if !autoPaste {
            serviceMessage = plainTextOnly
                ? L10n.pick("已复制纯文本：\(entry.title)", "Copied plain text: \(entry.title)")
                : L10n.pick("已复制：\(entry.title)", "Copied: \(entry.title)")
            if !isOverlayPinned { onHideOverlayRequest?() }
            return
        }
        if !plainTextOnly && targetApp == nil && hasLoadedWorkspace && !entry.fileURLs.isEmpty {
            if !isOverlayPinned { onHideOverlayRequest?() }
            pasteWorkspaceClipboard()
            return
        }
        if !isOverlayPinned { onHideOverlayRequest?() }
        if AXIsProcessTrusted() {
            serviceMessage = plainTextOnly
                ? L10n.pick("已作为纯文本粘贴：\(entry.title)", "Pasted plain text: \(entry.title)")
                : L10n.pick("已粘贴：\(entry.title)", "Pasted: \(entry.title)")
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(45)) {
                Self.postCommandVPasteKeystroke()
            }
        } else {
            serviceMessage = L10n.pick("已复制并切回原窗口，按 ⌘V 即可粘贴", "Copied & refocused target window — press ⌘V to paste")
        }
    }

    private static func postCommandVPasteKeystroke() {
        let src = CGEventSource(stateID: .hidSystemState)
        if let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true) {
            down.flags = .maskCommand
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false) {
            up.flags = .maskCommand
            up.post(tap: .cghidEventTap)
        }
    }

    func toggleClipboardPin(_ entry: ClipboardEntry) {
        guard let idx = clipboardItems.firstIndex(where: { $0.id == entry.id }) else { return }
        clipboardItems[idx].isPinned.toggle()
    }

    func deleteClipboardEntry(_ entry: ClipboardEntry) {
        guard let idx = clipboardItems.firstIndex(where: { $0.id == entry.id }) else { return }
        let removed = clipboardItems.remove(at: idx)
        let evicted = clipboardRuntime.pushDeleted(entry: removed, index: idx)
        canUndoClipboardDelete = clipboardRuntime.canUndo
        reclaimEvictedClipboardTempFiles(evicted)
        serviceMessage = L10n.pick("已删除剪贴板项（按 ⌘Z 撤回）", "Deleted clipboard item (⌘Z to undo)")
    }

    @discardableResult
    func deleteSelectedCandidateIfSupported() -> Bool {
        guard let selected = selectedCandidate, case .clipboard(let entry) = selected.kind else {
            return false
        }
        deleteClipboardEntry(entry)
        return true
    }

    @discardableResult
    func undoLastClipboardDelete() -> Bool {
        guard let last = clipboardRuntime.popDeleted() else { return false }
        canUndoClipboardDelete = clipboardRuntime.canUndo
        if !clipboardItems.contains(where: { $0.id == last.entry.id }) {
            let safeIdx = min(max(0, last.index), clipboardItems.count)
            clipboardItems.insert(last.entry, at: safeIdx)
        }
        serviceMessage = L10n.pick("已撤回删除：\(last.entry.title)", "Restored: \(last.entry.title)")
        return true
    }

    func toggleClipboardPause() {
        isClipboardPaused.toggle()
        lastPasteboardChangeCount = NSPasteboard.general.changeCount
        serviceMessage = isClipboardPaused
            ? L10n.pick("剪贴板记录已暂停（复制敏感内容不会被记录）", "Clipboard recording paused")
            : L10n.pick("剪贴板记录已恢复", "Clipboard recording resumed")
    }

    func clearUnpinnedClipboard() {
        batchCleanClipboard(.unpinnedAll)
    }

    func batchCleanClipboard(_ kind: ClipboardBatchCleanupKind) {
        let result = ClipboardBatchCleaner.apply(kind, to: clipboardItems)
        guard !result.removed.isEmpty else {
            serviceMessage = L10n.pick("没有符合清理条件的剪贴板记录", "No matching clipboard items to clean")
            return
        }
        clipboardItems = result.remaining
        reclaimEvictedClipboardTempFiles(result.removed)
        let count = result.removed.count
        switch kind {
        case .allIncludingPinned:
            serviceMessage = L10n.pick("已清空全部 \(count) 条剪贴板记录（含收藏）", "Cleared all \(count) clipboard items (including pinned)")
        case .unpinnedAll:
            serviceMessage = L10n.pick("已清空 \(count) 条未收藏剪贴板记录", "Cleared \(count) unpinned clipboard items")
        case .olderThan24Hours:
            serviceMessage = L10n.pick("已清理 \(count) 条 24 小时前的未收藏记录", "Cleaned \(count) unpinned items older than 24h")
        case .olderThan7Days:
            serviceMessage = L10n.pick("已清理 \(count) 条 7 天前的未收藏记录", "Cleaned \(count) unpinned items older than 7 days")
        case .unpinnedMediaOnly:
            serviceMessage = L10n.pick("已清理 \(count) 条未收藏图片/视频记录", "Cleaned \(count) unpinned image/video items")
        case .unpinnedCategory(let cat):
            serviceMessage = L10n.pick("已清理 \(count) 条未收藏「\(cat.localizedTitle)」记录", "Cleaned \(count) unpinned \(cat.localizedTitle) items")
        }
    }

    private func reclaimEvictedClipboardTempFiles(_ candidates: [ClipboardEntry]) {
        guard !candidates.isEmpty else { return }
        let activePaths = Set(
            (clipboardItems + clipboardRuntime.deletedUndoStack.map(\.entry))
                .flatMap { $0.fileURLs.map(\.path) }
        )
        let safeToRemove = candidates.filter { item in
            item.fileURLs.allSatisfy { !activePaths.contains($0.path) }
        }
        ClipboardService.removeTempFiles(for: safeToRemove)
    }

    func capturePasteboardOnceIfChanged() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastPasteboardChangeCount else { return }
        lastPasteboardChangeCount = pb.changeCount
        guard !isClipboardPaused else { return }
        let sourceBundleID = (isOverlayVisible ? resolveOverlayTargetApp?() : NSWorkspace.shared.frontmostApplication)?.bundleIdentifier
            ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if ClipboardService.shouldIgnoreSourceApp(
            bundleIdentifier: sourceBundleID,
            excludedBundleIDs: generalPreferences.clipboardExcludedBundleIDs
        ) {
            return
        }
        if let entry = ClipboardService.captureCurrent(from: pb) {
            clipboardItems = ClipboardService.insert(
                entry,
                into: clipboardItems,
                maxUnpinned: generalPreferences.clipboardMaxUnpinned,
                ttl: generalPreferences.clipboardRetentionTTL
            )
        }
    }

    func startClipboardMonitor() {
        stopClipboardMonitor()
        lastPasteboardChangeCount = NSPasteboard.general.changeCount
        var ticksSincePrune = 0
        clipboardRuntime.monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1500), tolerance: .milliseconds(250))
                guard !Task.isCancelled, let self else { break }
                if self.isCapturingScreen || self.isClipboardPaused { continue }
                self.capturePasteboardOnceIfChanged()
                ticksSincePrune &+= 1
                if ticksSincePrune >= 20, self.generalPreferences.clipboardRetentionTTL != .forever {
                    ticksSincePrune = 0
                    let pruned = ClipboardService.pruneAndCap(
                        self.clipboardItems,
                        maxUnpinned: self.generalPreferences.clipboardMaxUnpinned,
                        ttl: self.generalPreferences.clipboardRetentionTTL
                    )
                    if pruned != self.clipboardItems { self.clipboardItems = pruned }
                }
            }
        }
    }

    func stopClipboardMonitor() {
        clipboardRuntime.stopMonitor()
    }

    func loadPersistedPinnedClipboard() {
        let saved = ClipboardHistoryStore.loadMergedEntries(
            maxUnpinned: generalPreferences.clipboardMaxUnpinned,
            ttl: generalPreferences.clipboardRetentionTTL
        )
        guard !saved.isEmpty else { return }
        clipboardRuntime.isSyncingPinnedStore = true
        defer { clipboardRuntime.isSyncingPinnedStore = false }
        clipboardItems = saved
        _ = ClipboardHistoryStore.saveHistoryEntries(saved)
    }

    func persistPinnedClipboardIfNeeded(previous: [ClipboardEntry]) {
        guard !clipboardRuntime.isSyncingPinnedStore else { return }
        let pinnedChanged = clipboardItems.filter(\.isPinned) != previous.filter(\.isPinned)
        let unpinnedChanged = clipboardItems.filter { !$0.isPinned } != previous.filter { !$0.isPinned }
        guard pinnedChanged || unpinnedChanged else { return }
        clipboardRuntime.isSyncingPinnedStore = true
        defer { clipboardRuntime.isSyncingPinnedStore = false }
        var current = clipboardItems
        if pinnedChanged {
            current = ClipboardPersistenceStore.savePinnedEntries(current)
        }
        if unpinnedChanged {
            let undoPaths = Set(clipboardRuntime.deletedUndoStack.flatMap { $0.entry.fileURLs.map(\.path) })
            current = ClipboardHistoryStore.saveHistoryEntries(current, protectedMediaPaths: undoPaths)
        }
        if current != clipboardItems { clipboardItems = current }
    }
}

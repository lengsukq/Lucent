import AppKit
import Foundation
import LumakeyCore

extension AppViewModel {
    private static let maxClipboardUndoDepth = 15

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
        var stack = deletedClipboardUndoStack
        stack.append((entry: removed, index: idx))
        var evicted: [ClipboardEntry] = []
        while stack.count > Self.maxClipboardUndoDepth {
            evicted.append(stack.removeFirst().entry)
        }
        deletedClipboardUndoStack = stack
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
        guard !deletedClipboardUndoStack.isEmpty else { return false }
        var stack = deletedClipboardUndoStack
        let last = stack.removeLast()
        deletedClipboardUndoStack = stack
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
        let removed = clipboardItems.filter { !$0.isPinned }
        clipboardItems.removeAll { !$0.isPinned }
        reclaimEvictedClipboardTempFiles(removed)
    }

    private func reclaimEvictedClipboardTempFiles(_ candidates: [ClipboardEntry]) {
        guard !candidates.isEmpty else { return }
        let activePaths = Set(
            (clipboardItems + deletedClipboardUndoStack.map(\.entry))
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
        if let entry = ClipboardService.captureCurrent(from: pb) {
            clipboardItems = ClipboardService.insert(entry, into: clipboardItems)
        }
    }

    func startClipboardMonitor() {
        stopClipboardMonitor()
        lastPasteboardChangeCount = NSPasteboard.general.changeCount
        clipboardTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1500), tolerance: .milliseconds(250))
                guard !Task.isCancelled, let self else { break }
                if self.isCapturingScreen || self.isClipboardPaused { continue }
                self.capturePasteboardOnceIfChanged()
            }
        }
    }

    func stopClipboardMonitor() {
        clipboardTask?.cancel()
        clipboardTask = nil
    }

    func loadPersistedPinnedClipboard() {
        let saved = ClipboardPersistenceStore.loadPinnedEntries()
        guard !saved.isEmpty else { return }
        isSyncingPinnedClipboardStore = true
        defer { isSyncingPinnedClipboardStore = false }
        clipboardItems = saved
    }

    func persistPinnedClipboardIfNeeded(previous: [ClipboardEntry]) {
        guard !isSyncingPinnedClipboardStore, clipboardItems.filter(\.isPinned) != previous.filter(\.isPinned) else { return }
        isSyncingPinnedClipboardStore = true
        defer { isSyncingPinnedClipboardStore = false }
        let migrated = ClipboardPersistenceStore.savePinnedEntries(clipboardItems)
        if migrated != clipboardItems { clipboardItems = migrated }
    }
}

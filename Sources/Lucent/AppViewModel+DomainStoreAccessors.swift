import Foundation
import LucentCore

/// Thin forwarding accessors from `AppViewModel` to dedicated domain stores (`ClipboardStore`, `DeviceServicesStore` & `WorkspaceStore`).
/// Keeps imperative coordinator/extension code ergonomic while isolating SwiftUI `objectWillChange` notifications per domain.
extension AppViewModel {
    var clipboardItems: [ClipboardEntry] {
        get { clipboard.clipboardItems }
        set {
            let previous = clipboard.clipboardItems
            guard newValue != previous else { return }
            clipboard.clipboardItems = newValue
            if isOverlayVisible { refreshDisplayedCandidates(resetSelection: false) }
            persistPinnedClipboardIfNeeded(previous: previous)
        }
    }
    var clipboardCategory: ClipboardCategory {
        get { clipboard.clipboardCategory }
        set {
            guard newValue != clipboard.clipboardCategory else { return }
            clipboard.clipboardCategory = newValue
            refreshDisplayedCandidates(resetSelection: true)
        }
    }
    var isClipboardPaused: Bool {
        get { clipboard.isClipboardPaused }
        set { clipboard.isClipboardPaused = newValue }
    }
    var canUndoClipboardDelete: Bool {
        get { clipboard.canUndoClipboardDelete }
        set { clipboard.canUndoClipboardDelete = newValue }
    }

    var mosConfig: MosConfig {
        get { deviceServices.mosConfig }
        set { deviceServices.mosConfig = newValue }
    }
    var mosTapActive: Bool {
        get { deviceServices.mosTapActive }
        set { deviceServices.mosTapActive = newValue }
    }
    var mosAccessibilityTrusted: Bool {
        get { deviceServices.mosAccessibilityTrusted }
        set { deviceServices.mosAccessibilityTrusted = newValue }
    }
    var lumaLinkConfig: LumaLinkConfig {
        get { deviceServices.lumaLinkConfig }
        set { deviceServices.lumaLinkConfig = newValue }
    }
    var lumaLinkStatus: LumaLinkRuntimeSnapshot {
        get { deviceServices.lumaLinkStatus }
        set { deviceServices.lumaLinkStatus = newValue }
    }
    var lumaLinkRdpStatus: LumaLinkRdpStatus {
        get { deviceServices.lumaLinkRdpStatus }
        set { deviceServices.lumaLinkRdpStatus = newValue }
    }

    var layoutMode: ExplorerLayoutMode {
        get { workspace.layoutMode }
        set { workspace.layoutMode = newValue }
    }
    var showWorkspacePreview: Bool {
        get { workspace.showWorkspacePreview }
        set { workspace.showWorkspacePreview = newValue }
    }
    var activePane: PaneSide {
        get { workspace.activePane }
        set { workspace.activePane = newValue }
    }
    var leftPane: PaneState {
        get { workspace.leftPane }
        set { workspace.leftPane = newValue }
    }
    var rightPane: PaneState {
        get { workspace.rightPane }
        set { workspace.rightPane = newValue }
    }
    var locations: [LocationItem] {
        get { workspace.locations }
        set { workspace.locations = newValue }
    }
    var selectedEntry: FileEntry? {
        get { workspace.selectedEntry }
        set { workspace.selectedEntry = newValue }
    }
    var selectedEntryIDs: Set<String> {
        get { workspace.selectedEntryIDs }
        set { workspace.selectedEntryIDs = newValue }
    }
    var previewState: PreviewContentState {
        get { workspace.previewState }
        set { workspace.previewState = newValue }
    }
    var computedSHA256: String? {
        get { workspace.computedSHA256 }
        set { workspace.computedSHA256 = newValue }
    }
    var isComputingSHA256: Bool {
        get { workspace.isComputingSHA256 }
        set { workspace.isComputingSHA256 = newValue }
    }
    var showBatchRenameSheet: Bool {
        get { workspace.showBatchRenameSheet }
        set { workspace.showBatchRenameSheet = newValue }
    }
    var renameRule: BatchRenameRule {
        get { workspace.renameRule }
        set { workspace.renameRule = newValue }
    }
    var workspaceClipboard: WorkspaceClipboardState? {
        get { workspace.workspaceClipboard }
        set { workspace.workspaceClipboard = newValue }
    }
    var workspaceSearchFocusToken: Int {
        get { workspace.workspaceSearchFocusToken }
        set { workspace.workspaceSearchFocusToken = newValue }
    }
}

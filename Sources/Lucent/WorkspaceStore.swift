import Combine
import Foundation
import LucentCore

/// Dedicated observable store for the on-demand File & External Disk Workspace (`⌥E`) and file preview state.
/// Isolates directory navigation, multi-selection, preview loading, and batch-rename mutations from
/// `AppViewModel.objectWillChange` so overlay, settings, and menu bar views do not needlessly redraw.
@MainActor
final class WorkspaceStore: ObservableObject {
    @Published var layoutMode: ExplorerLayoutMode = .single
    @Published var showWorkspacePreview: Bool = true
    @Published var activePane: PaneSide = .left
    @Published var leftPane: PaneState
    @Published var rightPane: PaneState

    @Published var locations: [LocationItem] = []
    @Published var selectedEntry: FileEntry?
    @Published var selectedEntryIDs: Set<String> = []
    @Published var previewState: PreviewContentState = .empty
    @Published var computedSHA256: String?
    @Published var isComputingSHA256: Bool = false

    @Published var showBatchRenameSheet: Bool = false
    @Published var renameRule = BatchRenameRule()
    @Published var workspaceClipboard: WorkspaceClipboardState?
    @Published var workspaceSearchFocusToken: Int = 0

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first ?? home
        let leftTab = WorkspaceTab(directoryURL: home)
        let rightTab = WorkspaceTab(directoryURL: desktop)
        self.leftPane = PaneState(tabs: [leftTab], activeTabID: leftTab.id)
        self.rightPane = PaneState(tabs: [rightTab], activeTabID: rightTab.id)
    }
}

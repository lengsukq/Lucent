import Combine
import Foundation
import LucentCore

/// Dedicated observable store for clipboard history and filter UI state.
/// Isolates background pasteboard polling mutations from `AppViewModel.objectWillChange`
/// so unrelated overlay, workspace, and settings views avoid unnecessary redraws.
@MainActor
final class ClipboardStore: ObservableObject {
    @Published var clipboardItems: [ClipboardEntry] = []
    @Published var clipboardCategory: ClipboardCategory = .all
    @Published var isClipboardPaused: Bool = false
    @Published var canUndoClipboardDelete: Bool = false
}

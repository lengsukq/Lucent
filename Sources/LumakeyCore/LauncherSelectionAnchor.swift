import Foundation

public struct ResolvedLauncherSelection: Sendable, Equatable {
    public let index: Int
    public let anchoredID: String?

    public init(index: Int, anchoredID: String?) {
        self.index = index
        self.anchoredID = anchoredID
    }
}

public enum LauncherSelectionAnchor {
    /// Resolves the next selected row index after a candidate refresh so background
    /// index merges, FSEvents updates, or usage telemetry never snap a user-moved
    /// selection back to row 0.
    public static func resolve(
        candidates: [LauncherCandidate],
        currentIndex: Int,
        userMovedSelection: Bool,
        anchoredID: String?
    ) -> ResolvedLauncherSelection {
        guard !candidates.isEmpty else {
            return ResolvedLauncherSelection(index: 0, anchoredID: nil)
        }
        guard userMovedSelection else {
            return ResolvedLauncherSelection(index: 0, anchoredID: nil)
        }
        if let anchoredID,
           let matchedIndex = candidates.firstIndex(where: { $0.id == anchoredID }) {
            return ResolvedLauncherSelection(index: matchedIndex, anchoredID: anchoredID)
        }
        let clamped = min(max(0, currentIndex), candidates.count - 1)
        return ResolvedLauncherSelection(index: clamped, anchoredID: candidates[clamped].id)
    }
}

import AppKit
import LucentCore
import QuickLookThumbnailing
import SwiftUI

@MainActor
private final class FileShelfRowUIState: ObservableObject {
    @Published var thumbnail: NSImage?
    @Published var hovered = false
}

struct FileShelfRowContent: View {
    let row: FileShelfRowState
    let activate: () -> Void
    @StateObject private var uiState = FileShelfRowUIState()

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LiquidColors.pillSurface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(LiquidColors.pillBorder, lineWidth: 0.7)
                    }
                if let thumbnail = uiState.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(3)
                } else {
                    Image(systemName: row.url == nil ? "doc.badge.ellipsis" : "doc.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(row.url == nil ? LiquidColors.textSecondary : Color.teal)
                }
            }
            .frame(width: 34, height: 34)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2.5) {
                Text(row.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(row.url == nil ? LiquidColors.textSecondary : LiquidColors.textPrimary)
                    .lineLimit(1).truncationMode(.middle)
                Text(row.detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(row.url == nil ? Color.orange : LiquidColors.textSecondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 4)
            if row.availability != nil {
                let label = row.url == nil ? L10n.pick("重新定位", "Locate") : L10n.pick("快速查看", "Quick Look")
                Button(action: activate) {
                    Image(systemName: row.url == nil ? "link" : "eye")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(uiState.hovered ? LiquidColors.accentPrimary : LiquidColors.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(uiState.hovered ? LiquidColors.pillSurface : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain).help(label).accessibilityLabel(label)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(uiState.hovered ? LiquidColors.pillSurface.opacity(0.85) : LiquidColors.cardSurface.opacity(0.42))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(uiState.hovered ? LiquidColors.pillBorder : LiquidColors.subtleRim.opacity(0.45), lineWidth: 0.65)
                }
        }
        .padding(.horizontal, 4)
        .onHover { uiState.hovered = $0 }
        .help("\(row.name) · \(row.detail)")
        .task(id: row.url) {
            uiState.thumbnail = nil
            guard let url = row.url else { return }
            let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
            if values?.isUbiquitousItem == true && values?.ubiquitousItemDownloadingStatus != .current { return }
            if let cgImage = await ShelfThumbnailLoader.loadCGImage(for: url), !Task.isCancelled {
                uiState.thumbnail = NSImage(cgImage: cgImage, size: NSSize(width: 34, height: 34))
            }
        }
    }
}

private enum ShelfThumbnailLoader {
    // QLThumbnailGenerator.cancel(_:) is thread-safe, while macOS 15.x SDK headers omit Sendable on Request/Representation.
    private final class RequestBox: @unchecked Sendable {
        let request: QLThumbnailGenerator.Request
        init(url: URL) {
            self.request = QLThumbnailGenerator.Request(
                fileAt: url, size: CGSize(width: 68, height: 68), scale: 2, representationTypes: [.icon, .thumbnail]
            )
        }
    }

    static func loadCGImage(for url: URL) async -> CGImage? {
        let box = RequestBox(url: url)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                QLThumbnailGenerator.shared.generateBestRepresentation(for: box.request) { representation, _ in
                    continuation.resume(returning: representation?.cgImage)
                }
            }
        } onCancel: {
            QLThumbnailGenerator.shared.cancel(box.request)
        }
    }
}

import AppKit
import LucentCore
import QuickLookThumbnailing
import SwiftUI

struct FileShelfActions {
    let togglePinOrAutoHide: () -> Void
    let toggleCollapseOrTuck: () -> Void
    let dockToEdge: (FileShelfDockEdge) -> Void
    let toggleEdgeAutoHide: () -> Void
    let toggleRemoveAfterDragOut: () -> Void
    let onDragTargetedChanged: (Bool) -> Void
    let onDragWillStart: () -> Void
    let onDragEnded: () -> Void
    let onDragCancelled: () -> Void
    let onSearchFocusChanged: (Bool) -> Void
    let onDraggedOut: (Set<UUID>) -> Void
    let close: () -> Void
    let preview: (FileShelfRowState) -> Void
    let locate: (FileShelfRowState) -> Void
    let clear: () -> Void
}

struct FileShelfEmptyStateView: View {
    let symbol: String
    let title: String
    let detail: String
    var onDragWillStart: (() -> Void)? = nil
    var onDragEnded: (() -> Void)? = nil
    var onDragCancelled: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: symbol).font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.teal).padding(.bottom, 2).accessibilityHidden(true)
            Text(title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(LiquidColors.textPrimary)
            if !detail.isEmpty {
                Text(detail).font(.system(size: 11.5)).foregroundStyle(LiquidColors.textSecondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18).frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .background {
            if onDragWillStart != nil || onDragEnded != nil || onDragCancelled != nil {
                FileShelfDragOverlay(onDragWillStart: onDragWillStart, onDragEnded: onDragEnded, onDragCancelled: onDragCancelled)
            }
        }
    }
}

struct FileShelfDropOverlayView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: LiquidRadii.windowPanel, style: .continuous)
            .fill(Color.teal.opacity(0.16))
            .overlay {
                Label(L10n.pick("松手放入中转站", "Drop to add to shelf"), systemImage: "arrow.down.to.line")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LiquidColors.textPrimary)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(LiquidColors.solidCardSurface, in: Capsule(style: .continuous))
                    .overlay { Capsule(style: .continuous).strokeBorder(Color.teal.opacity(0.45), lineWidth: 1) }
            }
            .allowsHitTesting(false)
    }
}

final class FileShelfDragNSView: NSView {
    var onTap: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onDragWillStart: (() -> Void)?
    var onDragEnded: (() -> Void)?
    var onDragCancelled: (() -> Void)?
    override var mouseDownCanMoveWindow: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(point) ? self : nil }

    override func mouseDown(with event: NSEvent) {
        guard let window else { super.mouseDown(with: event); return }
        if event.clickCount == 2, let onDoubleClick {
            onDoubleClick()
            return
        }
        let startOrigin = window.frame.origin
        onDragWillStart?()
        window.performDrag(with: event)
        let endOrigin = window.frame.origin
        if hypot(endOrigin.x - startOrigin.x, endOrigin.y - startOrigin.y) >= 3.0 {
            onDragEnded?()
        } else {
            onDragCancelled?()
            onTap?()
        }
    }
}

struct FileShelfDragOverlay: NSViewRepresentable {
    var onTap: (() -> Void)? = nil
    var onDoubleClick: (() -> Void)? = nil
    var onDragWillStart: (() -> Void)? = nil
    var onDragEnded: (() -> Void)? = nil
    var onDragCancelled: (() -> Void)? = nil

    func makeNSView(context: Context) -> FileShelfDragNSView {
        let view = FileShelfDragNSView()
        sync(view)
        return view
    }

    func updateNSView(_ nsView: FileShelfDragNSView, context: Context) { sync(nsView) }

    private func sync(_ v: FileShelfDragNSView) {
        v.onTap = onTap; v.onDoubleClick = onDoubleClick
        v.onDragWillStart = onDragWillStart; v.onDragEnded = onDragEnded; v.onDragCancelled = onDragCancelled
    }
}

struct FileShelfEdgeTabView: View {
    let edge: FileShelfDockEdge
    let itemCount: Int
    let isDropTarget: Bool
    let onTap: () -> Void
    var onDragWillStart: (() -> Void)? = nil
    var onDragEnded: (() -> Void)? = nil
    var onDragCancelled: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 8) {
            Capsule(style: .continuous)
                .fill(LinearGradient(colors: [.teal, .cyan], startPoint: .top, endPoint: .bottom))
                .frame(width: 4, height: 28)
            Image(systemName: "tray.full.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isDropTarget ? Color.white : Color.teal)
                .frame(width: 22, height: 22)
                .background(
                    isDropTarget ? Color.teal : Color.teal.opacity(0.14),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
            if itemCount > 0 {
                Text(itemCount, format: .number)
                    .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                    .foregroundStyle(LiquidColors.textPrimary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(LiquidColors.pillSurface, in: Capsule(style: .continuous))
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isDropTarget ? Color.teal.opacity(0.28) : Color.teal.opacity(0.06))
        .contentShape(Rectangle())
        .overlay {
            FileShelfDragOverlay(onTap: onTap, onDragWillStart: onDragWillStart, onDragEnded: onDragEnded, onDragCancelled: onDragCancelled)
        }
        .accessibilityLabel(L10n.pick("展开文件中转站", "Expand File Shelf"))
        .help(L10n.pick(
            "悬停、拖拽调位或点击展开中转站（\(edge == .left ? "左侧" : "右侧")贴边）",
            "Hover, drag to reposition, or click to expand File Shelf"
        ))
    }
}

struct FileShelfCapsuleView: View {
    let itemCount: Int
    let isDropTarget: Bool
    let onTap: () -> Void
    var onDragWillStart: (() -> Void)? = nil
    var onDragEnded: (() -> Void)? = nil
    var onDragCancelled: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            SquircleBadge(symbol: "tray.full.fill", topColor: .teal, bottomColor: .cyan, size: 26)
            Text(itemCount, format: .number)
                .font(.system(size: 14, weight: .bold).monospacedDigit())
                .foregroundStyle(LiquidColors.textPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isDropTarget ? Color.teal.opacity(0.20) : .clear)
        .contentShape(Rectangle())
        .overlay {
            FileShelfDragOverlay(onTap: onTap, onDragWillStart: onDragWillStart, onDragEnded: onDragEnded, onDragCancelled: onDragCancelled)
        }
        .accessibilityLabel(L10n.pick("展开文件中转站", "Expand File Shelf"))
        .accessibilityValue(Text(itemCount, format: .number))
    }
}

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

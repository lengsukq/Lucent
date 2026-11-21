import AppKit
import LucentCore
import SwiftUI

extension FileShelfDockEdge {
    var dockBadgeTitle: String {
        switch self {
        case .left: L10n.pick("左贴边", "Left Dock")
        case .top: L10n.pick("顶贴边", "Top Dock")
        case .right: L10n.pick("右贴边", "Right Dock")
        case .none: ""
        }
    }

    var tuckButtonSymbol: String {
        switch self {
        case .left: "chevron.compact.left"
        case .right: "chevron.compact.right"
        case .top: "chevron.compact.up"
        case .none: "rectangle.compress.vertical"
        }
    }
}

struct FileShelfActions {
    let togglePinOrAutoHide: () -> Void
    let toggleCollapseOrTuck: () -> Void
    let dockToEdge: (FileShelfDockEdge) -> Void
    let toggleEdgeAutoHide: () -> Void
    let toggleRemoveAfterDragOut: () -> Void
    let onDragTargetedChanged: (Bool) -> Void
    let onDragWillStart: () -> Void
    let onDragMoved: (CGRect, CGRect) -> Void
    let onDragEnded: (CGRect) -> Void
    let onSearchFocusChanged: (Bool) -> Void
    let onDraggedOut: (Set<UUID>) -> Void
    let close: () -> Void
    let preview: (FileShelfRowState) -> Void
    let locate: (FileShelfRowState) -> Void
    let clear: () -> Void
    let matchingPlugins: ([FileShelfRowState]) -> [(PluginDescriptor, PluginContextPayload)]
    let sendToPlugin: (PluginDescriptor, PluginContextPayload) -> Void
}

struct FileShelfHeaderButton: View {
    let symbol: String
    let active: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(active ? LiquidColors.accentPrimary : LiquidColors.textSecondary)
                .frame(width: 26, height: 26)
                .background(active ? LiquidColors.accentPrimary.opacity(0.16) : LiquidColors.pillSurface.opacity(0.65),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(LiquidBentoTileStyle(cornerRadius: 8)).help(label).accessibilityLabel(label)
    }
}

struct FileShelfPluginSendMenuButton: View {
    let matches: [(PluginDescriptor, PluginContextPayload)]
    let onSend: (PluginDescriptor, PluginContextPayload) -> Void

    var body: some View {
        if !matches.isEmpty {
            Menu {
                ForEach(matches, id: \.0.id) { plugin, ctx in
                    Button(plugin.displayName) { onSend(plugin, ctx) }
                }
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LiquidColors.accentPrimary)
                    .frame(width: 26, height: 26)
                    .background(LiquidColors.pillSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(L10n.pick("发送到扩展插件", "Send to Plugin"))
        }
    }
}

struct FileShelfEmptyStateView: View {
    let symbol: String
    let title: String
    let detail: String

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

struct FileShelfEdgeTabView: View {
    let edge: FileShelfDockEdge
    let itemCount: Int
    let isDropTarget: Bool
    let onTap: () -> Void
    var onDragWillStart: (() -> Void)? = nil
    var onDragMoved: ((CGRect, CGRect) -> Void)? = nil
    var onDragEnded: ((CGRect) -> Void)? = nil

    var body: some View {
        Group {
            if edge == .top { topStripContent } else { sideStripContent }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isDropTarget ? Color.teal.opacity(0.28) : Color.teal.opacity(0.06))
        .contentShape(Rectangle())
        .overlay {
            FileShelfDragOverlay(onTap: onTap, onDragWillStart: onDragWillStart, onDragMoved: onDragMoved, onDragEnded: onDragEnded)
        }
        .accessibilityLabel(L10n.pick("展开文件中转站", "Expand File Shelf"))
        .help(L10n.pick(
            "悬停、拖拽调位或点击展开中转站（\(edgeLabel)贴边）",
            "Hover, drag to reposition, or click to expand File Shelf"
        ))
    }

    private var edgeLabel: String {
        switch edge {
        case .left: "左侧"
        case .top: "顶部"
        case .right, .none: "右侧"
        }
    }

    private var topStripContent: some View {
        HStack(spacing: 6) {
            Image(systemName: "tray.full.fill")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(isDropTarget ? Color.white : Color.teal)
                .frame(width: 20, height: 20)
                .background(
                    isDropTarget ? Color.teal : Color.teal.opacity(0.14),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
            Text(L10n.pick("中转站", "Shelf"))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(LiquidColors.textPrimary)
                .lineLimit(1)
            if itemCount > 0 {
                Text(itemCount, format: .number)
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.teal)
                    .padding(.horizontal, 5).padding(.vertical, 1.5)
                    .background(Color.teal.opacity(0.14), in: Capsule(style: .continuous))
            }
        }
        .padding(.horizontal, 10)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(LinearGradient(colors: [.teal, .cyan], startPoint: .leading, endPoint: .trailing))
                .frame(height: 2.5)
                .opacity(0.9)
        }
    }

    private var sideStripContent: some View {
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
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(LiquidColors.pillSurface, in: Capsule(style: .continuous))
            }
        }
        .padding(.vertical, 10)
    }
}

struct FileShelfCapsuleView: View {
    let itemCount: Int
    let isDropTarget: Bool
    let onTap: () -> Void
    var onDragWillStart: (() -> Void)? = nil
    var onDragMoved: ((CGRect, CGRect) -> Void)? = nil
    var onDragEnded: ((CGRect) -> Void)? = nil

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
            FileShelfDragOverlay(onTap: onTap, onDragWillStart: onDragWillStart, onDragMoved: onDragMoved, onDragEnded: onDragEnded)
        }
        .accessibilityLabel(L10n.pick("展开文件中转站", "Expand File Shelf"))
        .accessibilityValue(Text(itemCount, format: .number))
    }
}

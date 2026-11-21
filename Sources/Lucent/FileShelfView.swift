import AppKit
import LucentCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
private final class FileShelfDropState: ObservableObject {
    @Published var isDropTarget = false
}

struct FileShelfView: View {
    @ObservedObject var model: FileShelfModel
    @ObservedObject var panelState: FileShelfPanelState
    @ObservedObject private var theme = ThemeManager.shared
    @StateObject private var dropState = FileShelfDropState()
    @FocusState private var searchFocused: Bool

    let actions: FileShelfActions

    private var cornerRadius: CGFloat {
        switch panelState.mode {
        case .edgeTucked: 12
        case .capsule: 22
        case .expanded: LiquidRadii.windowPanel
        }
    }

    var body: some View {
        let prefs = SystemDisplayPreferences.shared.snapshot
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Group {
            switch panelState.mode {
            case .edgeTucked(let edge):
                FileShelfEdgeTabView(
                    edge: edge, itemCount: model.rows.count, isDropTarget: dropState.isDropTarget,
                    onTap: actions.toggleCollapseOrTuck, onDragWillStart: actions.onDragWillStart,
                    onDragEnded: actions.onDragEnded, onDragCancelled: actions.onDragCancelled
                )
            case .capsule:
                FileShelfCapsuleView(
                    itemCount: model.rows.count, isDropTarget: dropState.isDropTarget,
                    onTap: actions.toggleCollapseOrTuck, onDragWillStart: actions.onDragWillStart,
                    onDragEnded: actions.onDragEnded, onDragCancelled: actions.onDragCancelled
                )
            case .expanded:
                expanded
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(shape.fill(prefs.reduceTransparency ? LiquidColors.solidCardSurface : LiquidColors.shellTint.opacity(0.84)))
        .clipShape(shape)
        .overlay {
            if dropState.isDropTarget {
                shape.strokeBorder(Color.teal, lineWidth: 2.0).allowsHitTesting(false)
            } else {
                DoubleSpecularBorder(cornerRadius: cornerRadius, isShell: true, highContrast: prefs.increaseContrast)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropState.isDropTarget, perform: accept)
        .onChange(of: dropState.isDropTarget) { _, targeted in
            actions.onDragTargetedChanged(targeted)
        }
        .onChange(of: searchFocused) { _, focused in
            actions.onSearchFocusChanged(focused)
        }
        .onExitCommand {
            if panelState.mode == .expanded { actions.toggleCollapseOrTuck() } else { actions.close() }
        }
        .contextMenu { shelfContextMenu }
        .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .easeOut(duration: 0.16), value: dropState.isDropTarget)
        .id("\(theme.current.rawValue)-\(theme.resolvedIsDark)")
    }

    private var expanded: some View {
        VStack(spacing: 0) {
            dragGripBar
            header
            if model.loadFailed {
                FileShelfEmptyStateView(symbol: "exclamationmark.folder",
                                        title: L10n.pick("中转站暂不可读", "Shelf unavailable"),
                                        detail: model.message ?? "")
                Button(L10n.pick("重新读取", "Retry"), action: model.reload)
                    .buttonStyle(GlassPillButtonStyle(prominent: true, compact: true))
                    .padding(.bottom, 16)
            } else {
                if !model.rows.isEmpty { filter }
                content
                footer
            }
        }
        .overlay {
            if dropState.isDropTarget { FileShelfDropOverlayView() }
        }
    }

    private var dragGripBar: some View {
        HStack {
            Spacer()
            Capsule(style: .continuous).fill(LiquidColors.textSecondary.opacity(0.28)).frame(width: 34, height: 4)
            Spacer()
        }
        .padding(.top, 7).padding(.bottom, 2).contentShape(Rectangle())
        .overlay { dragOverlay(onDoubleClick: { actions.dockToEdge(panelState.settings.dockEdge == .none ? .right : .none) }) }
    }

    private func dragOverlay(onDoubleClick: (() -> Void)? = nil) -> FileShelfDragOverlay {
        FileShelfDragOverlay(onDoubleClick: onDoubleClick, onDragWillStart: actions.onDragWillStart,
                             onDragEnded: actions.onDragEnded, onDragCancelled: actions.onDragCancelled)
    }

    private var header: some View {
        let isDocked = panelState.settings.dockEdge != .none
        let isPinned = !panelState.settings.edgeAutoHide || panelState.settings.pinnedExpanded
        return HStack(spacing: 10) {
            HStack(spacing: 10) {
                SquircleBadge(symbol: "tray.full.fill", topColor: LiquidColors.accentPrimary, bottomColor: .teal, size: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1.5) {
                    Text(L10n.pick("文件中转站", "File Shelf"))
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundStyle(LiquidColors.textPrimary)
                    HStack(spacing: 5) {
                        Text(L10n.pick("\(model.rows.count) 项", "\(model.rows.count) items")).monospacedDigit()
                        if isDocked {
                            Text("·")
                            Text(panelState.settings.dockEdge == .left ? L10n.pick("左贴边", "Left Dock") : L10n.pick("右贴边", "Right Dock"))
                                .foregroundStyle(Color.teal)
                        }
                    }
                    .font(.system(size: 10.5, weight: .medium)).foregroundStyle(LiquidColors.textSecondary)
                }
                Spacer(minLength: 4)
            }
            .contentShape(Rectangle())
            .overlay { dragOverlay() }
            if isDocked {
                headerButton(
                    symbol: isPinned ? "pin.fill" : "sidebar.right", active: isPinned,
                    label: isPinned ? L10n.pick("取消固定（恢复靠边自动隐藏）", "Unpin (enable edge auto-hide)")
                                    : L10n.pick("固定展开（暂停靠边自动隐藏）", "Pin open (pause auto-hide)"),
                    action: actions.togglePinOrAutoHide
                )
            } else {
                headerButton(
                    symbol: "arrow.right.to.line", active: false,
                    label: L10n.pick("贴靠屏幕右侧并自动隐藏", "Dock to right edge"),
                    action: { actions.dockToEdge(.right) }
                )
            }
            headerButton(
                symbol: isDocked ? "chevron.compact.right" : "rectangle.compress.vertical", active: false,
                label: isDocked ? L10n.pick("贴边收起", "Tuck to edge") : L10n.pick("收起为胶囊", "Collapse"),
                action: actions.toggleCollapseOrTuck
            )
            headerButton(symbol: "xmark", active: false, label: L10n.pick("关闭", "Close"), action: actions.close)
        }
        .padding(.horizontal, 14).padding(.top, 5).padding(.bottom, 10)
    }

    private var filter: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium))
                .foregroundStyle(LiquidColors.textSecondary).accessibilityHidden(true)
            TextField(L10n.pick("查找暂放文件", "Find on shelf"), text: $model.filter)
                .textFieldStyle(.plain).focused($searchFocused)
                .onChange(of: model.filter) { _, _ in model.selection.formIntersection(model.filteredRows.map(\.id)) }
            if !model.filter.isEmpty {
                Button { model.filter = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(LiquidColors.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 12.5)).padding(.horizontal, 10).frame(height: 32)
        .background(LiquidColors.inputFieldSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(LiquidColors.inputFieldBorder, lineWidth: 0.7) }
        .padding(.horizontal, 14).padding(.bottom, 9)
    }

    @ViewBuilder
    private var content: some View {
        if model.rows.isEmpty {
            FileShelfEmptyStateView(
                symbol: "tray.and.arrow.down",
                title: L10n.pick("拖入文件或文件夹", "Drop files or folders here"),
                detail: L10n.pick("仅保存文件引用，不复制占用空间；拖到屏幕左右边可自动贴边隐藏。",
                                  "Stores file references only. Drag to the screen edge to auto-tuck."),
                onDragWillStart: actions.onDragWillStart, onDragEnded: actions.onDragEnded, onDragCancelled: actions.onDragCancelled
            )
        } else if model.filteredRows.isEmpty {
            FileShelfEmptyStateView(
                symbol: "magnifyingglass", title: L10n.pick("没有匹配的文件", "No matching files"), detail: "",
                onDragWillStart: actions.onDragWillStart, onDragEnded: actions.onDragEnded, onDragCancelled: actions.onDragCancelled
            )
        } else {
            FileShelfTable(model: model, focusSearch: { searchFocused = true },
                           preview: actions.preview, locate: actions.locate, onDraggedOut: actions.onDraggedOut)
                .padding(.horizontal, 6)
        }
    }

    private var footer: some View {
        let autoRemove = panelState.settings.removeAfterDragOut
        return HStack(spacing: 6) {
            HStack(spacing: 0) {
                Text(model.message ?? (model.selection.isEmpty
                    ? L10n.pick("拖入或拖出文件 · 空格预览", "Drag in/out · Space to preview")
                    : L10n.pick("已选 \(model.selection.count) 项", "\(model.selection.count) selected")))
                    .font(.system(size: 10.5)).foregroundStyle(LiquidColors.textSecondary)
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
            }
            .contentShape(Rectangle())
            .overlay { dragOverlay() }
            Button(action: actions.toggleRemoveAfterDragOut) {
                HStack(spacing: 3.5) {
                    Image(systemName: autoRemove ? "flame.fill" : "flame")
                        .font(.system(size: 10, weight: .semibold))
                    Text(L10n.pick("拖出移出", "Pop"))
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(autoRemove ? Color.white : LiquidColors.textSecondary)
                .padding(.horizontal, 7).padding(.vertical, 3.5)
                .background(autoRemove ? Color.teal : LiquidColors.pillSurface, in: Capsule(style: .continuous))
            }
            .buttonStyle(LiquidBentoTileStyle(cornerRadius: 12))
            .help(L10n.pick("拖出到其他应用后自动从中转站移出（不删原文件）",
                            "Auto-remove items from shelf after dragging out (originals stay on disk)"))
            if !model.selectedRows.isEmpty {
                headerButton(symbol: "minus.circle", active: false, label: L10n.pick("移除所选", "Remove selected"), action: model.removeSelected)
            }
            if !model.rows.isEmpty {
                headerButton(symbol: "trash", active: false, label: L10n.pick("清空中转站", "Clear the shelf"), action: actions.clear)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .overlay(alignment: .top) { Divider().opacity(0.45) }
        .background {
            Button("", action: { searchFocused = true }).keyboardShortcut("f", modifiers: .command)
                .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var shelfContextMenu: some View {
        Button(L10n.pick("贴靠屏幕左侧", "Dock to Left Edge")) { actions.dockToEdge(.left) }
        Button(L10n.pick("贴靠屏幕右侧", "Dock to Right Edge")) { actions.dockToEdge(.right) }
        Button(L10n.pick("自由浮窗（不贴边）", "Float Freely")) { actions.dockToEdge(.none) }
        Divider()
        Button(panelState.settings.edgeAutoHide
               ? L10n.pick("✓ 靠边自动隐藏", "✓ Auto-Hide at Edge")
               : L10n.pick("靠边自动隐藏", "Auto-Hide at Edge")) { actions.toggleEdgeAutoHide() }
        Button(panelState.settings.removeAfterDragOut
               ? L10n.pick("✓ 拖出后自动移出", "✓ Remove After Drag-Out")
               : L10n.pick("拖出后自动移出", "Remove After Drag-Out")) { actions.toggleRemoveAfterDragOut() }
        Divider()
        Button(L10n.pick("关闭中转站", "Close File Shelf"), action: actions.close)
    }

    private func headerButton(symbol: String, active: Bool, label: String, action: @escaping () -> Void) -> some View {
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

    private func accept(_ providers: [NSItemProvider]) -> Bool {
        guard !model.loadFailed, !providers.isEmpty else { return false }
        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                if let url = await readURL(from: provider) { urls.append(url) }
            }
            model.add(urls)
        }
        return true
    }

    private func readURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                continuation.resume(returning: data.flatMap { URL(dataRepresentation: $0, relativeTo: nil) })
            }
        }
    }
}

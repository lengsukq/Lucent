import LucentCore
import LucentMedia
import SwiftUI

enum ScreenshotToolbarAction: Sendable {
    case undo, redo, deleteSelected, clear, syncClipboard, longShot, ocr, cutout, pin, save, cancel, copy
}

struct CaptureClampedToolbarLayout: Layout {
    var localSelection: CGRect?
    var horizontalAlign: FloatingOverlayHorizontalAlign
    var edgeMargin: CGFloat = 14
    var selectionGap: CGFloat = 10
    var fallbackTopY: CGFloat = 44

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let subview = subviews.first else { return }
        let maxAvailW = max(120, bounds.width - edgeMargin * 2)
        let ideal = subview.sizeThatFits(.unspecified)
        let proposedW = min(ideal.width, maxAvailW)
        let fitted = ideal.width > maxAvailW
            ? subview.sizeThatFits(ProposedViewSize(width: proposedW, height: nil))
            : ideal
        let center = CaptureSelectionGeometry.clampedFloatingToolbarCenter(
            selection: localSelection, viewportSize: bounds.size, toolbarSize: fitted,
            horizontalAlign: horizontalAlign, edgeMargin: edgeMargin,
            selectionGap: selectionGap, fallbackTopY: fallbackTopY
        )
        subview.place(
            at: CGPoint(x: bounds.minX + center.x, y: bounds.minY + center.y),
            anchor: .center,
            proposal: ProposedViewSize(width: fitted.width, height: fitted.height)
        )
    }
}

struct CaptureClampedBadgeLayout: Layout {
    var localSelection: CGRect
    var edgeMargin: CGFloat = 12
    var verticalGap: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let subview = subviews.first else { return }
        let maxBadgeW = max(120, bounds.width - edgeMargin * 2)
        let ideal = subview.sizeThatFits(.unspecified)
        let fitted = ideal.width > maxBadgeW
            ? subview.sizeThatFits(ProposedViewSize(width: maxBadgeW, height: nil))
            : ideal
        let center = CaptureSelectionGeometry.clampedSelectionBadgeCenter(
            selection: localSelection, viewportSize: bounds.size,
            badgeSize: fitted, edgeMargin: edgeMargin, verticalGap: verticalGap
        )
        subview.place(
            at: CGPoint(x: bounds.minX + center.x, y: bounds.minY + center.y),
            anchor: .center,
            proposal: ProposedViewSize(width: fitted.width, height: fitted.height)
        )
    }
}

@MainActor
final class ToolbarHoverTipState: ObservableObject {
    @Published var hoveredTip: String?
    var tipTask: Task<Void, Never>?
}

struct ScreenshotToolbarView: View {
    @ObservedObject var session: ScreenshotSessionState
    var maxAvailableWidth: CGFloat = 4096
    let onAction: (ScreenshotToolbarAction) -> Void

    @StateObject private var tipState = ToolbarHoverTipState()

    private var hiddenItems: Set<String> {
        GeneralPreferences.load().hiddenToolbarItemSet
    }

    private var visibleTools: [AnnotationToolKind] {
        AnnotationToolKind.allCases.filter { !hiddenItems.contains(ScreenshotToolbarItemID.forTool($0).rawValue) }
    }

    private var showStyleBar: Bool {
        session.activeTool != .move || session.selectedAnnotationID != nil
    }

    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                toolbarBodyContent.fixedSize(horizontal: true, vertical: false)
                ScrollView(.horizontal, showsIndicators: false) {
                    toolbarBodyContent.fixedSize(horizontal: true, vertical: false)
                }
                .frame(maxWidth: max(260, maxAvailableWidth))
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(LiquidColors.pillBorder, lineWidth: 1))
            .shadow(color: .black.opacity(0.32), radius: 18, y: 8)

            if let tip = tipState.hoveredTip {
                Text(tip)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 3.5)
                    .background(.black.opacity(0.82), in: Capsule())
                    .transition(.opacity)
            }
        }
        .animation(LiquidMotion.snappySpring, value: session.activeTool)
        .animation(LiquidMotion.snappySpring, value: session.selectedAnnotationID)
        .transition(.opacity.combined(with: .scale(scale: 0.94)))
    }

    private var toolbarBodyContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 3) {
                ForEach(visibleTools) { tool in
                    toolButton(tool)
                }

                if !visibleTools.isEmpty {
                    Divider().frame(height: 18).padding(.horizontal, 4)
                }

                if !hiddenItems.contains(ScreenshotToolbarItemID.actionUndoRedo.rawValue) {
                    actionIconButton("arrow.uturn.backward", tip: L10n.pick("撤销 · ⌘Z", "Undo · ⌘Z"), disabled: session.undoSnapshots.isEmpty) {
                        onAction(.undo)
                    }
                    actionIconButton("arrow.uturn.forward", tip: L10n.pick("重做 · ⇧⌘Z", "Redo · ⇧⌘Z"), disabled: session.redoSnapshots.isEmpty) {
                        onAction(.redo)
                    }
                }

                if session.selectedAnnotationID != nil {
                    actionIconButton("delete.left", tip: L10n.pick("删除选中标注 · ⌫", "Delete Selected · ⌫"), disabled: false) {
                        onAction(.deleteSelected)
                    }
                }

                if !hiddenItems.contains(ScreenshotToolbarItemID.actionClear.rawValue) {
                    actionIconButton("trash", tip: L10n.pick("清空全部标注", "Clear All"), disabled: session.annotations.isEmpty) {
                        onAction(.clear)
                    }
                }

                Divider().frame(height: 18).padding(.horizontal, 4)

                if session.selectedWindow != nil && !session.isPinEditSession {
                    actionTextButton(
                        session.excludeWindowShadow ? "macwindow" : "square.2.layers.3d.top.filled",
                        title: session.excludeWindowShadow ? L10n.pick("无阴影", "No Shadow") : L10n.pick("含阴影", "Shadow"),
                        tip: L10n.pick("切换独立窗口阴影", "Toggle Window Shadow"),
                        tint: .cyan
                    ) {
                        session.excludeWindowShadow.toggle()
                        var prefs = GeneralPreferences.load()
                        prefs.screenshotExcludeWindowShadow = session.excludeWindowShadow
                        prefs.save()
                        onAction(.syncClipboard)
                    }
                }

                if !session.isPinEditSession {
                    if !hiddenItems.contains(ScreenshotToolbarItemID.actionLongShot.rawValue) {
                        actionTextButton("arrow.up.and.down.text.horizontal", title: L10n.pick("长图", "Scroll"), tip: L10n.pick("手动滚动长截图 · S", "Scrolling Capture · S"), tint: .mint) {
                            onAction(.longShot)
                        }
                    }
                    if !hiddenItems.contains(ScreenshotToolbarItemID.actionOCR.rawValue) {
                        actionTextButton("text.viewfinder", title: "OCR", tip: L10n.pick("离线识字 · O", "Offline OCR · O"), tint: .purple) {
                            onAction(.ocr)
                        }
                    }
                    if !hiddenItems.contains(ScreenshotToolbarItemID.actionCutout.rawValue) {
                        actionTextButton("person.crop.rectangle", title: L10n.pick("抠图", "Cutout"), tip: L10n.pick("主体抠图", "Lift Subject"), tint: .orange) {
                            onAction(.cutout)
                        }
                    }
                    if !hiddenItems.contains(ScreenshotToolbarItemID.actionPin.rawValue) {
                        actionTextButton("pin.fill", title: L10n.pick("钉图", "Pin"), tip: L10n.pick("钉在桌面 · P", "Pin · P"), tint: .teal) {
                            onAction(.pin)
                        }
                    }
                    if !hiddenItems.contains(ScreenshotToolbarItemID.actionSave.rawValue) {
                        actionTextButton("square.and.arrow.down", title: L10n.pick("保存", "Save"), tip: L10n.pick("保存图片 · ⌘S", "Save · ⌘S"), tint: .secondary) {
                            onAction(.save)
                        }
                    }
                }

                Button { onAction(.cancel) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(LiquidColors.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(LiquidColors.pillSurface, in: RoundedRectangle(cornerRadius: 8))
                        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(LiquidColors.pillBorder, lineWidth: 0.7) }
                }
                .buttonStyle(LiquidBentoTileStyle(cornerRadius: 8))
                .onHover { scheduleTip($0 ? L10n.pick("取消 · Esc", "Cancel · Esc") : nil) }

                Button { onAction(.copy) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                        Text(session.isPinEditSession ? L10n.pick("更新钉图", "Apply") : L10n.pick("完成", "Done"))
                    }
                    .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(.white).padding(.horizontal, 10).frame(height: 28)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(LiquidBentoTileStyle(cornerRadius: 8))
                .fixedSize(horizontal: true, vertical: false)
                .onHover { scheduleTip($0 ? L10n.pick("完成 · Enter / ⌘C / 双击", "Done · Return / ⌘C") : nil) }
            }

            if showStyleBar {
                ScreenshotColorAndStyleBar(session: session)
                    .padding(.top, 2)
                    .transition(LiquidMotion.floatingPillTransition)
            }
        }
    }

    private func scheduleTip(_ text: String?) {
        tipState.tipTask?.cancel()
        guard let text else { tipState.hoveredTip = nil; return }
        tipState.tipTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(380))
            if !Task.isCancelled { tipState.hoveredTip = text }
        }
    }

    private func toolButton(_ tool: AnnotationToolKind) -> some View {
        let active = session.activeTool == tool
        return Button {
            session.commitTextAnnotation()
            tipState.tipTask?.cancel(); tipState.hoveredTip = nil
            withAnimation(LiquidMotion.snappySpring) { session.activeTool = tool }
        } label: {
            Image(systemName: tool.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(active ? .white : .primary)
                .frame(width: 27, height: 28)
                .background(active ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(LiquidBentoTileStyle(cornerRadius: 8))
        .onHover { scheduleTip($0 ? "\(tool.shortTitle) · \(tool.shortcutHint)" : nil) }
    }

    private func actionIconButton(_ symbol: String, tip: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            tipState.tipTask?.cancel(); tipState.hoveredTip = nil; action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(disabled ? .tertiary : .primary)
                .frame(width: 25, height: 28)
        }
        .buttonStyle(LiquidBentoTileStyle(cornerRadius: 7))
        .disabled(disabled)
        .onHover { if !disabled { scheduleTip($0 ? tip : nil) } }
    }

    private func actionTextButton(_ symbol: String, title: String, tip: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            tipState.tipTask?.cancel(); tipState.hoveredTip = nil; action()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: symbol).foregroundStyle(tint)
                Text(title).foregroundStyle(.primary)
            }
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 7).frame(height: 28)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(LiquidBentoTileStyle(cornerRadius: 8))
        .fixedSize(horizontal: true, vertical: false)
        .onHover { scheduleTip($0 ? tip : nil) }
    }
}

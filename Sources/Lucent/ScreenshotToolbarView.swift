import LucentCore
import SwiftUI

enum ScreenshotToolbarAction: Sendable {
    case undo, redo, clear, syncClipboard, ocr, cutout, pin, save, cancel, copy
}

/// Zero-macro synchronous SwiftUI `Layout` that measures the exact rendered size of the
/// Screenshot or GIF Recording floating toolbar and clamps its X/Y coordinates strictly
/// inside the display viewport margins (preventing left/right edge clipping on window snaps).
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
            selection: localSelection,
            viewportSize: bounds.size,
            toolbarSize: fitted,
            horizontalAlign: horizontalAlign,
            edgeMargin: edgeMargin,
            selectionGap: selectionGap,
            fallbackTopY: fallbackTopY
        )
        subview.place(
            at: CGPoint(x: bounds.minX + center.x, y: bounds.minY + center.y),
            anchor: .center,
            proposal: ProposedViewSize(width: fitted.width, height: fitted.height)
        )
    }
}

/// Zero-macro synchronous SwiftUI `Layout` that clamps window/selection info badges away from left/right edges.
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
            selection: localSelection,
            viewportSize: bounds.size,
            badgeSize: fitted,
            edgeMargin: edgeMargin,
            verticalGap: verticalGap
        )
        subview.place(
            at: CGPoint(x: bounds.minX + center.x, y: bounds.minY + center.y),
            anchor: .center,
            proposal: ProposedViewSize(width: fitted.width, height: fitted.height)
        )
    }
}

struct ScreenshotToolbarView: View {
    @ObservedObject var session: ScreenshotSessionState
    var maxAvailableWidth: CGFloat = 4096
    let onAction: (ScreenshotToolbarAction) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            toolbarBodyContent
                .fixedSize(horizontal: true, vertical: false)
            ScrollView(.horizontal, showsIndicators: false) {
                toolbarBodyContent
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(maxWidth: max(260, maxAvailableWidth))
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(LiquidColors.pillBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.32), radius: 18, y: 8)
        .animation(LiquidMotion.snappySpring, value: session.activeTool)
        .transition(.opacity.combined(with: .scale(scale: 0.94)))
    }

    private var toolbarBodyContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 3) {
                ForEach(AnnotationToolKind.allCases) { tool in
                    toolButton(tool)
                }

                Divider().frame(height: 18).padding(.horizontal, 4)

                actionIconButton("arrow.uturn.backward", label: L10n.pick("撤销 (⌘Z)", "Undo (⌘Z)"), disabled: session.annotations.isEmpty) {
                    onAction(.undo)
                }
                actionIconButton("arrow.uturn.forward", label: L10n.pick("重做 (⇧⌘Z)", "Redo (⇧⌘Z)"), disabled: session.redoStack.isEmpty) {
                    onAction(.redo)
                }
                actionIconButton("trash", label: L10n.pick("清空", "Clear"), disabled: session.annotations.isEmpty) {
                    onAction(.clear)
                }

                Divider().frame(height: 18).padding(.horizontal, 4)

                if session.selectedWindow != nil {
                    actionTextButton(
                        session.excludeWindowShadow ? "macwindow" : "square.2.layers.3d.top.filled",
                        title: session.excludeWindowShadow ? L10n.pick("无阴影", "No Shadow") : L10n.pick("含阴影", "Shadow"),
                        tint: .cyan
                    ) {
                        session.excludeWindowShadow.toggle()
                        var prefs = GeneralPreferences.load()
                        prefs.screenshotExcludeWindowShadow = session.excludeWindowShadow
                        prefs.save()
                        onAction(.syncClipboard)
                    }
                }

                actionTextButton("text.viewfinder", title: "OCR", tint: .purple) { onAction(.ocr) }
                actionTextButton("person.crop.rectangle", title: L10n.pick("抠图", "Cutout"), tint: .orange) { onAction(.cutout) }
                actionTextButton("pin.fill", title: L10n.pick("钉图", "Pin"), tint: .teal) { onAction(.pin) }
                actionTextButton("square.and.arrow.down", title: L10n.pick("保存", "Save"), tint: .secondary) { onAction(.save) }

                Button { onAction(.cancel) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(LiquidColors.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(LiquidColors.pillSurface, in: RoundedRectangle(cornerRadius: 8))
                        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(LiquidColors.pillBorder, lineWidth: 0.7) }
                }
                .buttonStyle(LiquidBentoTileStyle(cornerRadius: 8))
                .help(L10n.pick("取消截图 (Esc)", "Cancel (Esc)"))

                Button { onAction(.copy) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                        Text(L10n.pick("完成", "Done"))
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(LiquidBentoTileStyle(cornerRadius: 8))
                .fixedSize(horizontal: true, vertical: false)
                .help(L10n.pick("完成截图（已自动复制到剪贴板 · Enter / ⌘C / 双击）", "Done (Auto-copied · Enter / ⌘C / Double-click)"))
            }

            if session.activeTool != .move {
                HStack(spacing: 8) {
                    if session.activeTool != .spotlight {
                        HStack(spacing: 4) {
                            ForEach(AnnotationStrokeSize.allCases) { size in
                                Button {
                                    withAnimation(LiquidMotion.snappySpring) { session.strokeSize = size }
                                } label: {
                                    Text(size.label)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(session.strokeSize == size ? .white : LiquidColors.textSecondary)
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(session.strokeSize == size ? Color.accentColor : LiquidColors.pillSurface, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Divider().frame(height: 14)
                    }

                    if session.activeTool != .mosaic && session.activeTool != .spotlight {
                        HStack(spacing: 6) {
                            ForEach(AnnotationRGBColor.presets, id: \.self) { color in
                                let selected = session.selectedColor == color
                                Button {
                                    withAnimation(LiquidMotion.snappySpring) { session.selectedColor = color }
                                } label: {
                                    Circle()
                                        .fill(Color(cgColor: color.cgColor))
                                        .frame(width: 15, height: 15)
                                        .scaleEffect(selected ? 1.15 : 1.0)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color.white, lineWidth: selected ? 2.2 : 0.8)
                                                .padding(selected ? -2 : 0)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Divider().frame(height: 14)
                    }

                    Text(L10n.pick("1–0 切换工具 · ⌘Z 撤销 · ⇧⌘Z 重做 · 双击完成", "1–0 Switch Tools · ⌘Z Undo · ⇧⌘Z Redo"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
                .transition(LiquidMotion.floatingPillTransition)
            }
        }
    }

    private func toolButton(_ tool: AnnotationToolKind) -> some View {
        let active = session.activeTool == tool
        return Button {
            session.commitTextAnnotation()
            withAnimation(LiquidMotion.snappySpring) {
                session.activeTool = tool
            }
        } label: {
            Image(systemName: tool.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(active ? .white : .primary)
                .frame(width: 27, height: 28)
                .background(active ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(LiquidBentoTileStyle(cornerRadius: 8))
        .help(tool.displayName)
    }

    private func actionIconButton(_ symbol: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(disabled ? .tertiary : .primary)
                .frame(width: 25, height: 28)
        }
        .buttonStyle(LiquidBentoTileStyle(cornerRadius: 7))
        .disabled(disabled)
        .help(label)
    }

    private func actionTextButton(_ symbol: String, title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
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
    }
}

import AppKit
import LucentCore
import LucentFoundation
import SwiftUI

@MainActor
extension ScrollingCaptureController {
    func presentControlHUD(near selectionRect: NSRect, state: ScrollingCaptureState) {
        let visible = NSScreen.screens.first(where: { $0.frame.intersects(selectionRect) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let hudSize = NSSize(width: 540, height: 54)
        let hudFrame = MultiDisplayLayout.clampedHUDFrame(preferredSize: hudSize, near: selectionRect, visibleFrame: visible)
        let panel = NSPanel(
            contentRect: hudFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.sharingType = .none
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: LocalizedRootContainer {
            ScrollingCaptureControlHUD(
                state: state,
                onUndo: { [weak self] in self?.undoSegment() },
                onAnnotate: { [weak self] in self?.finishIntoAnnotator() },
                onPin: { [weak self] in self?.finishPin() },
                onSave: { [weak self] in self?.finishSave() },
                onCancel: { [weak self] in self?.finishCancel() },
                onDone: { [weak self] in self?.finishCopy() }
            )
        })
        panel.orderFrontRegardless()
        hudPanel = panel
    }

    func presentSidePreviewIfFits(near selectionRect: NSRect, state: ScrollingCaptureState) {
        let visible = NSScreen.screens.first(where: { $0.frame.intersects(selectionRect) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let rightSpace = visible.maxX - selectionRect.maxX
        let leftSpace = selectionRect.minX - visible.minX
        let maxSlotWidth = max(rightSpace, leftSpace) - 24
        guard maxSlotWidth >= 96 else { return }

        let slotWidth = min(168, maxSlotWidth)
        let slotHeight = min(max(selectionRect.height, 220), visible.height - 48)
        let x = rightSpace >= leftSpace
            ? selectionRect.maxX + 12
            : selectionRect.minX - slotWidth - 12
        let y = min(max(visible.minY + 20, selectionRect.minY), visible.maxY - slotHeight - 20)
        let frame = NSRect(x: x, y: y, width: slotWidth, height: slotHeight)

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.sharingType = .none
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: LocalizedRootContainer {
            ScrollingCaptureLiveThumbnailView(state: state, slotSize: frame.size)
        })
        panel.orderFrontRegardless()
        previewPanel = panel
    }
}

struct ScrollingCaptureControlHUD: View {
    @ObservedObject var state: ScrollingCaptureState
    let onUndo: () -> Void
    let onAnnotate: () -> Void
    let onPin: () -> Void
    let onSave: () -> Void
    let onCancel: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 6) {
                HStack(spacing: 5) {
                    Circle().fill(Color.mint).frame(width: 7, height: 7)
                    Text("\(state.pixelWidth)×\(state.pixelHeight) px")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.white.opacity(0.08), in: Capsule())

                Button(action: onUndo) {
                    Label(L10n.pick("撤回", "Undo"), systemImage: "arrow.uturn.backward")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(GlassPillButtonStyle(compact: true))
                .disabled(!state.canUndo)

                Button(action: onAnnotate) {
                    Label(L10n.pick("标注 (E)", "Edit (E)"), systemImage: "pencil.and.outline")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(GlassPillButtonStyle(compact: true))

                Button(action: onPin) {
                    Label(L10n.pick("钉图 (P)", "Pin (P)"), systemImage: "pin.fill")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(GlassPillButtonStyle(compact: true))

                Button(action: onSave) {
                    Label(L10n.pick("保存 (⌘S)", "Save"), systemImage: "square.and.arrow.down")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(GlassPillButtonStyle(compact: true))

                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(GlassPillButtonStyle(compact: true))

                Button(action: onDone) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                        Text(L10n.pick("完成", "Done"))
                    }
                    .font(.system(size: 11.5, weight: .semibold))
                }
                .buttonStyle(GlassPillButtonStyle(prominent: true, compact: true))
            }

            Text(state.hintMessage)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(LiquidColors.pillBorder, lineWidth: 1))
    }
}

struct ScrollingCaptureLiveThumbnailView: View {
    @ObservedObject var state: ScrollingCaptureState
    let slotSize: CGSize

    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            Spacer(minLength: 0)
            if let cg = state.previewImage {
                let ratio = CGFloat(cg.width) / max(CGFloat(cg.height), 1)
                let maxH = max(80, slotSize.height - 24)
                let fitW = min(slotSize.width - 8, maxH * ratio)
                let fitH = min(maxH, fitW / max(ratio, 0.02))
                Image(decorative: cg, scale: 1, orientation: .up)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: max(28, fitW), height: max(40, fitH))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.mint.opacity(0.85), lineWidth: 1.4))
            }
            Text(L10n.pick("实时拼接 (\(state.segmentCount) 段)", "Preview (\(state.segmentCount))"))
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 7).padding(.vertical, 2.5)
                .background(.black.opacity(0.72), in: Capsule())
        }
        .frame(width: slotSize.width, height: slotSize.height, alignment: .bottom)
    }
}

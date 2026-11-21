import AppKit
import LucentCore
import LucentMedia
import SwiftUI

struct ScreenshotModeGuidePill: View {
    let mode: ScreenshotMode
    let hasLastSelection: Bool
    var multiDisplay: Bool = false

    var body: some View {
        let lastHint = hasLastSelection ? " · R 恢复选区" : ""
        let multiHint = multiDisplay ? " · 跨屏框选" : ""
        let text = mode == .quickOCR
            ? "⚡ 离线识字：单击截窗或控件 (滚轮切深度 / Tab 切下层)\(multiHint)\(lastHint) · Esc 取消"
            : "单击截窗或子控件 (滚轮切深度 / Tab 切窗 / F 全屏)\(lastHint) · C 取色 · Esc 取消"
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(.black.opacity(0.72), in: Capsule())
            .allowsHitTesting(false)
    }
}

struct ScreenshotWindowSnapOverlay: View {
    let rect: CGRect
    let sliceSize: CGSize
    let label: String
    let overlapCount: Int
    var isSubControl: Bool = false

    var body: some View {
        let accent: Color = isSubControl ? .mint : .cyan
        let hint = isSubControl
            ? " · 滚轮切父级/整窗"
            : (overlapCount >= 2 ? " · Tab 切下层 (\(overlapCount))" : " · 单击选中")
        let visibleBadgeHost = rect.intersects(CGRect(origin: .zero, size: sliceSize))
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: isSubControl ? 6 : 8, style: .continuous)
                .strokeBorder(accent.opacity(0.95), lineWidth: 2.2)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
            if visibleBadgeHost {
                CaptureClampedBadgeLayout(localSelection: rect) {
                    HStack(spacing: 5) {
                        Image(systemName: isSubControl ? "viewfinder.rectangular" : "macwindow")
                            .font(.system(size: 10.5, weight: .bold)).foregroundStyle(accent)
                        Text("\(label)\(hint)").lineLimit(1)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(.black.opacity(0.78), in: Capsule())
                }
                .frame(width: sliceSize.width, height: sliceSize.height)
            }
        }
        .frame(width: sliceSize.width, height: sliceSize.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

struct ScreenshotSelectionChrome: View {
    let rect: CGRect
    let sliceSize: CGSize
    let pixelSizeText: String
    let windowTitle: String?
    let mode: ScreenshotMode
    var isLockedPinEdit: Bool = false

    var body: some View {
        let badgeVisible = rect.minX < sliceSize.width && rect.maxX > 0
        ZStack(alignment: .topLeading) {
            Rectangle()
                .strokeBorder(isLockedPinEdit ? Color.teal : Color.accentColor, lineWidth: 1.5)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

            if !isLockedPinEdit {
                ForEach(SelectionHandle.allCases, id: \.self) { handle in
                    let pt = handle.point(in: rect)
                    Circle()
                        .fill(Color.white)
                        .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 1.5))
                        .frame(width: 9, height: 9)
                        .position(pt)
                }
            }

            if badgeVisible {
                CaptureClampedBadgeLayout(localSelection: rect) {
                    HStack(spacing: 6) {
                        if isLockedPinEdit {
                            Image(systemName: "pin.fill").foregroundStyle(.teal)
                            Text(L10n.pick("钉图无损编辑", "Pin Edit"))
                            Text("·").foregroundStyle(.white.opacity(0.5))
                        } else if let windowTitle, !windowTitle.isEmpty {
                            Image(systemName: "macwindow.badge.plus").foregroundStyle(.cyan)
                            Text(windowTitle).lineLimit(1)
                            Text("·").foregroundStyle(.white.opacity(0.5))
                        }
                        Text(pixelSizeText)
                        if mode == .quickOCR {
                            Text("OCR").foregroundStyle(.purple)
                        }
                    }
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.black.opacity(0.76), in: RoundedRectangle(cornerRadius: 6))
                }
                .frame(width: sliceSize.width, height: sliceSize.height)
            }
        }
        .frame(width: sliceSize.width, height: sliceSize.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

struct ScreenshotLoupeView: View {
    @ObservedObject var session: ScreenshotSessionState
    let localCursor: CGPoint
    let sliceSize: CGSize

    var body: some View {
        let pt = session.cursorPoint
        let offsetX: CGFloat = localCursor.x + 150 > sliceSize.width ? -86 : 86
        let offsetY: CGFloat = localCursor.y + 150 > sliceSize.height ? -86 : 86
        let zoomedCG = ScreenshotCompositor.cropLoupeImage(
            from: session.topology.compositorSlices, at: pt, pointSize: 28
        )
        VStack(spacing: 4) {
            ZStack {
                if let zoomedCG {
                    Image(decorative: zoomedCG, scale: 1, orientation: .up)
                        .interpolation(.none).resizable().frame(width: 96, height: 96)
                }
                Rectangle().fill(Color.accentColor.opacity(0.65)).frame(width: 96, height: 1)
                Rectangle().fill(Color.accentColor.opacity(0.65)).frame(width: 1, height: 96)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.75), lineWidth: 1.5))

            VStack(spacing: 1) {
                Text("\(session.cursorHex) · \(Int(pt.x)),\(Int(pt.y))")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                Text("C 复制 HEX · ⇧C 复制 RGB")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 6))
        }
        .position(x: localCursor.x + offsetX, y: localCursor.y + offsetY)
        .allowsHitTesting(false)
    }
}

struct ScreenshotInlineTextEditor: View {
    @ObservedObject var session: ScreenshotSessionState
    let localPoint: CGPoint
    let sliceSize: CGSize

    var body: some View {
        let fieldWidth: CGFloat = session.isEditingCounterNumber ? 96 : 240
        let fSize = session.isEditingCounterNumber ? 16 : max(14, session.strokeSize.fontSize * session.activeCustomScale)
        AutoFocusAnnotationTextField(
            text: $session.pendingTextValue,
            placeholder: session.isEditingCounterNumber ? "输入序号" : "输入文字，回车确认",
            fontSize: fSize,
            color: session.isEditingCounterNumber ? .white : (NSColor(cgColor: session.selectedColor.cgColor) ?? .systemRed),
            onCommit: { session.commitTextAnnotation() },
            onCancel: { session.cancelPendingText() }
        )
        .padding(.horizontal, 6).padding(.vertical, 4)
        .frame(width: fieldWidth, height: max(30, fSize + 14))
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(cgColor: session.selectedColor.cgColor), lineWidth: 1.2))
        .position(
            x: min(max(fieldWidth * 0.5 + 10, localPoint.x + fieldWidth * 0.5), max(fieldWidth * 0.5 + 10, sliceSize.width - fieldWidth * 0.5 - 10)),
            y: min(max(24, localPoint.y + 16), max(24, sliceSize.height - 24))
        )
    }
}

struct AutoFocusAnnotationTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = "输入文字，回车确认"
    let fontSize: CGFloat
    let color: NSColor
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.placeholderString = placeholder
        field.isBordered = false; field.drawsBackground = false; field.focusRingType = .none
        field.font = .systemFont(ofSize: fontSize, weight: .bold)
        field.textColor = color; field.delegate = context.coordinator
        DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        if nsView.stringValue != text { nsView.stringValue = text }
        nsView.font = .systemFont(ofSize: fontSize, weight: .bold)
        nsView.textColor = color
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AutoFocusAnnotationTextField
        init(parent: AutoFocusAnnotationTextField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSTextField, parent.text != field.stringValue { parent.text = field.stringValue }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if textView.hasMarkedText() { return false }
            if selector == #selector(NSResponder.insertNewline(_:)) { parent.onCommit(); return true }
            if selector == #selector(NSResponder.cancelOperation(_:)) { parent.onCancel(); return true }
            return false
        }
    }
}

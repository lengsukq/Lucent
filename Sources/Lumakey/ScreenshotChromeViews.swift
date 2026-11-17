import AppKit
import LumakeyCore
import SwiftUI

struct ScreenshotModeGuidePill: View {
    let mode: ScreenshotMode
    let hasLastSelection: Bool
    var multiDisplay: Bool = false

    var body: some View {
        let lastHint = hasLastSelection ? " · R 恢复选区" : ""
        let multiHint = multiDisplay ? " · 支持跨屏框选" : ""
        let text = mode == .quickOCR
            ? "⚡ 离线识字：单击精准截窗 (Tab 切下层)\(multiHint)\(lastHint) · 右键/Esc 取消"
            : "单击精准截应用窗 (Tab 切重叠窗 / ⌥去阴影)\(multiHint)\(lastHint) · C 取色 · 右键/Esc 取消"
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

    var body: some View {
        let hint = overlapCount >= 2 ? " · Tab 切下层 (\(overlapCount))" : " · 单击截整窗"
        let visibleBadgeHost = rect.intersects(CGRect(origin: .zero, size: sliceSize))
        let badgeX = min(max(130, rect.minX + 120), max(130, sliceSize.width - 130))
        let badgeY = rect.minY > 28 ? rect.minY - 14 : max(18, rect.minY + 18)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.cyan.opacity(0.95), lineWidth: 2.2)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
            if visibleBadgeHost {
                HStack(spacing: 5) {
                    Image(systemName: "macwindow").font(.system(size: 10.5, weight: .bold)).foregroundStyle(.cyan)
                    Text("\(label)\(hint)").lineLimit(1)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(.black.opacity(0.78), in: Capsule())
                .position(x: badgeX, y: min(badgeY, sliceSize.height - 18))
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

    var body: some View {
        let badgeVisible = rect.minX < sliceSize.width && rect.maxX > 0
        let badgeX = min(max(110, rect.minX + 100), max(110, sliceSize.width - 110))
        let badgeY = rect.minY > 28 ? rect.minY - 14 : max(16, rect.minY + 14)
        ZStack(alignment: .topLeading) {
            Rectangle()
                .strokeBorder(Color.accentColor, lineWidth: 1.5)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

            ForEach(SelectionHandle.allCases, id: \.self) { handle in
                let pt = handle.point(in: rect)
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 1.5))
                    .frame(width: 9, height: 9)
                    .position(pt)
            }

            if badgeVisible {
                HStack(spacing: 6) {
                    if let windowTitle, !windowTitle.isEmpty {
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
                .position(x: badgeX, y: min(badgeY, sliceSize.height - 18))
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
        AutoFocusAnnotationTextField(
            text: $session.pendingTextValue,
            fontSize: session.strokeSize.fontSize,
            color: NSColor(cgColor: session.selectedColor.cgColor) ?? .systemRed,
            onCommit: { session.commitTextAnnotation() },
            onCancel: { session.pendingTextPoint = nil; session.pendingTextValue = "" }
        )
        .padding(.horizontal, 6).padding(.vertical, 4)
        .frame(width: 240, height: max(30, session.strokeSize.fontSize + 14))
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(cgColor: session.selectedColor.cgColor), lineWidth: 1.2))
        .position(x: min(max(130, localPoint.x + 120), max(130, sliceSize.width - 130)), y: min(max(24, localPoint.y + 16), max(24, sliceSize.height - 24)))
    }
}

struct AutoFocusAnnotationTextField: NSViewRepresentable {
    @Binding var text: String
    let fontSize: CGFloat
    let color: NSColor
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.placeholderString = "输入文字，回车确认"
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

enum ScreenshotAnnotationRenderer {
    static func renderMosaicMask(_ item: ScreenshotAnnotation, in ctx: inout GraphicsContext) {
        guard item.tool == .mosaic, let first = item.points.first else { return }
        var p = Path(); p.move(to: first)
        for pt in item.points.dropFirst() { p.addLine(to: pt) }
        ctx.stroke(p, with: .color(.white), style: StrokeStyle(lineWidth: item.strokeSize.mosaicBrushRadius * 1.6, lineCap: .round, lineJoin: .round))
    }

    static func renderSpotlightOverlay(_ items: [ScreenshotAnnotation], selection: CGRect, in ctx: inout GraphicsContext) {
        guard !items.isEmpty else { return }
        var p = Path()
        p.addRect(selection)
        for item in items {
            guard let a = item.points.first, let b = item.points.last else { continue }
            let hole = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
            if hole.width >= 2 && hole.height >= 2 {
                p.addRoundedRect(in: hole, cornerSize: CGSize(width: min(8, hole.width / 4), height: min(8, hole.height / 4)))
            }
        }
        ctx.fill(p, with: .color(.black.opacity(0.54)), style: FillStyle(eoFill: true))
    }

    static func render(_ item: ScreenshotAnnotation, in ctx: inout GraphicsContext) {
        let color = Color(cgColor: item.color.cgColor)
        switch item.tool {
        case .move, .mosaic, .spotlight: break
        case .rect:
            guard let a = item.points.first, let b = item.points.last else { break }
            ctx.stroke(Path(CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))), with: .color(color), lineWidth: item.strokeSize.lineWidth)
        case .ellipse:
            guard let a = item.points.first, let b = item.points.last else { break }
            ctx.stroke(Path(ellipseIn: CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))), with: .color(color), lineWidth: item.strokeSize.lineWidth)
        case .line:
            guard let a = item.points.first, let b = item.points.last else { break }
            var line = Path(); line.move(to: a); line.addLine(to: b)
            ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: item.strokeSize.lineWidth, lineCap: .round))
        case .arrow:
            guard let a = item.points.first, let b = item.points.last else { break }
            let dx = b.x - a.x, dy = b.y - a.y, len = hypot(dx, dy)
            guard len > 1 else { break }
            let ux = dx / len, uy = dy / len, headLen = max(12, item.strokeSize.lineWidth * 3.2), headHalfW = headLen * 0.48
            var line = Path(); line.move(to: a); line.addLine(to: CGPoint(x: b.x - ux * headLen * 0.72, y: b.y - uy * headLen * 0.72))
            ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: item.strokeSize.lineWidth, lineCap: .round))
            var head = Path(); head.move(to: b)
            head.addLine(to: CGPoint(x: b.x - ux * headLen + uy * headHalfW, y: b.y - uy * headLen - ux * headHalfW))
            head.addLine(to: CGPoint(x: b.x - ux * headLen - uy * headHalfW, y: b.y - uy * headLen + ux * headHalfW))
            head.closeSubpath(); ctx.fill(head, with: .color(color))
        case .pen, .highlighter:
            guard let first = item.points.first else { break }
            var p = Path(); p.move(to: first)
            for pt in item.points.dropFirst() { p.addLine(to: pt) }
            let strokeW = item.tool == .highlighter ? item.strokeSize.lineWidth * 3.0 : item.strokeSize.lineWidth
            ctx.stroke(p, with: .color(item.tool == .highlighter ? color.opacity(0.36) : color), style: StrokeStyle(lineWidth: strokeW, lineCap: .round, lineJoin: .round))
        case .counter:
            guard let c = item.points.first else { break }
            let r: CGFloat = 12 + item.strokeSize.lineWidth * 0.4
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(color))
            ctx.draw(Text("\(item.counterIndex)").font(.system(size: r * 1.15, weight: .bold)).foregroundStyle(.white), at: c)
        case .text:
            guard let pt = item.points.first, !item.text.isEmpty else { break }
            ctx.draw(Text(item.text).font(.system(size: item.strokeSize.fontSize, weight: .bold)).foregroundStyle(color), at: pt, anchor: .topLeading)
        }
    }
}

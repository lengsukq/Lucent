import AppKit
import LucentCore
import LucentMedia
import SwiftUI

@MainActor
final class SwatchPopoverUIState: ObservableObject {
    @Published var editingSwatchIndex: Int?
    @Published var pickerColor: Color = .red
}

struct ScreenshotColorAndStyleBar: View {
    @ObservedObject var session: ScreenshotSessionState
    @StateObject private var ui = SwatchPopoverUIState()

    private var effectiveTool: AnnotationToolKind {
        if let selID = session.selectedAnnotationID,
           let item = session.annotations.first(where: { $0.id == selID }) {
            return item.tool
        }
        return session.activeTool
    }

    private var currentIsFilled: Bool {
        if let selID = session.selectedAnnotationID,
           let item = session.annotations.first(where: { $0.id == selID }) {
            return item.isFilled
        }
        return session.activeIsFilled
    }

    private var currentLineStyle: AnnotationLineStyle {
        if let selID = session.selectedAnnotationID,
           let item = session.annotations.first(where: { $0.id == selID }) {
            return item.lineStyle
        }
        return session.activeLineStyle
    }

    var body: some View {
        let tool = effectiveTool
        HStack(spacing: 8) {
            if tool != .spotlight {
                strokeSizeControls
                Divider().frame(height: 14)
            }

            if tool == .rect || tool == .ellipse {
                fillToggleButton
            }

            if [.rect, .ellipse, .line, .arrow, .pen].contains(tool) {
                lineStyleSegmented
                Divider().frame(height: 14)
            }

            if tool != .mosaic && tool != .blur && tool != .spotlight {
                colorSwatchesRow
                Divider().frame(height: 14)
            }

            Text(L10n.pick(
                "滚轮调粗细 · ⇧ 正圆/45° · ⌘拖/框边移对象 · ⌫ 单删",
                "Wheel size · ⇧ snap · ⌘-drag move · ⌫ delete"
            ))
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    private var strokeSizeControls: some View {
        HStack(spacing: 4) {
            ForEach(AnnotationStrokeSize.allCases) { size in
                let active = session.strokeSize == size
                Button {
                    withAnimation(LiquidMotion.snappySpring) {
                        session.strokeSize = size
                        session.activeCustomScale = 1.0
                        session.applyStyleMutation { $0.strokeSize = size; $0.customScale = 1.0 }
                    }
                } label: {
                    Text(size.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(active ? .white : LiquidColors.textSecondary)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(active ? Color.accentColor : LiquidColors.pillSurface, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var fillToggleButton: some View {
        let filled = currentIsFilled
        return Button {
            let next = !filled
            session.activeIsFilled = next
            session.applyStyleMutation { $0.isFilled = next }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: filled ? "square.fill" : "square")
                    .font(.system(size: 10, weight: .bold))
                Text(L10n.pick("填充", "Fill"))
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundStyle(filled ? .white : LiquidColors.textSecondary)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(filled ? Color.accentColor : LiquidColors.pillSurface, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var lineStyleSegmented: some View {
        let activeStyle = currentLineStyle
        return HStack(spacing: 3) {
            ForEach(AnnotationLineStyle.allCases) { style in
                let selected = activeStyle == style
                Button {
                    session.activeLineStyle = style
                    session.applyStyleMutation { $0.lineStyle = style }
                } label: {
                    Text(style.label)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(selected ? .white : LiquidColors.textSecondary)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(selected ? Color.accentColor : LiquidColors.pillSurface, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var colorSwatchesRow: some View {
        HStack(spacing: 6) {
            ForEach(Array(session.swatches.enumerated()), id: \.offset) { idx, color in
                let selected = !session.isUsingGradient && session.selectedColor == color
                Circle()
                    .fill(Color(cgColor: color.cgColor))
                    .frame(width: 15, height: 15)
                    .scaleEffect(selected ? 1.15 : 1.0)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white, lineWidth: selected ? 2.2 : 0.8)
                            .padding(selected ? -2 : 0)
                    )
                    .contentShape(Circle())
                    .onTapGesture(count: 2) {
                        ui.pickerColor = Color(cgColor: color.cgColor)
                        ui.editingSwatchIndex = idx
                    }
                    .onTapGesture(count: 1) {
                        session.isUsingGradient = false
                        session.selectedColor = color
                        session.applyStyleMutation { $0.color = color; $0.gradient = nil }
                    }
                    .popover(
                        isPresented: Binding(
                            get: { ui.editingSwatchIndex == idx },
                            set: { if !$0 && ui.editingSwatchIndex == idx { ui.editingSwatchIndex = nil } }
                        ),
                        arrowEdge: .top
                    ) {
                        swatchEditorPopover(index: idx)
                    }
                    .help(L10n.pick("单击使用 \(color.hexString) · 双击自定义改色", "Click to use \(color.hexString) · Double-click to customize"))
            }

            let white = AnnotationRGBColor(red: 1, green: 1, blue: 1)
            let whiteSelected = !session.isUsingGradient && session.selectedColor == white
            Button {
                session.isUsingGradient = false
                session.selectedColor = white
                session.applyStyleMutation { $0.color = white; $0.gradient = nil }
            } label: {
                Circle()
                    .fill(Color.white)
                    .frame(width: 15, height: 15)
                    .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: whiteSelected ? 2.2 : 0.7))
            }
            .buttonStyle(.plain)

            gradientChip
        }
    }

    private var gradientChip: some View {
        let presets = AnnotationGradientPreset.presets
        let preset = presets[session.activeGradientIndex % presets.count]
        let active = session.isUsingGradient
        return Circle()
            .fill(
                LinearGradient(
                    colors: [
                        Color(cgColor: preset.start.cgColor),
                        Color(cgColor: preset.mid.cgColor),
                        Color(cgColor: preset.end.cgColor)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 16, height: 16)
            .scaleEffect(active ? 1.15 : 1.0)
            .overlay(
                Circle()
                    .strokeBorder(Color.white, lineWidth: active ? 2.2 : 0.9)
                    .padding(active ? -2 : 0)
            )
            .onTapGesture(count: 2) {
                session.isUsingGradient = true
                session.activeGradientIndex = (session.activeGradientIndex + 1) % presets.count
                let nextGrad = presets[session.activeGradientIndex]
                session.applyStyleMutation { $0.gradient = nextGrad }
            }
            .onTapGesture(count: 1) {
                session.isUsingGradient = true
                session.applyStyleMutation { $0.gradient = preset }
            }
            .help(L10n.pick("渐变色块：单击使用 · 双击换一套配色", "Gradient: Click to apply · Double-click for next palette"))
    }

    private func swatchEditorPopover(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.pick("自定义色块 #\(index + 1)", "Customize Swatch #\(index + 1)"))
                .font(.caption.weight(.semibold))
            ColorPicker(L10n.pick("选择颜色", "Pick Color"), selection: $ui.pickerColor, supportsOpacity: false)
                .font(.caption)
            HStack {
                Spacer()
                Button(L10n.pick("保存", "Save")) {
                    if let ns = NSColor(ui.pickerColor).usingColorSpace(.sRGB) {
                        let rgb = AnnotationRGBColor(
                            red: Double(ns.redComponent),
                            green: Double(ns.greenComponent),
                            blue: Double(ns.blueComponent)
                        )
                        session.updateCustomSwatch(at: index, to: rgb)
                    }
                    ui.editingSwatchIndex = nil
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(10)
        .frame(width: 190)
    }
}

import AppKit
import LumakeyCore
import SwiftUI

struct FrostedWindowVisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material; view.blendingMode = .behindWindow; view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        if nsView.material != material { nsView.material = material }
        nsView.state = .active
    }
}

struct LiquidFluidBackdrop: View {
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        let reduceTransparency = SystemDisplayPreferences.shared.reduceTransparency
        let isPrism = themeManager.current == .prismPulse
        ZStack {
            if !reduceTransparency {
                FrostedWindowVisualEffectView(material: isPrism ? .underWindowBackground : .windowBackground)
                    .ignoresSafeArea()
            }
            LiquidColors.canvasBase.opacity(reduceTransparency ? 1.0 : (isPrism ? 0.42 : 0.76))
            if !reduceTransparency && isPrism {
                RadialGradient(colors: [Color.cyan.opacity(0.20), .clear], center: .topLeading, startRadius: 16, endRadius: 540)
                RadialGradient(colors: [Color.orange.opacity(0.13), .clear], center: .topTrailing, startRadius: 20, endRadius: 460)
                RadialGradient(colors: [Color.pink.opacity(0.16), Color.indigo.opacity(0.14), .clear], center: .bottomTrailing, startRadius: 24, endRadius: 620)
            }
        }
        .ignoresSafeArea()
    }
}

struct LiquidGlassShellModifier: ViewModifier {
    let cornerRadius: CGFloat
    @ObservedObject private var themeManager = ThemeManager.shared

    func body(content: Content) -> some View {
        let prefs = SystemDisplayPreferences.shared.snapshot
        let isPrism = themeManager.current == .prismPulse
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                ZStack {
                    if !prefs.reduceTransparency { shape.fill(isPrism ? .ultraThinMaterial : .regularMaterial) }
                    shape.fill(prefs.reduceTransparency ? LiquidColors.solidCardSurface : LiquidColors.shellTint)
                    if !prefs.reduceTransparency && isPrism {
                        RadialGradient(colors: [Color.cyan.opacity(0.15), .clear], center: .topLeading, startRadius: 8, endRadius: 380)
                        RadialGradient(colors: [Color.pink.opacity(0.12), .clear], center: .topTrailing, startRadius: 10, endRadius: 340)
                        RadialGradient(colors: [Color.purple.opacity(0.12), .clear], center: .bottomLeading, startRadius: 14, endRadius: 380)
                        LinearGradient(colors: [.white.opacity(0.18), .clear], startPoint: .top, endPoint: .center)
                    }
                }
            }
            .clipShape(shape)
            .overlay { DoubleSpecularBorder(cornerRadius: cornerRadius, isShell: true, highContrast: prefs.increaseContrast) }
    }
}

struct LiquidGlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let solidReadable: Bool
    @ObservedObject private var themeManager = ThemeManager.shared

    func body(content: Content) -> some View {
        let prefs = SystemDisplayPreferences.shared.snapshot
        let isPrism = themeManager.current == .prismPulse
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                ZStack {
                    if !prefs.reduceTransparency {
                        shape.fill((solidReadable || !isPrism) ? .regularMaterial : .ultraThinMaterial)
                    }
                    shape.fill(prefs.reduceTransparency ? LiquidColors.solidCardSurface : (solidReadable ? LiquidColors.elevatedSurface : LiquidColors.cardSurface))
                    if !prefs.reduceTransparency && isPrism {
                        LinearGradient(colors: [.white.opacity(0.15), .clear], startPoint: .topLeading, endPoint: .center)
                    }
                }
            }
            .clipShape(shape)
            .overlay { DoubleSpecularBorder(cornerRadius: cornerRadius, isShell: false, highContrast: prefs.increaseContrast) }
            .shadow(color: .black.opacity(prefs.reduceTransparency ? 0.07 : (isPrism ? 0.065 : 0.035)), radius: isPrism ? 10 : 5, y: isPrism ? 4 : 2)
    }
}

final class DragRegionNSView: NSView {
    var onDoubleClick: (() -> Void)?
    override var intrinsicContentSize: NSSize { NSSize(width: 1, height: 1) }
    override var mouseDownCanMoveWindow: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2, let onDoubleClick { onDoubleClick(); return }
        window?.performDrag(with: event)
    }
}

struct WindowDragRegion: NSViewRepresentable {
    var onDoubleClick: (() -> Void)? = nil
    func makeNSView(context: Context) -> DragRegionNSView { let v = DragRegionNSView(); v.onDoubleClick = onDoubleClick; return v }
    func updateNSView(_ nsView: DragRegionNSView, context: Context) { nsView.onDoubleClick = onDoubleClick }
}

extension View {
    func liquidGlassShell(cornerRadius: CGFloat = LiquidRadii.panel) -> some View {
        modifier(LiquidGlassShellModifier(cornerRadius: cornerRadius))
    }

    func liquidGlassCard(cornerRadius: CGFloat = LiquidRadii.card, solidReadable: Bool = false) -> some View {
        modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius, solidReadable: solidReadable))
    }
}

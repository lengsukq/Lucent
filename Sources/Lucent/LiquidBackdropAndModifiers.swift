import AppKit
import LucentCore
import SwiftUI

struct FrostedWindowVisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
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
        let isDark = themeManager.resolvedIsDark
        ZStack {
            if !reduceTransparency {
                FrostedWindowVisualEffectView(material: .underWindowBackground)
                    .ignoresSafeArea()
            }
            LiquidColors.canvasBase.opacity(reduceTransparency ? 1.0 : (isDark ? 0.56 : 0.68))
            if !reduceTransparency {
                LinearGradient(
                    colors: [Color.white.opacity(isDark ? 0.045 : 0.24), .clear],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.34)
                )
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
        let isDark = themeManager.resolvedIsDark
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                ZStack {
                    if !prefs.reduceTransparency {
                        shape.fill(.ultraThinMaterial)
                    }
                    shape.fill(prefs.reduceTransparency ? LiquidColors.solidCardSurface : LiquidColors.shellTint)
                    if !prefs.reduceTransparency {
                        shape.fill(
                            LinearGradient(
                                colors: [Color.white.opacity(isDark ? 0.08 : 0.30), .clear],
                                startPoint: .top,
                                endPoint: UnitPoint(x: 0.5, y: 0.28)
                            )
                        )
                    }
                }
            }
            .clipShape(shape)
            .overlay { DoubleSpecularBorder(cornerRadius: cornerRadius, isShell: true, highContrast: prefs.increaseContrast) }
    }
}

struct RoundedShapeOuterShadow<S: InsettableShape>: View {
    let shape: S
    let color: Color
    let radius: CGFloat
    let yOffset: CGFloat

    var body: some View {
        // Inset the opaque shadow caster inside the silhouette so its curved edge never touches
        // the outer rim, and expand the destinationOut cutout by 0.35pt to eliminate corner halos.
        shape
            .inset(by: 1.5)
            .fill(Color.black)
            .shadow(color: color, radius: radius, y: yOffset)
            .overlay {
                shape
                    .inset(by: -0.35)
                    .fill(Color.black)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
            .allowsHitTesting(false)
    }
}

struct LiquidGlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let solidReadable: Bool
    @ObservedObject private var themeManager = ThemeManager.shared

    func body(content: Content) -> some View {
        let prefs = SystemDisplayPreferences.shared.snapshot
        let isDark = themeManager.resolvedIsDark
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let shadowColor = Color.black.opacity(prefs.reduceTransparency ? 0.08 : (isDark ? 0.22 : 0.06))
        let shadowRadius: CGFloat = isDark ? 10 : 7
        let shadowY: CGFloat = isDark ? 4 : 2.5
        content
            .background {
                ZStack {
                    if !prefs.reduceTransparency {
                        shape.fill(solidReadable ? .regularMaterial : .ultraThinMaterial)
                    }
                    shape.fill(
                        prefs.reduceTransparency
                            ? LiquidColors.solidCardSurface
                            : (solidReadable ? LiquidColors.elevatedSurface : LiquidColors.cardSurface)
                    )
                    if !prefs.reduceTransparency {
                        shape.fill(LiquidColors.specularTopSheen)
                    }
                }
            }
            .clipShape(shape)
            .overlay { DoubleSpecularBorder(cornerRadius: cornerRadius, isShell: false, highContrast: prefs.increaseContrast) }
            .background {
                RoundedShapeOuterShadow(shape: shape, color: shadowColor, radius: shadowRadius, yOffset: shadowY)
            }
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

import AppKit
import LucentCore
import SwiftUI

@MainActor
final class LiquidRippleController: ObservableObject {
    @Published var isActive: Bool = false
    @Published var progress: CGFloat = 0.0
    @Published var reboundScale: CGFloat = 1.0
    @Published var origin: CGPoint? = nil
    private var settleTask: Task<Void, Never>?

    deinit { settleTask?.cancel() }

    func trigger(at point: CGPoint? = nil, enableRebound: Bool = true) {
        guard !LiquidMotion.reduceMotion else { return }
        settleTask?.cancel()
        origin = point
        progress = 0.0
        isActive = true
        if enableRebound {
            reboundScale = 0.992
            withAnimation(.spring(response: 0.22, dampingFraction: 0.80)) {
                reboundScale = 1.003
            }
        }
        withAnimation(.easeOut(duration: 0.26)) {
            progress = 1.0
        }
        settleTask = Task { @MainActor [weak self] in
            if enableRebound {
                try? await Task.sleep(nanoseconds: 80_000_000)
                guard !Task.isCancelled, let self else { return }
                withAnimation(.spring(response: 0.22, dampingFraction: 0.84)) {
                    self.reboundScale = 1.0
                }
            }
            try? await Task.sleep(nanoseconds: 240_000_000)
            guard !Task.isCancelled, let self else { return }
            self.isActive = false
            self.progress = 0.0
            self.reboundScale = 1.0
        }
    }
}

@MainActor
final class LiquidGlintController: ObservableObject {
    @Published var phase: CGFloat = -0.6
    @Published var opacity: Double = 0.0
    private var settleTask: Task<Void, Never>?

    deinit { settleTask?.cancel() }

    func fire() {
        guard !LiquidMotion.reduceMotion else { return }
        settleTask?.cancel()
        phase = -0.55
        opacity = 1.0
        withAnimation(.easeOut(duration: 0.50)) {
            phase = 1.45
        }
        settleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 340_000_000)
            guard !Task.isCancelled, let self else { return }
            withAnimation(.easeOut(duration: 0.18)) { self.opacity = 0.0 }
        }
    }
}

@MainActor
final class LiquidHoverSpecularController: ObservableObject {
    @Published var isHovering: Bool = false
    @Published var normalizedLocation: UnitPoint = .top
}

struct LiquidTapRippleModifier: ViewModifier {
    let cornerRadius: CGFloat
    let isCapsule: Bool
    let tint: Color
    let enableRebound: Bool
    @StateObject private var ripple = LiquidRippleController()

    func body(content: Content) -> some View {
        let reduceTrans = SystemDisplayPreferences.shared.reduceTransparency
        content
            .scaleEffect(LiquidMotion.reduceMotion ? 1.0 : ripple.reboundScale)
            .overlay {
                if ripple.isActive && !reduceTrans {
                    GeometryReader { geo in
                        let maxDim = max(geo.size.width, geo.size.height)
                        let diameter = max(24, maxDim * (0.28 + ripple.progress * 1.15))
                        let center = ripple.origin ?? CGPoint(x: geo.size.width * 0.5, y: geo.size.height * 0.5)
                        let fade = max(0, 1.0 - Double(ripple.progress))
                        Circle()
                            .fill(RadialGradient(colors: [tint.opacity(0.065 * fade), .clear], center: .center, startRadius: 2, endRadius: diameter * 0.5))
                            .frame(width: diameter, height: diameter)
                            .position(center)
                    }
                    .clipShape(clippedShape)
                    .allowsHitTesting(false)
                }
            }
            .simultaneousGesture(
                SpatialTapGesture().onEnded { value in
                    ripple.trigger(at: value.location, enableRebound: enableRebound)
                }
            )
    }

    private var clippedShape: AnyShape {
        isCapsule ? AnyShape(Capsule(style: .continuous)) : AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct LiquidRimGlintModifier: ViewModifier {
    let cornerRadius: CGFloat
    let isCapsule: Bool
    let trigger: Int
    let onHover: Bool
    @StateObject private var glint = LiquidGlintController()

    func body(content: Content) -> some View {
        let reduceTrans = SystemDisplayPreferences.shared.reduceTransparency
        content
            .overlay {
                if glint.opacity > 0.01 && !reduceTrans {
                    let grad = LinearGradient(
                        stops: [
                            .init(color: .clear, location: max(0, glint.phase - 0.24)),
                            .init(color: Color.white.opacity(0.28), location: min(1, max(0, glint.phase))),
                            .init(color: .clear, location: min(1, glint.phase + 0.24))
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Group {
                        if isCapsule {
                            Capsule(style: .continuous).strokeBorder(grad, lineWidth: 0.85)
                        } else {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(grad, lineWidth: 0.85)
                        }
                    }
                    .opacity(glint.opacity)
                    .allowsHitTesting(false)
                }
            }
            .onChange(of: trigger) { _, _ in glint.fire() }
            .onHover { hovering in
                if onHover && hovering { glint.fire() }
            }
    }
}

struct LiquidHoverSpecularModifier: ViewModifier {
    let cornerRadius: CGFloat
    let intensity: Double
    @StateObject private var hover = LiquidHoverSpecularController()
    @ObservedObject private var themeManager = ThemeManager.shared

    func body(content: Content) -> some View {
        let reduce = LiquidMotion.reduceMotion || SystemDisplayPreferences.shared.reduceTransparency
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let isDark = themeManager.resolvedIsDark
        content
            .overlay {
                if hover.isHovering && !reduce {
                    shape
                        .fill(
                            RadialGradient(
                                colors: [Color.white.opacity((isDark ? 0.075 : 0.18) * intensity), .clear],
                                center: hover.normalizedLocation,
                                startRadius: 4,
                                endRadius: 150
                            )
                        )
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .onContinuousHover(coordinateSpace: .local) { phase in
                guard !reduce else { return }
                switch phase {
                case .active(let pt):
                    let nx = min(1, max(0, pt.x / 220))
                    let ny = min(0.45, max(0, pt.y / 140))
                    if !hover.isHovering {
                        withAnimation(LiquidMotion.hoverSpring) { hover.isHovering = true }
                    }
                    hover.normalizedLocation = UnitPoint(x: nx, y: ny)
                case .ended:
                    withAnimation(LiquidMotion.hoverSpring) { hover.isHovering = false }
                }
            }
    }
}

struct LiquidPressFeedbackModifier: ViewModifier {
    let isPressed: Bool
    let cornerRadius: CGFloat
    let isCapsule: Bool
    let pressedScale: CGFloat
    let tint: Color
    @StateObject private var ripple = LiquidRippleController()

    func body(content: Content) -> some View {
        let reduce = LiquidMotion.reduceMotion
        let reduceTrans = SystemDisplayPreferences.shared.reduceTransparency
        let scale = reduce ? 1.0 : (isPressed ? pressedScale : ripple.reboundScale)
        let shape = isCapsule ? AnyShape(Capsule(style: .continuous)) : AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        content
            .overlay {
                if !reduceTrans {
                    shape
                        .fill(Color.primary.opacity(isPressed ? 0.035 : 0.0))
                        .allowsHitTesting(false)
                }
            }
            .scaleEffect(scale)
            .opacity(isPressed ? 0.96 : 1.0)
            .animation(LiquidMotion.pressSpring, value: isPressed)
            .onChange(of: isPressed) { wasPressed, nowPressed in
                if wasPressed && !nowPressed {
                    ripple.trigger(at: nil, enableRebound: true)
                }
            }
    }
}

extension View {
    func liquidTapRipple(
        cornerRadius: CGFloat = LiquidRadii.card,
        isCapsule: Bool = false,
        tint: Color = LiquidColors.accentPrimary,
        enableRebound: Bool = true
    ) -> some View {
        modifier(LiquidTapRippleModifier(cornerRadius: cornerRadius, isCapsule: isCapsule, tint: tint, enableRebound: enableRebound))
    }

    func liquidRimGlint(
        cornerRadius: CGFloat = LiquidRadii.card,
        isCapsule: Bool = false,
        trigger: Int = 0,
        onHover: Bool = true
    ) -> some View {
        modifier(LiquidRimGlintModifier(cornerRadius: cornerRadius, isCapsule: isCapsule, trigger: trigger, onHover: onHover))
    }

    func liquidHoverSpecular(cornerRadius: CGFloat = LiquidRadii.card, intensity: Double = 1.0) -> some View {
        modifier(LiquidHoverSpecularModifier(cornerRadius: cornerRadius, intensity: intensity))
    }

    func liquidPressEffect(
        isPressed: Bool,
        cornerRadius: CGFloat = LiquidRadii.control,
        isCapsule: Bool = false,
        pressedScale: CGFloat = 0.980,
        tint: Color = LiquidColors.accentPrimary
    ) -> some View {
        modifier(LiquidPressFeedbackModifier(isPressed: isPressed, cornerRadius: cornerRadius, isCapsule: isCapsule, pressedScale: pressedScale, tint: tint))
    }
}

import AppKit
import LucentCore
import SwiftUI

extension LiquidMotion {
    static var reduceMotion: Bool {
        SystemDisplayPreferences.shared.reduceMotion
    }

    static var snappySpring: Animation {
        reduceMotion
            ? .linear(duration: 0.01)
            : .spring(response: 0.21, dampingFraction: 0.84)
    }

    static var smoothSpring: Animation {
        reduceMotion
            ? .linear(duration: 0.01)
            : .spring(response: 0.28, dampingFraction: 0.82)
    }

    static var hoverSpring: Animation {
        reduceMotion
            ? .linear(duration: 0.01)
            : .spring(response: 0.19, dampingFraction: 0.80)
    }

    static var reboundSpring: Animation {
        reduceMotion
            ? .linear(duration: 0.01)
            : .spring(response: 0.24, dampingFraction: 0.80)
    }

    static var capsuleSlideSpring: Animation {
        reduceMotion
            ? .linear(duration: 0.01)
            : .spring(response: 0.26, dampingFraction: 0.78)
    }

    static var lensTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.982)),
            removal: .opacity
        )
    }

    static var floatingPillTransition: AnyTransition {
        .opacity
            .combined(with: .scale(scale: 0.93, anchor: .top))
            .combined(with: .offset(y: -4))
    }
}

@MainActor
final class LiquidHoverTracker: ObservableObject {
    @Published var isHovered: Bool = false
    @Published var hasAppeared: Bool = false
}

struct LiquidHoverLiftModifier: ViewModifier {
    let cornerRadius: CGFloat
    let hoverScale: CGFloat
    let staggerDelay: Double
    @StateObject private var tracker = LiquidHoverTracker()
    @ObservedObject private var themeManager = ThemeManager.shared

    func body(content: Content) -> some View {
        let reduce = LiquidMotion.reduceMotion
        let reduceTrans = SystemDisplayPreferences.shared.reduceTransparency
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let _ = themeManager.resolvedIsDark

        content
            .overlay {
                if tracker.isHovered && !reduceTrans {
                    shape
                        .strokeBorder(LiquidColors.hoverCardRimGradient, lineWidth: 0.95)
                        .allowsHitTesting(false)
                }
            }
            .scaleEffect(
                reduce
                    ? 1.0
                    : ((tracker.hasAppeared ? 1.0 : 0.975) * (tracker.isHovered ? hoverScale : 1.0))
            )
            .opacity(reduce || tracker.hasAppeared ? 1.0 : 0.0)
            .offset(y: reduce || tracker.hasAppeared ? 0 : 6)
            .shadow(
                color: tracker.isHovered && !reduceTrans ? LiquidColors.accentShadowColor.opacity(0.22) : .clear,
                radius: 8,
                y: 3
            )
            .onHover { hovering in
                withAnimation(LiquidMotion.hoverSpring) {
                    tracker.isHovered = hovering
                }
            }
            .onAppear {
                guard !tracker.hasAppeared else { return }
                if reduce {
                    tracker.hasAppeared = true
                } else {
                    withAnimation(LiquidMotion.smoothSpring.delay(staggerDelay)) {
                        tracker.hasAppeared = true
                    }
                }
            }
    }
}

struct LiquidHoverRowModifier: ViewModifier {
    let isActive: Bool
    let cornerRadius: CGFloat
    @StateObject private var tracker = LiquidHoverTracker()
    @ObservedObject private var themeManager = ThemeManager.shared

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let isDark = themeManager.resolvedIsDark
        content
            .background {
                if !isActive && tracker.isHovered {
                    shape.fill(Color.primary.opacity(isDark ? 0.065 : 0.045))
                }
            }
            .onHover { hovering in
                withAnimation(LiquidMotion.hoverSpring) {
                    tracker.isHovered = hovering
                }
            }
    }
}

extension View {
    func liquidHoverLift(
        cornerRadius: CGFloat = LiquidRadii.bento,
        scale: CGFloat = 1.008,
        staggerDelay: Double = 0
    ) -> some View {
        modifier(LiquidHoverLiftModifier(cornerRadius: cornerRadius, hoverScale: scale, staggerDelay: staggerDelay))
    }

    func liquidHoverRow(active: Bool, cornerRadius: CGFloat = 10) -> some View {
        modifier(LiquidHoverRowModifier(isActive: active, cornerRadius: cornerRadius))
    }
}

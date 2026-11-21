import AppKit
import LucentCore
import SwiftUI

@MainActor
final class LaunchIntroAnimationState: ObservableObject {
    @Published var auraVisible: Bool = false
    @Published var iconScale: CGFloat = 0.64
    @Published var iconOpacity: Double = 0.0
    @Published var iconOffsetY: CGFloat = 14
    @Published var iconTiltDegrees: Double = 16
    @Published var rippleProgress: CGFloat = 0.0
    @Published var rippleOpacity: Double = 0.0
    @Published var plaqueVisible: Bool = false
    @Published var shimmerPhase: CGFloat = -1.15
    @Published var fuseProgress: CGFloat = 0.0
    @Published var morphWaveActive: Bool = false
    @Published var stageDissolving: Bool = false
}

struct LaunchIntroOverlayView: View {
    @ObservedObject var state: LaunchIntroAnimationState
    let onSkip: () -> Void
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var languageManager = LanguageManager.shared

    private struct MoteSpec: Identifiable {
        let id: Int; let angle: Double; let distance: CGFloat; let size: CGFloat; let color: Color
    }

    private let motes: [MoteSpec] = [
        MoteSpec(id: 0, angle: -0.52, distance: 158, size: 5.5, color: Color(red: 0.56, green: 0.82, blue: 1.0)),
        MoteSpec(id: 1, angle: 0.35, distance: 172, size: 4.5, color: Color.white),
        MoteSpec(id: 2, angle: 1.18, distance: 136, size: 4.0, color: Color(red: 0.04, green: 0.52, blue: 1.0)),
        MoteSpec(id: 3, angle: 2.05, distance: 148, size: 5.0, color: Color(red: 0.74, green: 0.89, blue: 1.0)),
        MoteSpec(id: 4, angle: 2.72, distance: 168, size: 4.5, color: Color(red: 0.32, green: 0.68, blue: 1.0)),
        MoteSpec(id: 5, angle: -2.35, distance: 162, size: 5.0, color: Color.white),
        MoteSpec(id: 6, angle: -1.42, distance: 132, size: 4.0, color: Color(red: 0.14, green: 0.56, blue: 1.0)),
        MoteSpec(id: 7, angle: -0.10, distance: 184, size: 3.8, color: Color(red: 0.80, green: 0.92, blue: 1.0))
    ]

    private let iceBlue = Color(red: 0.62, green: 0.84, blue: 1.0)
    private let appleBlue = Color(red: 0.04, green: 0.52, blue: 1.0)

    var body: some View {
        let _ = languageManager.current
        let isDark = themeManager.resolvedIsDark
        let reduceTrans = SystemDisplayPreferences.shared.reduceTransparency

        ZStack {
            ambientPrismBackdrop(isDark: isDark, reduceTransparency: reduceTrans)
            shockwaveRipplesAndMotes(isDark: isDark)
            morphingPanelSilhouette(isDark: isDark)

            VStack(spacing: 18) {
                iconKeycapHeroStage(isDark: isDark)
                sloganGlassPlaque(isDark: isDark, reduceTransparency: reduceTrans)
            }
            .scaleEffect(state.stageDissolving ? 1.07 : 1.0)
            .opacity(state.stageDissolving ? 0.0 : 1.0)
            .blur(radius: state.stageDissolving ? 7 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { onSkip() }
    }

    @ViewBuilder
    private func ambientPrismBackdrop(isDark: Bool, reduceTransparency: Bool) -> some View {
        if !reduceTransparency {
            ZStack {
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [appleBlue.opacity(isDark ? 0.28 : 0.18), iceBlue.opacity(isDark ? 0.14 : 0.12), .clear],
                            center: .center, startRadius: 12, endRadius: 240
                        )
                    )
                    .frame(width: 520, height: 320).offset(x: -32, y: -16)

                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(isDark ? 0.14 : 0.34), iceBlue.opacity(isDark ? 0.12 : 0.14), .clear],
                            center: .center, startRadius: 10, endRadius: 210
                        )
                    )
                    .frame(width: 440, height: 280).offset(x: 46, y: 22)
            }
            .blur(radius: 28)
            .scaleEffect(state.auraVisible ? (state.stageDissolving ? 1.24 : 1.0) : 0.62)
            .opacity(state.auraVisible ? (state.stageDissolving ? 0.0 : 1.0) : 0.0)
            .allowsHitTesting(false)
        }
    }

    private func shockwaveRipplesAndMotes(isDark: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 36 + state.rippleProgress * 24, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.92), iceBlue.opacity(0.84), appleBlue.opacity(0.76), .white.opacity(0.82)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: max(0.6, 2.2 * (1.0 - state.rippleProgress))
                )
                .frame(width: 96 + state.rippleProgress * 310, height: 96 + state.rippleProgress * 230)
                .offset(y: -48).opacity(state.rippleOpacity)

            Circle()
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.82), iceBlue.opacity(0.55), appleBlue.opacity(0.40)], startPoint: .leading, endPoint: .trailing),
                    lineWidth: max(0.5, 1.4 * (1.0 - state.rippleProgress))
                )
                .frame(width: 82 + state.rippleProgress * 220, height: 82 + state.rippleProgress * 220)
                .offset(y: -48).opacity(state.rippleOpacity * 0.85)

            ForEach(motes) { mote in
                let dist = mote.distance * (0.28 + state.rippleProgress * 0.88)
                Circle()
                    .fill(mote.color).frame(width: mote.size, height: mote.size)
                    .shadow(color: appleBlue.opacity(isDark ? 0.72 : 0.42), radius: 5)
                    .offset(x: CGFloat(cos(mote.angle)) * dist, y: -48 + CGFloat(sin(mote.angle)) * dist * 0.68)
                    .opacity(state.rippleOpacity * 0.90)
            }
        }
        .allowsHitTesting(false)
    }

    private func morphingPanelSilhouette(isDark: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: LiquidRadii.panel, style: .continuous)
        return shape
            .strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(isDark ? 0.76 : 0.92), iceBlue.opacity(0.75), appleBlue.opacity(0.62)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                lineWidth: state.morphWaveActive ? 1.25 : 1.9
            )
            .background(
                shape.fill(
                    RadialGradient(colors: [iceBlue.opacity(isDark ? 0.10 : 0.14), appleBlue.opacity(0.05), .clear], center: .center, startRadius: 20, endRadius: 420)
                )
            )
            .frame(width: state.morphWaveActive ? 868 : 340, height: state.morphWaveActive ? 532 : 180)
            .opacity(state.morphWaveActive ? (state.stageDissolving ? 0.24 : 0.86) : 0.0)
            .allowsHitTesting(false)
    }

    private func iconKeycapHeroStage(isDark: Bool) -> some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [iceBlue.opacity(isDark ? 0.36 : 0.28), appleBlue.opacity(0.16), .clear], center: .center, startRadius: 4, endRadius: 74))
                .frame(width: 148, height: 148)
                .opacity(state.iconOpacity)

            LucentBrandIconView(size: 104, showAmbientGlow: true)
                .scaleEffect(state.iconScale)
                .offset(y: state.iconOffsetY)
                .rotation3DEffect(.degrees(state.iconTiltDegrees), axis: (x: 1.0, y: -0.35, z: 0.0), perspective: 0.55)
                .opacity(state.iconOpacity)
        }
    }

    private func sloganGlassPlaque(isDark: Bool, reduceTransparency: Bool) -> some View {
        let plaqueShape = RoundedRectangle(cornerRadius: LiquidRadii.bento, style: .continuous)
        return VStack(spacing: 8) {
            HStack(spacing: 7) {
                Text("流光  LUCENT")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded)).tracking(2.2)
                    .foregroundStyle(LiquidColors.textSecondary)

                Text("⌥Space")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(LiquidColors.accentPrimary)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(LiquidColors.pillSurface, in: Capsule(style: .continuous))
                    .overlay { Capsule(style: .continuous).strokeBorder(LiquidColors.pillBorder, lineWidth: 0.75) }
            }

            sloganShimmerHeadline(isDark: isDark)

            Text(L10n.pick("越用越懂你 · 毫秒唤起 · 松手即净", "Smarter Every Click · Instant · Zero Trace"))
                .font(.system(size: 11.5, weight: .medium)).foregroundStyle(LiquidColors.textSecondary)

            GeometryReader { geo in
                let fillW = max(8, geo.size.width * state.fuseProgress)
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous).fill(LiquidColors.pillBorder.opacity(0.45)).frame(height: 2.5)
                    Capsule(style: .continuous)
                        .fill(LinearGradient(colors: [appleBlue, iceBlue, .white.opacity(0.92)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: fillW, height: 2.5).shadow(color: appleBlue.opacity(0.45), radius: 4)
                }
            }
            .frame(width: 228, height: 3).padding(.top, 3)
        }
        .padding(.horizontal, 28).padding(.vertical, 16)
        .background {
            ZStack {
                if !reduceTransparency { plaqueShape.fill(.ultraThinMaterial) }
                plaqueShape.fill(reduceTransparency ? LiquidColors.solidCardSurface : LiquidColors.elevatedSurface.opacity(isDark ? 0.86 : 0.94))
            }
        }
        .overlay { DoubleSpecularBorder(cornerRadius: LiquidRadii.bento, isShell: true, highContrast: SystemDisplayPreferences.shared.increaseContrast) }
        .shadow(color: Color.black.opacity(isDark ? 0.36 : 0.12), radius: 22, y: 10)
        .scaleEffect(state.plaqueVisible ? 1.0 : 0.92)
        .offset(y: state.plaqueVisible ? 0 : 12)
        .opacity(state.plaqueVisible ? 1.0 : 0.0)
    }

    private func sloganShimmerHeadline(isDark: Bool) -> some View {
        let slogan = "一触流光，用完即焚"
        let baseGrad = LinearGradient(
            colors: isDark
                ? [.white, Color(red: 0.76, green: 0.89, blue: 1.0), Color(red: 0.45, green: 0.74, blue: 1.0)]
                : [Color(red: 0.07, green: 0.09, blue: 0.14), Color(red: 0.0, green: 0.42, blue: 0.86), Color(red: 0.14, green: 0.49, blue: 0.90)],
            startPoint: .leading, endPoint: .trailing
        )
        return Text(slogan)
            .font(.system(size: 25, weight: .bold, design: .rounded)).tracking(1.4)
            .foregroundStyle(baseGrad)
            .overlay {
                GeometryReader { geo in
                    let w = max(geo.size.width, 1)
                    LinearGradient(
                        colors: [.clear, .white.opacity(isDark ? 0.95 : 0.82), iceBlue.opacity(0.55), .clear],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    .frame(width: w * 0.46).offset(x: state.shimmerPhase * w)
                }
                .mask(Text(slogan).font(.system(size: 25, weight: .bold, design: .rounded)).tracking(1.4))
            }
    }
}

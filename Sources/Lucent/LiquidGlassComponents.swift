import AppKit
import LucentCore
import SwiftUI

struct DoubleSpecularBorder: View {
    let cornerRadius: CGFloat
    var isShell: Bool = false
    var highContrast: Bool = false
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let isDark = themeManager.resolvedIsDark
        Group {
            if highContrast {
                shape.strokeBorder(LiquidColors.subtleRim, lineWidth: isShell ? 1.5 : 1.35)
            } else {
                ZStack {
                    shape.strokeBorder(
                        isShell ? LiquidColors.specularRimGradient : LiquidColors.softCardRimGradient,
                        lineWidth: isShell ? 1.0 : 0.85
                    )
                    shape
                        .inset(by: 0.9)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(isDark ? (isShell ? 0.18 : 0.12) : (isShell ? 0.72 : 0.56)), .clear],
                                startPoint: .top,
                                endPoint: UnitPoint(x: 0.5, y: 0.45)
                            ),
                            lineWidth: 0.65
                        )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct SquircleBadge: View {
    let symbol: String
    let topColor: Color
    let bottomColor: Color
    var size: CGFloat = 38
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        let isDark = themeManager.resolvedIsDark
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        ZStack {
            shape.fill(
                LinearGradient(
                    colors: [topColor, bottomColor],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            shape.fill(
                LinearGradient(
                    colors: [.white.opacity(isDark ? 0.28 : 0.34), .white.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .center
                )
            )
            Image(systemName: symbol)
                .font(.system(size: size * 0.43, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.14), radius: 1.5, y: 0.8)
        }
        .frame(width: size, height: size)
        .overlay {
            shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(isDark ? 0.34 : 0.48), .white.opacity(0.12)], startPoint: .top, endPoint: .bottom),
                lineWidth: 0.8
            )
        }
        .shadow(color: bottomColor.opacity(isDark ? 0.24 : 0.16), radius: 4, y: 2)
    }
}

struct GlassPillButtonStyle: ButtonStyle {
    var prominent: Bool = false
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let highContrast = SystemDisplayPreferences.shared.increaseContrast
        configuration.label
            .font((compact ? Font.caption2 : Font.caption).weight(.semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(prominent ? Color.white : LiquidColors.textPrimary)
            .padding(.horizontal, compact ? 9 : 12)
            .padding(.vertical, compact ? 4.5 : 6)
            .background {
                if prominent {
                    Capsule(style: .continuous).fill(LiquidColors.accentGradient).overlay {
                        Capsule(style: .continuous).fill(LinearGradient(colors: [.white.opacity(0.24), .clear], startPoint: .top, endPoint: .center))
                    }
                } else {
                    Capsule(style: .continuous).fill(LiquidColors.pillSurface).overlay {
                        Capsule(style: .continuous).fill(Color.white.opacity(configuration.isPressed ? 0.06 : 0.02))
                    }
                }
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(
                        prominent
                            ? LinearGradient(colors: [.white.opacity(0.46), .white.opacity(0.16)], startPoint: .top, endPoint: .bottom)
                            : LinearGradient(
                                colors: [highContrast ? LiquidColors.subtleRim : LiquidColors.pillBorder, LiquidColors.pillBorder.opacity(0.72)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                        lineWidth: highContrast ? 1.15 : 0.85
                    )
            }
            .shadow(color: prominent ? LiquidColors.accentShadowColor : .clear, radius: 6, y: 2)
            .liquidPressEffect(
                isPressed: configuration.isPressed,
                cornerRadius: 999,
                isCapsule: true,
                pressedScale: 0.978,
                tint: prominent ? .white : LiquidColors.accentPrimary
            )
    }
}

struct LiquidBentoTileStyle: ButtonStyle {
    var cornerRadius: CGFloat = LiquidRadii.bento
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.035 : 0.0))
                    .allowsHitTesting(false)
            }
            .liquidPressEffect(isPressed: configuration.isPressed, cornerRadius: cornerRadius, isCapsule: false, pressedScale: 0.985)
    }
}

struct LiquidSidebarRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let reduce = LiquidMotion.reduceMotion
        configuration.label
            .scaleEffect(reduce ? 1.0 : (configuration.isPressed ? 0.988 : 1.0))
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(LiquidMotion.pressSpring, value: configuration.isPressed)
    }
}

struct KeycapPill: View {
    let title: String
    let keyText: String
    var prominent: Bool = false
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        let _ = themeManager.resolvedIsDark
        HStack(spacing: 5) {
            Text(L10n.translate(title, for: languageManager.current))
                .font(.caption2.weight(.medium))
                .foregroundStyle(prominent ? LiquidColors.textPrimary : LiquidColors.textSecondary)
            Text(keyText)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(prominent ? Color.white : LiquidColors.textPrimary)
                .padding(.horizontal, 6.5)
                .padding(.vertical, 2.5)
                .background {
                    if prominent {
                        Capsule(style: .continuous)
                            .fill(LiquidColors.accentGradient)
                            .overlay {
                                Capsule(style: .continuous)
                                    .fill(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center))
                            }
                    } else {
                        Capsule(style: .continuous).fill(LiquidColors.pillSurface)
                    }
                }
                .overlay {
                    Capsule(style: .continuous).strokeBorder(
                        prominent ? Color.white.opacity(0.36) : LiquidColors.pillBorder,
                        lineWidth: 0.75
                    )
                }
        }
    }
}

struct LiquidKeyHintBadge: View {
    let keyText: String
    var highlighted: Bool = false
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        let _ = themeManager.resolvedIsDark
        Text(keyText)
            .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(highlighted ? LiquidColors.textPrimary : LiquidColors.textSecondary.opacity(0.88))
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(
                highlighted ? LiquidColors.elevatedSurface : LiquidColors.pillSurface.opacity(0.75),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(highlighted ? Color.white.opacity(0.42) : LiquidColors.pillBorder.opacity(0.75), lineWidth: 0.7)
            }
    }
}

struct LiquidSectionDivider: View {
    enum Axis { case horizontal, vertical }
    var axis: Axis = .horizontal

    var body: some View {
        if axis == .horizontal {
            Rectangle()
                .fill(LinearGradient(colors: [.clear, LiquidColors.subtleRim.opacity(0.75), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 0.8)
        } else {
            Rectangle()
                .fill(LinearGradient(colors: [.clear, LiquidColors.subtleRim.opacity(0.75), .clear], startPoint: .top, endPoint: .bottom))
                .frame(width: 0.8)
        }
    }
}

struct LiquidStatusPill: View {
    let title: String
    var symbol: String? = nil
    var tint: Color = LiquidColors.accentPrimary
    var showDot: Bool = false
    var prominent: Bool = false
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        let _ = themeManager.resolvedIsDark
        HStack(spacing: 5) {
            if showDot {
                Circle().fill(tint).frame(width: 6, height: 6)
            } else if let symbol {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(prominent ? .white : tint)
            }
            Text(L10n.translate(title, for: languageManager.current))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(prominent ? Color.white : LiquidColors.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8.5)
        .padding(.vertical, 3.5)
        .background {
            if prominent {
                Capsule(style: .continuous).fill(LiquidColors.accentGradient)
            } else {
                Capsule(style: .continuous).fill(tint.opacity(0.11))
            }
        }
        .overlay {
            Capsule(style: .continuous).strokeBorder(prominent ? Color.white.opacity(0.35) : tint.opacity(0.28), lineWidth: 0.75)
        }
    }
}

struct GlassDropdownMenu<MenuContent: View>: View {
    let title: String
    let value: String
    @ViewBuilder var content: () -> MenuContent

    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(LiquidColors.textSecondary)
            Menu { content() } label: {
                HStack(spacing: 4) {
                    Text(value).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold))
                }
                .font(.caption2.weight(.semibold)).foregroundStyle(LiquidColors.textPrimary)
                .padding(.horizontal, 9).padding(.vertical, 4.5)
                .background(LiquidColors.pillSurface, in: Capsule())
                .overlay { Capsule().strokeBorder(LiquidColors.pillBorder, lineWidth: 0.85) }
            }
            .menuStyle(.borderlessButton).fixedSize()
        }
    }
}

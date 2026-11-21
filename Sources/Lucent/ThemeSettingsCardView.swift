import LucentCore
import SwiftUI

struct ThemeSettingsCardView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        let _ = languageManager.current
        let isAuto = themeManager.followSystemAppearance
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Label(L10n.pick("界面视觉主题", "Appearance & Theme"), systemImage: "paintpalette.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(LiquidColors.textPrimary)
                Text(themeManager.effectiveTheme.englishBadge)
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidColors.accentPrimary)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(LiquidColors.pillSurface, in: Capsule(style: .continuous))
                if isAuto {
                    Text(L10n.pick("自动", "AUTO"))
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidColors.textSecondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(LiquidColors.pillSurface, in: Capsule(style: .continuous))
                }
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    Text(L10n.pick("跟随系统外观", "Follow System"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(LiquidColors.textSecondary)
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { themeManager.followSystemAppearance },
                            set: { enabled in
                                withAnimation(LiquidMotion.snappySpring) {
                                    viewModel.setFollowSystemAppearance(enabled)
                                }
                            }
                        )
                    )
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .tint(LiquidColors.accentPrimary)
                }
            }

            HStack(spacing: 12) {
                ForEach(AppThemeID.allCases) { theme in
                    themeOptionCard(theme)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: isAuto ? "circle.lefthalf.filled" : "command")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(LiquidColors.accentPrimary)
                Text(
                    isAuto
                        ? L10n.pick("正随 macOS 系统深浅色实时联动 · 点击卡片可固定单主题，或在 ⌥Space 输入「主题」秒切", "Synced live with macOS appearance · Click a card to lock a theme or type \"theme\" in ⌥Space")
                        : L10n.pick("在 ⌥Space 输入「主题 / 晴霜 / 曜石」可随时即时切换", "Type \"theme\", \"light\" or \"dark\" in ⌥Space to switch anytime")
                )
                .font(.caption2)
                .foregroundStyle(LiquidColors.textSecondary)
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
    }

    private func themeOptionCard(_ theme: AppThemeID) -> some View {
        let isActive = themeManager.effectiveTheme == theme
        let isLockedHere = !themeManager.followSystemAppearance && themeManager.current == theme
        let isDarkCard = theme == .prismPulse
        let cardShape = RoundedRectangle(cornerRadius: LiquidRadii.card, style: .continuous)

        return Button {
            withAnimation(LiquidMotion.snappySpring) {
                viewModel.setAppTheme(theme)
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                miniGlassWindowPreview(isDarkCard: isDarkCard)

                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: theme.symbolName)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(isDarkCard ? Color(red: 0.42, green: 0.68, blue: 1.0) : Color(red: 0.95, green: 0.62, blue: 0.14))
                        .frame(width: 24, height: 24)
                        .background(LiquidColors.pillSurface, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(theme.localizedTitle)
                                .font(.callout.weight(.bold))
                                .foregroundStyle(LiquidColors.textPrimary)
                            Text(theme.englishBadge)
                                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                                .foregroundStyle(LiquidColors.textSecondary)
                        }
                        Text(theme.localizedSubtitle)
                            .font(.caption2)
                            .foregroundStyle(LiquidColors.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isActive ? LiquidColors.accentPrimary : LiquidColors.textSecondary.opacity(0.42))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isActive ? LiquidColors.selectedRowFill : LiquidColors.pillSurface.opacity(0.65),
                in: cardShape
            )
            .overlay {
                cardShape.strokeBorder(
                    isActive
                        ? AnyShapeStyle(LiquidColors.selectedRowRimGradient)
                        : AnyShapeStyle(LiquidColors.pillBorder),
                    lineWidth: isLockedHere ? 1.5 : (isActive ? 1.2 : 0.8)
                )
            }
            .liquidHoverSpecular(cornerRadius: LiquidRadii.card, intensity: 0.85)
            .contentShape(cardShape)
        }
        .buttonStyle(LiquidBentoTileStyle(cornerRadius: LiquidRadii.card))
        .liquidTapRipple(cornerRadius: LiquidRadii.card, enableRebound: false)
    }

    private func miniGlassWindowPreview(isDarkCard: Bool) -> some View {
        let previewShape = RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous)
        let windowShape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let accent = isDarkCard ? Color(red: 0.04, green: 0.52, blue: 1.0) : Color(red: 0.0, green: 0.44, blue: 0.89)

        return ZStack {
            LinearGradient(
                colors: isDarkCard
                    ? [Color(red: 0.08, green: 0.085, blue: 0.105), Color(red: 0.13, green: 0.14, blue: 0.165)]
                    : [Color(red: 0.90, green: 0.925, blue: 0.96), Color(red: 0.955, green: 0.965, blue: 0.98)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(accent.opacity(isDarkCard ? 0.14 : 0.10))
                .frame(width: 110, height: 110)
                .blur(radius: 18)
                .offset(x: 72, y: -26)

            VStack(spacing: 5.5) {
                Capsule()
                    .fill(isDarkCard ? Color.white.opacity(0.24) : Color.black.opacity(0.16))
                    .frame(width: 24, height: 2.5)

                HStack(spacing: 5) {
                    LucentBrandIconView(size: 14)
                    Capsule()
                        .fill(isDarkCard ? Color.white.opacity(0.22) : Color.black.opacity(0.12))
                        .frame(width: 72, height: 5)
                    Spacer()
                    Capsule()
                        .fill(accent)
                        .frame(width: 26, height: 10)
                }
                .padding(.horizontal, 6.5).padding(.vertical, 4)
                .background(
                    isDarkCard ? Color(red: 0.10, green: 0.10, blue: 0.12).opacity(0.85) : Color.white.opacity(0.95),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(isDarkCard ? Color.white.opacity(0.14) : Color.black.opacity(0.08), lineWidth: 0.6)
                }

                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { idx in
                        RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                            .fill(
                                isDarkCard
                                    ? (idx == 0 ? accent.opacity(0.24) : Color.white.opacity(0.09))
                                    : (idx == 0 ? accent.opacity(0.12) : Color.white.opacity(0.88))
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                                    .strokeBorder(
                                        idx == 0
                                            ? accent.opacity(isDarkCard ? 0.58 : 0.44)
                                            : (isDarkCard ? Color.white.opacity(0.12) : Color.black.opacity(0.07)),
                                        lineWidth: 0.7
                                    )
                            }
                            .frame(height: 20)
                    }
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(
                isDarkCard ? Color(red: 0.13, green: 0.13, blue: 0.155).opacity(0.82) : Color.white.opacity(0.76),
                in: windowShape
            )
            .overlay {
                windowShape.strokeBorder(
                    LinearGradient(
                        colors: isDarkCard
                            ? [Color.white.opacity(0.32), Color.white.opacity(0.09)]
                            : [Color.white.opacity(0.92), Color.black.opacity(0.10)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
            }
            .shadow(color: .black.opacity(isDarkCard ? 0.34 : 0.08), radius: 6, y: 2.5)
            .padding(8)
        }
        .frame(height: 82)
        .clipShape(previewShape)
        .overlay {
            previewShape.strokeBorder(
                isDarkCard ? Color.white.opacity(0.18) : Color.black.opacity(0.08),
                lineWidth: 0.75
            )
        }
    }
}

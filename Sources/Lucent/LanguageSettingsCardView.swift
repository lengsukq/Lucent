import LucentCore
import SwiftUI

struct LanguageSettingsCardView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("界面显示语言", systemImage: "globe")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(LiquidColors.textPrimary)
                Text(languageManager.current.badgeText)
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidColors.accentPrimary)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(LiquidColors.pillSurface, in: Capsule())
                Spacer()
                Text("在 ⌥Space 输入「语言」或「language」可随时切换")
                    .font(.caption2)
                    .foregroundStyle(LiquidColors.textSecondary)
            }

            Text("首次打开已自动跟随 macOS 系统语言，切换后全窗口即时生效")
                .font(.caption2)
                .foregroundStyle(LiquidColors.textSecondary)

            HStack(spacing: 12) {
                ForEach(AppLanguageID.allCases) { lang in
                    languageOptionCard(lang)
                }
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
    }

    private func languageOptionCard(_ lang: AppLanguageID) -> some View {
        let selected = languageManager.current == lang
        let isSystemDefault = languageManager.detectedSystemLanguage == lang
        let cardShape = RoundedRectangle(cornerRadius: LiquidRadii.control + 2, style: .continuous)

        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                viewModel.setAppLanguage(lang)
            }
        } label: {
            HStack(alignment: .center, spacing: 10) {
                SquircleBadge(
                    symbol: lang.symbolName,
                    topColor: lang == .zhHans ? .cyan : .indigo,
                    bottomColor: lang == .zhHans ? .blue : .purple,
                    size: 34
                )
                VStack(alignment: .leading, spacing: 2.5) {
                    HStack(spacing: 6) {
                        Text(lang.nativeTitle)
                            .font(.callout.weight(.bold))
                            .foregroundStyle(LiquidColors.textPrimary)
                        if isSystemDefault {
                            Text(L10n.pick("系统语言", "System"))
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(LiquidColors.accentPrimary)
                                .padding(.horizontal, 6).padding(.vertical, 1.5)
                                .background(LiquidColors.pillSurface, in: Capsule())
                        }
                    }
                    Text(lang.localizedSubtitle)
                        .font(.caption2)
                        .foregroundStyle(LiquidColors.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selected ? LiquidColors.accentPrimary : LiquidColors.textSecondary.opacity(0.45))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selected ? LiquidColors.highlightGlow.opacity(0.55) : LiquidColors.pillSurface.opacity(0.55),
                in: cardShape
            )
            .overlay {
                cardShape.strokeBorder(
                    selected
                        ? AnyShapeStyle(LiquidColors.selectedRowRimGradient)
                        : AnyShapeStyle(LiquidColors.pillBorder),
                    lineWidth: selected ? 1.5 : 0.8
                )
            }
            .contentShape(cardShape)
        }
        .buttonStyle(.plain)
    }
}

import LucentCore
import SwiftUI

struct ThemeSettingsCardView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("界面视觉主题", systemImage: "paintpalette.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(LiquidColors.textPrimary)
                Text(themeManager.current.englishBadge)
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidColors.accentPrimary)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(LiquidColors.pillSurface, in: Capsule())
                Spacer()
                Text("在 ⌥Space 输入「主题」可随时秒切")
                    .font(.caption2)
                    .foregroundStyle(LiquidColors.textSecondary)
            }

            HStack(spacing: 12) {
                ForEach(AppThemeID.allCases) { theme in
                    themeOptionCard(theme)
                }
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
    }

    private func themeOptionCard(_ theme: AppThemeID) -> some View {
        let selected = themeManager.current == theme
        let isPrism = theme == .prismPulse
        let cardShape = RoundedRectangle(cornerRadius: isPrism ? 16 : 12, style: .continuous)

        return Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                viewModel.setAppTheme(theme)
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                miniLauncherPreview(isPrism: isPrism)

                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: theme.symbolName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isPrism ? Color.purple : Color.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(theme.localizedTitle)
                                .font(.callout.weight(.bold))
                                .foregroundStyle(LiquidColors.textPrimary)
                            Text(theme.englishBadge)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(LiquidColors.textSecondary)
                        }
                        Text(theme.localizedSubtitle)
                            .font(.caption2)
                            .foregroundStyle(LiquidColors.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(selected ? LiquidColors.accentPrimary : LiquidColors.textSecondary.opacity(0.45))
                }
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

    private func miniLauncherPreview(isPrism: Bool) -> some View {
        let previewShape = RoundedRectangle(cornerRadius: isPrism ? 13 : 9, style: .continuous)
        return ZStack {
            if isPrism {
                LinearGradient(
                    colors: [
                        Color(red: 0.13, green: 0.12, blue: 0.26),
                        Color(red: 0.22, green: 0.14, blue: 0.36)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(colors: [.cyan.opacity(0.38), .clear], center: .topLeading, startRadius: 4, endRadius: 110)
                RadialGradient(colors: [.pink.opacity(0.36), .clear], center: .bottomTrailing, startRadius: 4, endRadius: 110)
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.96, green: 0.965, blue: 0.978),
                        Color(red: 0.92, green: 0.93, blue: 0.95)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    LucentBrandIconView(size: 16)
                    Capsule()
                        .fill(isPrism ? Color.white.opacity(0.26) : Color.black.opacity(0.10))
                        .frame(width: 78, height: 6)
                    Spacer()
                    Capsule()
                        .fill(
                            isPrism
                                ? AnyShapeStyle(LinearGradient(colors: [.cyan, .purple, .pink], startPoint: .leading, endPoint: .trailing))
                                : AnyShapeStyle(Color.blue)
                        )
                        .frame(width: 30, height: 12)
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(
                    isPrism ? Color.white.opacity(0.12) : Color.white.opacity(0.92),
                    in: RoundedRectangle(cornerRadius: isPrism ? 8 : 6, style: .continuous)
                )

                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { idx in
                        RoundedRectangle(cornerRadius: isPrism ? 8 : 5.5, style: .continuous)
                            .fill(isPrism ? Color.white.opacity(idx == 0 ? 0.22 : 0.11) : Color.white.opacity(idx == 0 ? 0.96 : 0.76))
                            .overlay {
                                RoundedRectangle(cornerRadius: isPrism ? 8 : 5.5, style: .continuous)
                                    .strokeBorder(
                                        idx == 0
                                            ? (isPrism ? Color.pink.opacity(0.65) : Color.blue.opacity(0.45))
                                            : (isPrism ? Color.white.opacity(0.18) : Color.black.opacity(0.06)),
                                        lineWidth: 0.8
                                    )
                            }
                            .frame(height: 24)
                    }
                }
            }
            .padding(9)
        }
        .frame(height: 76)
        .clipShape(previewShape)
        .overlay {
            previewShape.strokeBorder(
                isPrism ? Color.white.opacity(0.28) : Color.black.opacity(0.08),
                lineWidth: 0.8
            )
        }
    }
}

import AppKit
import LucentCore
import SwiftUI

struct SecondaryWindowScaffold<Content: View>: View {
    let title: String
    let subtitle: String?
    let symbol: String
    let pinWindowKey: String?
    private let content: () -> Content
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var languageManager = LanguageManager.shared

    init(title: String, subtitle: String? = nil, symbol: String, pinWindowKey: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.subtitle = subtitle; self.symbol = symbol; self.pinWindowKey = pinWindowKey; self.content = content
    }

    var body: some View {
        ZStack {
            LiquidFluidBackdrop()
            content().padding(.top, 10).padding(.horizontal, 16).padding(.bottom, 16)
        }
        .overlay(alignment: .top) {
            ZStack {
                WindowDragRegion()
                titlebarBadgeStrip.allowsHitTesting(false)
                if let pinWindowKey {
                    HStack {
                        Spacer()
                        WindowPinPillButton(key: pinWindowKey).shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                    }
                    .padding(.trailing, 14)
                }
            }
            .frame(height: 32).padding(.top, 3).ignoresSafeArea(.container, edges: .top)
        }
    }

    private var titlebarBadgeStrip: some View {
        let reduceTransparency = SystemDisplayPreferences.shared.reduceTransparency
        let resolvedTitle = L10n.translate(title, for: languageManager.current)
        return HStack(spacing: 7) {
            LucentBrandIconView(size: 19)
            Image(systemName: symbol).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(LiquidColors.accentPrimary)
            Text(resolvedTitle).font(.system(size: 12, weight: .semibold)).foregroundStyle(LiquidColors.textPrimary).lineLimit(1)
            if let subtitle, !subtitle.isEmpty {
                Text("·").foregroundStyle(LiquidColors.textSecondary)
                Text(L10n.translate(subtitle, for: languageManager.current))
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(LiquidColors.textSecondary).lineLimit(1)
            }
        }
        .padding(.leading, 5).padding(.trailing, 12).padding(.vertical, 3.5)
        .background {
            ZStack {
                if !reduceTransparency { Capsule(style: .continuous).fill(.ultraThinMaterial) }
                Capsule(style: .continuous).fill(reduceTransparency ? LiquidColors.solidCardSurface : LiquidColors.elevatedSurface)
            }
        }
        .overlay { Capsule(style: .continuous).strokeBorder(LiquidColors.pillBorder, lineWidth: 0.85) }
        .shadow(color: .black.opacity(0.06), radius: 7, y: 2)
        .frame(height: 28, alignment: .center)
    }
}

struct SettingsSectionHeroHeader<Trailing: View>: View {
    let symbol: String
    let topColor: Color
    let bottomColor: Color
    let title: String
    let subtitle: String
    private let trailing: () -> Trailing
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var languageManager = LanguageManager.shared

    init(symbol: String, topColor: Color, bottomColor: Color, title: String, subtitle: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.symbol = symbol; self.topColor = topColor; self.bottomColor = bottomColor
        self.title = title; self.subtitle = subtitle; self.trailing = trailing
    }

    var body: some View {
        let isPrism = themeManager.current == .prismPulse
        let lang = languageManager.current
        HStack(alignment: .center, spacing: 15) {
            SquircleBadge(symbol: symbol, topColor: topColor, bottomColor: bottomColor, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.translate(title, for: lang)).font(.title3.weight(.bold)).foregroundStyle(LiquidColors.textPrimary)
                Text(L10n.translate(subtitle, for: lang)).font(.caption).foregroundStyle(LiquidColors.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            trailing()
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isPrism {
                RadialGradient(colors: [topColor.opacity(0.14), .clear], center: .topLeading, startRadius: 8, endRadius: 280)
                    .clipShape(RoundedRectangle(cornerRadius: LiquidRadii.bento, style: .continuous))
            }
        }
        .liquidGlassCard(cornerRadius: LiquidRadii.bento)
    }
}

extension SettingsSectionHeroHeader where Trailing == EmptyView {
    init(symbol: String, topColor: Color, bottomColor: Color, title: String, subtitle: String) {
        self.init(symbol: symbol, topColor: topColor, bottomColor: bottomColor, title: title, subtitle: subtitle) { EmptyView() }
    }
}

struct SettingsToggleCardRow: View {
    let symbol: String
    let topColor: Color
    let bottomColor: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        let isPrism = themeManager.current == .prismPulse
        let lang = languageManager.current
        HStack(alignment: .center, spacing: 14) {
            SquircleBadge(symbol: symbol, topColor: topColor, bottomColor: bottomColor, size: 38)
            VStack(alignment: .leading, spacing: 2.5) {
                Text(L10n.translate(title, for: lang)).font(.callout.weight(.semibold)).foregroundStyle(LiquidColors.textPrimary)
                Text(L10n.translate(subtitle, for: lang)).font(.caption2).foregroundStyle(LiquidColors.textSecondary).lineLimit(2)
            }
            Spacer(minLength: 10)
            Toggle("", isOn: $isOn).toggleStyle(.switch).labelsHidden().tint(LiquidColors.accentPrimary)
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .background {
            if isOn && isPrism {
                RoundedRectangle(cornerRadius: LiquidRadii.card, style: .continuous)
                    .fill(RadialGradient(colors: [topColor.opacity(0.10), .clear], center: .leading, startRadius: 6, endRadius: 240))
            }
        }
        .liquidGlassCard(cornerRadius: LiquidRadii.card)
    }
}

struct GlassInputField: View {
    let symbol: String?
    let placeholder: String
    @Binding var text: String
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var languageManager = LanguageManager.shared

    init(symbol: String? = nil, placeholder: String, text: Binding<String>) {
        self.symbol = symbol; self.placeholder = placeholder; self._text = text
    }

    var body: some View {
        let shape = Capsule(style: .continuous)
        let reduceTransparency = SystemDisplayPreferences.shared.reduceTransparency
        let _ = themeManager.current
        let resolvedPlaceholder = L10n.translate(placeholder, for: languageManager.current)
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(LiquidColors.textSecondary)
                    .frame(width: 22, height: 22).background(LiquidColors.pillSurface, in: Circle())
            }
            TextField(resolvedPlaceholder, text: $text)
                .textFieldStyle(.plain)
                .font(.caption.weight(.medium))
                .foregroundStyle(LiquidColors.textPrimary)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(LiquidColors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, symbol == nil ? 13 : 7).padding(.trailing, 11).padding(.vertical, 6.5)
        .frame(minWidth: 110)
        .background {
            ZStack {
                if !reduceTransparency { shape.fill(.ultraThinMaterial) }
                shape.fill(reduceTransparency ? LiquidColors.solidCardSurface : LiquidColors.inputFieldSurface)
            }
        }
        .overlay { shape.strokeBorder(LiquidColors.inputFieldBorder, lineWidth: 0.85) }
    }
}

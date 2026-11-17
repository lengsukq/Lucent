import AppKit
import LumakeyCore
import SwiftUI

struct PluginViewActionButtons: View {
    let item: PluginViewItem
    let onRunCommandArgs: (([String]) -> Void)?
    let onRequestAction: (PluginViewAction) -> Void

    var body: some View {
        let actions = item.actions ?? []
        if !actions.isEmpty {
            ForEach(actions) { action in
                Button(action.label) {
                    onRequestAction(action)
                }
                .buttonStyle(GlassPillButtonStyle(prominent: action.style == .primary, compact: true))
                .tint(action.style == .destructive ? .red : nil)
            }
        } else if let args = item.commandArgs, !args.isEmpty, onRunCommandArgs != nil {
            Button(L10n.pick("执行", "Run")) {
                onRunCommandArgs?(args)
            }
            .buttonStyle(GlassPillButtonStyle(prominent: true, compact: true))
        }
    }
}

struct PluginStarterGalleryListView: View {
    let installedIDs: Set<String>
    let onInstall: (PluginStarterTemplate) -> Void
    var onOpenSettings: ((String) -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 9) {
                ForEach(PluginStarterGallery.templates) { tpl in
                    let installed = installedIDs.contains(tpl.id)
                    HStack(alignment: .center, spacing: 11) {
                        SquircleBadge(
                            symbol: tpl.icon,
                            topColor: tpl.mode == .view ? .cyan : .indigo,
                            bottomColor: tpl.mode == .view ? .blue : .purple,
                            size: 36
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(L10n.translate(tpl.name)).font(.caption.weight(.bold)).foregroundStyle(LiquidColors.textPrimary)
                                if !tpl.capabilities.isEmpty {
                                    Text("Host Bridge")
                                        .font(.system(size: 9, weight: .bold, design: .rounded))
                                        .foregroundStyle(.mint)
                                        .padding(.horizontal, 6).padding(.vertical, 1.5)
                                        .background(LiquidColors.pillSurface, in: Capsule())
                                }
                            }
                            Text(L10n.translate(tpl.description))
                                .font(.caption2)
                                .foregroundStyle(LiquidColors.textSecondary)
                                .lineLimit(2)
                            Text("触发词: \(tpl.keywords.joined(separator: ", "))")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(LiquidColors.textSecondary)
                        }
                        Spacer(minLength: 6)
                        if installed, let onOpenSettings {
                            Button(L10n.pick("打开设置 →", "Settings →")) { onOpenSettings(tpl.id) }
                                .buttonStyle(GlassPillButtonStyle(prominent: true, compact: true))
                        }
                        Button(installed ? L10n.pick("重装", "Reinstall") : L10n.pick("一键安装", "Install")) { onInstall(tpl) }
                            .buttonStyle(GlassPillButtonStyle(prominent: !installed, compact: installed))
                    }
                    .padding(10)
                    .liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)
                }
            }
        }
    }
}

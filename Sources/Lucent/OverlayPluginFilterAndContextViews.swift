import AppKit
import LucentCore
import SwiftUI

struct OverlayPluginFilterStrip: View {
    @ObservedObject var viewModel: AppViewModel

    private var stripPlugins: [PluginDescriptor] {
        viewModel.plugins.filter { $0.isValid && ($0.isBuiltin || $0.isEnabled) }
    }

    private func itemCount(for plugin: PluginDescriptor) -> Int {
        let idxHits = viewModel.pluginSearchEntries.reduce(into: 0) { acc, item in
            if item.pluginID == plugin.id { acc += 1 }
        }
        return idxHits + plugin.declaredCommands.count
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button(L10n.pick("全部插件 (\(stripPlugins.count))", "All (\(stripPlugins.count))")) {
                    viewModel.scopedPluginID = nil
                    viewModel.inlinePluginViewPayload = nil
                    viewModel.activeInlinePlugin = nil
                    viewModel.refreshDisplayedCandidates(resetSelection: true)
                    viewModel.bumpFocusToken()
                }
                .buttonStyle(GlassPillButtonStyle(prominent: viewModel.scopedPluginID == nil))

                Divider().frame(height: 16).opacity(0.35)

                ForEach(stripPlugins) { plugin in
                    let active = viewModel.scopedPluginID == plugin.id
                    let count = itemCount(for: plugin)
                    let label = count > 0 ? "\(plugin.displayName) (\(count))" : plugin.displayName
                    Button {
                        if active {
                            viewModel.scopedPluginID = nil
                            viewModel.refreshDisplayedCandidates(resetSelection: true)
                        } else {
                            viewModel.enterPluginScopedOverlay(plugin, initialQuery: viewModel.overlayQuery)
                        }
                    } label: {
                        HStack(spacing: 5) {
                            if let iconURL = plugin.customIconURL,
                               let nsImg = IconCache.shared.pluginIcon(for: iconURL, pointSize: 14) {
                                Image(nsImage: nsImg)
                                    .resizable().scaledToFit().frame(width: 12, height: 12)
                                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                            } else {
                                Image(systemName: plugin.symbolIconName)
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            Text(label).lineLimit(1)
                        }
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: active))
                }

                if let scoped = viewModel.activeScopedPlugin {
                    Divider().frame(height: 16).opacity(0.35)
                    if !scoped.isBuiltin {
                        let isSyncing = viewModel.syncingPluginIDs.contains(scoped.id)
                        Button {
                            viewModel.runBackgroundPluginSync(scoped)
                        } label: {
                            HStack(spacing: 5) {
                                if isSyncing { ProgressView().controlSize(.small) }
                                Text(isSyncing ? L10n.pick("同步中…", "Syncing…") : L10n.pick("同步索引", "Sync"))
                            }
                        }
                        .buttonStyle(GlassPillButtonStyle())
                        .disabled(isSyncing)
                    }
                    Button(L10n.pick("设置 ⌘,", "Settings ⌘,")) {
                        viewModel.openPluginSettings(id: scoped.id)
                    }
                    .buttonStyle(GlassPillButtonStyle())
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 24)
            .padding(.vertical, 7)
        }
    }
}

struct OverlayScopedPluginCapsule: View {
    let plugin: PluginDescriptor
    let onExit: () -> Void

    var body: some View {
        let tint = PluginVisualPalette.tint(from: plugin.manifest.accentColor, fallback: .cyan)
        HStack(spacing: 5) {
            if let iconURL = plugin.customIconURL,
               let nsImg = IconCache.shared.pluginIcon(for: iconURL, pointSize: 14) {
                Image(nsImage: nsImg)
                    .resizable().scaledToFit().frame(width: 13, height: 13)
                    .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
            } else {
                Image(systemName: plugin.symbolIconName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
            }
            Text(plugin.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(LiquidColors.textPrimary)
                .lineLimit(1)
            Button(action: onExit) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(LiquidColors.textSecondary)
            }
            .buttonStyle(.plain)
            .help(L10n.pick("退出插件子模式 (⌫ / Esc)", "Exit plugin scope (⌫ / Esc)"))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4.5)
        .background(tint.opacity(0.15), in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(tint.opacity(0.42), lineWidth: 0.85)
        }
    }
}

struct PluginContextActionStrip: View {
    let context: PluginContextPayload
    let plugins: [PluginDescriptor]
    let onTrigger: (PluginDescriptor, PluginContextPayload) -> Void

    private var matched: [PluginDescriptor] {
        PluginContextMatcher.matchingPlugins(in: plugins, for: context)
    }

    var body: some View {
        if !matched.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.pick("扩展插件联动", "Plugin Actions"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LiquidColors.textSecondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(matched) { plugin in
                            Button {
                                onTrigger(plugin, context)
                            } label: {
                                HStack(spacing: 4) {
                                    if let iconURL = plugin.customIconURL,
                                       let nsImg = IconCache.shared.pluginIcon(for: iconURL, pointSize: 13) {
                                        Image(nsImage: nsImg)
                                            .resizable().scaledToFit().frame(width: 12, height: 12)
                                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                                    } else {
                                        Image(systemName: plugin.symbolIconName)
                                            .font(.system(size: 10.5, weight: .semibold))
                                            .foregroundStyle(PluginVisualPalette.tint(from: plugin.manifest.accentColor))
                                    }
                                    Text(plugin.displayName)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(GlassPillButtonStyle())
                        }
                    }
                }
            }
        }
    }
}

struct OverlayPluginCommandLensCard: View {
    let command: PluginRegisteredCommand
    let onExecute: () -> Void
    let onToggleQuickButton: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                PluginIconBadge(
                    symbol: command.symbolName,
                    customIconURL: command.pluginCustomIconURL,
                    accentColor: command.isQuickButtonEnabled ? "orange" : command.pluginAccentColor,
                    isBuiltin: command.isBuiltin,
                    size: 38
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(command.localizedTitle).font(.headline).foregroundStyle(LiquidColors.textPrimary)
                    LiquidStatusPill(
                        title: command.pluginName,
                        symbol: command.isQuickButtonEnabled ? "bolt.fill" : "puzzlepiece.extension.fill",
                        tint: command.isQuickButtonEnabled ? .orange : .cyan
                    )
                }
            }
            Text(command.localizedSubtitle)
                .font(.caption).foregroundStyle(LiquidColors.textSecondary)
            LiquidSectionDivider()
            HStack {
                Text(L10n.pick("检索触发词", "Keywords")).font(.caption).foregroundStyle(LiquidColors.textSecondary)
                Spacer()
                Text(command.command.keywords.isEmpty ? L10n.pick("名称/拼音检索", "Title / Pinyin") : command.command.keywords.joined(separator: ", "))
                    .font(.caption.monospaced()).foregroundStyle(LiquidColors.textPrimary).lineLimit(1)
            }
            HStack {
                Text(L10n.pick("子功能快捷键", "Command Hotkey")).font(.caption).foregroundStyle(LiquidColors.textSecondary)
                Spacer()
                Text(command.effectiveHotKey ?? L10n.pick("未绑定", "None"))
                    .font(.caption.monospaced()).foregroundStyle(command.effectiveHotKey != nil ? .cyan : LiquidColors.textSecondary)
            }
            HStack {
                Text(L10n.pick("快捷按钮状态", "Quick Button")).font(.caption).foregroundStyle(LiquidColors.textSecondary)
                Spacer()
                Text(command.isQuickButtonEnabled ? L10n.pick("已挂载快捷按钮", "Mounted") : L10n.pick("未挂载（默认关闭）", "Off by default"))
                    .font(.caption).foregroundStyle(command.isQuickButtonEnabled ? .orange : LiquidColors.textSecondary)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 6) {
                Button(L10n.pick("立即执行子功能 ↩", "Run Command ↩"), action: onExecute)
                    .buttonStyle(GlassPillButtonStyle(prominent: true))
                HStack(spacing: 7) {
                    Button(command.isQuickButtonEnabled ? L10n.pick("移出快捷按钮", "Remove Quick Button") : L10n.pick("添加到快捷按钮", "Add Quick Button"), action: onToggleQuickButton)
                        .buttonStyle(GlassPillButtonStyle())
                    Button(L10n.pick("插件设置 ⌘,", "Settings ⌘,"), action: onOpenSettings)
                        .buttonStyle(GlassPillButtonStyle())
                }
            }
        }
        .padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
    }
}

import AppKit
import LumakeyCore
import SwiftUI

struct HotKeyExternalBindingsSection: View {
    let displayedPlugins: [PluginDescriptor]
    let boundScripts: [ScriptRecord]
    let pluginHotKeys: [ExternalPluginHotKey]
    let onOpenPluginSettings: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.pick(
                "插件、子功能与快捷脚本全局热键（点击右侧直接跳转对应设置页重录）",
                "Plugin, Command & Quick Script Global Hotkeys"
            ))
            .font(.caption.weight(.bold))
            .foregroundStyle(LiquidColors.textSecondary)
            .padding(.top, 4)

            ForEach(boundScripts) { script in
                HStack(spacing: 10) {
                    PluginIconBadge(
                        symbol: script.symbolIconName,
                        customIconURL: script.customIconURL(in: ScriptLibraryStore.shared.scriptsDirectory),
                        accentColor: script.accentColor,
                        size: 30
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(script.displayTitle).font(.caption.weight(.semibold)).lineLimit(1)
                            Text(script.runtime.badgeLabel)
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(.teal)
                                .padding(.horizontal, 5).padding(.vertical, 1.5)
                                .background(LiquidColors.pillSurface, in: Capsule())
                        }
                        Text(
                            script.keywords.isEmpty
                                ? script.fileName
                                : L10n.pick("脚本触发词: \(script.keywords.joined(separator: ", "))", "Keywords: \(script.keywords.joined(separator: ", "))")
                        )
                        .font(.caption2).foregroundStyle(LiquidColors.textSecondary).lineLimit(1)
                    }
                    Spacer()
                    Text(script.hotKey ?? L10n.pick("未绑定", "None"))
                        .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(.cyan)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(LiquidColors.pillSurface, in: Capsule())
                    if let onOpenPluginSettings {
                        Button(L10n.pick("前往设置 →", "Settings →")) {
                            onOpenPluginSettings("script:\(script.id)")
                        }
                        .buttonStyle(GlassPillButtonStyle(compact: true))
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)
            }

            ForEach(displayedPlugins) { plugin in
                let cmdBindings = pluginHotKeys.filter { $0.pluginID == plugin.id && $0.commandID != nil }
                HStack(spacing: 10) {
                    PluginIconBadge(plugin: plugin, size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plugin.displayName).font(.caption.weight(.semibold)).lineLimit(1)
                        Text(cmdBindings.isEmpty
                             ? "触发词: \(plugin.effectiveKeywords.joined(separator: ", "))"
                             : "子功能热键: \(cmdBindings.map { $0.chord.displayString }.joined(separator: ", "))")
                            .font(.caption2).foregroundStyle(LiquidColors.textSecondary).lineLimit(1)
                    }
                    Spacer()
                    Text(plugin.effectiveHotKey ?? (cmdBindings.first?.chord.displayString ?? "未绑定"))
                        .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                        .foregroundStyle((plugin.effectiveHotKey != nil || !cmdBindings.isEmpty) ? .cyan : LiquidColors.textSecondary)
                        .padding(.horizontal, 10).padding(.vertical, 4).background(LiquidColors.pillSurface, in: Capsule())
                    if let onOpenPluginSettings {
                        Button("前往设置 →") { onOpenPluginSettings(plugin.id) }.buttonStyle(GlassPillButtonStyle(compact: true))
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)
            }
        }
    }
}

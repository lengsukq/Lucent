import AppKit
import LucentCore
import SwiftUI

struct OverlayScriptLensCard: View {
    let match: ScriptMatch
    let scriptsDirectory: URL
    let onExecute: () -> Void
    let onToggleQuickBar: () -> Void
    let onOpenSettings: () -> Void
    let onRevealInFinder: () -> Void

    private var script: ScriptRecord { match.script }

    var body: some View {
        let tint = PluginVisualPalette.tint(from: script.accentColor, fallback: .teal)
        let customIcon = script.customIconURL(in: scriptsDirectory)
        let scopeLabels = script.allowedScopes.map(\.title).sorted()

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                PluginIconBadge(
                    symbol: script.symbolIconName,
                    customIconURL: customIcon,
                    accentColor: script.accentColor,
                    size: 38
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(script.displayTitle)
                        .font(.headline)
                        .foregroundStyle(LiquidColors.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        LiquidStatusPill(title: script.runtime.badgeLabel, symbol: "terminal.fill", tint: tint)
                        LiquidStatusPill(title: script.outputMode.shortBadge, tint: .cyan)
                    }
                }
            }

            Text(script.displaySubtitle)
                .font(.caption)
                .foregroundStyle(LiquidColors.textSecondary)
                .lineLimit(3)

            LiquidSectionDivider()

            rowMeta(
                label: L10n.pick("触发词", "Keywords"),
                value: script.keywords.isEmpty ? L10n.pick("标题 / 拼音检索", "Title / Pinyin") : script.keywords.joined(separator: ", ")
            )
            rowMeta(
                label: L10n.pick("脚本文件", "File"),
                value: script.fileName
            )
            rowMeta(
                label: L10n.pick("全局快捷键", "Hotkey"),
                value: script.hotKey ?? L10n.pick("未绑定", "None")
            )
            rowMeta(
                label: L10n.pick("沙箱作用域", "Sandbox"),
                value: scopeLabels.isEmpty ? L10n.pick("纯沙箱只读隔离", "Read-only Sandbox") : scopeLabels.joined(separator: " · ")
            )

            Spacer()

            VStack(alignment: .leading, spacing: 6) {
                Button(
                    match.trailingQuery.isEmpty
                        ? L10n.pick("立即运行脚本 ↩", "Run Script ↩")
                        : L10n.pick("传入「\(match.trailingQuery)」运行 ↩", "Run with \"\(match.trailingQuery)\" ↩"),
                    action: onExecute
                )
                .buttonStyle(GlassPillButtonStyle(prominent: true))

                HStack(spacing: 7) {
                    Button(L10n.pick("编辑脚本 ⌘,", "Edit ⌘,"), action: onOpenSettings)
                        .buttonStyle(GlassPillButtonStyle())
                    Button(
                        script.pinnedInQuickBar
                            ? L10n.pick("移出快捷栏", "Unpin Bar")
                            : L10n.pick("加到快捷栏", "Quick Bar"),
                        action: onToggleQuickBar
                    )
                    .buttonStyle(GlassPillButtonStyle())
                    Button(L10n.pick("访达 ⌘R", "Finder ⌘R"), action: onRevealInFinder)
                        .buttonStyle(GlassPillButtonStyle())
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
    }

    private func rowMeta(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(LiquidColors.textSecondary)
            Spacer()
            Text(value).font(.caption.monospaced()).foregroundStyle(LiquidColors.textPrimary).lineLimit(1)
        }
    }
}

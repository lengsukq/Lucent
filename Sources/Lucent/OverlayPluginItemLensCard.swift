import AppKit
import LucentCore
import SwiftUI

struct OverlayPluginItemLensCard: View {
    let entry: PluginSearchEntry
    let onOpenURL: (URL) -> Void
    let onRunManage: ([String]) -> Void
    let onCopyText: (String, String) -> Void

    var body: some View {
        let tint = PluginVisualPalette.tint(from: entry.tintColor, fallback: entry.pinned ? .orange : .cyan)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                PluginIconBadge(
                    symbol: entry.symbolIconName,
                    customIconURL: entry.customIconURL,
                    accentColor: entry.pinned ? "orange" : (entry.tintColor ?? "teal"),
                    size: 38
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.title)
                        .font(.headline)
                        .foregroundStyle(LiquidColors.textPrimary)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        LiquidStatusPill(title: entry.badge ?? entry.pluginName, tint: tint)
                        if entry.pinned {
                            LiquidStatusPill(title: "已置顶", symbol: "pin.fill", tint: .orange)
                        }
                    }
                }
            }

            if !entry.tags.isEmpty {
                Text(entry.tags.map { "#\($0)" }.joined(separator: "  "))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(tint)
            }

            if let rawURL = entry.url, !rawURL.isEmpty {
                Text(rawURL)
                    .font(.caption2.monospaced())
                    .foregroundStyle(LiquidColors.textSecondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }

            if !entry.subtitle.isEmpty {
                Text(entry.subtitle)
                    .font(.caption)
                    .foregroundStyle(LiquidColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            HStack(spacing: 7) {
                if let rawURL = entry.url, let url = URL(string: rawURL) {
                    Button(L10n.pick("打开 ↩", "Open ↩")) { onOpenURL(url) }
                        .buttonStyle(GlassPillButtonStyle(prominent: true))
                }
                if let args = entry.commandArgs, !args.isEmpty {
                    Button(L10n.pick("管理 / 置顶 ⌘↩", "Manage ⌘↩")) { onRunManage(args) }
                        .buttonStyle(GlassPillButtonStyle(prominent: entry.url == nil))
                }
                if let copyVal = entry.copyText ?? entry.url, !copyVal.isEmpty {
                    Button(L10n.pick("复制 ⌘C", "Copy ⌘C")) { onCopyText(copyVal, "已复制：\(entry.title)") }
                        .buttonStyle(GlassPillButtonStyle())
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
    }
}

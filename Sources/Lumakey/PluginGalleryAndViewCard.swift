import AppKit
import LumakeyCore
import SwiftUI

@MainActor
private final class PluginCardDialogState: ObservableObject {
    @Published var pendingConfirmAction: PluginViewAction?
    @Published var pendingPromptAction: PluginViewAction?
}

struct PluginStructuredViewCard: View {
    let payload: PluginViewPayload
    var bundleDirectory: URL? = nil
    var dataDirectory: URL? = nil
    var onCopyText: ((String) -> Void)? = nil
    var onOpenURL: ((URL) -> Void)? = nil
    var onRunCommandArgs: (([String]) -> Void)? = nil

    @StateObject private var dialogState = PluginCardDialogState()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(payload.title)
                        .font(.callout.weight(.bold))
                        .foregroundStyle(LiquidColors.textPrimary)
                    if let subtitle = payload.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(LiquidColors.textSecondary)
                    }
                }
                Spacer(minLength: 6)
                if let badge = payload.badge, !badge.isEmpty {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.cyan)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(LiquidColors.pillSurface, in: Capsule(style: .continuous))
                        .overlay { Capsule(style: .continuous).strokeBorder(LiquidColors.pillBorder, lineWidth: 0.7) }
                }
            }

            if let metrics = payload.metrics, !metrics.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(metrics) { metric in
                        Button { copyValue(metric.value) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(metric.key)
                                    .font(.caption2)
                                    .foregroundStyle(LiquidColors.textSecondary)
                                Text(metric.value)
                                    .font(.caption.monospaced().weight(.semibold))
                                    .foregroundStyle(LiquidColors.textPrimary)
                                    .lineLimit(1)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(LiquidColors.pillSurface, in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous)
                                    .strokeBorder(LiquidColors.pillBorder, lineWidth: 0.7)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let items = payload.items, !items.isEmpty {
                VStack(spacing: 6) {
                    ForEach(items) { item in
                        itemRow(item)
                    }
                }
            }

            if let markdown = payload.markdown, !markdown.isEmpty {
                markdownBlock(markdown)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
        .alert(
            dialogState.pendingConfirmAction?.label ?? L10n.pick("确认操作", "Confirm Action"),
            isPresented: Binding(
                get: { dialogState.pendingConfirmAction != nil },
                set: { if !$0 { dialogState.pendingConfirmAction = nil } }
            )
        ) {
            Button(L10n.pick("取消", "Cancel"), role: .cancel) { dialogState.pendingConfirmAction = nil }
            Button(L10n.pick("确认", "Confirm"), role: dialogState.pendingConfirmAction?.style == .destructive ? .destructive : nil) {
                guard let action = dialogState.pendingConfirmAction else { return }
                dialogState.pendingConfirmAction = nil
                if let fields = action.promptFields, !fields.isEmpty {
                    dialogState.pendingPromptAction = action
                } else {
                    onRunCommandArgs?(action.commandArgs)
                }
            }
        } message: {
            Text(dialogState.pendingConfirmAction?.confirmMessage ?? L10n.pick("确认执行该插件操作？", "Run this plugin action?"))
        }
        .sheet(item: $dialogState.pendingPromptAction) { action in
            PluginActionPromptSheet(
                action: action,
                onCancel: { dialogState.pendingPromptAction = nil },
                onSubmit: { finalArgs in
                    dialogState.pendingPromptAction = nil
                    onRunCommandArgs?(finalArgs)
                }
            )
        }
    }

    private func itemRow(_ item: PluginViewItem) -> some View {
        HStack(spacing: 10) {
            PluginItemLeadingBadge(
                rawIcon: item.icon,
                tintColor: item.tintColor,
                bundleDirectory: bundleDirectory,
                dataDirectory: dataDirectory,
                size: 26
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LiquidColors.textPrimary)
                    .lineLimit(1)
                if let sub = item.subtitle, !sub.isEmpty {
                    Text(sub)
                        .font(.caption2)
                        .foregroundStyle(LiquidColors.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 6)
            if let badge = item.badge, !badge.isEmpty {
                Text(badge)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(LiquidColors.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(LiquidColors.pillSurface, in: Capsule())
            }
            if let copyText = item.copyText, !copyText.isEmpty {
                Button(L10n.pick("复制", "Copy")) { copyValue(copyText) }
                    .buttonStyle(GlassPillButtonStyle(compact: true))
            }
            if let rawURL = item.openURL, let url = URL(string: rawURL) {
                Button(openButtonTitle(for: url)) {
                    if let onOpenURL { onOpenURL(url) } else { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(GlassPillButtonStyle(compact: true))
            }
            PluginViewActionButtons(
                item: item,
                onRunCommandArgs: onRunCommandArgs,
                onRequestAction: { action in
                    if let msg = action.confirmMessage, !msg.isEmpty {
                        dialogState.pendingConfirmAction = action
                    } else if let fields = action.promptFields, !fields.isEmpty {
                        dialogState.pendingPromptAction = action
                    } else {
                        onRunCommandArgs?(action.commandArgs)
                    }
                }
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(LiquidColors.pillSurface.opacity(0.75), in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous)
                .strokeBorder(LiquidColors.pillBorder, lineWidth: 0.65)
        }
    }

    private func openButtonTitle(for url: URL) -> String {
        if url.scheme?.lowercased() == "lumakey" {
            switch url.host?.lowercased() {
            case "reader": return L10n.pick("阅读窗", "Reader")
            case "pin": return L10n.pick("钉在屏幕", "Pin")
            case "image": return L10n.pick("看图窗", "Viewer")
            default: return L10n.pick("打开", "Open")
            }
        }
        return L10n.pick("打开", "Open")
    }

    @ViewBuilder
    private func markdownBlock(_ raw: String) -> some View {
        let blocks = MarkdownDocumentParser.parse(raw)
        let hasRichStructure = blocks.count > 1 || blocks.contains { block in
            if case .paragraph = block { return false }
            return true
        }
        Group {
            if hasRichStructure {
                MarkdownBlocksStackView(blocks: blocks, baseFontSize: 12)
            } else if let attributed = try? AttributedString(
                markdown: raw,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            ) {
                Text(attributed).font(.caption).foregroundStyle(LiquidColors.textPrimary).textSelection(.enabled)
            } else {
                Text(raw).font(.caption).foregroundStyle(LiquidColors.textPrimary).textSelection(.enabled)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LiquidColors.pillSurface, in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
    }

    private func copyValue(_ value: String) {
        if let onCopyText {
            onCopyText(value)
        } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
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

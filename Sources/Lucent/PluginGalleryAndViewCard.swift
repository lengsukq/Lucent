import AppKit
import LucentCore
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
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        let _ = themeManager.resolvedIsDark
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
                        .foregroundStyle(LiquidColors.accentPrimary)
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
                        .buttonStyle(LiquidBentoTileStyle(cornerRadius: LiquidRadii.control))
                    }
                }
            }

            if let items = payload.items, !items.isEmpty {
                VStack(spacing: 6) {
                    ForEach(items) { item in itemRow(item) }
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
        let hasCopy = (item.copyText?.isEmpty == false)
        let hasURL = (item.openURL.flatMap(URL.init(string:)) != nil)
        let hasCmd = !(item.commandArgs ?? []).isEmpty && onRunCommandArgs != nil
        let hasActions = !(item.actions ?? []).isEmpty
        let isTappable = hasCmd || hasURL || hasCopy
        let showActionStrip = hasCopy || hasURL || hasActions || hasCmd

        return VStack(alignment: .leading, spacing: 6) {
            Button { triggerPrimaryItemAction(item) } label: {
                HStack(alignment: .top, spacing: 9) {
                    PluginItemLeadingBadge(
                        rawIcon: item.icon, tintColor: item.tintColor,
                        bundleDirectory: bundleDirectory, dataDirectory: dataDirectory, size: 26
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(LiquidColors.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if let sub = item.subtitle, !sub.isEmpty {
                            Text(sub)
                                .font(.caption2)
                                .foregroundStyle(LiquidColors.textSecondary)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 4)
                    if let badge = item.badge, !badge.isEmpty {
                        Text(badge)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(LiquidColors.textSecondary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(LiquidColors.pillSurface, in: Capsule())
                    } else if isTappable && !showActionStrip {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(LiquidColors.textSecondary)
                            .padding(.top, 5)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(LiquidBentoTileStyle(cornerRadius: LiquidRadii.control))
            .disabled(!isTappable)

            if showActionStrip {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
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
                    .padding(.leading, 35)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7.5)
        .background(LiquidColors.pillSurface.opacity(0.75), in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous)
                .strokeBorder(LiquidColors.pillBorder, lineWidth: 0.65)
        }
    }

    private func triggerPrimaryItemAction(_ item: PluginViewItem) {
        if let args = item.commandArgs, !args.isEmpty, let onRunCommandArgs {
            onRunCommandArgs(args)
        } else if let rawURL = item.openURL, let url = URL(string: rawURL) {
            if let onOpenURL { onOpenURL(url) } else { NSWorkspace.shared.open(url) }
        } else if let copyText = item.copyText, !copyText.isEmpty {
            copyValue(copyText)
        }
    }

    private func openButtonTitle(for url: URL) -> String {
        if url.scheme?.lowercased() == "lucent" {
            switch url.host?.lowercased() {
            case "panel": return L10n.pick("悬浮面板", "Float Panel")
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

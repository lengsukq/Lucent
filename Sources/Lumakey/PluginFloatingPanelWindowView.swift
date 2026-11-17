import AppKit
import LumakeyCore
import SwiftUI

struct PluginFloatingPanelWindowView: View {
    @ObservedObject var controller: PluginFloatingPanelController
    let windowKey: String
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        let plugin = controller.plugin
        let title = plugin?.displayName ?? controller.pluginID
        SecondaryWindowScaffold(
            title: title,
            subtitle: L10n.pick("实时悬浮面板", "Live Floating Panel"),
            symbol: "macwindow.on.rectangle",
            pinWindowKey: windowKey
        ) {
            VStack(alignment: .leading, spacing: 10) {
                topControlBar(plugin: plugin)
                if !controller.missingCapabilities.isEmpty {
                    missingCapabilitiesBanner
                }
                if let err = controller.errorMessage, !err.isEmpty {
                    diagnosticBanner(err)
                }
                contentStage(plugin: plugin)
            }
            .padding(.top, 26)
        }
        .frame(minWidth: 420, minHeight: 360)
        .onAppear { controller.start() }
        .onDisappear { controller.stop() }
    }

    private func topControlBar(plugin: PluginDescriptor?) -> some View {
        HStack(spacing: 8) {
            if let plugin {
                PluginIconBadge(plugin: plugin, size: 28)
            } else {
                SquircleBadge(symbol: "puzzlepiece.extension.fill", topColor: .emeraldCompat, bottomColor: .cyan, size: 28)
            }

            VStack(alignment: .leading, spacing: 1.5) {
                HStack(spacing: 6) {
                    Text(statusHeadline)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(LiquidColors.textPrimary)
                        .lineLimit(1)
                    if controller.isRefreshing {
                        ProgressView().controlSize(.mini)
                    }
                }
                Text(updatedSubtitle)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(LiquidColors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            intervalMenu

            if controller.refreshIntervalSeconds > 0 {
                Button { controller.togglePaused() } label: {
                    Image(systemName: controller.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                }
                .buttonStyle(GlassPillButtonStyle(prominent: controller.isPaused, compact: true))
                .help(controller.isPaused ? L10n.pick("恢复自动刷新", "Resume Auto-Refresh") : L10n.pick("暂停自动刷新", "Pause Auto-Refresh"))
            }

            Button { controller.refreshNow() } label: {
                Label(L10n.pick("刷新", "Refresh"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(GlassPillButtonStyle(prominent: true, compact: true))

            Button { controller.openPluginSettings() } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(GlassPillButtonStyle(compact: true))
            .help(L10n.pick("打开插件独立设置 (⌘,)", "Plugin Settings (⌘,)"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .liquidGlassCard(cornerRadius: LiquidRadii.card)
    }

    private var intervalMenu: some View {
        Menu {
            ForEach(PluginFloatingPanelController.intervalChoices, id: \.self) { sec in
                Button {
                    controller.setInterval(sec)
                } label: {
                    let label = intervalLabel(sec)
                    if controller.refreshIntervalSeconds == sec {
                        Label(label, systemImage: "checkmark")
                    } else {
                        Text(label)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "timer")
                    .font(.system(size: 10, weight: .semibold))
                Text(intervalLabel(controller.refreshIntervalSeconds))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(LiquidColors.textSecondary)
            }
            .foregroundStyle(LiquidColors.textPrimary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(LiquidColors.pillSurface, in: Capsule(style: .continuous))
            .overlay { Capsule(style: .continuous).strokeBorder(LiquidColors.pillBorder, lineWidth: 0.75) }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var missingCapabilitiesBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            Text(L10n.pick(
                "待授权能力：\(controller.missingCapabilities.map(\.title).joined(separator: "、"))",
                "Missing permissions: \(controller.missingCapabilities.map(\.title).joined(separator: ", "))"
            ))
            .font(.caption2.weight(.medium))
            .foregroundStyle(LiquidColors.textPrimary)
            .lineLimit(2)
            Spacer(minLength: 4)
            Button(L10n.pick("一键授权并重跑", "Grant & Re-run")) {
                controller.grantMissingCapabilitiesAndRefresh()
            }
            .buttonStyle(GlassPillButtonStyle(prominent: true, compact: true))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.32), lineWidth: 0.7)
        }
    }

    private func diagnosticBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption2)
                .foregroundStyle(LiquidColors.textPrimary)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .liquidGlassCard(cornerRadius: LiquidRadii.control)
    }

    @ViewBuilder
    private func contentStage(plugin: PluginDescriptor?) -> some View {
        let dataDir = plugin.flatMap {
            PluginDataPaths.dataDirectory(for: $0.id, pluginsRoot: $0.directoryURL.deletingLastPathComponent())
        }
        ScrollView {
            if let payload = controller.payload {
                PluginStructuredViewCard(
                    payload: payload,
                    bundleDirectory: plugin?.directoryURL,
                    dataDirectory: dataDir,
                    onCopyText: { text in
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    },
                    onOpenURL: { url in controller.handleOpenURL(url) },
                    onRunCommandArgs: { args in controller.refreshNow(actionArguments: args) }
                )
            } else if let plain = controller.plainTextFallback, !plain.isEmpty {
                Text(plain)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(LiquidColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
                    .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
            } else {
                VStack(spacing: 10) {
                    ProgressView()
                    Text(L10n.pick("正在实时拉取插件面板数据…", "Fetching live plugin panel…"))
                        .font(.caption)
                        .foregroundStyle(LiquidColors.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
                .liquidGlassCard(cornerRadius: LiquidRadii.card)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusHeadline: String {
        if controller.refreshIntervalSeconds <= 0 {
            return L10n.pick("手动刷新模式", "Manual Refresh")
        }
        if controller.isPaused {
            return L10n.pick("已暂停自动刷新", "Auto-Refresh Paused")
        }
        return L10n.pick("实时监控中 · 关窗即停", "Live · Stops on Close")
    }

    private var updatedSubtitle: String {
        guard let date = controller.lastUpdatedAt else {
            return L10n.pick("等待首次采样…", "Sampling…")
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let clock = formatter.string(from: date)
        if let ms = controller.lastDurationMs {
            return L10n.pick("更新于 \(clock) · \(ms)ms", "Updated \(clock) · \(ms)ms")
        }
        return L10n.pick("更新于 \(clock)", "Updated \(clock)")
    }

    private func intervalLabel(_ sec: Int) -> String {
        if sec <= 0 { return L10n.pick("手动", "Manual") }
        return "\(sec)s"
    }
}

private extension Color {
    static var emeraldCompat: Color { Color(red: 0.06, green: 0.73, blue: 0.51) }
}

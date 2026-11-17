import AppKit
import LumakeyCore
import SwiftUI

struct OverlaySideLensView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var usageTracker = AppUsageTrackerController.shared

    private var lensIdentity: String {
        if viewModel.inlinePluginViewPayload != nil {
            return "pluginView:\(viewModel.activeInlinePlugin?.id ?? "inline")"
        }
        if viewModel.inlineResultBody != nil {
            return "inlineResult:\(viewModel.inlineResultTitle)"
        }
        return "candidate:\(viewModel.selectedCandidate?.id ?? "empty")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let viewPayload = viewModel.inlinePluginViewPayload {
                PluginViewLensContainerCard(
                    payload: viewPayload,
                    plugin: viewModel.activeInlinePlugin,
                    onCopyText: { val in copyString(val, toast: "已复制：\(val)") },
                    onOpenURL: { url in viewModel.handlePluginOpenURL(url) },
                    onRunCommandArgs: { args in
                        guard let plugin = viewModel.activeInlinePlugin else { return }
                        viewModel.runPlugin(plugin, query: "", arguments: args, showInline: true)
                    },
                    onGrantCapabilitiesAndRerun: {
                        guard let plugin = viewModel.activeInlinePlugin else { return }
                        viewModel.grantMissingCapabilitiesAndRerun(plugin)
                    },
                    onPopOutFloatingPanel: viewModel.activeInlinePlugin.map { activePlug in
                        { viewModel.openFloatingPluginPanel(for: activePlug, seedPayload: viewPayload) }
                    },
                    onClose: {
                        withAnimation(LiquidMotion.snappySpring) {
                            viewModel.inlinePluginViewPayload = nil
                            viewModel.activeInlinePlugin = nil
                        }
                    }
                )
            } else if let inline = viewModel.inlineResultBody {
                InlineOutputLensCard(
                    title: viewModel.inlineResultTitle,
                    outputText: inline,
                    onCopy: { copyString(inline, toast: "已复制输出内容") },
                    onClose: { withAnimation(LiquidMotion.snappySpring) { viewModel.inlineResultBody = nil } }
                )
            } else if let candidate = viewModel.selectedCandidate, case .clipboard(let clip) = candidate.kind {
                clipboardDetailLens(clip)
                if let ctx = PluginContextMatcher.payloadFromClipboard(clip) {
                    PluginContextActionStrip(context: ctx, plugins: viewModel.plugins) { plugin, payload in
                        viewModel.runPluginWithContext(plugin, context: payload)
                    }
                }
            } else if let candidate = viewModel.selectedCandidate {
                candidateDetailLens(candidate)
            } else {
                SideLivePreviewCard(previewState: viewModel.previewState).frame(maxHeight: .infinity)
            }
        }
        .id(lensIdentity)
        .transition(LiquidMotion.lensTransition)
        .animation(LiquidMotion.snappySpring, value: lensIdentity)
        .padding(12)
    }

    @ViewBuilder
    private func clipboardDetailLens(_ clip: ClipboardEntry) -> some View {
        switch clip.payloadKind {
        case .colorHex(let hex):
            ColorSwatchLensCard(
                hex: hex, clip: clip,
                onCopyText: { value, toast in copyString(value, toast: toast) },
                onCopyClipboard: { viewModel.executeClipboardEntry(clip) },
                onPasteClipboard: { viewModel.executeClipboardEntry(clip, autoPaste: true) },
                onTogglePin: { viewModel.toggleClipboardPin(clip) }
            )
        case .image(let url, let dims):
            ImageClipboardLensCard(
                url: url, dimensions: dims, clip: clip,
                onCopyImage: { viewModel.executeClipboardEntry(clip) },
                onPasteImage: { viewModel.executeClipboardEntry(clip, autoPaste: true) },
                onPinOverlay: { PinWindowController.shared.pinImage(at: url) },
                onOpenViewer: { viewModel.openMediaWindow(for: url, kind: .image, pinOnTop: true) },
                onTogglePin: { viewModel.toggleClipboardPin(clip) },
                onCopyText: { value, toast in copyString(value, toast: toast) }
            )
        case .video(let url):
            VideoClipboardLensCard(
                url: url, clip: clip,
                onCopyVideo: { viewModel.executeClipboardEntry(clip) },
                onPasteVideo: { viewModel.executeClipboardEntry(clip, autoPaste: true) },
                onOpenPlayer: { viewModel.openMediaWindow(for: url, kind: .video, pinOnTop: true) },
                onTogglePin: { viewModel.toggleClipboardPin(clip) }
            )
        case .file(let url):
            FileClipboardLensCard(
                url: url, clip: clip,
                onCopyFile: { viewModel.executeClipboardEntry(clip) },
                onPasteFile: { viewModel.executeClipboardEntry(clip, autoPaste: true) },
                onTogglePin: { viewModel.toggleClipboardPin(clip) }
            )
        case .text:
            TextClipboardLensCard(
                clip: clip,
                onCopyClipboard: { viewModel.executeClipboardEntry(clip) },
                onPasteClipboard: { viewModel.executeClipboardEntry(clip, autoPaste: true) },
                onTogglePin: { viewModel.toggleClipboardPin(clip) }
            )
        }
    }

    @ViewBuilder
    private func candidateDetailLens(_ candidate: LauncherCandidate) -> some View {
        switch candidate.kind {
        case .fileHit(let hit):
            SideLivePreviewCard(previewState: viewModel.previewState).frame(maxHeight: .infinity)
            fileActionStrip(for: hit)
        case .app(let app): appDetailCard(app: app, candidate: candidate)
        case .calculator(let expr, let resultText, let badge):
            CalculatorLensCard(expression: expr, resultText: resultText, badge: badge) { viewModel.executeCandidate(candidate) }
        case .devTool(let tool):
            DevToolLensCard(
                tool: tool, onExecute: { viewModel.executeCandidate(candidate) },
                onCopyText: { val, toast in copyString(val, toast: toast) },
                onPinImage: { url in PinWindowController.shared.pinImage(at: url) }
            )
        case .snippet(let match):
            SnippetLensCard(
                match: match, onExecute: { viewModel.executeCandidate(candidate) },
                onOpenSettings: { viewModel.openRoute(.settings(.snippets)) }
            )
        case .plugin(let plugin): pluginDetailCard(plugin: plugin, candidate: candidate)
        case .pluginCommand(let regCmd):
            OverlayPluginCommandLensCard(
                command: regCmd, onExecute: { viewModel.executeCandidate(candidate) },
                onToggleQuickButton: { viewModel.togglePluginCommandQuickButton(regCmd) },
                onOpenSettings: { viewModel.openPluginSettings(id: regCmd.pluginID) }
            )
        case .pluginItem(let entry):
            OverlayPluginItemLensCard(
                entry: entry, onOpenURL: { url in viewModel.handlePluginOpenURL(url) },
                onRunManage: { args in
                    if let plugin = viewModel.plugins.first(where: { $0.id == entry.pluginID }) {
                        viewModel.runPlugin(plugin, query: "", arguments: args, showInline: true)
                    }
                },
                onCopyText: { val, toast in copyString(val, toast: toast) }
            )
        case .command(let cmd):
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    SquircleBadge(symbol: cmd.symbol, topColor: .cyan, bottomColor: .blue, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cmd.title).font(.headline).foregroundStyle(LiquidColors.textPrimary)
                        LiquidStatusPill(title: cmd.badgeLabel, tint: .cyan)
                    }
                }
                Text(cmd.subtitle).font(.caption).foregroundStyle(LiquidColors.textSecondary)
                Spacer()
                Button("执行命令 ↩") { viewModel.executeCandidate(candidate) }.buttonStyle(GlassPillButtonStyle(prominent: true))
            }
            .padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
        case .clipboard: EmptyView()
        }
    }

    private func appDetailCard(app: InstalledAppItem, candidate: LauncherCandidate) -> some View {
        let pinned = usageTracker.isPinned(app)
        let summary = usageTracker.usageSummary(for: app)
        return VStack(spacing: 11) {
            Spacer(minLength: 0)
            Image(nsImage: IconCache.shared.appIcon(for: app.url)).resizable()
                .frame(width: 68, height: 68).shadow(color: .black.opacity(0.18), radius: 8, y: 4)
            Text(app.displayName).font(.headline).foregroundStyle(LiquidColors.textPrimary)
            LiquidStatusPill(title: summary, symbol: pinned ? "pin.fill" : "clock", tint: pinned ? .orange : .cyan)
            Text(app.url.path).font(.caption2.monospaced()).foregroundStyle(LiquidColors.textSecondary)
                .multilineTextAlignment(.center).lineLimit(2)
            Spacer(minLength: 0)
            VStack(spacing: 7) {
                HStack(spacing: 7) {
                    Button("启动应用 ↩") { viewModel.executeCandidate(candidate) }.buttonStyle(GlassPillButtonStyle(prominent: true))
                    Button("访达 ⌘R") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }.buttonStyle(GlassPillButtonStyle())
                }
                Button { usageTracker.togglePin(app) } label: {
                    Label(pinned ? "取消钉住" : "钉在常用栏", systemImage: pinned ? "pin.slash" : "pin.fill")
                }.buttonStyle(GlassPillButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(14)
        .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
    }

    private func pluginDetailCard(plugin: PluginDescriptor, candidate: LauncherCandidate) -> some View {
        let tint = PluginVisualPalette.tint(from: plugin.manifest.accentColor, fallback: plugin.isBuiltin ? .mint : .cyan)
        let missingCaps = plugin.isBuiltin ? [] : plugin.declaredCapabilities.filter { !plugin.grantedCapabilities.contains($0) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                PluginIconBadge(plugin: plugin, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(plugin.displayName).font(.headline).foregroundStyle(LiquidColors.textPrimary)
                    LiquidStatusPill(title: plugin.displayCategoryBadge, tint: tint)
                }
            }
            Text(plugin.effectiveStatusSummary).font(.caption).foregroundStyle(LiquidColors.textSecondary)
            if !missingCaps.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Label(
                        L10n.pick("待授权能力：\(missingCaps.map(\.title).joined(separator: "、"))", "Needs permissions: \(missingCaps.map(\.title).joined(separator: ", "))"),
                        systemImage: "lock.shield.fill"
                    ).font(.caption2.weight(.semibold)).foregroundStyle(.orange)
                    Button(L10n.pick("一键授权并运行", "Grant & Run")) { viewModel.grantMissingCapabilitiesAndRerun(plugin) }
                        .buttonStyle(GlassPillButtonStyle(prominent: true, compact: true))
                }
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
            }
            LiquidSectionDivider()
            MetadataLabel(key: L10n.pick("触发词", "Keywords"), val: plugin.effectiveKeywords.joined(separator: ", "))
            MetadataLabel(key: L10n.pick("子功能", "Commands"), val: "\(plugin.declaredCommands.count)")
            MetadataLabel(key: L10n.pick("全局热键", "Hotkey"), val: plugin.effectiveHotKey ?? L10n.pick("未绑定", "None"))
            Spacer()
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Button(L10n.pick("打开/运行 ↩", "Run ↩")) { viewModel.executeCandidate(candidate) }.buttonStyle(GlassPillButtonStyle(prominent: true))
                    if viewModel.scopedPluginID != plugin.id {
                        Button(L10n.pick("子功能列表 ⇥", "Commands ⇥")) { viewModel.enterPluginScopedOverlay(plugin) }.buttonStyle(GlassPillButtonStyle())
                    }
                }
                HStack(spacing: 7) {
                    if !plugin.isBuiltin && plugin.manifest.mode == .view {
                        Button(L10n.pick("悬浮窗", "Float")) { viewModel.openFloatingPluginPanel(for: plugin) }
                            .buttonStyle(GlassPillButtonStyle())
                    }
                    Button(L10n.pick("设置 ⌘,", "Settings ⌘,")) { viewModel.openPluginSettings(id: plugin.id) }.buttonStyle(GlassPillButtonStyle())
                    Button(plugin.pinnedInOverlay ? L10n.pick("移出快捷按钮", "Unpin") : L10n.pick("快捷按钮", "Quick Btn")) {
                        viewModel.togglePluginOverlayPin(plugin)
                    }.buttonStyle(GlassPillButtonStyle())
                }
            }
        }
        .padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
    }

    @ViewBuilder
    private func fileActionStrip(for hit: EverythingSearchHit) -> some View {
        let canDedicatedWindow = [.markdown, .text, .image, .video].contains(hit.mediaKind)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if canDedicatedWindow {
                    Button(hit.mediaKind == .video ? "影院播放" : "独立窗口") { viewModel.openMediaWindow(for: hit.url, kind: hit.mediaKind) }
                        .buttonStyle(GlassPillButtonStyle(prominent: true))
                } else {
                    Button("打开 ↩") { viewModel.executeEverythingHit(hit) }.buttonStyle(GlassPillButtonStyle(prominent: true))
                }
                if hit.mediaKind == .image {
                    Button("复制图片") {
                        _ = ScreenshotCompositor.copyImageFileToPasteboard(at: hit.url)
                        viewModel.serviceMessage = "图片已复制到剪贴板"
                    }.buttonStyle(GlassPillButtonStyle())
                }
                Button("访达 ⌘R") { NSWorkspace.shared.activateFileViewerSelecting([hit.url]) }.buttonStyle(GlassPillButtonStyle())
            }
            if let ctx = PluginContextMatcher.payloadFromFiles([hit.url], source: "everything") {
                PluginContextActionStrip(context: ctx, plugins: viewModel.plugins) { plugin, payload in
                    viewModel.runPluginWithContext(plugin, context: payload)
                }
            }
        }
    }

    private func copyString(_ value: String, toast: String) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string)
        viewModel.serviceMessage = toast
    }
}

private struct MetadataLabel: View {
    let key: String; let val: String
    var body: some View {
        HStack {
            Text(key).font(.caption).foregroundStyle(LiquidColors.textSecondary)
            Spacer()
            Text(val).font(.caption.monospaced()).foregroundStyle(LiquidColors.textPrimary).lineLimit(1)
        }
    }
}

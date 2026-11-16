import AppKit
import LumakeyCore
import SwiftUI

struct SettingsDetailSectionsView: View {
    @ObservedObject var viewModel: AppViewModel
    let section: SettingsSection
    @StateObject private var pluginCenterCtrl = PluginCenterController()

    var body: some View {
        switch section {
        case .plugins: pluginsSection
        case .about: aboutSection
        default: EmptyView()
        }
    }

    private var pluginsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeroHeader(
                symbol: "puzzlepiece.extension.fill", topColor: .purple, bottomColor: .indigo,
                title: "插件市场、权限全景与原生 MCP",
                subtitle: "已安装的内置与外部插件均挂载于左侧「插件独立设置」栏；点击右侧可一键复制完整 AI Agent 接入提示词。"
            ) {
                HStack(spacing: 8) {
                    if pluginCenterCtrl.activeTab != .mcp {
                        Button("查看 MCP 提示词") {
                            pluginCenterCtrl.activeTab = .mcp
                        }
                        .buttonStyle(GlassPillButtonStyle())
                    }
                    Button("复制 Agent 接入提示词") {
                        let bin = MCPAgentPromptBuilder.resolveExecutablePath()
                        let prompt = MCPAgentPromptBuilder.buildAgentPrompt(
                            executablePath: bin.path,
                            extraTask: pluginCenterCtrl.mcpExtraTask,
                            language: LanguageManager.shared.current
                        )
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(prompt, forType: .string)
                        let msg = L10n.pick(
                            "✓ 已复制完整 Agent 接入提示词，可直接粘贴发送给 AI 助手",
                            "✓ Copied full Agent setup prompt to clipboard"
                        )
                        pluginCenterCtrl.statusNote = msg
                        viewModel.serviceMessage = msg
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: true))
                }
            }
            PluginCenterView(viewModel: viewModel, ctrl: pluginCenterCtrl)
        }
    }

    private var aboutSection: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 10) {
                    SquircleBadge(symbol: "sparkles", topColor: .cyan, bottomColor: .indigo, size: 60)
                    Text(L10n.pick("流光 Lumakey 0.8.9", "Lumakey 0.8.9")).font(.title2.weight(.bold))
                    Text(L10n.pick("Apple Silicon (arm64) 原生 Swift 6 · 零第三方依赖 · Build 26", "Apple Silicon (arm64) Native Swift 6 · Zero Third-Party Dependencies · Build 26"))
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                    Text(
                        L10n.pick(
                            "轻量级菜单栏高效快捷中枢：内置中英双语实时切换与「凝霜留白」「霓彩流光」双视觉主题，统合全局智能检索、插件独立设置与按需快捷按钮、文件工作台多选归档、原生 GIF 录屏、智能截图标注与钉屏、离线 Vision OCR、WebDAV 云备份与插件系统 v3。",
                            "Lightweight native menu bar productivity hub with live Chinese/English switching and dual built-in themes (Pure Frost & Prism Pulse), uniting omni-search, dedicated plugin settings & quick buttons, multi-volume file workspace, GIF capture, screenshot annotation & pinning, offline Vision OCR, WebDAV backup, and Plugin System v3."
                        )
                    )
                    .font(.callout).multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 540)

                    FlowWrapLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                        Button("立即呼出快捷台 (⌥Space)") { viewModel.showOverlay(filter: .all) }
                            .buttonStyle(GlassPillButtonStyle(prominent: true))
                        Button("文件工作台 (⌥E)") { viewModel.openRoute(.workspace) }
                            .buttonStyle(GlassPillButtonStyle())
                        Button("网络流量监控 (⌥N)") { viewModel.openRoute(.networkMonitor) }
                            .buttonStyle(GlassPillButtonStyle())
                        Button("GIF 动图录制 (⌥G)") { viewModel.startGifRecording() }
                            .buttonStyle(GlassPillButtonStyle())
                    }
                    .padding(.top, 4)
                }
                .padding(20).frame(maxWidth: .infinity)
                .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)

                HStack(spacing: 10) {
                    aboutPillar("cpu", .cyan, "Native Services First", "完全基于 SwiftUI、AppKit、Vision 与 CoreGraphics 原生构建，无任何外部依赖或浏览器壳。")
                    aboutPillar("leaf.arrow.circlepath", .green, "最优内存自洁架构", "浮窗隐藏 30s 回收视图树，索引按需驻留 · 空闲 90s 卸载（保留 LMKYIDX2 快照），独立窗口关闭即销毁。")
                    aboutPillar("shield.lefthalf.filled", .orange, "无感静默启动策略", "全部悬浮监控与顶部实时状态新装默认关闭，不安装任何 launchd 后台常驻守护进程。")
                }
            }
            .padding(.trailing, 4)
        }
    }

    private func aboutPillar(_ symbol: String, _ color: Color, _ title: String, _ desc: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).font(.title3).foregroundStyle(color)
            Text(L10n.translate(title)).font(.callout.weight(.semibold))
            Text(L10n.translate(desc)).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)
    }
}

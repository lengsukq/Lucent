import AppKit
import LumakeyCore
import SwiftUI

struct PluginMCPSetupView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var ctrl: PluginCenterController
    @ObservedObject private var languageManager = LanguageManager.shared

    private var resolvedBinary: (path: String, exists: Bool) {
        MCPAgentPromptBuilder.resolveExecutablePath()
    }

    private var fullPrompt: String {
        MCPAgentPromptBuilder.buildAgentPrompt(
            executablePath: resolvedBinary.path,
            extraTask: ctrl.mcpExtraTask,
            language: languageManager.current
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            actionHeaderCard
            extraTaskBar
            promptPreviewCard
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var actionHeaderCard: some View {
        let bin = resolvedBinary
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                SquircleBadge(symbol: "terminal.fill", topColor: .cyan, bottomColor: .indigo, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(L10n.pick("一键发给 AI Agent 自动接入 lumakey-mcp", "One-Click Prompt for AI Agents to Connect lumakey-mcp"))
                            .font(.callout.weight(.bold))
                            .foregroundStyle(LiquidColors.textPrimary)
                            .lineLimit(1)
                        Text(bin.exists ? L10n.pick("二进制已就绪 · stdio", "Binary Ready · stdio") : L10n.pick("默认包内路径", "Bundle Path"))
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundStyle(bin.exists ? Color.mint : Color.orange)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(LiquidColors.pillSurface, in: Capsule())
                    }
                    Text(L10n.pick(
                        "支持 Claude Code、Cursor、Codex、Gemini CLI、Windsurf、Claude Desktop 等客户端；复制下方完整提示词发给 Agent 即可自动挂载并读取插件规范。",
                        "Works with Claude Code, Cursor, Codex, Gemini CLI, Windsurf, Claude Desktop & more — paste the prompt to your Agent to auto-configure."
                    ))
                    .font(.caption2)
                    .foregroundStyle(LiquidColors.textSecondary)
                    .lineLimit(2)
                }
                Spacer(minLength: 6)
                Button {
                    copyPrompt()
                } label: {
                    Label(L10n.pick("复制完整 Agent 提示词", "Copy Full Agent Prompt"), systemImage: "doc.on.doc.fill")
                }
                .buttonStyle(GlassPillButtonStyle(prominent: true))
            }

            HStack(spacing: 8) {
                Image(systemName: "bolt.horizontal.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.cyan)
                Text(bin.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(LiquidColors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: 6)
                if bin.exists {
                    Button(L10n.pick("访达定位", "Reveal in Finder")) {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: bin.path)])
                    }
                    .buttonStyle(GlassPillButtonStyle(compact: true))
                }
                Button(L10n.pick("仅复制纯 JSON", "Copy Raw JSON")) {
                    let json = MCPAgentPromptBuilder.buildConfigJSON(executablePath: bin.path)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(json, forType: .string)
                    let msg = L10n.pick("已复制 lumakey-mcp 纯 JSON 配置", "Copied raw lumakey-mcp JSON config")
                    ctrl.statusNote = msg
                    viewModel.serviceMessage = msg
                }
                .buttonStyle(GlassPillButtonStyle(compact: true))
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(LiquidColors.pillSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
        }
        .padding(12)
        .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
    }

    private var extraTaskBar: some View {
        HStack(spacing: 8) {
            GlassInputField(
                symbol: "sparkles",
                placeholder: L10n.pick(
                    "可选：附带接入后让 Agent 顺手完成的任务（如：帮我写一个查看端口占用的视图插件）",
                    "Optional: append a follow-up task for the Agent (e.g. build a port inspector view plugin)"
                ),
                text: $ctrl.mcpExtraTask
            )
            if !ctrl.mcpExtraTask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(L10n.pick("清空附加需求", "Clear")) {
                    ctrl.mcpExtraTask = ""
                }
                .buttonStyle(GlassPillButtonStyle(compact: true))
            }
        }
    }

    private var promptPreviewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(
                    L10n.pick("可直接发送给 AI Agent 的完整提示词预览", "Ready-to-Send AI Agent Prompt Preview"),
                    systemImage: "text.bubble.fill"
                )
                .font(.caption.weight(.bold))
                .foregroundStyle(LiquidColors.textSecondary)
                Spacer()
                Button(L10n.pick("复制提示词", "Copy Prompt")) {
                    copyPrompt()
                }
                .buttonStyle(GlassPillButtonStyle(prominent: true, compact: true))
            }

            ScrollView {
                Text(fullPrompt)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(LiquidColors.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(LiquidColors.pillSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous)
                    .strokeBorder(LiquidColors.pillBorder, lineWidth: 0.75)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
    }

    private func copyPrompt() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fullPrompt, forType: .string)
        let msg = L10n.pick(
            "✓ 已复制完整 Agent 接入提示词，可直接粘贴发送给任意 AI 编程助手",
            "✓ Copied full Agent setup prompt — paste it directly into your AI coding assistant"
        )
        ctrl.statusNote = msg
        viewModel.serviceMessage = msg
    }
}

import AppKit
import LucentCore
import SwiftUI

struct BatchRenameSheet: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ZStack {
            LiquidFluidBackdrop()
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    SquircleBadge(symbol: "pencil.and.list.clipboard", topColor: .orange, bottomColor: .pink, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("安全批量重命名").font(.headline)
                        Text("共 \(viewModel.batchRenamePreview.count) 项待预览，提交前自动校验重名与非法字符")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("序号递增", isOn: $viewModel.renameRule.useIndexNumbering)
                        .toggleStyle(.switch)
                }
                .padding(12)
                .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)

                HStack(spacing: 8) {
                    GlassInputField(symbol: "magnifyingglass", placeholder: "查找文本", text: $viewModel.renameRule.findText)
                    GlassInputField(symbol: "arrow.triangle.2.circlepath", placeholder: "替换为", text: $viewModel.renameRule.replaceText)
                    GlassInputField(placeholder: "统一前缀", text: $viewModel.renameRule.prefix)
                    GlassInputField(placeholder: "统一后缀", text: $viewModel.renameRule.suffix)
                }

                List(viewModel.batchRenamePreview) { item in
                    HStack(spacing: 8) {
                        Text(item.originalName).foregroundStyle(.secondary).lineLimit(1)
                        Image(systemName: "arrow.right").font(.caption).foregroundStyle(.cyan)
                        Text(item.proposedName).fontWeight(.medium).lineLimit(1)
                        Spacer()
                        if let reason = item.conflictReason {
                            Text(reason)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.red, in: Capsule())
                        } else {
                            Text("可提交")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
                .frame(minHeight: 240)

                HStack {
                    Spacer()
                    Button("取消") { viewModel.showBatchRenameSheet = false }
                        .buttonStyle(GlassPillButtonStyle())
                    Button("确认重命名") { viewModel.applyBatchRename() }
                        .buttonStyle(GlassPillButtonStyle(prominent: true))
                        .disabled(viewModel.batchRenamePreview.contains(where: \.hasConflict))
                }
            }
            .padding(16)
        }
        .frame(minWidth: 740, minHeight: 450)
    }
}

struct WorkspaceHostView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var prompt: WorkspacePromptController

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        self.prompt = viewModel.workspacePrompt
    }

    var body: some View {
        SecondaryWindowScaffold(
            title: "文件与外置磁盘工作台",
            subtitle: viewModel.layoutMode == .dual ? "双栏模式" : "单栏模式",
            symbol: "externaldrive.fill.badge.checkmark",
            pinWindowKey: "workspace"
        ) {
            FileWorkspaceView(viewModel: viewModel)
        }
        .background { WorkspaceKeyShortcutBridgeView(viewModel: viewModel).frame(width: 0, height: 0) }
        .sheet(isPresented: $viewModel.showBatchRenameSheet) { BatchRenameSheet(viewModel: viewModel) }
        .sheet(
            isPresented: Binding(get: { prompt.isPresented }, set: { if !$0 { prompt.dismiss() } })
        ) {
            WorkspacePromptSheetView(viewModel: viewModel, prompt: prompt)
        }
        .alert(
            viewModel.diagnostic?.title ?? "提示",
            isPresented: Binding(get: { viewModel.diagnostic != nil }, set: { if !$0 { viewModel.diagnostic = nil } })
        ) {
            Button("确定", role: .cancel) { viewModel.diagnostic = nil }
        } message: {
            if let diag = viewModel.diagnostic {
                Text("\(diag.reason)\n\(diag.dataSafety)\n\(diag.nextStep)")
            }
        }
    }
}

import LumakeyCore
import SwiftUI

struct PluginScaffoldFormView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var ctrl: PluginCenterController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("脚手架创建自定义插件 (v3.1)").font(.callout.weight(.semibold))
                VStack(alignment: .leading, spacing: 3) {
                    Text("插件唯一 ID").font(.caption2.weight(.medium)).foregroundStyle(LiquidColors.textSecondary)
                    GlassInputField(symbol: "number", placeholder: "小写字母 / 数字 / 连字符", text: $ctrl.newID)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("插件显示名称").font(.caption2.weight(.medium)).foregroundStyle(LiquidColors.textSecondary)
                    GlassInputField(symbol: "tag", placeholder: "显示名称", text: $ctrl.newName)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("触发关键词（逗号分隔）").font(.caption2.weight(.medium)).foregroundStyle(LiquidColors.textSecondary)
                    GlassInputField(symbol: "text.magnifyingglass", placeholder: "触发关键词", text: $ctrl.newKeywords)
                }
                HStack(spacing: 8) {
                    Text("输出协议:").font(.caption).foregroundStyle(LiquidColors.textSecondary)
                    ForEach(PluginMode.allCases, id: \.rawValue) { mode in
                        Button(mode.rawValue.uppercased()) { ctrl.newMode = mode }
                            .buttonStyle(GlassPillButtonStyle(prominent: ctrl.newMode == mode))
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Host Bridge 能力声明（不选即 []）").font(.caption2.weight(.medium)).foregroundStyle(LiquidColors.textSecondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 6)], spacing: 6) {
                        ForEach(PluginCapability.allCases) { cap in
                            let selected = ctrl.newCapabilities.contains(cap)
                            Button(cap.title) {
                                if selected { ctrl.newCapabilities.remove(cap) } else { ctrl.newCapabilities.insert(cap) }
                            }
                            .buttonStyle(GlassPillButtonStyle(prominent: selected))
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("外部资源作用域声明（必填，不选即 []）").font(.caption2.weight(.medium)).foregroundStyle(LiquidColors.textSecondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 6)], spacing: 6) {
                        ForEach(PluginResourceScope.allCases) { scope in
                            let selected = ctrl.newResourceScopes.contains(scope)
                            Button(scope.shortLabel) {
                                if selected { ctrl.newResourceScopes.remove(scope) } else { ctrl.newResourceScopes.insert(scope) }
                            }
                            .buttonStyle(GlassPillButtonStyle(prominent: selected))
                        }
                    }
                }
                HStack(spacing: 8) {
                    Button("生成并运行测试") { ctrl.scaffoldCustom(viewModel: viewModel) }
                        .buttonStyle(GlassPillButtonStyle(prominent: true))
                    Button("前往「MCP 接入」复制 Agent 提示词 →") { ctrl.activeTab = .mcp }
                        .buttonStyle(GlassPillButtonStyle())
                }
            }
            .padding(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
    }
}

import LumakeyCore
import SwiftUI

struct PluginConfigFormCard: View {
    let plugin: PluginDescriptor
    let fields: [PluginConfigField]
    @ObservedObject var ctrl: PluginCenterController
    let viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("参数配置 (密钥由系统钥匙串托管)").font(.caption.weight(.bold))
                Spacer()
                Button("保存配置") { ctrl.saveConfig(for: plugin, viewModel: viewModel) }
                    .buttonStyle(GlassPillButtonStyle(prominent: true))
            }
            ForEach(fields) { field in
                VStack(alignment: .leading, spacing: 4) {
                    if field.type != .boolean {
                        Text(field.label).font(.caption2.weight(.medium)).foregroundStyle(LiquidColors.textSecondary)
                    }
                    switch field.type {
                    case .text:
                        GlassInputField(symbol: "slider.horizontal.3", placeholder: field.placeholder ?? field.key, text: ctrl.binding(for: field))
                    case .secret:
                        SecureField(field.placeholder ?? "输入密钥参数", text: ctrl.binding(for: field))
                            .textFieldStyle(.plain).font(.caption)
                            .padding(.horizontal, 11).padding(.vertical, 7)
                            .background(LiquidColors.inputFieldSurface, in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
                    case .boolean:
                        HStack(spacing: 8) {
                            Text(field.label).font(.caption.weight(.medium)).foregroundStyle(LiquidColors.textPrimary)
                            Spacer()
                            Toggle("", isOn: ctrl.boolBinding(for: field)).toggleStyle(.switch).labelsHidden().controlSize(.small)
                        }
                        .padding(.vertical, 2)
                    case .select:
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 6)], spacing: 6) {
                            ForEach(field.options ?? [], id: \.self) { opt in
                                Button(opt) { ctrl.configDraft[field.key] = opt }
                                    .buttonStyle(GlassPillButtonStyle(prominent: (ctrl.configDraft[field.key] ?? field.defaultValue) == opt))
                            }
                        }
                    }
                }
            }
        }
        .padding(10)
        .liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)
    }
}

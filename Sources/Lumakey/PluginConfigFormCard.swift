import AppKit
import LumakeyCore
import SwiftUI

struct PluginConfigFormCard: View {
    let plugin: PluginDescriptor
    let fields: [PluginConfigField]
    @ObservedObject var ctrl: PluginCenterController
    let viewModel: AppViewModel
    @StateObject private var tagDrafts = PluginFieldTagInputState()

    private var groupedFields: [(section: String?, items: [PluginConfigField])] {
        var result: [(section: String?, items: [PluginConfigField])] = []
        for field in fields {
            let sec = plugin.manifest.localizedFieldSection(field)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = (sec?.isEmpty == true) ? nil : sec
            if let idx = result.firstIndex(where: { $0.section == normalized }) {
                result[idx].items.append(field)
            } else {
                result.append((normalized, [field]))
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(L10n.pick("参数配置", "Preferences"), systemImage: "slider.horizontal.3")
                    .font(.callout.weight(.semibold))
                Text(L10n.pick("改动即时生效 · 密钥加密托管", "Auto-saved · Secrets encrypted"))
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(LiquidColors.textSecondary)
                Spacer()
                if ctrl.hasUnsavedTextEdits {
                    Button(L10n.pick("应用修改", "Apply")) { ctrl.saveConfig(for: plugin, viewModel: viewModel) }
                        .buttonStyle(GlassPillButtonStyle(prominent: true, compact: true))
                } else {
                    Label(L10n.pick("已同步", "Synced"), systemImage: "checkmark.circle.fill")
                        .font(.caption2.weight(.semibold)).foregroundStyle(.mint)
                }
            }

            ForEach(Array(groupedFields.enumerated()), id: \.offset) { _, group in
                VStack(alignment: .leading, spacing: 8) {
                    if let sec = group.section {
                        Text(sec).font(.caption2.weight(.bold)).foregroundStyle(LiquidColors.accentPrimary).padding(.top, 2)
                    }
                    ForEach(group.items) { fieldRow($0) }
                }
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: LiquidRadii.bento, solidReadable: true)
        .onDisappear {
            if ctrl.hasUnsavedTextEdits {
                ctrl.saveConfig(for: plugin, viewModel: viewModel, silent: true)
            }
        }
    }

    @ViewBuilder
    private func fieldRow(_ field: PluginConfigField) -> some View {
        let labelText = plugin.manifest.localizedFieldLabel(field)
        VStack(alignment: .leading, spacing: 4) {
            if field.type != .boolean && field.control != .slider {
                HStack(spacing: 5) {
                    Text(labelText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(LiquidColors.textSecondary)
                    if field.required == true {
                        Text(L10n.pick("必填", "Required"))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.orange.opacity(0.14), in: Capsule())
                    }
                    if field.type == .secret {
                        let hasVal = !(ctrl.binding(for: field).wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Text(hasVal ? L10n.pick("加密已就绪", "Encrypted") : L10n.pick("待录入密钥", "Missing Secret"))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(hasVal ? .mint : .orange)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background((hasVal ? Color.mint : Color.orange).opacity(0.14), in: Capsule())
                    }
                    Spacer()
                }
            }
            controlBody(for: field, labelText: labelText)
            if let help = plugin.manifest.localizedFieldHelpText(field), !help.isEmpty {
                Text(help)
                    .font(.system(size: 10.5))
                    .foregroundStyle(LiquidColors.textSecondary.opacity(0.85))
            }
        }
    }

    @ViewBuilder
    private func controlBody(for field: PluginConfigField, labelText: String) -> some View {
        let ph = plugin.manifest.localizedFieldPlaceholder(field)
        switch field.type {
        case .text:
            GlassInputField(
                symbol: "character.cursor.ibeam",
                placeholder: ph ?? field.key,
                text: ctrl.autoSaveTextBinding(for: field, plugin: plugin, viewModel: viewModel)
            )
            .onSubmit { ctrl.saveConfig(for: plugin, viewModel: viewModel) }
        case .secret:
            HStack(spacing: 7) {
                Image(systemName: "key.fill").font(.caption).foregroundStyle(.mint)
                SecureField(
                    ph ?? L10n.pick("输入密钥参数（回车或切换即加密保存）", "Enter secret (saved automatically)"),
                    text: ctrl.autoSaveTextBinding(for: field, plugin: plugin, viewModel: viewModel)
                )
                .textFieldStyle(.plain).font(.caption)
                .onSubmit { ctrl.saveConfig(for: plugin, viewModel: viewModel) }
            }
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(LiquidColors.inputFieldSurface, in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous).strokeBorder(LiquidColors.inputFieldBorder, lineWidth: 0.8) }
        case .boolean:
            HStack(spacing: 8) {
                Text(labelText).font(.caption.weight(.medium)).foregroundStyle(LiquidColors.textPrimary)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { ctrl.boolBinding(for: field).wrappedValue },
                    set: { next in
                        ctrl.boolBinding(for: field).wrappedValue = next
                        ctrl.saveConfig(for: plugin, viewModel: viewModel, silent: true)
                    }
                ))
                .toggleStyle(.switch).labelsHidden().controlSize(.small)
            }
            .padding(.vertical, 2)
        case .select:
            FlowWrapLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(field.options ?? [], id: \.self) { opt in
                    Button(opt) {
                        ctrl.configDraft[field.key] = opt
                        ctrl.saveConfig(for: plugin, viewModel: viewModel, silent: true)
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: (ctrl.configDraft[field.key] ?? field.defaultValue) == opt))
                }
            }
        case .number:
            numberField(field, labelText: labelText, placeholder: ph)
        case .path:
            pathPickerField(field, placeholder: ph, chooseDirectories: false)
        case .directory:
            pathPickerField(field, placeholder: ph, chooseDirectories: true)
        case .tags:
            tagsEditor(field, placeholder: ph)
        }
    }

    @ViewBuilder
    private func numberField(_ field: PluginConfigField, labelText: String, placeholder: String?) -> some View {
        let strBinding = ctrl.autoSaveTextBinding(for: field, plugin: plugin, viewModel: viewModel)
        let currentNum = Double(strBinding.wrappedValue) ?? Double(field.defaultValue ?? "0") ?? 0
        let lo = field.minValue ?? -1_000_000
        let hi = field.maxValue ?? 1_000_000
        let step = field.stepValue ?? 1
        let isIntegerStep = step.truncatingRemainder(dividingBy: 1) == 0

        if field.control == .slider, let minV = field.minValue, let maxV = field.maxValue, minV < maxV {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(labelText).font(.caption.weight(.medium)).foregroundStyle(LiquidColors.textPrimary)
                    Spacer()
                    Text(isIntegerStep ? "\(Int(currentNum))" : String(format: "%.2f", currentNum))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(LiquidColors.textSecondary)
                }
                Slider(
                    value: Binding(
                        get: { min(max(currentNum, minV), maxV) },
                        set: { next in
                            ctrl.configDraft[field.key] = isIntegerStep ? String(Int(next.rounded())) : String(format: "%.2f", next)
                        }
                    ),
                    in: minV...maxV,
                    step: step,
                    onEditingChanged: { editing in
                        if !editing { ctrl.saveConfig(for: plugin, viewModel: viewModel, silent: true) }
                    }
                )
            }
        } else {
            HStack(spacing: 8) {
                GlassInputField(symbol: "number", placeholder: placeholder ?? L10n.pick("数值", "Number"), text: strBinding)
                    .onSubmit { ctrl.saveConfig(for: plugin, viewModel: viewModel, silent: true) }
                Stepper("", value: Binding(
                    get: { currentNum },
                    set: { next in
                        let clamped = min(max(next, lo), hi)
                        ctrl.configDraft[field.key] = isIntegerStep ? String(Int(clamped)) : String(format: "%.2f", clamped)
                        ctrl.saveConfig(for: plugin, viewModel: viewModel, silent: true)
                    }
                ), in: lo...hi, step: step)
                .labelsHidden()
                if field.minValue != nil || field.maxValue != nil {
                    Text("\(Int(lo))…\(Int(hi))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(LiquidColors.textSecondary)
                }
            }
        }
    }

    private func pathPickerField(_ field: PluginConfigField, placeholder: String?, chooseDirectories: Bool) -> some View {
        HStack(spacing: 6) {
            GlassInputField(
                symbol: chooseDirectories ? "folder" : "doc.text",
                placeholder: placeholder ?? (chooseDirectories ? L10n.pick("选择文件夹路径", "Choose folder") : L10n.pick("选择文件路径", "Choose file")),
                text: ctrl.autoSaveTextBinding(for: field, plugin: plugin, viewModel: viewModel)
            )
            .onSubmit { ctrl.saveConfig(for: plugin, viewModel: viewModel, silent: true) }
            Button(L10n.pick("选择…", "Browse…")) {
                let panel = NSOpenPanel()
                panel.canChooseFiles = !chooseDirectories
                panel.canChooseDirectories = chooseDirectories
                panel.allowsMultipleSelection = false
                panel.canCreateDirectories = true
                if panel.runModal() == .OK, let url = panel.url {
                    ctrl.configDraft[field.key] = url.path
                    ctrl.saveConfig(for: plugin, viewModel: viewModel, silent: true)
                }
            }
            .buttonStyle(GlassPillButtonStyle(compact: true))
        }
    }

    private func tagsEditor(_ field: PluginConfigField, placeholder: String?) -> some View {
        let raw = ctrl.binding(for: field).wrappedValue
        let tags = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let appendDraft = {
            let candidate = tagDrafts.text(for: field.key).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !candidate.isEmpty else { return }
            var updated = tags
            for part in candidate.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !part.isEmpty && !updated.contains(part) {
                updated.append(part)
            }
            ctrl.configDraft[field.key] = updated.joined(separator: ", ")
            tagDrafts.clear(field.key)
            ctrl.saveConfig(for: plugin, viewModel: viewModel, silent: true)
        }
        return VStack(alignment: .leading, spacing: 6) {
            if !tags.isEmpty {
                FlowWrapLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text(tag).font(.caption2.weight(.medium)).lineLimit(1)
                            Button {
                                ctrl.configDraft[field.key] = tags.filter { $0 != tag }.joined(separator: ", ")
                                ctrl.saveConfig(for: plugin, viewModel: viewModel, silent: true)
                            } label: {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 8.5).padding(.vertical, 3.5)
                        .background(LiquidColors.pillSurface, in: Capsule())
                        .overlay { Capsule().strokeBorder(LiquidColors.pillBorder, lineWidth: 0.7) }
                    }
                }
            }
            HStack(spacing: 6) {
                GlassInputField(
                    symbol: "tag",
                    placeholder: placeholder ?? L10n.pick("输入标签后回车或点添加", "Type tag & press Return"),
                    text: tagDrafts.binding(for: field.key)
                )
                .onSubmit(appendDraft)
                Button(L10n.pick("添加", "Add"), action: appendDraft)
                    .buttonStyle(GlassPillButtonStyle(compact: true))
            }
        }
    }
}

@MainActor
private final class PluginFieldTagInputState: ObservableObject {
    @Published var drafts: [String: String] = [:]

    func text(for key: String) -> String { drafts[key] ?? "" }
    func clear(_ key: String) { drafts[key] = "" }
    func binding(for key: String) -> Binding<String> {
        Binding(get: { self.drafts[key] ?? "" }, set: { self.drafts[key] = $0 })
    }
}

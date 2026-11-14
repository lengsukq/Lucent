import LumakeyCore
import SwiftUI

@MainActor
private final class PluginActionPromptState: ObservableObject {
    @Published var values: [String: String] = [:]
}

struct PluginActionPromptSheet: View {
    let action: PluginViewAction
    let onCancel: () -> Void
    let onSubmit: ([String]) -> Void

    @StateObject private var state = PluginActionPromptState()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(action.label).font(.headline)
                Spacer()
                Button("取消", action: onCancel)
                    .buttonStyle(GlassPillButtonStyle())
            }
            Divider().opacity(0.25)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(action.promptFields ?? []) { field in
                        fieldView(field)
                    }
                }
            }
            .frame(maxHeight: 320)

            HStack {
                Spacer()
                Button("确认执行") { submit() }
                    .buttonStyle(GlassPillButtonStyle(prominent: true))
                    .disabled(!canSubmit)
            }
        }
        .padding(16)
        .frame(width: 360)
        .onAppear {
            var initial: [String: String] = [:]
            for field in action.promptFields ?? [] {
                if let def = field.defaultValue { initial[field.key] = def }
            }
            state.values = initial
        }
    }

    @ViewBuilder
    private func fieldView(_ field: PluginActionPromptField) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(field.label + (field.required == true ? " *" : ""))
                .font(.caption.weight(.semibold))
                .foregroundStyle(LiquidColors.textSecondary)
            switch field.type ?? .text {
            case .boolean:
                Toggle("", isOn: Binding(
                    get: { (state.values[field.key] ?? field.defaultValue ?? "false").lowercased() == "true" },
                    set: { state.values[field.key] = $0 ? "true" : "false" }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            case .select:
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 6)], spacing: 6) {
                    ForEach(field.options ?? [], id: \.self) { opt in
                        let active = (state.values[field.key] ?? field.defaultValue) == opt
                        Button(opt) { state.values[field.key] = opt }
                            .buttonStyle(GlassPillButtonStyle(prominent: active))
                    }
                }
            case .text, .secret:
                GlassInputField(
                    symbol: "pencil",
                    placeholder: field.placeholder ?? field.key,
                    text: Binding(
                        get: { state.values[field.key] ?? field.defaultValue ?? "" },
                        set: { state.values[field.key] = $0 }
                    )
                )
            }
        }
    }

    private var canSubmit: Bool {
        for field in action.promptFields ?? [] where field.required == true {
            let v = (state.values[field.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if v.isEmpty { return false }
        }
        return true
    }

    private func submit() {
        let jsonData = (try? JSONSerialization.data(withJSONObject: state.values, options: [.sortedKeys])) ?? Data("{}".utf8)
        let jsonText = String(data: jsonData, encoding: .utf8) ?? "{}"
        onSubmit(action.commandArgs + ["--input-json", jsonText])
    }
}

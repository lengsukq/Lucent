import LumakeyCore
import SwiftUI

struct PluginViewActionButtons: View {
    let item: PluginViewItem
    let onRunCommandArgs: (([String]) -> Void)?
    let onRequestAction: (PluginViewAction) -> Void

    var body: some View {
        let actions = item.actions ?? []
        if !actions.isEmpty {
            ForEach(actions) { action in
                Button(action.label) {
                    onRequestAction(action)
                }
                .buttonStyle(GlassPillButtonStyle(prominent: action.style == .primary))
                .tint(action.style == .destructive ? .red : nil)
            }
        } else if let args = item.commandArgs, !args.isEmpty, onRunCommandArgs != nil {
            Button("执行") {
                onRunCommandArgs?(args)
            }
            .buttonStyle(GlassPillButtonStyle(prominent: true))
        }
    }
}

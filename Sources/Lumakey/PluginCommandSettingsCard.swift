import AppKit
import Carbon
import LumakeyCore
import SwiftUI

@MainActor
private final class LocalCommandHotKeyRecorder: ObservableObject {
    @Published var recordingCmdID: String?
    private var monitorToken: Any?

    func toggle(for spec: PluginCommandSpec, pluginID: String, viewModel: AppViewModel) {
        if recordingCmdID == spec.id { stop(); return }
        stop()
        recordingCmdID = spec.id
        monitorToken = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak viewModel] event in
            let code = Int(event.keyCode)
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let consumed = MainActor.assumeIsolated {
                guard let self else { return false }
                if HotKeyChord(keyCode: code, carbonModifiers: 0).isPureModifierKey { return true }
                if code == kVK_Escape && flags.isEmpty { self.stop(); return true }
                if (code == kVK_Delete || code == kVK_ForwardDelete) && flags.intersection([.command, .option, .control]).isEmpty {
                    self.stop()
                    try? PluginSystem.setPluginCommandHotKey(pluginID: pluginID, commandID: spec.id, hotKey: "")
                    viewModel?.reloadPluginsAndHotKeys()
                    return true
                }
                let chord = HotKeyChord(keyCode: code, modifierFlags: flags)
                guard chord.validationError == nil else { return true }
                self.stop()
                try? PluginSystem.setPluginCommandHotKey(pluginID: pluginID, commandID: spec.id, hotKey: chord.displayString)
                viewModel?.reloadPluginsAndHotKeys()
                return true
            }
            return consumed ? nil : event
        }
    }

    func stop() {
        if let monitorToken { NSEvent.removeMonitor(monitorToken); self.monitorToken = nil }
        recordingCmdID = nil
    }
}

struct PluginCommandSettingsCard: View {
    let plugin: PluginDescriptor
    @ObservedObject var viewModel: AppViewModel
    var settingsState: PluginDedicatedSettingsState? = nil
    @StateObject private var localRecorder = LocalCommandHotKeyRecorder()

    private var commands: [PluginCommandSpec] { plugin.declaredCommands }

    private var enabledQuickButtonCount: Int {
        let enabledSet = Set(plugin.overrides.quickButtonCommandIDs)
        return commands.filter { enabledSet.contains($0.id) }.count + (plugin.pinnedInOverlay ? 1 : 0)
    }

    var body: some View {
        if !commands.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Label(
                        L10n.pick("子功能 · 全局搜索、热键、快捷按钮与菜单栏", "Commands · Search, Hotkeys, Quick Buttons & Menu Bar"),
                        systemImage: "bolt.horizontal.circle.fill"
                    )
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    Spacer()
                    if enabledQuickButtonCount > 0 {
                        Button(L10n.pick("关闭快捷按钮 (\(enabledQuickButtonCount))", "Clear Quick Buttons (\(enabledQuickButtonCount))")) {
                            viewModel.clearAllQuickButtons(for: plugin)
                        }
                        .buttonStyle(GlassPillButtonStyle(compact: true))
                    } else {
                        Text(L10n.pick("共 \(commands.count) 项", "\(commands.count) commands"))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(LiquidColors.textSecondary)
                            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    }
                }

                Text(L10n.pick(
                    "每项子功能可独立决定是否接入 ⌥Space 全局搜索、单独录制全局热键（⌫ 清空）、挂载浮窗快捷按钮或挂载至顶部状态栏菜单。",
                    "Each command can join Global Search, bind a global hotkey, mount as a Quick Button, or appear in the status bar menu."
                ))
                .font(.caption2)
                .foregroundStyle(LiquidColors.textSecondary)

                VStack(spacing: 7) {
                    ForEach(commands) { spec in
                        commandRow(spec)
                    }
                }
            }
            .padding(14)
            .liquidGlassCard(cornerRadius: LiquidRadii.bento, solidReadable: true)
            .onDisappear { localRecorder.stop() }
        }
    }

    private func commandRow(_ spec: PluginCommandSpec) -> some View {
        let isQuickOn = plugin.overrides.quickButtonCommandIDs.contains(spec.id)
        let isMenuOn = plugin.overrides.menuBarCommandIDs.contains(spec.id)
        let isSearchOn = plugin.isCommandSearchEnabled(spec)
        let cmdTitle = plugin.manifest.localizedCommandTitle(spec)
        let cmdSub = plugin.manifest.localizedCommandSubtitle(spec)
        let cmdHK = plugin.effectiveCommandHotKey(for: spec.id)
        let isRecording = (settingsState?.recordingCommandID == spec.id) || (localRecorder.recordingCmdID == spec.id)
        let customIcon = PluginIconResolver.resolveBundleIconURL(rawIcon: spec.icon, in: plugin.directoryURL) ?? plugin.customIconURL
        let sym = (spec.icon?.isEmpty == false && !PluginIconResolver.looksLikeRelativeFilePath(spec.icon))
            ? (spec.icon ?? plugin.symbolIconName)
            : plugin.symbolIconName

        return HStack(alignment: .center, spacing: 10) {
            PluginIconBadge(
                symbol: sym, customIconURL: customIcon,
                accentColor: isQuickOn ? "orange" : plugin.manifest.accentColor,
                isBuiltin: plugin.isBuiltin, mode: plugin.manifest.mode, size: 32
            )
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(cmdTitle)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(LiquidColors.textPrimary)
                        .lineLimit(1)
                        .layoutPriority(1)
                    if spec.includeInGlobalSearch == false && plugin.overrides.commandSearchOverrides[spec.id] == nil {
                        Text(L10n.pick("默认域内", "Scoped"))
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidColors.textSecondary)
                            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 5.5).padding(.vertical, 1.5)
                            .background(LiquidColors.pillSurface, in: Capsule())
                    }
                    ForEach(spec.keywords.prefix(2), id: \.self) { kw in
                        Text(kw)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(LiquidColors.accentPrimary)
                            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 6).padding(.vertical, 1.5)
                            .background(LiquidColors.pillSurface, in: Capsule())
                    }
                }
                Text(cmdSub)
                    .font(.caption2)
                    .foregroundStyle(LiquidColors.textSecondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 130, maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                commandHotKeyButton(spec: spec, currentHotKey: cmdHK, isRecording: isRecording)

                Toggle(L10n.pick("搜索", "Search"), isOn: Binding(
                    get: { isSearchOn },
                    set: { viewModel.setPluginCommandSearchEnabled(pluginID: plugin.id, commandID: spec.id, title: cmdTitle, enabled: $0) }
                ))
                .font(.caption2).fixedSize(horizontal: true, vertical: false)

                Toggle(L10n.pick("快捷按钮", "Quick"), isOn: Binding(
                    get: { isQuickOn },
                    set: { viewModel.setPluginCommandQuickButton(pluginID: plugin.id, commandID: spec.id, title: cmdTitle, enabled: $0) }
                ))
                .font(.caption2.weight(.semibold)).fixedSize(horizontal: true, vertical: false).tint(.orange)

                Toggle(L10n.pick("菜单栏", "Menu"), isOn: Binding(
                    get: { isMenuOn },
                    set: { viewModel.setPluginCommandMenuBar(pluginID: plugin.id, commandID: spec.id, title: cmdTitle, enabled: $0) }
                ))
                .font(.caption2.weight(.semibold)).fixedSize(horizontal: true, vertical: false).tint(.cyan)

                Button(L10n.pick("运行", "Run")) {
                    viewModel.runPlugin(plugin, query: "", arguments: spec.arguments, showInline: false)
                }
                .buttonStyle(GlassPillButtonStyle(compact: true))
                .disabled(!plugin.isBuiltin && (!plugin.isEnabled || !plugin.isValid))
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(
            isQuickOn ? Color.orange.opacity(0.08) : LiquidColors.pillSurface.opacity(0.55),
            in: RoundedRectangle(cornerRadius: LiquidRadii.row, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: LiquidRadii.row, style: .continuous)
                .strokeBorder(isQuickOn ? Color.orange.opacity(0.35) : LiquidColors.pillBorder, lineWidth: 0.75)
        }
    }

    private func commandHotKeyButton(spec: PluginCommandSpec, currentHotKey: String?, isRecording: Bool) -> some View {
        let label = isRecording ? L10n.pick("按键…", "Press…") : (currentHotKey ?? L10n.pick("绑热键", "Hotkey"))
        return Button {
            if let settingsState {
                settingsState.toggleCommandHotKeyRecording(command: spec, plugin: plugin, viewModel: viewModel)
            } else {
                localRecorder.toggle(for: spec, pluginID: plugin.id, viewModel: viewModel)
            }
        } label: {
            Text(label)
                .font(.system(size: 10.5, weight: .bold, design: isRecording ? .rounded : .monospaced))
                .foregroundStyle(isRecording ? .white : (currentHotKey != nil ? .cyan : LiquidColors.textSecondary))
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 8.5).padding(.vertical, 4)
                .background(
                    isRecording
                        ? AnyShapeStyle(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                        : AnyShapeStyle(LiquidColors.pillSurface),
                    in: Capsule()
                )
                .overlay { Capsule().strokeBorder(LiquidColors.pillBorder, lineWidth: 0.75) }
        }
        .buttonStyle(.plain)
        .help(L10n.pick("点击录制该子功能专属全局快捷键（按 ⌫ 清空）", "Click to record command hotkey (⌫ to clear)"))
    }
}

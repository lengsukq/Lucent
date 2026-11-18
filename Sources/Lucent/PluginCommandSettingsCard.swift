import AppKit
import Carbon
import LucentCore
import SwiftUI

@MainActor
private final class LocalCommandHotKeyRecorder: ObservableObject {
    @Published var recordingCmdID: String?
    private var monitorToken: Any?

    func toggle(for spec: PluginCommandSpec, plugin: PluginDescriptor, viewModel: AppViewModel) {
        if recordingCmdID == spec.id {
            stop()
            viewModel.presentHotKeyBanner(
                tone: .neutral,
                message: L10n.pick("已取消热键录制", "Hotkey recording canceled"),
                autoDismissSeconds: 1.8
            )
            return
        }
        stop()
        recordingCmdID = spec.id
        let cmdTitle = plugin.manifest.localizedCommandTitle(spec)
        let prompt = L10n.pick(
            "正在录制子功能「\(cmdTitle)」全局热键 · 请按下组合键（需含 ⌘/⌥/⌃），按 ⌫ 清空，Esc 取消",
            "Recording hotkey for \"\(cmdTitle)\" · Press shortcut, ⌫ to clear, Esc to cancel"
        )
        viewModel.presentHotKeyBanner(tone: .recording, message: prompt) { [weak self, weak viewModel] in
            self?.stop()
            viewModel?.presentHotKeyBanner(
                tone: .neutral,
                message: L10n.pick("已取消热键录制", "Hotkey recording canceled"),
                autoDismissSeconds: 1.8
            )
        }
        monitorToken = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak viewModel] event in
            let code = Int(event.keyCode)
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let consumed = MainActor.assumeIsolated {
                guard let self, let viewModel else { return false }
                if HotKeyChord(keyCode: code, carbonModifiers: 0).isPureModifierKey { return true }
                if code == kVK_Escape && flags.isEmpty {
                    self.stop()
                    viewModel.presentHotKeyBanner(
                        tone: .neutral,
                        message: L10n.pick("已取消热键录制", "Hotkey recording canceled"),
                        autoDismissSeconds: 1.8
                    )
                    return true
                }
                if (code == kVK_Delete || code == kVK_ForwardDelete) && flags.intersection([.command, .option, .control]).isEmpty {
                    self.stop()
                    try? PluginSystem.setPluginCommandHotKey(pluginID: plugin.id, commandID: spec.id, hotKey: "")
                    viewModel.reloadPluginsAndHotKeys()
                    viewModel.presentHotKeyBanner(
                        tone: .success,
                        message: L10n.pick("已清空「\(cmdTitle)」热键", "Cleared hotkey"),
                        autoDismissSeconds: 2.0
                    )
                    return true
                }
                let chord = HotKeyChord(keyCode: code, modifierFlags: flags)
                if let err = chord.validationError {
                    viewModel.presentHotKeyBanner(tone: .error, message: err) { [weak self, weak viewModel] in
                        self?.stop()
                        viewModel?.presentHotKeyBanner(
                            tone: .neutral,
                            message: L10n.pick("已取消热键录制", "Hotkey recording canceled"),
                            autoDismissSeconds: 1.8
                        )
                    }
                    return true
                }
                self.stop()
                try? PluginSystem.setPluginCommandHotKey(pluginID: plugin.id, commandID: spec.id, hotKey: chord.displayString)
                viewModel.reloadPluginsAndHotKeys()
                viewModel.presentHotKeyBanner(
                    tone: .success,
                    message: L10n.pick("已绑定「\(cmdTitle)」: \(chord.displayString)", "Bound \"\(cmdTitle)\": \(chord.displayString)"),
                    autoDismissSeconds: 2.4
                )
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
                    "「混入搜索」= 在 ⌥Space 直接搜到 ·「快捷按钮」= 固定在快捷台首页 ·「菜单栏」= 放进顶部状态栏菜单 ·「绑热键」= 全局快捷键（按 ⌫ 清空）",
                    "Search = appear in ⌥Space · Quick = pin on Home · Menu = add to status menu · Hotkey = global shortcut (⌫ to clear)"
                ))
                .font(.caption2)
                .foregroundStyle(LiquidColors.textSecondary)

                VStack(spacing: 8) {
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
        let isWindowCmd = spec.arguments.contains("--custom-hud") || spec.arguments.contains("--float-panel")
        let runLabel = isWindowCmd ? L10n.pick("打开浮窗", "Open") : L10n.pick("运行", "Run")

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                PluginIconBadge(
                    symbol: sym, customIconURL: customIcon,
                    accentColor: isQuickOn ? "orange" : plugin.manifest.accentColor,
                    isBuiltin: plugin.isBuiltin, mode: plugin.manifest.mode, size: 32
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(cmdTitle)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(LiquidColors.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(cmdSub)
                        .font(.caption2)
                        .foregroundStyle(LiquidColors.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    commandHotKeyButton(spec: spec, currentHotKey: cmdHK, isRecording: isRecording)
                    Button(runLabel) {
                        viewModel.runPlugin(plugin, query: "", arguments: spec.arguments, showInline: !isWindowCmd)
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: isWindowCmd, compact: true))
                    .disabled(!plugin.isBuiltin && (!plugin.isEnabled || !plugin.isValid))
                }
                .fixedSize(horizontal: true, vertical: false)
            }

            HStack(spacing: 10) {
                if !spec.keywords.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(spec.keywords.prefix(2), id: \.self) { kw in
                            Text(kw)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(LiquidColors.accentPrimary)
                                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(LiquidColors.pillSurface, in: Capsule())
                        }
                    }
                }
                Spacer(minLength: 4)
                Toggle(L10n.pick("混入搜索", "Search"), isOn: Binding(
                    get: { isSearchOn },
                    set: { viewModel.setPluginCommandSearchEnabled(pluginID: plugin.id, commandID: spec.id, title: cmdTitle, enabled: $0) }
                ))
                .font(.caption2).fixedSize(horizontal: true, vertical: false)
                .help(L10n.pick("允许在 ⌥Space 搜索框直接检索此功能", "Show this command in ⌥Space search results"))

                Toggle(L10n.pick("首页快捷按钮", "Quick Btn"), isOn: Binding(
                    get: { isQuickOn },
                    set: { viewModel.setPluginCommandQuickButton(pluginID: plugin.id, commandID: spec.id, title: cmdTitle, enabled: $0) }
                ))
                .font(.caption2.weight(.medium)).fixedSize(horizontal: true, vertical: false).tint(.orange)
                .help(L10n.pick("固定为 ⌥Space 首页快捷按钮", "Pin as a Quick Button on ⌥Space Home"))

                Toggle(L10n.pick("菜单栏", "Menu"), isOn: Binding(
                    get: { isMenuOn },
                    set: { viewModel.setPluginCommandMenuBar(pluginID: plugin.id, commandID: spec.id, title: cmdTitle, enabled: $0) }
                ))
                .font(.caption2.weight(.medium)).fixedSize(horizontal: true, vertical: false).tint(.cyan)
                .help(L10n.pick("添加到屏幕顶部状态栏菜单", "Add to macOS status bar menu"))
            }
            .padding(.leading, 42)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
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
                localRecorder.toggle(for: spec, plugin: plugin, viewModel: viewModel)
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

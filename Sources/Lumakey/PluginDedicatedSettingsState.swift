import AppKit
import Carbon
import Foundation
import LumakeyCore
import SwiftUI

@MainActor
final class PluginDedicatedSettingsState: ObservableObject {
    @Published var keywordDraft: String = ""
    @Published var isRecordingHotKey: Bool = false
    @Published var recordingCommandID: String? = nil
    @Published var showDeveloperDiagnostics: Bool = false
    @Published var dataStatus: PluginDataStatus?
    @Published var bannerMessage: String?

    private var boundPluginID: String?
    private var keyMonitor: Any?

    func bindIfNeeded(plugin: PluginDescriptor, ctrl: PluginCenterController) {
        if boundPluginID != plugin.id {
            stopRecordingHotKey()
            boundPluginID = plugin.id
            keywordDraft = ""
            bannerMessage = nil
            ctrl.select(plugin)
        }
        refreshDataStatus(for: plugin)
    }

    func refreshDataStatus(for plugin: PluginDescriptor) {
        dataStatus = PluginDataInspector.inspect(plugin)
    }

    func stopRecordingHotKey() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        isRecordingHotKey = false
        recordingCommandID = nil
    }

    func toggleHotKeyRecording(for plugin: PluginDescriptor, viewModel: AppViewModel) {
        if isRecordingHotKey && recordingCommandID == nil {
            stopRecordingHotKey()
            viewModel.presentHotKeyBanner(
                tone: .neutral,
                message: L10n.pick("已取消热键录制", "Hotkey recording canceled"),
                autoDismissSeconds: 1.8
            )
            return
        }
        stopRecordingHotKey()
        isRecordingHotKey = true
        recordingCommandID = nil
        let prompt = L10n.pick(
            "正在录制「\(plugin.displayName)」全局热键 · 请按下组合键（需含 ⌘/⌥/⌃），按 ⌫ 清空，Esc 取消",
            "Recording hotkey for \"\(plugin.displayName)\" · Press shortcut, ⌫ to clear, Esc to cancel"
        )
        viewModel.presentHotKeyBanner(tone: .recording, message: prompt) { [weak self, weak viewModel] in
            self?.stopRecordingHotKey()
            viewModel?.presentHotKeyBanner(
                tone: .neutral,
                message: L10n.pick("已取消热键录制", "Hotkey recording canceled"),
                autoDismissSeconds: 1.8
            )
        }
        installKeyMonitor(plugin: plugin, viewModel: viewModel)
    }

    func toggleCommandHotKeyRecording(command: PluginCommandSpec, plugin: PluginDescriptor, viewModel: AppViewModel) {
        if recordingCommandID == command.id {
            stopRecordingHotKey()
            viewModel.presentHotKeyBanner(
                tone: .neutral,
                message: L10n.pick("已取消热键录制", "Hotkey recording canceled"),
                autoDismissSeconds: 1.8
            )
            return
        }
        stopRecordingHotKey()
        recordingCommandID = command.id
        let cmdTitle = plugin.manifest.localizedCommandTitle(command)
        let prompt = L10n.pick(
            "正在录制子功能「\(cmdTitle)」全局热键 · 请按下组合键（需含 ⌘/⌥/⌃），按 ⌫ 清空，Esc 取消",
            "Recording hotkey for \"\(cmdTitle)\" · Press shortcut, ⌫ to clear, Esc to cancel"
        )
        viewModel.presentHotKeyBanner(tone: .recording, message: prompt) { [weak self, weak viewModel] in
            self?.stopRecordingHotKey()
            viewModel?.presentHotKeyBanner(
                tone: .neutral,
                message: L10n.pick("已取消热键录制", "Hotkey recording canceled"),
                autoDismissSeconds: 1.8
            )
        }
        installKeyMonitor(plugin: plugin, viewModel: viewModel)
    }

    private func installKeyMonitor(plugin: PluginDescriptor, viewModel: AppViewModel) {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak viewModel] event in
            let code = Int(event.keyCode)
            let rawFlags = event.modifierFlags
            let consumed = MainActor.assumeIsolated {
                guard let self, let viewModel else { return false }
                return self.handleHotKeyEvent(code: code, rawFlags: rawFlags, plugin: plugin, viewModel: viewModel)
            }
            return consumed ? nil : event
        }
    }

    private func handleHotKeyEvent(
        code: Int,
        rawFlags: NSEvent.ModifierFlags,
        plugin: PluginDescriptor,
        viewModel: AppViewModel
    ) -> Bool {
        guard isRecordingHotKey || recordingCommandID != nil else { return false }
        if HotKeyChord(keyCode: code, carbonModifiers: 0).isPureModifierKey { return true }
        let flags = rawFlags.intersection([.command, .option, .control, .shift])
        if code == kVK_Escape && flags.isEmpty {
            stopRecordingHotKey()
            viewModel.presentHotKeyBanner(
                tone: .neutral,
                message: L10n.pick("已取消热键录制", "Hotkey recording canceled"),
                autoDismissSeconds: 1.8
            )
            return true
        }
        let targetCmdID = recordingCommandID
        if (code == kVK_Delete || code == kVK_ForwardDelete) && flags.intersection([.command, .option, .control]).isEmpty {
            stopRecordingHotKey()
            if let cmdID = targetCmdID {
                clearCommandHotKey(commandID: cmdID, for: plugin, viewModel: viewModel)
            } else {
                clearHotKey(for: plugin, viewModel: viewModel)
            }
            return true
        }
        let chord = HotKeyChord(keyCode: code, modifierFlags: flags)
        if let err = chord.validationError {
            viewModel.presentHotKeyBanner(tone: .error, message: err) { [weak self, weak viewModel] in
                self?.stopRecordingHotKey()
                viewModel?.presentHotKeyBanner(
                    tone: .neutral,
                    message: L10n.pick("已取消热键录制", "Hotkey recording canceled"),
                    autoDismissSeconds: 1.8
                )
            }
            return true
        }
        stopRecordingHotKey()
        if let cmdID = targetCmdID {
            try? PluginSystem.setPluginCommandHotKey(pluginID: plugin.id, commandID: cmdID, hotKey: chord.displayString)
            viewModel.reloadPluginsAndHotKeys()
            let msg = L10n.pick("已绑定子功能热键：\(chord.displayString)", "Bound command hotkey: \(chord.displayString)")
            viewModel.presentHotKeyBanner(tone: .success, message: msg, autoDismissSeconds: 2.4)
        } else {
            mutateOverrides(for: plugin, viewModel: viewModel, note: "已绑定全局热键：\(chord.displayString)") {
                $0.customHotKey = chord.displayString
            }
            viewModel.presentHotKeyBanner(
                tone: .success,
                message: L10n.pick("已绑定全局热键：\(chord.displayString)", "Bound hotkey: \(chord.displayString)"),
                autoDismissSeconds: 2.4
            )
        }
        return true
    }

    func clearCommandHotKey(commandID: String, for plugin: PluginDescriptor, viewModel: AppViewModel) {
        try? PluginSystem.setPluginCommandHotKey(pluginID: plugin.id, commandID: commandID, hotKey: "")
        viewModel.reloadPluginsAndHotKeys()
        let msg = L10n.pick("已清空该子功能的全局热键", "Cleared command hotkey")
        viewModel.presentHotKeyBanner(tone: .success, message: msg, autoDismissSeconds: 2.0)
    }

    func clearHotKey(for plugin: PluginDescriptor, viewModel: AppViewModel) {
        mutateOverrides(for: plugin, viewModel: viewModel, note: "已清空该插件的全局热键") {
            $0.customHotKey = ""
        }
        viewModel.presentHotKeyBanner(
            tone: .success,
            message: L10n.pick("已清空该插件的全局热键", "Cleared plugin hotkey"),
            autoDismissSeconds: 2.0
        )
    }

    func restoreDefaultHotKey(for plugin: PluginDescriptor, viewModel: AppViewModel) {
        mutateOverrides(for: plugin, viewModel: viewModel, note: "已恢复清单默认热键设置") {
            $0.customHotKey = nil
        }
    }

    func addKeyword(for plugin: PluginDescriptor, viewModel: AppViewModel) {
        let parts = keywordDraft
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return }
        var current = plugin.effectiveKeywords
        for kw in parts where !current.contains(where: { $0.caseInsensitiveCompare(kw) == .orderedSame }) {
            current.append(kw)
        }
        keywordDraft = ""
        mutateOverrides(for: plugin, viewModel: viewModel, note: "已更新触发词：\(current.joined(separator: ", "))") {
            $0.customKeywords = current
        }
    }

    func removeKeyword(_ target: String, for plugin: PluginDescriptor, viewModel: AppViewModel) {
        let remaining = plugin.effectiveKeywords.filter { $0 != target }
        guard !remaining.isEmpty else {
            bannerMessage = "至少保留一个触发词；如需恢复默认请点击「恢复默认触发词」"
            return
        }
        mutateOverrides(for: plugin, viewModel: viewModel, note: "已移除触发词 '\(target)'") {
            $0.customKeywords = remaining
        }
    }

    func restoreDefaultKeywords(for plugin: PluginDescriptor, viewModel: AppViewModel) {
        mutateOverrides(for: plugin, viewModel: viewModel, note: "已恢复默认触发词：\(plugin.manifest.keywords.joined(separator: ", "))") {
            $0.customKeywords = nil
        }
    }

    func mutateOverrides(
        for plugin: PluginDescriptor,
        viewModel: AppViewModel,
        note: String? = nil,
        _ mutate: (inout PluginUserOverrides) -> Void
    ) {
        do {
            try PluginSystem.updatePluginOverrides(id: plugin.id, mutate)
            viewModel.reloadPluginsAndHotKeys()
            if let refreshed = viewModel.plugins.first(where: { $0.id == plugin.id }) {
                refreshDataStatus(for: refreshed)
            }
            if let note {
                bannerMessage = note
                viewModel.serviceMessage = note
            }
        } catch {
            bannerMessage = error.localizedDescription
        }
    }

    func resetAllOverrides(for plugin: PluginDescriptor, viewModel: AppViewModel) {
        do {
            try PluginSystem.resetPluginOverrides(id: plugin.id)
            viewModel.reloadPluginsAndHotKeys()
            bannerMessage = "已重置「\(plugin.displayName)」全部个性化覆盖项"
            viewModel.serviceMessage = bannerMessage
        } catch {
            bannerMessage = error.localizedDescription
        }
    }

    func syncSearchIndexNow(for plugin: PluginDescriptor, ctrl: PluginCenterController, viewModel: AppViewModel) {
        ctrl.runAsync(plugin, arguments: ["--sync"], viewModel: viewModel)
        Task { @MainActor [weak self, weak viewModel] in
            try? await Task.sleep(for: .milliseconds(600))
            guard let self, let viewModel else { return }
            viewModel.reloadPluginSearchIndex()
            viewModel.reloadPlugins()
            if let latest = viewModel.plugins.first(where: { $0.id == plugin.id }) {
                self.refreshDataStatus(for: latest)
            }
        }
    }

    func clearCache(for plugin: PluginDescriptor, preserveIndex: Bool, viewModel: AppViewModel) {
        PluginDataInspector.clearPluginData(for: plugin.id, preserveSearchIndex: preserveIndex)
        viewModel.reloadPluginSearchIndex()
        viewModel.reloadPlugins()
        refreshDataStatus(for: plugin)
        let msg = preserveIndex ? "已清理运行缓存（保留免前缀索引）" : "已清空插件全部数据与检索索引"
        bannerMessage = msg
        viewModel.serviceMessage = msg
    }
}

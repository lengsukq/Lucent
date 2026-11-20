import Foundation
import PluginKit

let input = PluginInput.read()
let title = input.isEnglish ? "Audio Presets" : "一键音频组合"

func localized(_ chinese: String, _ english: String) -> String { input.isEnglish ? english : chinese }

func openPanel(message: String? = nil, preset: UUID? = nil) {
    var state: [String: String] = [:]
    state["message"] = message
    state["presetID"] = preset?.uuidString
    let json = (try? PluginOutput.encodeJSON(state)).flatMap { String(data: $0, encoding: .utf8) }
    let spec = WindowLaunchSpec(windowID: "main", initialStateJSON: json)
    PluginOutput.emit(ViewPayload(title: title, effect: PostActionEffect(closeOverlay: true, openWindow: spec)))
}

func emitDocument(_ document: AudioPresetDocument) throws {
    let encoded = try PluginOutput.encodeJSON(document)
    var raw = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] ?? [:]
    raw["title"] = title
    raw["effect"] = ["reloadSearchIndex": true]
    PluginOutput.emitJSONObject(raw)
}

func apply(_ preset: AudioPreset) {
    let response = HostBridgeClient(input: input).call(
        capability: "audioDevices", action: "apply",
        params: ["inputUID": preset.inputUID, "outputUID": preset.outputUID, "showFeedback": true]
    )
    if response.ok && response.string("status") == "applied" {
        PluginOutput.emit(ViewPayload(title: title, effect: PostActionEffect(closeOverlay: true)))
        return
    }
    let message: String
    switch response.string("status") {
    case "unavailable":
        let missing = response.data["missing"] as? [String] ?? []
        let devices = missing.map { $0 == "input" ? preset.inputName : preset.outputName }.joined(separator: " · ")
        message = localized("未连接：\(devices)", "Disconnected: \(devices)")
    case "restored":
        message = localized("切换失败，已恢复之前的设备。", "Switch failed. The previous devices were restored.")
    case "partial":
        message = localized("未能完全恢复，请核对当前设备。", "Couldn’t fully restore audio. Check the current devices.")
    default:
        message = localized("请检查音频设备授权后重试。", "Check audio device access and try again.")
    }
    openPanel(message: message, preset: preset.id)
}

do {
    let command = input.arguments.first
    if command == nil || command == "--open" {
        openPanel()
    } else {
        let store = try AudioPresetStore(dataDirectory: input.dataDir)
        let argument = input.arguments.dropFirst().first
        switch command {
        case "--list", "--sync":
            try emitDocument(store.update())
        case "--save":
            let preset = try JSONDecoder().decode(AudioPreset.self, from: Data(input.query.utf8))
            guard preset.isValid else { throw CocoaError(.fileReadCorruptFile) }
            try emitDocument(store.update { state in
                if let existing = state.presets.firstIndex(where: { $0.id == preset.id }) {
                    state.presets[existing] = preset
                } else {
                    state.presets.append(preset)
                }
            })
        case "--delete", "--set-favorite":
            guard let argument, let id = UUID(uuidString: argument) else { throw CocoaError(.fileReadCorruptFile) }
            try emitDocument(store.update { state in
                guard state.presets.contains(where: { $0.id == id }) else { return }
                if command == "--delete" {
                    state.presets.removeAll { $0.id == id }
                    if state.favorite == id { state.favorite = nil }
                } else {
                    state.favorite = state.favorite == id ? nil : id
                }
            })
        case "--apply", "--favorite":
            let state = try store.update()
            let id = command == "--favorite" ? state.favorite : argument.flatMap(UUID.init(uuidString:))
            if let preset = state.presets.first(where: { $0.id == id }) {
                apply(preset)
            } else {
                openPanel(message: command == "--favorite"
                    ? localized("请先把一套组合设为常用。", "Mark a preset as your favorite first.")
                    : localized("这套组合已移除。", "This preset was removed."))
            }
        default:
            throw CocoaError(.featureUnsupported)
        }
    }
} catch {
    let message = localized("无法读取或保存组合，请检查磁盘与访问权限。", "Couldn’t read or save presets. Check storage and access.")
    let isQuickAction = ["--apply", "--favorite"].contains(input.arguments.first ?? "")
    if isQuickAction { openPanel(message: message) }
    else { PluginOutput.emitJSONObject(["title": title, "error": message]) }
}

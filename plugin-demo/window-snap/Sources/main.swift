import Foundation
import PluginKit

let input = PluginInput.read()
let pluginTitle = input.pick("窗口分屏与工作区", "Window Snap & Workspaces")

func openConsole(message: String? = nil, workspaceID: UUID? = nil, openCapture: Bool = false) {
    var state: [String: Any] = [:]
    if let message, !message.isEmpty { state["message"] = message }
    if let workspaceID { state["workspaceID"] = workspaceID.uuidString }
    if openCapture { state["openCapture"] = true }
    let json = (try? JSONSerialization.data(withJSONObject: state)).flatMap { String(data: $0, encoding: .utf8) }
    let spec = WindowLaunchSpec(windowID: "main", initialStateJSON: json, reuseIfOpen: true)
    PluginOutput.emit(ViewPayload(
        title: pluginTitle,
        effect: PostActionEffect(closeOverlay: true, openWindow: spec)
    ))
}

func emitDocument(_ document: WindowSnapDocument) throws {
    let encoded = try PluginOutput.encodeJSON(document)
    var raw = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] ?? [:]
    raw["title"] = pluginTitle
    raw["configGap"] = effectiveGap(from: document)
    raw["configLaunchMissing"] = effectiveLaunchMissing(from: document)
    raw["configShowHud"] = input.cfgBool("showHudFeedback", default: true)
    raw["effect"] = ["reloadSearchIndex": true]
    PluginOutput.emitJSONObject(raw)
}

func effectiveGap(from doc: WindowSnapDocument?) -> Int {
    if let prefGap = doc?.preferences.gap { return max(0, min(24, prefGap)) }
    return input.cfgInt("windowGap", default: 8, min: 0, max: 24)
}

func effectiveLaunchMissing(from doc: WindowSnapDocument?) -> Bool {
    if let pref = doc?.preferences.launchMissingApps { return pref }
    return input.cfgBool("launchMissingApps", default: true)
}

func runSnap(preset: String, doc: WindowSnapDocument?) {
    let gap = effectiveGap(from: doc)
    let showFeedback = input.cfgBool("showHudFeedback", default: true)
    let response = HostBridgeClient(input: input, timeoutSeconds: 5).call(
        capability: "windowControl",
        action: "snap",
        params: [
            "preset": preset,
            "gap": gap,
            "showFeedback": showFeedback
        ]
    )
    if response.ok {
        let status = response.string("status")
        if status == "applied" {
            PluginOutput.emit(ViewPayload(
                title: pluginTitle,
                effect: PostActionEffect(closeOverlay: true)
            ))
            return
        }
        let msg = response.string("message", default: input.pick("未找到可调整的前台窗口", "No active window to snap"))
        PluginOutput.emit(ViewPayload(
            title: pluginTitle,
            effect: PostActionEffect(toast: msg, closeOverlay: true)
        ))
        return
    }
    if response.error == "tcc_not_granted" || response.error == "capability_not_granted" {
        let msg = input.pick(
            "请先授权窗口控制与系统「辅助功能」权限。",
            "Grant window control and macOS Accessibility permission first."
        )
        openConsole(message: msg)
        return
    }
    let fallback = response.message ?? input.pick("窗口分屏失败，请重试。", "Couldn’t snap window. Please try again.")
    openConsole(message: fallback)
}

func applyWorkspace(_ preset: WindowWorkspacePreset, doc: WindowSnapDocument) {
    let gap = effectiveGap(from: doc)
    let launchMissing = effectiveLaunchMissing(from: doc)
    let showFeedback = input.cfgBool("showHudFeedback", default: true)
    let response = HostBridgeClient(input: input, timeoutSeconds: 8).call(
        capability: "windowControl",
        action: "applyWorkspace",
        params: [
            "name": preset.name,
            "slots": preset.slots.map { $0.toBridgeDictionary() },
            "gap": gap,
            "launchMissing": launchMissing,
            "showFeedback": showFeedback
        ]
    )
    if response.ok {
        let status = response.string("status")
        let moved = response.int("movedCount")
        let missing = response.data["missingApps"] as? [String] ?? []
        let usedFallback = response.bool("usedFallbackDisplay")
        if status == "applied" && !usedFallback {
            PluginOutput.emit(ViewPayload(
                title: pluginTitle,
                effect: PostActionEffect(closeOverlay: true)
            ))
            return
        }
        if moved > 0 {
            var notes: [String] = []
            if usedFallback {
                notes.append(input.pick("部分外接屏已断开，已自动归入当前屏幕", "Disconnected displays folded onto active screen"))
            }
            if !missing.isEmpty {
                let apps = missing.prefix(3).joined(separator: "、")
                notes.append(input.pick("未找到：\(apps)", "Skipped: \(apps)"))
            }
            let toast = notes.isEmpty
                ? input.pick("已排列 \(moved) 个窗口", "Arranged \(moved) window(s)")
                : notes.joined(separator: " · ")
            PluginOutput.emit(ViewPayload(
                title: pluginTitle,
                effect: PostActionEffect(toast: toast, closeOverlay: true)
            ))
            return
        }
        let emptyMsg = input.pick(
            "工作区「\(preset.name)」中的目标应用均未打开。",
            "None of the apps in '\(preset.name)' are currently open."
        )
        openConsole(message: emptyMsg, workspaceID: preset.id)
        return
    }
    if response.error == "tcc_not_granted" || response.error == "capability_not_granted" {
        openConsole(
            message: input.pick("请先授权窗口控制与系统「辅助功能」权限。", "Grant window control and Accessibility access first."),
            workspaceID: preset.id
        )
        return
    }
    openConsole(message: response.message ?? input.pick("恢复工作区失败。", "Failed to apply workspace."), workspaceID: preset.id)
}

do {
    let command = input.arguments.first
    if command == nil || command == "--open" {
        openConsole()
    } else if command == "--capture-open" {
        openConsole(openCapture: true)
    } else {
        let store = try? WindowWorkspaceStore(dataDirectory: input.dataDir)
        let arg = input.arguments.dropFirst().first
        switch command {
        case "--snap":
            guard let preset = arg, !preset.isEmpty else { throw CocoaError(.featureUnsupported) }
            let doc = try? store?.update(isEnglish: input.isEnglish)
            runSnap(preset: preset, doc: doc)

        case "--list", "--sync":
            guard let store else { throw CocoaError(.fileNoSuchFile) }
            try emitDocument(store.update(isEnglish: input.isEnglish))

        case "--set-gap":
            guard let store, let rawGap = arg, let gapVal = Int(rawGap) else { throw CocoaError(.fileReadCorruptFile) }
            let clamped = max(0, min(24, gapVal))
            try emitDocument(store.update(isEnglish: input.isEnglish) { doc in
                doc.preferences.gap = clamped
            })

        case "--set-launch-missing":
            guard let store, let rawBool = arg else { throw CocoaError(.fileReadCorruptFile) }
            let enabled = ["1", "true", "yes"].contains(rawBool.lowercased())
            try emitDocument(store.update(isEnglish: input.isEnglish) { doc in
                doc.preferences.launchMissingApps = enabled
            })

        case "--save-workspace":
            guard let store else { throw CocoaError(.fileNoSuchFile) }
            let preset = try JSONDecoder().decode(WindowWorkspacePreset.self, from: Data(input.query.utf8))
            guard preset.isValid else { throw CocoaError(.fileReadCorruptFile) }
            try emitDocument(store.update(isEnglish: input.isEnglish) { doc in
                if let idx = doc.workspaces.firstIndex(where: { $0.id == preset.id }) {
                    doc.workspaces[idx] = preset
                } else {
                    doc.workspaces.insert(preset, at: 0)
                }
            })

        case "--delete-workspace", "--set-favorite":
            guard let store, let arg, let id = UUID(uuidString: arg) else { throw CocoaError(.fileReadCorruptFile) }
            try emitDocument(store.update(isEnglish: input.isEnglish) { doc in
                guard doc.workspaces.contains(where: { $0.id == id }) else { return }
                if command == "--delete-workspace" {
                    doc.workspaces.removeAll { $0.id == id }
                    if doc.favorite == id { doc.favorite = nil }
                } else {
                    doc.favorite = (doc.favorite == id) ? nil : id
                }
            })

        case "--apply-workspace", "--favorite":
            guard let store else { throw CocoaError(.fileNoSuchFile) }
            let doc = try store.update(isEnglish: input.isEnglish)
            let targetID = (command == "--favorite") ? doc.favorite : arg.flatMap(UUID.init(uuidString:))
            if let preset = doc.workspaces.first(where: { $0.id == targetID }) {
                applyWorkspace(preset, doc: doc)
            } else {
                openConsole(message: command == "--favorite"
                    ? input.pick("请先将一套多屏工作区设为常用。", "Star a workspace preset as your favorite first.")
                    : input.pick("该工作区布局已删除。", "This workspace preset was removed."))
            }

        default:
            throw CocoaError(.featureUnsupported)
        }
    }
} catch {
    let msg = input.pick("无法读取或保存窗口布局，请检查磁盘与权限。", "Couldn’t read or save layouts. Check storage and permissions.")
    let isQuick = ["--snap", "--apply-workspace", "--favorite"].contains(input.arguments.first ?? "")
    if isQuick { openConsole(message: msg) }
    else { PluginOutput.emitJSONObject(["title": pluginTitle, "error": msg]) }
}

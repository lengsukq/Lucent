import Carbon
import Combine
import Foundation
import LucentCore

struct ExternalHotKeyBinding {
    let pluginID: String
    let chord: HotKeyChord
    let handler: () -> Void
}

@MainActor
final class GlobalHotKeyManager: ObservableObject {
    nonisolated static let signature: OSType = 0x4C4D_4B59
    private static let externalHotKeyBaseID = 10_000
    static weak var activeInstance: GlobalHotKeyManager?

    @Published private(set) var currentConfig: HotKeyBindingConfig = HotKeyBindingConfig.load()
    @Published private(set) var registrationResults: [HotKeyActionID: Bool] = [:]
    @Published private(set) var ownedChords: Set<HotKeyChord> = []

    private var handlerRef: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var actions: [Int: () -> Void] = [:]
    private var storedHandlers: [HotKeyActionID: () -> Void] = [:]
    private var storedExternalBindings: [ExternalHotKeyBinding] = []

    init() {
        Self.activeInstance = self
        installCarbonEventHandlerIfNeeded()
    }

    private func installCarbonEventHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                guard let event else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                if status == noErr && hotKeyID.signature == GlobalHotKeyManager.signature {
                    let id = Int(hotKeyID.id)
                    Task { @MainActor in
                        GlobalHotKeyManager.activeInstance?.actions[id]?()
                    }
                }
                return noErr
            },
            1,
            &spec,
            nil,
            &handlerRef
        )
    }

    @discardableResult
    func applyConfig(
        _ config: HotKeyBindingConfig,
        handlers: [HotKeyActionID: () -> Void],
        externalBindings: [ExternalHotKeyBinding]? = nil
    ) -> [HotKeyActionID: Bool] {
        installCarbonEventHandlerIfNeeded()
        storedHandlers = handlers
        if let externalBindings { storedExternalBindings = externalBindings }
        currentConfig = config
        unregisterHotKeysOnly()

        var results: [HotKeyActionID: Bool] = [:]
        var claimed = Set<HotKeyChord>()

        for action in HotKeyActionID.allCases {
            let entry = config.binding(for: action)
            guard entry.isEnabled, let chord = entry.chord else { continue }
            guard chord.isValidGlobalShortcut else {
                results[action] = false
                continue
            }
            guard let callback = handlers[action] else { continue }
            if claimed.contains(chord) {
                results[action] = false
                continue
            }
            let ok = register(
                id: Int(action.carbonHotKeyNumericID),
                keyCode: chord.keyCode,
                modifiers: chord.carbonModifiers,
                action: callback
            )
            results[action] = ok
            if ok { claimed.insert(chord) }
        }

        for (idx, binding) in storedExternalBindings.enumerated() {
            guard binding.chord.isValidGlobalShortcut, !claimed.contains(binding.chord) else { continue }
            let ok = register(
                id: Self.externalHotKeyBaseID + idx,
                keyCode: binding.chord.keyCode,
                modifiers: binding.chord.carbonModifiers,
                action: binding.handler
            )
            if ok { claimed.insert(binding.chord) }
        }

        registrationResults = results
        ownedChords = claimed
        return results
    }

    @discardableResult
    func reapplyConfig(_ config: HotKeyBindingConfig, persist: Bool = true) -> [HotKeyActionID: Bool] {
        if persist { config.save() }
        return applyConfig(config, handlers: storedHandlers)
    }

    func updateExternalPluginHotKeys(_ bindings: [ExternalHotKeyBinding]) {
        storedExternalBindings = bindings
        _ = applyConfig(currentConfig, handlers: storedHandlers, externalBindings: bindings)
    }

    @discardableResult
    func register(id: Int, keyCode: Int, modifiers: Int, action: @escaping () -> Void) -> Bool {
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: UInt32(id))
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr, let ref {
            actions[id] = action
            hotKeyRefs.append(ref)
            return true
        }
        return false
    }

    private func unregisterHotKeysOnly() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        actions.removeAll()
    }

    func unregisterAll() {
        unregisterHotKeysOnly()
        registrationResults.removeAll()
        ownedChords.removeAll()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }
}

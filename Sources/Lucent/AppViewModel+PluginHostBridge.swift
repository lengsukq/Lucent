import AppKit
import CoreGraphics
import Foundation
import LucentCore

extension AppViewModel {
    func buildRichPluginBridgeContext(shelfContext: PluginContextPayload? = nil) -> PluginBridgeHostContext {
        PluginBridgeHostContext(
            everythingIndex: everythingIndex,
            preCapturedSelection: lastCapturedSelection,
            pasteBackHandler: { [weak self] text in
                guard let self else {
                    return PluginPasteBackOutcome(
                        writtenToClipboard: false, pastedToActiveApp: false,
                        accessibilityGranted: false, message: "Host unavailable"
                    )
                }
                return Self.runOnMainActorSync {
                    self.performPluginPasteBack(text)
                }
            },
            interactiveCaptureHandler: { [weak self] in
                guard let self else {
                    return PluginCapturedScreenFile(cancelled: true)
                }
                return try Self.runAsyncOnMainBlocking {
                    try await self.performPluginInteractiveCapture()
                }
            },
            customWindowOpener: { [weak self] spec in
                guard let self else { return false }
                return Self.runOnMainActorSync {
                    PluginCustomWebWindowController.shared.open(spec: spec, viewModel: self)
                }
            },
            customWindowCloser: { pluginID, windowID in
                Self.runOnMainActorSync {
                    PluginCustomWebWindowController.shared.close(pluginID: pluginID, windowID: windowID)
                }
            },
            fileShelfAction: { [weak self] id, adding in
                guard let self else { return false }
                return Self.runOnMainActorSync {
                    guard self.plugins.contains(where: {
                        $0.id == id && $0.isEnabled && $0.isValid && $0.isCapabilityGranted(.fileShelf)
                    }) else { return false }
                    let urls = adding ? (shelfContext?.filePaths ?? []).map { URL(fileURLWithPath: $0) } : []
                    guard !adding || !urls.isEmpty else { return false }
                    return FileShelfPanels.shared.open(pluginID: id, urls: urls, takeFocus: !adding)
                }
            },
            allowsAudioDevices: true,
            audioFeedback: { input, output in
                Task { @MainActor in AudioPresetHUD.shared.present(input: input, output: output) }
            },
            progressReporter: { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let pct = progress.fraction {
                        self.serviceMessage = "\(progress.message) (\(Int((pct * 100).rounded()))%)"
                    } else {
                        self.serviceMessage = progress.message
                    }
                }
            },
            contextMatcher: { [weak self] sourcePluginID, payload in
                guard let self else { return [] }
                return Self.runOnMainActorSync {
                    PluginContextMatcher.matchingPlugins(in: self.plugins, for: payload)
                        .filter { $0.id != sourcePluginID }
                        .map { plugin in
                            PluginContextRouteCandidate(
                                id: plugin.id,
                                name: plugin.displayName,
                                categoryTag: plugin.manifest.localizedCategoryTag(isBuiltin: plugin.isBuiltin),
                                symbolName: plugin.symbolIconName,
                                accentColor: plugin.manifest.accentColor ?? "cyan"
                            )
                        }
                }
            },
            contextRouter: { [weak self] targetPluginID, payload in
                guard let self else { return false }
                return Self.runOnMainActorSync {
                    self.routePluginContextToTarget(targetPluginID: targetPluginID, payload: payload)
                }
            }
        )
    }

    func routePluginContextToTarget(targetPluginID: String, payload: PluginContextPayload) -> Bool {
        guard let target = plugins.first(where: {
            $0.id == targetPluginID && !$0.isBuiltin && $0.isValid && $0.isEnabled
        }) else { return false }
        let matched = PluginContextMatcher.matchingPlugins(in: [target], for: payload)
        guard !matched.isEmpty else { return false }
        if target.declaredCapabilities.contains(.fileShelf),
           let paths = payload.filePaths, !paths.isEmpty {
            guard let authorized = authorizeFileShelfIfNeeded(target) else { return false }
            let urls = paths.map { URL(fileURLWithPath: $0) }
            PluginSystem.recordPluginUsage(id: authorized.id)
            return FileShelfPanels.shared.open(pluginID: authorized.id, urls: urls, takeFocus: false, expandIfTucked: true)
        }
        runPluginWithContext(target, context: payload)
        return true
    }

    @discardableResult
    func performPluginPasteBack(_ text: String) -> PluginPasteBackOutcome {
        guard !text.isEmpty else {
            return PluginPasteBackOutcome(
                writtenToClipboard: false, pastedToActiveApp: false,
                accessibilityGranted: AXIsProcessTrusted(), message: "Empty text"
            )
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        let wrote = pb.setString(text, forType: .string)
        lastPasteboardChangeCount = pb.changeCount

        let targetApp = resolveOverlayTargetApp?()
        if !isOverlayPinned {
            onHideOverlayRequest?()
        }
        targetApp?.activate()

        let axGranted = PluginHostTCCBroker.requestAccessOnBehalfOfPlugin(.accessibility).isGranted
        if wrote && axGranted {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(55)) {
                Self.postSyntheticCommandV()
            }
            let msg = L10n.pick("已自动粘贴回原窗口", "Pasted back to active window")
            serviceMessage = msg
            return PluginPasteBackOutcome(
                writtenToClipboard: true, pastedToActiveApp: true,
                accessibilityGranted: true, message: msg
            )
        }
        let fallbackMsg = L10n.pick(
            "已写入剪贴板（待授予 Lucent 辅助功能权限后支持自动粘贴，当前请按 ⌘V）",
            "Copied to clipboard (grant Accessibility to Lucent for auto-paste, or press ⌘V)"
        )
        serviceMessage = fallbackMsg
        return PluginPasteBackOutcome(
            writtenToClipboard: wrote, pastedToActiveApp: false,
            accessibilityGranted: axGranted, message: fallbackMsg
        )
    }

    private func performPluginInteractiveCapture() async throws -> PluginCapturedScreenFile {
        let preferredTargetApp = resolveOverlayTargetApp?()
        isCapturingScreen = true
        onHideOverlayRequest?()
        defer { isCapturingScreen = false }

        let result = try await ScreenCaptureCoordinator.shared.capture(
            mode: .interactiveAnnotate,
            preferredTargetApp: preferredTargetApp
        )
        switch result {
        case .cancelled:
            return PluginCapturedScreenFile(cancelled: true)
        case .copied(let url), .ocrRequested(let url), .cutoutRequested(let url), .saved(let url), .pinEdited(let url, _):
            let img = NSImage(contentsOf: url)
            return PluginCapturedScreenFile(
                cancelled: false, imagePath: url.path,
                width: Int(img?.size.width ?? 0), height: Int(img?.size.height ?? 0)
            )
        case .pinned(let url, _, _, _):
            let img = NSImage(contentsOf: url)
            return PluginCapturedScreenFile(
                cancelled: false, imagePath: url.path,
                width: Int(img?.size.width ?? 0), height: Int(img?.size.height ?? 0)
            )
        }
    }

    private static func postSyntheticCommandV() {
        let src = CGEventSource(stateID: .hidSystemState)
        if let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true) {
            down.flags = .maskCommand
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false) {
            up.flags = .maskCommand
            up.post(tap: .cghidEventTap)
        }
    }

    private nonisolated static func runOnMainActorSync<T: Sendable>(_ work: @MainActor @Sendable () -> T) -> T {
        if Thread.isMainThread { return MainActor.assumeIsolated(work) }
        return DispatchQueue.main.sync { MainActor.assumeIsolated(work) }
    }

    private nonisolated static func runAsyncOnMainBlocking<T: Sendable>(
        _ work: @MainActor @Sendable @escaping () async throws -> T
    ) throws -> T {
        let sem = DispatchSemaphore(value: 0)
        let box = LockedResultBox<T>()
        Task { @MainActor in
            do { box.set(.success(try await work())) }
            catch { box.set(.failure(error)) }
            sem.signal()
        }
        sem.wait()
        return try box.get()
    }
}

private final class LockedResultBox<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<T, Error>?
    func set(_ value: Result<T, Error>) { lock.withLock { result = value } }
    func get() throws -> T {
        try lock.withLock {
            guard let result else { throw LucentError.pluginExecutionFailed("Async bridge cancelled") }
            return try result.get()
        }
    }
}

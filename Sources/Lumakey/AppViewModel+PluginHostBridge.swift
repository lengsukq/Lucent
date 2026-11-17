import AppKit
import CoreGraphics
import Foundation
import LumakeyCore

extension AppViewModel {
    func buildRichPluginBridgeContext() -> PluginBridgeHostContext {
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
            }
        )
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
            "已写入剪贴板（待授予 Lumakey 辅助功能权限后支持自动粘贴，当前请按 ⌘V）",
            "Copied to clipboard (grant Accessibility to Lumakey for auto-paste, or press ⌘V)"
        )
        serviceMessage = fallbackMsg
        return PluginPasteBackOutcome(
            writtenToClipboard: wrote, pastedToActiveApp: false,
            accessibilityGranted: axGranted, message: fallbackMsg
        )
    }

    private func performPluginInteractiveCapture() async throws -> PluginCapturedScreenFile {
        isCapturingScreen = true
        onHideOverlayRequest?()
        defer { isCapturingScreen = false }

        let result = try await ScreenCaptureCoordinator.shared.capture(mode: .interactiveAnnotate)
        switch result {
        case .cancelled:
            return PluginCapturedScreenFile(cancelled: true)
        case .copied(let url), .ocrRequested(let url), .cutoutRequested(let url), .saved(let url):
            let img = NSImage(contentsOf: url)
            return PluginCapturedScreenFile(
                cancelled: false, imagePath: url.path,
                width: Int(img?.size.width ?? 0), height: Int(img?.size.height ?? 0)
            )
        case .pinned(let url, _):
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
            guard let result else { throw LumakeyError.pluginExecutionFailed("Async bridge cancelled") }
            return try result.get()
        }
    }
}

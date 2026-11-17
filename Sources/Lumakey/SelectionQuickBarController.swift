import AppKit
import ApplicationServices
import LumakeyCore
import SwiftUI

private final class NonActivatingSelectionPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class SelectionQuickBarController {
    static let shared = SelectionQuickBarController()

    private var panel: NonActivatingSelectionPanel?
    private let state = SelectionQuickBarState()
    private weak var viewModel: AppViewModel?
    private var activePlugin: PluginDescriptor?

    private var downMonitor: Any?
    private var upMonitor: Any?
    private var dismissMonitor: Any?
    private var probeTask: Task<Void, Never>?
    private var translateTask: Task<Void, Never>?
    private var mouseDownPoint: NSPoint?
    private var isMonitoring = false

    private init() {}

    func syncMonitoring(enabled: Bool, plugins: [PluginDescriptor], viewModel: AppViewModel) {
        self.viewModel = viewModel
        self.activePlugin = Self.pickSelectionPlugin(from: plugins)
        let shouldMonitor = enabled && AXIsProcessTrusted() && activePlugin != nil
        if shouldMonitor && !isMonitoring {
            startMonitors()
        } else if !shouldMonitor && isMonitoring {
            stopMonitors()
            dismiss()
        }
    }

    func stopAll() {
        stopMonitors()
        dismiss()
    }

    private static func pickSelectionPlugin(from plugins: [PluginDescriptor]) -> PluginDescriptor? {
        let candidates = plugins.filter {
            !$0.isBuiltin && $0.isEnabled && $0.isValid && $0.isCapabilityGranted(.selection)
        }
        return candidates.first(where: { $0.id == "translate-hub" }) ?? candidates.first
    }

    private func startMonitors() {
        isMonitoring = true
        downMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.mouseDownPoint = NSEvent.mouseLocation
                if let p = self.panel, p.isVisible, !p.frame.contains(NSEvent.mouseLocation) {
                    self.dismiss()
                }
            }
        }
        upMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            let clickCount = event.clickCount
            MainActor.assumeIsolated {
                self?.handleGlobalMouseUp(clickCount: clickCount)
            }
        }
        dismissMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.rightMouseDown, .scrollWheel, .keyDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if case .actions = self.state.phase { self.dismiss() }
            }
        }
    }

    private func stopMonitors() {
        isMonitoring = false
        if let downMonitor { NSEvent.removeMonitor(downMonitor); self.downMonitor = nil }
        if let upMonitor { NSEvent.removeMonitor(upMonitor); self.upMonitor = nil }
        if let dismissMonitor { NSEvent.removeMonitor(dismissMonitor); self.dismissMonitor = nil }
        probeTask?.cancel(); probeTask = nil
    }

    private func handleGlobalMouseUp(clickCount: Int) {
        let upPt = NSEvent.mouseLocation
        let downPt = mouseDownPoint
        mouseDownPoint = nil
        if let p = panel, p.isVisible, p.frame.contains(upPt) { return }
        guard let vm = viewModel, !vm.isOverlayVisible, !vm.isCapturingScreen else { return }
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        let dist = downPt.map { hypot(upPt.x - $0.x, upPt.y - $0.y) } ?? 0
        guard SelectionQuickBarFilter.shouldTriggerOnMouseRelease(dragDistance: dist, clickCount: clickCount) else { return }

        probeTask?.cancel()
        probeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self, let plugin = self.activePlugin else { return }
            let snapshot = PluginSelectionReader.captureFrontmostSelection(allowCopyFallback: false)
            guard let clean = SelectionQuickBarFilter.normalizedSelectionText(snapshot.text) else { return }
            self.presentActions(text: clean, plugin: plugin, near: NSEvent.mouseLocation)
        }
    }

    private func presentActions(text: String, plugin: PluginDescriptor, near cursor: NSPoint) {
        translateTask?.cancel()
        state.selectedText = text
        state.pluginName = plugin.displayName
        state.phase = .actions
        state.toast = nil
        state.savedToVocab = false
        showPanel(near: cursor, estimatedSize: NSSize(width: 175, height: 42))
    }

    private func showPanel(near anchor: NSPoint, estimatedSize: NSSize) {
        let panel = ensurePanel()
        if let hosting = panel.contentView as? NSHostingView<LocalizedRootContainer<SelectionQuickBarView>> {
            hosting.layoutSubtreeIfNeeded()
        }
        let fit = panel.contentView?.fittingSize ?? estimatedSize
        let size = NSSize(width: max(fit.width, estimatedSize.width), height: max(fit.height, estimatedSize.height))
        let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor) }) ?? NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = min(max(visible.minX + 4, anchor.x - size.width / 2), visible.maxX - size.width - 4)
        let aboveY = anchor.y + 18 - SelectionQuickBarView.bottomShadowInset
        let belowY = anchor.y - size.height - 16 + SelectionQuickBarView.topShadowInset
        let y = (aboveY + size.height <= visible.maxY - 4) ? aboveY : max(visible.minY + 4, belowY)
        panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
        panel.orderFrontRegardless()
    }

    private func ensurePanel() -> NonActivatingSelectionPanel {
        if let panel { return panel }
        let p = NonActivatingSelectionPanel(
            contentRect: NSRect(x: 0, y: 0, width: 175, height: 42),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = NSHostingView(rootView: LocalizedRootContainer {
            SelectionQuickBarView(
                state: state,
                onTranslate: { [weak self] in self?.runQuickTranslation() },
                onSpeak: { [weak self] in
                    guard let self else { return }
                    _ = PluginAudioBridgePlayer.shared.speak(text: self.state.selectedText)
                },
                onCopySource: { [weak self] in
                    guard let self else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(self.state.selectedText, forType: .string)
                    self.dismiss()
                },
                onCopyResult: { [weak self] val in
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(val, forType: .string)
                    self?.state.toast = L10n.pick("已复制", "Copied")
                },
                onSaveVocab: { [weak self] args in self?.saveWordToVocab(args) },
                onClose: { [weak self] in self?.dismiss() }
            )
        })
        self.panel = p
        return p
    }

    private func runQuickTranslation() {
        guard let vm = viewModel, let plugin = activePlugin else { return }
        let anchor = panel.map { NSPoint(x: $0.frame.midX, y: $0.frame.minY) } ?? NSEvent.mouseLocation
        state.phase = .loading
        showPanel(near: anchor, estimatedSize: NSSize(width: 260, height: 52))

        let text = state.selectedText
        let ctxPayload = PluginContextPayload(kind: .text, text: text, source: "selection")
        let bridgeCtx = vm.makePluginBridgeContext()

        translateTask?.cancel()
        translateTask = Task { [weak self] in
            do {
                let res = try await PluginSystem.runPluginAsync(
                    plugin, query: text, clipboardText: "", arguments: [],
                    contextPayload: ctxPayload, hostContext: bridgeCtx
                )
                guard !Task.isCancelled, let self else { return }
                if let payload = res.viewPayload {
                    let details = (payload.items ?? []).dropFirst().map { "• \($0.title)" }.joined(separator: "\n")
                    let saveArgs = (payload.items?.first?.actions ?? []).first(where: { $0.id.hasPrefix("save-voc") })?.commandArgs
                    self.state.phase = .result(
                        title: payload.title,
                        subtitle: payload.subtitle ?? "",
                        detail: details,
                        saveArgs: saveArgs
                    )
                    self.showPanel(near: anchor, estimatedSize: NSSize(width: 340, height: 190))
                } else {
                    self.state.phase = .result(
                        title: res.plainText.isEmpty ? L10n.pick("暂无译文", "No result") : res.plainText,
                        subtitle: "", detail: "", saveArgs: nil
                    )
                    self.showPanel(near: anchor, estimatedSize: NSSize(width: 340, height: 150))
                }
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.state.phase = .error(error.localizedDescription)
                self.showPanel(near: anchor, estimatedSize: NSSize(width: 280, height: 100))
            }
        }
    }

    private func saveWordToVocab(_ args: [String]) {
        guard let vm = viewModel, let plugin = activePlugin else { return }
        let bridgeCtx = vm.makePluginBridgeContext()
        Task { [weak self] in
            _ = try? await PluginSystem.runPluginAsync(plugin, query: "", clipboardText: "", arguments: args, hostContext: bridgeCtx)
            await MainActor.run {
                self?.state.savedToVocab = true
                self?.state.toast = L10n.pick("已存生词本", "Saved")
                vm.reloadPluginSearchIndex()
            }
        }
    }

    func dismiss() {
        probeTask?.cancel(); probeTask = nil
        translateTask?.cancel(); translateTask = nil
        panel?.orderOut(nil)
    }
}

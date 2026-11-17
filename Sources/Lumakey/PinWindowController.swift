import AppKit
import LumakeyCore
import SwiftUI

final class KeyablePinPanel: NSPanel {
    var onEscape: (() -> Void)?
    var onKeyShortcut: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onKeyShortcut?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
        } else if onKeyShortcut?(event) == true {
            return
        } else {
            super.keyDown(with: event)
        }
    }
}

@MainActor
final class PinWindowController {
    static let shared = PinWindowController()
    private var panels: [NSPanel] = []
    private var unlockBadges: [ObjectIdentifier: NSPanel] = [:]
    var activePinCount: Int { panels.count }
    var availablePluginsProvider: (() -> [PluginDescriptor])?
    var onRouteToPlugin: ((PluginDescriptor, PluginContextPayload) -> Void)?

    func pinImage(at url: URL, screenRect: NSRect? = nil) {
        guard let nsImage = NSImage(contentsOf: url) else { return }
        let ratio = nsImage.size.height > 0 ? (nsImage.size.width / nsImage.size.height) : 1.0
        let rect: NSRect
        if let screenRect, screenRect.width >= 40, screenRect.height >= 40 {
            rect = screenRect
        } else {
            let visible = ScreenTopologyAndWindowMatcher.activeCursorScreen()?.visibleFrame
                ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let width = min(max(nsImage.size.width, 260), min(580, visible.width * 0.7))
            let height = min(max(width / max(ratio, 0.25), 180), min(500, visible.height * 0.7))
            let offset = CGFloat((panels.count % 6) * 26)
            let x = min(max(visible.minX + 24, visible.midX - width / 2 + offset), visible.maxX - width - 24)
            let y = min(max(visible.minY + 24, visible.midY - height / 2 - offset), visible.maxY - height - 24)
            rect = NSRect(x: x, y: y, width: width, height: height)
        }

        let panel = KeyablePinPanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isMovableByWindowBackground = true
        panel.hasShadow = true
        panel.minSize = NSSize(width: 96, height: 64)
        panel.contentAspectRatio = rect.size
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let state = PinOverlayState()
        let closeAction: () -> Void = { [weak self, weak panel] in
            guard let self, let panel else { return }
            self.dismissUnlockBadge(for: panel)
            self.panels.removeAll { $0 === panel }
            WindowMotionAnimator.dismiss(panel, style: .floatingPin) { [weak panel] in
                panel?.contentView = nil
                panel?.close()
                let name = url.lastPathComponent
                if name.hasPrefix("lumakey-pin-") || name.hasPrefix("cutout-") {
                    try? FileManager.default.removeItem(at: url)
                }
                MemoryStats.reclaimFreeHeapPages()
            }
        }
        panel.onEscape = closeAction

        let setClickThrough: (Bool) -> Void = { [weak self, weak panel] enabled in
            guard let self, let panel else { return }
            state.isClickThrough = enabled
            panel.ignoresMouseEvents = enabled
            if enabled {
                if state.opacity > 0.65 { state.opacity = 0.52 }
                state.isHovered = false
                self.presentUnlockBadge(for: panel) { [weak panel, weak self] in
                    guard let panel, let self else { return }
                    state.isClickThrough = false
                    panel.ignoresMouseEvents = false
                    state.opacity = 0.98
                    state.flashBadge(L10n.pick("已退出穿透模式", "Click-through off"))
                    self.dismissUnlockBadge(for: panel)
                }
            } else {
                state.opacity = 0.98
                self.dismissUnlockBadge(for: panel)
            }
        }

        let view = PinnedImageOverlayView(
            image: nsImage,
            imageURL: url,
            aspectRatio: max(ratio, 0.1),
            state: state,
            availablePluginsProvider: { [weak self] in self?.availablePluginsProvider?() ?? [] },
            onRouteToPlugin: { [weak self] plugin, ctx in self?.onRouteToPlugin?(plugin, ctx) },
            onToggleClickThrough: { setClickThrough(!state.isClickThrough) },
            onPinCutout: { [weak self] cutoutURL in self?.pinImage(at: cutoutURL) },
            onResetOriginalSize: { [weak panel] in
                guard let panel else { return }
                let screen = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
                let w = min(max(nsImage.size.width, 140), screen.width * 0.88)
                let h = w / max(ratio, 0.1)
                let next = NSRect(x: panel.frame.midX - w / 2, y: panel.frame.midY - h / 2, width: w, height: h)
                WindowMotionAnimator.animateFrame(panel, to: next, duration: 0.22)
            },
            onCloseAll: { [weak self] in self?.closeAll(animated: true) },
            onClose: closeAction
        )
        panel.onKeyShortcut = { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function])
            let ch = event.charactersIgnoringModifiers?.lowercased() ?? ""
            if flags == .command && ch == "c" { view.copyImage(); return true }
            if flags == .command && ch == "s" { view.saveAsPNG(); return true }
            if flags.isEmpty && ch == "t" { setClickThrough(!state.isClickThrough); return true }
            if flags.isEmpty && ch == "o" { view.runOCR(); return true }
            return false
        }

        let hosting = NSHostingView(rootView: LocalizedRootContainer { view })
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = 16
        hosting.layer?.cornerCurve = .continuous
        hosting.layer?.masksToBounds = true
        panel.contentView = hosting
        panels.append(panel)
        WindowMotionAnimator.present(panel, style: .floatingPin, makeKey: true)
    }

    private func presentUnlockBadge(for hostPanel: NSPanel, onUnlock: @escaping () -> Void) {
        dismissUnlockBadge(for: hostPanel)
        let badgeSize = NSSize(width: 96, height: 28)
        let origin = NSPoint(
            x: hostPanel.frame.maxX - badgeSize.width - 8,
            y: hostPanel.frame.maxY - badgeSize.height - 8
        )
        let badge = NSPanel(
            contentRect: NSRect(origin: origin, size: badgeSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        badge.level = .statusBar
        badge.isOpaque = false
        badge.backgroundColor = .clear
        badge.hasShadow = true
        badge.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        badge.contentView = NSHostingView(rootView: Button(action: onUnlock) {
            HStack(spacing: 4) {
                Image(systemName: "lock.open.fill").font(.system(size: 10, weight: .bold))
                Text(L10n.pick("退出穿透", "Unlock")).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.orange.opacity(0.92), in: Capsule(style: .continuous))
        }.buttonStyle(.plain))
        hostPanel.addChildWindow(badge, ordered: .above)
        badge.orderFrontRegardless()
        unlockBadges[ObjectIdentifier(hostPanel)] = badge
    }

    private func dismissUnlockBadge(for hostPanel: NSPanel) {
        let key = ObjectIdentifier(hostPanel)
        guard let badge = unlockBadges.removeValue(forKey: key) else { return }
        hostPanel.removeChildWindow(badge)
        badge.contentView = nil
        badge.close()
    }

    func closeAll(animated: Bool = true) {
        for (_, badge) in unlockBadges {
            badge.parent?.removeChildWindow(badge)
            badge.contentView = nil
            badge.close()
        }
        unlockBadges.removeAll()
        let activePanels = panels
        panels.removeAll()
        guard !activePanels.isEmpty else { return }
        if animated {
            for panel in activePanels {
                WindowMotionAnimator.dismiss(panel, style: .floatingPin) { [weak panel] in
                    panel?.contentView = nil
                    panel?.close()
                    MemoryStats.reclaimFreeHeapPages()
                }
            }
        } else {
            for panel in activePanels {
                panel.contentView = nil
                panel.close()
            }
            MemoryStats.reclaimFreeHeapPages()
        }
    }
}

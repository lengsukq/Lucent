import AppKit
import LucentCore
import SwiftUI

@MainActor
final class WindowSnapHUD {
    static let shared = WindowSnapHUD()
    private var window: NSPanel?
    private var hideTask: Task<Void, Never>?

    func present(title: String, subtitle: String, symbol: String) {
        hideTask?.cancel()
        if let existing = window {
            existing.contentView = nil
            existing.orderOut(nil)
            window = nil
        }
        let frame = ScreenTopologyAndWindowMatcher.activeCursorScreen()?.visibleFrame
            ?? NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let width: CGFloat = 336
        let height: CGFloat = 86
        let rect = CGRect(x: frame.midX - width / 2, y: frame.minY + 68, width: width, height: height)

        let panel = PluginHUDCanvasPanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let glass = RoundedGlassContainerView(cornerRadius: LiquidRadii.windowPanel)
        glass.frame = NSRect(origin: .zero, size: rect.size)
        glass.autoresizingMask = [.width, .height]
        let hosting = NSHostingView(rootView: LocalizedRootContainer {
            WindowSnapHUDView(title: title, subtitle: subtitle, symbol: symbol)
        })
        hosting.sizingOptions = []
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.frame = glass.bounds
        hosting.autoresizingMask = [.width, .height]
        glass.addSubview(hosting)
        panel.contentView = glass

        WindowMotionAnimator.present(panel, style: .pulseCapsule, makeKey: false)
        window = panel

        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1650))
            guard !Task.isCancelled, let self, let activePanel = self.window else { return }
            WindowMotionAnimator.dismiss(activePanel, style: .pulseCapsule) { [weak self, weak activePanel] in
                guard let self, self.window === activePanel else { return }
                activePanel?.contentView = nil
                self.window = nil
                self.hideTask = nil
            }
        }
    }
}

private struct WindowSnapHUDView: View {
    let title: String
    let subtitle: String
    let symbol: String
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        let highContrast = SystemDisplayPreferences.shared.increaseContrast
        let shape = RoundedRectangle(cornerRadius: LiquidRadii.windowPanel, style: .continuous)
        HStack(spacing: 14) {
            SquircleBadge(symbol: symbol, topColor: .blue, bottomColor: .cyan, size: 38)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3.5) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(LiquidColors.textPrimary)
                        .lineLimit(1)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color.mint)
                }
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(LiquidColors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(shape)
        .overlay {
            DoubleSpecularBorder(cornerRadius: LiquidRadii.windowPanel, isShell: true, highContrast: highContrast)
        }
        .id(theme.current)
    }
}

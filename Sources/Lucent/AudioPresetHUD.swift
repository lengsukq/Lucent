import AppKit
import LucentCore
import SwiftUI

@MainActor
final class AudioPresetHUD {
    static let shared = AudioPresetHUD()
    private var window: NSPanel?
    private var hideTask: Task<Void, Never>?

    func present(input: String, output: String) {
        hideTask?.cancel()
        if let existing = window {
            existing.contentView = nil
            existing.orderOut(nil)
            window = nil
        }
        let frame = ScreenTopologyAndWindowMatcher.activeCursorScreen()?.visibleFrame
            ?? NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let width: CGFloat = 352
        let height: CGFloat = 104
        let rect = CGRect(x: frame.midX - width / 2, y: frame.minY + 64, width: width, height: height)

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
            AudioPresetHUDView(input: input, output: output)
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
            try? await Task.sleep(for: .milliseconds(2300))
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

private struct AudioPresetHUDView: View {
    let input: String
    let output: String
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        let highContrast = SystemDisplayPreferences.shared.increaseContrast
        let shape = RoundedRectangle(cornerRadius: LiquidRadii.windowPanel, style: .continuous)
        HStack(spacing: 14) {
            SquircleBadge(symbol: "waveform", topColor: .indigo, bottomColor: .cyan, size: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4.5) {
                HStack(spacing: 6) {
                    Text(L10n.pick("已切换音频组合", "Audio Preset Applied"))
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(LiquidColors.textPrimary)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.mint)
                }
                Label(output, systemImage: "speaker.wave.2.fill")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(LiquidColors.textSecondary)
                    .lineLimit(1).truncationMode(.middle)
                Label(input, systemImage: "mic.fill")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(LiquidColors.textSecondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(shape)
        .overlay {
            DoubleSpecularBorder(cornerRadius: LiquidRadii.windowPanel, isShell: true, highContrast: highContrast)
        }
        .id(theme.current)
    }
}

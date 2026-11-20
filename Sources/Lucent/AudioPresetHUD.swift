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
        window?.close()
        let frame = ScreenTopologyAndWindowMatcher.activeCursorScreen()?.visibleFrame
            ?? NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 920, height: 720)
        let width: CGFloat = 344
        let viewHeight: CGFloat = 112
        let panel = PluginHUDCanvasPanel(
            contentRect: CGRect(x: frame.midX - width / 2, y: frame.minY + 62, width: width, height: viewHeight),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let hosting = NSHostingView(rootView: statusView(input: input, output: output))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.orderFrontRegardless()
        window = panel
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(2400))
            guard !Task.isCancelled else { return }
            self?.window?.close()
            self?.window = nil
            self?.hideTask = nil
        }
    }

    private func statusView(input: String, output: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.indigo)
                .frame(width: 38, height: 38)
                .background(Color.indigo.opacity(0.15), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.pick("已切换音频组合", "Audio preset applied"))
                    .font(.system(size: 14, weight: .semibold))
                Label(output, systemImage: "speaker.wave.2.fill").lineLimit(1).truncationMode(.middle)
                Label(input, systemImage: "mic.fill").lineLimit(1).truncationMode(.middle)
            }
            .font(.system(size: 12))
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
        }
        .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { LiquidFluidBackdrop() }
        .clipShape(RoundedRectangle(cornerRadius: LiquidRadii.windowPanel))
        .overlay { RoundedRectangle(cornerRadius: LiquidRadii.windowPanel).strokeBorder(LiquidColors.inputFieldBorder) }
    }
}

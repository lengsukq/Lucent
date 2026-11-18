import AppKit
import LucentCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class PinOverlayState: ObservableObject {
    @Published var opacity: Double = 0.98
    @Published var isHovered: Bool = false
    @Published var isClickThrough: Bool = false
    @Published var statusBadge: String?
    private var badgeTask: Task<Void, Never>?

    func flashBadge(_ text: String, autoClear: Bool = true) {
        badgeTask?.cancel(); statusBadge = text
        guard autoClear else { return }
        badgeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            if !Task.isCancelled { self?.statusBadge = nil }
        }
    }
}

struct PinMenuCallbacks {
    let copyImage: () -> Void
    let runOCR: () -> Void
    let runCutout: () -> Void
    let resetSize: () -> Void
    let toggleOpacity: () -> Void
    let toggleClickThrough: () -> Void
    let savePNG: () -> Void
    let matchingPlugins: () -> [(PluginDescriptor, PluginContextPayload)]
    let sendToPlugin: (PluginDescriptor, PluginContextPayload) -> Void
    let closeThis: () -> Void
    let closeAll: () -> Void
}

struct PinnedImageOverlayView: View {
    let image: NSImage
    let imageURL: URL
    let aspectRatio: CGFloat
    var isCutoutSubject: Bool = false
    @ObservedObject var state: PinOverlayState
    var availablePluginsProvider: () -> [PluginDescriptor] = { [] }
    var onRouteToPlugin: ((PluginDescriptor, PluginContextPayload) -> Void)? = nil
    var onInvalidateShadow: (() -> Void)? = nil
    let onToggleClickThrough: () -> Void
    let onPinCutout: (URL) -> Void
    let onResetOriginalSize: () -> Void
    let onCloseAll: () -> Void
    let onClose: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        ZStack {
            if isCutoutSubject {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .opacity(state.opacity)
            } else {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .opacity(state.opacity)
                    .clipShape(shape)
                    .overlay { shape.strokeBorder(LiquidColors.specularRimGradient, lineWidth: 1.3) }
            }

            PinInteractionLayer(
                aspectRatio: aspectRatio,
                onDoubleClick: { copyImage() },
                onAdjustOpacity: { delta in
                    state.opacity = min(1.0, max(0.20, state.opacity + delta))
                    onInvalidateShadow?()
                    state.flashBadge("\(Int(round(state.opacity * 100)))% 透明")
                },
                onHoverChanged: { state.isHovered = $0 },
                menuCallbacks: PinMenuCallbacks(
                    copyImage: { copyImage() }, runOCR: { runOCR() }, runCutout: { runCutout() },
                    resetSize: onResetOriginalSize, toggleOpacity: { toggleOpacity() },
                    toggleClickThrough: onToggleClickThrough, savePNG: { saveAsPNG() },
                    matchingPlugins: { resolveMatchingPlugins() },
                    sendToPlugin: { plugin, ctx in onRouteToPlugin?(plugin, ctx) },
                    closeThis: onClose, closeAll: onCloseAll
                )
            )

            VStack {
                HStack(spacing: 6) {
                    if let badge = state.statusBadge {
                        Text(badge).font(.caption2.weight(.semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.black.opacity(0.68), in: Capsule())
                    }
                    Spacer()
                    if state.isHovered && !state.isClickThrough { toolbarPills }
                }
                .padding(8)
                Spacer()
            }
        }
    }

    private var toolbarPills: some View {
        HStack(spacing: 5) {
            Button("识字") { runOCR() }
            Button("抠图") { runCutout() }
            Button("复制") { copyImage() }
            Button(action: onToggleClickThrough) { Image(systemName: "hand.point.up.braille") }
                .help(L10n.pick("半透明鼠标穿透对照 (T)", "Click-through overlay (T)"))
            Button { toggleOpacity() } label: { Image(systemName: "circle.lefthalf.filled") }
                .help("半透明对比 (⌥+滚轮可微调)")
            Button { saveAsPNG() } label: { Image(systemName: "square.and.arrow.down") }
                .help("另存为 PNG (⌘S)")
            Button(action: onClose) { Image(systemName: "xmark") }.help("关闭此钉图 (Esc)")
        }
        .font(.caption2.weight(.semibold)).buttonStyle(.plain)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.ultraThickMaterial, in: Capsule(style: .continuous))
        .overlay { Capsule(style: .continuous).strokeBorder(.white.opacity(0.32), lineWidth: 0.8) }
    }

    private func resolveMatchingPlugins() -> [(PluginDescriptor, PluginContextPayload)] {
        guard let ctx = PluginContextMatcher.payloadFromFiles([imageURL], source: "pin") else { return [] }
        return PluginContextMatcher.matchingPlugins(in: availablePluginsProvider(), for: ctx).map { ($0, ctx) }
    }

    func toggleOpacity() {
        state.opacity = state.opacity > 0.72 ? 0.55 : 0.98
        onInvalidateShadow?()
        state.flashBadge("\(Int(round(state.opacity * 100)))% 透明")
    }

    func copyImage() {
        if !ScreenshotCompositor.copyImageFileToPasteboard(at: imageURL) {
            let pb = NSPasteboard.general; pb.clearContents(); pb.writeObjects([image])
        }
        state.flashBadge("图片已复制")
    }

    func saveAsPNG() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = "Lucent-Pin-\(stamp).png"
        if panel.runModal() == .OK, let dest = panel.url {
            try? FileManager.default.copyItem(at: imageURL, to: dest); state.flashBadge("已保存")
        }
    }

    func runOCR() {
        state.flashBadge("识字中…", autoClear: false); let url = imageURL
        Task {
            do {
                let res = try await Task.detached(priority: .userInitiated) { try VisionService.analyzeTextAndBarcodes(at: url) }.value
                state.flashBadge(res.recognizedText.isEmpty && res.barcodes.isEmpty ? "无文本" : "OCR 已复制")
                OCRResultWindowController.shared.present(imageURL: url, analysis: res)
            } catch { state.flashBadge("识别失败") }
        }
    }

    func runCutout() {
        state.flashBadge("抠图中…", autoClear: false); let url = imageURL
        Task {
            do {
                let outURL = try await Task.detached(priority: .userInitiated) { try VisionService.liftForegroundSubject(from: url) }.value
                _ = ScreenshotCompositor.copyImageFileToPasteboard(at: outURL)
                state.flashBadge("已抠图并复制"); onPinCutout(outURL)
            } catch { state.flashBadge("未检测到主体") }
        }
    }
}

struct PinInteractionLayer: NSViewRepresentable {
    let aspectRatio: CGFloat
    let onDoubleClick: () -> Void
    let onAdjustOpacity: (Double) -> Void
    let onHoverChanged: (Bool) -> Void
    let menuCallbacks: PinMenuCallbacks

    func makeNSView(context: Context) -> PinInteractionNSView {
        let view = PinInteractionNSView(); sync(view); return view
    }
    func updateNSView(_ nsView: PinInteractionNSView, context: Context) { sync(nsView) }
    private func sync(_ view: PinInteractionNSView) {
        view.aspectRatio = aspectRatio; view.onDoubleClick = onDoubleClick
        view.onAdjustOpacity = onAdjustOpacity; view.onHoverChanged = onHoverChanged
        view.menuCallbacks = menuCallbacks
    }
}

final class PinInteractionNSView: NSView {
    var aspectRatio: CGFloat = 1.0
    var onDoubleClick: (() -> Void)?
    var onAdjustOpacity: ((Double) -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    var menuCallbacks: PinMenuCallbacks?
    private var trackingArea: NSTrackingArea?

    override var mouseDownCanMoveWindow: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        if event.clickCount == 2 { onDoubleClick?(); return }
        window?.performDrag(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY * 10
        guard abs(delta) > 0.05 else { return }
        if event.modifierFlags.contains(.option) { onAdjustOpacity?(delta > 0 ? 0.05 : -0.05); return }
        guard let win = window else { return }
        let factor: CGFloat = delta > 0 ? 1.06 : 0.94
        let visible = win.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let cur = win.frame
        let newW = min(max(96, cur.width * factor), visible.width * 0.92)
        let newH = max(64, newW / max(aspectRatio, 0.1))
        win.setFrame(NSRect(x: cur.midX - newW / 2, y: cur.midY - newH / 2, width: newW, height: newH), display: true, animate: false)
        win.invalidateShadow()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area); trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChanged?(false) }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let cb = menuCallbacks else { return nil }
        let menu = NSMenu()
        menu.addItem(PinMenuActionItem(title: L10n.pick("复制图片 (⌘C)", "Copy Image (⌘C)"), action: cb.copyImage))
        menu.addItem(PinMenuActionItem(title: L10n.pick("离线识字 (O)", "Offline OCR (O)"), action: cb.runOCR))
        menu.addItem(PinMenuActionItem(title: L10n.translate("主体抠图"), action: cb.runCutout))
        let matched = cb.matchingPlugins()
        if !matched.isEmpty {
            let sub = NSMenu()
            for (plugin, ctx) in matched { sub.addItem(PinMenuActionItem(title: plugin.displayName) { cb.sendToPlugin(plugin, ctx) }) }
            let parent = NSMenuItem(title: L10n.pick("发送到扩展插件", "Send to Plugin"), action: nil, keyEquivalent: "")
            parent.submenu = sub; menu.addItem(parent)
        }
        menu.addItem(.separator())
        menu.addItem(PinMenuActionItem(title: L10n.translate("100% 原始大小"), action: cb.resetSize))
        menu.addItem(PinMenuActionItem(title: L10n.pick("半透明鼠标穿透对照 (T)", "Click-Through Mode (T)"), action: cb.toggleClickThrough))
        menu.addItem(PinMenuActionItem(title: L10n.translate("切换半透明对比 (⌥滚轮)"), action: cb.toggleOpacity))
        menu.addItem(PinMenuActionItem(title: L10n.pick("另存为 PNG… (⌘S)", "Save as PNG… (⌘S)"), action: cb.savePNG))
        menu.addItem(.separator())
        menu.addItem(PinMenuActionItem(title: L10n.translate("关闭此钉图 (Esc)"), action: cb.closeThis))
        menu.addItem(PinMenuActionItem(title: L10n.translate("关闭全部钉图"), action: cb.closeAll))
        return menu
    }
}

@MainActor
private final class PinMenuActionItem: NSMenuItem {
    private let callback: () -> Void
    init(title: String, action: @escaping () -> Void) {
        self.callback = action
        super.init(title: title, action: #selector(handleTap), keyEquivalent: "")
        self.target = self
    }
    @available(*, unavailable) required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func handleTap() { callback() }
}

import AppKit
import ImageIO
import LucentCore
import SwiftUI

@MainActor
final class ImageViewerState: ObservableObject {
    @Published var zoomMode: ZoomMode = .fit
    @Published var scale: CGFloat = 1.0
    @Published var panOffset: CGSize = .zero
    @Published var currentURL: URL?
    @Published var playlistURLs: [URL] = []
    @Published var pixelSize: CGSize?
    @Published var toastText: String?
    private var toastTask: Task<Void, Never>?

    enum ZoomMode: Equatable {
        case fit
        case manual
    }

    func configure(initialURL: URL, providedSiblings: [URL]) {
        if providedSiblings.count > 1 {
            playlistURLs = providedSiblings
        } else {
            let scanned = MediaClassifier.siblingMediaURLs(around: initialURL, matching: [.image])
            playlistURLs = scanned.isEmpty ? [initialURL] : scanned
        }
        selectImage(at: initialURL)
    }

    func selectImage(at url: URL) {
        currentURL = url
        zoomMode = .fit
        scale = 1.0
        panOffset = .zero
        pixelSize = MediaClassifier.readImageDimensions(at: url)
    }

    func step(by delta: Int, fallback: URL) {
        guard playlistURLs.count > 1 else { return }
        let active = currentURL ?? fallback
        let idx = playlistURLs.firstIndex(of: active) ?? 0
        let next = (idx + delta + playlistURLs.count) % playlistURLs.count
        selectImage(at: playlistURLs[next])
    }

    func fitToWindow() {
        zoomMode = .fit
        scale = 1.0
        panOffset = .zero
    }

    func setActualSize(fitBaseScale: CGFloat) {
        zoomMode = .manual
        let ratio = fitBaseScale > 0.01 ? (1.0 / fitBaseScale) : 1.0
        scale = min(max(ratio, 0.25), 6.0)
        panOffset = .zero
    }

    func adjustScale(by factor: CGFloat) {
        zoomMode = .manual
        let next = min(max(scale * factor, 0.25), 6.0)
        scale = next
        if next <= 1.01 { panOffset = .zero }
    }

    func toggleDoubleClickZoom() {
        if zoomMode == .fit && abs(scale - 1.0) < 0.02 {
            zoomMode = .manual
            scale = 2.0
        } else {
            fitToWindow()
        }
    }

    func copyImage(at url: URL, fallbackImage: NSImage?) {
        var copied = ScreenshotCompositor.copyImageFileToPasteboard(at: url)
        if !copied, let fallbackImage {
            let pb = NSPasteboard.general
            pb.clearContents()
            copied = pb.writeObjects([fallbackImage])
        }
        if copied { showToast(L10n.pick("已复制图片", "Copied")) }
    }

    func showToast(_ text: String) {
        toastText = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1050))
            guard !Task.isCancelled, let self, self.toastText == text else { return }
            self.toastText = nil
        }
    }
}

struct ReadOnlyImageViewerSheet: View {
    let initialURL: URL
    let siblingURLs: [URL]
    let windowKey: String
    let onClose: () -> Void
    @StateObject private var state = ImageViewerState()

    private var activeURL: URL { state.currentURL ?? initialURL }

    var body: some View {
        let list = state.playlistURLs
        let indexText = list.count <= 1 ? nil : "\((list.firstIndex(of: activeURL) ?? 0) + 1) / \(list.count)"
        let loadedImage = NSImage(contentsOf: activeURL)

        SecondaryWindowScaffold(
            title: "只读看图",
            subtitle: indexText,
            symbol: "photo.on.rectangle.angled",
            pinWindowKey: windowKey
        ) {
            VStack(spacing: 10) {
                toolbarCard(listCount: list.count, loadedImage: loadedImage)
                canvasArea(loadedImage: loadedImage)
            }
        }
        .frame(minWidth: 760, minHeight: 540)
        .onAppear { state.configure(initialURL: initialURL, providedSiblings: siblingURLs) }
    }

    private func toolbarCard(listCount: Int, loadedImage: NSImage?) -> some View {
        HStack(alignment: .center, spacing: 8) {
            SquircleBadge(symbol: "photo.fill", topColor: .pink, bottomColor: .purple, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(activeURL.lastPathComponent).font(.callout.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                if let px = state.pixelSize {
                    Text("\(Int(px.width)) × \(Int(px.height)) px")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            Text(state.zoomMode == .fit ? L10n.pick("适应", "Fit") : "\(Int(round(state.scale * 100)))%")
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(LiquidColors.pillSurface, in: Capsule())

            Spacer(minLength: 6)

            if listCount > 1 {
                Button { state.step(by: -1, fallback: initialURL) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(GlassPillButtonStyle()).help("上一张 (←)")
                Button { state.step(by: 1, fallback: initialURL) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(GlassPillButtonStyle()).help("下一张 (→)")
            }
            Button { state.adjustScale(by: 0.8) } label: { Image(systemName: "minus.magnifyingglass") }
                .buttonStyle(GlassPillButtonStyle()).help("缩小 (-)")
            Button("适应") { state.fitToWindow() }
                .buttonStyle(GlassPillButtonStyle(prominent: state.zoomMode == .fit)).help("适应窗口 (0 / 双击)")
            Button { state.adjustScale(by: 1.25) } label: { Image(systemName: "plus.magnifyingglass") }
                .buttonStyle(GlassPillButtonStyle()).help("放大 (+)")
            Button { state.copyImage(at: activeURL, fallbackImage: loadedImage) } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            .buttonStyle(GlassPillButtonStyle()).help("复制图片 (⌘C)")
            Button { PinWindowController.shared.pinImage(at: activeURL) } label: {
                Label("贴图置顶", systemImage: "pin.fill")
            }
            .buttonStyle(GlassPillButtonStyle(prominent: true))
            Button { NSWorkspace.shared.activateFileViewerSelecting([activeURL]) } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(GlassPillButtonStyle()).help("在 Finder 中显示")
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .liquidGlassCard(cornerRadius: LiquidRadii.bento)
    }

    @ViewBuilder
    private func canvasArea(loadedImage: NSImage?) -> some View {
        if let nsImage = loadedImage {
            GeometryReader { geo in
                let availW = max(120, geo.size.width - 28)
                let availH = max(120, geo.size.height - 28)
                let imgW = max(1, nsImage.size.width)
                let imgH = max(1, nsImage.size.height)
                let fitRatio = min(1.0, min(availW / imgW, availH / imgH))
                let drawW = imgW * fitRatio * state.scale
                let drawH = imgH * fitRatio * state.scale

                ZStack {
                    AnimatedOrStaticImageRepresentable(image: nsImage)
                        .frame(width: drawW, height: drawH)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
                        }
                        .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
                        .offset(state.panOffset)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
                        .clipped()

                    ImageCanvasInteractionOverlay(
                        canPan: drawW > geo.size.width + 4 || drawH > geo.size.height + 4,
                        onScrollZoom: { factor in state.adjustScale(by: factor) },
                        onPanDelta: { dx, dy in
                            let maxX = max(0, (drawW - geo.size.width) / 2 + 40)
                            let maxY = max(0, (drawH - geo.size.height) / 2 + 40)
                            state.panOffset = CGSize(
                                width: min(max(state.panOffset.width + dx, -maxX), maxX),
                                height: min(max(state.panOffset.height - dy, -maxY), maxY)
                            )
                        },
                        onDoubleClick: { state.toggleDoubleClickZoom() },
                        onKeyCommand: { event in handleViewerKey(event, fitRatio: fitRatio, image: nsImage) }
                    )

                    if let toast = state.toastText {
                        VStack {
                            PlayerOSDToastView(text: toast).padding(.top, 12)
                            Spacer()
                        }
                    }
                }
            }
            .liquidGlassCard(cornerRadius: LiquidRadii.bento)
        } else {
            ContentUnavailableView("无法读取图像文件", systemImage: "photo")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .liquidGlassCard(cornerRadius: LiquidRadii.bento)
        }
    }

    private func handleViewerKey(_ event: NSEvent, fitRatio: CGFloat, image: NSImage) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let ch = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let code = event.keyCode
        if flags.isEmpty && (code == 53 || code == 49) { onClose(); return true }
        if flags.isEmpty && (code == 123 || code == 126) { state.step(by: -1, fallback: initialURL); return true }
        if flags.isEmpty && (code == 124 || code == 125) { state.step(by: 1, fallback: initialURL); return true }
        if (flags.isEmpty || flags == .command) && (ch == "+" || ch == "=") { state.adjustScale(by: 1.25); return true }
        if (flags.isEmpty || flags == .command) && ch == "-" { state.adjustScale(by: 0.8); return true }
        if (flags.isEmpty || flags == .command) && ch == "0" { state.fitToWindow(); return true }
        if (flags.isEmpty || flags == .command) && ch == "1" { state.setActualSize(fitBaseScale: fitRatio); return true }
        if flags == .command && ch == "c" { state.copyImage(at: activeURL, fallbackImage: image); return true }
        return false
    }
}

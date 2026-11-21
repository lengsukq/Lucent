import AppKit
import LucentCore
import SwiftUI

enum GifCapturePhase: Equatable {
    case idle
    case selectingRegion
    case recording(isPaused: Bool)
    case encoding
    case completed(GifFinalizeResult)
    case completedVideo(VideoFinalizeResult)
}

final class GifHUDPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    @MainActor
    static func present(near region: NSRect, visibleFrame: NSRect, controller: GifCaptureController) -> GifHUDPanel {
        let hosting = NSHostingView(rootView: LocalizedRootContainer { GifRecordingHUDView(controller: controller) })
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        let fittedWidth = max(720, ceil(hosting.fittingSize.width) + 64)
        let hudFrame = MultiDisplayLayout.clampedHUDFrame(
            preferredSize: CGSize(width: fittedWidth, height: 96),
            near: region,
            visibleFrame: visibleFrame
        )
        let panel = GifHUDPanel(
            contentRect: hudFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.sharingType = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.contentView = hosting
        WindowMotionAnimator.present(panel, style: .dynamicIsland, makeKey: false)
        return panel
    }

    @MainActor
    static func presentSelection(
        session: GifSelectionSession,
        slice: ScreenDisplaySlice,
        makeKey: Bool,
        onStart: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> CaptureOverlayPanel {
        let screen = slice.appKitScreen
        let panel = CaptureOverlayPanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.acceptsMouseMovedEvents = true
        panel.contentView = FirstMouseHostingView(rootView: LocalizedRootContainer {
            GifSelectionOverlayView(session: session, slice: slice, onStartRecording: onStart, onCancel: onCancel)
        })
        panel.setFrame(screen.frame, display: true)
        WindowMotionAnimator.present(panel, style: .fullscreenOverlay, makeKey: makeKey)
        return panel
    }
}

struct GifRecordingHUDView: View {
    @ObservedObject var controller: GifCaptureController

    private var islandTransition: AnyTransition {
        .asymmetric(insertion: .scale(scale: 0.90).combined(with: .opacity), removal: .scale(scale: 0.93).combined(with: .opacity))
    }

    var body: some View {
        ZStack {
            switch controller.phase {
            case .recording(let isPaused): recordingCapsule(isPaused: isPaused).transition(islandTransition)
            case .encoding: encodingCapsule.transition(islandTransition)
            case .completed(let result): completedCapsule(result: result).transition(islandTransition)
            case .completedVideo(let video): completedVideoCapsule(result: video).transition(islandTransition)
            case .idle, .selectingRegion: EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(LiquidMotion.smoothSpring, value: controller.phase)
    }

    private func recordingCapsule(isPaused: Bool) -> some View {
        let pulse = isPaused ? 1.0 : (0.45 + 0.55 * (0.5 + 0.5 * sin(controller.elapsedSeconds * 5.4)))
        let dotColor = isPaused ? Color.orange : Color(red: 1.0, green: 0.24, blue: 0.22)
        let isVideo = controller.recordingMode == .video
        let dimLabel = isVideo ? VideoRecordingOptions.dimensionLabel(for: controller.videoOptions.maxDimension) : GifRecordingOptions.dimensionLabel(for: controller.options.maxDimension)
        let fpsVal = isVideo ? controller.videoOptions.fps : controller.options.fps
        let audioTag = (isVideo && controller.videoOptions.captureAudio) ? "·🔊" : ""

        return HStack(spacing: 10) {
            HStack(spacing: 7) {
                ZStack {
                    Circle().fill(dotColor.opacity(0.30 * pulse)).frame(width: 16, height: 16)
                    Circle().fill(dotColor.opacity(pulse)).frame(width: 8.5, height: 8.5)
                }
                Text(Self.formatDuration(controller.elapsedSeconds))
                    .font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(.white)
                    .contentTransition(.numericText()).lineLimit(1).fixedSize(horizontal: true, vertical: false)
            }
            .padding(.leading, 4)

            capsuleDivider

            HStack(spacing: 6) {
                Text(frameSummaryText(isPaused: isPaused))
                    .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.86))
                    .contentTransition(.numericText()).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                Text("\(dimLabel)·\(fpsVal)FPS\(audioTag)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(.cyan)
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 7).padding(.vertical, 2.5).background(.cyan.opacity(0.16), in: Capsule())
            }

            capsuleDivider

            HStack(spacing: 6) {
                hudButton(title: isPaused ? "继续" : "暂停", symbol: isPaused ? "play.fill" : "pause.fill", tint: .white.opacity(0.14)) { controller.togglePauseResume() }
                hudButton(title: "取消", symbol: "xmark", tint: .white.opacity(0.12)) { controller.cancelCapture() }
                Button(action: { controller.finishRecording() }) {
                    HStack(spacing: 5) {
                        Image(systemName: "stop.fill").font(.system(size: 9, weight: .bold))
                        Text("完成并复制").font(.system(size: 11.5, weight: .semibold))
                    }
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(.white).padding(.horizontal, 11).padding(.vertical, 5.5)
                    .background(LinearGradient(colors: [Color(red: 1.0, green: 0.28, blue: 0.26), Color(red: 0.88, green: 0.14, blue: 0.34)], startPoint: .topLeading, endPoint: .bottomTrailing), in: Capsule())
                }
                .buttonStyle(GifScaleButtonStyle()).fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8).fixedSize(horizontal: true, vertical: false)
        .modifier(DynamicIslandGlassModifier())
    }

    private var encodingCapsule: some View {
        HStack(spacing: 9) {
            ProgressView().controlSize(.small).tint(.cyan)
            Text(controller.recordingMode == .video
                 ? L10n.pick("正在封装 MP4 视频 (\(controller.encodedFrameCount) 帧)…", "Finalizing MP4 video (\(controller.encodedFrameCount) frames)…")
                 : "正在合成 GIF89a 动图 (\(controller.encodedFrameCount) 帧)…")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .modifier(DynamicIslandGlassModifier())
    }

    private func completedCapsule(result: GifFinalizeResult) -> some View {
        let sizeText = FastFormatters.formatFileBytes(result.fileSizeBytes)
        let w = Int(result.pixelSize.width), h = Int(result.pixelSize.height)
        return completedCapsuleShell(
            title: "已复制 GIF 动图",
            subtitle: "\(sizeText) · \(w)×\(h) · \(result.frameCount)帧",
            fileURL: result.fileURL,
            onCopy: { controller.copyResultAgain(result) },
            onSave: { controller.saveResultAs(result) },
            onReveal: { controller.revealResultInFinder(result.fileURL) },
            onPreview: { controller.previewResult(result.fileURL) }
        )
    }

    private func completedVideoCapsule(result: VideoFinalizeResult) -> some View {
        let sizeText = FastFormatters.formatFileBytes(result.fileSizeBytes)
        let w = Int(result.pixelSize.width), h = Int(result.pixelSize.height)
        let durText = Self.formatDuration(result.durationSeconds)
        return completedCapsuleShell(
            title: L10n.pick("已复制 MP4 录像", "MP4 Recording Copied"),
            subtitle: "\(sizeText) · \(w)×\(h) · \(durText)",
            fileURL: result.fileURL,
            onCopy: { controller.copyVideoResultAgain(result) },
            onSave: { controller.saveVideoResultAs(result) },
            onReveal: { controller.revealResultInFinder(result.fileURL) },
            onPreview: { controller.previewResult(result.fileURL) }
        )
    }

    private func completedCapsuleShell(
        title: String,
        subtitle: String,
        fileURL: URL,
        onCopy: @escaping () -> Void,
        onSave: @escaping () -> Void,
        onReveal: @escaping () -> Void,
        onPreview: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 11.5, weight: .bold)).foregroundStyle(.white)
                        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                }
            }
            .padding(.leading, 3)

            capsuleDivider

            HStack(spacing: 6) {
                hudButton(title: "复制", symbol: "doc.on.doc", tint: .white.opacity(0.14), action: onCopy)
                hudButton(title: "另存为", symbol: "square.and.arrow.down", tint: .white.opacity(0.14), action: onSave)
                hudButton(title: "访达定位", symbol: "folder", tint: .white.opacity(0.14), action: onReveal)
                hudButton(title: "预览", symbol: "eye", tint: .white.opacity(0.14), action: onPreview)
                GifCompletedPluginSendMenu(fileURL: fileURL) { controller.dismissCompletedHUD() }
                hudButton(title: "再来一段", symbol: "arrow.clockwise", tint: .cyan.opacity(0.28)) { controller.recordAgain() }
                Button(action: { controller.dismissCompletedHUD() }) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.78))
                        .frame(width: 24, height: 24).background(.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(GifScaleButtonStyle())
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 7.5)
        .fixedSize(horizontal: true, vertical: false)
        .modifier(DynamicIslandGlassModifier())
    }

    private var capsuleDivider: some View {
        Rectangle().fill(.white.opacity(0.18)).frame(width: 1, height: 18)
    }

    private func frameSummaryText(isPaused: Bool) -> String {
        if isPaused { return L10n.pick("已暂停 · \(controller.encodedFrameCount)帧", "Paused · \(controller.encodedFrameCount)f") }
        return controller.mergedFrameCount > 0
            ? L10n.pick("\(controller.encodedFrameCount)帧 (省\(controller.mergedFrameCount))", "\(controller.encodedFrameCount)f (-\(controller.mergedFrameCount))")
            : L10n.pick("\(controller.encodedFrameCount) 帧", "\(controller.encodedFrameCount) frames")
    }

    private func hudButton(title: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                Text(L10n.translate(title)).font(.system(size: 11, weight: .semibold))
            }
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(.white.opacity(0.94)).padding(.horizontal, 9.5).padding(.vertical, 5.5)
            .background(tint, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 0.7))
        }
        .buttonStyle(GifScaleButtonStyle())
        .fixedSize(horizontal: true, vertical: false)
    }

    static func formatDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private struct DynamicIslandGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        let reduceTransparency = SystemDisplayPreferences.shared.reduceTransparency
        let capsule = Capsule(style: .continuous)
        content
            .background {
                ZStack {
                    if !reduceTransparency { capsule.fill(.ultraThinMaterial) }
                    capsule.fill(Color(red: 0.06, green: 0.07, blue: 0.11).opacity(reduceTransparency ? 0.96 : 0.76))
                    WindowDragRegion()
                }
            }
            .clipShape(capsule)
            .overlay { capsule.strokeBorder(LiquidColors.specularRimGradient, lineWidth: 1.0) }
            .background {
                RoundedShapeOuterShadow(shape: capsule, color: .black.opacity(0.26), radius: 10, yOffset: 4)
            }
    }
}

private struct GifScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(LiquidMotion.pressSpring, value: configuration.isPressed)
    }
}

import AppKit
import LucentCore
import SwiftUI

struct CaptureSettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    private var prefs: GeneralPreferences { viewModel.generalPreferences }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionHeroHeader(
                    symbol: "camera.viewfinder",
                    topColor: .pink,
                    bottomColor: .purple,
                    title: L10n.pick("截图、钉图与 GIF 录屏", "Capture, Pins & GIF Recording"),
                    subtitle: L10n.pick(
                        "集中配置默认导出目录、独立窗口去阴影、静默保存及 GIF 录制规格，并快捷管理屏幕钉图。",
                        "Configure default save folder, window shadows, silent ⌘S saving, GIF presets, and active screen pins."
                    )
                ) {
                    HStack(spacing: 8) {
                        Button(L10n.pick("关闭所有屏幕钉图", "Close All Pins")) {
                            PinWindowController.shared.closeAll()
                        }
                        .buttonStyle(GlassPillButtonStyle())

                        Button(L10n.pick("截图 (⌥A)", "Capture (⌥A)")) {
                            viewModel.captureAndPinScreenshot()
                        }
                        .buttonStyle(GlassPillButtonStyle())

                        Button(L10n.pick("录 GIF (⌥G)", "GIF (⌥G)")) {
                            viewModel.startGifRecording()
                        }
                        .buttonStyle(GlassPillButtonStyle())

                        Button(L10n.pick("区域录像 (⌥R)", "Record (⌥R)")) {
                            viewModel.startVideoRecording()
                        }
                        .buttonStyle(GlassPillButtonStyle(prominent: true))
                    }
                }

                captureExportDefaultsCard
                gifDefaultsCard
                videoDefaultsCard
                captureTipsCard
            }
            .padding(.trailing, 4)
        }
    }

    private var captureExportDefaultsCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(
                L10n.pick("截图导出与标注默认项", "Screenshot Export & Annotation"),
                systemImage: "photo.on.rectangle.angled"
            )
            .font(.callout.weight(.semibold))

            HStack(spacing: 8) {
                Image(systemName: "folder.badge.gearshape")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LiquidColors.accentPrimary)
                Text(L10n.pick("默认导出目录：", "Default Save Folder:"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LiquidColors.textSecondary)
                Text(prefs.displayCaptureSaveDirectory)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(LiquidColors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Button(L10n.pick("选择目录…", "Choose…")) {
                    viewModel.selectCaptureSaveDirectoryInteractive()
                }
                .buttonStyle(GlassPillButtonStyle(compact: true))

                if !prefs.defaultCaptureSaveDirectoryPath.isEmpty {
                    Button(L10n.pick("恢复默认", "Reset")) {
                        viewModel.updateGeneralPreferences { $0.defaultCaptureSaveDirectoryPath = "" }
                    }
                    .buttonStyle(GlassPillButtonStyle(compact: true))
                }

                Button(L10n.pick("访达", "Reveal")) {
                    let dir = prefs.resolvedCaptureSaveDirectory()
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(dir)
                }
                .buttonStyle(GlassPillButtonStyle(compact: true))
            }

            FlowWrapLayout(horizontalSpacing: 18, verticalSpacing: 8) {
                Toggle(
                    L10n.pick("截图 / GIF 按 ⌘S 直接静默保存至默认目录（免每次弹窗）", "Save screenshots & GIFs directly to default folder on ⌘S (skip dialog)"),
                    isOn: Binding(
                        get: { prefs.quickSaveCaptureWithoutDialog },
                        set: { val in viewModel.updateGeneralPreferences { $0.quickSaveCaptureWithoutDialog = val } }
                    )
                )
                .fixedSize(horizontal: true, vertical: false)

                Toggle(
                    L10n.pick("独立窗口截图默认去除窗口阴影", "Exclude window shadow by default in window screenshots"),
                    isOn: Binding(
                        get: { prefs.screenshotExcludeWindowShadow },
                        set: { val in viewModel.updateGeneralPreferences { $0.screenshotExcludeWindowShadow = val } }
                    )
                )
                .fixedSize(horizontal: true, vertical: false)
            }
            .font(.caption)
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
    }

    private var gifDefaultsCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Label(
                    L10n.pick("GIF 动图录制默认规格", "GIF Recording Defaults"),
                    systemImage: "film.stack.fill"
                )
                .font(.callout.weight(.semibold))
                Spacer()
                Text("\(prefs.gifDefaultOptions.fps) FPS · \(GifRecordingOptions.dimensionLabel(for: prefs.gifDefaultOptions.maxDimension))")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(LiquidColors.accentPrimary)
                    .padding(.horizontal, 8).padding(.vertical, 2.5)
                    .background(LiquidColors.pillSurface, in: Capsule())
            }

            HStack(spacing: 7) {
                Text(L10n.pick("默认帧率：", "Default FPS:"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LiquidColors.textSecondary)
                ForEach(GifRecordingOptions.fpsPresets, id: \.self) { fps in
                    Button("\(fps) FPS") {
                        viewModel.updateGeneralPreferences { $0.gifDefaultOptions.fps = fps }
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: prefs.gifDefaultOptions.fps == fps, compact: true))
                }
                Spacer()
            }

            HStack(spacing: 7) {
                Text(L10n.pick("最大分辨率：", "Max Resolution:"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LiquidColors.textSecondary)
                ForEach(GifRecordingOptions.dimensionPresets, id: \.self) { dim in
                    Button(GifRecordingOptions.dimensionLabel(for: dim)) {
                        viewModel.updateGeneralPreferences { $0.gifDefaultOptions.maxDimension = dim }
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: prefs.gifDefaultOptions.maxDimension == dim, compact: true))
                }
                Spacer()
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
    }

    private var videoDefaultsCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Label(L10n.pick("区域 MP4 录像默认规格", "Region MP4 Recording Defaults"), systemImage: "video.circle.fill")
                    .font(.callout.weight(.semibold))
                Spacer()
                Text("\(prefs.videoDefaultOptions.fps) FPS · \(VideoRecordingOptions.dimensionLabel(for: prefs.videoDefaultOptions.maxDimension))")
                    .font(.caption2.monospacedDigit().weight(.semibold)).foregroundStyle(LiquidColors.accentPrimary)
                    .padding(.horizontal, 8).padding(.vertical, 2.5).background(LiquidColors.pillSurface, in: Capsule())
            }

            HStack(spacing: 7) {
                Text(L10n.pick("默认帧率：", "Default FPS:")).font(.caption2.weight(.semibold)).foregroundStyle(LiquidColors.textSecondary)
                ForEach(VideoRecordingOptions.fpsPresets, id: \.self) { fps in
                    Button("\(fps) FPS") { viewModel.updateGeneralPreferences { $0.videoDefaultOptions.fps = fps } }
                        .buttonStyle(GlassPillButtonStyle(prominent: prefs.videoDefaultOptions.fps == fps, compact: true))
                }
                Spacer()
            }

            HStack(spacing: 7) {
                Text(L10n.pick("画质规格：", "Resolution:")).font(.caption2.weight(.semibold)).foregroundStyle(LiquidColors.textSecondary)
                ForEach(VideoRecordingOptions.dimensionPresets, id: \.self) { dim in
                    Button(VideoRecordingOptions.dimensionLabel(for: dim)) { viewModel.updateGeneralPreferences { $0.videoDefaultOptions.maxDimension = dim } }
                        .buttonStyle(GlassPillButtonStyle(prominent: prefs.videoDefaultOptions.maxDimension == dim, compact: true))
                }
                Spacer()
            }

            Toggle(
                L10n.pick("录制时同时捕获系统内部音频（单屏或单窗口模式生效）", "Capture system audio during recording (single-display or window mode)"),
                isOn: Binding(
                    get: { prefs.videoDefaultOptions.captureAudio },
                    set: { val in viewModel.updateGeneralPreferences { $0.videoDefaultOptions.captureAudio = val } }
                )
            )
            .font(.caption)
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
    }

    private var captureTipsCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(L10n.pick("高频操作速记", "Quick Tips"), systemImage: "keyboard")
                .font(.caption.weight(.semibold))
                .foregroundStyle(LiquidColors.textSecondary)
            Text(L10n.pick(
                "• 单击任意窗口直接吸附完整圆角窗口（重叠窗口按 Tab 轮切），拖拽可自由框选区域\n• 截图按 C 取色、按 T 切换半透明钉图点击穿透；离线识字 (⌥O) 支持中英识别与条码提取",
                "• Click any window to snap cleanly (press Tab to cycle overlapping windows), or drag to select a region\n• Press C for color picker, T for click-through screen pins; Offline OCR (⌥O) extracts text & QR codes"
            ))
            .font(.caption2)
            .foregroundStyle(LiquidColors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)
    }
}

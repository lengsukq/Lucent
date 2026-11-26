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
                        "集中配置默认导出目录、多格式命名模板、子控件捕捉、工具栏精简及 GIF / MP4 录制规格。",
                        "Configure save folder, export format & templates, control drill-down, toolbar items, and recording presets."
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
                CaptureToolbarCustomizationCard(viewModel: viewModel)
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
                L10n.pick("截图导出、命名模板与交互行为", "Screenshot Export, Template & Behavior"),
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

            HStack(spacing: 8) {
                Text(L10n.pick("默认格式：", "Export Format:"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LiquidColors.textSecondary)
                ForEach(CaptureExportFormat.allCases) { fmt in
                    Button(fmt.displayLabel) {
                        viewModel.updateGeneralPreferences { $0.captureExportFormat = fmt }
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: prefs.captureExportFormat == fmt, compact: true))
                }

                Divider().frame(height: 14).padding(.horizontal, 4)

                Text(L10n.pick("双击选区空白：", "Double-click Selection:"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LiquidColors.textSecondary)
                ForEach(CaptureDoubleClickAction.allCases) { act in
                    Button(act.label) {
                        viewModel.updateGeneralPreferences { $0.captureDoubleClickAction = act }
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: prefs.captureDoubleClickAction == act, compact: true))
                }
                Spacer()
            }

            templateConfigRow

            FlowWrapLayout(horizontalSpacing: 18, verticalSpacing: 8) {
                Toggle(
                    L10n.pick("截图 / 长图按 ⌘S 直接静默保存至默认目录（弹可定位轻提示）", "Quick-save screenshots directly on ⌘S with Finder reveal toast"),
                    isOn: Binding(
                        get: { prefs.quickSaveCaptureWithoutDialog },
                        set: { val in viewModel.updateGeneralPreferences { $0.quickSaveCaptureWithoutDialog = val } }
                    )
                )
                .fixedSize(horizontal: true, vertical: false)

                Toggle(
                    L10n.pick("独立窗口截图默认去除窗口阴影", "Exclude window shadow by default"),
                    isOn: Binding(
                        get: { prefs.screenshotExcludeWindowShadow },
                        set: { val in viewModel.updateGeneralPreferences { $0.screenshotExcludeWindowShadow = val } }
                    )
                )
                .fixedSize(horizontal: true, vertical: false)

                Toggle(
                    L10n.pick("截图时隐藏 Lucent 自身窗口（关闭后可截取 Lucent 界面与浮窗）", "Hide Lucent windows during screenshots (turn off to capture Lucent UI)"),
                    isOn: Binding(
                        get: { prefs.hideLucentDuringScreenshot },
                        set: { val in viewModel.updateGeneralPreferences { $0.hideLucentDuringScreenshot = val } }
                    )
                )
                .fixedSize(horizontal: true, vertical: false)

                Toggle(
                    L10n.pick("有未保存标注时连按两次 Esc / 右键才退出（防手滑丢稿）", "Require double Esc / Right-click to discard unsaved annotations"),
                    isOn: Binding(
                        get: { prefs.confirmCancelAnnotatedCaptureWithDoublePress },
                        set: { val in viewModel.updateGeneralPreferences { $0.confirmCancelAnnotatedCaptureWithDoublePress = val } }
                    )
                )
                .fixedSize(horizontal: true, vertical: false)

                Toggle(
                    L10n.pick("启用无障碍子控件级下钻捕捉（悬停识别按钮/输入框，滚轮切层级）", "Enable Accessibility UI control drill-down snap"),
                    isOn: Binding(
                        get: { prefs.enableCaptureControlDrillDown },
                        set: { val in viewModel.updateGeneralPreferences { $0.enableCaptureControlDrillDown = val } }
                    )
                )
                .fixedSize(horizontal: true, vertical: false)
            }
            .font(.caption)
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
    }

    private var templateConfigRow: some View {
        let preview = CaptureFileNameFormatter.formatBaseName(template: prefs.captureFileNameTemplate, appName: "Safari")
            + ".\(prefs.captureExportFormat.fileExtension)"
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(L10n.pick("命名模板：", "Filename Template:"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LiquidColors.textSecondary)
                TextField(
                    CaptureFileNameFormatter.defaultTemplate,
                    text: Binding(
                        get: { prefs.captureFileNameTemplate },
                        set: { val in viewModel.updateGeneralPreferences { $0.captureFileNameTemplate = val } }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11.5, design: .monospaced))
                .frame(maxWidth: 240)

                ForEach(["{date}", "{time}", "{ms}", "{app}"], id: \.self) { token in
                    Button(token) {
                        viewModel.updateGeneralPreferences {
                            if !$0.captureFileNameTemplate.contains(token) {
                                $0.captureFileNameTemplate += "_\(token)"
                            }
                        }
                    }
                    .buttonStyle(GlassPillButtonStyle(compact: true))
                }
                Spacer()
            }
            Text(L10n.pick("实时预览：\(preview)", "Live preview: \(preview)"))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(LiquidColors.textSecondary)
        }
    }

    private var gifDefaultsCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Label(L10n.pick("GIF 动图录制默认规格", "GIF Recording Defaults"), systemImage: "film.stack.fill")
                    .font(.callout.weight(.semibold))
                Spacer()
                Text("\(prefs.gifDefaultOptions.fps) FPS · \(GifRecordingOptions.dimensionLabel(for: prefs.gifDefaultOptions.maxDimension))")
                    .font(.caption2.monospacedDigit().weight(.semibold)).foregroundStyle(LiquidColors.accentPrimary)
                    .padding(.horizontal, 8).padding(.vertical, 2.5).background(LiquidColors.pillSurface, in: Capsule())
            }
            HStack(spacing: 7) {
                Text(L10n.pick("默认帧率：", "Default FPS:")).font(.caption2.weight(.semibold)).foregroundStyle(LiquidColors.textSecondary)
                ForEach(GifRecordingOptions.fpsPresets, id: \.self) { fps in
                    Button("\(fps) FPS") { viewModel.updateGeneralPreferences { $0.gifDefaultOptions.fps = fps } }
                        .buttonStyle(GlassPillButtonStyle(prominent: prefs.gifDefaultOptions.fps == fps, compact: true))
                }
                Spacer()
            }
            HStack(spacing: 7) {
                Text(L10n.pick("最大分辨率：", "Max Resolution:")).font(.caption2.weight(.semibold)).foregroundStyle(LiquidColors.textSecondary)
                ForEach(GifRecordingOptions.dimensionPresets, id: \.self) { dim in
                    Button(GifRecordingOptions.dimensionLabel(for: dim)) { viewModel.updateGeneralPreferences { $0.gifDefaultOptions.maxDimension = dim } }
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
        VStack(alignment: .leading, spacing: 6) {
            Label(L10n.pick("高频操作速记", "Quick Tips"), systemImage: "keyboard")
                .font(.caption.weight(.semibold)).foregroundStyle(LiquidColors.textSecondary)
            Text(L10n.pick(
                "• 悬停窗口滚轮钻取子控件、Tab 轮切重叠窗、F 全屏选区、⇧⌘A 再次截图、S 手动滚动长截图\n• 选中标注可改色/滚轮调粗细/⌫ 单独删除、箭头支持 S 形贝塞尔控制柄、钉图聚焦按空格原地补画标注",
                "• Hover + Wheel drills into UI controls, Tab cycles windows, F selects screen, S starts scrolling capture\n• Click annotations to edit/resize/delete (⌫), bend arrows via handles, and press Space on Pins to annotate"
            ))
            .font(.caption2).foregroundStyle(LiquidColors.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)
    }
}

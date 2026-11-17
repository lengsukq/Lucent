import AppKit
import LumakeyCore
import SwiftUI

struct StartupAndResidenceCardView: View {
    @ObservedObject var viewModel: AppViewModel

    private var prefs: GeneralPreferences { viewModel.generalPreferences }
    private var loginStatus: LaunchAtLoginStatus { viewModel.launchAtLoginStatus }

    private var statusColor: Color {
        switch loginStatus {
        case .enabled: .mint
        case .requiresApproval: .orange
        case .notFound: .yellow
        case .notRegistered: LiquidColors.textSecondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Label(
                    L10n.pick("启动、登录项与驻留方式", "Startup, Login Item & Residence"),
                    systemImage: "power.circle.fill"
                )
                .font(.callout.weight(.semibold))

                Text(loginStatus.localizedBadge)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 8).padding(.vertical, 2.5)
                    .background(LiquidColors.pillSurface, in: Capsule())

                Spacer()

                if loginStatus == .requiresApproval {
                    Button(L10n.pick("打开系统登录项…", "Open Login Items…")) {
                        LaunchAtLoginService.openSystemLoginItemsSettings()
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: true, compact: true))
                } else if !LaunchAtLoginService.isInstalledInApplications() {
                    Button(L10n.pick("打开应用程序目录", "Open /Applications")) {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true))
                    }
                    .buttonStyle(GlassPillButtonStyle(compact: true))
                }
            }

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.pick("登录 macOS 时自动启动 Lumakey", "Launch Lumakey at macOS Login"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(LiquidColors.textPrimary)
                    Text(loginStatus.localizedGuidance)
                        .font(.caption2)
                        .foregroundStyle(LiquidColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: Binding(
                    get: { loginStatus.isEnabledOrPending },
                    set: { enabled in viewModel.setLaunchAtLogin(enabled) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(LiquidColors.pillSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: LiquidRadii.row, style: .continuous))

            FlowWrapLayout(horizontalSpacing: 18, verticalSpacing: 8) {
                Toggle(
                    L10n.pick("启动时静默驻留状态栏（不自动弹出快捷台）", "Launch silently in menu bar (don't pop up launcher)"),
                    isOn: Binding(
                        get: { prefs.launchSilentlyInMenuBar },
                        set: { val in viewModel.updateGeneralPreferences { $0.launchSilentlyInMenuBar = val } }
                    )
                )
                .fixedSize(horizontal: true, vertical: false)

                Toggle(
                    L10n.pick("无窗口时仍在程序坞 (Dock) 常驻图标", "Keep icon in Dock when all windows are closed"),
                    isOn: Binding(
                        get: { viewModel.showDockIcon },
                        set: { val in viewModel.setDockIconVisible(val) }
                    )
                )
                .fixedSize(horizontal: true, vertical: false)
            }
            .font(.caption)

            Divider().opacity(0.22)

            HStack(spacing: 8) {
                Text(L10n.pick("状态栏图标样式：", "Menu Bar Icon:"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LiquidColors.textSecondary)

                ForEach(MenuBarIconStyle.allCases) { style in
                    let active = prefs.menuBarIconStyle == style
                    Button {
                        viewModel.updateGeneralPreferences { $0.menuBarIconStyle = style }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: style.symbolName)
                                .font(.system(size: 11.5, weight: .semibold))
                            Text(style.localizedTitle)
                        }
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: active, compact: true))
                }
                Spacer()
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
        .onAppear { viewModel.refreshLaunchAtLoginStatus() }
    }
}

struct LauncherAndCaptureDefaultsCardView: View {
    @ObservedObject var viewModel: AppViewModel

    private var prefs: GeneralPreferences { viewModel.generalPreferences }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Label(
                    L10n.pick("快捷台交互与截图 / GIF 默认工作流", "Launcher Behavior & Capture Defaults"),
                    systemImage: "sparkles.rectangle.stack.fill"
                )
                .font(.callout.weight(.semibold))
                Spacer()
                if prefs.savedOverlayTopCenter != nil {
                    Button(L10n.pick("重置悬浮窗居中", "Recenter Launcher")) {
                        viewModel.recenterFloatingPanel()
                    }
                    .buttonStyle(GlassPillButtonStyle(compact: true))
                }
            }

            HStack(spacing: 7) {
                Text(L10n.pick("搜索词清理：", "Query Reset:"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LiquidColors.textSecondary)
                ForEach(OverlayQueryClearPolicy.allCases) { policy in
                    Button(policy.localizedTitle) {
                        viewModel.updateGeneralPreferences { $0.queryClearPolicy = policy }
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: prefs.queryClearPolicy == policy, compact: true))
                }
                Spacer()
            }

            HStack(spacing: 7) {
                Text(L10n.pick("弹出显示器：", "Target Display:"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LiquidColors.textSecondary)
                ForEach(OverlayScreenTarget.allCases) { target in
                    Button {
                        viewModel.updateGeneralPreferences { $0.overlayScreenTarget = target }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: target.symbolName).font(.system(size: 10.5, weight: .semibold))
                            Text(target.localizedTitle)
                        }
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: prefs.overlayScreenTarget == target, compact: true))
                }
                Spacer()
            }

            Toggle(
                L10n.pick("记忆手动拖拽后的快捷台屏幕坐标（双击顶部拖拽条可居中还原）", "Remember custom dragged launcher position (double-click top bar to recenter)"),
                isOn: Binding(
                    get: { prefs.rememberOverlayPosition },
                    set: { val in
                        viewModel.updateGeneralPreferences {
                            $0.rememberOverlayPosition = val
                            if !val { $0.savedOverlayTopCenter = nil }
                        }
                    }
                )
            )
            .font(.caption)

            Divider().opacity(0.22)

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

                Toggle(
                    L10n.pick("鼠标划词后显示悬浮翻译气泡（需开启辅助功能权限）", "Show floating translate bubble after highlighting text (requires Accessibility)"),
                    isOn: Binding(
                        get: { prefs.enableSelectionQuickBar },
                        set: { val in viewModel.updateGeneralPreferences { $0.enableSelectionQuickBar = val } }
                    )
                )
                .fixedSize(horizontal: true, vertical: false)
            }
            .font(.caption)

            HStack(spacing: 7) {
                Text(L10n.pick("GIF 默认录制规格：", "Default GIF Preset:"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LiquidColors.textSecondary)
                ForEach(GifRecordingOptions.fpsPresets, id: \.self) { fps in
                    Button("\(fps) FPS") {
                        viewModel.updateGeneralPreferences { $0.gifDefaultOptions.fps = fps }
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: prefs.gifDefaultOptions.fps == fps, compact: true))
                }
                Divider().frame(height: 14).opacity(0.25)
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
}

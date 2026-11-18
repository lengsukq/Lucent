import AppKit
import LucentCore
import SwiftUI

struct SoftwareAndPluginUpdateCardView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var updater = AppUpdateCoordinator.shared

    private var prefs: GeneralPreferences { viewModel.generalPreferences }

    private var lastCheckSummary: String {
        guard prefs.lastUpdateCheckTimestamp > 0 else {
            return L10n.pick("尚未自动检查", "Not checked yet")
        }
        let date = Date(timeIntervalSince1970: prefs.lastUpdateCheckTimestamp)
        return L10n.pick("上次检查：", "Last check: ") + FastFormatters.formatModificationDate(date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Label(
                    L10n.pick("应用版本与插件更新中心", "App & Plugin Update Center"),
                    systemImage: "arrow.triangle.2.circlepath.circle.fill"
                )
                .font(.callout.weight(.semibold))

                Text("v\(updater.currentVersion) (\(updater.currentBuild))")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(LiquidColors.accentPrimary)
                    .padding(.horizontal, 8).padding(.vertical, 2.5)
                    .background(LiquidColors.pillSurface, in: Capsule())

                Text(lastCheckSummary)
                    .font(.caption2)
                    .foregroundStyle(LiquidColors.textSecondary)
                    .lineLimit(1)

                Spacer()

                Button {
                    if let url = URL(string: AppUpdateService.releasesWebURL) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text(L10n.pick("版本历史", "Releases"))
                }
                .buttonStyle(GlassPillButtonStyle(compact: true))

                Button {
                    updater.checkNow(viewModel: viewModel)
                } label: {
                    HStack(spacing: 5) {
                        if updater.isCheckingUpdates {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(updater.isCheckingUpdates ? L10n.pick("正在检查…", "Checking…") : L10n.pick("立即检查更新", "Check Now"))
                    }
                }
                .buttonStyle(GlassPillButtonStyle(prominent: true, compact: true))
                .disabled(updater.isCheckingUpdates)
            }

            if let release = updater.availableAppRelease {
                appReleaseBanner(release)
            }

            if !updater.pendingPluginUpdates.isEmpty {
                pluginUpdatesBanner
            }

            if let banner = updater.statusBanner {
                HStack(spacing: 7) {
                    Image(systemName: updater.isErrorBanner ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(updater.isErrorBanner ? Color.orange : Color.mint)
                    Text(banner)
                        .font(.caption2)
                        .foregroundStyle(LiquidColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(LiquidColors.pillSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: LiquidRadii.row, style: .continuous))
            }

            HStack(spacing: 7) {
                Text(L10n.pick("自动检查频率：", "Auto-Check:"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LiquidColors.textSecondary)
                ForEach(UpdateCheckFrequency.allCases) { freq in
                    Button(freq.localizedTitle) {
                        viewModel.updateGeneralPreferences { $0.updateCheckFrequency = freq }
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: prefs.updateCheckFrequency == freq, compact: true))
                }
                Spacer()
            }

            FlowWrapLayout(horizontalSpacing: 18, verticalSpacing: 8) {
                Toggle(
                    L10n.pick("同步检查已订阅插件源的新版本", "Check subscribed plugin stores for updates"),
                    isOn: Binding(
                        get: { prefs.autoCheckPluginUpdates },
                        set: { val in viewModel.updateGeneralPreferences { $0.autoCheckPluginUpdates = val } }
                    )
                )
                .fixedSize(horizontal: true, vertical: false)

                Toggle(
                    L10n.pick("自动静默升级未新增权限的安全插件（越权升级仍需确认）", "Auto-upgrade safe plugins with zero new permissions"),
                    isOn: Binding(
                        get: { prefs.autoInstallSafePluginUpdates },
                        set: { val in viewModel.updateGeneralPreferences { $0.autoInstallSafePluginUpdates = val } }
                    )
                )
                .fixedSize(horizontal: true, vertical: false)

                Toggle(
                    L10n.pick("接收预览版更新 (Pre-release)", "Include pre-release builds"),
                    isOn: Binding(
                        get: { prefs.includePrereleaseAppUpdates },
                        set: { val in viewModel.updateGeneralPreferences { $0.includePrereleaseAppUpdates = val } }
                    )
                )
                .fixedSize(horizontal: true, vertical: false)
            }
            .font(.caption)
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
    }

    private func appReleaseBanner(_ release: AppReleaseInfo) -> some View {
        let sign = CodeSigningInspector.inspect()
        let localCert = AppUpdateInstaller.resolveLocalSigningIdentity(currentStatus: sign)
        let supportsAutoInstall = release.dmgDownloadURL != nil
            && Bundle.main.bundleURL.pathExtension == "app"
            && AppUpdateInstaller.canInstallInPlace()
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(.cyan)
                Text(L10n.pick(
                    "发现新版本：\(release.title)（当前 v\(updater.currentVersion) → v\(release.normalizedVersion)）",
                    "New Release: \(release.title) (v\(updater.currentVersion) → v\(release.normalizedVersion))"
                ))
                .font(.caption.weight(.semibold))
                if let size = release.dmgSizeBytes, size > 0 {
                    Text(FastFormatters.formatFileBytes(size))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(LiquidColors.textSecondary)
                }
                Spacer()
                Button(L10n.pick("跳过此版", "Skip")) {
                    updater.skipAvailableAppRelease(viewModel: viewModel)
                }
                .buttonStyle(GlassPillButtonStyle(compact: true))

                if release.dmgDownloadURL != nil {
                    Button(L10n.pick("仅下载 DMG", "Download DMG")) {
                        updater.downloadAndOpenReleaseDMG()
                    }
                    .buttonStyle(GlassPillButtonStyle(compact: true))
                    .disabled(updater.isDownloadingDMG || updater.isInstallingUpdate)
                }

                Button {
                    if supportsAutoInstall {
                        updater.downloadAndAutoInstallReleaseDMG()
                    } else {
                        updater.downloadAndOpenReleaseDMG()
                    }
                } label: {
                    HStack(spacing: 5) {
                        if updater.isDownloadingDMG || updater.isInstallingUpdate {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: supportsAutoInstall ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.down.circle.fill")
                        }
                        Text(
                            supportsAutoInstall
                                ? L10n.pick("自动安装并重启", "Install & Relaunch")
                                : (release.dmgDownloadURL != nil ? L10n.pick("下载并打开 DMG", "Download & Open DMG") : L10n.pick("前往下载页", "Open Release"))
                        )
                    }
                }
                .buttonStyle(GlassPillButtonStyle(prominent: true, compact: true))
                .disabled(updater.isDownloadingDMG || updater.isInstallingUpdate)
            }

            if supportsAutoInstall {
                Text(
                    localCert.map { cert in
                        L10n.pick(
                            "升级过程会自动用本机证书「\(cert)」原地重签并重启，无需手拖 DMG，既有「辅助功能 / 屏幕录制」权限直接保留。",
                            "Auto-install will re-sign with local certificate '\(cert)' and relaunch so TCC permissions stay intact."
                        )
                    } ?? L10n.pick(
                        "升级过程会自动替换应用并重启；若尚未在本机配置固定证书，重启后可在「通用设置」一键固定签名以保留权限。",
                        "Auto-install replaces the app and relaunches automatically. Configure local signing in General to preserve TCC permissions."
                    )
                )
                .font(.caption2)
                .foregroundStyle(localCert != nil ? Color.mint : LiquidColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            if !release.releaseNotes.isEmpty {
                Text(release.releaseNotes)
                    .font(.caption2)
                    .foregroundStyle(LiquidColors.textSecondary)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let dmgURL = updater.downloadedDMGURL, FileManager.default.fileExists(atPath: dmgURL.path) {
                HStack(spacing: 6) {
                    Image(systemName: "externaldrive.fill.badge.checkmark").font(.caption2).foregroundStyle(.mint)
                    Text(dmgURL.path).font(.system(size: 10.5, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button(L10n.pick("在访达中显示", "Show in Finder")) {
                        NSWorkspace.shared.activateFileViewerSelecting([dmgURL])
                    }
                    .buttonStyle(GlassPillButtonStyle(compact: true))
                }
            }
        }
        .padding(10)
        .background(Color.cyan.opacity(0.10), in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous).strokeBorder(Color.cyan.opacity(0.32), lineWidth: 0.8) }
    }

    private var pluginUpdatesBanner: some View {
        let count = updater.pendingPluginUpdates.count
        let names = updater.pendingPluginUpdates.prefix(3).map { $0.item.localizedName() }.joined(separator: "、")
        return HStack(spacing: 8) {
            Image(systemName: "puzzlepiece.extension.fill").foregroundStyle(.mint)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.pick("发现 \(count) 款已安装插件有新版本可升级", "\(count) installed plugin(s) have updates available"))
                    .font(.caption.weight(.semibold))
                Text(names)
                    .font(.caption2)
                    .foregroundStyle(LiquidColors.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(L10n.pick("前往插件市场更新", "Open Plugin Store")) {
                viewModel.openRoute(.settings(.plugins))
            }
            .buttonStyle(GlassPillButtonStyle(prominent: true, compact: true))
        }
        .padding(10)
        .background(Color.mint.opacity(0.10), in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous).strokeBorder(Color.mint.opacity(0.32), lineWidth: 0.8) }
    }
}

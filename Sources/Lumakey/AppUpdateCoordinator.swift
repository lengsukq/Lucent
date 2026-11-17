import AppKit
import Foundation
import LumakeyCore

@MainActor
final class AppUpdateCoordinator: ObservableObject {
    static let shared = AppUpdateCoordinator()

    @Published private(set) var isCheckingUpdates: Bool = false
    @Published private(set) var isDownloadingDMG: Bool = false
    @Published private(set) var availableAppRelease: AppReleaseInfo? = nil
    @Published private(set) var downloadedDMGURL: URL? = nil
    @Published private(set) var pendingPluginUpdates: [PluginStoreAvailableUpdate] = []
    @Published var statusBanner: String? = nil
    @Published var isErrorBanner: Bool = false

    private var startupCheckTask: Task<Void, Never>?

    private init() {}

    var currentVersion: String { AppUpdateService.currentAppVersion() }
    var currentBuild: String { AppUpdateService.currentBuildNumber() }
    var hasAnyPendingUpdate: Bool { availableAppRelease != nil || !pendingPluginUpdates.isEmpty }

    func performScheduledCheckOnStartupIfNeeded(viewModel: AppViewModel) {
        let prefs = viewModel.generalPreferences
        guard prefs.updateCheckFrequency.isDue(lastCheckedTimestamp: prefs.lastUpdateCheckTimestamp) else { return }
        startupCheckTask?.cancel()
        startupCheckTask = Task { [weak self, weak viewModel] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, let self, let viewModel else { return }
            await self.runCombinedUpdateCheck(viewModel: viewModel, userInitiated: false)
        }
    }

    func checkNow(viewModel: AppViewModel) {
        guard !isCheckingUpdates else { return }
        Task { [weak self, weak viewModel] in
            guard let self, let viewModel else { return }
            await self.runCombinedUpdateCheck(viewModel: viewModel, userInitiated: true)
        }
    }

    func runCombinedUpdateCheck(viewModel: AppViewModel, userInitiated: Bool) async {
        guard !isCheckingUpdates else { return }
        isCheckingUpdates = true
        if userInitiated {
            statusBanner = nil
            isErrorBanner = false
        }

        let prefs = viewModel.generalPreferences
        var appErr: String? = nil
        do {
            let outcome = try await AppUpdateService.checkGitHubUpdates(
                currentVersion: currentVersion,
                includePrerelease: prefs.includePrereleaseAppUpdates
            )
            switch outcome {
            case .upToDate:
                availableAppRelease = nil
            case .updateAvailable(_, let release):
                if !userInitiated && !prefs.skippedAppVersion.isEmpty
                    && release.normalizedVersion == prefs.skippedAppVersion {
                    availableAppRelease = nil
                } else {
                    availableAppRelease = release
                }
            }
        } catch {
            appErr = error.localizedDescription
        }

        var autoUpgradedCount = 0
        if userInitiated || prefs.autoCheckPluginUpdates {
            _ = PluginStoreDefaults.ensureDefaultDemoStoreSeeded()
            let storeOutcome = await PluginStoreService.refreshAllStores()
            var discovered = PluginStoreService.availableUpdates(
                in: storeOutcome.stores,
                installedPlugins: viewModel.plugins
            )
            if prefs.autoInstallSafePluginUpdates && !discovered.isEmpty {
                let safeUpdates = discovered.filter { !$0.permissionDiff.hasEscalation }
                for entry in safeUpdates {
                    if (try? await PluginStoreService.installStoreItem(entry.item, from: entry.store)) != nil {
                        autoUpgradedCount += 1
                    }
                }
                if autoUpgradedCount > 0 {
                    viewModel.reloadPluginsAndHotKeys()
                    discovered = PluginStoreService.availableUpdates(
                        in: storeOutcome.stores,
                        installedPlugins: viewModel.plugins
                    )
                }
            }
            pendingPluginUpdates = discovered
        }

        let nowEpoch = Date().timeIntervalSince1970
        viewModel.updateGeneralPreferences { $0.lastUpdateCheckTimestamp = nowEpoch }
        isCheckingUpdates = false
        NotificationCenter.default.post(name: .lumakeyMenuBarConfigDidChange, object: nil)

        if let appErr, availableAppRelease == nil, pendingPluginUpdates.isEmpty, autoUpgradedCount == 0 {
            if userInitiated {
                statusBanner = L10n.pick("检查更新失败：\(appErr)", "Update check failed: \(appErr)")
                isErrorBanner = true
            }
            return
        }

        var summaryParts: [String] = []
        if let rel = availableAppRelease {
            summaryParts.append(L10n.pick("发现 Lumakey v\(rel.normalizedVersion) 新版本", "Lumakey v\(rel.normalizedVersion) available"))
        }
        if autoUpgradedCount > 0 {
            summaryParts.append(L10n.pick("已静默升级 \(autoUpgradedCount) 款安全插件", "Auto-updated \(autoUpgradedCount) safe plugin(s)"))
        }
        if !pendingPluginUpdates.isEmpty {
            summaryParts.append(L10n.pick("\(pendingPluginUpdates.count) 款插件待确认更新", "\(pendingPluginUpdates.count) plugin update(s) ready"))
        }

        if summaryParts.isEmpty {
            if userInitiated {
                statusBanner = L10n.pick(
                    "当前应用 (v\(currentVersion)) 与全部已安装插件均已是最新版本",
                    "Lumakey (v\(currentVersion)) and all installed plugins are up to date"
                )
                isErrorBanner = false
            }
        } else {
            let joined = summaryParts.joined(separator: " · ")
            statusBanner = joined
            isErrorBanner = false
            if userInitiated { viewModel.serviceMessage = joined }
        }
    }

    func downloadAndOpenReleaseDMG() {
        guard let release = availableAppRelease, !isDownloadingDMG else { return }
        if release.dmgDownloadURL == nil {
            if let webURL = URL(string: release.htmlURL) { NSWorkspace.shared.open(webURL) }
            return
        }
        isDownloadingDMG = true
        statusBanner = L10n.pick("正在下载并校验 Lumakey v\(release.normalizedVersion) 安装包…", "Downloading & verifying Lumakey v\(release.normalizedVersion) DMG…")
        isErrorBanner = false

        Task { [weak self] in
            guard let self else { return }
            do {
                let dmgURL = try await AppUpdateService.downloadAndVerifyDMG(release)
                self.isDownloadingDMG = false
                self.downloadedDMGURL = dmgURL
                self.statusBanner = L10n.pick(
                    "✓ 已下载并通过 SHA-256 校验：\(dmgURL.lastPathComponent)，正在挂载安装包…",
                    "✓ Verified SHA-256 & downloaded \(dmgURL.lastPathComponent). Opening installer…"
                )
                self.isErrorBanner = false
                NSWorkspace.shared.open(dmgURL)
            } catch {
                self.isDownloadingDMG = false
                self.statusBanner = error.localizedDescription
                self.isErrorBanner = true
            }
        }
    }

    func skipAvailableAppRelease(viewModel: AppViewModel) {
        guard let rel = availableAppRelease else { return }
        viewModel.updateGeneralPreferences { $0.skippedAppVersion = rel.normalizedVersion }
        availableAppRelease = nil
        statusBanner = L10n.pick("已跳过 v\(rel.normalizedVersion) 自动提醒", "Skipped v\(rel.normalizedVersion)")
        isErrorBanner = false
        NotificationCenter.default.post(name: .lumakeyMenuBarConfigDidChange, object: nil)
    }

    func copyLocalResignCommand(viewModel: AppViewModel) {
        let command = AppUpdateService.localResignCommand(forAppBundleURL: Bundle.main.bundleURL)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        let msg = L10n.pick(
            "✓ 已复制保权限重签命令，可在终端粘贴运行以固定签名并延续系统权限",
            "✓ Copied TCC-preserving local resign command to clipboard"
        )
        statusBanner = msg
        isErrorBanner = false
        viewModel.serviceMessage = msg
    }

    func runLocalResignCommandInTerminal(viewModel: AppViewModel) {
        do {
            let scriptURL = try AppUpdateService.writeLocalResignTerminalScript(
                forAppBundleURL: Bundle.main.bundleURL
            )
            let terminalURL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
            if FileManager.default.fileExists(atPath: terminalURL.path) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.open([scriptURL], withApplicationAt: terminalURL, configuration: config) { [weak self] _, error in
                    Task { @MainActor in
                        guard let self else { return }
                        if let error {
                            self.handleTerminalLaunchFallback(error: error, viewModel: viewModel)
                        } else {
                            let msg = L10n.pick(
                                "✓ 已在终端启动本机保权限重签命令，请按终端及系统弹窗提示确认完成",
                                "✓ Launched local TCC-stable signing script in Terminal. Follow prompts there to finish."
                            )
                            self.statusBanner = msg
                            self.isErrorBanner = false
                            viewModel.serviceMessage = msg
                        }
                    }
                }
            } else if NSWorkspace.shared.open(scriptURL) {
                let msg = L10n.pick(
                    "✓ 已启动本机保权限重签命令，请按终端提示确认完成",
                    "✓ Launched local TCC-stable signing script in Terminal."
                )
                statusBanner = msg
                isErrorBanner = false
                viewModel.serviceMessage = msg
            } else {
                copyLocalResignCommand(viewModel: viewModel)
            }
        } catch {
            handleTerminalLaunchFallback(error: error, viewModel: viewModel)
        }
    }

    private func handleTerminalLaunchFallback(error: Error, viewModel: AppViewModel) {
        let command = AppUpdateService.localResignCommand(forAppBundleURL: Bundle.main.bundleURL)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        let msg = L10n.pick(
            "无法直接拉起终端（\(error.localizedDescription)），已将命令复制到剪贴板，请手动在终端粘贴执行",
            "Could not launch Terminal (\(error.localizedDescription)). Copied command to clipboard instead."
        )
        statusBanner = msg
        isErrorBanner = true
        viewModel.serviceMessage = msg
    }

    func refreshCachedPluginUpdateCount(installedPlugins: [PluginDescriptor]) {
        let catalog = PluginStoreService.loadCatalog()
        pendingPluginUpdates = PluginStoreService.availableUpdates(in: catalog.stores, installedPlugins: installedPlugins)
    }
}

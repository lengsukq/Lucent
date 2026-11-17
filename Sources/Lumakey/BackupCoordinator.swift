import AppKit
import Foundation
import LumakeyCore

struct PendingBackupRestore: Equatable {
    let sourceLabel: String
    let data: Data
    let summary: BackupInspectionSummary
    var options: BackupRestoreOptions
    var passphraseInput: String
}

enum BackupBannerTone: Equatable { case success, info, error }

struct BackupStatusBanner: Equatable {
    let tone: BackupBannerTone
    let message: String
}

@MainActor
enum BackupCoordinator {
    static func exportCurrentArchiveData(
        viewModel: AppViewModel,
        passphraseOverride: String? = nil
    ) throws -> Data {
        let resolvedPass = passphraseOverride ?? WebDAVKeychainStore.loadBackupPassphrase()
        return try BackupArchiveService.exportBackupData(
            clipboardEntries: viewModel.clipboardItems,
            mosConfig: viewModel.mosConfig,
            telemetryConfig: SystemPulseWindowController.shared.state.config,
            encryptionPassphrase: resolvedPass,
            compress: true
        )
    }

    static func applyRestoreReport(_ report: BackupRestoreReport, to viewModel: AppViewModel) {
        SnippetStore.shared.reloadFromDisk()
        AppUsageService.shared.discardPendingAndReloadFromDisk()
        LocalSecretVault.clearMemoryCache()

        viewModel.reloadGeneralPreferencesFromDisk()
        viewModel.applyMosConfig(report.mosConfig)
        let pulse = SystemPulseWindowController.shared
        pulse.state.config = report.telemetryConfig
        pulse.state.config.save()
        pulse.setMenuBarEnabled(report.telemetryConfig.showInMenuBar)
        pulse.setFloatingEnabled(report.telemetryConfig.floatingEnabled)

        var merged = viewModel.clipboardItems
        for entry in report.restoredClipboardEntries.reversed() {
            merged = ClipboardService.insert(
                entry,
                into: merged,
                maxUnpinned: viewModel.generalPreferences.clipboardMaxUnpinned,
                ttl: viewModel.generalPreferences.clipboardRetentionTTL
            )
        }
        viewModel.clipboardItems = merged
        viewModel.reloadThemeFromDisk()
        viewModel.reloadLanguageFromDisk()
        viewModel.reloadHomeLayoutFromDisk()
        viewModel.reloadAppsAndPlugins()
    }

    static func triggerQuickBackup(viewModel: AppViewModel) {
        let cfg = WebDAVConfig.load()
        if cfg.isConfigured, let pwd = try? WebDAVKeychainStore.loadPassword(account: cfg.username), !pwd.isEmpty {
            viewModel.serviceMessage = "正在后台上传 WebDAV 快照备份…"
            Task { @MainActor in
                do {
                    let archive = try exportCurrentArchiveData(viewModel: viewModel)
                    let client = WebDAVClient(config: cfg, password: pwd)
                    let item = try await Task.detached(priority: .utility) { try await client.uploadBackup(data: archive) }.value
                    viewModel.serviceMessage = "已上传云备份：\(item.fileName)"
                } catch {
                    viewModel.serviceMessage = "云备份失败：\(error.localizedDescription)"
                }
            }
        } else {
            BackupSettingsViewState().exportLocalBackupInteractive(viewModel: viewModel)
        }
    }

    static func triggerAutoBackupOnLaunchIfNeeded(viewModel: AppViewModel) {
        let cfg = WebDAVConfig.load()
        guard cfg.autoBackupOnLaunch, cfg.isConfigured,
              let pwd = try? WebDAVKeychainStore.loadPassword(account: cfg.username), !pwd.isEmpty else { return }
        Task { @MainActor in
            guard let archive = try? exportCurrentArchiveData(viewModel: viewModel) else { return }
            let client = WebDAVClient(config: cfg, password: pwd)
            _ = try? await Task.detached(priority: .background) { try await client.uploadBackup(data: archive) }.value
        }
    }
}

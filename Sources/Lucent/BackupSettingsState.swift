import AppKit
import Foundation
import LucentCore
import UniformTypeIdentifiers

@MainActor
final class BackupSettingsViewState: ObservableObject {
    @Published var webdavConfig: WebDAVConfig = WebDAVConfig.load()
    @Published var passwordInput: String = ""
    @Published var archivePassphraseInput: String = ""
    @Published var selectedPresetID: String = "jianguoyun"
    @Published var remoteItems: [WebDAVRemoteItem] = []
    @Published var pendingRestore: PendingBackupRestore?
    @Published var isBusy: Bool = false
    @Published var busyLabel: String = ""
    @Published var banner: BackupStatusBanner?
    private var previousAccount: String = ""

    var activePreset: WebDAVProviderPreset {
        WebDAVProviderPreset.allPresets.first(where: { $0.id == selectedPresetID }) ?? WebDAVProviderPreset.allPresets[0]
    }

    func onAppearLoad() {
        let cfg = WebDAVConfig.load()
        webdavConfig = cfg
        previousAccount = cfg.username
        if let saved = try? WebDAVKeychainStore.loadPassword(account: cfg.username) {
            passwordInput = saved
        }
        if let savedArchivePass = WebDAVKeychainStore.loadBackupPassphrase() {
            archivePassphraseInput = savedArchivePass
        }
        if let matched = WebDAVProviderPreset.allPresets.first(where: {
            !cfg.serverURL.isEmpty && cfg.serverURL.lowercased().contains($0.id)
        }) {
            selectedPresetID = matched.id
        }
    }

    func selectPreset(_ preset: WebDAVProviderPreset) {
        selectedPresetID = preset.id
        let trimmed = webdavConfig.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || WebDAVProviderPreset.allPresets.contains(where: { $0.sampleURL == trimmed }) {
            webdavConfig.serverURL = preset.sampleURL
        }
    }

    @discardableResult
    func saveArchivePassphrase() -> Bool {
        do {
            try WebDAVKeychainStore.saveBackupPassphrase(archivePassphraseInput)
            let hasPass = !archivePassphraseInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            banner = BackupStatusBanner(
                tone: .success,
                message: hasPass ? "已保存备份加密口令，后续导出与云同步将自动加密携带插件密钥" : "已清空备份加密口令，备份将仅包含非敏感配置与插件数据"
            )
            return true
        } catch {
            banner = BackupStatusBanner(tone: .error, message: error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func persistSettings() -> Bool {
        webdavConfig.save()
        do {
            if !previousAccount.isEmpty && previousAccount != webdavConfig.username {
                try? WebDAVKeychainStore.deletePassword(account: previousAccount)
            }
            try WebDAVKeychainStore.savePassword(passwordInput, account: webdavConfig.username)
            try WebDAVKeychainStore.saveBackupPassphrase(archivePassphraseInput)
            previousAccount = webdavConfig.username
            return true
        } catch {
            banner = BackupStatusBanner(tone: .error, message: error.localizedDescription)
            return false
        }
    }

    func exportLocalBackupInteractive(viewModel: AppViewModel) {
        let panel = NSSavePanel()
        panel.title = "导出 Lucent 全量备份归档 (v2 压缩)"
        panel.nameFieldStringValue = BackupArchiveService.defaultBackupFileName()
        panel.canCreateDirectories = true
        panel.allowsOtherFileTypes = true
        guard panel.runModal() == .OK, let targetURL = panel.url else { return }
        do {
            try? WebDAVKeychainStore.saveBackupPassphrase(archivePassphraseInput)
            let data = try BackupCoordinator.exportCurrentArchiveData(
                viewModel: viewModel, passphraseOverride: archivePassphraseInput
            )
            try data.write(to: targetURL, options: .atomic)
            let s = try BackupArchiveService.inspectBackupData(data)
            let secretNote = s.hasEncryptedSecrets ? " · 含口令加密密钥" : ""
            let msg = "已导出 \(targetURL.lastPathComponent)（\(s.configCount) 项配置 · \(s.pinnedClipboardCount) 条收藏 · \(s.pluginCount) 个插件 · \(s.pluginDataFileCount) 份插件数据\(secretNote)）"
            banner = BackupStatusBanner(tone: .success, message: msg)
            viewModel.serviceMessage = msg
        } catch {
            banner = BackupStatusBanner(tone: .error, message: error.localizedDescription)
        }
    }

    func chooseLocalBackupForRestore() {
        let panel = NSOpenPanel()
        panel.title = "选择 .lucentbackup 备份归档文件"
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: BackupEnvelope.fileExtension, conformingTo: .data), .json, .data
        ].compactMap { $0 }
        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }
        do {
            let data = try Data(contentsOf: sourceURL)
            let summary = try BackupArchiveService.inspectBackupData(data)
            pendingRestore = PendingBackupRestore(
                sourceLabel: sourceURL.lastPathComponent,
                data: data,
                summary: summary,
                options: .all,
                passphraseInput: archivePassphraseInput
            )
            banner = BackupStatusBanner(tone: .info, message: "SHA-256 校验通过，请核对下方快照摘要后确认恢复")
        } catch {
            banner = BackupStatusBanner(tone: .error, message: error.localizedDescription)
        }
    }

    func confirmPendingRestore(viewModel: AppViewModel) {
        guard var pending = pendingRestore else { return }
        pending.options.decryptionPassphrase = pending.passphraseInput
        do {
            let r = try BackupArchiveService.restoreBackupData(pending.data, options: pending.options)
            BackupCoordinator.applyRestoreReport(r, to: viewModel)
            pendingRestore = nil
            let missingPlugins = viewModel.plugins
                .filter { r.restoredPluginIDs.contains($0.id) && !PluginDataInspector.inspect($0).missingRequiredSecretKeys.isEmpty }
                .map(\.manifest.name)
            let secretNote = if !r.restoredSecretPluginIDs.isEmpty {
                " · 已解密恢复 \(r.restoredSecretPluginIDs.count) 个插件密钥"
            } else if !missingPlugins.isEmpty {
                "（提示：\(missingPlugins.joined(separator: "、")) 的密钥需在独立设置页录入）"
            } else {
                ""
            }
            let msg = "恢复完成：\(r.restoredConfigFileNames.count) 项配置、\(r.restoredClipboardEntries.count) 条收藏、\(r.restoredPluginIDs.count) 个插件、\(r.restoredPluginDataIDs.count) 组插件数据已生效\(secretNote)"
            banner = BackupStatusBanner(tone: .success, message: msg)
            viewModel.serviceMessage = msg
        } catch {
            banner = BackupStatusBanner(tone: .error, message: error.localizedDescription)
        }
    }

    func runWebDAVTest() {
        guard persistSettings() else { return }
        let client = WebDAVClient(config: webdavConfig, password: passwordInput)
        runAsyncTask(label: "正在验证 WebDAV 连通性…") {
            let status = try await client.testConnection()
            self.banner = BackupStatusBanner(tone: .success, message: status)
        }
    }

    func uploadBackupToWebDAV(viewModel: AppViewModel) {
        guard persistSettings() else { return }
        let archive: Data
        do {
            archive = try BackupCoordinator.exportCurrentArchiveData(
                viewModel: viewModel, passphraseOverride: archivePassphraseInput
            )
        } catch {
            banner = BackupStatusBanner(tone: .error, message: error.localizedDescription); return
        }
        let client = WebDAVClient(config: webdavConfig, password: passwordInput)
        runAsyncTask(label: "正在上传 v2 压缩备份并执行快照轮转…") {
            let uploaded = try await client.uploadBackup(data: archive)
            self.remoteItems = (try? await client.listBackups()) ?? [uploaded]
            self.banner = BackupStatusBanner(tone: .success, message: "云备份成功：\(uploaded.fileName)（保留最近 \(self.webdavConfig.keepLatestCount) 份）")
        }
    }

    func refreshRemoteList() {
        guard persistSettings() else { return }
        let client = WebDAVClient(config: webdavConfig, password: passwordInput)
        runAsyncTask(label: "正在拉取云端备份列表…") {
            do {
                let items = try await client.listBackups()
                self.remoteItems = items
                self.banner = BackupStatusBanner(tone: .info, message: items.isEmpty ? "云端目录暂无 .lucentbackup 快照" : "已同步 \(items.count) 份云端历史快照")
            } catch WebDAVError.notFound {
                self.remoteItems = []
                self.banner = BackupStatusBanner(tone: .info, message: "远端备份目录尚未建立，首次上传时将自动创建")
            }
        }
    }

    func downloadAndStageRemoteRestore(_ item: WebDAVRemoteItem) {
        let client = WebDAVClient(config: webdavConfig, password: passwordInput)
        runAsyncTask(label: "正在下载 \(item.fileName)…") {
            let data = try await client.downloadBackup(item: item)
            let summary = try BackupArchiveService.inspectBackupData(data)
            self.pendingRestore = PendingBackupRestore(
                sourceLabel: "云端 · \(item.fileName)",
                data: data,
                summary: summary,
                options: .all,
                passphraseInput: self.archivePassphraseInput
            )
            self.banner = BackupStatusBanner(tone: .info, message: "云端快照下载并通过 SHA-256 校验，请确认恢复")
        }
    }

    func deleteRemoteItem(_ item: WebDAVRemoteItem) {
        let client = WebDAVClient(config: webdavConfig, password: passwordInput)
        runAsyncTask(label: "正在删除 \(item.fileName)…") {
            try await client.deleteBackup(item: item)
            self.remoteItems.removeAll { $0.id == item.id }
            self.banner = BackupStatusBanner(tone: .success, message: "已删除云端快照：\(item.fileName)")
        }
    }

    private func runAsyncTask(label: String, operation: @escaping @MainActor () async throws -> Void) {
        guard !isBusy else { return }
        isBusy = true; busyLabel = label
        Task { @MainActor in
            defer { self.isBusy = false; self.busyLabel = "" }
            do { try await operation() }
            catch { self.banner = BackupStatusBanner(tone: .error, message: error.localizedDescription) }
        }
    }
}

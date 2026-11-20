import AppKit
import Combine
import Foundation
import LucentCore

extension AppViewModel {
    func configureLifecycleIntegrations() {
        installHomeLayoutObservers()
        installScriptObservers()
        let tracker = AppUsageTrackerController.shared
        runtime.usageCancellable = tracker.$revision.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateCachedDockApps()
                if self.isOverlayVisible { self.refreshDisplayedCandidates() }
            }
        }

        runtime.pluginWatcher?.stop()
        runtime.pluginWatcher = PluginDirectoryWatcher { [weak self] changes in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if changes.contains(.bundle) {
                    self.reloadPluginsAndHotKeys()
                } else if changes.contains(.searchIndex) {
                    self.reloadPluginSearchIndex()
                }
            }
        }

        GifCaptureController.shared.onRecordingCompleted = { [weak self] result in
            guard let self else { return }
            self.capturePasteboardOnceIfChanged()
            let sizeStr = FastFormatters.formatFileBytes(result.fileSizeBytes)
            self.serviceMessage = "GIF 动图已复制 (\(sizeStr) · \(result.frameCount) 帧)，可直接 ⌘V 粘贴"
        }
        GifCaptureController.shared.onVideoRecordingCompleted = { [weak self] result in
            guard let self else { return }
            self.capturePasteboardOnceIfChanged()
            let sizeStr = FastFormatters.formatFileBytes(result.fileSizeBytes)
            self.serviceMessage = L10n.pick(
                "MP4 区域录像已复制 (\(sizeStr) · \(result.frameCount) 帧)，可直接 ⌘V 粘贴",
                "MP4 recording copied (\(sizeStr) · \(result.frameCount) frames), ready for ⌘V"
            )
        }
        GifCaptureController.shared.onStatusMessage = { [weak self] msg in
            self?.serviceMessage = msg
        }
        GifCaptureController.shared.onDiagnostic = { [weak self] diag in
            self?.diagnostic = diag
        }
    }

    func performStartupOrphanCleanup() {
        LumaLinkRdpSidecarService.shared.cleanupOrphanedDaemonIfNeeded()
        PluginDataPaths.cleanupStaleSocketFiles()
        PluginDataPaths.cleanupStaleTmpDirectories()
    }

    func shutdownAllServicesAndTasks() {
        stopClipboardMonitor()
        workspaceRuntime.cancelAllTasks()
        workspaceRuntime.removeVolumeObservers()
        runtime.shutdownAll()
        _ = PluginAudioBridgePlayer.shared.stop()
    }

    func stopPluginWatcher() {
        runtime.stopPluginWatcherAndTasks()
    }

    func captureAndPinScreenshot() {
        runScreenCapture(mode: .interactiveAnnotate)
    }

    func captureAndAnalyzeOCR() {
        runScreenCapture(mode: .quickOCR)
    }

    private func runScreenCapture(mode: ScreenshotMode) {
        let preferredTargetApp = resolveOverlayTargetApp?()
        isCapturingScreen = true; onHideOverlayRequest?()
        Task {
            defer { self.isCapturingScreen = false }
            do {
                let result = try await ScreenCaptureCoordinator.shared.capture(mode: mode, preferredTargetApp: preferredTargetApp)
                self.isCapturingScreen = false
                switch result {
                case .cancelled:
                    self.capturePasteboardOnceIfChanged()
                case .copied(let url):
                    self.capturePasteboardOnceIfChanged()
                    latestCaptureURL = url; serviceMessage = "截图已自动复制到剪贴板，可直接 ⌘V 粘贴"
                case .saved(let url):
                    self.capturePasteboardOnceIfChanged()
                    latestCaptureURL = url; serviceMessage = "截图已保存并复制到剪贴板：\(url.lastPathComponent)"
                case .pinned(let url, let screenRect):
                    self.capturePasteboardOnceIfChanged()
                    latestCaptureURL = url; PinWindowController.shared.pinImage(at: url, screenRect: screenRect)
                    serviceMessage = "已钉在屏幕并自动复制到剪贴板"
                case .ocrRequested(let url):
                    await executeCaptureOCR(at: url)
                case .cutoutRequested(let url):
                    latestCaptureURL = url; liftSubject(at: url)
                }
            } catch let err as LucentError {
                diagnostic = err.diagnostic; serviceMessage = err.diagnostic.reason
                if err.diagnostic.reason.contains("屏幕录制"), let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            } catch {
                serviceMessage = error.localizedDescription
            }
        }
    }

    private func executeCaptureOCR(at url: URL) async {
        latestCaptureURL = url
        do {
            let analysis = try await Task.detached(priority: .userInitiated) { try VisionService.analyzeTextAndBarcodes(at: url) }.value
            let combined = ([analysis.recognizedText] + analysis.barcodes).filter { !$0.isEmpty }.joined(separator: "\n")
            serviceMessage = combined.isEmpty ? "未检测到文本" : "OCR 结果已复制到剪贴板"
            OCRResultWindowController.shared.present(imageURL: url, analysis: analysis) { [weak self] in
                self?.captureAndAnalyzeOCR()
            }
        } catch let err as LucentError {
            serviceMessage = err.diagnostic.reason
        } catch {
            serviceMessage = error.localizedDescription
        }
    }

    func analyzeImageWithVision(at url: URL) {
        Task {
            if let analysis = try? await Task.detached(priority: .userInitiated, operation: { try VisionService.analyzeTextAndBarcodes(at: url) }).value {
                ocrResultText = analysis.recognizedText.isEmpty ? "未识别到文本内容。" : analysis.recognizedText
                barcodeResults = analysis.barcodes
            }
        }
    }

    func liftSubject(at url: URL) {
        Task {
            if let outURL = try? await Task.detached(priority: .userInitiated, operation: { try VisionService.liftForegroundSubject(from: url) }).value {
                _ = ScreenshotCompositor.copyImageFileToPasteboard(at: outURL)
                capturePasteboardOnceIfChanged()
                PinWindowController.shared.pinImage(at: outURL)
                serviceMessage = "主体抠图已钉在屏幕并自动复制到剪贴板"
            }
        }
    }

    func applyMosConfig(_ next: MosConfig) {
        mosConfig = next
        MosEngine.shared.apply(config: next, persist: true)
        refreshMosStatus()
        reloadPlugins()
    }

    func requestMosAccessibilityPermission() {
        _ = MosEngine.shared.requestAccessibilityPermission()
        handleAccessibilityTrustOrMosChanged()
    }

    func refreshMosStatus() {
        MosEngine.shared.refreshTapStateIfNeeded()
        mosAccessibilityTrusted = MosEngine.shared.isAccessibilityTrusted
        mosTapActive = MosEngine.shared.isTapActive
    }

    func refreshToolingStatus() {
        Task { [weak self] in
            let detected = await Task.detached(priority: .utility) { HostToolingStatus.detect() }.value
            self?.toolingStatus = detected
        }
    }

    func presentHotKeyBanner(
        tone: SettingsHotKeyBanner.Tone,
        message: String,
        autoDismissSeconds: Double? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        runtime.hotKeyBannerDismissTask?.cancel()
        runtime.hotKeyBannerDismissTask = nil
        let banner = SettingsHotKeyBanner(tone: tone, message: message)
        hotKeyBanner = banner
        runtime.hotKeyBannerCancelAction = onCancel
        serviceMessage = message
        if let autoDismissSeconds, autoDismissSeconds > 0 {
            let bannerID = banner.id
            runtime.hotKeyBannerDismissTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(autoDismissSeconds))
                guard !Task.isCancelled, let self, self.hotKeyBanner?.id == bannerID else { return }
                self.dismissHotKeyBanner()
            }
        }
    }

    func dismissHotKeyBanner() {
        runtime.hotKeyBannerDismissTask?.cancel()
        runtime.hotKeyBannerDismissTask = nil
        runtime.hotKeyBannerCancelAction = nil
        hotKeyBanner = nil
    }

    func handleAccessibilityTrustOrMosChanged() {
        let prevTrusted = mosAccessibilityTrusted
        let prevActive = mosTapActive
        refreshMosStatus()
        SelectionQuickBarController.shared.syncMonitoring(
            enabled: generalPreferences.enableSelectionQuickBar,
            plugins: plugins,
            viewModel: self
        )
        if prevTrusted != mosAccessibilityTrusted || prevActive != mosTapActive {
            reloadPlugins()
        }
    }

    func applyLumaLinkConfig(_ next: LumaLinkConfig) {
        lumaLinkConfig = next
        LumaLinkRdpSidecarService.shared.onStatusChanged = { [weak self] in
            self?.refreshLumaLinkStatus(refreshPermissions: false)
        }
        LumaLinkServer.shared.apply(config: next, persist: true)
        refreshLumaLinkStatus(refreshPermissions: next.rdpEnabled)
        reloadPlugins()
    }

    func regenerateLumaLinkPin() {
        _ = LumaLinkServer.shared.regeneratePin()
        refreshLumaLinkStatus(refreshPermissions: false)
    }

    func revokeLumaLinkDevice(id: String) {
        LumaLinkServer.shared.revokePairedDevice(id: id)
        refreshLumaLinkStatus(refreshPermissions: false)
    }

    func refreshLumaLinkStatus(refreshPermissions: Bool = true) {
        lumaLinkConfig = LumaLinkServer.shared.currentConfig()
        lumaLinkStatus = LumaLinkServer.shared.currentSnapshot()
        lumaLinkRdpStatus = LumaLinkRdpSidecarService.shared.currentStatus(refreshPermissions: refreshPermissions)
        mosAccessibilityTrusted = MosEngine.shared.isAccessibilityTrusted
    }
}

import AppKit
import AVFoundation
import Combine
import CoreMedia
import Foundation
import LucentCore
import SwiftUI

@MainActor
final class CinemaPlayerController: ObservableObject {
    @Published var player: AVPlayer?
    @Published var preferredRate: Float = 1.0
    @Published var activeRate: Float = 1.0
    @Published var currentURL: URL?
    @Published var playlistURLs: [URL] = []
    @Published var episodeFilter: String = ""
    @Published var autoPlayNext: Bool = true
    @Published var isLoading: Bool = false
    @Published var errorReason: String?
    @Published var metadata: VideoStreamMetadata?
    @Published var showHUD: Bool = true
    @Published var showEpisodeDrawer: Bool = false
    @Published var showShortcutPopover: Bool = false
    @Published var osdMessage: String?

    private var tempRemuxURL: URL?
    private var loadTask: Task<Void, Never>?
    private var loadingDelayTask: Task<Void, Never>?
    private var hudHideTask: Task<Void, Never>?
    private var osdHideTask: Task<Void, Never>?
    private var endObserver: NSObjectProtocol?
    private var playerCancellables = Set<AnyCancellable>()
    private var targetSeekBaseTime: Double?
    private var lastSeekTimestamp: TimeInterval = 0

    var isNonUnitSpeed: Bool {
        PlayerRateHelper.isNonUnit(activeRate) || PlayerRateHelper.isNonUnit(preferredRate)
    }

    var effectiveDisplayRate: Float {
        PlayerRateHelper.isNonUnit(activeRate) ? activeRate : preferredRate
    }

    func configureAndLoad(initialURL: URL, providedSiblings: [URL], startCompact: Bool = false) {
        let targetKind: PreviewMediaKind = MediaClassifier.classify(url: initialURL, isDirectory: false) == .audio ? .audio : .video
        let resolvedList = providedSiblings.count > 1
            ? providedSiblings.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            : MediaClassifier.siblingMediaURLs(around: initialURL, matching: [targetKind])
        playlistURLs = resolvedList.isEmpty ? [initialURL] : resolvedList
        showEpisodeDrawer = !startCompact && playlistURLs.count > 1
        load(url: initialURL)
    }

    var filteredPlaylist: [(index: Int, url: URL)] {
        let needle = episodeFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        return playlistURLs.enumerated().compactMap { idx, url in
            (!needle.isEmpty && !url.lastPathComponent.localizedStandardContains(needle)) ? nil : (idx, url)
        }
    }

    func load(url: URL) {
        PreviewPlaybackRegistry.shared.pauseAll()
        loadTask?.cancel(); loadingDelayTask?.cancel()
        stopPlayerOnly(); cleanupTempFile()
        currentURL = url; isLoading = false; errorReason = nil; metadata = nil
        targetSeekBaseTime = nil; activeRate = preferredRate; showHUD = true

        loadingDelayTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled, let self, self.player == nil, self.errorReason == nil else { return }
            self.isLoading = true
        }

        loadTask = Task { [weak self] in
            let resolved = await VideoPlaybackCompat.preparePlayback(for: url, allowFFmpegRemux: true)
            guard !Task.isCancelled, let self else {
                if case .ready(_, _, let temp) = resolved, let temp { try? FileManager.default.removeItem(at: temp) }
                return
            }
            self.loadingDelayTask?.cancel(); self.isLoading = false
            switch resolved {
            case .ready(let item, let meta, let tempURL):
                self.tempRemuxURL = tempURL; self.metadata = meta
                let avPlayer = AVPlayer(playerItem: item)
                let launchRate = self.preferredRate > 0 ? self.preferredRate : 1.0
                avPlayer.defaultRate = launchRate
                self.installObservers(for: avPlayer, item: item)
                self.player = avPlayer
                avPlayer.playImmediately(atRate: launchRate)
                self.activeRate = launchRate
                self.scheduleHUDHide()
            case .unsupported(let reason):
                self.errorReason = reason
            }
        }
    }

    func handleKeyboardCommand(_ cmd: PlayerKeyboardCommand, window: NSWindow?, onClose: () -> Void) -> Bool {
        switch cmd {
        case .togglePlayPause: togglePlayPause(); return true
        case .seekRelative(let d): seek(by: d); return true
        case .adjustVolume(let d): adjustVolume(by: d); return true
        case .toggleMute: toggleMute(); return true
        case .stepSpeed(let dir): setRate(PlayerRateHelper.steppedRate(from: effectiveDisplayRate, delta: dir)); return true
        case .resetSpeed: resetRate(); return true
        case .frameStep(let f): stepFrame(by: f); return true
        case .toggleFullScreen: window?.toggleFullScreen(nil); return true
        case .stepEpisode(let d):
            guard playlistURLs.count > 1 else { return false }
            stepEpisode(by: d); return true
        case .togglePlaylist:
            guard playlistURLs.count > 1 else { return false }
            toggleEpisodeDrawer(); return true
        case .escape:
            if showShortcutPopover { showShortcutPopover = false; return true }
            if showEpisodeDrawer { toggleEpisodeDrawer(); return true }
            if let window, window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil); return true }
            onClose(); return true
        }
    }

    func togglePlayPause() {
        pokeHUD()
        guard let player else { return }
        if player.timeControlStatus == .playing || player.rate != 0 {
            player.pause(); presentOSD(L10n.pick("已暂停", "Paused"))
        } else {
            if let item = player.currentItem, item.duration.isNumeric,
               item.currentTime().seconds >= item.duration.seconds - 0.15 {
                player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            }
            let resume = preferredRate > 0 ? preferredRate : 1.0
            player.defaultRate = resume; activeRate = resume
            player.playImmediately(atRate: resume)
            let suffix = PlayerRateHelper.isNonUnit(resume) ? " · \(PlayerRateHelper.format(resume))" : ""
            presentOSD(L10n.pick("播放\(suffix)", "Play\(suffix)"))
        }
    }

    func seek(by seconds: Double) {
        pokeHUD()
        guard let player else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let base = (now - lastSeekTimestamp < 0.42 ? targetSeekBaseTime : nil) ?? max(0, player.currentTime().seconds)
        let nextTarget = max(0, base + seconds)
        targetSeekBaseTime = nextTarget; lastSeekTimestamp = now
        PlayerRateHelper.seekPreservingState(player: player, targetSeconds: nextTarget, preferredRate: preferredRate)
        presentOSD("\(seconds >= 0 ? "+" : "")\(Int(seconds))s")
    }

    func stepFrame(by count: Int) {
        pokeHUD()
        guard let player, let item = player.currentItem else { return }
        if player.rate != 0 { player.pause() }
        if count > 0, item.canStepForward { item.step(byCount: count); presentOSD(L10n.pick("下一帧", "Next Frame")) }
        if count < 0, item.canStepBackward { item.step(byCount: count); presentOSD(L10n.pick("上一帧", "Prev Frame")) }
    }

    func adjustVolume(by delta: Float) {
        pokeHUD()
        guard let player else { return }
        if player.isMuted && delta > 0 { player.isMuted = false }
        let next = min(1.0, max(0.0, player.volume + delta))
        player.volume = next
        presentOSD(L10n.pick("音量 \(Int((next * 100).rounded()))%", "Volume \(Int((next * 100).rounded()))%"))
    }

    func toggleMute() {
        pokeHUD()
        guard let player else { return }
        player.isMuted.toggle()
        presentOSD(player.isMuted ? L10n.pick("已静音", "Muted") : L10n.pick("取消静音", "Unmuted"))
    }

    func setRate(_ newValue: Float) {
        preferredRate = newValue; activeRate = newValue; pokeHUD()
        if let player {
            player.defaultRate = newValue
            if player.timeControlStatus == .playing || player.rate != 0 { player.rate = newValue }
        }
        presentOSD(L10n.pick("倍速 \(PlayerRateHelper.format(newValue))", "Speed \(PlayerRateHelper.format(newValue))"))
    }

    func resetRate() {
        preferredRate = 1.0; activeRate = 1.0; pokeHUD()
        if let player {
            player.defaultRate = 1.0
            if player.timeControlStatus == .playing || player.rate != 0 { player.rate = 1.0 }
        }
        presentOSD(L10n.pick("已还原 1.0× 原速", "Restored 1.0× Speed"))
    }

    func stepEpisode(by delta: Int) {
        guard playlistURLs.count > 1, let active = currentURL else { return }
        let idx = playlistURLs.firstIndex(of: active) ?? 0
        load(url: playlistURLs[(idx + delta + playlistURLs.count) % playlistURLs.count])
    }

    func pokeHUD() {
        if !showHUD { withAnimation(.easeOut(duration: 0.16)) { showHUD = true } }
        scheduleHUDHide()
    }

    func toggleEpisodeDrawer() {
        withAnimation(.easeInOut(duration: 0.2)) { showEpisodeDrawer.toggle() }
        pokeHUD()
    }

    func openInExternalPlayer(fallback: URL) {
        player?.pause(); PreviewPlaybackRegistry.shared.pauseAll()
        let target = currentURL ?? fallback
        let iinaURL = URL(fileURLWithPath: "/Applications/IINA.app")
        if FileManager.default.fileExists(atPath: iinaURL.path) {
            NSWorkspace.shared.open([target], withApplicationAt: iinaURL, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(target)
        }
    }

    func stop() {
        loadTask?.cancel(); loadTask = nil; loadingDelayTask?.cancel(); loadingDelayTask = nil
        hudHideTask?.cancel(); hudHideTask = nil; osdHideTask?.cancel(); osdHideTask = nil
        stopPlayerOnly(); cleanupTempFile()
    }

    private func presentOSD(_ text: String) {
        osdMessage = text; osdHideTask?.cancel()
        osdHideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1150))
            guard !Task.isCancelled, let self else { return }
            withAnimation(.easeOut(duration: 0.2)) { self.osdMessage = nil }
        }
    }

    private func installObservers(for avPlayer: AVPlayer, item: AVPlayerItem) {
        playerCancellables.removeAll()
        avPlayer.publisher(for: \.rate, options: [.new]).receive(on: RunLoop.main).sink { [weak self] newRate in
            guard let self else { return }
            if newRate != 0 {
                if abs(self.activeRate - newRate) > 0.005 { self.activeRate = newRate }
                if newRate > 0 && newRate <= 3.0 && PlayerRateHelper.presets.contains(where: { abs($0 - newRate) < 0.02 }) {
                    self.preferredRate = newRate
                }
            } else if self.activeRate < 0 || self.activeRate > 3.0 {
                self.activeRate = self.preferredRate
            }
        }.store(in: &playerCancellables)

        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.autoPlayNext, self.playlistURLs.count > 1 else { return }
                self.stepEpisode(by: 1)
            }
        }
    }

    private func scheduleHUDHide() {
        hudHideTask?.cancel()
        hudHideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.8))
            guard !Task.isCancelled, let self else { return }
            if self.player?.timeControlStatus == .playing && !self.showEpisodeDrawer && !self.showShortcutPopover {
                withAnimation(.easeOut(duration: 0.28)) { self.showHUD = false }
            }
        }
    }

    private func stopPlayerOnly() {
        playerCancellables.removeAll()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver); self.endObserver = nil }
        player?.pause(); player?.replaceCurrentItem(with: nil); player = nil
    }

    private func cleanupTempFile() {
        if let tempRemuxURL { try? FileManager.default.removeItem(at: tempRemuxURL); self.tempRemuxURL = nil }
    }
}

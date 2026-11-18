import AppKit
import AVKit
import Combine
import CoreMedia
import LucentCore
import SwiftUI

@MainActor
private final class InlinePreviewUIState: ObservableObject {
    @Published var activeRate: Float = 1.0
    @Published var resetTrigger: Int = 0
    @Published var osdText: String?
    private var hideTask: Task<Void, Never>?

    func showOSD(_ msg: String) {
        osdText = msg
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(950))
            guard !Task.isCancelled, let self, self.osdText == msg else { return }
            self.osdText = nil
        }
    }
}

struct InlinePreviewMediaPlayerBox: View {
    let url: URL
    @StateObject private var ui = InlinePreviewUIState()

    var body: some View {
        ZStack(alignment: .top) {
            InlineAVPlayerRepresentable(
                url: url,
                resetTrigger: ui.resetTrigger,
                onRateChanged: { ui.activeRate = $0 },
                onOSD: { ui.showOSD($0) }
            )
            .clipShape(RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))

            VStack(spacing: 6) {
                if PlayerRateHelper.isNonUnit(ui.activeRate) {
                    HStack {
                        Spacer()
                        PlayerResetSpeedPill(rateText: PlayerRateHelper.format(ui.activeRate), compact: true) {
                            ui.resetTrigger &+= 1
                        }
                    }
                    .padding(.top, 8).padding(.trailing, 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
                if let osdText = ui.osdText {
                    PlayerOSDToastView(text: osdText)
                        .padding(.top, PlayerRateHelper.isNonUnit(ui.activeRate) ? 2 : 10)
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
            }
        }
        .animation(.easeOut(duration: 0.16), value: PlayerRateHelper.isNonUnit(ui.activeRate))
    }
}

struct InlineAVPlayerRepresentable: NSViewRepresentable {
    let url: URL
    var resetTrigger: Int = 0
    var onRateChanged: ((Float) -> Void)? = nil
    var onOSD: ((String) -> Void)? = nil

    @MainActor
    final class Coordinator {
        let registryToken = UUID()
        var currentURL: URL?
        var lastResetTrigger: Int = 0
        var preferredRate: Float = 1.0
        var loadTask: Task<Void, Never>?
        var cancellables = Set<AnyCancellable>()
        var onRateChanged: ((Float) -> Void)?
        var onOSD: ((String) -> Void)?
        weak var boundView: InteractiveAVPlayerView?

        func load(url: URL, resetTrigger: Int, into view: InteractiveAVPlayerView) {
            boundView = view
            if resetTrigger != lastResetTrigger {
                lastResetTrigger = resetTrigger
                resetPlaybackSpeed()
            }
            if let existingPlayer = view.player {
                PreviewPlaybackRegistry.shared.register(token: registryToken, player: existingPlayer)
            }
            guard currentURL != url else { return }
            currentURL = url
            preferredRate = 1.0
            onRateChanged?(1.0)
            loadTask?.cancel()
            cancellables.removeAll()
            view.player?.pause()
            view.player?.replaceCurrentItem(with: nil)
            let epochAtStart = PreviewPlaybackRegistry.shared.pauseEpoch
            loadTask = Task { [weak self, weak view] in
                let resolved = await VideoPlaybackCompat.preparePlayback(for: url, allowFFmpegRemux: false)
                guard !Task.isCancelled, let self, let view, self.currentURL == url else {
                    if case .ready(_, _, let temp) = resolved, let temp {
                        try? FileManager.default.removeItem(at: temp)
                    }
                    return
                }
                let activePlayer: AVPlayer
                switch resolved {
                case .ready(let item, _, _):
                    if let existing = view.player {
                        existing.replaceCurrentItem(with: item)
                        activePlayer = existing
                    } else {
                        let created = AVPlayer(playerItem: item)
                        view.player = created
                        activePlayer = created
                    }
                case .unsupported:
                    let created = AVPlayer(url: url)
                    view.player = created
                    activePlayer = created
                }
                self.observeRate(on: activePlayer)
                PreviewPlaybackRegistry.shared.register(token: self.registryToken, player: activePlayer)
                if PreviewPlaybackRegistry.shared.pauseEpoch != epochAtStart {
                    activePlayer.pause()
                }
            }
        }

        func handleCommand(_ cmd: PlayerKeyboardCommand) -> Bool {
            guard let player = boundView?.player else { return false }
            switch cmd {
            case .togglePlayPause:
                if player.timeControlStatus == .playing || player.rate != 0 {
                    player.pause(); onOSD?("已暂停")
                } else {
                    let r = preferredRate > 0 ? preferredRate : 1.0
                    player.defaultRate = r
                    player.playImmediately(atRate: r)
                    onOSD?("播放")
                }
                return true
            case .seekRelative(let delta):
                let next = max(0, player.currentTime().seconds + delta)
                PlayerRateHelper.seekPreservingState(player: player, targetSeconds: next, preferredRate: preferredRate)
                onOSD?("\(delta >= 0 ? "+" : "")\(Int(delta))s")
                return true
            case .adjustVolume(let delta):
                if player.isMuted && delta > 0 { player.isMuted = false }
                let next = min(1.0, max(0.0, player.volume + delta))
                player.volume = next
                onOSD?("音量 \(Int((next * 100).rounded()))%")
                return true
            case .toggleMute:
                player.isMuted.toggle()
                onOSD?(player.isMuted ? "已静音" : "取消静音")
                return true
            case .stepSpeed(let dir):
                let current = player.rate > 0 ? player.rate : preferredRate
                applyRate(PlayerRateHelper.steppedRate(from: current, delta: dir), to: player)
                return true
            case .resetSpeed:
                resetPlaybackSpeed(); return true
            case .frameStep(let frames):
                if player.rate != 0 { player.pause() }
                if frames > 0, player.currentItem?.canStepForward == true { player.currentItem?.step(byCount: frames) }
                if frames < 0, player.currentItem?.canStepBackward == true { player.currentItem?.step(byCount: frames) }
                return true
            default:
                return false
            }
        }

        private func applyRate(_ rate: Float, to player: AVPlayer) {
            preferredRate = rate
            player.defaultRate = rate
            if player.timeControlStatus == .playing || player.rate != 0 { player.rate = rate }
            onRateChanged?(rate)
            onOSD?("倍速 \(PlayerRateHelper.format(rate))")
        }

        func resetPlaybackSpeed() {
            preferredRate = 1.0
            if let player = boundView?.player {
                player.defaultRate = 1.0
                if player.timeControlStatus == .playing || player.rate != 0 { player.rate = 1.0 }
            }
            onRateChanged?(1.0)
            onOSD?("已还原 1.0×")
        }

        private func observeRate(on player: AVPlayer) {
            cancellables.removeAll()
            player.publisher(for: \.rate, options: [.new])
                .receive(on: RunLoop.main)
                .sink { [weak self] newRate in
                    guard let self else { return }
                    if newRate != 0 {
                        if newRate > 0 && newRate <= 3.0 && PlayerRateHelper.presets.contains(where: { abs($0 - newRate) < 0.02 }) {
                            self.preferredRate = newRate
                        }
                        self.onRateChanged?(newRate)
                    } else {
                        self.onRateChanged?(self.preferredRate != 1.0 ? self.preferredRate : 1.0)
                    }
                }
                .store(in: &cancellables)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> InteractiveAVPlayerView {
        let view = InteractiveAVPlayerView()
        view.capturesAllWindowKeys = false
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        context.coordinator.onRateChanged = onRateChanged
        context.coordinator.onOSD = onOSD
        view.onCommand = { [weak coord = context.coordinator] cmd in coord?.handleCommand(cmd) ?? false }
        context.coordinator.load(url: url, resetTrigger: resetTrigger, into: view)
        return view
    }

    func updateNSView(_ nsView: InteractiveAVPlayerView, context: Context) {
        context.coordinator.onRateChanged = onRateChanged
        context.coordinator.onOSD = onOSD
        context.coordinator.load(url: url, resetTrigger: resetTrigger, into: nsView)
    }

    static func dismantleNSView(_ nsView: InteractiveAVPlayerView, coordinator: Coordinator) {
        PreviewPlaybackRegistry.shared.unregister(token: coordinator.registryToken)
        coordinator.loadTask?.cancel(); coordinator.loadTask = nil
        coordinator.cancellables.removeAll()
        nsView.cleanupKeyMonitor()
        nsView.player?.pause()
        nsView.player?.replaceCurrentItem(with: nil)
        nsView.player = nil
    }
}

import AppKit
import AVKit
import LucentCore
import SwiftUI

struct CinemaVideoPlayerSheet: View {
    let initialURL: URL
    let siblingURLs: [URL]
    let windowKey: String
    let onClose: () -> Void
    @StateObject private var state = CinemaPlayerController()
    @ObservedObject private var windowPins = WindowLevelStore.shared

    private var activeURL: URL { state.currentURL ?? initialURL }
    private var isCompact: Bool { windowPins.isCompact(windowKey) }
    private var isAudioTrack: Bool {
        state.metadata?.isAudioOnly == true || MediaClassifier.classify(url: activeURL, isDirectory: false) == .audio
    }
    private var hudVisible: Bool {
        isAudioTrack || state.showHUD || state.isLoading || state.errorReason != nil || state.showEpisodeDrawer || state.showShortcutPopover
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Color(red: 0.04, green: 0.045, blue: 0.06).ignoresSafeArea()
            if let player = state.player {
                CinemaPlayerNSView(
                    player: player,
                    onMouseActivity: { state.pokeHUD() },
                    onCommand: { cmd, win in state.handleKeyboardCommand(cmd, window: win, onClose: onClose) }
                )
                .ignoresSafeArea()
            }
            if isAudioTrack && !state.isLoading && state.errorReason == nil {
                audioTrackBackdropCard.allowsHitTesting(false)
            }
            if state.isLoading {
                CinemaLoadingOverlayCard(fileName: activeURL.lastPathComponent) {
                    state.openInExternalPlayer(fallback: initialURL)
                }
            }
            if let reason = state.errorReason {
                CinemaErrorOverlayCard(reason: reason, activeURL: activeURL) {
                    state.openInExternalPlayer(fallback: initialURL)
                }
            }
            if state.showEpisodeDrawer && !isCompact {
                CinemaEpisodeDrawerView(state: state, activeURL: activeURL)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            VStack(spacing: 0) {
                if hudVisible { topHUDBar.transition(.opacity.combined(with: .move(edge: .top))) }
                if let osd = state.osdMessage {
                    PlayerOSDToastView(text: osd)
                        .padding(.top, hudVisible ? 6 : 20)
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                }
                Spacer(minLength: 0)
                if state.isNonUnitSpeed {
                    PlayerResetSpeedPill(
                        rateText: PlayerRateHelper.format(state.effectiveDisplayRate),
                        compact: isCompact
                    ) { state.resetRate() }
                    .padding(.bottom, isCompact ? 54 : 68)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .frame(maxWidth: .infinity)
            .ignoresSafeArea(.container, edges: .top)
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 460, minHeight: 260)
        .onAppear { state.configureAndLoad(initialURL: initialURL, providedSiblings: siblingURLs, startCompact: isCompact) }
        .onDisappear { state.stop(); _ = onClose }
    }

    private var audioTrackBackdropCard: some View {
        VStack(spacing: 12) {
            SquircleBadge(symbol: "waveform", topColor: .cyan, bottomColor: .indigo, size: isCompact ? 48 : 64)
                .shadow(color: .cyan.opacity(0.24), radius: 14, y: 4)
            Text(activeURL.deletingPathExtension().lastPathComponent)
                .font(isCompact ? .callout.weight(.semibold) : .title3.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            if let badge = state.metadata?.codecBadge {
                Text(badge)
                    .font(.caption2.weight(.semibold)).foregroundStyle(.cyan)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Color.cyan.opacity(0.16), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var topHUDBar: some View {
        let playlist = state.playlistURLs
        let idx = playlist.firstIndex(of: activeURL) ?? 0
        let subtitle = "\(activeURL.deletingLastPathComponent().lastPathComponent) · \(idx + 1)/\(max(1, playlist.count))"
        return HStack(spacing: isCompact ? 6 : 8) {
            SquircleBadge(symbol: isAudioTrack ? "waveform" : "film.fill", topColor: .cyan, bottomColor: .indigo, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(activeURL.lastPathComponent).font(.callout.weight(.semibold)).foregroundStyle(.white).lineLimit(1).truncationMode(.middle)
                    if !isCompact, let badge = state.metadata?.codecBadge {
                        Text(badge).font(.system(size: 10, weight: .semibold)).foregroundStyle(.cyan)
                            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 7).padding(.vertical, 2).background(Color.cyan.opacity(0.16), in: Capsule())
                    }
                }
                if !isCompact { Text(subtitle).font(.caption2).foregroundStyle(.white.opacity(0.65)).lineLimit(1).truncationMode(.middle) }
            }
            .frame(minWidth: 60, maxWidth: .infinity, alignment: .leading).layoutPriority(-1)
            ViewThatFits(in: .horizontal) {
                topHUDControls(playlistCount: playlist.count, compactLabels: false)
                topHUDControls(playlistCount: playlist.count, compactLabels: true)
            }
            .layoutPriority(1)
        }
        .padding(.leading, 78).padding(.trailing, 14).padding(.top, 9).padding(.bottom, 16)
        .background(LinearGradient(colors: [Color.black.opacity(0.84), Color.black.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom))
    }

    private func topHUDControls(playlistCount: Int, compactLabels: Bool) -> some View {
        HStack(spacing: compactLabels ? 4 : 5) {
            if playlistCount > 1 && !isCompact { CinemaCapsuleButton(symbol: "backward.end.fill", helpText: "上一首/集 (P / ⇧←)") { state.stepEpisode(by: -1) } }
            if !isCompact {
                CinemaCapsuleButton(symbol: "gobackward.5", helpText: "快退 5 秒 (←)") { state.seek(by: -5) }
                CinemaCapsuleButton(symbol: "goforward.5", helpText: "快进 5 秒 (→)") { state.seek(by: 5) }
            }
            if playlistCount > 1 && !isCompact { CinemaCapsuleButton(symbol: "forward.end.fill", helpText: "下一首/集 (N / ⇧→)") { state.stepEpisode(by: 1) } }
            if !isCompact {
                rateMenuButton
                if state.isNonUnitSpeed {
                    CinemaCapsuleButton(symbol: "arrow.counterclockwise", label: "1×", active: true, helpText: "一键还原 1.0× 原速 (R)") { state.resetRate() }
                }
                let listTitle = compactLabels ? "\(playlistCount)" : "播放列表 (\(playlistCount))"
                CinemaCapsuleButton(symbol: "list.bullet", label: listTitle, active: state.showEpisodeDrawer, helpText: "同目录播放列表 (L)") { state.toggleEpisodeDrawer() }
                shortcutHelpButton
            }
            WindowPinPillButton(key: windowKey, title: "置顶", darkAppearance: true)
            let pipTitle: String? = compactLabels && !isCompact ? nil : (isCompact ? "还原" : "小窗")
            CinemaCapsuleButton(symbol: isCompact ? "pip.exit" : "pip.enter", label: pipTitle, active: isCompact) {
                if !isCompact { state.showEpisodeDrawer = false }
                windowPins.toggleCompact(forKey: windowKey)
            }
            if !isCompact {
                CinemaCapsuleButton(symbol: "arrow.up.forward.app", label: compactLabels ? nil : "外部播放") { state.openInExternalPlayer(fallback: initialURL) }
            }
        }
    }

    private var rateMenuButton: some View {
        let nonUnit = state.isNonUnitSpeed
        return Menu {
            if nonUnit {
                Button("↺ 还原 1.0× 原速 (R)") { state.resetRate() }
                Divider()
            }
            ForEach(PlayerRateHelper.presets, id: \.self) { r in
                Button { state.setRate(r) } label: {
                    if abs(state.effectiveDisplayRate - r) < 0.02 { Label(PlayerRateHelper.format(r), systemImage: "checkmark") }
                    else { Text(PlayerRateHelper.format(r)) }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(PlayerRateHelper.format(state.effectiveDisplayRate))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).opacity(0.75)
            }
            .font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(.white)
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(nonUnit ? Color.cyan.opacity(0.34) : Color.white.opacity(0.13), in: Capsule())
            .overlay { Capsule().strokeBorder(nonUnit ? Color.cyan.opacity(0.65) : Color.white.opacity(0.18), lineWidth: 0.8) }
        }
        .menuIndicator(.hidden).buttonStyle(.plain).fixedSize(horizontal: true, vertical: false)
    }

    private var shortcutHelpButton: some View {
        CinemaCapsuleButton(symbol: "keyboard", active: state.showShortcutPopover, helpText: "查看播放快捷键") {
            state.showShortcutPopover.toggle(); state.pokeHUD()
        }
        .popover(isPresented: $state.showShortcutPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text("播放快捷键").font(.caption.weight(.bold))
                ForEach([
                    ("Space", "播放 / 暂停"), ("← / →", "快退 / 快进 5 秒（不暂停）"),
                    ("⌥← / ⌥→", "快退 / 快进 15 秒"), ("↑ / ↓ · M", "音量调节 · 静音切换"),
                    ("[ / ]", "减速 / 加速倍速"), ("R / Z / 1", "一键还原 1.0× 原速"),
                    ("双击画面 / F", "全屏切换"), ("P / N · L", "上/下一集 · 播放列表")
                ], id: \.0) { row in
                    HStack {
                        Text(row.0).font(.caption2.monospaced().weight(.semibold)).foregroundStyle(.cyan)
                        Spacer(minLength: 8)
                        Text(row.1).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12).frame(width: 236)
        }
    }
}

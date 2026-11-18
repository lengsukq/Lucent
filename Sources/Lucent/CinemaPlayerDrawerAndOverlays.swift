import AppKit
import AVKit
import LucentCore
import SwiftUI

struct CinemaLoadingOverlayCard: View {
    let fileName: String
    let onOpenExternal: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.regular)
            Text("正在无损快封兼容媒体流…").font(.callout.weight(.semibold)).foregroundStyle(.white)
            Text(fileName).font(.caption).foregroundStyle(.white.opacity(0.68)).lineLimit(1)
            Button("使用外部播放器打开", action: onOpenExternal).buttonStyle(.borderedProminent).controlSize(.small)
        }
        .padding(22).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 0.9) }
    }
}

struct CinemaErrorOverlayCard: View {
    let reason: String
    let activeURL: URL
    let onOpenExternal: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            SquircleBadge(symbol: "exclamationmark.triangle.fill", topColor: .orange, bottomColor: .red, size: 42)
            Text(reason).font(.callout).foregroundStyle(.white).multilineTextAlignment(.center).frame(maxWidth: 380)
            HStack(spacing: 10) {
                Button("使用外部播放器打开", action: onOpenExternal).buttonStyle(.borderedProminent)
                Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([activeURL]) }.buttonStyle(.bordered)
            }
        }
        .padding(24).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 0.9) }
    }
}

struct CinemaEpisodeDrawerView: View {
    @ObservedObject var state: CinemaPlayerController
    let activeURL: URL

    var body: some View {
        let items = state.filteredPlaylist
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("同目录列表 (\(state.playlistURLs.count))").font(.callout.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                Spacer(minLength: 4)
                Button { state.autoPlayNext.toggle() } label: {
                    Text("连播").font(.caption2.weight(.semibold)).foregroundStyle(state.autoPlayNext ? .white : .white.opacity(0.6))
                        .lineLimit(1).fixedSize(horizontal: true, vertical: false).padding(.horizontal, 8).padding(.vertical, 3)
                        .background(state.autoPlayNext ? Color.cyan.opacity(0.38) : Color.white.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain).fixedSize(horizontal: true, vertical: false).help("播完当前曲目后自动播放同目录下一项")
                Button { state.toggleEpisodeDrawer() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.7)) }
                    .buttonStyle(.plain).fixedSize()
            }
            if state.playlistURLs.count > 4 {
                TextField("筛选同目录曲目…", text: $state.episodeFilter)
                    .textFieldStyle(.plain).font(.caption).foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 0.7) }
            }
            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(items, id: \.url) { item in
                        let selected = item.url == activeURL
                        Button { state.load(url: item.url) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: selected ? "speaker.wave.2.fill" : "play.circle")
                                    .font(.caption).foregroundStyle(selected ? .cyan : .white.opacity(0.65))
                                Text("\(item.index + 1). \(item.url.lastPathComponent)")
                                    .font(.caption.weight(selected ? .semibold : .regular))
                                    .foregroundStyle(.white).lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(selected ? Color.cyan.opacity(0.24) : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay { if selected { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.cyan.opacity(0.45), lineWidth: 0.8) } }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14).frame(width: 268).frame(maxHeight: .infinity)
        .background(.ultraThinMaterial, in: UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 0, style: .continuous))
        .overlay {
            UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 0, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.8)
        }
        .padding(.top, 52)
    }
}

struct CinemaCapsuleButton: View {
    var symbol: String? = nil; var label: String? = nil; var active: Bool = false; var helpText: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)) }
                if let label { Text(label).font(.caption.weight(.medium)).lineLimit(1) }
            }
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(.white).padding(.horizontal, label == nil ? 9 : 10).padding(.vertical, 5)
            .background(active ? Color.cyan.opacity(0.32) : Color.white.opacity(0.13), in: Capsule())
            .overlay { Capsule().strokeBorder(active ? Color.cyan.opacity(0.55) : Color.white.opacity(0.18), lineWidth: 0.7) }
        }
        .buttonStyle(.plain).fixedSize(horizontal: true, vertical: false).help(helpText)
    }
}

struct CinemaPlayerNSView: NSViewRepresentable {
    let player: AVPlayer
    let onMouseActivity: () -> Void
    let onCommand: (PlayerKeyboardCommand, NSWindow?) -> Bool

    func makeNSView(context: Context) -> InteractiveAVPlayerView {
        let view = InteractiveAVPlayerView()
        view.capturesAllWindowKeys = true; view.controlsStyle = .floating; view.videoGravity = .resizeAspect
        view.allowsPictureInPicturePlayback = true; view.showsFullScreenToggleButton = true
        view.onMouseActivity = onMouseActivity; view.onCommand = { [weak view] cmd in onCommand(cmd, view?.window) }
        view.player = player; return view
    }

    func updateNSView(_ nsView: InteractiveAVPlayerView, context: Context) {
        nsView.onMouseActivity = onMouseActivity
        nsView.onCommand = { [weak nsView] cmd in onCommand(cmd, nsView?.window) }
        if nsView.player !== player { nsView.player = player }
    }

    static func dismantleNSView(_ nsView: InteractiveAVPlayerView, coordinator: ()) {
        nsView.cleanupKeyMonitor(); nsView.player?.pause(); nsView.player = nil
    }
}

import AppKit
import AVFoundation
import LucentCore
import SwiftUI

@MainActor
private final class VideoClipboardPreviewState: ObservableObject {
    @Published var posterImage: NSImage?
    @Published var durationText: String?
    @Published var resolutionText: String?
    private var loadedPath: String?
    private var loadTask: Task<Void, Never>?

    func loadIfNeeded(url: URL) {
        let stdPath = url.standardizedFileURL.path
        guard loadedPath != stdPath else { return }
        loadedPath = stdPath
        posterImage = nil; durationText = nil; resolutionText = nil
        loadTask?.cancel()
        loadTask = Task {
            let meta = await Self.extractPosterAndMetadata(at: url)
            guard !Task.isCancelled, self.loadedPath == stdPath else { return }
            if let cg = meta.poster {
                self.posterImage = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }
            self.durationText = meta.durationText
            self.resolutionText = meta.resolutionText
        }
    }

    func cancel() {
        loadTask?.cancel()
        loadTask = nil
    }

    private nonisolated static func extractPosterAndMetadata(at url: URL) async -> (poster: CGImage?, durationText: String?, resolutionText: String?) {
        guard FileManager.default.fileExists(atPath: url.path) else { return (nil, nil, nil) }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 420)
        let probeTime = CMTime(seconds: 0.25, preferredTimescale: 600)
        var poster = (try? await generator.image(at: probeTime))?.image
        if poster == nil {
            poster = (try? await generator.image(at: .zero))?.image
        }
        let resText = poster.map { "\($0.width) × \($0.height)" }
        let duration = (try? await asset.load(.duration)) ?? .zero
        let sec = CMTimeGetSeconds(duration)
        let durText: String?
        if sec.isFinite && sec > 0 {
            let total = Int(sec.rounded())
            durText = String(format: "%02d:%02d", total / 60, total % 60)
        } else {
            durText = nil
        }
        return (poster, durText, resText)
    }
}

struct VideoClipboardLensCard: View {
    let url: URL
    let clip: ClipboardEntry
    let onCopyVideo: () -> Void
    let onPasteVideo: () -> Void
    let onOpenPlayer: () -> Void
    let onTogglePin: () -> Void
    @StateObject private var preview = VideoClipboardPreviewState()

    var body: some View {
        let exists = FileManager.default.fileExists(atPath: url.path)
        let sizeText = FastFormatters.formatFileBytes(
            Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        )
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                if let poster = preview.posterImage {
                    Image(nsImage: poster)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
                        .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
                        .padding(8)
                } else {
                    VStack(spacing: 8) {
                        SquircleBadge(symbol: "film.stack.fill", topColor: .indigo, bottomColor: .cyan, size: 44)
                        Text(exists ? url.lastPathComponent : L10n.pick("源视频文件已不存在", "Source video file missing"))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(LiquidColors.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .padding(12)
                }

                Button(action: onOpenPlayer) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(.white.opacity(0.92))
                        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
                .disabled(!exists)
            }
            .frame(maxWidth: .infinity, minHeight: 162, maxHeight: 206)
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 5) {
                    if let res = preview.resolutionText {
                        badgeCapsule(res)
                    }
                    if let dur = preview.durationText {
                        badgeCapsule(dur)
                    }
                    badgeCapsule(sizeText)
                }
                .padding(8)
            }
            .background(Color.black.opacity(0.14), in: RoundedRectangle(cornerRadius: LiquidRadii.card, style: .continuous))
            .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)

            VStack(alignment: .leading, spacing: 3) {
                Text(clip.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LiquidColors.textPrimary)
                    .lineLimit(1)
                Text(url.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(LiquidColors.textSecondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlassCard(cornerRadius: LiquidRadii.row, solidReadable: true)

            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Button(action: onCopyVideo) {
                        Label(L10n.pick("复制视频 ↩", "Copy Video ↩"), systemImage: "doc.on.doc")
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: true))
                    Button(action: onPasteVideo) {
                        Label(L10n.pick("直接粘贴 ⇧↩", "Paste ⇧↩"), systemImage: "arrow.turn.down.left")
                    }
                    .buttonStyle(GlassPillButtonStyle())
                }
                HStack(spacing: 6) {
                    Button(L10n.pick("影院置顶", "Cinema Player"), action: onOpenPlayer)
                        .buttonStyle(GlassPillButtonStyle())
                        .disabled(!exists)
                    Button(L10n.pick("访达 ⌘R", "Finder ⌘R")) {
                        NSWorkspace.shared.activateFileViewerSelecting(clip.fileURLs.isEmpty ? [url] : clip.fileURLs)
                    }
                    .buttonStyle(GlassPillButtonStyle())
                    Button(clip.isPinned ? L10n.pick("取消收藏", "Unpin") : L10n.pick("收藏", "Pin"), action: onTogglePin)
                        .buttonStyle(GlassPillButtonStyle())
                }
            }
        }
        .onAppear { preview.loadIfNeeded(url: url) }
        .onChange(of: url) { _, newURL in preview.loadIfNeeded(url: newURL) }
        .onDisappear { preview.cancel() }
    }

    private func badgeCapsule(_ text: String) -> some View {
        Text(text)
            .font(.caption2.monospacedDigit().weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.black.opacity(0.60), in: Capsule(style: .continuous))
    }
}

struct FileClipboardLensCard: View {
    let url: URL
    let clip: ClipboardEntry
    let onCopyFile: () -> Void
    let onPasteFile: () -> Void
    let onTogglePin: () -> Void

    var body: some View {
        let urls = clip.fileURLs.isEmpty ? [url] : clip.fileURLs
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let icon = IconCache.shared.fileIcon(isDirectory: isDir, extensionLowercased: url.pathExtension.lowercased())
        let totalBytes = urls.reduce(Int64(0)) { acc, item in
            acc + Int64((try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 8) {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                Text(clip.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(LiquidColors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                HStack(spacing: 6) {
                    LiquidStatusPill(title: urls.count > 1 ? "\(urls.count) 项" : clip.payloadKind.badgeTitle, tint: .cyan)
                    if totalBytes > 0 {
                        LiquidStatusPill(title: FastFormatters.formatFileBytes(totalBytes), tint: .indigo)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(urls.prefix(8), id: \.path) { item in
                        Text(item.path)
                            .font(.caption2.monospaced())
                            .foregroundStyle(LiquidColors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(10)
            .frame(maxHeight: 110)
            .liquidGlassCard(cornerRadius: LiquidRadii.row, solidReadable: true)

            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Button(action: onCopyFile) {
                        Label(L10n.pick("复制文件 ↩", "Copy File ↩"), systemImage: "doc.on.doc")
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: true))
                    Button(action: onPasteFile) {
                        Label(L10n.pick("直接粘贴 ⇧↩", "Paste ⇧↩"), systemImage: "arrow.turn.down.left")
                    }
                    .buttonStyle(GlassPillButtonStyle())
                }
                HStack(spacing: 6) {
                    Button(L10n.pick("访达 ⌘R", "Finder ⌘R")) {
                        NSWorkspace.shared.activateFileViewerSelecting(urls)
                    }
                    .buttonStyle(GlassPillButtonStyle())
                    Button(clip.isPinned ? L10n.pick("取消收藏", "Unpin") : L10n.pick("收藏", "Pin"), action: onTogglePin)
                        .buttonStyle(GlassPillButtonStyle())
                }
            }
        }
    }
}

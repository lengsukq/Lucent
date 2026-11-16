import LumakeyFoundation; import LumakeySearch; import LumakeyMedia; import LumakeySystem
import AppKit
import CoreGraphics
import Foundation

public enum ClipboardCategory: String, CaseIterable, Identifiable, Sendable {
    case all = "全部"
    case text = "文本"
    case image = "图片"
    case video = "视频"
    case file = "文件"
    case pinned = "收藏"

    public var id: String { rawValue }

    public var localizedTitle: String {
        switch self {
        case .all: L10n.pick("全部", "All")
        case .text: L10n.pick("文本", "Text")
        case .image: L10n.pick("图片", "Images")
        case .video: L10n.pick("视频", "Videos")
        case .file: L10n.pick("文件", "Files")
        case .pinned: L10n.pick("收藏", "Pinned")
        }
    }
}

public enum ClipboardPayloadKind: Sendable, Hashable {
    case text
    case colorHex(String)
    case image(URL, CGSize)
    case video(URL)
    case file(URL)

    public var badgeTitle: String {
        switch self {
        case .text: L10n.pick("文本", "Text")
        case .colorHex: L10n.pick("色值", "Color")
        case .image: L10n.pick("图片", "Image")
        case .video: L10n.pick("视频", "Video")
        case .file: L10n.pick("文件", "File")
        }
    }
}

public struct ClipboardEntry: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let title: String
    public let subtitle: String
    public let textValue: String?
    public let fileURL: URL?
    public let fileURLs: [URL]
    public let capturedAt: Date
    public var isPinned: Bool
    public let payloadKind: ClipboardPayloadKind

    public init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        textValue: String? = nil,
        fileURL: URL? = nil,
        fileURLs: [URL]? = nil,
        capturedAt: Date = Date(),
        isPinned: Bool = false,
        payloadKind: ClipboardPayloadKind
    ) {
        let resolvedURLs: [URL]
        if let fileURLs, !fileURLs.isEmpty {
            resolvedURLs = fileURLs.map(\.standardizedFileURL)
        } else if let fileURL {
            resolvedURLs = [fileURL.standardizedFileURL]
        } else {
            switch payloadKind {
            case .image(let u, _), .video(let u), .file(let u):
                resolvedURLs = [u.standardizedFileURL]
            case .text, .colorHex:
                resolvedURLs = []
            }
        }
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.textValue = textValue
        self.fileURL = resolvedURLs.first
        self.fileURLs = resolvedURLs
        self.capturedAt = capturedAt
        self.isPinned = isPinned
        self.payloadKind = payloadKind
    }
}

public enum ClipboardService {
    public static let concealedTypes: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "com.agilebits.onepassword"
    ]

    @MainActor
    public static func captureCurrent(from pasteboard: NSPasteboard = .general) -> ClipboardEntry? {
        ClipboardPasteboardIO.captureCurrent(from: pasteboard)
    }

    public static func insert(_ entry: ClipboardEntry, into list: [ClipboardEntry], maxUnpinned: Int = 80) -> [ClipboardEntry] {
        var next = list
        var preservedPin = entry.isPinned
        var removed: [ClipboardEntry] = []
        let entryPaths = entry.fileURLs.map(\.path)
        next.removeAll { existing in
            let existingPaths = existing.fileURLs.map(\.path)
            let match = (entry.textValue != nil && existing.textValue == entry.textValue)
                || (!entryPaths.isEmpty && existingPaths == entryPaths)
            if match && existing.isPinned { preservedPin = true }
            if match && Set(existingPaths) != Set(entryPaths) {
                removed.append(existing)
            }
            return match
        }
        var updated = entry
        updated.isPinned = preservedPin
        next.insert(updated, at: 0)

        var unpinnedSeen = 0
        var kept: [ClipboardEntry] = []
        kept.reserveCapacity(next.count)
        for item in next {
            if item.isPinned {
                kept.append(item)
            } else {
                unpinnedSeen += 1
                if unpinnedSeen <= maxUnpinned {
                    kept.append(item)
                } else {
                    removed.append(item)
                }
            }
        }
        let activePaths = Set(kept.flatMap { $0.fileURLs.map(\.path) })
        let safeToRemove = removed.filter { candidate in
            candidate.fileURLs.allSatisfy { !activePaths.contains($0.path) }
        }
        removeTempFiles(for: safeToRemove)
        return kept
    }

    public static func promote(_ entry: ClipboardEntry, in list: [ClipboardEntry]) -> [ClipboardEntry] {
        guard let idx = list.firstIndex(where: { $0.id == entry.id }), idx > 0 else { return list }
        var next = list
        let picked = next.remove(at: idx)
        next.insert(picked, at: 0)
        return next
    }

    public static func removeTempFiles(for entries: [ClipboardEntry]) {
        let clipRoot = ClipboardPasteboardIO.clipboardTempDirectory().standardizedFileURL.path
        let fm = FileManager.default
        for item in entries {
            for url in item.fileURLs {
                let std = url.standardizedFileURL
                guard std.path.hasPrefix(clipRoot + "/") else { continue }
                try? fm.removeItem(at: std)
                let parent = std.deletingLastPathComponent()
                if parent.path != clipRoot && parent.path.hasPrefix(clipRoot + "/") {
                    if ((try? fm.contentsOfDirectory(atPath: parent.path)) ?? []).isEmpty {
                        try? fm.removeItem(at: parent)
                    }
                }
            }
        }
    }

    public static func filter(_ list: [ClipboardEntry], query: String, category: ClipboardCategory) -> [ClipboardEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return list.filter { item in
            let catOK: Bool
            switch category {
            case .all: catOK = true
            case .text: catOK = item.textValue != nil
            case .image:
                if case .image = item.payloadKind { catOK = true } else { catOK = false }
            case .video:
                if case .video = item.payloadKind { catOK = true } else { catOK = false }
            case .file:
                if case .file = item.payloadKind { catOK = true } else { catOK = false }
            case .pinned: catOK = item.isPinned
            }
            guard catOK else { return false }
            guard !needle.isEmpty else { return true }
            return item.title.localizedCaseInsensitiveContains(needle)
                || item.subtitle.localizedCaseInsensitiveContains(needle)
                || (item.textValue?.localizedCaseInsensitiveContains(needle) ?? false)
        }
    }

    @MainActor
    @discardableResult
    public static func copyToPasteboard(_ entry: ClipboardEntry, pasteboard: NSPasteboard = .general) -> Bool {
        ClipboardPasteboardIO.writeToPasteboard(entry, pasteboard: pasteboard)
    }

    public static func parseHexColor(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count == 7, s.hasPrefix("#"),
              s.dropFirst().allSatisfy(\.isHexDigit) else { return nil }
        return s.uppercased()
    }
}

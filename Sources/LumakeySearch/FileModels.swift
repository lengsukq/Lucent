import LumakeyFoundation
import Darwin
import Foundation

public enum FastFormatters {
    public static func formatFileBytes(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 B" }
        if bytes < 1_000 { return "\(bytes) B" }
        if bytes < 1_000_000 {
            let kb = max(1, Int((Double(bytes) / 1_000.0).rounded()))
            return "\(kb) KB"
        }
        if bytes < 1_000_000_000 {
            return String(format: "%.1f MB", Double(bytes) / 1_000_000.0)
        }
        if bytes < 1_000_000_000_000 {
            return String(format: "%.2f GB", Double(bytes) / 1_000_000_000.0)
        }
        return String(format: "%.2f TB", Double(bytes) / 1_000_000_000_000.0)
    }

    public static func formatModificationDate(_ date: Date) -> String {
        guard date != .distantPast else { return "—" }
        var sec = time_t(date.timeIntervalSince1970)
        var local = tm()
        localtime_r(&sec, &local)
        return String(
            format: "%04d-%02d-%02d %02d:%02d",
            Int(local.tm_year) + 1900,
            Int(local.tm_mon) + 1,
            Int(local.tm_mday),
            Int(local.tm_hour),
            Int(local.tm_min)
        )
    }
}

public enum LocationKind: String, Sendable, Hashable {
    case home
    case desktop
    case downloads
    case external
    case network
    case custom

    public var symbolName: String {
        switch self {
        case .home: "house.fill"
        case .desktop: "menubar.dock.rectangle"
        case .downloads: "arrow.down.circle.fill"
        case .external: "externaldrive.fill"
        case .network: "externaldrive.connected.to.line.below.fill"
        case .custom: "folder.fill"
        }
    }
}

public struct LocationItem: Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let url: URL
    public let kind: LocationKind
    public let volumeSummary: VolumeSummary?

    public init(
        name: String,
        url: URL,
        kind: LocationKind,
        volumeSummary: VolumeSummary? = nil
    ) {
        self.id = url.standardizedFileURL.path
        self.name = name
        self.url = url
        self.kind = kind
        self.volumeSummary = volumeSummary
    }
}

public enum PaneSide: String, Sendable {
    case left
    case right
}

public enum ExplorerLayoutMode: String, CaseIterable, Identifiable, Sendable {
    case single
    case dual

    public var id: String { rawValue }
    public var title: String { self == .single ? L10n.pick("单栏", "Single") : L10n.pick("双栏", "Dual") }
}

public enum SortField: String, CaseIterable, Identifiable, Sendable {
    case name
    case modifiedAt
    case createdAt
    case size
    case kind
    case ext

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .name: L10n.pick("名称", "Name")
        case .modifiedAt: L10n.pick("修改时间", "Modified")
        case .createdAt: L10n.pick("创建时间", "Created")
        case .size: L10n.pick("大小", "Size")
        case .kind: L10n.pick("类型", "Kind")
        case .ext: L10n.pick("扩展名", "Extension")
        }
    }
}

public enum WorkspaceDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case list
    case grid
    case compact

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .list: L10n.pick("列表", "List")
        case .grid: L10n.pick("网格", "Grid")
        case .compact: L10n.pick("紧凑", "Compact")
        }
    }

    public var symbolName: String {
        switch self {
        case .list: "list.bullet"
        case .grid: "square.grid.2x2"
        case .compact: "rectangle.grid.2x2"
        }
    }
}

public enum WorkspaceMediaFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case folder
    case image
    case video
    case audio
    case document
    case archive

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .all: L10n.pick("全部", "All")
        case .folder: L10n.pick("文件夹", "Folders")
        case .image: L10n.pick("图片", "Images")
        case .video: L10n.pick("视频", "Videos")
        case .audio: L10n.pick("音频", "Audio")
        case .document: L10n.pick("文档", "Docs")
        case .archive: L10n.pick("压缩包", "Archives")
        }
    }

    public var symbolName: String {
        switch self {
        case .all: "square.grid.2x2"
        case .folder: "folder"
        case .image: "photo"
        case .video: "film"
        case .audio: "waveform"
        case .document: "doc.richtext"
        case .archive: "archivebox"
        }
    }

    public func matches(_ entry: FileEntry) -> Bool {
        switch self {
        case .all: return true
        case .folder: return entry.isDirectory && !entry.isPackage
        case .image: return entry.mediaKind == .image
        case .video: return entry.mediaKind == .video
        case .audio: return entry.mediaKind == .audio
        case .document: return [.markdown, .text, .pdf].contains(entry.mediaKind)
        case .archive: return entry.mediaKind == .archive
        }
    }
}

public enum LumakeySortOrder: String, Sendable {
    case ascending
    case descending

    public var toggled: LumakeySortOrder {
        self == .ascending ? .descending : .ascending
    }
}

public struct FileEntry: Identifiable, Sendable, Hashable {
    public let id: String
    public let url: URL
    public let name: String
    public let isDirectory: Bool
    public let isPackage: Bool
    public let isHidden: Bool
    public let sizeBytes: Int64
    public let modifiedAt: Date
    public let createdAt: Date
    public let extensionLowercased: String
    public let mediaKind: PreviewMediaKind
    public let tags: [String]

    public init(
        url: URL,
        name: String,
        isDirectory: Bool,
        isPackage: Bool = false,
        isHidden: Bool = false,
        sizeBytes: Int64,
        modifiedAt: Date,
        createdAt: Date = .distantPast,
        extensionLowercased: String,
        mediaKind: PreviewMediaKind,
        tags: [String] = []
    ) {
        self.id = url.standardizedFileURL.path
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.isPackage = isPackage
        self.isHidden = isHidden
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
        self.createdAt = createdAt == .distantPast ? modifiedAt : createdAt
        self.extensionLowercased = extensionLowercased
        self.mediaKind = mediaKind
        self.tags = tags
    }

    public var formattedSize: String {
        if isDirectory && !isPackage {
            return "—"
        }
        return FastFormatters.formatFileBytes(sizeBytes)
    }

    public var formattedDate: String {
        FastFormatters.formatModificationDate(modifiedAt)
    }
}

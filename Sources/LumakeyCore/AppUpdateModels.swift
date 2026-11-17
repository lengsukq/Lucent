import Foundation
import LumakeyFoundation

public enum UpdateCheckFrequency: String, Codable, CaseIterable, Identifiable, Sendable {
    case daily
    case onEveryLaunch
    case weekly
    case manualOnly

    public var id: String { rawValue }

    public var intervalSeconds: TimeInterval? {
        switch self {
        case .daily: 86_400
        case .onEveryLaunch: 0
        case .weekly: 604_800
        case .manualOnly: nil
        }
    }

    public var localizedTitle: String {
        switch self {
        case .daily: L10n.pick("每日自动检查", "Daily")
        case .onEveryLaunch: L10n.pick("每次启动时", "Every Launch")
        case .weekly: L10n.pick("每周检查", "Weekly")
        case .manualOnly: L10n.pick("仅手动检查", "Manual Only")
        }
    }

    public func isDue(lastCheckedTimestamp: Double, now: Date = Date()) -> Bool {
        guard let interval = intervalSeconds else { return false }
        if interval <= 0 || lastCheckedTimestamp <= 0 { return true }
        return (now.timeIntervalSince1970 - lastCheckedTimestamp) >= interval
    }
}

public struct AppReleaseInfo: Codable, Sendable, Hashable, Equatable {
    public let tagName: String
    public let normalizedVersion: String
    public let title: String
    public let releaseNotes: String
    public let publishedAtISO8601: String?
    public let isPrerelease: Bool
    public let htmlURL: String
    public let dmgDownloadURL: String?
    public let dmgAssetName: String?
    public let dmgSizeBytes: Int64?
    public let sha256AssetURL: String?

    public init(
        tagName: String,
        normalizedVersion: String? = nil,
        title: String,
        releaseNotes: String,
        publishedAtISO8601: String? = nil,
        isPrerelease: Bool = false,
        htmlURL: String,
        dmgDownloadURL: String? = nil,
        dmgAssetName: String? = nil,
        dmgSizeBytes: Int64? = nil,
        sha256AssetURL: String? = nil
    ) {
        self.tagName = tagName
        self.normalizedVersion = normalizedVersion ?? AppVersionComparator.normalize(tagName)
        self.title = title.isEmpty ? tagName : title
        self.releaseNotes = releaseNotes
        self.publishedAtISO8601 = publishedAtISO8601
        self.isPrerelease = isPrerelease
        self.htmlURL = htmlURL
        self.dmgDownloadURL = dmgDownloadURL
        self.dmgAssetName = dmgAssetName
        self.dmgSizeBytes = dmgSizeBytes
        self.sha256AssetURL = sha256AssetURL
    }
}

public enum AppUpdateCheckOutcome: Sendable, Equatable {
    case upToDate(currentVersion: String, latestVersion: String)
    case updateAvailable(currentVersion: String, release: AppReleaseInfo)
}

public enum AppVersionComparator {
    public static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.first == "v" || s.first == "V" {
            s.removeFirst()
        }
        if let plusIdx = s.firstIndex(of: "+") {
            s = String(s[..<plusIdx])
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func isRemoteNewer(remote: String, current: String) -> Bool {
        let (rCore, rPre) = splitVersion(normalize(remote))
        let (cCore, cPre) = splitVersion(normalize(current))
        guard !rCore.isEmpty else { return false }
        let count = max(rCore.count, cCore.count)
        for i in 0..<count {
            let rv = i < rCore.count ? rCore[i] : 0
            let cv = i < cCore.count ? cCore[i] : 0
            if rv != cv { return rv > cv }
        }
        if rPre == nil && cPre != nil { return true }
        if rPre != nil && cPre == nil { return false }
        if let rp = rPre, let cp = cPre, rp != cp {
            return rp.localizedStandardCompare(cp) == .orderedDescending
        }
        return false
    }

    private static func splitVersion(_ normalized: String) -> (core: [Int], prerelease: String?) {
        let parts = normalized.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let coreStr = parts.first.map(String.init) ?? ""
        let pre = parts.count > 1 && !parts[1].isEmpty ? String(parts[1]).lowercased() : nil
        let nums = coreStr.split(separator: ".").map { Int($0) ?? 0 }
        return (nums, pre)
    }
}

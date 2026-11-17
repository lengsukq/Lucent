import CryptoKit
import Foundation
import LumakeyFoundation
import LumakeySearch

public enum AppUpdateError: LocalizedError, Sendable, Equatable {
    case invalidResponse(Int)
    case malformedReleasePayload
    case missingDMGAsset
    case checksumMismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse(let code):
            L10n.pick("更新源响应异常 (HTTP \(code))", "Update server returned HTTP \(code)")
        case .malformedReleasePayload:
            L10n.pick("无法解析版本发布清单数据", "Unable to parse release manifest")
        case .missingDMGAsset:
            L10n.pick("该版本尚未附带可下载的 .dmg 安装包", "No .dmg installer attached to this release")
        case .checksumMismatch(let expected, let actual):
            L10n.pick(
                "DMG 安装包 SHA-256 校验不一致（期望 \(expected.prefix(10))…，实际 \(actual.prefix(10))…），已中止打开",
                "DMG SHA-256 mismatch (expected \(expected.prefix(10))…, got \(actual.prefix(10))…)"
            )
        }
    }
}

public enum AppUpdateService {
    public static let githubRepoSlug = "lengsukq/Lumakey"
    public static let releasesWebURL = "https://github.com/lengsukq/Lumakey/releases"
    public static let localResignOneLiner = "curl -fsSL https://raw.githubusercontent.com/lengsukq/Lumakey/main/scripts/resign-local-app.sh | bash"

    public static func currentAppVersion(bundle: Bundle = .main) -> String {
        if let ver = bundle.infoDictionary?["CFBundleShortVersionString"] as? String,
           !ver.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ver
        }
        return "0.9.0"
    }

    public static func currentBuildNumber(bundle: Bundle = .main) -> String {
        (bundle.infoDictionary?["CFBundleVersion"] as? String) ?? "28"
    }

    private struct GitHubAssetDTO: Decodable {
        let name: String
        let browser_download_url: String
        let size: Int64?
    }

    private struct GitHubReleaseDTO: Decodable {
        let tag_name: String
        let name: String?
        let body: String?
        let html_url: String
        let draft: Bool?
        let prerelease: Bool?
        let published_at: String?
        let assets: [GitHubAssetDTO]?
    }

    public static func parseGitHubReleasesJSON(
        _ data: Data,
        includePrerelease: Bool
    ) throws -> AppReleaseInfo? {
        let decoder = JSONDecoder()
        if let single = try? decoder.decode(GitHubReleaseDTO.self, from: data) {
            guard single.draft != true else { return nil }
            if !includePrerelease && single.prerelease == true { return nil }
            return mapDTO(single)
        }
        if let list = try? decoder.decode([GitHubReleaseDTO].self, from: data) {
            let candidates = list.filter { dto in
                guard dto.draft != true else { return false }
                if !includePrerelease && dto.prerelease == true { return false }
                return true
            }
            guard let newest = candidates.max(by: {
                AppVersionComparator.isRemoteNewer(remote: $1.tag_name, current: $0.tag_name)
            }) else { return nil }
            return mapDTO(newest)
        }
        throw AppUpdateError.malformedReleasePayload
    }

    private static func mapDTO(_ dto: GitHubReleaseDTO) -> AppReleaseInfo {
        let assets = dto.assets ?? []
        let dmgAsset = assets.first(where: {
            let lower = $0.name.lowercased()
            return lower.hasSuffix(".dmg") && !lower.hasSuffix(".dmg.sha256")
        })
        let shaAsset = assets.first(where: {
            let lower = $0.name.lowercased()
            return lower.hasSuffix(".dmg.sha256") || lower == "sha256sums.txt" || lower.hasSuffix(".sha256")
        })
        return AppReleaseInfo(
            tagName: dto.tag_name,
            title: (dto.name?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? dto.tag_name,
            releaseNotes: (dto.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            publishedAtISO8601: dto.published_at,
            isPrerelease: dto.prerelease ?? false,
            htmlURL: dto.html_url,
            dmgDownloadURL: dmgAsset?.browser_download_url,
            dmgAssetName: dmgAsset?.name,
            dmgSizeBytes: dmgAsset?.size,
            sha256AssetURL: shaAsset?.browser_download_url
        )
    }

    public static func checkGitHubUpdates(
        currentVersion: String = currentAppVersion(),
        includePrerelease: Bool = false,
        repoSlug: String = githubRepoSlug,
        session: URLSession = .shared
    ) async throws -> AppUpdateCheckOutcome {
        let endpoint = includePrerelease
            ? "https://api.github.com/repos/\(repoSlug)/releases?per_page=10"
            : "https://api.github.com/repos/\(repoSlug)/releases/latest"
        guard let url = URL(string: endpoint) else { throw AppUpdateError.malformedReleasePayload }

        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Lumakey/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse {
            if http.statusCode == 404 {
                return .upToDate(currentVersion: currentVersion, latestVersion: currentVersion)
            }
            guard (200..<300).contains(http.statusCode) else {
                throw AppUpdateError.invalidResponse(http.statusCode)
            }
        }

        guard let latest = try parseGitHubReleasesJSON(data, includePrerelease: includePrerelease) else {
            return .upToDate(currentVersion: currentVersion, latestVersion: currentVersion)
        }
        if AppVersionComparator.isRemoteNewer(remote: latest.normalizedVersion, current: currentVersion) {
            return .updateAvailable(currentVersion: currentVersion, release: latest)
        }
        return .upToDate(currentVersion: currentVersion, latestVersion: latest.normalizedVersion)
    }

    public static func parseFirstSHA256Hex(from text: String, matchingFileName: String? = nil) -> String? {
        let lines = text.components(separatedBy: .newlines)
        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let name = matchingFileName, lines.count > 1, !trimmed.contains(name) { continue }
            let tokens = trimmed.split(whereSeparator: { $0.isWhitespace || $0 == "*" })
            if let firstHex = tokens.first(where: { $0.count == 64 && $0.allSatisfy(\.isHexDigit) }) {
                return String(firstHex).lowercased()
            }
        }
        return nil
    }

    public static func downloadAndVerifyDMG(
        _ release: AppReleaseInfo,
        destinationDirectory: URL? = nil,
        session: URLSession = .shared
    ) async throws -> URL {
        guard let rawURL = release.dmgDownloadURL, let dmgURL = URL(string: rawURL) else {
            throw AppUpdateError.missingDMGAsset
        }
        let targetDir = destinationDirectory
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

        let (tempFileURL, resp) = try await session.download(from: dmgURL)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            try? FileManager.default.removeItem(at: tempFileURL)
            throw AppUpdateError.invalidResponse(http.statusCode)
        }

        if let shaURLStr = release.sha256AssetURL, let shaURL = URL(string: shaURLStr),
           let (shaData, shaResp) = try? await session.data(from: shaURL),
           (shaResp as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
           let shaText = String(data: shaData, encoding: .utf8),
           let expectedHex = parseFirstSHA256Hex(from: shaText, matchingFileName: release.dmgAssetName) {
            let actualHex = try DirectoryScanner.computeSHA256(for: tempFileURL).lowercased()
            if actualHex != expectedHex {
                try? FileManager.default.removeItem(at: tempFileURL)
                throw AppUpdateError.checksumMismatch(expected: expectedHex, actual: actualHex)
            }
        }

        let fileName = "Lumakey-\(release.normalizedVersion).dmg"
        let dstURL = targetDir.appendingPathComponent(fileName, isDirectory: false)
        try? FileManager.default.removeItem(at: dstURL)
        try FileManager.default.moveItem(at: tempFileURL, to: dstURL)
        return dstURL
    }
}

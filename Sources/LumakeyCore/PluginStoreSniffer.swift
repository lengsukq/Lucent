import LumakeyFoundation; import LumakeySearch; import LumakeyMedia; import LumakeySystem
import Foundation

public typealias PluginURLFetcher = @Sendable (URL) async throws -> (Data, HTTPURLResponse?)

public enum PluginStoreSniffer {
    public static let maxDownloadBytes = 32 * 1024 * 1024

    public static let defaultFetcher: PluginURLFetcher = { url in
        try validateSafeScheme(url)
        if url.isFileURL {
            let data = try Data(contentsOf: url)
            guard data.count <= maxDownloadBytes else {
                throw LumakeyError.pluginInvalid("插件包体积超过 32 MB 安全上限")
            }
            return (data, nil)
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("Lumakey-PluginStore/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        if let code = http?.statusCode, !(200...299).contains(code) {
            throw LumakeyError.pluginInvalid("请求 \(url.absoluteString) 返回 HTTP \(code)")
        }
        guard data.count <= maxDownloadBytes else {
            throw LumakeyError.pluginInvalid("远端资源体积超过 32 MB 安全上限")
        }
        return (data, http)
    }

    public static func validateSafeScheme(_ url: URL) throws {
        guard let scheme = url.scheme?.lowercased() else {
            throw LumakeyError.pluginInvalid("无效地址：缺少协议头（仅支持 https:// 或本地路径）")
        }
        if scheme == "https" || scheme == "file" { return }
        if scheme == "http", let host = url.host?.lowercased(),
           host == "127.0.0.1" || host == "localhost" || host == "::1" {
            return
        }
        throw LumakeyError.pluginInvalid("出于安全限制，外部插件与商店源仅支持 HTTPS 加密地址（\(url.absoluteString)）")
    }

    public static func normalizeInputURL(_ rawInput: String) throws -> URL {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LumakeyError.pluginInvalid("请输入插件地址或插件商店地址")
        }
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~/") {
            let expanded = (trimmed as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded).standardizedFileURL
        }
        let withScheme: String
        if trimmed.contains("://") {
            withScheme = trimmed
        } else if trimmed.lowercased().hasPrefix("github.com/") || trimmed.lowercased().hasPrefix("raw.githubusercontent.com/") {
            withScheme = "https://" + trimmed
        } else {
            withScheme = "https://" + trimmed
        }
        guard let url = URL(string: withScheme) else {
            throw LumakeyError.pluginInvalid("无法解析地址：\(trimmed)")
        }
        try validateSafeScheme(url)
        return url
    }

    public static func resolveSource(
        from rawInput: String,
        fetcher: PluginURLFetcher = defaultFetcher
    ) async throws -> DiscoveredPluginSource {
        let url = try normalizeInputURL(rawInput)

        // 0. Local filesystem directory shortcut
        if url.isFileURL {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                return try await resolveLocalDirectory(url, rawInput: rawInput, fetcher: fetcher)
            }
        }

        let lowerPath = url.path.lowercased()
        // 1. Direct archive link (.zip / .lumakeyplugin)
        if lowerPath.hasSuffix(".zip") || lowerPath.hasSuffix(".lumakeyplugin") {
            let (data, _) = try await fetcher(url)
            return try stageSinglePluginFromArchive(data: data, sourceInput: rawInput, downloadURL: url, expectedSHA256: nil)
        }

        // 2. GitHub repository root or /tree/{branch} shorthand
        if let ghRepo = parseGitHubRepoCoordinates(url) {
            return try await probeGitHubRepository(ghRepo, rawInput: rawInput, fetcher: fetcher)
        }

        // 3. Direct JSON file or direct fetch sniffing
        if lowerPath.hasSuffix(".json") || url.isFileURL {
            let (data, _) = try await fetcher(url)
            if looksLikeZipArchive(data) {
                return try stageSinglePluginFromArchive(data: data, sourceInput: rawInput, downloadURL: url, expectedSHA256: nil)
            }
            return try await classifyJSONPayload(data, resolvedURL: url, sourceInput: rawInput, fetcher: fetcher)
        }

        // 4. Generic HTTPS URL: probe direct response first, then directory conventions
        if let (directData, _) = try? await fetcher(url) {
            if looksLikeZipArchive(directData) {
                return try stageSinglePluginFromArchive(data: directData, sourceInput: rawInput, downloadURL: url, expectedSHA256: nil)
            }
            if let classified = try? await classifyJSONPayload(directData, resolvedURL: url, sourceInput: rawInput, fetcher: fetcher) {
                return classified
            }
        }

        let regURL = appendingPathCleanly(base: url, component: PluginStoreRegistryManifest.defaultFileName)
        if let (regData, _) = try? await fetcher(regURL),
           let classified = try? await classifyJSONPayload(regData, resolvedURL: regURL, sourceInput: rawInput, fetcher: fetcher) {
            return classified
        }

        let plugURL = appendingPathCleanly(base: url, component: "plugin.json")
        if let (plugData, _) = try? await fetcher(plugURL) {
            return try await classifyJSONPayload(plugData, resolvedURL: plugURL, sourceInput: rawInput, fetcher: fetcher)
        }

        throw LumakeyError.pluginInvalid("未能从该地址识别出有效的插件商店 (\(PluginStoreRegistryManifest.defaultFileName)) 或插件包")
    }

    // MARK: - Helpers

    struct GitHubRepoCoords {
        let owner: String; let repo: String; let explicitBranch: String?; let subpath: String?
    }

    static func parseGitHubRepoCoordinates(_ url: URL) -> GitHubRepoCoords? {
        guard let host = url.host?.lowercased(), host == "github.com" || host == "www.github.com" else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2 else { return nil }
        let owner = parts[0]
        let repo = parts[1].hasSuffix(".git") ? String(parts[1].dropLast(4)) : parts[1]
        if parts.count == 2 { return GitHubRepoCoords(owner: owner, repo: repo, explicitBranch: nil, subpath: nil) }
        if parts.count >= 4, parts[2] == "tree" {
            let sub = parts.count > 4 ? parts[4...].joined(separator: "/") : nil
            return GitHubRepoCoords(owner: owner, repo: repo, explicitBranch: parts[3], subpath: sub)
        }
        return nil
    }

    private static func probeGitHubRepository(
        _ coords: GitHubRepoCoords, rawInput: String, fetcher: PluginURLFetcher
    ) async throws -> DiscoveredPluginSource {
        let branches = coords.explicitBranch.map { [$0] } ?? ["main", "master"]
        let prefix = coords.subpath.map { "\($0)/" } ?? ""
        for branch in branches {
            let rawReg = URL(string: "https://raw.githubusercontent.com/\(coords.owner)/\(coords.repo)/\(branch)/\(prefix)\(PluginStoreRegistryManifest.defaultFileName)")!
            if let (data, _) = try? await fetcher(rawReg),
               let store = try? decodeStoreSubscription(data: data, resolvedURL: rawReg, sourceInput: rawInput) {
                return .storeRegistry(store)
            }
        }
        for branch in branches {
            let rawPlug = URL(string: "https://raw.githubusercontent.com/\(coords.owner)/\(coords.repo)/\(branch)/\(prefix)plugin.json")!
            if let (data, _) = try? await fetcher(rawPlug) {
                return try await resolveRemoteSingleManifest(
                    data: data, manifestURL: rawPlug, sourceInput: rawInput,
                    gitHubCoords: (coords.owner, coords.repo, branch), fetcher: fetcher
                )
            }
        }
        throw LumakeyError.pluginInvalid("GitHub 仓库 \(coords.owner)/\(coords.repo) 未找到 \(PluginStoreRegistryManifest.defaultFileName) 或 plugin.json")
    }

    private static func resolveLocalDirectory(_ dirURL: URL, rawInput: String, fetcher: PluginURLFetcher) async throws -> DiscoveredPluginSource {
        let regURL = dirURL.appendingPathComponent(PluginStoreRegistryManifest.defaultFileName)
        if FileManager.default.fileExists(atPath: regURL.path) {
            let data = try Data(contentsOf: regURL)
            return .storeRegistry(try decodeStoreSubscription(data: data, resolvedURL: regURL, sourceInput: rawInput))
        }
        let plugJson = dirURL.appendingPathComponent("plugin.json")
        if FileManager.default.fileExists(atPath: plugJson.path) {
            let loaded = PluginSystem.loadPlugin(at: dirURL, snapshot: PluginStateSnapshot(), includeSecrets: false, allowKeychainInteraction: false)
            guard loaded.isValid else {
                throw LumakeyError.pluginInvalid("本地插件校验未通过：\(loaded.validationIssues.joined(separator: "；"))")
            }
            return .singlePlugin(SinglePluginCandidate(
                manifest: loaded.manifest, sourceInput: rawInput, resolvedDownloadURL: dirURL.absoluteString,
                originDisplay: dirURL.path, sha256: "local-directory",
                stagingBundleDirectory: dirURL, stagingRootDirectory: nil
            ))
        }
        throw LumakeyError.pluginInvalid("目录 \(dirURL.lastPathComponent) 中未找到 \(PluginStoreRegistryManifest.defaultFileName) 或 plugin.json")
    }

    private static func classifyJSONPayload(
        _ data: Data,
        resolvedURL: URL,
        sourceInput: String,
        fetcher: PluginURLFetcher
    ) async throws -> DiscoveredPluginSource {
        guard let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LumakeyError.pluginInvalid("返回内容不是有效的 JSON 清单")
        }
        if top["storeId"] != nil && top["plugins"] != nil {
            return .storeRegistry(try decodeStoreSubscription(data: data, resolvedURL: resolvedURL, sourceInput: sourceInput))
        }
        if top["id"] != nil && top["entry"] != nil {
            return try await resolveRemoteSingleManifest(data: data, manifestURL: resolvedURL, sourceInput: sourceInput, gitHubCoords: nil, fetcher: fetcher)
        }
        throw LumakeyError.pluginInvalid("JSON 缺少商店字段 (storeId/plugins) 或插件字段 (id/entry)")
    }

    private static func decodeStoreSubscription(data: Data, resolvedURL: URL, sourceInput: String) throws -> PluginStoreSubscription {
        let manifest: PluginStoreRegistryManifest
        do {
            manifest = try JSONDecoder().decode(PluginStoreRegistryManifest.self, from: data)
        } catch {
            throw LumakeyError.pluginInvalid("商店清单解析失败：\(error.localizedDescription)")
        }
        let issues = manifest.validate()
        guard issues.isEmpty else {
            throw LumakeyError.pluginInvalid("商店清单校验未通过：\(issues.joined(separator: "；"))")
        }
        let now = ISO8601DateFormatter().string(from: Date())
        return PluginStoreSubscription(
            sourceURL: sourceInput.trimmingCharacters(in: .whitespacesAndNewlines),
            resolvedRegistryURL: resolvedURL.absoluteString,
            addedAtISO8601: now,
            lastSyncedAtISO8601: now,
            manifest: manifest
        )
    }

    private static func resolveRemoteSingleManifest(
        data: Data, manifestURL: URL, sourceInput: String,
        gitHubCoords: (owner: String, repo: String, branch: String)?,
        fetcher: PluginURLFetcher
    ) async throws -> DiscoveredPluginSource {
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
        let rawTop = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let explicitDL = rawTop["downloadURL"] as? String
        let expectedHash = rawTop["sha256"] as? String

        let baseDir = manifestURL.deletingLastPathComponent()
        var candidateURLs: [URL] = []
        if let explicitDL, let resolved = URL(string: explicitDL, relativeTo: baseDir)?.absoluteURL {
            candidateURLs.append(resolved)
        }
        if let gh = gitHubCoords {
            if let relURL = URL(string: "https://github.com/\(gh.owner)/\(gh.repo)/releases/latest/download/\(manifest.id).zip") {
                candidateURLs.append(relURL)
            }
            if let distURL = URL(string: "https://raw.githubusercontent.com/\(gh.owner)/\(gh.repo)/\(gh.branch)/dist/\(manifest.id).zip") {
                candidateURLs.append(distURL)
            }
        }
        candidateURLs.append(baseDir.appendingPathComponent("\(manifest.id).zip"))
        candidateURLs.append(baseDir.appendingPathComponent("dist/\(manifest.id).zip"))

        for archiveURL in candidateURLs {
            if let (zipData, _) = try? await fetcher(archiveURL), looksLikeZipArchive(zipData) {
                return try stageSinglePluginFromArchive(
                    data: zipData, sourceInput: sourceInput, downloadURL: archiveURL, expectedSHA256: expectedHash
                )
            }
        }
        throw LumakeyError.pluginInvalid("已识别单插件清单 '\(manifest.id)'，但未找到对应的 .zip 发布包（请在仓库 Release 或同级目录放置 \(manifest.id).zip，或声明 downloadURL）")
    }

    private static func stageSinglePluginFromArchive(
        data: Data, sourceInput: String, downloadURL: URL, expectedSHA256: String?
    ) throws -> DiscoveredPluginSource {
        let unpacked = try PluginStoreService.unpackArchiveSafely(archiveData: data, expectedSHA256: expectedSHA256)
        let loaded = PluginSystem.loadPlugin(at: unpacked.pluginDir, snapshot: PluginStateSnapshot(), includeSecrets: false, allowKeychainInteraction: false)
        guard loaded.isValid else {
            try? FileManager.default.removeItem(at: unpacked.stagingRoot)
            throw LumakeyError.pluginInvalid("插件包校验失败：\(loaded.validationIssues.joined(separator: "；"))")
        }
        let origin = downloadURL.isFileURL ? downloadURL.lastPathComponent : (downloadURL.host ?? downloadURL.absoluteString)
        return .singlePlugin(SinglePluginCandidate(
            manifest: loaded.manifest, sourceInput: sourceInput,
            resolvedDownloadURL: downloadURL.absoluteString, originDisplay: origin,
            sha256: unpacked.computedSHA256, stagingBundleDirectory: unpacked.pluginDir,
            stagingRootDirectory: unpacked.stagingRoot
        ))
    }

    static func looksLikeZipArchive(_ data: Data) -> Bool {
        data.count >= 4 && data[data.startIndex] == 0x50 && data[data.startIndex + 1] == 0x4B
            && data[data.startIndex + 2] == 0x03 && data[data.startIndex + 3] == 0x04
    }

    private static func appendingPathCleanly(base: URL, component: String) -> URL {
        base.path.hasSuffix("/") ? base.appendingPathComponent(component) : URL(string: base.absoluteString + "/" + component) ?? base.appendingPathComponent(component)
    }
}

import Foundation
import UniformTypeIdentifiers

enum LocalSendConstants {
    static let protocolVersion = "2.1"
    static let multicastAddress = "224.0.0.167"
    static let defaultPort: UInt16 = 53317
    static let pinMaxFailures = 5
    static let pinLockoutSeconds: TimeInterval = 60
    static let incomingPromptTimeoutSeconds: TimeInterval = 60
    static let maxInlineTextPreviewBytes = 65_536
}

struct LocalSendDeviceInfo: Codable, Sendable, Equatable {
    var alias: String
    var version: String
    var deviceModel: String?
    var deviceType: String?
    var fingerprint: String
    var port: Int
    var protocolName: String
    var download: Bool?
    var announce: Bool?

    enum CodingKeys: String, CodingKey {
        case alias, version, deviceModel, deviceType, fingerprint, port, download, announce
        case protocolName = "protocol"
    }
}

struct LocalSendFileMetadata: Codable, Sendable, Equatable {
    var id: String
    var fileName: String
    var size: Int64
    var fileType: String
    var sha256: String?
    var preview: String?
}

struct LocalSendPrepareUploadRequest: Codable, Sendable {
    var info: LocalSendDeviceInfo
    var files: [String: LocalSendFileMetadata]
}

struct LocalSendPrepareUploadResponse: Codable, Sendable {
    var sessionId: String
    var files: [String: String]
}

struct LocalSendPeer: Codable, Sendable, Equatable {
    var fingerprint: String
    var alias: String
    var ip: String
    var port: Int
    var protocolName: String
    var deviceModel: String
    var deviceType: String
    var isFavorite: Bool
    var isLumaLinkPaired: Bool
    var lastSeenEpoch: Double

    var baseURLString: String { "\(protocolName)://\(ip):\(port)" }

    func toJSONObject() -> [String: Any] {
        [
            "fingerprint": fingerprint,
            "alias": alias,
            "ip": ip,
            "port": port,
            "protocol": protocolName,
            "deviceModel": deviceModel,
            "deviceType": deviceType,
            "isFavorite": isFavorite,
            "isLumaLinkPaired": isLumaLinkPaired,
            "lastSeenEpoch": lastSeenEpoch
        ]
    }
}

struct LocalSendFavoritePeer: Codable, Sendable, Equatable {
    var id: String
    var alias: String
    var ip: String
    var port: Int
    var protocolName: String
    var fingerprint: String?
}

enum LocalSendReceiveMode: String, Codable, Sendable {
    case prompt
    case quickSave
    case sendOnly
}

struct LocalSendSessionConfig: Sendable {
    var alias: String
    var port: UInt16
    var useHttps: Bool
    var receiveMode: LocalSendReceiveMode
    var receivePin: String
    var saveDirectory: URL
    var dataDirectory: URL
    var autoRouteFilesToShelf: Bool
    var autoCopyReceivedText: Bool
    var isEnglish: Bool

    static func from(
        config: [String: String],
        dataDir: String,
        isEnglish: Bool
    ) -> LocalSendSessionConfig {
        let rawAlias = config["deviceAlias"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let defaultAlias = Host.current().localizedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Mac"
        let alias = rawAlias.isEmpty ? defaultAlias : rawAlias

        let parsedPort = Int(config["port"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? Int(LocalSendConstants.defaultPort)
        let clampedPort = UInt16(min(max(parsedPort, 1024), 65535))

        let httpsRaw = config["useHttps"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "true"
        let useHttps = !["false", "0", "no", "off"].contains(httpsRaw)

        let modeRaw = config["receiveMode"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "prompt"
        let receiveMode = LocalSendReceiveMode(rawValue: modeRaw) ?? .prompt

        let pin = config["receivePin"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawSave = config["saveDirectory"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "~/Downloads"
        let expandedSave = ((rawSave.isEmpty ? "~/Downloads" : rawSave) as NSString).expandingTildeInPath
        let saveURL = URL(fileURLWithPath: expandedSave, isDirectory: true).standardizedFileURL

        let resolvedDataDir = dataDir.isEmpty
            ? FileManager.default.temporaryDirectory.appendingPathComponent("lucent-local-send-data", isDirectory: true)
            : URL(fileURLWithPath: dataDir, isDirectory: true)

        let autoShelf = ["true", "1", "yes", "on"].contains((config["autoRouteFilesToShelf"] ?? "").lowercased())
        let autoCopy = ["true", "1", "yes", "on"].contains((config["autoCopyReceivedText"] ?? "").lowercased())

        return LocalSendSessionConfig(
            alias: alias,
            port: clampedPort,
            useHttps: useHttps,
            receiveMode: receiveMode,
            receivePin: pin,
            saveDirectory: saveURL,
            dataDirectory: resolvedDataDir,
            autoRouteFilesToShelf: autoShelf,
            autoCopyReceivedText: autoCopy,
            isEnglish: isEnglish
        )
    }
}

enum LocalSendFileSafety {
    /// 清洗来自远端设备的相对路径，严防 `../` 路径穿越与空字节注入，同时保留合法子目录结构。
    static func sanitizedRelativeComponents(from rawFileName: String) -> [String] {
        let normalized = rawFileName
            .replacingOccurrences(of: "\\", with: "/")
            .replacingOccurrences(of: "\0", with: "")
        let rawParts = normalized.split(separator: "/").map(String.init)
        var safeParts: [String] = []
        for part in rawParts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == "." || trimmed == ".." { continue }
            let cleaned = trimmed.replacingOccurrences(of: ":", with: "_")
            if !cleaned.isEmpty { safeParts.append(cleaned) }
        }
        return safeParts.isEmpty ? ["received-file"] : safeParts
    }

    static func resolveUniqueDestinationURL(baseDirectory: URL, rawFileName: String) throws -> URL {
        let fm = FileManager.default
        let canonicalBase = baseDirectory.standardizedFileURL
        try fm.createDirectory(at: canonicalBase, withIntermediateDirectories: true)

        let parts = sanitizedRelativeComponents(from: rawFileName)
        var targetDir = canonicalBase
        if parts.count > 1 {
            for folder in parts.dropLast() {
                targetDir = targetDir.appendingPathComponent(folder, isDirectory: true)
            }
            try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)
        }
        let leaf = parts.last ?? "received-file"
        let basePrefix = canonicalBase.path.hasSuffix("/") ? canonicalBase.path : canonicalBase.path + "/"
        let candidate = targetDir.appendingPathComponent(leaf, isDirectory: false).standardizedFileURL
        guard candidate.path.hasPrefix(basePrefix) else {
            throw NSError(domain: "LocalSend", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid destination path"])
        }
        if !fm.fileExists(atPath: candidate.path) { return candidate }

        let stem = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        for idx in 2...9999 {
            let nextName = ext.isEmpty ? "\(stem) (\(idx))" : "\(stem) (\(idx)).\(ext)"
            let nextURL = targetDir.appendingPathComponent(nextName, isDirectory: false).standardizedFileURL
            if nextURL.path.hasPrefix(basePrefix), !fm.fileExists(atPath: nextURL.path) {
                return nextURL
            }
        }
        let fallback = "\(stem)-\(UUID().uuidString.prefix(6))" + (ext.isEmpty ? "" : ".\(ext)")
        return targetDir.appendingPathComponent(fallback, isDirectory: false).standardizedFileURL
    }

    static func mimeType(for url: URL) -> String {
        if let ut = UTType(filenameExtension: url.pathExtension), let mime = ut.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }
}

enum LocalSendFavoriteStore {
    static func fileURL(in dataDir: URL) -> URL {
        dataDir.appendingPathComponent("favorites.json", isDirectory: false)
    }

    static func load(in dataDir: URL) -> [LocalSendFavoritePeer] {
        guard let data = try? Data(contentsOf: fileURL(in: dataDir)),
              let list = try? JSONDecoder().decode([LocalSendFavoritePeer].self, from: data) else {
            return []
        }
        return list
    }

    static func save(_ items: [LocalSendFavoritePeer], in dataDir: URL) {
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(items) {
            try? data.write(to: fileURL(in: dataDir), options: .atomic)
        }
    }
}

import Foundation

public enum LucentIdentifiers {
    public static let bundleID = "app.lucent.macos"
    public static let legacyBundleID = "com.queensu.lucent"

    public static func scoped(_ suffix: String) -> String {
        "\(bundleID).\(suffix)"
    }
}

public extension LucentAppPaths {
    static func configFileURL(_ fileName: String, in appSupportDirectory: URL = defaultAppSupportDirectory()) -> URL {
        appSupportDirectory.appendingPathComponent(fileName, isDirectory: false)
    }

    static func defaultIndexCacheDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let current = base.appendingPathComponent("\(LucentIdentifiers.bundleID)/everything-index", isDirectory: true)
        let legacy = base.appendingPathComponent("\(LucentIdentifiers.legacyBundleID)/everything-index", isDirectory: true)
        let fm = FileManager.default
        if !fm.fileExists(atPath: current.path), fm.fileExists(atPath: legacy.path) {
            try? fm.createDirectory(at: current.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.moveItem(at: legacy, to: current)
            try? fm.removeItem(at: legacy.deletingLastPathComponent())
        }
        return current
    }
}

public enum AtomicJSONStore {
    public static func decode<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    public static func load<T: Decodable>(
        _ type: T.Type,
        from url: URL,
        fallback: @autoclosure () -> T
    ) -> T {
        decode(type, from: url) ?? fallback()
    }

    public static func encodeData<T: Encodable>(
        _ value: T,
        formatting: JSONEncoder.OutputFormatting = [.prettyPrinted, .sortedKeys]
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = formatting
        return try encoder.encode(value)
    }

    public static func writeThrowing<T: Encodable>(
        _ value: T,
        to url: URL,
        formatting: JSONEncoder.OutputFormatting = [.prettyPrinted, .sortedKeys]
    ) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encodeData(value, formatting: formatting)
        try data.write(to: url, options: .atomic)
    }

    @discardableResult
    public static func save<T: Encodable>(
        _ value: T,
        to url: URL,
        formatting: JSONEncoder.OutputFormatting = [.prettyPrinted, .sortedKeys],
        notification: Notification.Name? = nil
    ) -> Bool {
        do {
            try writeThrowing(value, to: url, formatting: formatting)
            if let notification {
                NotificationCenter.default.post(name: notification, object: nil)
            }
            return true
        } catch {
            return false
        }
    }
}

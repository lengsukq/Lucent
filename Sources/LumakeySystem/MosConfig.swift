import Foundation

public struct MosConfig: Codable, Sendable, Hashable {
    public var enabled: Bool = false
    public var reverseWheelDirection: Bool = true
    public var smoothScroll: Bool = true
    public var stepPixels: Double = 36.0
    public var smoothness: Double = 0.24
    public var shiftHorizontal: Bool = true
    public var optionBoost: Bool = true
    public var excludedBundleIDs: [String] = []

    public init(
        enabled: Bool = false,
        reverseWheelDirection: Bool = true,
        smoothScroll: Bool = true,
        stepPixels: Double = 36.0,
        smoothness: Double = 0.24,
        shiftHorizontal: Bool = true,
        optionBoost: Bool = true,
        excludedBundleIDs: [String] = []
    ) {
        self.enabled = enabled
        self.reverseWheelDirection = reverseWheelDirection
        self.smoothScroll = smoothScroll
        self.stepPixels = stepPixels
        self.smoothness = smoothness
        self.shiftHorizontal = shiftHorizontal
        self.optionBoost = optionBoost
        self.excludedBundleIDs = excludedBundleIDs
    }

    public static func defaultConfigURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("Lumakey", isDirectory: true).appendingPathComponent("mos-config.json")
    }

    public static func load(from url: URL = defaultConfigURL()) -> MosConfig {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(MosConfig.self, from: data)
        else { return MosConfig() }
        return decoded
    }

    public func save(to url: URL = defaultConfigURL()) {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(self) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

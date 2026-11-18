import Foundation
import LucentFoundation

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
        LucentAppPaths.configFileURL("mos-config.json")
    }

    public static func load(from url: URL = defaultConfigURL()) -> MosConfig {
        AtomicJSONStore.load(MosConfig.self, from: url, fallback: MosConfig())
    }

    public func save(to url: URL = defaultConfigURL()) {
        AtomicJSONStore.save(self, to: url)
    }
}

import AppKit
import CoreGraphics
import Foundation

public enum LumaLinkDisplayError: LocalizedError {
    case displayNotFound
    case modeNotFound
    case configurationFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case .displayNotFound: return "未找到目标显示器"
        case .modeNotFound: return "未找到指定的显示分辨率模式"
        case .configurationFailed(let code): return "系统拒绝修改分辨率 (错误码 \(code))"
        }
    }
}

public final class LumaLinkDisplayService: @unchecked Sendable {
    public static let shared = LumaLinkDisplayService()

    private let lock = NSLock()
    private var originalModes: [CGDirectDisplayID: CGDisplayMode] = [:]

    private init() {}

    public var hasSnapshottedChanges: Bool {
        lock.withLock { !originalModes.isEmpty }
    }

    public func listDisplays() -> [LumaLinkDisplayInfo] {
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetActiveDisplayList(16, &ids, &count) == .success else { return [] }
        if count == 0 {
            // Fall back to online displays so remote control still enumerates displays while screen is asleep.
            _ = CGGetOnlineDisplayList(16, &ids, &count)
        }
        let mainID = CGMainDisplayID()
        let activeIDs = ids.prefix(Int(count))

        return activeIDs.enumerated().map { index, displayID in
            let currentMode = CGDisplayCopyDisplayMode(displayID)
            let currentKey = currentMode.map(Self.modeKey(for:)) ?? ""
            let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
            let rawModes = (CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode]) ?? []
            let selectedModes = Self.curateModes(rawModes: rawModes, currentMode: currentMode)
            let name = Self.displayName(for: displayID, index: index, isMain: displayID == mainID)
            return LumaLinkDisplayInfo(
                displayID: displayID,
                name: name,
                isMain: displayID == mainID,
                currentModeKey: currentKey,
                modes: selectedModes
            )
        }
    }

    public func setDisplayMode(displayID: UInt32?, modeKey: String) throws -> [LumaLinkDisplayInfo] {
        let targetID = displayID ?? CGMainDisplayID()
        guard let currentMode = CGDisplayCopyDisplayMode(targetID) else {
            throw LumaLinkDisplayError.displayNotFound
        }
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        let rawModes = (CGDisplayCopyAllDisplayModes(targetID, options) as? [CGDisplayMode]) ?? []
        guard let targetMode = rawModes.first(where: { Self.modeKey(for: $0) == modeKey }) else {
            throw LumaLinkDisplayError.modeNotFound
        }

        lock.withLock {
            if originalModes[targetID] == nil {
                originalModes[targetID] = currentMode
            }
        }

        var cfg: CGDisplayConfigRef?
        let beginErr = CGBeginDisplayConfiguration(&cfg)
        guard beginErr == .success, let cfg else {
            throw LumaLinkDisplayError.configurationFailed(beginErr.rawValue)
        }
        CGConfigureDisplayWithDisplayMode(cfg, targetID, targetMode, nil)
        let completeErr = CGCompleteDisplayConfiguration(cfg, .forAppOnly)
        guard completeErr == .success else {
            CGCancelDisplayConfiguration(cfg)
            throw LumaLinkDisplayError.configurationFailed(completeErr.rawValue)
        }
        return listDisplays()
    }

    @discardableResult
    public func restoreAll() -> Bool {
        let saved = lock.withLock { () -> [CGDirectDisplayID: CGDisplayMode] in
            let copy = originalModes
            originalModes.removeAll()
            return copy
        }
        guard !saved.isEmpty else { return false }
        var cfg: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&cfg) == .success, let cfg else { return false }
        for (displayID, mode) in saved {
            CGConfigureDisplayWithDisplayMode(cfg, displayID, mode, nil)
        }
        return CGCompleteDisplayConfiguration(cfg, .forAppOnly) == .success
    }

    public static func modeKey(for mode: CGDisplayMode) -> String {
        let scale = mode.pixelWidth > mode.width ? 2 : 1
        let hz = max(60, Int(mode.refreshRate.rounded()))
        return "\(mode.width)x\(mode.height)@\(scale)x_\(hz)"
    }

    public static func curateModes(rawModes: [CGDisplayMode], currentMode: CGDisplayMode?) -> [LumaLinkDisplayModeInfo] {
        let currentKey = currentMode.map(modeKey(for:)) ?? ""
        var bestBySize: [String: CGDisplayMode] = [:]

        for mode in rawModes {
            guard mode.width >= 800, mode.height >= 600 else { continue }
            let isHiDPI = mode.pixelWidth > mode.width
            let bucket = "\(mode.width)x\(mode.height)@\(isHiDPI ? 2 : 1)"
            if let existing = bestBySize[bucket] {
                if mode.refreshRate > existing.refreshRate {
                    bestBySize[bucket] = mode
                }
            } else {
                bestBySize[bucket] = mode
            }
        }
        if let cur = currentMode {
            let bucket = "\(cur.width)x\(cur.height)@\(cur.pixelWidth > cur.width ? 2 : 1)"
            bestBySize[bucket] = cur
        }

        let preferredSizes: Set<String> = [
            "1280x720", "1280x800", "1440x900", "1600x900",
            "1680x1050", "1920x1080", "2048x1280", "2560x1440", "2560x1600"
        ]

        let sorted = bestBySize.values.sorted { lhs, rhs in
            if lhs.width != rhs.width { return lhs.width < rhs.width }
            if lhs.height != rhs.height { return lhs.height < rhs.height }
            let lHi = lhs.pixelWidth > lhs.width
            let rHi = rhs.pixelWidth > rhs.width
            if lHi != rHi { return lHi && !rHi }
            return lhs.refreshRate > rhs.refreshRate
        }

        return sorted.compactMap { mode in
            let key = modeKey(for: mode)
            let isCurrent = key == currentKey
            let sizeTag = "\(mode.width)x\(mode.height)"
            let isHiDPI = mode.pixelWidth > mode.width
            guard isCurrent || preferredSizes.contains(sizeTag) else { return nil }
            let hz = max(60, Int(mode.refreshRate.rounded()))
            return LumaLinkDisplayModeInfo(
                modeKey: key,
                label: friendlyLabel(width: mode.width, height: mode.height, isHiDPI: isHiDPI, isCurrent: isCurrent),
                pixelWidth: mode.pixelWidth,
                pixelHeight: mode.pixelHeight,
                pointWidth: mode.width,
                pointHeight: mode.height,
                refreshHz: hz,
                isHiDPI: isHiDPI,
                isCurrent: isCurrent
            )
        }
    }

    private static func friendlyLabel(width: Int, height: Int, isHiDPI: Bool, isCurrent: Bool) -> String {
        let base = "\(width)×\(height)"
        let hi = isHiDPI ? " HiDPI" : ""
        let hint: String = switch "\(width)x\(height)" {
        case "1280x720": " · 手机护眼高清"
        case "1440x900": " · MacBook 舒适"
        case "1600x900": " · 16:9 清晰"
        case "1920x1080": " · 1080p 全高清"
        case "2560x1440": " · 2K 锐利"
        default: ""
        }
        return "\(base)\(hi)\(hint)\(isCurrent ? " (当前)" : "")"
    }

    private static func displayName(for id: CGDirectDisplayID, index: Int, isMain: Bool) -> String {
        for screen in NSScreen.screens {
            if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
               num.uint32Value == id {
                return isMain ? "\(screen.localizedName) (主屏)" : screen.localizedName
            }
        }
        return isMain ? "主显示器" : "显示器 \(index + 1)"
    }
}

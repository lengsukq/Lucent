import Foundation
import AppKit

struct WindowFrameRecord: Codable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var opacity: Double?
    var pinOnTop: Bool?
    var updatedAtEpoch: Double?
}

struct ScreenBoundsInfo: Codable {
    let minX: Double
    let minY: Double
    let maxX: Double
    let maxY: Double
    let visibleMinX: Double
    let visibleMinY: Double
    let visibleMaxX: Double
    let visibleMaxY: Double
}

struct FrameCheckResult: Codable {
    let ok: Bool
    let windowId: String
    let updatedAt: Double
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let distLeft: Double
    let distRight: Double
    let distTop: Double
    let outOfBounds: Bool
    let detectedEdge: String?
    let snapX: Double?
    let snapY: Double?
    let shouldUndock: Bool
    let restoreX: Double?
    let restoreY: Double?
    let screen: ScreenBoundsInfo?
}

func currentScreenBounds() -> [ScreenBoundsInfo] {
    let screens = NSScreen.screens
    if !screens.isEmpty {
        return screens.map { s in
            let f = s.frame
            let v = s.visibleFrame
            return ScreenBoundsInfo(
                minX: Double(f.minX),
                minY: Double(f.minY),
                maxX: Double(f.maxX),
                maxY: Double(f.maxY),
                visibleMinX: Double(v.minX),
                visibleMinY: Double(v.minY),
                visibleMaxX: Double(v.maxX),
                visibleMaxY: Double(v.maxY)
            )
        }
    }
    return [
        ScreenBoundsInfo(
            minX: 0, minY: 0, maxX: 1512, maxY: 982,
            visibleMinX: 0, visibleMinY: 94, visibleMaxX: 1512, visibleMaxY: 949
        )
    ]
}

func screenContaining(x: Double, y: Double, width: Double, height: Double) -> ScreenBoundsInfo {
    let screens = currentScreenBounds()
    var bestScreen = screens[0]
    var bestArea: Double = -1
    for s in screens {
        let ox = max(0, min(x + width, s.maxX) - max(x, s.minX))
        let oy = max(0, min(y + height, s.maxY) - max(y, s.minY))
        let area = ox * oy
        if area > bestArea {
            bestArea = area
            bestScreen = s
        }
    }
    if bestArea > 0 { return bestScreen }

    let cx = x + width * 0.5
    let cy = y + height * 0.5
    return screens.min(by: { a, b in
        let dxA = max(a.minX - cx, 0, cx - a.maxX)
        let dyA = max(a.minY - cy, 0, cy - a.maxY)
        let dxB = max(b.minX - cx, 0, cx - b.maxX)
        let dyB = max(b.minY - cy, 0, cy - b.maxY)
        return hypot(dxA, dyA) < hypot(dxB, dyB)
    }) ?? screens[0]
}

private func windowFramesURL(dataDir: String) -> URL? {
    guard !dataDir.isEmpty else { return nil }
    return URL(fileURLWithPath: dataDir, isDirectory: true).appendingPathComponent("window-frames.json")
}

func loadAllWindowFrames(dataDir: String) -> [String: WindowFrameRecord] {
    guard let url = windowFramesURL(dataDir: dataDir),
          let data = try? Data(contentsOf: url),
          let decoded = try? JSONDecoder().decode([String: WindowFrameRecord].self, from: data) else {
        return [:]
    }
    return decoded
}

func updateSavedWindowFrame(
    dataDir: String,
    windowId: String,
    x: Double,
    y: Double,
    width: Double,
    height: Double,
    opacity: Double = 1.0
) {
    guard let url = windowFramesURL(dataDir: dataDir) else { return }
    var all = loadAllWindowFrames(dataDir: dataDir)
    let existing = all[windowId]
    all[windowId] = WindowFrameRecord(
        x: x.rounded(),
        y: y.rounded(),
        width: width.rounded(),
        height: height.rounded(),
        opacity: existing?.opacity ?? opacity,
        pinOnTop: true,
        updatedAtEpoch: Date().timeIntervalSince1970
    )
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? enc.encode(all) {
        try? data.write(to: url, options: .atomic)
    }
}

func dockTargetSize(for edge: String) -> (w: Double, h: Double) {
    return edge == "top" ? (260, 60) : (164, 104)
}

func computeSnapOrigin(edge: String, sourceFrame: WindowFrameRecord, targetW: Double, targetH: Double) -> (x: Double, y: Double) {
    let s = screenContaining(x: sourceFrame.x, y: sourceFrame.y, width: sourceFrame.width, height: sourceFrame.height)
    switch edge {
    case "left":
        let rawY = sourceFrame.y + (sourceFrame.height - targetH) * 0.5
        let clampedY = max(s.visibleMinY + 8, min(rawY, s.visibleMaxY - targetH - 8))
        return (s.minX, clampedY.rounded())
    case "top":
        let rawX = sourceFrame.x + (sourceFrame.width - targetW) * 0.5
        let clampedX = max(s.visibleMinX + 8, min(rawX, s.visibleMaxX - targetW - 8))
        return (clampedX.rounded(), (s.visibleMaxY - targetH).rounded())
    default:
        let rawY = sourceFrame.y + (sourceFrame.height - targetH) * 0.5
        let clampedY = max(s.visibleMinY + 8, min(rawY, s.visibleMaxY - targetH - 8))
        return ((s.maxX - targetW).rounded(), clampedY.rounded())
    }
}

func checkWindowEdgeState(dataDir: String, windowId: String, mode: String, returnMode: String = "standard") -> FrameCheckResult {
    let frames = loadAllWindowFrames(dataDir: dataDir)
    let resolvedId = frames[windowId] != nil
        ? windowId
        : (frames[PulseConstants.windowID] != nil ? PulseConstants.windowID : (frames["main"] != nil ? "main" : windowId))
    guard let f = frames[resolvedId] else {
        return FrameCheckResult(
            ok: false, windowId: resolvedId, updatedAt: 0,
            x: 0, y: 0, width: 0, height: 0,
            distLeft: 9999, distRight: 9999, distTop: 9999,
            outOfBounds: false, detectedEdge: nil, snapX: nil, snapY: nil,
            shouldUndock: false, restoreX: nil, restoreY: nil, screen: nil
        )
    }

    let s = screenContaining(x: f.x, y: f.y, width: f.width, height: f.height)
    let distLeft = f.x - s.minX
    let distRight = s.maxX - (f.x + f.width)
    let distTop = s.visibleMaxY - (f.y + f.height)
    let distBottom = f.y - s.visibleMinY
    let outOfBounds = (distLeft < -1) || (distRight < -1) || (distTop < -1) || (distBottom < -1)

    let isDock = (mode == "dock")
    let edgeThreshold: Double = isDock ? 56.0 : 28.0
    var detected: String? = nil

    if distTop <= edgeThreshold && distTop <= distLeft && distTop <= distRight {
        detected = "top"
    } else if distLeft <= edgeThreshold && distLeft <= distRight {
        detected = "left"
    } else if distRight <= edgeThreshold && distRight < distLeft {
        detected = "right"
    } else if isDock && outOfBounds {
        detected = (distLeft <= distRight) ? "left" : "right"
    }

    let shouldUndock = isDock && !outOfBounds && (distLeft > 84 && distRight > 84 && distTop > 64)
    var snapX: Double? = nil
    var snapY: Double? = nil
    if let edge = detected {
        let dsz = dockTargetSize(for: edge)
        let origin = computeSnapOrigin(edge: edge, sourceFrame: f, targetW: dsz.w, targetH: dsz.h)
        snapX = origin.x
        snapY = origin.y
    }

    var restoreX: Double? = nil
    var restoreY: Double? = nil
    if shouldUndock {
        let targetW: Double = PulseConstants.standardHudWidth
        let targetH: Double = PulseConstants.standardHudHeight
        restoreX = max(s.visibleMinX + 40, min(f.x + (f.width - targetW) * 0.5, s.visibleMaxX - targetW - 40)).rounded()
        restoreY = max(s.visibleMinY + 32, min(f.y + (f.height - targetH) * 0.5, s.visibleMaxY - targetH - 36)).rounded()
    }

    return FrameCheckResult(
        ok: true,
        windowId: resolvedId,
        updatedAt: f.updatedAtEpoch ?? 0,
        x: f.x,
        y: f.y,
        width: f.width,
        height: f.height,
        distLeft: distLeft,
        distRight: distRight,
        distTop: distTop,
        outOfBounds: outOfBounds,
        detectedEdge: detected,
        snapX: snapX,
        snapY: snapY,
        shouldUndock: shouldUndock,
        restoreX: restoreX,
        restoreY: restoreY,
        screen: s
    )
}

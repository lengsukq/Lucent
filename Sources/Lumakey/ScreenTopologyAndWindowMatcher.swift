import AppKit
import CoreGraphics
import Foundation
import LumakeyCore
import ScreenCaptureKit

struct DetectedScreenWindow: Identifiable, Equatable, Sendable {
    let id: CGWindowID
    let ownerName: String
    let title: String
    let frame: CGRect

    var displayLabel: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if ownerName.isEmpty { return trimmedTitle }
        if trimmedTitle.isEmpty || trimmedTitle == ownerName { return ownerName }
        let short = trimmedTitle.count > 28 ? String(trimmedTitle.prefix(28)) + "…" : trimmedTitle
        return "\(ownerName) — \(short)"
    }
}

struct ScreenDisplaySlice: Identifiable {
    var id: CGDirectDisplayID { displayID }
    let displayID: CGDirectDisplayID
    let scDisplay: SCDisplay
    let appKitScreen: NSScreen
    let cgFrame: CGRect
    let canvasFrame: CGRect
    let scale: CGFloat
}

@MainActor
struct ScreenTopologySnapshot {
    let displays: [ScreenDisplaySlice]
    let cgUnionBounds: CGRect
    let canvasBounds: CGRect
    let primaryScreenHeight: CGFloat
    let maxScale: CGFloat
    let baseImage: CGImage
    let windows: [DetectedScreenWindow]

    func canvasPoint(fromAppKitGlobal nsPt: NSPoint) -> CGPoint {
        let cgX = nsPt.x
        let cgY = primaryScreenHeight - nsPt.y
        return CGPoint(x: cgX - cgUnionBounds.minX, y: cgY - cgUnionBounds.minY)
    }

    func appKitGlobalRect(fromCanvas rect: CGRect) -> NSRect {
        let cgRect = rect.offsetBy(dx: cgUnionBounds.minX, dy: cgUnionBounds.minY)
        return NSRect(x: cgRect.minX, y: primaryScreenHeight - cgRect.maxY, width: cgRect.width, height: cgRect.height)
    }

    func displaySlice(containingCanvasPoint pt: CGPoint) -> ScreenDisplaySlice? {
        displays.first(where: { $0.canvasFrame.insetBy(dx: -0.5, dy: -0.5).contains(pt) })
            ?? displays.min(by: { hypot($0.canvasFrame.midX - pt.x, $0.canvasFrame.midY - pt.y) < hypot($1.canvasFrame.midX - pt.x, $1.canvasFrame.midY - pt.y) })
    }

    func targetSlice(forSelection sel: CGRect, fallbackPoint: CGPoint) -> ScreenDisplaySlice? {
        let anchor = CGPoint(x: sel.maxX, y: sel.maxY)
        if let hit = displays.first(where: { $0.canvasFrame.insetBy(dx: -1, dy: -1).contains(anchor) }) { return hit }
        return displays
            .compactMap { slice -> (ScreenDisplaySlice, CGFloat)? in
                let inter = slice.canvasFrame.intersection(sel)
                guard !inter.isNull, inter.width > 0, inter.height > 0 else { return nil }
                return (slice, inter.width * inter.height)
            }
            .max(by: { $0.1 < $1.1 })?.0
            ?? displaySlice(containingCanvasPoint: fallbackPoint)
    }
}

@MainActor
enum ScreenTopologyAndWindowMatcher {
    private static let ignoredOwnerNames: Set<String> = [
        "Window Server", "WindowServer", "Dock", "Wallpaper", "Control Center", "控制中心", "Notification Center", "通知中心"
    ]

    @MainActor
    static func captureSnapshot() async throws -> ScreenTopologySnapshot {
        let nsScreens = NSScreen.screens
        guard !nsScreens.isEmpty else {
            throw LumakeyError.visionFailed(L10n.pick("未检测到可用显示器。", "No available display detected."))
        }
        let primaryHeight = nsScreens[0].frame.height
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard !content.displays.isEmpty else {
            throw LumakeyError.visionFailed(L10n.pick("未检测到可捕获的显示器。", "No shareable display detected."))
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownApps = content.applications.filter { $0.processID == ownPID }

        var rawSlices: [(scDisplay: SCDisplay, screen: NSScreen, cgFrame: CGRect, scale: CGFloat)] = []
        for screen in nsScreens {
            let num = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            guard let scDisp = content.displays.first(where: { $0.displayID == CGDirectDisplayID(num) }) else { continue }
            let cgRect = CGRect(x: screen.frame.minX, y: primaryHeight - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height)
            rawSlices.append((scDisp, screen, cgRect, max(screen.backingScaleFactor, 1.0)))
        }
        if rawSlices.isEmpty, let firstDisp = content.displays.first {
            rawSlices.append((firstDisp, nsScreens[0], firstDisp.frame, max(nsScreens[0].backingScaleFactor, 1.0)))
        }

        let cgUnion = rawSlices.reduce(CGRect.null) { $0.union($1.cgFrame) }
        let canvasBounds = CGRect(origin: .zero, size: cgUnion.size)
        let maxScale = rawSlices.map(\.scale).max() ?? 2.0

        let slices: [ScreenDisplaySlice] = rawSlices.map { item in
            ScreenDisplaySlice(
                displayID: item.scDisplay.displayID, scDisplay: item.scDisplay, appKitScreen: item.screen,
                cgFrame: item.cgFrame, canvasFrame: item.cgFrame.offsetBy(dx: -cgUnion.minX, dy: -cgUnion.minY), scale: item.scale
            )
        }

        var capturedPerDisplay: [(CGRect, CGImage)] = []
        for slice in slices {
            let filter = SCContentFilter(display: slice.scDisplay, excludingApplications: ownApps, exceptingWindows: [])
            let cfg = SCStreamConfiguration()
            cfg.width = max(2, Int(round(slice.cgFrame.width * slice.scale)))
            cfg.height = max(2, Int(round(slice.cgFrame.height * slice.scale)))
            cfg.showsCursor = false
            let img = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
            capturedPerDisplay.append((slice.canvasFrame, img))
        }

        let composite = try compositeCanvasImage(canvasBounds: canvasBounds, scale: maxScale, pieces: capturedPerDisplay)
        let orderedWindows = buildZOrderedWindows(scWindows: content.windows, ownPID: ownPID, cgUnion: cgUnion, canvasBounds: canvasBounds)
        return ScreenTopologySnapshot(
            displays: slices, cgUnionBounds: cgUnion, canvasBounds: canvasBounds,
            primaryScreenHeight: primaryHeight, maxScale: maxScale, baseImage: composite, windows: orderedWindows
        )
    }

    static func buildZOrderedWindows(scWindows: [SCWindow], ownPID: pid_t, cgUnion: CGRect, canvasBounds: CGRect) -> [DetectedScreenWindow] {
        var scByID: [CGWindowID: SCWindow] = [:]
        for w in scWindows where w.isOnScreen && w.windowLayer == 0 && w.owningApplication?.processID != ownPID {
            scByID[w.windowID] = w
        }
        let rawInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var result: [DetectedScreenWindow] = []
        var seen = Set<CGWindowID>()

        for entry in rawInfo {
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let winIDNum = entry[kCGWindowNumber as String] as? UInt32 else { continue }
            let alpha = (entry[kCGWindowAlpha as String] as? Double) ?? 1.0
            guard alpha > 0.05 else { continue }
            let owner = (entry[kCGWindowOwnerName as String] as? String) ?? ""
            if ignoredOwnerNames.contains(owner) { continue }

            let winID = CGWindowID(winIDNum)
            guard let scWin = scByID[winID], seen.insert(winID).inserted else { continue }
            let canvasRect = scWin.frame.offsetBy(dx: -cgUnion.minX, dy: -cgUnion.minY).intersection(canvasBounds)
            guard !canvasRect.isNull, canvasRect.width >= 36, canvasRect.height >= 36 else { continue }
            let finalOwner = scWin.owningApplication?.applicationName ?? owner
            let title = scWin.title ?? (entry[kCGWindowName as String] as? String) ?? ""
            result.append(DetectedScreenWindow(id: winID, ownerName: finalOwner, title: title, frame: canvasRect))
        }

        for scWin in scWindows where scWin.isOnScreen && scWin.windowLayer == 0
            && scWin.owningApplication?.processID != ownPID && !seen.contains(scWin.windowID) {
            let owner = scWin.owningApplication?.applicationName ?? ""
            guard !ignoredOwnerNames.contains(owner) else { continue }
            let canvasRect = scWin.frame.offsetBy(dx: -cgUnion.minX, dy: -cgUnion.minY).intersection(canvasBounds)
            guard !canvasRect.isNull, canvasRect.width >= 36, canvasRect.height >= 36 else { continue }
            result.append(DetectedScreenWindow(id: scWin.windowID, ownerName: owner, title: scWin.title ?? "", frame: canvasRect))
        }
        return result
    }

    static func compositeCanvasImage(canvasBounds: CGRect, scale: CGFloat, pieces: [(canvasFrame: CGRect, image: CGImage)]) throws -> CGImage {
        if pieces.count == 1, pieces[0].canvasFrame.origin == .zero, pieces[0].canvasFrame.size == canvasBounds.size {
            return pieces[0].image
        }
        let pixelW = max(2, Int(round(canvasBounds.width * scale)))
        let pixelH = max(2, Int(round(canvasBounds.height * scale)))
        let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: pixelW, height: pixelH, bitsPerComponent: 8, bytesPerRow: pixelW * 4,
            space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw LumakeyError.visionFailed("无法创建多屏合成画布。") }
        ctx.interpolationQuality = .high
        for (rect, img) in pieces {
            ctx.draw(img, in: CGRect(x: rect.minX * scale, y: (canvasBounds.height - rect.maxY) * scale, width: rect.width * scale, height: rect.height * scale))
        }
        guard let out = ctx.makeImage() else { throw LumakeyError.visionFailed("合成多显示器画面失败。") }
        return out
    }

    static func captureIndependentWindowImage(windowID: CGWindowID, ignoreShadow: Bool, scale: CGFloat) async throws -> CGImage? {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        guard let scWin = content.windows.first(where: { $0.windowID == windowID }) else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: scWin)
        let rect = filter.contentRect
        let effScale = max(scale, CGFloat(filter.pointPixelScale), 1.0)
        let cfg = SCStreamConfiguration()
        cfg.width = max(2, Int(round(rect.width * effScale)))
        cfg.height = max(2, Int(round(rect.height * effScale)))
        cfg.scalesToFit = false; cfg.showsCursor = false
        cfg.ignoreShadowsSingleWindow = ignoreShadow
        cfg.shouldBeOpaque = false; cfg.backgroundColor = .clear
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
    }

    @MainActor
    static func activeCursorScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    static func captureCrossDisplayRegion(
        canvasRect: CGRect, cgUnionBounds: CGRect,
        displays: [(scDisplay: SCDisplay, canvasFrame: CGRect, scale: CGFloat)],
        excludedWindows: [SCWindow], showsCursor: Bool, outputSize: (Int, Int)
    ) async -> CGImage? {
        let _ = cgUnionBounds
        var pieces: [(CGRect, CGImage)] = []
        for disp in displays {
            let inter = disp.canvasFrame.intersection(canvasRect)
            guard !inter.isNull, inter.width >= 2, inter.height >= 2 else { continue }
            let localSrc = inter.offsetBy(dx: -disp.canvasFrame.minX, dy: -disp.canvasFrame.minY)
            let filter = SCContentFilter(display: disp.scDisplay, excludingWindows: excludedWindows)
            let cfg = SCStreamConfiguration()
            cfg.sourceRect = localSrc
            cfg.width = max(2, Int(round(localSrc.width * disp.scale)))
            cfg.height = max(2, Int(round(localSrc.height * disp.scale)))
            cfg.showsCursor = showsCursor; cfg.scalesToFit = true
            if let img = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg) {
                pieces.append((inter.offsetBy(dx: -canvasRect.minX, dy: -canvasRect.minY), img))
            }
        }
        guard !pieces.isEmpty else { return nil }
        let outW = max(2, outputSize.0), outH = max(2, outputSize.1)
        let sx = CGFloat(outW) / max(canvasRect.width, 1), sy = CGFloat(outH) / max(canvasRect.height, 1)
        let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: outW, height: outH, bitsPerComponent: 8, bytesPerRow: outW * 4, space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        for (rel, img) in pieces {
            ctx.draw(img, in: CGRect(x: rel.minX * sx, y: (canvasRect.height - rel.maxY) * sy, width: rel.width * sx, height: rel.height * sy))
        }
        return ctx.makeImage()
    }
}

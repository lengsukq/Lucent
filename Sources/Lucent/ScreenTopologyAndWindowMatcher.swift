import AppKit
import CoreGraphics
import Foundation
import LucentCore
import LucentMedia
@preconcurrency import ScreenCaptureKit

@MainActor
enum ScreenTopologyAndWindowMatcher {
    private static let ignoredOwnerNames: Set<String> = [
        "Window Server", "WindowServer", "Dock", "Wallpaper", "Control Center", "控制中心", "Notification Center", "通知中心"
    ]

    static func screenDisplayID(_ screen: NSScreen) -> CGDirectDisplayID {
        let num = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        return CGDirectDisplayID(num)
    }

    private static func ownChromeWindowIDs(includeStatusBar: Bool) -> Set<CGWindowID> {
        var ids = Set<CGWindowID>()
        for win in NSApp?.windows ?? [] {
            guard let id = CaptureSelfVisibilityPolicy.validWindowID(from: win.windowNumber) else { continue }
            let cls = NSStringFromClass(type(of: win))
            if win is CaptureOverlayPanel || cls.contains("MenuWindow") || (includeStatusBar && cls.contains("StatusBar")) {
                ids.insert(id)
            }
        }
        return ids
    }

    @MainActor
    static func captureSnapshot(excludeOwnWindows: Bool = true, includeCaptureOverlays: Bool = false) async throws -> ScreenTopologySnapshot {
        let nsScreens = NSScreen.screens
        guard !nsScreens.isEmpty else {
            throw LucentError.visionFailed(L10n.pick("未检测到可用显示器。", "No available display detected."))
        }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard !content.displays.isEmpty else {
            throw LucentError.visionFailed(L10n.pick("未检测到可捕获的显示器。", "No shareable display detected."))
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let shouldExcludeOwn = excludeOwnWindows && !includeCaptureOverlays
        let ownApps = shouldExcludeOwn ? content.applications.filter { $0.processID == ownPID } : []
        let ignoredCaptureIDs = (shouldExcludeOwn || includeCaptureOverlays) ? Set<CGWindowID>() : ownChromeWindowIDs(includeStatusBar: false)
        let excludedCaptureWins = (!shouldExcludeOwn && !ignoredCaptureIDs.isEmpty)
            ? content.windows.filter { ignoredCaptureIDs.contains($0.windowID) }
            : []

        var matchedScreens: [(scDisplay: SCDisplay, screen: NSScreen, id: CGDirectDisplayID, scale: CGFloat)] = []
        for screen in nsScreens {
            let id = screenDisplayID(screen)
            guard id != 0, let scDisp = content.displays.first(where: { $0.displayID == id }) else { continue }
            matchedScreens.append((scDisp, screen, id, max(screen.backingScaleFactor, 1.0)))
        }
        if matchedScreens.isEmpty, let firstDisp = content.displays.first {
            matchedScreens.append((firstDisp, nsScreens[0], firstDisp.displayID, max(nsScreens[0].backingScaleFactor, 1.0)))
        }

        let layout = MultiDisplayLayout(
            screens: matchedScreens.map { ($0.id, $0.screen.frame, $0.screen.visibleFrame, $0.scale) },
            mainDisplayID: CGMainDisplayID()
        )
        var slices: [ScreenDisplaySlice] = []
        slices.reserveCapacity(matchedScreens.count)
        for item in matchedScreens {
            guard let desc = layout.slices.first(where: { $0.displayID == item.id }) else { continue }
            let filter = ownApps.isEmpty
                ? SCContentFilter(display: item.scDisplay, excludingWindows: excludedCaptureWins)
                : SCContentFilter(display: item.scDisplay, excludingApplications: ownApps, exceptingWindows: [])
            let cfg = SCStreamConfiguration()
            cfg.width = max(2, Int(round(desc.cgFrame.width * desc.scale)))
            cfg.height = max(2, Int(round(desc.cgFrame.height * desc.scale)))
            cfg.showsCursor = false; cfg.captureResolution = .best
            let img = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
            slices.append(ScreenDisplaySlice(descriptor: desc, scDisplay: item.scDisplay, appKitScreen: item.screen, image: img))
        }
        guard !slices.isEmpty else {
            throw LucentError.visionFailed(L10n.pick("显示器画面捕获为空。", "Captured display slices are empty."))
        }

        let ignoredSnapIDs = shouldExcludeOwn ? Set<CGWindowID>() : ownChromeWindowIDs(includeStatusBar: true)
        let orderedWindows = includeCaptureOverlays ? [] : buildZOrderedWindows(
            scWindows: content.windows, ownPID: ownPID, excludeOwnWindows: shouldExcludeOwn,
            ignoredOwnWindowIDs: ignoredSnapIDs, cgUnion: layout.cgUnionBounds, canvasBounds: layout.canvasBounds
        )
        return ScreenTopologySnapshot(layout: layout, displays: slices, windows: orderedWindows)
    }

    static func buildZOrderedWindows(
        scWindows: [SCWindow], ownPID: pid_t, excludeOwnWindows: Bool,
        ignoredOwnWindowIDs: Set<CGWindowID>, cgUnion: CGRect, canvasBounds: CGRect
    ) -> [DetectedScreenWindow] {
        let maxOwnLayer = Int(CGWindowLevelForKey(.statusWindow))
        var scByID: [CGWindowID: SCWindow] = [:]
        for w in scWindows where w.isOnScreen {
            let pid = w.owningApplication?.processID ?? 0
            if CaptureSelfVisibilityPolicy.shouldIncludeInSnapList(
                ownerPID: pid, ownPID: ownPID, windowLayer: w.windowLayer, windowID: w.windowID,
                excludeOwnWindows: excludeOwnWindows, ignoredOwnWindowIDs: ignoredOwnWindowIDs, maxOwnWindowLayer: maxOwnLayer
            ) { scByID[w.windowID] = w }
        }
        let rawInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var result: [DetectedScreenWindow] = []
        var seen = Set<CGWindowID>()
        func appendWindow(_ scWin: SCWindow, fallbackOwner: String, fallbackTitle: String) {
            let owner = scWin.owningApplication?.applicationName ?? fallbackOwner
            guard !ignoredOwnerNames.contains(owner) && !ignoredOwnerNames.contains(fallbackOwner) else { return }
            let rect = scWin.frame.offsetBy(dx: -cgUnion.minX, dy: -cgUnion.minY).intersection(canvasBounds)
            guard !rect.isNull, rect.width >= 36, rect.height >= 36 else { return }
            result.append(DetectedScreenWindow(id: scWin.windowID, ownerName: owner, title: scWin.title ?? fallbackTitle, frame: rect))
        }
        for entry in rawInfo {
            guard let layer = entry[kCGWindowLayer as String] as? Int,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let winIDNum = entry[kCGWindowNumber as String] as? UInt32 else { continue }
            let winID = CGWindowID(winIDNum)
            guard CaptureSelfVisibilityPolicy.shouldIncludeInSnapList(
                ownerPID: pid, ownPID: ownPID, windowLayer: layer, windowID: winID,
                excludeOwnWindows: excludeOwnWindows, ignoredOwnWindowIDs: ignoredOwnWindowIDs, maxOwnWindowLayer: maxOwnLayer
            ), seen.insert(winID).inserted else { continue }
            let alpha = (entry[kCGWindowAlpha as String] as? Double) ?? 1.0
            guard alpha > 0.05, let scWin = scByID[winID] else { continue }
            appendWindow(scWin, fallbackOwner: (entry[kCGWindowOwnerName as String] as? String) ?? "", fallbackTitle: (entry[kCGWindowName as String] as? String) ?? "")
        }
        for scWin in scWindows where !seen.contains(scWin.windowID) && scByID[scWin.windowID] != nil {
            appendWindow(scWin, fallbackOwner: "", fallbackTitle: "")
        }
        return result
    }

    static func captureIndependentWindowImage(
        windowID: CGWindowID, ignoreShadow: Bool, fallbackScale: CGFloat
    ) async throws -> (image: CGImage, scale: CGFloat)? {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        guard let scWin = content.windows.first(where: { $0.windowID == windowID }) else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: scWin)
        guard let logicalSize = CaptureSelectionGeometry.resolvedWindowCaptureSize(
            filterContentRect: filter.contentRect, fallbackWindowFrame: scWin.frame
        ) else { return nil }
        let nativeScale = CGFloat(filter.pointPixelScale)
        let effScale = nativeScale >= 1.0 ? nativeScale : max(fallbackScale, 1.0)
        let cfg = SCStreamConfiguration()
        cfg.width = max(2, Int(round(logicalSize.width * effScale)))
        cfg.height = max(2, Int(round(logicalSize.height * effScale)))
        cfg.scalesToFit = false; cfg.showsCursor = false
        cfg.ignoreShadowsSingleWindow = ignoreShadow
        cfg.shouldBeOpaque = false; cfg.backgroundColor = .clear
        cfg.captureResolution = .best
        let img = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
        guard img.width >= 4, img.height >= 4 else { return nil }
        return (img, effScale)
    }

    @MainActor
    static func activeCursorScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) || $0.frame.contains(mouse) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    static func captureCrossDisplayRegion(
        canvasRect: CGRect,
        displays: [(scDisplay: SCDisplay, canvasFrame: CGRect, scale: CGFloat)],
        excludedWindows: [SCWindow],
        showsCursor: Bool,
        outputSize: (Int, Int)
    ) async -> CGImage? {
        var pieces: [(CGRect, CGImage)] = []
        for disp in displays {
            guard let localSrc = MultiDisplayLayout.clampedLocalSourceRect(forSelection: canvasRect, in: disp.canvasFrame) else { continue }
            let inter = disp.canvasFrame.intersection(canvasRect.standardized)
            guard !inter.isNull, inter.width >= 2, inter.height >= 2 else { continue }
            let filter = SCContentFilter(display: disp.scDisplay, excludingWindows: excludedWindows)
            let cfg = SCStreamConfiguration()
            cfg.sourceRect = localSrc
            cfg.width = max(2, Int(round(localSrc.width * disp.scale)))
            cfg.height = max(2, Int(round(localSrc.height * disp.scale)))
            cfg.showsCursor = showsCursor
            cfg.scalesToFit = true
            if let img = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg) {
                pieces.append((inter.offsetBy(dx: -canvasRect.minX, dy: -canvasRect.minY), img))
            }
        }
        guard !pieces.isEmpty else { return nil }
        let outW = max(2, outputSize.0), outH = max(2, outputSize.1)
        let sx = CGFloat(outW) / max(canvasRect.width, 1), sy = CGFloat(outH) / max(canvasRect.height, 1)
        let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: outW, height: outH, bitsPerComponent: 8, bytesPerRow: outW * 4,
            space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        for (rel, img) in pieces {
            ctx.draw(img, in: CGRect(x: rel.minX * sx, y: (canvasRect.height - rel.maxY) * sy, width: rel.width * sx, height: rel.height * sy))
        }
        return ctx.makeImage()
    }
}

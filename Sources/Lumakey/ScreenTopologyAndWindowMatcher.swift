import AppKit
import CoreGraphics
import Foundation
import LumakeyCore
@preconcurrency import ScreenCaptureKit

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

import SwiftUI

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
    var id: CGDirectDisplayID { descriptor.displayID }
    let descriptor: DisplaySliceDescriptor
    let scDisplay: SCDisplay
    let appKitScreen: NSScreen
    let image: CGImage
    let pixelatedImage: CGImage?

    var displayID: CGDirectDisplayID { descriptor.displayID }
    var cgFrame: CGRect { descriptor.cgFrame }
    var canvasFrame: CGRect { descriptor.canvasFrame }
    var scale: CGFloat { descriptor.scale }
}

@MainActor
struct ScreenTopologySnapshot {
    let layout: MultiDisplayLayout
    let displays: [ScreenDisplaySlice]
    let windows: [DetectedScreenWindow]

    var cgUnionBounds: CGRect { layout.cgUnionBounds }
    var canvasBounds: CGRect { layout.canvasBounds }
    var primaryScreenHeight: CGFloat { layout.primaryScreenHeight }
    var maxScale: CGFloat { layout.maxScale }

    var compositorSlices: [(canvasFrame: CGRect, scale: CGFloat, image: CGImage)] {
        displays.map { ($0.canvasFrame, $0.scale, $0.image) }
    }

    var colorSampleSlices: [(canvasFrame: CGRect, image: CGImage)] {
        displays.map { ($0.canvasFrame, $0.image) }
    }

    func canvasPoint(fromAppKitGlobal nsPt: NSPoint) -> CGPoint {
        layout.canvasPoint(fromAppKitGlobal: nsPt)
    }

    func appKitGlobalRect(fromCanvas rect: CGRect) -> NSRect {
        layout.appKitGlobalRect(fromCanvas: rect)
    }

    func clampedPinRect(fromCanvas rect: CGRect) -> NSRect {
        layout.clampedPinFrame(forAppKitSelection: layout.appKitGlobalRect(fromCanvas: rect))
    }

    func effectiveScale(forSelection rect: CGRect) -> CGFloat {
        layout.effectiveScale(forSelection: rect)
    }

    func displaySlice(containingCanvasPoint pt: CGPoint) -> ScreenDisplaySlice? {
        guard let desc = layout.slice(containingCanvasPoint: pt) else { return displays.first }
        return displays.first { $0.displayID == desc.displayID }
    }

    func targetSlice(forSelection sel: CGRect, fallbackPoint: CGPoint) -> ScreenDisplaySlice? {
        guard let desc = layout.targetSlice(forSelection: sel, fallbackPoint: fallbackPoint) else {
            return displaySlice(containingCanvasPoint: fallbackPoint)
        }
        return displays.first { $0.displayID == desc.displayID }
    }
}

@MainActor
enum ScreenTopologyAndWindowMatcher {
    private static let ignoredOwnerNames: Set<String> = [
        "Window Server", "WindowServer", "Dock", "Wallpaper", "Control Center", "控制中心", "Notification Center", "通知中心"
    ]

    static func screenDisplayID(_ screen: NSScreen) -> CGDirectDisplayID {
        let num = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        return CGDirectDisplayID(num)
    }

    @MainActor
    static func captureSnapshot(includePixelatedPreview: Bool = true) async throws -> ScreenTopologySnapshot {
        let nsScreens = NSScreen.screens
        guard !nsScreens.isEmpty else {
            throw LumakeyError.visionFailed(L10n.pick("未检测到可用显示器。", "No available display detected."))
        }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard !content.displays.isEmpty else {
            throw LumakeyError.visionFailed(L10n.pick("未检测到可捕获的显示器。", "No shareable display detected."))
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownApps = content.applications.filter { $0.processID == ownPID }

        var matchedScreens: [(scDisplay: SCDisplay, screen: NSScreen, id: CGDirectDisplayID, scale: CGFloat)] = []
        for screen in nsScreens {
            let id = screenDisplayID(screen)
            guard id != 0, let scDisp = content.displays.first(where: { $0.displayID == id }) else { continue }
            matchedScreens.append((scDisp, screen, id, max(screen.backingScaleFactor, 1.0)))
        }
        if matchedScreens.isEmpty, let firstDisp = content.displays.first {
            matchedScreens.append((firstDisp, nsScreens[0], firstDisp.displayID, max(nsScreens[0].backingScaleFactor, 1.0)))
        }

        let layoutInputs = matchedScreens.map {
            (displayID: $0.id, appKitFrame: $0.screen.frame, appKitVisibleFrame: $0.screen.visibleFrame, scale: $0.scale)
        }
        let layout = MultiDisplayLayout(screens: layoutInputs, mainDisplayID: CGMainDisplayID())

        var slices: [ScreenDisplaySlice] = []
        slices.reserveCapacity(matchedScreens.count)
        for item in matchedScreens {
            guard let desc = layout.slices.first(where: { $0.displayID == item.id }) else { continue }
            let filter = SCContentFilter(display: item.scDisplay, excludingApplications: ownApps, exceptingWindows: [])
            let cfg = SCStreamConfiguration()
            cfg.width = max(2, Int(round(desc.cgFrame.width * desc.scale)))
            cfg.height = max(2, Int(round(desc.cgFrame.height * desc.scale)))
            cfg.showsCursor = false
            cfg.captureResolution = .best
            let img = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
            let pix = includePixelatedPreview ? ScreenshotCompositor.makePixelatedPreview(from: img, cellPixelSize: max(8, Int(round(8 * desc.scale)))) : nil
            slices.append(ScreenDisplaySlice(
                descriptor: desc, scDisplay: item.scDisplay, appKitScreen: item.screen,
                image: img, pixelatedImage: pix
            ))
        }

        guard !slices.isEmpty else {
            throw LumakeyError.visionFailed(L10n.pick("显示器画面捕获为空。", "Captured display slices are empty."))
        }

        let orderedWindows = buildZOrderedWindows(
            scWindows: content.windows, ownPID: ownPID,
            cgUnion: layout.cgUnionBounds, canvasBounds: layout.canvasBounds
        )
        return ScreenTopologySnapshot(layout: layout, displays: slices, windows: orderedWindows)
    }

    static func buildZOrderedWindows(
        scWindows: [SCWindow], ownPID: pid_t, cgUnion: CGRect, canvasBounds: CGRect
    ) -> [DetectedScreenWindow] {
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

    static func captureIndependentWindowImage(
        windowID: CGWindowID, ignoreShadow: Bool, fallbackScale: CGFloat
    ) async throws -> (image: CGImage, scale: CGFloat)? {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        guard let scWin = content.windows.first(where: { $0.windowID == windowID }) else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: scWin)
        let rect = filter.contentRect
        let nativeScale = CGFloat(filter.pointPixelScale)
        let effScale = nativeScale >= 1.0 ? nativeScale : max(fallbackScale, 1.0)
        let cfg = SCStreamConfiguration()
        cfg.width = max(2, Int(round(rect.width * effScale)))
        cfg.height = max(2, Int(round(rect.height * effScale)))
        cfg.scalesToFit = false; cfg.showsCursor = false
        cfg.ignoreShadowsSingleWindow = ignoreShadow
        cfg.shouldBeOpaque = false; cfg.backgroundColor = .clear
        cfg.captureResolution = .best
        let img = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
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

import AppKit
import CoreGraphics
import Foundation
import LucentCore
import LucentMedia
@preconcurrency import ScreenCaptureKit
import SwiftUI

final class CaptureOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class SliceLazyEffectsCache: ObservableObject {
    @Published private(set) var pixelatedByDisplay: [CGDirectDisplayID: CGImage] = [:]
    @Published private(set) var blurredByDisplay: [CGDirectDisplayID: CGImage] = [:]

    func ensurePixelated(for slice: ScreenDisplaySlice) -> CGImage? {
        if let cached = pixelatedByDisplay[slice.displayID] { return cached }
        let cell = max(8, Int(round(8 * slice.scale)))
        guard let generated = ScreenshotCompositor.makePixelatedPreview(from: slice.image, cellPixelSize: cell) else {
            return nil
        }
        pixelatedByDisplay[slice.displayID] = generated
        return generated
    }

    func ensureBlurred(for slice: ScreenDisplaySlice) -> CGImage? {
        if let cached = blurredByDisplay[slice.displayID] { return cached }
        guard let generated = ScreenshotCompositor.makeBlurredPreview(from: slice.image, radius: Double(16.0 * slice.scale)) else {
            return nil
        }
        blurredByDisplay[slice.displayID] = generated
        return generated
    }
}

struct ScreenDisplaySlice: Identifiable {
    var id: CGDirectDisplayID { descriptor.displayID }
    let descriptor: DisplaySliceDescriptor
    let scDisplay: SCDisplay?
    let appKitScreen: NSScreen
    let image: CGImage

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
    let effectsCache = SliceLazyEffectsCache()

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

    func quartzGlobalPoint(fromCanvas pt: CGPoint) -> CGPoint {
        CGPoint(x: pt.x + cgUnionBounds.minX, y: pt.y + cgUnionBounds.minY)
    }

    func canvasRect(fromQuartzGlobal rect: CGRect) -> CGRect {
        layout.canvasRect(fromQuartzGlobal: rect).intersection(canvasBounds)
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

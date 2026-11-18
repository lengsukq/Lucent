import AppKit
import LucentCore
import SwiftUI

enum LucentBrandIcon {
    nonisolated(unsafe) private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 32
        return c
    }()

    static func appIconImage(pointSize: CGFloat = 512) -> NSImage {
        image(pointSize: pointSize, includeOuterMargin: true)
    }

    static func statusBarImage(pointSize: CGFloat = 17) -> NSImage {
        let img = image(pointSize: pointSize, includeOuterMargin: false)
        img.isTemplate = false
        return img
    }

    static func image(pointSize: CGFloat, includeOuterMargin: Bool = false) -> NSImage {
        let bucket = max(14, Int((pointSize * 2.0).rounded()))
        let key = "\(includeOuterMargin ? "app" : "ui"):\(bucket)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let px = max(32, bucket)
        guard let cg = BrandIconRenderer.renderCGImage(pixelSize: px, includeOuterMargin: includeOuterMargin) else {
            return NSImage(size: NSSize(width: pointSize, height: pointSize))
        }
        let nsImage = NSImage(cgImage: cg, size: NSSize(width: pointSize, height: pointSize))
        cache.setObject(nsImage, forKey: key)
        return nsImage
    }
}

struct LucentBrandIconView: View {
    var size: CGFloat = 36
    var showAmbientGlow: Bool = false

    var body: some View {
        Image(nsImage: LucentBrandIcon.image(pointSize: size, includeOuterMargin: false))
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .shadow(
                color: showAmbientGlow ? Color.cyan.opacity(0.34) : Color.black.opacity(0.18),
                radius: showAmbientGlow ? max(6, size * 0.16) : max(2, size * 0.08),
                y: max(1, size * 0.05)
            )
    }
}

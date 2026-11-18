import AppKit
import Foundation

@main
struct GenerateIconMain {
    static func main() throws {
        guard CommandLine.arguments.count >= 2 else {
            fputs("Usage: generate-icon <output-iconset-dir>\n", stderr)
            exit(1)
        }

        let outputDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let slots: [(name: String, px: Int)] = [
            ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
        ]

        for slot in slots {
            guard let cgImage = BrandIconRenderer.renderCGImage(pixelSize: slot.px, includeOuterMargin: true),
                  let pngData = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
                fputs("ERROR: Failed to render icon slot \(slot.name)\n", stderr)
                exit(1)
            }
            try pngData.write(to: outputDir.appendingPathComponent(slot.name))
        }
    }
}

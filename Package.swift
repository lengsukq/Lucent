// swift-tools-version: 6.0
import Foundation
import PackageDescription

let cltTestingPluginDir = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
var testSwiftSettings: [SwiftSetting] = [.swiftLanguageMode(.v6)]
if FileManager.default.fileExists(atPath: "\(cltTestingPluginDir)/libTestingMacros.dylib") {
    testSwiftSettings.append(.unsafeFlags(["-plugin-path", cltTestingPluginDir]))
}

let package = Package(
    name: "Lumakey",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "LumakeyFoundation", targets: ["LumakeyFoundation"]),
        .library(name: "LumakeySearch", targets: ["LumakeySearch"]),
        .library(name: "LumakeyMedia", targets: ["LumakeyMedia"]),
        .library(name: "LumakeySystem", targets: ["LumakeySystem"]),
        .library(name: "LumakeyCore", targets: ["LumakeyCore"]),
        .executable(name: "Lumakey", targets: ["Lumakey"]),
        .executable(name: "lumakey-mcp", targets: ["lumakey-mcp"]),
        .executable(name: "lumakey-check", targets: ["lumakey-check"])
    ],
    targets: [
        .target(
            name: "LumakeyFoundation",
            path: "Sources/LumakeyFoundation",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "LumakeySearch",
            dependencies: ["LumakeyFoundation"],
            path: "Sources/LumakeySearch",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "LumakeyMedia",
            dependencies: ["LumakeyFoundation", "LumakeySearch"],
            path: "Sources/LumakeyMedia",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "LumakeySystem",
            dependencies: ["LumakeyFoundation"],
            path: "Sources/LumakeySystem",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "LumakeyCore",
            dependencies: [
                "LumakeyFoundation",
                "LumakeySearch",
                "LumakeyMedia",
                "LumakeySystem"
            ],
            path: "Sources/LumakeyCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "Lumakey",
            dependencies: ["LumakeyCore"],
            path: "Sources/Lumakey",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "lumakey-mcp",
            dependencies: ["LumakeyCore"],
            path: "Sources/LumakeyMCP",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "lumakey-check",
            dependencies: ["LumakeyCore"],
            path: "Tests/LumakeyCheck",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "LumakeyTests",
            dependencies: [
                "LumakeyFoundation",
                "LumakeySearch",
                "LumakeyMedia",
                "LumakeySystem",
                "LumakeyCore"
            ],
            path: "Tests/LumakeyTests",
            swiftSettings: testSwiftSettings
        )
    ]
)

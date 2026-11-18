// swift-tools-version: 6.0
import Foundation
import PackageDescription

let cltTestingPluginDir = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
var testSwiftSettings: [SwiftSetting] = [.swiftLanguageMode(.v6)]
if FileManager.default.fileExists(atPath: "\(cltTestingPluginDir)/libTestingMacros.dylib") {
    testSwiftSettings.append(.unsafeFlags(["-plugin-path", cltTestingPluginDir]))
}

let package = Package(
    name: "Lucent",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "LucentFoundation", targets: ["LucentFoundation"]),
        .library(name: "LucentSearch", targets: ["LucentSearch"]),
        .library(name: "LucentMedia", targets: ["LucentMedia"]),
        .library(name: "LucentSystem", targets: ["LucentSystem"]),
        .library(name: "LucentCore", targets: ["LucentCore"]),
        .executable(name: "Lucent", targets: ["Lucent"]),
        .executable(name: "lucent-mcp", targets: ["lucent-mcp"]),
        .executable(name: "lucent-check", targets: ["lucent-check"])
    ],
    targets: [
        .target(
            name: "LucentFoundation",
            path: "Sources/LucentFoundation",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "LucentSearch",
            dependencies: ["LucentFoundation"],
            path: "Sources/LucentSearch",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "LucentMedia",
            dependencies: ["LucentFoundation", "LucentSearch"],
            path: "Sources/LucentMedia",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "LucentSystem",
            dependencies: ["LucentFoundation"],
            path: "Sources/LucentSystem",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "LucentCore",
            dependencies: [
                "LucentFoundation",
                "LucentSearch",
                "LucentMedia",
                "LucentSystem"
            ],
            path: "Sources/LucentCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "Lucent",
            dependencies: ["LucentCore"],
            path: "Sources/Lucent",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "lucent-mcp",
            dependencies: ["LucentCore"],
            path: "Sources/LucentMCP",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "lucent-check",
            dependencies: ["LucentCore"],
            path: "Tests/LucentCheck",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "LucentTests",
            dependencies: [
                "LucentFoundation",
                "LucentSearch",
                "LucentMedia",
                "LucentSystem",
                "LucentCore"
            ],
            path: "Tests/LucentTests",
            swiftSettings: testSwiftSettings
        )
    ]
)

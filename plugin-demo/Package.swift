// swift-tools-version: 6.0
import PackageDescription

let demoPlugins = [
    "browser-hub",
    "lumalink-companion",
    "mac-pilot",
    "notion-bookmarks",
    "quick-remind",
    "screen-shield",
    "translate-hub"
]

let starterPlugins = [
    "sys-ip-dns",
    "port-killer",
    "shell-note"
]

var targets: [Target] = [
    .target(
        name: "PluginKit",
        path: "Shared/PluginKit",
        swiftSettings: [.swiftLanguageMode(.v6)]
    )
]

for id in demoPlugins {
    var linker: [LinkerSetting] = []
    if id == "browser-hub" {
        linker.append(.linkedLibrary("sqlite3"))
    }
    targets.append(
        .executableTarget(
            name: id,
            dependencies: ["PluginKit"],
            path: "\(id)/Sources",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: linker
        )
    )
}

for id in starterPlugins {
    targets.append(
        .executableTarget(
            name: id,
            dependencies: ["PluginKit"],
            path: "Starters/\(id)/Sources",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    )
}

let package = Package(
    name: "LumakeyDemoPlugins",
    platforms: [.macOS(.v14)],
    products: (demoPlugins + starterPlugins).map { .executable(name: $0, targets: [$0]) },
    targets: targets
)

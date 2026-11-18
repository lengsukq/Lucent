import LucentFoundation
import Foundation

extension HomeProfile {
    public static func dockItems(fromAppPaths paths: [String]) -> [HomeLaunchItem] {
        var seen = Set<String>()
        var items: [HomeLaunchItem] = []
        for raw in paths {
            let std = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath).standardizedFileURL.path
            guard std.hasPrefix("/"), std.lowercased().hasSuffix(".app"), seen.insert(std).inserted else { continue }
            let slug = URL(fileURLWithPath: std).deletingPathExtension().lastPathComponent
                .lowercased()
                .filter { ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9") || $0 == "-" }
            let id = "app-\(slug.isEmpty ? "item" : slug)-\(items.count)"
            items.append(HomeLaunchItem(id: id, target: .nativeApp(path: std)))
            if items.count >= 24 { break }
        }
        return items
    }

    public static func defaultBentoItems() -> [HomeLaunchItem] {
        [
            HomeLaunchItem(id: "tile-files", target: .builtin(.files)),
            HomeLaunchItem(id: "tile-clipboard", target: .builtin(.clipboard)),
            HomeLaunchItem(id: "tile-pin", target: .builtin(.screenshotPin)),
            HomeLaunchItem(id: "tile-gif", target: .builtin(.gifRecord)),
            HomeLaunchItem(id: "tile-ocr", target: .builtin(.ocr)),
            HomeLaunchItem(id: "tile-network", target: .builtin(.networkMonitor))
        ]
    }

    public static func defaultUtilityChips() -> [HomeLaunchItem] {
        [
            HomeLaunchItem(id: "chip-math", target: .queryChip(query: "128 * 48")),
            HomeLaunchItem(id: "chip-ts", target: .queryChip(query: "ts")),
            HomeLaunchItem(id: "chip-uuid", target: .queryChip(query: "uuid")),
            HomeLaunchItem(id: "chip-snip", target: .queryChip(query: ";date")),
            HomeLaunchItem(id: "chip-qr", target: .queryChip(query: "qr Lucent")),
            HomeLaunchItem(id: "chip-port", target: .queryChip(query: "port 3000"))
        ]
    }

    public static func defaultUtilityRightItems() -> [HomeLaunchItem] {
        [
            HomeLaunchItem(id: "util-pulse", target: .builtin(.systemPulse)),
            HomeLaunchItem(id: "util-plugins", target: .builtin(.pluginsList)),
            HomeLaunchItem(id: "util-backup", target: .builtin(.backupSync))
        ]
    }

    public static func makePreset(
        _ preset: HomeLayoutPreset,
        id: String = HomeProfile.defaultProfileID,
        name: String? = nil,
        symbol: String? = nil,
        pinnedAppPaths: [String] = []
    ) -> HomeProfile {
        let seededDock = dockItems(fromAppPaths: pinnedAppPaths)
        switch preset {
        case .balanced:
            return HomeProfile(
                id: id,
                name: name ?? L10n.pick("默认主页", "Default Home"),
                symbol: symbol ?? "sparkles",
                sectionOrder: HomeSectionKind.allCases,
                hiddenSections: [],
                bentoColumns: .three,
                bentoItems: defaultBentoItems(),
                dockRows: 1,
                dockFillMode: .smartHybrid,
                dockItems: seededDock,
                pillShelves: [
                    HomePillShelf(
                        id: HomePillShelf.defaultQuickShelfID,
                        title: L10n.pick("快捷按钮与书签", "Quick Actions & Bookmarks"),
                        symbol: "bolt.circle.fill",
                        accentColor: "orange",
                        includeLegacyQuickButtons: true
                    )
                ],
                utilityChips: defaultUtilityChips(),
                utilityRightItems: defaultUtilityRightItems(),
                compactFooterBar: true
            )
        case .minimal:
            return HomeProfile(
                id: id,
                name: name ?? L10n.pick("极简纯搜", "Minimal Focus"),
                symbol: symbol ?? "circle.grid.2x2",
                sectionOrder: [.omniDock, .pillShelves, .bentoGrid, .utilityStrip],
                hiddenSections: [.bentoGrid, .utilityStrip],
                bentoColumns: .three,
                bentoItems: defaultBentoItems(),
                dockRows: 2,
                dockFillMode: .smartHybrid,
                dockItems: seededDock,
                pillShelves: [
                    HomePillShelf(
                        id: HomePillShelf.defaultQuickShelfID,
                        title: L10n.pick("快捷直达", "Quick Access"),
                        symbol: "bolt.circle.fill",
                        accentColor: "cyan",
                        includeLegacyQuickButtons: true
                    )
                ],
                utilityChips: defaultUtilityChips(),
                utilityRightItems: defaultUtilityRightItems(),
                compactFooterBar: true
            )
        case .developer:
            return HomeProfile(
                id: id,
                name: name ?? L10n.pick("开发者工作台", "Developer Hub"),
                symbol: symbol ?? "hammer.fill",
                sectionOrder: [.bentoGrid, .pillShelves, .omniDock, .utilityStrip],
                hiddenSections: [],
                bentoColumns: .three,
                bentoItems: [
                    HomeLaunchItem(id: "dev-workspace", target: .builtin(.fileWorkspace)),
                    HomeLaunchItem(id: "dev-pin", target: .builtin(.screenshotPin)),
                    HomeLaunchItem(id: "dev-ocr", target: .builtin(.ocr)),
                    HomeLaunchItem(id: "dev-net", target: .builtin(.networkMonitor)),
                    HomeLaunchItem(id: "dev-pulse", target: .builtin(.systemPulse)),
                    HomeLaunchItem(id: "dev-ram", target: .builtin(.reclaimMemory))
                ],
                dockRows: 1,
                dockFillMode: .smartHybrid,
                dockItems: seededDock,
                pillShelves: [
                    HomePillShelf(
                        id: HomePillShelf.defaultQuickShelfID,
                        title: L10n.pick("开发插件与命令", "Dev Plugins & Commands"),
                        symbol: "terminal.fill",
                        accentColor: "mint",
                        includeLegacyQuickButtons: true
                    ),
                    HomePillShelf(
                        id: "dev-bookmarks",
                        title: L10n.pick("开发书签", "Dev Bookmarks"),
                        symbol: "bookmark.fill",
                        accentColor: "cyan",
                        items: [
                            HomeLaunchItem(
                                id: "bm-github",
                                target: .bookmark(url: "https://github.com"),
                                customTitle: "GitHub",
                                customIcon: "chevron.left.forwardslash.chevron.right",
                                accentColor: "indigo"
                            ),
                            HomeLaunchItem(
                                id: "bm-localhost",
                                target: .bookmark(url: "http://localhost:3000"),
                                customTitle: "Localhost :3000",
                                customIcon: "network",
                                accentColor: "teal"
                            )
                        ]
                    )
                ],
                utilityChips: [
                    HomeLaunchItem(id: "dchip-port", target: .queryChip(query: "port 3000")),
                    HomeLaunchItem(id: "dchip-swift", target: .queryChip(query: "ext:swift", filter: "files")),
                    HomeLaunchItem(id: "dchip-ts", target: .queryChip(query: "ts")),
                    HomeLaunchItem(id: "dchip-uuid", target: .queryChip(query: "uuid"))
                ],
                utilityRightItems: defaultUtilityRightItems(),
                compactFooterBar: true
            )
        case .creatorBookmarks:
            return HomeProfile(
                id: id,
                name: name ?? L10n.pick("应用与书签中心", "Apps & Bookmarks"),
                symbol: symbol ?? "bookmark.square.fill",
                sectionOrder: [.bentoGrid, .pillShelves, .omniDock, .utilityStrip],
                hiddenSections: [.utilityStrip],
                bentoColumns: .four,
                bentoItems: [
                    HomeLaunchItem(id: "cb-files", target: .builtin(.files)),
                    HomeLaunchItem(id: "cb-clip", target: .builtin(.clipboard)),
                    HomeLaunchItem(id: "cb-pin", target: .builtin(.screenshotPin)),
                    HomeLaunchItem(id: "cb-ocr", target: .builtin(.ocr)),
                    HomeLaunchItem(id: "cb-ws", target: .builtin(.fileWorkspace)),
                    HomeLaunchItem(id: "cb-plugins", target: .builtin(.pluginsList)),
                    HomeLaunchItem(id: "cb-snip", target: .builtin(.snippets)),
                    HomeLaunchItem(id: "cb-backup", target: .builtin(.backupSync))
                ],
                dockRows: 1,
                dockFillMode: .smartHybrid,
                dockItems: seededDock,
                pillShelves: [
                    HomePillShelf(
                        id: "bookmarks",
                        title: L10n.pick("精选书签", "Pinned Bookmarks"),
                        symbol: "safari.fill",
                        accentColor: "blue"
                    ),
                    HomePillShelf(
                        id: HomePillShelf.defaultQuickShelfID,
                        title: L10n.pick("自制与扩展应用", "Custom & Store Apps"),
                        symbol: "bolt.circle.fill",
                        accentColor: "purple",
                        includeLegacyQuickButtons: true
                    )
                ],
                utilityChips: defaultUtilityChips(),
                utilityRightItems: defaultUtilityRightItems(),
                compactFooterBar: true
            )
        }
    }
}

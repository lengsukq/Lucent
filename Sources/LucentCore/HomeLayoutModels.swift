import LucentFoundation
import Foundation

public enum HomeSectionKind: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case bentoGrid
    case omniDock
    case pillShelves
    case utilityStrip

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .bentoGrid: L10n.pick("Bento 磁贴区", "Bento Tiles")
        case .omniDock: L10n.pick("混合高频坞", "Omni Dock")
        case .pillShelves: L10n.pick("分组书签与胶囊架", "Bookmark & Quick Shelves")
        case .utilityStrip: L10n.pick("探索提示与底栏入口", "Query Chips & Utilities")
        }
    }

    public var subtitle: String {
        switch self {
        case .bentoGrid: L10n.pick("大号毛玻璃磁贴，适合核心内置动作、主力自制插件与高频书签", "Large glass tiles for core tools, custom plugins & top bookmarks")
        case .omniDock: L10n.pick("8 或 16 格混合应用坞，支持钉选本机应用、插件、书签与文件夹", "8 or 16-slot dock mixing native apps, plugins, bookmarks & folders")
        case .pillShelves: L10n.pick("多组命名横向胶囊架，按主题收纳书签链接与插件子功能", "Named horizontal capsule shelves for bookmarks & plugin commands")
        case .utilityStrip: L10n.pick("搜索示例词与快捷状态开关（老用户可一键隐藏留白）", "Search query chips & utility pills (can be hidden for a clean look)")
        }
    }

    public var symbolName: String {
        switch self {
        case .bentoGrid: "square.grid.3x2.fill"
        case .omniDock: "dock.rectangle"
        case .pillShelves: "bookmark.square.fill"
        case .utilityStrip: "sparkles.rectangle.stack.fill"
        }
    }
}

public enum HomeBentoColumns: Int, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case two = 2
    case three = 3
    case four = 4

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .two: L10n.pick("2 列宽卡", "2 Columns")
        case .three: L10n.pick("3 列标准", "3 Columns")
        case .four: L10n.pick("4 列紧凑", "4 Columns")
        }
    }
}

public enum HomeDockFillMode: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case smartHybrid
    case manualOnly

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .smartHybrid: L10n.pick("钉选优先 + 智能高频补位", "Pinned + Smart App Fill")
        case .manualOnly: L10n.pick("纯手动白名单", "Pinned Only")
        }
    }
}

public enum HomeLayoutPreset: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case balanced
    case minimal
    case developer
    case creatorBookmarks

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .balanced: L10n.pick("均衡默认", "Balanced")
        case .minimal: L10n.pick("极简纯搜", "Minimal")
        case .developer: L10n.pick("开发者台", "Developer")
        case .creatorBookmarks: L10n.pick("书签与应用", "Apps & Bookmarks")
        }
    }

    public var subtitle: String {
        switch self {
        case .balanced: L10n.pick("3×2 核心磁贴 + 8 格智能混合坞 + 快捷胶囊", "3×2 core Bento + 8-slot smart dock + quick shelf")
        case .minimal: L10n.pick("隐藏大磁贴与提示条，仅保留双排 16 格高频混合坞", "Hide Bento & tips; keep clean 16-slot hybrid dock")
        case .developer: L10n.pick("聚焦双栏文件台、截图识字、端口探测与开发书签架", "Workspace, OCR, port probe & developer bookmark shelves")
        case .creatorBookmarks: L10n.pick("4 列紧凑磁贴 + 多组命名书签与自制插件分类架", "4-column compact tiles + categorized bookmark & plugin shelves")
        }
    }
}

public enum HomeItemDestination: Codable, Sendable, Hashable, Equatable {
    case bento
    case dock
    case shelf(String)
    case utilityChips
    case utilityRight

    public static func parse(section: String, shelfID: String? = nil) -> HomeItemDestination? {
        switch section.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "bento", "bentogrid": return .bento
        case "dock", "omnidock": return .dock
        case "shelf", "pillshelf", "pillshelves":
            let id = (shelfID ?? "quick-actions").trimmingCharacters(in: .whitespacesAndNewlines)
            return id.isEmpty ? .shelf("quick-actions") : .shelf(id)
        case "utilitychips", "chips": return .utilityChips
        case "utilityright", "utility": return .utilityRight
        default: return nil
        }
    }
}

public struct HomePillShelf: Codable, Sendable, Hashable, Identifiable, Equatable {
    public static let defaultQuickShelfID = "quick-actions"

    public var id: String
    public var title: String
    public var symbol: String
    public var accentColor: String
    public var isHidden: Bool
    public var includeLegacyQuickButtons: Bool
    public var items: [HomeLaunchItem]

    public init(
        id: String,
        title: String,
        symbol: String = "bolt.circle.fill",
        accentColor: String = "orange",
        isHidden: Bool = false,
        includeLegacyQuickButtons: Bool = false,
        items: [HomeLaunchItem] = []
    ) {
        self.id = HomeLaunchSecurity.isSafeIdentifier(id, maxLength: 48) ? id : Self.defaultQuickShelfID
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = cleanTitle.isEmpty ? L10n.pick("快捷胶囊", "Quick Shelf") : String(cleanTitle.prefix(32))
        let cleanSym = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        self.symbol = cleanSym.isEmpty ? "bolt.circle.fill" : String(cleanSym.prefix(48))
        let cleanAccent = accentColor.trimmingCharacters(in: .whitespacesAndNewlines)
        self.accentColor = cleanAccent.isEmpty ? "orange" : String(cleanAccent.prefix(24))
        self.isHidden = isHidden
        self.includeLegacyQuickButtons = includeLegacyQuickButtons
        self.items = Self.deduplicate(items, cap: 24)
    }

    static func deduplicate(_ raw: [HomeLaunchItem], cap: Int) -> [HomeLaunchItem] {
        var seen = Set<String>()
        var out: [HomeLaunchItem] = []
        for item in raw where HomeLaunchSecurity.validateItem(item) == nil {
            if seen.insert(item.id).inserted {
                out.append(item)
                if out.count >= cap { break }
            }
        }
        return out
    }
}

public struct HomeProfile: Codable, Sendable, Hashable, Identifiable, Equatable {
    public static let defaultProfileID = "default"

    public var id: String
    public var name: String
    public var symbol: String
    public var sectionOrder: [HomeSectionKind]
    public var hiddenSections: Set<HomeSectionKind>
    public var bentoColumns: HomeBentoColumns
    public var bentoItems: [HomeLaunchItem]
    public var dockRows: Int
    public var dockFillMode: HomeDockFillMode
    public var dockItems: [HomeLaunchItem]
    public var pillShelves: [HomePillShelf]
    public var utilityChips: [HomeLaunchItem]
    public var utilityRightItems: [HomeLaunchItem]
    public var compactFooterBar: Bool

    public init(
        id: String = HomeProfile.defaultProfileID,
        name: String = "默认主页",
        symbol: String = "sparkles",
        sectionOrder: [HomeSectionKind] = HomeSectionKind.allCases,
        hiddenSections: Set<HomeSectionKind> = [],
        bentoColumns: HomeBentoColumns = .three,
        bentoItems: [HomeLaunchItem] = [],
        dockRows: Int = 1,
        dockFillMode: HomeDockFillMode = .smartHybrid,
        dockItems: [HomeLaunchItem] = [],
        pillShelves: [HomePillShelf] = [],
        utilityChips: [HomeLaunchItem] = [],
        utilityRightItems: [HomeLaunchItem] = [],
        compactFooterBar: Bool = true
    ) {
        self.id = HomeLaunchSecurity.isSafeIdentifier(id, maxLength: 40) ? id : Self.defaultProfileID
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = trimmedName.isEmpty ? "默认主页" : String(trimmedName.prefix(28))
        let trimmedSym = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        self.symbol = trimmedSym.isEmpty ? "sparkles" : String(trimmedSym.prefix(48))
        self.sectionOrder = Self.normalizeSectionOrder(sectionOrder)
        self.hiddenSections = hiddenSections
        self.bentoColumns = bentoColumns
        self.bentoItems = HomePillShelf.deduplicate(bentoItems, cap: 16)
        self.dockRows = min(max(dockRows, 1), 2)
        self.dockFillMode = dockFillMode
        self.dockItems = HomePillShelf.deduplicate(dockItems, cap: 24)
        self.pillShelves = Self.normalizeShelves(pillShelves)
        self.utilityChips = HomePillShelf.deduplicate(utilityChips, cap: 12)
        self.utilityRightItems = HomePillShelf.deduplicate(utilityRightItems, cap: 6)
        self.compactFooterBar = compactFooterBar
    }

    public var dockSlotCapacity: Int { dockRows * 8 }

    public var visibleSections: [HomeSectionKind] {
        sectionOrder.filter { !hiddenSections.contains($0) }
    }

    public func isSectionVisible(_ kind: HomeSectionKind) -> Bool {
        !hiddenSections.contains(kind)
    }

    public mutating func setSectionVisible(_ kind: HomeSectionKind, visible: Bool) {
        if visible { hiddenSections.remove(kind) } else { hiddenSections.insert(kind) }
    }

    public mutating func moveSection(_ kind: HomeSectionKind, offset: Int) {
        guard let idx = sectionOrder.firstIndex(of: kind) else { return }
        let dest = min(max(0, idx + offset), sectionOrder.count - 1)
        guard dest != idx else { return }
        sectionOrder.remove(at: idx)
        sectionOrder.insert(kind, at: dest)
    }

    public static func normalizeSectionOrder(_ raw: [HomeSectionKind]) -> [HomeSectionKind] {
        var seen = Set<HomeSectionKind>()
        var ordered: [HomeSectionKind] = []
        for s in raw where seen.insert(s).inserted { ordered.append(s) }
        for s in HomeSectionKind.allCases where seen.insert(s).inserted { ordered.append(s) }
        return ordered
    }

    private static func normalizeShelves(_ raw: [HomePillShelf]) -> [HomePillShelf] {
        var seen = Set<String>()
        var out: [HomePillShelf] = []
        for shelf in raw where seen.insert(shelf.id).inserted {
            out.append(shelf)
            if out.count >= 6 { break }
        }
        return out
    }
}

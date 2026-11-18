import AppKit
import Foundation
import LucentCore

struct HomeResolvedVisual {
    let title: String
    let subtitle: String
    let symbolName: String
    let customIconURL: URL?
    let nativeAppURL: URL?
    let localFileURL: URL?
    let isDirectory: Bool
    let accentColor: String
    let hotkeyHint: String?
    let badgeText: String?
}

struct HomeResolvedDockSlot: Identifiable {
    let id: String
    let item: HomeLaunchItem
    let isExplicitlyPinned: Bool
    let visual: HomeResolvedVisual
}

extension AppViewModel {
    func installHomeLayoutObservers() {
        removeHomeLayoutObservers()
        runtime.homeLayoutObserver = DistributedNotificationCenter.default().addObserver(
            forName: HomeLayoutConfig.distributedReloadNotificationName,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let targetPath = HomeLayoutConfig.defaultConfigURL().standardizedFileURL.path
            if let senderObj = note.object as? String, !senderObj.isEmpty, senderObj != targetPath {
                return
            }
            MainActor.assumeIsolated {
                self?.reloadHomeLayoutFromDisk()
            }
        }
    }

    func removeHomeLayoutObservers() {
        runtime.removeHomeLayoutObserver()
    }

    func mutateHomeLayout(_ transform: (inout HomeLayoutConfig) -> Void) {
        var next = homeLayoutConfig
        transform(&next)
        guard next != homeLayoutConfig else { return }
        homeLayoutConfig = next
        next.save(notifyInProcess: true, notifyCrossProcess: false)
    }

    func reloadHomeLayoutFromDisk() {
        let loaded = HomeLayoutConfig.loadOrBootstrap(
            legacyPinnedAppIDs: AppUsageService.shared.pinnedAppIDs
        )
        if homeLayoutConfig != loaded {
            homeLayoutConfig = loaded
        }
    }

    func resolvedHomeVisual(for item: HomeLaunchItem) -> HomeResolvedVisual {
        switch item.target {
        case .builtin(let action):
            let dynSub: String = switch action {
            case .clipboard:
                L10n.pick("已记录 \(clipboardHistoryCount) 条", "\(clipboardHistoryCount) items saved")
            case .toggleMos:
                mosConfig.enabled ? L10n.pick("已开启 · 点击关闭", "Active · Click to turn off") : L10n.pick("已关闭 · 点击开启", "Off · Click to turn on")
            default:
                action.subtitle
            }
            return HomeResolvedVisual(
                title: item.customTitle ?? action.title,
                subtitle: item.customSubtitle ?? dynSub,
                symbolName: item.customIcon ?? action.symbolName,
                customIconURL: nil, nativeAppURL: nil, localFileURL: nil, isDirectory: false,
                accentColor: item.accentColor ?? action.defaultAccentColor,
                hotkeyHint: item.hotkeyHint ?? action.defaultHotKeyHint,
                badgeText: nil
            )
        case .nativeApp(let path, _):
            let stdPath = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path
            let appURL = URL(fileURLWithPath: stdPath)
            let matched = installedApps.first { $0.id == stdPath }
            let defaultName = matched?.displayName ?? appURL.deletingPathExtension().lastPathComponent
            let usageBadge = matched.flatMap { AppUsageTrackerController.shared.compactUsageBadge(for: $0) }.map { L10n.translate($0) }
            return HomeResolvedVisual(
                title: item.customTitle ?? defaultName,
                subtitle: item.customSubtitle ?? usageBadge ?? stdPath,
                symbolName: item.customIcon ?? "app.fill",
                customIconURL: nil,
                nativeAppURL: item.customIcon == nil ? appURL : nil,
                localFileURL: nil, isDirectory: false,
                accentColor: item.accentColor ?? "blue",
                hotkeyHint: item.hotkeyHint,
                badgeText: usageBadge
            )
        case .plugin(let pluginID, _):
            let plugin = plugins.first { $0.id == pluginID }
            let pTitle = plugin?.displayName ?? pluginID
            let pSub = plugin?.displayDescription ?? L10n.pick("未安装的插件", "Missing plugin")
            return HomeResolvedVisual(
                title: item.customTitle ?? pTitle,
                subtitle: item.customSubtitle ?? pSub,
                symbolName: item.customIcon ?? plugin?.symbolIconName ?? "puzzlepiece.extension.fill",
                customIconURL: item.customIcon == nil ? plugin?.customIconURL : nil,
                nativeAppURL: nil, localFileURL: nil, isDirectory: false,
                accentColor: item.accentColor ?? plugin?.manifest.accentColor ?? "purple",
                hotkeyHint: item.hotkeyHint ?? plugin?.effectiveHotKey,
                badgeText: L10n.pick("插件", "Plugin")
            )
        case .pluginCommand(let pluginID, let commandID, _):
            let reg = pluginCommands.first { $0.pluginID == pluginID && $0.command.id == commandID }
            let cTitle = reg?.localizedTitle ?? commandID
            let cSub = reg.map { "\($0.pluginName) · \($0.localizedSubtitle)" } ?? pluginID
            return HomeResolvedVisual(
                title: item.customTitle ?? cTitle,
                subtitle: item.customSubtitle ?? cSub,
                symbolName: item.customIcon ?? reg?.symbolName ?? "bolt.fill",
                customIconURL: item.customIcon == nil ? reg?.pluginCustomIconURL : nil,
                nativeAppURL: nil, localFileURL: nil, isDirectory: false,
                accentColor: item.accentColor ?? reg?.pluginAccentColor ?? "orange",
                hotkeyHint: item.hotkeyHint ?? reg?.effectiveHotKey,
                badgeText: reg?.pluginName
            )
        case .script(let scriptID):
            let script = scripts.first { $0.id == scriptID }
            let sTitle = script?.displayTitle ?? scriptID
            let sSub = script?.displaySubtitle ?? L10n.pick("未找到的快捷脚本", "Missing script")
            let iconURL = item.customIcon == nil ? script?.customIconURL(in: ScriptLibraryStore.shared.scriptsDirectory) : nil
            return HomeResolvedVisual(
                title: item.customTitle ?? sTitle,
                subtitle: item.customSubtitle ?? sSub,
                symbolName: item.customIcon ?? script?.symbolIconName ?? "terminal.fill",
                customIconURL: iconURL,
                nativeAppURL: nil, localFileURL: nil, isDirectory: false,
                accentColor: item.accentColor ?? script?.accentColor ?? "teal",
                hotkeyHint: item.hotkeyHint ?? script?.hotKey,
                badgeText: script?.runtime.badgeLabel ?? L10n.pick("脚本", "Script")
            )
        case .bookmark(let rawURL, _, _):
            let parsed = URL(string: rawURL)
            let host = parsed?.host ?? parsed?.scheme ?? rawURL
            return HomeResolvedVisual(
                title: item.customTitle ?? host,
                subtitle: item.customSubtitle ?? rawURL,
                symbolName: item.customIcon ?? (parsed?.scheme == "lucent" ? "sparkles" : "safari.fill"),
                customIconURL: nil, nativeAppURL: nil, localFileURL: nil, isDirectory: false,
                accentColor: item.accentColor ?? "cyan",
                hotkeyHint: item.hotkeyHint,
                badgeText: L10n.pick("书签", "Link")
            )
        case .localPath(let path):
            let fileURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
            var isDir: ObjCBool = false
            _ = FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir)
            let name = fileURL.lastPathComponent.isEmpty ? fileURL.path : fileURL.lastPathComponent
            return HomeResolvedVisual(
                title: item.customTitle ?? name,
                subtitle: item.customSubtitle ?? fileURL.deletingLastPathComponent().path,
                symbolName: item.customIcon ?? (isDir.boolValue ? "folder.fill" : "doc.fill"),
                customIconURL: nil, nativeAppURL: nil,
                localFileURL: item.customIcon == nil ? fileURL : nil,
                isDirectory: isDir.boolValue,
                accentColor: item.accentColor ?? "teal",
                hotkeyHint: item.hotkeyHint,
                badgeText: isDir.boolValue ? L10n.pick("目录", "Folder") : L10n.pick("文件", "File")
            )
        case .queryChip(let query, _):
            return HomeResolvedVisual(
                title: item.customTitle ?? query,
                subtitle: item.customSubtitle ?? L10n.pick("填入搜索：\(query)", "Fill query: \(query)"),
                symbolName: item.customIcon ?? "magnifyingglass",
                customIconURL: nil, nativeAppURL: nil, localFileURL: nil, isDirectory: false,
                accentColor: item.accentColor ?? "cyan",
                hotkeyHint: item.hotkeyHint,
                badgeText: L10n.pick("搜索词", "Query")
            )
        }
    }

    func resolvedHomeDockSlots() -> [HomeResolvedDockSlot] {
        let profile = homeLayoutConfig.activeProfile
        let cap = profile.dockSlotCapacity
        var slots: [HomeResolvedDockSlot] = []
        var usedAppPaths = Set<String>()

        for item in profile.dockItems.prefix(cap) {
            if case .nativeApp(let path, _) = item.target {
                usedAppPaths.insert(URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path)
            }
            slots.append(HomeResolvedDockSlot(
                id: item.id, item: item, isExplicitlyPinned: true, visual: resolvedHomeVisual(for: item)
            ))
        }

        if profile.dockFillMode == .smartHybrid, slots.count < cap {
            let remaining = cap - slots.count
            let ranked = AppUsageTrackerController.shared.rankedDockApps(from: installedApps, limit: cap + 12)
            for app in ranked where !usedAppPaths.contains(app.id) {
                let synth = HomeLaunchItem(id: "auto-app:\(app.id)", target: .nativeApp(path: app.id))
                slots.append(HomeResolvedDockSlot(
                    id: synth.id, item: synth,
                    isExplicitlyPinned: AppUsageTrackerController.shared.isPinned(app),
                    visual: resolvedHomeVisual(for: synth)
                ))
                if slots.count >= cap || slots.count - profile.dockItems.count >= remaining { break }
            }
        }
        return slots
    }

    func resolvedShelfItems(for shelf: HomePillShelf) -> [HomeLaunchItem] {
        var combined = shelf.items
        guard shelf.includeLegacyQuickButtons else { return combined }
        for qb in enabledQuickButtons {
            let target: HomeLaunchTarget = switch qb.target {
            case .plugin(let pid): .plugin(pluginID: pid, behavior: .auto)
            case .command(let pid, let cid): .pluginCommand(pluginID: pid, commandID: cid)
            }
            let alreadyPresent = combined.contains { existing in
                switch (existing.target, target) {
                case (.plugin(let a, _), .plugin(let b, _)): a == b
                case (.pluginCommand(let p1, let c1, _), .pluginCommand(let p2, let c2, _)): p1 == p2 && c1 == c2
                default: false
                }
            }
            if !alreadyPresent {
                combined.append(HomeLaunchItem(
                    id: "legacy-\(qb.id)", target: target,
                    customTitle: qb.title, customSubtitle: qb.subtitle, accentColor: qb.accentColor
                ))
            }
        }
        for sc in scripts where sc.isEnabled && sc.pinnedInQuickBar {
            let exists = combined.contains { if case .script(let sid) = $0.target { return sid == sc.id } else { return false } }
            if !exists {
                combined.append(HomeLaunchItem(
                    id: "legacy-script-\(sc.id)", target: .script(scriptID: sc.id),
                    customTitle: sc.displayTitle, customSubtitle: sc.displaySubtitle, accentColor: sc.accentColor
                ))
            }
        }
        return combined
    }
}

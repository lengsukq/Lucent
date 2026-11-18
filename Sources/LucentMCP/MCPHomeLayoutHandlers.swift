import Foundation
import LucentCore

extension MCPServer {
    var resolvedHomeLayoutURL: URL {
        customHomeLayoutURL ?? HomeLayoutConfig.scopedConfigURL(forPluginsRoot: pluginsDirectory)
    }

    func loadHomeConfig() -> HomeLayoutConfig {
        HomeLayoutConfig.loadOrBootstrap(from: resolvedHomeLayoutURL)
    }

    func saveHomeConfig(_ config: HomeLayoutConfig) {
        config.save(to: resolvedHomeLayoutURL, notifyInProcess: false, notifyCrossProcess: true)
    }

    private func encodeJSONObject<T: Encodable>(_ value: T) -> Any {
        guard let data = try? JSONEncoder().encode(value),
              let obj = try? JSONSerialization.jsonObject(with: data) else { return [:] }
        return obj
    }

    func handleGetHomeLayout(arguments: [String: Any]) -> [String: Any] {
        let cfg = loadHomeConfig()
        let includeCandidates = arguments["includeCandidates"] as? Bool ?? true
        let includeNativeApps = arguments["includeNativeApps"] as? Bool ?? false

        var out: [String: Any] = [
            "configPath": resolvedHomeLayoutURL.path,
            "activeProfileID": cfg.activeProfileID,
            "canUndo": cfg.lastUndoProfile != nil,
            "activeProfile": encodeJSONObject(cfg.activeProfile),
            "profiles": cfg.profiles.map { p -> [String: Any] in
                [
                    "id": p.id, "name": p.name, "symbol": p.symbol,
                    "visibleSections": p.visibleSections.map(\.rawValue),
                    "bentoCount": p.bentoItems.count,
                    "dockPinnedCount": p.dockItems.count,
                    "shelvesCount": p.pillShelves.count
                ]
            }
        ]

        if includeCandidates {
            let plugins = PluginSystem.listPlugins(in: pluginsDirectory, includeDisabled: false, includeBuiltin: true, includeSecrets: false)
            let entries = PluginSearchIndex.loadEntries(for: plugins, in: pluginsDirectory, maxItemsPerPlugin: 60)
            let bookmarks = entries.filter { ($0.url ?? "").isEmpty == false }.prefix(20).map { e -> [String: Any] in
                ["pluginID": e.pluginID, "title": e.title, "url": e.url ?? "", "subtitle": e.subtitle]
            }
            var candidates: [String: Any] = [
                "builtinActions": HomeBuiltinActionID.allCases.map { act -> [String: Any] in
                    ["id": act.rawValue, "title": act.title, "symbol": act.symbolName, "defaultAccent": act.defaultAccentColor]
                },
                "installedPlugins": plugins.map { p -> [String: Any] in
                    [
                        "id": p.id, "name": p.displayName, "isBuiltin": p.isBuiltin,
                        "hasCustomWindow": p.manifest.window != nil,
                        "commands": p.declaredCommands.map { ["id": $0.id, "title": p.manifest.localizedCommandTitle($0)] }
                    ]
                },
                "installedScripts": resolvedScriptStore.allScripts(includeDisabled: false).map { s -> [String: Any] in
                    ["id": s.id, "title": s.displayTitle, "runtime": s.runtime.rawValue, "keywords": s.keywords]
                },
                "indexedBookmarksSample": bookmarks
            ]
            if includeNativeApps {
                let apps = LauncherEngine.discoverInstalledApps().prefix(25).map { ["name": $0.displayName, "path": $0.id] }
                candidates["sampleNativeApps"] = apps
            }
            out["candidates"] = candidates
        }
        return textResult(prettyJSON(out))
    }

    func handleUpdateHomeLayout(arguments: [String: Any]) -> [String: Any] {
        var cfg = loadHomeConfig()
        do {
            if arguments["undoLastChange"] as? Bool == true {
                guard cfg.undoLastChange() else {
                    return textResult("No undo snapshot available.", isError: true)
                }
                saveHomeConfig(cfg)
                return textResult(prettyJSON(["undone": true, "activeProfileID": cfg.activeProfileID, "activeProfile": encodeJSONObject(cfg.activeProfile)]))
            }

            if let createDict = arguments["createProfile"] as? [String: Any] {
                let name = (createDict["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !name.isEmpty else { return textResult("createProfile.name is required.", isError: true) }
                let preset = (createDict["preset"] as? String).flatMap(HomeLayoutPreset.init(rawValue:)) ?? .balanced
                _ = try cfg.createProfile(
                    id: createDict["id"] as? String, name: name,
                    symbol: (createDict["symbol"] as? String) ?? "sparkles",
                    preset: preset, activate: createDict["activate"] as? Bool ?? true
                )
            }

            if let delID = arguments["deleteProfileID"] as? String {
                guard try cfg.deleteProfile(id: delID) else {
                    return textResult("Profile not found: \(delID)", isError: true)
                }
            }

            if let selID = arguments["selectProfileID"] as? String {
                guard cfg.selectProfile(id: selID) else {
                    return textResult("Profile not found: \(selID)", isError: true)
                }
            }

            if let ren = arguments["renameProfile"] as? [String: Any] {
                let pid = (ren["id"] as? String) ?? cfg.activeProfileID
                guard let idx = cfg.profiles.firstIndex(where: { $0.id == pid }) else {
                    return textResult("Profile not found: \(pid)", isError: true)
                }
                if let name = ren["name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    cfg.profiles[idx].name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(28))
                }
                if let sym = ren["symbol"] as? String, !sym.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    cfg.profiles[idx].symbol = String(sym.trimmingCharacters(in: .whitespacesAndNewlines).prefix(48))
                }
            }

            if let rawPreset = arguments["applyPreset"] as? String {
                guard let preset = HomeLayoutPreset(rawValue: rawPreset) else {
                    return textResult("Unknown preset '\(rawPreset)'.", isError: true)
                }
                let preserve = arguments["preserveDockItems"] as? Bool ?? true
                cfg.applyPreset(preset, preserveDockItems: preserve)
            }

            try applyProfileLayoutFields(&cfg, arguments: arguments)
            saveHomeConfig(cfg)
            return textResult(prettyJSON([
                "updated": true,
                "activeProfileID": cfg.activeProfileID,
                "activeProfile": encodeJSONObject(cfg.activeProfile)
            ]))
        } catch {
            return textResult("Error: \(error.localizedDescription)", isError: true)
        }
    }

    private func applyProfileLayoutFields(_ cfg: inout HomeLayoutConfig, arguments: [String: Any]) throws {
        var profile = cfg.activeProfile
        var mutated = false

        if let rawOrder = arguments["sectionOrder"] as? [String] {
            var parsed: [HomeSectionKind] = []
            for raw in rawOrder {
                guard let s = HomeSectionKind(rawValue: raw) else {
                    throw HomeLayoutError.invalidItem("Unknown section '\(raw)'.")
                }
                parsed.append(s)
            }
            profile.sectionOrder = HomeProfile.normalizeSectionOrder(parsed)
            mutated = true
        }
        if let rawHidden = arguments["hiddenSections"] as? [String] {
            var hidden = Set<HomeSectionKind>()
            for raw in rawHidden {
                guard let s = HomeSectionKind(rawValue: raw) else {
                    throw HomeLayoutError.invalidItem("Unknown section '\(raw)'.")
                }
                hidden.insert(s)
            }
            profile.hiddenSections = hidden; mutated = true
        }
        if let cols = arguments["bentoColumns"] as? Int {
            guard let parsed = HomeBentoColumns(rawValue: cols) else {
                throw HomeLayoutError.invalidItem("bentoColumns must be 2, 3, or 4.")
            }
            profile.bentoColumns = parsed; mutated = true
        }
        if let rows = arguments["dockRows"] as? Int {
            guard rows == 1 || rows == 2 else { throw HomeLayoutError.invalidItem("dockRows must be 1 or 2.") }
            profile.dockRows = rows; mutated = true
        }
        if let modeRaw = arguments["dockFillMode"] as? String {
            guard let mode = HomeDockFillMode(rawValue: modeRaw) else {
                throw HomeLayoutError.invalidItem("Unknown dockFillMode '\(modeRaw)'.")
            }
            profile.dockFillMode = mode; mutated = true
        }
        if let compact = arguments["compactFooterBar"] as? Bool {
            profile.compactFooterBar = compact; mutated = true
        }
        if let shelfObj = arguments["upsertShelf"] as? [String: Any] {
            let sid = (shelfObj["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard HomeLaunchSecurity.isSafeIdentifier(sid, maxLength: 48) else {
                throw HomeLayoutError.invalidItem("Invalid shelf id '\(sid)'.")
            }
            let title = (shelfObj["title"] as? String) ?? sid
            if let idx = profile.pillShelves.firstIndex(where: { $0.id == sid }) {
                profile.pillShelves[idx].title = String(title.prefix(32))
                if let sym = shelfObj["symbol"] as? String { profile.pillShelves[idx].symbol = sym }
                if let acc = shelfObj["accentColor"] as? String { profile.pillShelves[idx].accentColor = acc }
                if let hid = shelfObj["isHidden"] as? Bool { profile.pillShelves[idx].isHidden = hid }
                if let leg = shelfObj["includeLegacyQuickButtons"] as? Bool { profile.pillShelves[idx].includeLegacyQuickButtons = leg }
            } else {
                guard profile.pillShelves.count < 6 else { throw HomeLayoutError.shelfLimitReached }
                profile.pillShelves.append(HomePillShelf(
                    id: sid, title: title,
                    symbol: (shelfObj["symbol"] as? String) ?? "bookmark.fill",
                    accentColor: (shelfObj["accentColor"] as? String) ?? "cyan",
                    isHidden: (shelfObj["isHidden"] as? Bool) ?? false,
                    includeLegacyQuickButtons: (shelfObj["includeLegacyQuickButtons"] as? Bool) ?? false
                ))
            }
            mutated = true
        }
        if let remShelf = arguments["removeShelfID"] as? String {
            profile.pillShelves.removeAll { $0.id == remShelf }; mutated = true
        }
        if mutated { cfg.activeProfile = profile }
    }
}

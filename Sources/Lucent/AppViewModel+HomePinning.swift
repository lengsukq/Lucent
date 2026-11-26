import AppKit
import Foundation
import LucentCore

extension AppViewModel {
    func tryExecuteHomeShortcut(at index: Int) -> Bool {
        guard displayedCandidates.isEmpty, omniFilter == .all, scopedPluginID == nil,
              overlayQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let profile = homeLayoutConfig.activeProfile
        if profile.isSectionVisible(.bentoGrid), index >= 0, index < profile.bentoItems.count {
            executeHomeLaunchItem(profile.bentoItems[index])
        }
        return true
    }

    func executeHomeLaunchItem(_ item: HomeLaunchItem) {
        switch item.target {
        case .builtin(let action):
            executeHomeBuiltinAction(action)
        case .nativeApp(let path, _):
            let stdPath = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path
            if let matched = findInstalledApp(matchingRawPath: path) {
                launchApp(matched)
            } else if FileManager.default.fileExists(atPath: stdPath) {
                NSWorkspace.shared.open(URL(fileURLWithPath: stdPath))
                if !isOverlayPinned { onHideOverlayRequest?() }
            } else {
                let name = URL(fileURLWithPath: stdPath).deletingPathExtension().lastPathComponent
                serviceMessage = L10n.pick("未找到应用「\(name)」（可能已卸载或移动）", "App \"\(name)\" not found (may have been removed)")
            }
        case .plugin(let pluginID, let behavior):
            guard let plugin = plugins.first(where: { $0.id == pluginID }) else {
                serviceMessage = L10n.pick("未找到插件：\(pluginID)", "Plugin not found: \(pluginID)")
                return
            }
            switch behavior {
            case .scoped: enterPluginScopedOverlay(plugin)
            case .runInline: runPlugin(plugin, query: "", showInline: true)
            case .openWindow: openPreferredFloatingWindow(for: plugin)
            case .auto:
                if plugin.isBuiltin { runPlugin(plugin, query: "", showInline: true) }
                else if plugin.manifest.window != nil && plugin.isCapabilityGranted(.floatingWindow) {
                    openPluginCustomWindow(plugin)
                } else { enterPluginScopedOverlay(plugin) }
            }
        case .pluginCommand(let pluginID, let commandID, let argsOverride):
            guard let plugin = plugins.first(where: { $0.id == pluginID }) else { return }
            let specArgs = plugin.declaredCommands.first(where: { $0.id == commandID })?.arguments ?? []
            runPlugin(plugin, query: "", arguments: argsOverride ?? specArgs, showInline: true)
        case .script(let scriptID):
            guard let script = scripts.first(where: { $0.id == scriptID }) else {
                serviceMessage = L10n.pick("未找到快捷脚本：\(scriptID)", "Script not found: \(scriptID)")
                return
            }
            runScript(script)
        case .bookmark(let rawURL, let browserPath, let sourcePluginID):
            if let sourcePluginID { PluginSystem.recordPluginUsage(id: sourcePluginID) }
            guard let url = URL(string: rawURL) else { return }
            if url.scheme?.lowercased() == "lucent" {
                handlePluginOpenURL(url); return
            }
            if let browserPath, !browserPath.isEmpty {
                let bURL = URL(fileURLWithPath: (browserPath as NSString).expandingTildeInPath).standardizedFileURL
                if FileManager.default.fileExists(atPath: bURL.path) {
                    NSWorkspace.shared.open([url], withApplicationAt: bURL, configuration: NSWorkspace.OpenConfiguration())
                    if !isOverlayPinned { onHideOverlayRequest?() }
                    return
                }
            }
            handlePluginOpenURL(url)
            if !isOverlayPinned { onHideOverlayRequest?() }
        case .localPath(let path):
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
            executeSystemCommand(.openPath(url))
        case .queryChip(let query, let rawFilter):
            if let rawFilter, let f = OmniFilter(rawValue: rawFilter), omniFilter != f { setOmniFilter(f) }
            overlayQuery = query
            bumpFocusToken()
        }
    }

    private func executeHomeBuiltinAction(_ action: HomeBuiltinActionID) {
        switch action {
        case .files: setOmniFilter(.files)
        case .clipboard: setOmniFilter(.clipboard)
        case .screenshotPin: captureAndPinScreenshot()
        case .gifRecord: startGifRecording()
        case .videoRecord: startVideoRecording()
        case .ocr: captureAndAnalyzeOCR()
        case .networkMonitor: openRoute(.networkMonitor)
        case .fileWorkspace: openRoute(.workspace)
        case .systemPulse: SystemPulseWindowController.shared.toggleFloatingWidget()
        case .toggleMos: executeSystemCommand(.toggleMosEnabled)
        case .pluginsList: setOmniFilter(.plugins)
        case .scripts: openRoute(.settings(.scripts))
        case .snippets: openRoute(.settings(.snippets))
        case .backupSync: openRoute(.settings(.backup))
        case .cacheCleanup: openRoute(.settings(.cache))
        case .reclaimMemory: executeSystemCommand(.reclaimMemory)
        case .settingsCenter: openRoute(.settings(.general))
        }
    }

    func homeLaunchItem(from candidate: LauncherCandidate) -> HomeLaunchItem? {
        let suffix = String(UUID().uuidString.prefix(6)).lowercased()
        switch candidate.kind {
        case .app(let app):
            return HomeLaunchItem(id: "app-\(suffix)", target: .nativeApp(path: app.id))
        case .plugin(let plugin):
            return HomeLaunchItem(id: "plug-\(plugin.id)", target: .plugin(pluginID: plugin.id))
        case .pluginCommand(let cmd):
            return HomeLaunchItem(
                id: "cmd-\(cmd.pluginID)-\(cmd.command.id)",
                target: .pluginCommand(pluginID: cmd.pluginID, commandID: cmd.command.id)
            )
        case .pluginItem(let entry):
            if let url = entry.url, !url.isEmpty {
                return HomeLaunchItem(
                    id: "bm-\(suffix)",
                    target: .bookmark(url: url, sourcePluginID: entry.pluginID),
                    customTitle: entry.title,
                    customSubtitle: entry.subtitle.isEmpty ? nil : entry.subtitle,
                    customIcon: entry.icon,
                    accentColor: entry.tintColor
                )
            }
            if let args = entry.commandArgs, !args.isEmpty {
                return HomeLaunchItem(
                    id: "pitem-\(suffix)",
                    target: .pluginCommand(pluginID: entry.pluginID, commandID: "item", arguments: args),
                    customTitle: entry.title, customSubtitle: entry.subtitle, accentColor: entry.tintColor
                )
            }
            return nil
        case .fileHit(let hit):
            return HomeLaunchItem(id: "path-\(suffix)", target: .localPath(path: hit.url.path))
        case .script(let match):
            return HomeLaunchItem(id: "script-\(match.script.id)", target: .script(scriptID: match.script.id))
        case .snippet(let match):
            let q = match.snippet.keyword.isEmpty ? match.snippet.title : match.snippet.keyword
            return HomeLaunchItem(
                id: "snip-\(suffix)", target: .queryChip(query: q),
                customTitle: match.snippet.title, customIcon: "text.quote", accentColor: "indigo"
            )
        default:
            return nil
        }
    }

    func pinCandidateToHome(_ candidate: LauncherCandidate, destination: HomeItemDestination, shelfTitle: String? = nil) {
        guard let item = homeLaunchItem(from: candidate) else { return }
        let vis = resolvedHomeVisual(for: item)
        mutateHomeLayout { try? $0.upsertItem(item, in: destination, shelfTitle: shelfTitle) }
        if case .dock = destination, case .nativeApp(let path, _) = item.target {
            AppUsageTrackerController.shared.setPinned(true, appID: path)
        }
        let destLabel: String = switch destination {
        case .bento: L10n.pick("Bento 磁贴区", "Bento Tiles")
        case .dock: L10n.pick("混合高频坞", "Omni Dock")
        case .shelf(let id): shelfTitle ?? id
        case .utilityChips: L10n.pick("搜索词条", "Query Chips")
        case .utilityRight: L10n.pick("底栏入口", "Utility Strip")
        }
        serviceMessage = L10n.pick("已将「\(vis.title)」钉到\(destLabel)", "Pinned \"\(vis.title)\" to \(destLabel)")
    }

    func toggleHomeDockSlotPin(_ slot: HomeResolvedDockSlot) {
        if slot.isExplicitlyPinned {
            mutateHomeLayout { _ = $0.removeItem(id: slot.item.id, from: .dock) }
            if case .nativeApp(let path, _) = slot.item.target { AppUsageTrackerController.shared.setPinned(false, appID: path) }
            serviceMessage = L10n.pick("已从混合高频坞取消钉选「\(slot.visual.title)」", "Unpinned \"\(slot.visual.title)\"")
        } else {
            var copy = slot.item
            if copy.id.hasPrefix("auto-app:") { copy.id = "dock-app-\(UUID().uuidString.prefix(6).lowercased())" }
            mutateHomeLayout { try? $0.upsertItem(copy, in: .dock) }
            if case .nativeApp(let path, _) = copy.target { AppUsageTrackerController.shared.setPinned(true, appID: path) }
            serviceMessage = L10n.pick("已将「\(slot.visual.title)」固定到混合高频坞", "Pinned \"\(slot.visual.title)\" to Dock")
        }
    }

    func moveHomeDockSlot(_ slot: HomeResolvedDockSlot, offset: Int) {
        if slot.item.id.hasPrefix("auto-app:") {
            if case .nativeApp(let path, _) = slot.item.target,
               let app = findInstalledApp(matchingRawPath: path) {
                AppUsageTrackerController.shared.movePin(app, delta: offset)
            }
            return
        }
        mutateHomeLayout { _ = $0.moveItem(id: slot.item.id, in: .dock, offset: offset) }
    }

    func removeLegacyOrHomeShelfItem(_ item: HomeLaunchItem, shelfID: String) {
        if item.id.hasPrefix("legacy-") {
            switch item.target {
            case .plugin(let pid, _):
                try? PluginSystem.updatePluginOverrides(id: pid) { $0.pinnedInOverlay = false }; reloadPlugins()
            case .pluginCommand(let pid, let cid, _):
                try? PluginSystem.setPluginCommandQuickButton(pluginID: pid, commandID: cid, enabled: false); reloadPlugins()
            case .script(let sid):
                if let sc = scripts.first(where: { $0.id == sid }) { toggleScriptQuickBarPin(sc) }
            default: break
            }
        } else {
            mutateHomeLayout { _ = $0.removeItem(id: item.id, from: .shelf(shelfID)) }
        }
        let title = resolvedHomeVisual(for: item).title
        serviceMessage = L10n.pick("已移除胶囊项「\(title)」", "Removed \"\(title)\"")
    }
}

import Foundation
import LumakeyCore

extension MCPServer {
    func handleUpsertHomeItem(arguments: [String: Any]) -> [String: Any] {
        var cfg = loadHomeConfig()
        if let targetProfile = arguments["profileID"] as? String, !targetProfile.isEmpty {
            guard cfg.selectProfile(id: targetProfile) else {
                return textResult("Profile not found: \(targetProfile)", isError: true)
            }
        }
        let rawSection = arguments["section"] as? String ?? ""
        guard let dest = HomeItemDestination.parse(section: rawSection, shelfID: arguments["shelfID"] as? String) else {
            return textResult("Invalid section '\(rawSection)'. Expected bento, dock, shelf, utilityChips, or utilityRight.", isError: true)
        }

        if let moveOffset = arguments["moveOffset"] as? Int,
           arguments["kind"] == nil,
           let existingID = arguments["id"] as? String {
            let moved = cfg.moveItem(id: existingID, in: dest, offset: moveOffset)
            if moved { saveHomeConfig(cfg) }
            return textResult(prettyJSON(["id": existingID, "moved": moved, "activeProfileID": cfg.activeProfileID]))
        }

        do {
            let target = try parseLaunchTarget(from: arguments)
            let rawID = (arguments["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedID = (rawID?.isEmpty == false) ? rawID! : "mcp-\(target.kindName)-\(UUID().uuidString.prefix(6).lowercased())"
            let item = HomeLaunchItem(
                id: resolvedID,
                target: target,
                customTitle: arguments["customTitle"] as? String,
                customSubtitle: arguments["customSubtitle"] as? String,
                customIcon: arguments["customIcon"] as? String,
                accentColor: arguments["accentColor"] as? String,
                hotkeyHint: arguments["hotkeyHint"] as? String
            )
            try cfg.upsertItem(
                item,
                in: dest,
                at: arguments["index"] as? Int,
                shelfTitle: arguments["shelfTitle"] as? String
            )
            if let moveOffset = arguments["moveOffset"] as? Int, moveOffset != 0 {
                _ = cfg.moveItem(id: item.id, in: dest, offset: moveOffset)
            }
            saveHomeConfig(cfg)
            return textResult(prettyJSON([
                "upserted": true,
                "id": item.id,
                "activeProfileID": cfg.activeProfileID,
                "item": encodeInternalItem(item)
            ]))
        } catch {
            return textResult("Error: \(error.localizedDescription)", isError: true)
        }
    }

    func handleRemoveHomeItem(arguments: [String: Any]) -> [String: Any] {
        var cfg = loadHomeConfig()
        if let targetProfile = arguments["profileID"] as? String, !targetProfile.isEmpty {
            guard cfg.selectProfile(id: targetProfile) else {
                return textResult("Profile not found: \(targetProfile)", isError: true)
            }
        }
        if let rawReset = arguments["resetPreset"] as? String {
            guard let preset = HomeLayoutPreset(rawValue: rawReset) else {
                return textResult("Unknown preset '\(rawReset)'.", isError: true)
            }
            cfg.applyPreset(preset, preserveDockItems: false)
            saveHomeConfig(cfg)
            return textResult(prettyJSON(["resetPreset": preset.rawValue, "activeProfileID": cfg.activeProfileID]))
        }
        guard let itemID = arguments["id"] as? String, !itemID.isEmpty else {
            return textResult("Provide either 'id' to remove an item or 'resetPreset' to reset the profile.", isError: true)
        }
        let dest: HomeItemDestination?
        if let rawSec = arguments["section"] as? String, !rawSec.isEmpty {
            guard let parsed = HomeItemDestination.parse(section: rawSec, shelfID: arguments["shelfID"] as? String) else {
                return textResult("Invalid section '\(rawSec)'.", isError: true)
            }
            dest = parsed
        } else {
            dest = nil
        }
        let removedCount = cfg.removeItem(id: itemID, from: dest)
        if removedCount > 0 { saveHomeConfig(cfg) }
        return textResult(prettyJSON(["id": itemID, "removedCount": removedCount, "activeProfileID": cfg.activeProfileID]))
    }

    private func parseLaunchTarget(from arguments: [String: Any]) throws -> HomeLaunchTarget {
        guard let kind = arguments["kind"] as? String else {
            throw HomeLayoutError.invalidItem("Missing required string argument 'kind'.")
        }
        switch kind {
        case "builtin":
            guard let raw = arguments["builtinID"] as? String, let id = HomeBuiltinActionID(rawValue: raw) else {
                throw HomeLayoutError.invalidItem("Missing or unknown 'builtinID'.")
            }
            return .builtin(id)
        case "nativeApp":
            guard let path = arguments["path"] as? String, !path.isEmpty else {
                throw HomeLayoutError.invalidItem("Missing 'path' for nativeApp.")
            }
            let std = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path
            return .nativeApp(path: std, bundleID: arguments["bundleID"] as? String)
        case "plugin":
            guard let pid = arguments["pluginID"] as? String, !pid.isEmpty else {
                throw HomeLayoutError.invalidItem("Missing 'pluginID' for plugin.")
            }
            let beh = (arguments["behavior"] as? String).flatMap(HomePluginLaunchBehavior.init(rawValue:)) ?? .auto
            return .plugin(pluginID: pid, behavior: beh)
        case "pluginCommand":
            guard let pid = arguments["pluginID"] as? String, !pid.isEmpty,
                  let cid = arguments["commandID"] as? String, !cid.isEmpty else {
                throw HomeLayoutError.invalidItem("Both 'pluginID' and 'commandID' are required for pluginCommand.")
            }
            return .pluginCommand(pluginID: pid, commandID: cid, arguments: arguments["arguments"] as? [String])
        case "script":
            guard let sid = arguments["scriptID"] as? String, !sid.isEmpty else {
                throw HomeLayoutError.invalidItem("Missing 'scriptID' for script.")
            }
            return .script(scriptID: sid)
        case "bookmark":
            guard let url = arguments["url"] as? String, !url.isEmpty else {
                throw HomeLayoutError.invalidItem("Missing 'url' for bookmark.")
            }
            return .bookmark(
                url: url,
                browserAppPath: arguments["browserAppPath"] as? String,
                sourcePluginID: arguments["sourcePluginID"] as? String
            )
        case "localPath":
            guard let path = arguments["path"] as? String, !path.isEmpty else {
                throw HomeLayoutError.invalidItem("Missing 'path' for localPath.")
            }
            let std = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path
            return .localPath(path: std)
        case "queryChip":
            guard let q = arguments["query"] as? String, !q.isEmpty else {
                throw HomeLayoutError.invalidItem("Missing 'query' for queryChip.")
            }
            return .queryChip(query: q, filter: arguments["filter"] as? String)
        default:
            throw HomeLayoutError.invalidItem("Unknown target kind '\(kind)'.")
        }
    }

    private func encodeInternalItem(_ item: HomeLaunchItem) -> Any {
        guard let data = try? JSONEncoder().encode(item),
              let obj = try? JSONSerialization.jsonObject(with: data) else { return [:] }
        return obj
    }
}

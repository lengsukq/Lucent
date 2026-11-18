import Foundation
import LumakeyCore

extension MCPServer {
    func homeLayoutToolSchemas() -> [[String: Any]] {
        let builtinIDs = HomeBuiltinActionID.allCases.map(\.rawValue)
        let presetIDs = HomeLayoutPreset.allCases.map(\.rawValue)
        let sectionIDs = HomeSectionKind.allCases.map(\.rawValue)
        let behaviors = HomePluginLaunchBehavior.allCases.map(\.rawValue)
        let dockModes = HomeDockFillMode.allCases.map(\.rawValue)
        let destSections = ["bento", "dock", "shelf", "utilityChips", "utilityRight"]
        let itemKinds = ["builtin", "nativeApp", "plugin", "pluginCommand", "script", "bookmark", "localPath", "queryChip"]

        var getProps: [String: Any] = [:]
        getProps["includeCandidates"] = [
            "type": "boolean",
            "description": "Include available builtin actions, installed plugins/commands, scripts, indexed bookmarks, and top native apps (default true)."
        ]
        getProps["includeNativeApps"] = [
            "type": "boolean",
            "description": "Scan /Applications for native app candidates when includeCandidates is true (default false for fast queries)."
        ]

        var updateProps: [String: Any] = [:]
        updateProps["selectProfileID"] = ["type": "string", "description": "Switch active home profile by ID."]
        updateProps["createProfile"] = [
            "type": "object",
            "description": "Create a new scene profile (`{id?, name, symbol?, preset?, activate?}`).",
            "properties": [
                "id": ["type": "string"],
                "name": ["type": "string"],
                "symbol": ["type": "string"],
                "preset": ["type": "string", "enum": presetIDs],
                "activate": ["type": "boolean"]
            ]
        ]
        updateProps["renameProfile"] = [
            "type": "object",
            "description": "Rename or update symbol of a profile (`{id?, name?, symbol?}`).",
            "properties": ["id": ["type": "string"], "name": ["type": "string"], "symbol": ["type": "string"]]
        ]
        updateProps["deleteProfileID"] = ["type": "string", "description": "Delete a non-last home profile by ID."]
        updateProps["applyPreset"] = ["type": "string", "enum": presetIDs, "description": "Apply a built-in layout preset to the active profile."]
        updateProps["preserveDockItems"] = ["type": "boolean", "description": "Keep pinned dock items when applying a preset (default true)."]
        updateProps["sectionOrder"] = ["type": "array", "items": ["type": "string", "enum": sectionIDs]]
        updateProps["hiddenSections"] = ["type": "array", "items": ["type": "string", "enum": sectionIDs]]
        updateProps["bentoColumns"] = ["type": "integer", "enum": [2, 3, 4]]
        updateProps["dockRows"] = ["type": "integer", "enum": [1, 2]]
        updateProps["dockFillMode"] = ["type": "string", "enum": dockModes]
        updateProps["compactFooterBar"] = ["type": "boolean"]
        updateProps["upsertShelf"] = [
            "type": "object",
            "description": "Create or update a named bookmark/plugin pill shelf (`{id, title, symbol?, accentColor?, isHidden?, includeLegacyQuickButtons?}`).",
            "properties": [
                "id": ["type": "string"],
                "title": ["type": "string"],
                "symbol": ["type": "string"],
                "accentColor": ["type": "string"],
                "isHidden": ["type": "boolean"],
                "includeLegacyQuickButtons": ["type": "boolean"]
            ]
        ]
        updateProps["removeShelfID"] = ["type": "string", "description": "Remove a pill shelf by ID."]
        updateProps["undoLastChange"] = ["type": "boolean", "description": "If true, revert the last profile modification."]

        var upsertProps: [String: Any] = [:]
        upsertProps["profileID"] = ["type": "string", "description": "Optional target profile ID (defaults to active profile)."]
        upsertProps["section"] = ["type": "string", "enum": destSections, "description": "Target home container (`bento`, `dock`, `shelf`, `utilityChips`, `utilityRight`)."]
        upsertProps["shelfID"] = ["type": "string", "description": "Shelf ID when `section == 'shelf'` (creates shelf if missing)."]
        upsertProps["shelfTitle"] = ["type": "string", "description": "Optional display title when creating/updating a shelf."]
        upsertProps["id"] = ["type": "string", "description": "Stable item ID (auto-generated if omitted; updates existing item if matched)."]
        upsertProps["kind"] = ["type": "string", "enum": itemKinds]
        upsertProps["builtinID"] = ["type": "string", "enum": builtinIDs]
        upsertProps["path"] = ["type": "string", "description": "Absolute `.app` path for `nativeApp` or file/folder path for `localPath`."]
        upsertProps["bundleID"] = ["type": "string"]
        upsertProps["pluginID"] = ["type": "string"]
        upsertProps["behavior"] = ["type": "string", "enum": behaviors]
        upsertProps["commandID"] = ["type": "string"]
        upsertProps["arguments"] = ["type": "array", "items": ["type": "string"]]
        upsertProps["scriptID"] = ["type": "string", "description": "Quick Script ID when `kind == 'script'`."]
        upsertProps["url"] = ["type": "string", "description": "Bookmark/deep-link URL (safe scheme whitelist enforced)."]
        upsertProps["browserAppPath"] = ["type": "string", "description": "Optional specific browser `.app` path for `bookmark`."]
        upsertProps["sourcePluginID"] = ["type": "string"]
        upsertProps["query"] = ["type": "string", "description": "Search text for `queryChip`."]
        upsertProps["filter"] = ["type": "string", "enum": ["all", "files", "clipboard", "plugins"]]
        upsertProps["customTitle"] = ["type": "string"]
        upsertProps["customSubtitle"] = ["type": "string"]
        upsertProps["customIcon"] = ["type": "string", "description": "Optional SF Symbol name override."]
        upsertProps["accentColor"] = ["type": "string", "description": "Palette token (`cyan`, `indigo`, `mint`, `orange`, etc.) or `#RRGGBB`."]
        upsertProps["hotkeyHint"] = ["type": "string"]
        upsertProps["index"] = ["type": "integer", "description": "Optional 0-based insertion index."]
        upsertProps["moveOffset"] = ["type": "integer", "description": "Optional relative reorder offset (`-1`, `1`, etc.) for an existing item `id`."]

        var removeProps: [String: Any] = [:]
        removeProps["profileID"] = ["type": "string", "description": "Optional target profile ID (defaults to active profile)."]
        removeProps["id"] = ["type": "string", "description": "Item ID to remove."]
        removeProps["section"] = ["type": "string", "enum": destSections, "description": "Optional section scope; if omitted, removes matching `id` from all sections in the profile."]
        removeProps["shelfID"] = ["type": "string"]
        removeProps["resetPreset"] = ["type": "string", "enum": presetIDs, "description": "Optional preset name to reset the target profile cleanly."]

        return [
            schema(
                "lumakey_get_home_layout",
                "Read Lumakey's customizable Launcher Home Page configuration (`home-layout.json`), including all scene profiles, active profile sections/items, and available builtin actions, installed plugins, scripts, and indexed bookmarks.",
                getProps, []
            ),
            schema(
                "lumakey_update_home_layout",
                "Create/switch/delete Launcher Home profiles, apply presets (`balanced`, `minimal`, `developer`, `creatorBookmarks`), reorder or hide sections (`bentoGrid`, `omniDock`, `pillShelves`, `utilityStrip`), configure grid density, manage bookmark shelves, or undo the last change.",
                updateProps, []
            ),
            schema(
                "lumakey_upsert_home_item",
                "Add, update, or reorder a Launcher Home item (`builtin`, `nativeApp`, `plugin`, `pluginCommand`, `script`, `bookmark`, `localPath`, or `queryChip`) inside Bento Tiles, Omni Dock, a named Bookmark/Pill Shelf, or Utility Strip.",
                upsertProps, ["section"]
            ),
            schema(
                "lumakey_remove_home_item",
                "Remove a Launcher Home item by `id` or reset a profile to a clean built-in preset (`resetPreset`).",
                removeProps, []
            )
        ]
    }
}

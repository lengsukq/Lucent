import Foundation
import LumakeyCore

extension MCPServer {
    func callTool(name: String, arguments: [String: Any]) -> [String: Any] {
        switch name {
        case "lumakey_list_plugins": return handleListPlugins(arguments: arguments)
        case "lumakey_app_permissions": return handleAppPermissions(arguments: arguments)
        case "lumakey_scaffold_plugin": return handleScaffoldPlugin(arguments: arguments)
        case "lumakey_validate_plugin": return handleValidatePlugin(arguments: arguments)
        case "lumakey_run_plugin_test": return handleRunPluginTest(arguments: arguments)
        case "lumakey_install_starter_plugin": return handleInstallStarter(arguments: arguments)
        case "lumakey_set_plugin_enabled": return handleSetEnabled(arguments: arguments)
        case "lumakey_update_plugin_overrides": return handleUpdatePluginOverrides(arguments: arguments)
        case "lumakey_remove_plugin": return handleRemovePlugin(arguments: arguments)
        case "lumakey_package_plugin_for_store": return handlePackagePluginForStore(arguments: arguments)
        case "lumakey_list_plugin_stores": return handleListPluginStores()
        case "lumakey_resolve_or_install_url": return handleResolveOrInstallURL(arguments: arguments)
        default: return textResult("Unknown tool: \(name)", isError: true)
        }
    }

    func toolSchemas() -> [[String: Any]] {
        let starterIDs = PluginStarterGallery.templates.map(\.id)
        let capIDs = PluginCapability.allCases.map(\.rawValue)
        let scopeIDs = PluginResourceScope.allCases.map(\.rawValue)
        let acceptIDs = PluginContextKind.allCases.map(\.rawValue)
        return [
            schema("lumakey_list_plugins",
                   "List installed external plugins and (by default) builtin native plugins (`BUILTIN`) with their localized names, custom icons/accent colors, declared permissions, sub-commands, command hotkeys, quick buttons (OFF by default), runtime status summary, and enabled state.",
                   ["includeBuiltin": ["type": "boolean", "description": "Include BUILTIN native plugins (default true)."]], []),
            schema("lumakey_app_permissions",
                   "Return Lumakey's app-wide permission matrix: every system TCC / kernel / Host Bridge / Resource Scope permission and the exact list of builtin & external plugins that declared or use each permission, plus pure sandbox (`[]`) plugins.",
                   ["onlyUsed": ["type": "boolean", "description": "If true, omit permissions with zero declaring plugins (default false)."]], []),
            schema("lumakey_scaffold_plugin",
                   "Create a new on-demand plugin under the Lumakey Plugins directory. Mandatory registration rule: BOTH `capabilities` AND `resourceScopes` MUST be explicitly provided (pass `[]` for pure sandboxed plugins). Never generate daemons or infinite loops.",
                   [
                       "id": ["type": "string", "description": "Lowercase alphanumeric + hyphen plugin ID (must NOT start with 'builtin-')."],
                       "name": ["type": "string", "description": "Display name shown in Launcher and Plugin Settings."],
                       "keywords": ["type": "array", "items": ["type": "string"], "description": "Launcher trigger keywords."],
                       "capabilities": ["type": "array", "items": ["type": "string", "enum": capIDs], "description": "REQUIRED Host Bridge declaration on registration. Pass [] if no host permission needed."],
                       "resourceScopes": ["type": "array", "items": ["type": "string", "enum": scopeIDs], "description": "REQUIRED external resource declaration on registration (`network`, `filesystem`, `subprocess`, or [])."],
                       "accepts": ["type": "array", "items": ["type": "string", "enum": acceptIDs], "description": "Optional context targets (`url`, `text`, `image`, `file`, `directory`) for cross-module action routing."],
                       "description": ["type": "string", "description": "Short functional description."],
                       "mode": ["type": "string", "enum": ["script", "view"], "description": "Prefer 'view' for rich structured cards."],
                       "author": ["type": "string"],
                       "icon": ["type": "string", "description": "SF Symbol name or relative bundle image path."],
                       "hotkey": ["type": "string", "description": "Optional shortcut hint (e.g. '⌥⇧K')."]
                   ], ["id", "name", "keywords", "capabilities", "resourceScopes"]),
            schema("lumakey_validate_plugin",
                   "Validate a plugin's plugin.json (including mandatory `capabilities` and `resourceScopes`, bundle icon safety, slider bounds, `commands`, and `accepts`) and return its declaredPermissions and issues.",
                   ["id": ["type": "string"]], ["id"]),
            schema("lumakey_run_plugin_test",
                   "Execute a plugin (external with ephemeral Host Bridge + LUMAKEY_DATA_DIR + locale/theme, or BUILTIN view payload) with optional CLI arguments, context payload, configOverrides, stdin query/clipboardText, and inspect stdout, structured viewValidation diagnostics, and exitCode.",
                   [
                       "id": ["type": "string"],
                       "query": ["type": "string"],
                       "clipboardText": ["type": "string", "description": "Optional mock clipboard text (only injected if clipboard capability is granted)."],
                       "arguments": ["type": "array", "items": ["type": "string"], "description": "Optional CLI arguments simulating sub-command or card button actions."],
                       "context": ["type": "object", "description": "Optional context payload (`kind`, `source`, `text`, `url`, `filePaths`)."],
                       "configOverrides": ["type": "object", "description": "Optional key-value config overrides for testing."],
                       "autoGrantDeclaredCapabilities": ["type": "boolean", "description": "If true, grant all declared Host Bridge capabilities in state before test execution."]
                   ], ["id", "query"]),
            schema("lumakey_install_starter_plugin",
                   "Install a curated starter plugin template (templates include Global Search sub-commands, Host Bridge, and context action examples).",
                   ["id": ["type": "string", "enum": starterIDs], "overwrite": ["type": "boolean"]], ["id"]),
            schema("lumakey_set_plugin_enabled",
                   "Enable or disable an external or BUILTIN plugin. Disabling BUILTIN plugins stops their listeners/timers immediately.",
                   ["id": ["type": "string"], "enabled": ["type": "boolean"]], ["id", "enabled"]),
            schema("lumakey_update_plugin_overrides",
                   "Configure user-level overrides for a plugin (`customKeywords`, `customHotKey`, `commandHotKeys`, `pinnedInOverlay`, `quickButtonCommandIDs`, `disabledCommandIDs`, `revokedResourceScopes`, `includeInGlobalSearch`, `showInSettingsSidebar`, `priorityBoost`) without modifying plugin.json.",
                   [
                       "id": ["type": "string"],
                       "customKeywords": ["type": "array", "items": ["type": "string"]],
                       "customHotKey": ["type": "string"],
                       "commandHotKeys": ["type": "object", "description": "Map of sub-command ID to global shortcut string (pass empty string to clear)."],
                       "pinnedInOverlay": ["type": "boolean"],
                       "quickButtonCommandIDs": ["type": "array", "items": ["type": "string"], "description": "Sub-command IDs enabled as Quick Buttons (default [])."],
                       "disabledCommandIDs": ["type": "array", "items": ["type": "string"], "description": "Sub-command IDs hidden from Global Search (default [])."],
                       "revokedResourceScopes": ["type": "array", "items": ["type": "string", "enum": scopeIDs], "description": "Declared resource scopes revoked via Seatbelt sandbox."],
                       "includeInGlobalSearch": ["type": "boolean"],
                       "showInSettingsSidebar": ["type": "boolean"],
                       "priorityBoost": ["type": "integer"]
                   ], ["id"]),
            schema("lumakey_remove_plugin",
                   "Remove an external plugin directory. Builtin plugins (`builtin-*`) cannot be deleted.",
                   ["id": ["type": "string"]], ["id"])
        ] + storeToolSchemas()
    }

    private func handleListPlugins(arguments: [String: Any]) -> [String: Any] {
        let includeBuiltin = arguments["includeBuiltin"] as? Bool ?? true
        let plugins = PluginSystem.listPlugins(in: pluginsDirectory, includeDisabled: true, includeBuiltin: includeBuiltin, includeSecrets: false)
            .map { desc -> [String: Any] in
                let accentVal: Any = desc.manifest.accentColor ?? NSNull()
                let hkVal: Any = desc.effectiveHotKey ?? NSNull()
                var item: [String: Any] = [
                    "id": desc.id,
                    "name": desc.displayName,
                    "kind": desc.kind.rawValue,
                    "mode": desc.manifest.mode.rawValue,
                    "categoryBadge": desc.displayCategoryBadge,
                    "statusSummary": desc.effectiveStatusSummary,
                    "accentColor": accentVal,
                    "hasCustomBundleIcon": desc.customIconURL != nil,
                    "keywords": desc.manifest.keywords,
                    "effectiveKeywords": desc.effectiveKeywords,
                    "effectiveHotKey": hkVal,
                    "commandHotKeys": desc.overrides.commandHotKeys,
                    "pinnedInOverlay": desc.pinnedInOverlay,
                    "quickButtonCommandIDs": desc.overrides.quickButtonCommandIDs,
                    "includeInGlobalSearch": desc.includeInGlobalSearch,
                    "settingsDeepLink": desc.isBuiltin ? "lumakey://settings/\(desc.builtinMetadata?.settingsTarget ?? "plugins")" : "lumakey://settings/plugin/\(desc.id)",
                    "enabled": desc.isEnabled,
                    "valid": desc.isValid,
                    "issues": desc.validationIssues,
                    "declaredCommands": desc.declaredCommands.map { cmd -> [String: Any] in
                        let cmdHKVal: Any = desc.effectiveCommandHotKey(for: cmd.id) ?? NSNull()
                        return [
                            "id": cmd.id,
                            "title": desc.manifest.localizedCommandTitle(cmd),
                            "keywords": cmd.keywords,
                            "arguments": cmd.arguments,
                            "effectiveHotKey": cmdHKVal
                        ]
                    },
                    "declaredCapabilities": desc.declaredCapabilities.map(\.rawValue),
                    "declaredResourceScopes": desc.declaredResourceScopes.map(\.rawValue),
                    "grantedResourceScopes": desc.grantedResourceScopes.map(\.rawValue).sorted(),
                    "revokedResourceScopes": desc.revokedResourceScopes.map(\.rawValue).sorted(),
                    "declaredContextKinds": desc.declaredContextKinds.map(\.rawValue),
                    "grantedCapabilities": desc.grantedCapabilities.map(\.rawValue).sorted(),
                    "declaredPermissions": desc.declaredPermissions.map(\.rawValue)
                ]
                if let meta = desc.builtinMetadata {
                    item["builtinMetadata"] = [
                        "badge": meta.categoryBadge,
                        "settingsTarget": meta.settingsTarget,
                        "statusSummary": meta.statusSummary,
                        "requiredPermissions": meta.requiredPermissions.map(\.rawValue)
                    ]
                }
                return item
            }
        return textResult(prettyJSON(plugins))
    }

    private func handleAppPermissions(arguments: [String: Any]) -> [String: Any] {
        let onlyUsed = arguments["onlyUsed"] as? Bool ?? false
        let plugins = PluginSystem.listPlugins(in: pluginsDirectory, includeDisabled: true, includeBuiltin: true, includeSecrets: false)
        let entries = PluginPermissionAudit.buildAudit(plugins: plugins)
            .filter { !onlyUsed || $0.declaredPluginCount > 0 }
            .map { entry -> [String: Any] in
                [
                    "permission": entry.permission.rawValue, "title": entry.permission.title,
                    "category": entry.permission.category.rawValue, "summary": entry.permission.summary,
                    "declaredPluginCount": entry.declaredPluginCount, "activePluginCount": entry.activePluginCount,
                    "usedByPlugins": entry.plugins.map { u -> [String: Any] in
                        [
                            "id": u.pluginID, "name": u.pluginName, "kind": u.kind.rawValue,
                            "enabled": u.isPluginEnabled, "authorized": u.isAuthorized, "role": u.roleNote
                        ]
                    }
                ]
            }
        let sandbox = PluginPermissionAudit.sandboxOnlyPlugins(in: plugins).map {
            ["id": $0.id, "name": $0.displayName, "kind": $0.kind.rawValue]
        }
        return textResult(prettyJSON(["permissions": entries, "sandboxOnlyPlugins": sandbox]))
    }

    private func handleScaffoldPlugin(arguments: [String: Any]) -> [String: Any] {
        guard let rawCaps = arguments["capabilities"] as? [String] else {
            return textResult("Missing required array argument 'capabilities' (declare required capabilities or [] for pure sandbox).", isError: true)
        }
        guard let rawScopes = arguments["resourceScopes"] as? [String] else {
            return textResult("Missing required array argument 'resourceScopes' (declare network/filesystem/subprocess or [] if none).", isError: true)
        }
        var caps: [PluginCapability] = []
        for raw in rawCaps {
            guard let cap = PluginCapability(rawValue: raw) else {
                return textResult("Unknown capability '\(raw)'. Allowed: \(PluginCapability.allCases.map(\.rawValue).joined(separator: ", "))", isError: true)
            }
            if !caps.contains(cap) { caps.append(cap) }
        }
        var scopes: [PluginResourceScope] = []
        for raw in rawScopes {
            guard let scope = PluginResourceScope(rawValue: raw) else {
                return textResult("Unknown resourceScope '\(raw)'. Allowed: \(PluginResourceScope.allCases.map(\.rawValue).joined(separator: ", "))", isError: true)
            }
            if !scopes.contains(scope) { scopes.append(scope) }
        }
        var accepts: [PluginContextKind]? = nil
        if let rawAccepts = arguments["accepts"] as? [String] {
            var parsed: [PluginContextKind] = []
            for raw in rawAccepts {
                guard let kind = PluginContextKind(rawValue: raw) else {
                    return textResult("Unknown accepts kind '\(raw)'. Allowed: \(PluginContextKind.allCases.map(\.rawValue).joined(separator: ", "))", isError: true)
                }
                if !parsed.contains(kind) { parsed.append(kind) }
            }
            accepts = parsed
        }
        let id = arguments["id"] as? String ?? ""
        let displayName = arguments["name"] as? String ?? id
        let keywords = arguments["keywords"] as? [String] ?? [id]
        let description = arguments["description"] as? String ?? "AI 生成插件"
        let mode = PluginMode(rawValue: arguments["mode"] as? String ?? "view") ?? .view
        do {
            let created = try PluginSystem.scaffoldPlugin(
                id: id, name: displayName, keywords: keywords, description: description,
                mode: mode, author: arguments["author"] as? String,
                icon: arguments["icon"] as? String, hotkey: arguments["hotkey"] as? String,
                capabilities: caps, resourceScopes: scopes, accepts: accepts, in: pluginsDirectory
            )
            return textResult(prettyJSON([
                "id": created.id, "path": created.directoryURL.path,
                "mode": created.manifest.mode.rawValue,
                "capabilities": created.declaredCapabilities.map(\.rawValue),
                "resourceScopes": created.declaredResourceScopes.map(\.rawValue),
                "accepts": created.declaredContextKinds.map(\.rawValue),
                "valid": created.isValid
            ]))
        } catch {
            return textResult("Error: \(error.localizedDescription)", isError: true)
        }
    }

    private func handleInstallStarter(arguments: [String: Any]) -> [String: Any] {
        let id = arguments["id"] as? String ?? ""
        let overwrite = arguments["overwrite"] as? Bool ?? true
        do {
            let installed = try PluginStarterGallery.install(templateID: id, in: pluginsDirectory, overwrite: overwrite)
            return textResult(prettyJSON([
                "id": installed.id, "name": installed.displayName, "mode": installed.manifest.mode.rawValue,
                "path": installed.directoryURL.path, "valid": installed.isValid,
                "commandsCount": installed.declaredCommands.count,
                "capabilities": installed.declaredCapabilities.map(\.rawValue)
            ]))
        } catch {
            return textResult("Install error: \(error.localizedDescription)", isError: true)
        }
    }

    private func handleSetEnabled(arguments: [String: Any]) -> [String: Any] {
        let id = arguments["id"] as? String ?? ""
        guard let enabled = arguments["enabled"] as? Bool else {
            return textResult("Missing boolean argument 'enabled'", isError: true)
        }
        if PluginBuiltinRegistry.isBuiltin(id: id) {
            guard PluginBuiltinRegistry.setBuiltinEnabled(id: id, isEnabled: enabled) else {
                return textResult("Unknown builtin plugin: \(id)", isError: true)
            }
            return textResult(prettyJSON(["id": id, "kind": "builtin", "enabled": enabled]))
        }
        let dir = pluginsDirectory.appendingPathComponent(id, isDirectory: true)
        guard PluginSystem.isSafePluginID(id), FileManager.default.fileExists(atPath: dir.path) else {
            return textResult("Plugin not found or invalid id: \(id)", isError: true)
        }
        do {
            try PluginSystem.setPluginEnabled(id: id, isEnabled: enabled, in: pluginsDirectory)
            return textResult(prettyJSON(["id": id, "kind": "external", "enabled": enabled]))
        } catch {
            return textResult("Error: \(error.localizedDescription)", isError: true)
        }
    }

    private func handleRemovePlugin(arguments: [String: Any]) -> [String: Any] {
        let id = arguments["id"] as? String ?? ""
        guard !PluginBuiltinRegistry.isBuiltin(id: id) else {
            return textResult("Cannot delete BUILTIN plugin '\(id)'. Use lumakey_set_plugin_enabled instead.", isError: true)
        }
        do {
            try PluginSystem.removePlugin(id: id, in: pluginsDirectory)
            return textResult(prettyJSON(["id": id, "removed": true]))
        } catch {
            return textResult("Remove error: \(error.localizedDescription)", isError: true)
        }
    }
}

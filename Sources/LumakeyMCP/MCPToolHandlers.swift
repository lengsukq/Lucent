import Foundation
import LumakeyCore

extension MCPServer {
    func callTool(name: String, arguments: [String: Any]) -> [String: Any] {
        switch name {
        case "lumakey_list_plugins":
            return handleListPlugins(arguments: arguments)
        case "lumakey_app_permissions":
            return handleAppPermissions(arguments: arguments)
        case "lumakey_scaffold_plugin":
            return handleScaffoldPlugin(arguments: arguments)
        case "lumakey_validate_plugin":
            return handleValidatePlugin(arguments: arguments)
        case "lumakey_run_plugin_test":
            return handleRunPluginTest(arguments: arguments)
        case "lumakey_install_starter_plugin":
            return handleInstallStarter(arguments: arguments)
        case "lumakey_set_plugin_enabled":
            return handleSetEnabled(arguments: arguments)
        case "lumakey_remove_plugin":
            return handleRemovePlugin(arguments: arguments)
        default:
            return textResult("Unknown tool: \(name)", isError: true)
        }
    }

    func toolSchemas() -> [[String: Any]] {
        let starterIDs = PluginStarterGallery.templates.map(\.id)
        let capIDs = PluginCapability.allCases.map(\.rawValue)
        return [
            schema("lumakey_list_plugins",
                   "List installed external plugins and (by default) builtin native plugins (`BUILTIN`) with their declared permissions (`capabilities`/`declaredPermissions`), granted status, keywords, and enabled state. Always call this before creating a new plugin to avoid duplicating builtin features.",
                   ["includeBuiltin": ["type": "boolean", "description": "Include BUILTIN native plugins (default true)."]], []),
            schema("lumakey_app_permissions",
                   "Return Lumakey's app-wide permission matrix: every system TCC / kernel / Host Bridge permission and the exact list of builtin & external plugins that declared or use each permission, plus pure sandbox (`[]`) plugins.",
                   ["onlyUsed": ["type": "boolean", "description": "If true, omit permissions with zero declaring plugins (default false)."]], []),
            schema("lumakey_scaffold_plugin",
                   "Create a new on-demand plugin under the Lumakey Plugins directory. Mandatory registration rule: `capabilities` MUST be explicitly provided (pass `[]` for pure sandboxed plugins needing no host privileges, or choose from available Host Bridge capabilities). Never generate daemons or infinite loops.",
                   [
                       "id": ["type": "string", "description": "Lowercase alphanumeric + hyphen plugin ID (must NOT start with 'builtin-')."],
                       "name": ["type": "string", "description": "Display name shown in Launcher and Plugin Center."],
                       "keywords": ["type": "array", "items": ["type": "string"], "description": "Launcher trigger keywords."],
                       "capabilities": ["type": "array", "items": ["type": "string", "enum": capIDs], "description": "REQUIRED permission declaration on registration. Pass [] if no host permission needed, or declare Host Bridge capabilities."],
                       "description": ["type": "string", "description": "Short functional description."],
                       "mode": ["type": "string", "enum": ["script", "view"], "description": "Prefer 'view' for rich structured cards."],
                       "author": ["type": "string"],
                       "icon": ["type": "string", "description": "SF Symbol name (e.g. 'sparkles')."],
                       "hotkey": ["type": "string", "description": "Optional shortcut hint (e.g. '⌥⇧K')."]
                   ], ["id", "name", "keywords", "capabilities"]),
            schema("lumakey_validate_plugin",
                   "Validate a plugin's plugin.json (including mandatory `capabilities` declaration and entry permissions) and return its declaredPermissions and issues.",
                   ["id": ["type": "string"]], ["id"]),
            schema("lumakey_run_plugin_test",
                   "Execute a plugin (external with ephemeral Host Bridge context, or BUILTIN view payload) with test stdin query/clipboardText and inspect stdout, structured view validity, and exitCode.",
                   [
                       "id": ["type": "string"],
                       "query": ["type": "string"],
                       "clipboardText": ["type": "string", "description": "Optional mock clipboard text injected into stdin JSON."]
                   ], ["id", "query"]),
            schema("lumakey_install_starter_plugin",
                   "Install a curated starter plugin template (v3 templates include Host Bridge examples).",
                   ["id": ["type": "string", "enum": starterIDs], "overwrite": ["type": "boolean"]], ["id"]),
            schema("lumakey_set_plugin_enabled",
                   "Enable or disable an external or BUILTIN plugin. Disabling BUILTIN plugins stops their listeners/timers immediately.",
                   ["id": ["type": "string"], "enabled": ["type": "boolean"]], ["id", "enabled"]),
            schema("lumakey_remove_plugin",
                   "Remove an external plugin directory. Builtin plugins (`builtin-*`) cannot be deleted.",
                   ["id": ["type": "string"]], ["id"])
        ]
    }

    private func handleListPlugins(arguments: [String: Any]) -> [String: Any] {
        let includeBuiltin = arguments["includeBuiltin"] as? Bool ?? true
        let plugins = PluginSystem.listPlugins(in: pluginsDirectory, includeDisabled: true, includeBuiltin: includeBuiltin)
            .map { desc -> [String: Any] in
                var item: [String: Any] = [
                    "id": desc.id,
                    "name": desc.manifest.name,
                    "kind": desc.kind.rawValue,
                    "mode": desc.manifest.mode.rawValue,
                    "keywords": desc.manifest.keywords,
                    "enabled": desc.isEnabled,
                    "valid": desc.isValid,
                    "issues": desc.validationIssues,
                    "declaredCapabilities": desc.declaredCapabilities.map(\.rawValue),
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
        let plugins = PluginSystem.listPlugins(in: pluginsDirectory, includeDisabled: true, includeBuiltin: true)
        let entries = PluginPermissionAudit.buildAudit(plugins: plugins)
            .filter { !onlyUsed || $0.declaredPluginCount > 0 }
            .map { entry -> [String: Any] in
                [
                    "permission": entry.permission.rawValue,
                    "title": entry.permission.title,
                    "category": entry.permission.category.rawValue,
                    "summary": entry.permission.summary,
                    "declaredPluginCount": entry.declaredPluginCount,
                    "activePluginCount": entry.activePluginCount,
                    "usedByPlugins": entry.plugins.map { u in
                        [
                            "id": u.pluginID,
                            "name": u.pluginName,
                            "kind": u.kind.rawValue,
                            "enabled": u.isPluginEnabled,
                            "authorized": u.isAuthorized,
                            "role": u.roleNote
                        ]
                    }
                ]
            }
        let sandbox = PluginPermissionAudit.sandboxOnlyPlugins(in: plugins).map {
            ["id": $0.id, "name": $0.manifest.name, "kind": $0.kind.rawValue]
        }
        return textResult(prettyJSON(["permissions": entries, "sandboxOnlyPlugins": sandbox]))
    }

    private func handleScaffoldPlugin(arguments: [String: Any]) -> [String: Any] {
        guard let rawCaps = arguments["capabilities"] as? [String] else {
            return textResult("Missing required array argument 'capabilities' (declare required capabilities or [] for pure sandbox).", isError: true)
        }
        var caps: [PluginCapability] = []
        for raw in rawCaps {
            guard let cap = PluginCapability(rawValue: raw) else {
                let allowed = PluginCapability.allCases.map(\.rawValue).joined(separator: ", ")
                return textResult("Unknown capability '\(raw)'. Allowed: \(allowed)", isError: true)
            }
            if !caps.contains(cap) { caps.append(cap) }
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
                capabilities: caps, in: pluginsDirectory
            )
            return textResult(prettyJSON([
                "id": created.id,
                "path": created.directoryURL.path,
                "mode": created.manifest.mode.rawValue,
                "capabilities": created.declaredCapabilities.map(\.rawValue),
                "valid": created.isValid
            ]))
        } catch {
            return textResult("Error: \(error.localizedDescription)", isError: true)
        }
    }

    private func handleValidatePlugin(arguments: [String: Any]) -> [String: Any] {
        let id = arguments["id"] as? String ?? ""
        if PluginBuiltinRegistry.isBuiltin(id: id) {
            guard let builtin = PluginBuiltinRegistry.descriptors().first(where: { $0.id == id }) else {
                return textResult("Unknown builtin plugin: \(id)", isError: true)
            }
            return textResult(prettyJSON([
                "id": builtin.id, "kind": "builtin", "valid": true,
                "issues": [], "declaredPermissions": builtin.declaredPermissions.map(\.rawValue)
            ]))
        }
        guard PluginSystem.isSafePluginID(id) else {
            return textResult("Invalid plugin id: \(id)", isError: true)
        }
        let dir = pluginsDirectory.appendingPathComponent(id, isDirectory: true)
        let desc = PluginSystem.loadPlugin(at: dir, in: pluginsDirectory)
        return textResult(prettyJSON([
            "id": desc.id, "kind": "external", "valid": desc.isValid, "issues": desc.validationIssues,
            "hasCapabilitiesDeclaration": desc.manifest.capabilities != nil,
            "declaredCapabilities": desc.declaredCapabilities.map(\.rawValue),
            "grantedCapabilities": desc.grantedCapabilities.map(\.rawValue).sorted(),
            "declaredPermissions": desc.declaredPermissions.map(\.rawValue)
        ]))
    }

    private func handleRunPluginTest(arguments: [String: Any]) -> [String: Any] {
        let id = arguments["id"] as? String ?? ""
        let query = arguments["query"] as? String ?? ""
        let clip = arguments["clipboardText"] as? String ?? ""
        if PluginBuiltinRegistry.isBuiltin(id: id) {
            guard let resolved = PluginBuiltinRegistry.runBuiltin(id: id, query: query) else {
                return textResult("Unknown builtin plugin: \(id)", isError: true)
            }
            return textResult(prettyJSON([
                "kind": "builtin", "exitCode": resolved.execution.exitCode,
                "durationMs": resolved.execution.durationMs,
                "isStructuredView": resolved.isStructuredView,
                "stdout": resolved.execution.stdout
            ]))
        }
        guard PluginSystem.isSafePluginID(id) else { return textResult("Invalid plugin id: \(id)", isError: true) }
        let dir = pluginsDirectory.appendingPathComponent(id, isDirectory: true)
        let desc = PluginSystem.loadPlugin(at: dir, in: pluginsDirectory)
        do {
            let resolved = try PluginSystem.runPluginSync(desc, query: query, clipboardText: clip, in: pluginsDirectory)
            return textResult(prettyJSON([
                "kind": "external", "exitCode": resolved.execution.exitCode,
                "durationMs": resolved.execution.durationMs, "isStructuredView": resolved.isStructuredView,
                "stdout": resolved.execution.stdout, "stderr": resolved.execution.stderr
            ]), isError: resolved.execution.exitCode != 0)
        } catch {
            return textResult("Execution error: \(error.localizedDescription)", isError: true)
        }
    }

    private func handleInstallStarter(arguments: [String: Any]) -> [String: Any] {
        let id = arguments["id"] as? String ?? ""
        let overwrite = arguments["overwrite"] as? Bool ?? true
        do {
            let installed = try PluginStarterGallery.install(templateID: id, in: pluginsDirectory, overwrite: overwrite)
            return textResult(prettyJSON([
                "id": installed.id, "name": installed.manifest.name, "mode": installed.manifest.mode.rawValue,
                "path": installed.directoryURL.path, "valid": installed.isValid,
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

import Foundation
import LucentCore

extension MCPServer {
    func handleAppPermissions(arguments: [String: Any]) -> [String: Any] {
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

    func handleValidatePlugin(arguments: [String: Any]) -> [String: Any] {
        let id = arguments["id"] as? String ?? ""
        if PluginBuiltinRegistry.isBuiltin(id: id) {
            guard let builtin = PluginBuiltinRegistry.descriptors().first(where: { $0.id == id }) else {
                return textResult("Unknown builtin plugin: \(id)", isError: true)
            }
            return textResult(prettyJSON([
                "id": builtin.id, "kind": "builtin", "valid": true,
                "issues": [], "declaredCommands": builtin.declaredCommands.map(\.id),
                "declaredPermissions": builtin.declaredPermissions.map(\.rawValue)
            ]))
        }
        guard PluginSystem.isSafePluginID(id) else {
            return textResult("Invalid plugin id: \(id)", isError: true)
        }
        let dir = pluginsDirectory.appendingPathComponent(id, isDirectory: true)
        let desc = PluginSystem.loadPlugin(at: dir, in: pluginsDirectory, includeSecrets: false)
        var report: [String: Any] = [
            "id": desc.id, "kind": "external", "valid": desc.isValid, "issues": desc.validationIssues,
            "minAppVersion": desc.manifest.minAppVersion ?? NSNull(),
            "timeoutSeconds": desc.manifest.effectiveTimeoutSeconds,
            "hasCapabilitiesDeclaration": desc.manifest.capabilities != nil,
            "hasResourceScopesDeclaration": desc.manifest.resourceScopes != nil,
            "hasCustomBundleIcon": desc.customIconURL != nil,
            "categoryBadge": desc.displayCategoryBadge,
            "includeInGlobalSearch": desc.includeInGlobalSearch,
            "searchIndexInGlobalSearch": desc.searchIndexInGlobalSearch,
            "isPureSandbox": desc.isPureSandbox
        ]
        report["declaredCommands"] = desc.declaredCommands.map(\.id)
        report["declaredCapabilities"] = desc.declaredCapabilities.map(\.rawValue)
        report["declaredResourceScopes"] = desc.declaredResourceScopes.map(\.rawValue)
        report["grantedResourceScopes"] = desc.grantedResourceScopes.map(\.rawValue).sorted()
        report["revokedResourceScopes"] = desc.revokedResourceScopes.map(\.rawValue).sorted()
        report["declaredContextKinds"] = desc.declaredContextKinds.map(\.rawValue)
        report["acceptExtensions"] = desc.manifest.acceptExtensions ?? []
        report["acceptURLHosts"] = desc.manifest.acceptURLHosts ?? []
        report["effectiveKeywords"] = desc.effectiveKeywords
        report["commandHotKeys"] = desc.overrides.commandHotKeys
        report["quickButtonCommandIDs"] = desc.overrides.quickButtonCommandIDs
        report["menuBarCommandIDs"] = desc.overrides.menuBarCommandIDs
        report["grantedCapabilities"] = desc.grantedCapabilities.map(\.rawValue).sorted()
        report["declaredPermissions"] = desc.declaredPermissions.map(\.rawValue)
        return textResult(prettyJSON(report))
    }

    func handleUpdatePluginOverrides(arguments: [String: Any]) -> [String: Any] {
        let id = arguments["id"] as? String ?? ""
        guard PluginSystem.isValidAnyPluginID(id) else {
            return textResult("Invalid plugin id: \(id)", isError: true)
        }
        do {
            try PluginSystem.updatePluginOverrides(id: id, in: pluginsDirectory) { ov in
                if let kws = arguments["customKeywords"] as? [String] { ov.customKeywords = kws }
                if let hk = arguments["customHotKey"] as? String { ov.customHotKey = hk }
                if let cmdHKs = arguments["commandHotKeys"] as? [String: String] {
                    for (k, v) in cmdHKs { ov.commandHotKeys[k] = v }
                }
                if let pin = arguments["pinnedInOverlay"] as? Bool { ov.pinnedInOverlay = pin }
                if let mb = arguments["showInMenuBar"] as? Bool { ov.showInMenuBar = mb }
                if let qbs = arguments["quickButtonCommandIDs"] as? [String] { ov.quickButtonCommandIDs = qbs }
                if let mbs = arguments["menuBarCommandIDs"] as? [String] { ov.menuBarCommandIDs = mbs }
                if let cmdSearch = arguments["commandSearchOverrides"] as? [String: Bool] {
                    for (cmdID, flag) in cmdSearch { ov.commandSearchOverrides[cmdID] = flag }
                }
                if let glob = arguments["includeInGlobalSearch"] as? Bool { ov.includeInGlobalSearchOverride = glob }
                if let idxGlob = arguments["searchIndexInGlobalSearch"] as? Bool { ov.searchIndexGlobalOverride = idxGlob }
                if let side = arguments["showInSettingsSidebar"] as? Bool { ov.showInSettingsSidebar = side }
                if let boost = arguments["priorityBoost"] as? Int { ov.priorityBoost = boost }
            }
            if let revRaw = arguments["revokedResourceScopes"] as? [String], !PluginBuiltinRegistry.isBuiltin(id: id) {
                let desiredRevoked = Set(revRaw.compactMap(PluginResourceScope.init(rawValue:)))
                for scope in PluginResourceScope.allCases {
                    try PluginSystem.setPluginResourceScopeGranted(id: id, scope: scope, granted: !desiredRevoked.contains(scope), in: pluginsDirectory)
                }
            }
            let updated = PluginSystem.pluginOverrides(id: id, in: pluginsDirectory)
            let revokedNow = PluginSystem.revokedResourceScopes(id: id, in: pluginsDirectory).map(\.rawValue).sorted()
            var response: [String: Any] = [
                "id": id,
                "customKeywords": updated.customKeywords ?? NSNull(),
                "customHotKey": updated.customHotKey ?? NSNull(),
                "commandHotKeys": updated.commandHotKeys,
                "pinnedInOverlay": updated.pinnedInOverlay,
                "showInMenuBar": updated.showInMenuBar
            ]
            response["quickButtonCommandIDs"] = updated.quickButtonCommandIDs
            response["menuBarCommandIDs"] = updated.menuBarCommandIDs
            response["commandSearchOverrides"] = updated.commandSearchOverrides
            response["revokedResourceScopes"] = revokedNow
            response["includeInGlobalSearch"] = updated.includeInGlobalSearch
            response["searchIndexGlobalOverride"] = updated.searchIndexGlobalOverride ?? NSNull()
            response["showInSettingsSidebar"] = updated.showInSettingsSidebar
            response["priorityBoost"] = updated.priorityBoost
            return textResult(prettyJSON(response))
        } catch {
            return textResult("Error: \(error.localizedDescription)", isError: true)
        }
    }

    func handleRunPluginTest(arguments: [String: Any]) -> [String: Any] {
        let id = arguments["id"] as? String ?? ""
        let query = arguments["query"] as? String ?? ""
        let clip = arguments["clipboardText"] as? String ?? ""
        let cliArgs = arguments["arguments"] as? [String] ?? []
        let configOverrides = arguments["configOverrides"] as? [String: String]
        let contextPayload = parseContextPayload(from: arguments["context"] as? [String: Any])
        if PluginBuiltinRegistry.isBuiltin(id: id) {
            guard let resolved = PluginBuiltinRegistry.runBuiltin(id: id, query: query, arguments: cliArgs) else {
                return textResult("Unknown builtin plugin: \(id)", isError: true)
            }
            return textResult(prettyJSON([
                "kind": "builtin", "exitCode": resolved.execution.exitCode,
                "durationMs": resolved.execution.durationMs,
                "isStructuredView": resolved.isStructuredView,
                "viewValidation": viewValidationJSON(for: resolved),
                "stdout": resolved.execution.stdout
            ]))
        }
        guard PluginSystem.isSafePluginID(id) else { return textResult("Invalid plugin id: \(id)", isError: true) }
        let dir = pluginsDirectory.appendingPathComponent(id, isDirectory: true)
        var desc = PluginSystem.loadPlugin(at: dir, in: pluginsDirectory)
        if (arguments["autoGrantDeclaredCapabilities"] as? Bool) == true, !desc.declaredCapabilities.isEmpty {
            try? PluginSystem.setPluginCapabilities(id: id, capabilities: Set(desc.declaredCapabilities), in: pluginsDirectory)
            desc = PluginSystem.loadPlugin(at: dir, in: pluginsDirectory)
        }
        do {
            let resolved = try PluginSystem.runPluginSync(
                desc, query: query, clipboardText: clip, arguments: cliArgs,
                contextPayload: contextPayload, configOverrides: configOverrides,
                in: pluginsDirectory
            )
            return textResult(prettyJSON([
                "kind": "external", "exitCode": resolved.execution.exitCode,
                "durationMs": resolved.execution.durationMs,
                "isStructuredView": resolved.isStructuredView,
                "viewValidation": viewValidationJSON(for: resolved),
                "stdout": resolved.execution.stdout, "stderr": resolved.execution.stderr
            ]), isError: resolved.execution.exitCode != 0)
        } catch {
            return textResult("Execution error: \(error.localizedDescription)", isError: true)
        }
    }

    private func parseContextPayload(from raw: [String: Any]?) -> PluginContextPayload? {
        guard let raw, let kindRaw = raw["kind"] as? String, let kind = PluginContextKind(rawValue: kindRaw) else {
            return nil
        }
        return PluginContextPayload(
            kind: kind, text: raw["text"] as? String, url: raw["url"] as? String,
            filePaths: raw["filePaths"] as? [String], source: (raw["source"] as? String) ?? "mcp-test"
        )
    }

    private func viewValidationJSON(for resolved: PluginResolvedOutput) -> [String: Any] {
        if let payload = resolved.viewPayload {
            let itemCount = payload.items?.count ?? 0
            let actionCount = (payload.items ?? []).reduce(0) { sum, item in
                sum + (item.actions?.count ?? ((item.commandArgs?.isEmpty == false) ? 1 : 0))
            }
            return [
                "valid": true, "title": payload.title,
                "itemCount": itemCount, "actionCount": actionCount,
                "hasEffect": payload.effect != nil
            ]
        }
        return ["valid": false, "diagnostic": resolved.viewParseDiagnostic ?? "Not a structured view payload"]
    }
}

import Foundation
import LumakeyCore

extension MCPServer {
    func handleValidatePlugin(arguments: [String: Any]) -> [String: Any] {
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
        let desc = PluginSystem.loadPlugin(at: dir, in: pluginsDirectory, includeSecrets: false)
        return textResult(prettyJSON([
            "id": desc.id, "kind": "external", "valid": desc.isValid, "issues": desc.validationIssues,
            "hasCapabilitiesDeclaration": desc.manifest.capabilities != nil,
            "hasResourceScopesDeclaration": desc.manifest.resourceScopes != nil,
            "declaredCapabilities": desc.declaredCapabilities.map(\.rawValue),
            "declaredResourceScopes": desc.declaredResourceScopes.map(\.rawValue),
            "grantedCapabilities": desc.grantedCapabilities.map(\.rawValue).sorted(),
            "declaredPermissions": desc.declaredPermissions.map(\.rawValue),
            "isPureSandbox": desc.isPureSandbox
        ]))
    }

    func handleRunPluginTest(arguments: [String: Any]) -> [String: Any] {
        let id = arguments["id"] as? String ?? ""
        let query = arguments["query"] as? String ?? ""
        let clip = arguments["clipboardText"] as? String ?? ""
        let cliArgs = arguments["arguments"] as? [String] ?? []
        let configOverrides = arguments["configOverrides"] as? [String: String]
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
        var desc = PluginSystem.loadPlugin(at: dir, in: pluginsDirectory, allowKeychainInteraction: false)
        if (arguments["autoGrantDeclaredCapabilities"] as? Bool) == true, !desc.declaredCapabilities.isEmpty {
            try? PluginSystem.setPluginCapabilities(id: id, capabilities: Set(desc.declaredCapabilities), in: pluginsDirectory)
            desc = PluginSystem.loadPlugin(at: dir, in: pluginsDirectory, allowKeychainInteraction: false)
        }
        do {
            let resolved = try PluginSystem.runPluginSync(
                desc,
                query: query,
                clipboardText: clip,
                arguments: cliArgs,
                configOverrides: configOverrides,
                in: pluginsDirectory
            )
            return textResult(prettyJSON([
                "kind": "external",
                "exitCode": resolved.execution.exitCode,
                "durationMs": resolved.execution.durationMs,
                "isStructuredView": resolved.isStructuredView,
                "viewValidation": viewValidationJSON(for: resolved),
                "stdout": resolved.execution.stdout,
                "stderr": resolved.execution.stderr
            ]), isError: resolved.execution.exitCode != 0)
        } catch {
            return textResult("Execution error: \(error.localizedDescription)", isError: true)
        }
    }

    private func viewValidationJSON(for resolved: PluginResolvedOutput) -> [String: Any] {
        if let payload = resolved.viewPayload {
            let itemCount = payload.items?.count ?? 0
            let actionCount = (payload.items ?? []).reduce(0) { sum, item in
                sum + (item.actions?.count ?? ((item.commandArgs?.isEmpty == false) ? 1 : 0))
            }
            return [
                "valid": true,
                "title": payload.title,
                "itemCount": itemCount,
                "actionCount": actionCount,
                "hasEffect": payload.effect != nil
            ]
        }
        return [
            "valid": false,
            "diagnostic": resolved.viewParseDiagnostic ?? "Not a structured view payload"
        ]
    }
}

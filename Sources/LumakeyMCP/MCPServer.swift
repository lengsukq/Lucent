import Foundation
import LumakeyCore

final class MCPServer {
    let pluginsDirectory: URL
    let customHomeLayoutURL: URL?

    init(pluginsDirectory: URL, customHomeLayoutURL: URL? = nil) {
        self.pluginsDirectory = pluginsDirectory
        self.customHomeLayoutURL = customHomeLayoutURL
    }

    func runStdioLoop() {
        while let line = readLine(strippingNewline: true) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let method = request["method"] as? String
            else { continue }

            guard let id = request["id"] else { continue }
            let params = request["params"] as? [String: Any] ?? [:]
            writeJSONLine(handleRequest(id: id, method: method, params: params))
        }
    }

    private func handleRequest(id: Any, method: String, params: [String: Any]) -> [String: Any] {
        switch method {
        case "initialize":
            return ok(id: id, result: [
                "protocolVersion": "2024-11-05",
                "capabilities": ["resources": [:], "tools": [:]],
                "serverInfo": ["name": "lumakey-mcp", "version": "0.3.2"],
                "instructions": """
                Lumakey is a lightweight macOS productivity hub (NOT a resident server, daemon runner, or cron gateway).
                Follow these mandatory rules when creating plugins or customizing the Launcher Home Page:
                1. Before authoring any plugin, read `lumakey://specs/plugin-v3` and call `lumakey_list_plugins` (to check BUILTIN native plugins like SmoothScroll/LumaLink/SystemPulse so you do not duplicate them) and `lumakey_app_permissions` (to audit app-wide permission usage).
                2. Every plugin MUST explicitly declare its required permissions via `capabilities` (Host Bridge) AND `resourceScopes` (`network`, `filesystem`, `subprocess`, or `[]` if none) in `plugin.json` at registration time. Pass `[]` for both when authoring a pure sandboxed plugin.
                3. Reuse host TCC permissions through declared `capabilities` and the ephemeral per-run UDS Host Bridge (`LUMAKEY_BRIDGE_SOCK` / `LUMAKEY_BRIDGE_TOKEN`). Never write `launchd` plists, resident HTTP servers, or infinite `while true` loops.
                4. Prefer `mode: "view"` outputting `PluginViewPayload` JSON for native Liquid Glass cards.
                5. Always run `lumakey_validate_plugin` and `lumakey_run_plugin_test` after scaffolding or editing a plugin.
                6. When sharing a plugin or building a custom plugin store (`lumakey-registry.json`), read `lumakey://specs/plugin-store-v1` and call `lumakey_package_plugin_for_store`.
                7. When customizing the user's Launcher Home Page (Bento tiles, Omni Dock, bookmark shelves, or multi-scene profiles), read `lumakey://specs/home-layout-v1` and call `lumakey_get_home_layout` first, then apply changes via `lumakey_update_home_layout`, `lumakey_upsert_home_item`, or `lumakey_remove_home_item`.
                """
            ])
        case "ping":
            return ok(id: id, result: [:])
        case "resources/list":
            return ok(id: id, result: [
                "resources": [
                    [
                        "uri": "lumakey://specs/plugin-v3",
                        "name": "Lumakey Plugin Spec v3",
                        "description": "Unified Builtin/External model, mandatory registration capabilities declaration, and ephemeral UDS Host Bridge protocol.",
                        "mimeType": "text/markdown"
                    ],
                    [
                        "uri": "lumakey://specs/plugin-store-v1",
                        "name": "Lumakey Plugin & Store Distribution Spec v1",
                        "description": "Smart URL auto-detection rules, lumakey-registry.json custom store format, SHA-256 verification, and packaging workflow.",
                        "mimeType": "text/markdown"
                    ],
                    [
                        "uri": "lumakey://specs/home-layout-v1",
                        "name": "Lumakey Home Layout & Multi-Profile Spec v1",
                        "description": "Modular Bento tiles, hybrid Omni Dock, bookmark shelves, multi-scene profiles, and safe HomeLaunchItem targets.",
                        "mimeType": "text/markdown"
                    ]
                ]
            ])
        case "resources/read":
            let uri = params["uri"] as? String ?? ""
            let specText: String? = switch uri {
            case "lumakey://specs/plugin-v3": PluginSystem.specV3Markdown
            case "lumakey://specs/plugin-store-v1": PluginSystem.specStoreV1Markdown
            case "lumakey://specs/home-layout-v1": HomeLayoutConfig.specV1Markdown
            default: nil
            }
            guard let specText else {
                return err(id: id, code: -32602, message: "Unknown resource URI: \(uri)")
            }
            return ok(id: id, result: [
                "contents": [["uri": uri, "mimeType": "text/markdown", "text": specText]]
            ])
        case "tools/list":
            return ok(id: id, result: ["tools": toolSchemas()])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            return ok(id: id, result: callTool(name: name, arguments: args))
        default:
            return err(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    func schema(_ name: String, _ desc: String, _ props: [String: Any], _ req: [String]) -> [String: Any] {
        var input: [String: Any] = ["type": "object", "properties": props]
        if !req.isEmpty { input["required"] = req }
        return ["name": name, "description": desc, "inputSchema": input]
    }

    func textResult(_ text: String, isError: Bool = false) -> [String: Any] {
        ["content": [["type": "text", "text": text]], "isError": isError]
    }

    private func ok(id: Any, result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private func err(id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    func prettyJSON(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }

    private func writeJSONLine(_ object: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) else { return }
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
    }
}

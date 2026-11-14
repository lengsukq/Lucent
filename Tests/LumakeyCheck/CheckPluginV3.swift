import Foundation
import LumakeyCore

func testV081PluginV3AndMCP() throws {
    try verifyBuiltinRegistryAndLifecycle()
    try verifyPermissionDeclarationAndAuditMatrix()
    try verifyHostBridgeSecurityAndRoundtrip()
    try verifyMCPServerV3Subprocess()
    print("[ok] v0.8.1 Plugin v3 (Builtin/Capabilities/PermissionAudit/HostBridge) + lumakey-mcp v0.3.0")
}

private func verifyBuiltinRegistryAndLifecycle() throws {
    let builtins = PluginBuiltinRegistry.descriptors()
    check(builtins.count == 3, "3 builtin native plugins registered")
    let ids = Set(builtins.map(\.id))
    check(ids == ["builtin-mos", "builtin-lumalink", "builtin-system-pulse"], "expected builtin plugin IDs")
    check(builtins.allSatisfy { $0.isBuiltin && $0.builtinMetadata?.categoryBadge == "BUILTIN" && !$0.declaredPermissions.isEmpty },
          "every builtin plugin declares BUILTIN badge & requiredPermissions")

    // Default listPlugins keeps external only unless includeBuiltin=true
    let tmp = try makeTempDir("v081-builtin")
    defer { try? FileManager.default.removeItem(at: tmp) }
    check(PluginSystem.listPlugins(in: tmp, includeBuiltin: false).isEmpty, "includeBuiltin=false excludes builtins")
    check(PluginSystem.listPlugins(in: tmp, includeBuiltin: true).count == 3, "includeBuiltin=true includes builtins")

    // Stopping builtins turns off listeners/taps safely
    let savedMos = MosConfig.load()
    let savedLL = LumaLinkConfig.load()
    defer {
        MosEngine.shared.stopTapAndReleaseAll()
        LumaLinkServer.shared.stopAll(waitUntilFinished: true)
        savedMos.save()
        savedLL.save()
    }
    check(PluginBuiltinRegistry.setBuiltinEnabled(id: "builtin-mos", isEnabled: false), "disable builtin-mos")
    check(!MosEngine.shared.isTapActive, "disabling builtin-mos stops CGEventTap")
    check(PluginBuiltinRegistry.setBuiltinEnabled(id: "builtin-lumalink", isEnabled: false), "disable builtin-lumalink")
    check(!LumaLinkServer.shared.currentSnapshot().isListening, "disabling builtin-lumalink stops listener")

    let runOut = PluginBuiltinRegistry.runBuiltin(id: "builtin-mos", query: "wheel")
    check(runOut?.isStructuredView == true && runOut?.viewPayload?.items?.first?.openURL == "lumakey://settings/mos",
          "runBuiltin returns structured view card with lumakey://settings/mos URL")
}

private func verifyPermissionDeclarationAndAuditMatrix() throws {
    let tmp = try makeTempDir("v081-perms")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let pluginsRoot = tmp.appendingPathComponent("Plugins", isDirectory: true)
    try FileManager.default.createDirectory(at: pluginsRoot, withIntermediateDirectories: true)

    // 1. Omitting capabilities in plugin.json fails validation
    let missingDir = pluginsRoot.appendingPathComponent("missing-caps", isDirectory: true)
    try FileManager.default.createDirectory(at: missingDir, withIntermediateDirectories: true)
    let noopURL = missingDir.appendingPathComponent("run.sh")
    try "#!/bin/zsh\necho ok\n".write(to: noopURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: noopURL.path)
    try Data("""
    {"id":"missing-caps","name":"Missing Caps","version":"1.0.0","description":"x","mode":"script","keywords":["mc"],"entry":"run.sh"}
    """.utf8).write(to: missingDir.appendingPathComponent("plugin.json"))
    let missingDesc = PluginSystem.loadPlugin(at: missingDir, in: pluginsRoot)
    check(!missingDesc.isValid && missingDesc.validationIssues.contains(where: { $0.contains("capabilities") }),
          "omitting capabilities fails validation")
    try? FileManager.default.removeItem(at: missingDir)

    // 2. Unknown capability fails validation; missing resourceScopes fails strict validation; reserved builtin- prefix blocked
    let badCapManifest = PluginManifest(
        id: "builtin-spoof", name: "Spoof", version: "1.0.0", description: "bad",
        mode: .script, keywords: ["s"], entry: "run.sh", capabilities: ["unknownPerm"], resourceScopes: nil
    )
    let issues = PluginSystem.validate(manifest: badCapManifest, in: pluginsRoot)
    check(issues.contains(where: { $0.contains("保留前缀") })
          && issues.contains(where: { $0.contains("unknownPerm") })
          && issues.contains(where: { $0.contains("resourceScopes") }),
          "reserved builtin- prefix, unknown capability, and missing resourceScopes rejected")

    // 3. Explicit sandbox plugin [] and Host Bridge plugin [clipboard, displayInfo]
    let sandboxDesc = try PluginSystem.scaffoldPlugin(
        id: "pure-sandbox", name: "Pure Sandbox", keywords: ["ps"], description: "sandbox", capabilities: [], in: pluginsRoot
    )
    check(sandboxDesc.isValid && sandboxDesc.declaredPermissions.isEmpty, "pure sandbox [] plugin valid")

    let capDesc = try PluginSystem.scaffoldPlugin(
        id: "clip-disp", name: "Clip Display", keywords: ["cd"], description: "bridge",
        capabilities: [.clipboard, .displayInfo], in: pluginsRoot
    )
    check(capDesc.isValid && capDesc.grantedCapabilities.isEmpty, "declared capabilities default ungranted (least privilege)")

    let allPlugins = PluginSystem.listPlugins(in: pluginsRoot, includeDisabled: true, includeBuiltin: true)
    let audit = PluginPermissionAudit.buildAudit(plugins: allPlugins, accessibilityGranted: false)
    let accEntry = audit.first(where: { $0.permission == .accessibility })
    check(accEntry?.plugins.map(\.pluginID).contains("builtin-mos") == true
          && accEntry?.plugins.map(\.pluginID).contains("builtin-lumalink") == true,
          "accessibility audit entry lists both builtin-mos and builtin-lumalink")

    let clipEntry = audit.first(where: { $0.permission == .clipboard })
    check(clipEntry?.plugins.first?.pluginID == "clip-disp" && clipEntry?.plugins.first?.isAuthorized == false,
          "clipboard audit shows clip-disp before grant (isAuthorized=false)")

    try PluginSystem.setPluginCapabilityGranted(id: "clip-disp", capability: .clipboard, granted: true, in: pluginsRoot)
    let updatedPlugins = PluginSystem.listPlugins(in: pluginsRoot, includeDisabled: true, includeBuiltin: true)
    let updatedClip = PluginPermissionAudit.buildAudit(plugins: updatedPlugins).first(where: { $0.permission == .clipboard })
    check(updatedClip?.plugins.first?.isAuthorized == true, "clipboard audit updates to isAuthorized=true after grant")
    check(PluginPermissionAudit.sandboxOnlyPlugins(in: updatedPlugins).map(\.id) == ["pure-sandbox"],
          "sandboxOnlyPlugins reports pure-sandbox")
}

private func verifyHostBridgeSecurityAndRoundtrip() throws {
    let tmp = try makeTempDir("v081-bridge")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let pluginsRoot = tmp.appendingPathComponent("Plugins", isDirectory: true)
    let searchDir = tmp.appendingPathComponent("IndexedFolder", isDirectory: true)
    try FileManager.default.createDirectory(at: pluginsRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: searchDir, withIntermediateDirectories: true)

    let targetFile = searchDir.appendingPathComponent("lumakey-v3-needle.txt")
    try "needle".write(to: targetFile, atomically: true, encoding: .utf8)
    let pngFile = tmp.appendingPathComponent("bridge-ocr.png")
    try renderTextPNG(text: "BRIDGE99", to: pngFile)

    let everythingIndex = EverythingIndex(
        rootURLs: [searchDir],
        nodes: [IndexedNode(parentID: -1, rootIndex: 0, isDirectory: false, name: "lumakey-v3-needle.txt")],
        builtAt: Date(),
        reachedNodeLimit: false
    )

    final class ClipboardBox: @unchecked Sendable {
        private let lock = NSLock()
        private var text = "INIT_CLIP"
        func get() -> String { lock.withLock { text } }
        func set(_ next: String) -> Bool { lock.withLock { text = next }; return true }
    }
    let clipBox = ClipboardBox()
    let hostCtx = PluginBridgeHostContext(
        everythingIndex: everythingIndex,
        clipboardReader: { clipBox.get() },
        clipboardWriter: { clipBox.set($0) },
        preCapturedSelection: PluginSelectionSnapshot(text: "SELECTED_WORD", sourceApp: "Safari", bundleIdentifier: "com.apple.Safari")
    )

    // Create external script probing unauthorized, invalid token, and authorized capabilities + socket path check
    let plugDir = pluginsRoot.appendingPathComponent("bridge-probe", isDirectory: true)
    try FileManager.default.createDirectory(at: plugDir, withIntermediateDirectories: true)
    let script = """
    #!/bin/zsh
    set -euo pipefail
    cat >/dev/null
    SOCK="$LUMAKEY_BRIDGE_SOCK"
    TOK="$LUMAKEY_BRIDGE_TOKEN"
    REQ_BAD_TOK=$(printf '{"token":"wrong","capability":"clipboard","action":"read"}\\n' | /usr/bin/nc -U "$SOCK")
    REQ_DENIED_SYS=$(printf '{"token":"%s","capability":"systemControl","action":"status"}\\n' "$TOK" | /usr/bin/nc -U "$SOCK")
    REQ_NOT_DECL=$(printf '{"token":"%s","capability":"lumaLinkStatus","action":"status"}\\n' "$TOK" | /usr/bin/nc -U "$SOCK")
    REQ_CLIP=$(printf '{"token":"%s","capability":"clipboard","action":"write","params":{"text":"NEW_CLIP"}}\\n' "$TOK" | /usr/bin/nc -U "$SOCK")
    REQ_SEL=$(printf '{"token":"%s","capability":"selection","action":"read","params":{}}\\n' "$TOK" | /usr/bin/nc -U "$SOCK")
    REQ_AUD=$(printf '{"token":"%s","capability":"audio","action":"stop","params":{}}\\n' "$TOK" | /usr/bin/nc -U "$SOCK")
    REQ_SEARCH=$(printf '{"token":"%s","capability":"everythingSearch","action":"search","params":{"query":"lumakey-v3-needle"}}\\n' "$TOK" | /usr/bin/nc -U "$SOCK")
    REQ_OCR=$(printf '{"token":"%s","capability":"ocr","action":"recognize","params":{"imagePath":"\(pngFile.path)"}}\\n' "$TOK" | /usr/bin/nc -U "$SOCK")
    echo "SOCK=$SOCK"
    echo "BAD_TOK=$REQ_BAD_TOK"
    echo "DENIED_SYS=$REQ_DENIED_SYS"
    echo "NOT_DECL=$REQ_NOT_DECL"
    echo "CLIP=$REQ_CLIP"
    echo "SEL=$REQ_SEL"
    echo "AUD=$REQ_AUD"
    echo "SEARCH=$REQ_SEARCH"
    echo "OCR=$REQ_OCR"
    """
    let scriptURL = plugDir.appendingPathComponent("run.sh")
    try script.write(to: scriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

    let manifest = PluginManifest(
        id: "bridge-probe", name: "Bridge Probe", version: "3.0.0", description: "probe",
        mode: .script, keywords: ["probe"], entry: "run.sh",
        capabilities: ["clipboard", "selection", "audio", "everythingSearch", "ocr", "systemControl"],
        resourceScopes: ["subprocess"]
    )
    try JSONEncoder().encode(manifest).write(to: plugDir.appendingPathComponent("plugin.json"))

    // Grant clipboard, selection, audio, everythingSearch, ocr; intentionally keep systemControl DENIED and lumaLinkStatus NOT DECLARED
    try PluginSystem.setPluginCapabilities(id: "bridge-probe", capabilities: [.clipboard, .selection, .audio, .everythingSearch, .ocr], in: pluginsRoot)
    let desc = PluginSystem.loadPlugin(at: plugDir, in: pluginsRoot)
    let res = try PluginSystem.runScriptPlugin(desc, query: "go", hostContext: hostCtx, in: pluginsRoot)
    check(res.exitCode == 0, "bridge-probe exited 0, stderr=\(res.stderr)")

    check(res.stdout.contains("BAD_TOK={\"action\":\"read\",\"capability\":\"clipboard\",\"error\":\"invalid_token\",\"ok\":false}")
          || res.stdout.contains("\"invalid_token\""), "bad token rejected")
    check(res.stdout.contains("\"capability_not_granted\""), "ungranted systemControl rejected")
    check(res.stdout.contains("\"capability_not_declared\""), "undeclared lumaLinkStatus rejected")
    check(clipBox.get() == "NEW_CLIP" && res.stdout.contains("\"written\":true"), "clipboard write roundtrip succeeded")
    check(res.stdout.contains("SELECTED_WORD") && res.stdout.contains("com.apple.Safari"), "selection bridge returned pre-captured selection")
    check(res.stdout.contains("\"stopped\":true"), "audio bridge stop action succeeded")
    check(res.stdout.contains("lumakey-v3-needle.txt"), "everythingSearch returned real indexed file")
    check(res.stdout.contains("BRIDGE99"), "OCR returned text from rendered PNG")

    if let sockLine = res.stdout.split(separator: "\n").first(where: { $0.hasPrefix("SOCK=") }) {
        let sockPath = String(sockLine.dropFirst("SOCK=".count))
        check(!FileManager.default.fileExists(atPath: sockPath), "ephemeral UDS socket cleaned up after execution: \(sockPath)")
    } else {
        check(false, "expected SOCK= output line")
    }
}

private func verifyMCPServerV3Subprocess() throws {
    let tmp = try makeTempDir("v081-mcp-v3")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let binDir = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent()
    let proc = Process()
    proc.executableURL = binDir.appendingPathComponent("lumakey-mcp")
    proc.arguments = ["--plugins-dir", tmp.path]
    let inPipe = Pipe(); let outPipe = Pipe()
    proc.standardInput = inPipe; proc.standardOutput = outPipe
    try proc.run()

    let requests = [
        #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#,
        #"{"jsonrpc":"2.0","id":2,"method":"resources/read","params":{"uri":"lumakey://specs/plugin-v3"}}"#,
        #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"lumakey_scaffold_plugin","arguments":{"id":"no-caps-fail","name":"Fail","keywords":["f"]}}}"#,
        #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"lumakey_scaffold_plugin","arguments":{"id":"v3-demo","name":"V3 Demo","keywords":["v3d"],"mode":"view","capabilities":["displayInfo"],"resourceScopes":["subprocess"]}}}"#,
        #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"lumakey_list_plugins","arguments":{}}}"#,
        #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"lumakey_app_permissions","arguments":{}}}"#,
        #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"lumakey_validate_plugin","arguments":{"id":"v3-demo"}}}"#,
        #"{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"lumakey_run_plugin_test","arguments":{"id":"v3-demo","query":"test"}}}"#,
        #"{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"lumakey_remove_plugin","arguments":{"id":"builtin-mos"}}}"#,
        #"{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"lumakey_remove_plugin","arguments":{"id":"v3-demo"}}}"#
    ]
    try inPipe.fileHandleForWriting.write(contentsOf: Data((requests.joined(separator: "\n") + "\n").utf8))
    try inPipe.fileHandleForWriting.close()
    proc.waitUntilExit()
    check(proc.terminationStatus == 0, "lumakey-mcp v0.3.0 exited 0")

    let lines = (String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
        .split(separator: "\n").map(String.init)
    check(lines.count == 10, "expected 10 MCP v3 responses, got \(lines.count)")

    func parseToolJSON(_ index: Int) -> [String: Any] {
        guard let outerData = lines[index].data(using: .utf8),
              let outer = try? JSONSerialization.jsonObject(with: outerData) as? [String: Any],
              let result = outer["result"] as? [String: Any],
              let content = result["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String,
              let innerData = text.data(using: .utf8),
              let inner = try? JSONSerialization.jsonObject(with: innerData) as? [String: Any]
        else { return [:] }
        return inner
    }

    check(lines[0].contains("0.3.0") && lines[0].contains("instructions") && lines[0].contains("lumakey://specs/plugin-v3"),
          "initialize returns version 0.3.0 + instructions")
    check(lines[1].contains("Host Bridge") && lines[1].contains("capabilities"), "plugin-v3 spec returned")
    check(lines[2].contains(#""isError":true"#), "scaffold without capabilities fails")
    check(lines[3].contains("v3-demo") && lines[3].contains("displayInfo"), "scaffold with capabilities succeeds")
    check(lines[4].contains("builtin-mos") && lines[4].contains("builtin-lumalink") && lines[4].contains("v3-demo"),
          "list_plugins exposes builtin + external plugins")
    check(lines[5].contains("accessibility") && lines[5].contains("displayInfo") && lines[5].contains("v3-demo"),
          "app_permissions exposes full permission matrix")
    let valObj = parseToolJSON(6)
    check((valObj["valid"] as? Bool) == true && (valObj["hasCapabilitiesDeclaration"] as? Bool) == true,
          "validate_plugin confirms valid v3 plugin, got \(lines[6])")
    let runObj = parseToolJSON(7)
    check((runObj["isStructuredView"] as? Bool) == true && (runObj["exitCode"] as? Int) == 0,
          "run_plugin_test runs view card cleanly, got \(lines[7])")
    check(lines[8].contains(#""isError":true"#), "remove_plugin protects builtin-mos")
    let remObj = parseToolJSON(9)
    check((remObj["removed"] as? Bool) == true, "remove_plugin deletes v3-demo")
}

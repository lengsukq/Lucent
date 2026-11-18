import Foundation
import LucentCore

func testV082PluginV31ArchitectureHardening() throws {
    try verifyStrictResourceScopesAndImportGate()
    try verifySecretKeychainAndClipboardGate()
    try verifyPluginDataSeparationAndScopedWatcher()
    try verifyProcessGroupTaskCancellation()
    try verifyViewProtocolV2AndBuiltinArguments()
    try verifyStarterSyntaxAndMCPActionTest()
    print("[ok] v0.8.2 Plugin v3.1 Architecture (Keychain/ClipboardGate/PluginData/PGIDCancel/ViewV2/MCP)")
}

private func verifyStrictResourceScopesAndImportGate() throws {
    let tmp = try makeTempDir("v31-strict")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let pluginsRoot = tmp.appendingPathComponent("Plugins", isDirectory: true)
    try FileManager.default.createDirectory(at: pluginsRoot, withIntermediateDirectories: true)

    let badSrc = tmp.appendingPathComponent("bad-import", isDirectory: true)
    try FileManager.default.createDirectory(at: badSrc, withIntermediateDirectories: true)
    let badScript = badSrc.appendingPathComponent("run.sh")
    try "#!/bin/zsh\necho ok\n".write(to: badScript, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: badScript.path)
    try Data("""
    {"id":"bad-import","name":"Bad","version":"1.0.0","description":"x","mode":"script","keywords":["b"],"entry":"run.sh","capabilities":[]}
    """.utf8).write(to: badSrc.appendingPathComponent("plugin.json"))

    var blocked = false
    do {
        _ = try PluginSystem.importPluginDirectory(from: badSrc, in: pluginsRoot)
    } catch {
        blocked = true
    }
    check(blocked, "importPluginDirectory blocks plugin missing resourceScopes")
    check(!FileManager.default.fileExists(atPath: pluginsRoot.appendingPathComponent("bad-import").path),
          "blocked import leaves nothing in Plugins dir")

    let netPlug = try PluginSystem.scaffoldPlugin(
        id: "net-tool", name: "Net Tool", keywords: ["nt"], description: "network",
        capabilities: [], resourceScopes: [.network, .filesystem], in: pluginsRoot
    )
    check(netPlug.isValid && !netPlug.isPureSandbox, "plugin with resourceScopes is not marked pure sandbox")
    let loaded = PluginSystem.listPlugins(in: pluginsRoot, includeDisabled: true, includeBuiltin: false)
    check(!PluginPermissionAudit.sandboxOnlyPlugins(in: loaded).contains(where: { $0.id == "net-tool" }),
          "sandboxOnlyPlugins excludes plugins with resourceScopes")
}

private func verifySecretKeychainAndClipboardGate() throws {
    let tmp = try makeTempDir("v31-secrets")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let pluginsRoot = tmp.appendingPathComponent("Plugins", isDirectory: true)
    try FileManager.default.createDirectory(at: pluginsRoot, withIntermediateDirectories: true)

    let plugDir = pluginsRoot.appendingPathComponent("sec-clip", isDirectory: true)
    try FileManager.default.createDirectory(at: plugDir, withIntermediateDirectories: true)
    let scriptURL = plugDir.appendingPathComponent("run.sh")
    try """
    #!/bin/zsh
    cat
    """.write(to: scriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

    let manifest = PluginManifest(
        schemaVersion: 3, id: "sec-clip", name: "SecClip", version: "1.0.0", description: "test",
        mode: .script, keywords: ["sc"], entry: "run.sh",
        config: [
            PluginConfigField(key: "apiToken", label: "API Token", type: .secret, defaultValue: ""),
            PluginConfigField(key: "region", label: "Region", type: .text, defaultValue: "us")
        ],
        capabilities: ["clipboard"],
        resourceScopes: []
    )
    try JSONEncoder().encode(manifest).write(to: plugDir.appendingPathComponent("plugin.json"))

    // 1. Verify plaintext secrets placed in plugin-state.json are ignored (secrets reside strictly in LocalSecretVault)
    let rawSnap = PluginStateSnapshot(plugins: [
        "sec-clip": PluginInstanceState(isEnabled: true, configValues: ["apiToken": "PLAINTEXT_IGNORED", "region": "eu"], grantedCapabilities: [])
    ])
    try PluginSystem.saveStateSnapshot(rawSnap, in: pluginsRoot)
    let initialDesc = PluginSystem.loadPlugin(at: plugDir, in: pluginsRoot)
    defer { try? PluginSystem.removePlugin(id: "sec-clip", in: pluginsRoot) }
    check(initialDesc.userConfig["apiToken"] == "", "plaintext secret in plugin-state.json is never trusted")
    check(initialDesc.userConfig["region"] == "eu", "non-secret config loaded from plugin-state.json")

    // 2. Update secret cleanly -> stored in LocalSecretVault, never written to plugin-state.json
    try PluginSystem.updatePluginConfig(id: "sec-clip", values: ["apiToken": "KC_SECRET_42", "region": "jp"], in: pluginsRoot)
    let rawAfterUpdate = try String(contentsOf: PluginSystem.stateFileURL(for: pluginsRoot), encoding: .utf8)
    check(!rawAfterUpdate.contains("KC_SECRET_42") && rawAfterUpdate.contains("jp"),
          "secret stored in LocalSecretVault while non-secret remains in plugin-state.json")

    // 3. Ungranted clipboard => stdin clipboard MUST be empty; granted => injected
    let reloadedWithSecret = PluginSystem.loadPlugin(at: plugDir, in: pluginsRoot)
    let ungrantedOut = try PluginSystem.runPluginSync(reloadedWithSecret, query: "q1", clipboardText: "TOP_SECRET_CLIP", in: pluginsRoot)
    check(!ungrantedOut.execution.stdout.contains("TOP_SECRET_CLIP"), "ungranted clipboard is NOT leaked to stdin")
    check(ungrantedOut.execution.stdout.contains("KC_SECRET_42"), "Keychain secret hydrated into runtime stdin config")

    try PluginSystem.setPluginCapabilityGranted(id: "sec-clip", capability: .clipboard, granted: true, in: pluginsRoot)
    let grantedDesc = PluginSystem.loadPlugin(at: plugDir, in: pluginsRoot)
    let grantedOut = try PluginSystem.runPluginSync(grantedDesc, query: "q2", clipboardText: "TOP_SECRET_CLIP", in: pluginsRoot)
    check(grantedOut.execution.stdout.contains("TOP_SECRET_CLIP") && grantedOut.execution.stdout.contains("KC_SECRET_42"),
          "granted stdin receives expected clipboardText and Keychain secret")
}

private func verifyPluginDataSeparationAndScopedWatcher() throws {
    let tmp = try makeTempDir("v31-data")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let pluginsRoot = tmp.appendingPathComponent("Plugins", isDirectory: true)
    try FileManager.default.createDirectory(at: pluginsRoot, withIntermediateDirectories: true)

    let searchHit = DispatchSemaphore(value: 0)
    let watcher = PluginDirectoryWatcher(directoryURL: pluginsRoot, debounceInterval: 0.12) { changes in
        if changes.contains(.searchIndex) { searchHit.signal() }
    }
    defer { watcher?.stop() }

    let plugDir = pluginsRoot.appendingPathComponent("data-plug", isDirectory: true)
    try FileManager.default.createDirectory(at: plugDir, withIntermediateDirectories: true)
    let scriptURL = plugDir.appendingPathComponent("run.sh")
    try """
    #!/bin/zsh
    cat >/dev/null
    printf '{"items":[{"id":"1","title":"DataDir Item","subtitle":"ok"}]}' > "$LUCENT_DATA_DIR/search-index.json"
    echo "$LUCENT_DATA_DIR"
    """.write(to: scriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    try JSONEncoder().encode(PluginManifest(
        schemaVersion: 3, id: "data-plug", name: "DataPlug", version: "1.0.0", description: "d",
        mode: .script, keywords: ["dp"], entry: "run.sh", capabilities: [], resourceScopes: []
    )).write(to: plugDir.appendingPathComponent("plugin.json"))

    let desc = PluginSystem.loadPlugin(at: plugDir, in: pluginsRoot)
    let res = try PluginSystem.runPluginSync(desc, query: "", in: pluginsRoot)
    check(res.execution.stdout.contains("/PluginData/data-plug"), "LUCENT_DATA_DIR points to separated PluginData/<id>")
    check(searchHit.wait(timeout: .now() + 3.0) == .success, "Scoped watcher detected search-index.json change in PluginData")

    let entries = PluginSearchIndex.loadEntries(for: [desc], in: pluginsRoot)
    check(entries.count == 1 && entries.first?.title == "DataDir Item", "PluginSearchIndex loads from PluginData/<id>/search-index.json")

    let exportDest = tmp.appendingPathComponent("Exports", isDirectory: true)
    let exported = try PluginSystem.exportPlugin(id: "data-plug", to: exportDest, in: pluginsRoot)
    check(!FileManager.default.fileExists(atPath: exported.appendingPathComponent("search-index.json").path),
          "exportPlugin excludes runtime PluginData search-index cache")
}

private final class CancelledFlagBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set(_ newValue: Bool) { lock.lock(); defer { lock.unlock() }; value = newValue }
    func get() -> Bool { lock.lock(); defer { lock.unlock() }; return value }
}

private func verifyProcessGroupTaskCancellation() throws {
    let tmp = try makeTempDir("v31-cancel")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let pluginsRoot = tmp.appendingPathComponent("Plugins", isDirectory: true)
    try FileManager.default.createDirectory(at: pluginsRoot, withIntermediateDirectories: true)

    let plugDir = pluginsRoot.appendingPathComponent("slow-sleep", isDirectory: true)
    try FileManager.default.createDirectory(at: plugDir, withIntermediateDirectories: true)
    let scriptURL = plugDir.appendingPathComponent("run.sh")
    try "#!/bin/zsh\nsleep 10 & wait\n".write(to: scriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    try JSONEncoder().encode(PluginManifest(
        schemaVersion: 3, id: "slow-sleep", name: "Slow", version: "1.0.0", description: "s",
        mode: .script, keywords: ["sl"], entry: "run.sh", capabilities: [], resourceScopes: ["subprocess"]
    )).write(to: plugDir.appendingPathComponent("plugin.json"))

    let desc = PluginSystem.loadPlugin(at: plugDir, in: pluginsRoot)
    let sem = DispatchSemaphore(value: 0)
    let cancelledBox = CancelledFlagBox()
    let start = ContinuousClock.now
    let task = Task.detached {
        do {
            _ = try await PluginSystem.runPluginAsync(desc, query: "", in: pluginsRoot, timeoutSeconds: 8.0)
        } catch is CancellationError {
            cancelledBox.set(true)
        } catch {}
        sem.signal()
    }
    Thread.sleep(forTimeInterval: 0.15)
    task.cancel()
    check(sem.wait(timeout: .now() + 2.5) == .success, "Cancelled plugin process returns quickly (< 2.5s)")
    let elapsed = start.duration(to: .now)
    check(cancelledBox.get() && elapsed.components.seconds < 2, "Process group cancellation threw CancellationError swiftly")
}

private func verifyViewProtocolV2AndBuiltinArguments() throws {
    let itemA = PluginViewItem(title: "Same", commandArgs: ["--one"])
    let itemB = PluginViewItem(title: "Same", commandArgs: ["--two"])
    check(itemA.id != itemB.id, "PluginViewItem.id distinguishes items with differing commandArgs")

    let diag = PluginViewPayload.parseDetailed(from: "WARNING log line\n{\"title\":\"Card\"}")
    check(diag.payload == nil && (diag.diagnosticReason?.contains("非 JSON") == true),
          "parseDetailed returns clear diagnostic when stdout has non-JSON prefix")

    let v2JSON = """
    {"schemaVersion":2,"title":"Actions","effect":{"toast":"Done","reloadSearchIndex":true},
     "items":[{"id":"row1","title":"Row","actions":[{"id":"del","label":"Archive","style":"destructive","commandArgs":["--archive","1"],"confirmMessage":"Confirm?"}]}]}
    """
    let parsed = PluginViewPayload.parse(from: v2JSON)
    check(parsed?.items?.first?.actions?.first?.confirmMessage == "Confirm?"
          && parsed?.effect?.reloadSearchIndex == true,
          "View v2 actions/confirmMessage/effect decode cleanly")

    let cfgTmp = try makeTempDir("v31-builtin-cfg")
    defer {
        MosEngine.shared.stopTapAndReleaseAll()
        try? FileManager.default.removeItem(at: cfgTmp)
    }
    let cfgPaths = BuiltinPluginConfigPaths(
        mosURL: cfgTmp.appendingPathComponent("mos-config.json"),
        monitorURL: cfgTmp.appendingPathComponent("telemetry-v2.json")
    )
    let builtinOut = PluginBuiltinRegistry.runBuiltin(id: "builtin-mos", query: "", arguments: ["--disable"], configPaths: cfgPaths)
    check(builtinOut?.viewPayload?.items?.contains(where: { $0.commandArgs == ["--enable"] }) == true,
          "runBuiltin executes --disable argument cleanly")
}

private func verifyStarterSyntaxAndMCPActionTest() throws {
    let starterTmp = try makeTempDir("v31-starters")
    defer { try? FileManager.default.removeItem(at: starterTmp) }
    for tpl in PluginStarterGallery.templates {
        let installed = try PluginStarterGallery.install(templateID: tpl.id, in: starterTmp)
        let entryURL = installed.directoryURL.appendingPathComponent(installed.manifest.entry)
        check(installed.isValid && FileManager.default.isExecutableFile(atPath: entryURL.path),
              "Starter template '\(tpl.id)' installs valid native executable '\(installed.manifest.entry)'")
    }

    let tmp = try makeTempDir("v31-mcp")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let plugDir = tmp.appendingPathComponent("arg-card", isDirectory: true)
    try FileManager.default.createDirectory(at: plugDir, withIntermediateDirectories: true)
    let scriptURL = plugDir.appendingPathComponent("run.sh")
    try """
    #!/bin/zsh
    cat >/dev/null
    echo "{\\"title\\":\\"Arg:${1:-none}\\",\\"items\\":[{\\"title\\":\\"OK\\",\\"commandArgs\\":[\\"--ping\\"]}]}"
    """.write(to: scriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    try JSONEncoder().encode(PluginManifest(
        schemaVersion: 3, id: "arg-card", name: "ArgCard", version: "1.0.0", description: "a",
        mode: .view, keywords: ["ac"], entry: "run.sh", capabilities: [], resourceScopes: []
    )).write(to: plugDir.appendingPathComponent("plugin.json"))

    let binDir = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent()
    let proc = Process()
    proc.executableURL = binDir.appendingPathComponent("lucent-mcp")
    proc.arguments = ["--plugins-dir", tmp.path]
    let inPipe = Pipe(); let outPipe = Pipe()
    proc.standardInput = inPipe; proc.standardOutput = outPipe
    try proc.run()
    let req = #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"lucent_run_plugin_test","arguments":{"id":"arg-card","query":"","arguments":["--detail","99"]}}}"# + "\n"
    try inPipe.fileHandleForWriting.write(contentsOf: Data(req.utf8))
    try inPipe.fileHandleForWriting.close()
    proc.waitUntilExit()
    let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    check(out.contains("Arg:--detail") && out.contains("actionCount"), "lucent_run_plugin_test supports arguments & viewValidation")
}

import Foundation
import LumakeyCore

func testV089PluginStoreAndSmartSniffer() throws {
    try verifySmartSnifferPackagerAndAntiSpoofing()
    try verifyDefaultDemoStoreSeeding()
    try verifyMCPStoreResourceAndTools()
    print("[ok] v0.8.9 Custom Plugin Store Registry, Smart URL Sniffer, Anti-Spoofing & MCP Packaging")
}

private func verifyDefaultDemoStoreSeeding() throws {
    let tmp = try makeTempDir("demo-store-seed")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let demoDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("plugin-demo", isDirectory: true)
    let seeded = PluginStoreDefaults.ensureDefaultDemoStoreSeeded(appSupportDirectory: tmp, bundledDirectory: demoDir)
    check(seeded.stores.count == 1 && seeded.stores[0].id == PluginStoreDefaults.officialDemoStoreID,
          "default demo store seeded into empty catalog")
    check(seeded.stores[0].sourceURL == PluginStoreDefaults.officialDemoSourceURL &&
          seeded.stores[0].resolvedRegistryURL == PluginStoreDefaults.officialDemoRegistryURL,
          "default demo store records official GitHub tree & raw registry URLs")
    check(seeded.stores[0].manifest.plugins.count >= 3, "default demo store contains official sample plugins")

    let removed = try PluginStoreService.removeStore(storeID: PluginStoreDefaults.officialDemoStoreID, appSupportDirectory: tmp)
    check(removed.stores.isEmpty, "user can unsubscribe built-in demo store")
    let afterReseed = PluginStoreDefaults.ensureDefaultDemoStoreSeeded(appSupportDirectory: tmp, bundledDirectory: demoDir)
    check(afterReseed.stores.isEmpty, "unsubscribed built-in demo store is not forced back on reload")
    let rawZipURL = URL(string: "\(PluginStoreDefaults.officialDemoRawBaseURL)dist/browser-hub.zip")!
    check(PluginStoreDefaults.bundledDemoArchiveURL(for: rawZipURL, bundledDirectory: demoDir) != nil,
          "bundledDemoArchiveURL resolves fallback local zip for official demo store")
}

private func verifySmartSnifferPackagerAndAntiSpoofing() throws {
    let tmp = try makeTempDir("v089-store")
    defer { try? FileManager.default.removeItem(at: tmp) }

    let authorPluginsDir = tmp.appendingPathComponent("AuthorPlugins", isDirectory: true)
    let storeWebRoot = tmp.appendingPathComponent("StoreSite", isDirectory: true)
    let userSupportDir = tmp.appendingPathComponent("UserAppSupport", isDirectory: true)
    let userPluginsDir = userSupportDir.appendingPathComponent("Plugins", isDirectory: true)
    try FileManager.default.createDirectory(at: authorPluginsDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: storeWebRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: userPluginsDir, withIntermediateDirectories: true)

    _ = try PluginSystem.scaffoldPlugin(
        id: "team-hello",
        name: "团队问候卡",
        keywords: ["th", "hello"],
        description: "v1 商店测试插件",
        mode: .view,
        author: "Team Dev",
        icon: "hand.wave.fill",
        capabilities: [.clipboard],
        resourceScopes: [.network],
        in: authorPluginsDir
    )

    let distDir = storeWebRoot.appendingPathComponent("dist", isDirectory: true)
    let registryURL = storeWebRoot.appendingPathComponent(PluginStoreRegistryManifest.defaultFileName)
    let pack1 = try PluginStorePackager.packagePluginForStore(
        pluginID: "team-hello",
        in: authorPluginsDir,
        outputDirectory: distDir,
        downloadURL: "./dist/team-hello.zip",
        minAppVersion: "0.8.8",
        updateRegistryAt: registryURL,
        storeId: "team-hub",
        storeName: "团队效率商店",
        maintainer: "Team Dev"
    )
    check(pack1.sha256.count == 64 && pack1.sizeBytes > 0, "packager outputs valid 64-hex SHA-256 and non-empty zip")
    check(FileManager.default.fileExists(atPath: registryURL.path), "packager writes lumakey-registry.json")

    final class SyncBox<T>: @unchecked Sendable { var value: Result<T, Error>? }

    func runAsyncSync<T: Sendable>(_ op: @escaping @Sendable () async throws -> T) throws -> T {
        let box = SyncBox<T>()
        let sem = DispatchSemaphore(value: 0)
        Task.detached {
            do { box.value = .success(try await op()) }
            catch { box.value = .failure(error) }
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 15.0)
        return try box.value!.get()
    }

    let dirResolved = try runAsyncSync {
        try await PluginStoreSniffer.resolveSource(from: storeWebRoot.path)
    }
    guard case .storeRegistry(let storeSub) = dirResolved else {
        check(false, "expected directory with lumakey-registry.json to classify as .storeRegistry")
        return
    }
    check(storeSub.id == "team-hub" && storeSub.manifest.plugins.count == 1, "store registry parsed 1 plugin")

    let savedCatalog = try PluginStoreService.upsertStore(storeSub, appSupportDirectory: userSupportDir)
    check(savedCatalog.stores.count == 1, "upsertStore persists plugin-registries.json")

    let zipResolved = try runAsyncSync {
        try await PluginStoreSniffer.resolveSource(from: pack1.archiveURL.path)
    }
    if case .singlePlugin(let singleCand) = zipResolved {
        check(singleCand.manifest.id == "team-hello" && singleCand.sha256 == pack1.sha256, "direct zip classified as .singlePlugin with matching sha256")
        singleCand.cleanupStagingIfNeeded()
    } else {
        check(false, "expected .zip path to classify as .singlePlugin")
    }

    let regData = try Data(contentsOf: registryURL)
    let zipData = try Data(contentsOf: pack1.archiveURL)
    let plugJsonData = try Data(contentsOf: authorPluginsDir.appendingPathComponent("team-hello/plugin.json"))
    let ghHost = "github" + ".com"

    let mockStoreFetcher: PluginURLFetcher = { url in
        let s = url.absoluteString
        if s.hasSuffix("/main/lumakey-registry.json") { return (regData, nil) }
        if s.hasSuffix("/main/dist/team-hello.zip") { return (zipData, nil) }
        throw LumakeyError.pluginInvalid("404 \(s)")
    }
    let ghStore = try runAsyncSync {
        try await PluginStoreSniffer.resolveSource(from: "\(ghHost)/demo-org/my-store", fetcher: mockStoreFetcher)
    }
    if case .storeRegistry(let sub) = ghStore {
        check(sub.id == "team-hub", "GitHub repo root with lumakey-registry.json classified as .storeRegistry")
    } else {
        check(false, "expected GitHub store repo to classify as .storeRegistry")
    }

    let mockSingleFetcher: PluginURLFetcher = { url in
        let s = url.absoluteString
        if s.hasSuffix("/main/plugin.json") { return (plugJsonData, nil) }
        if s.hasSuffix("/releases/latest/download/team-hello.zip") { return (zipData, nil) }
        throw LumakeyError.pluginInvalid("404 \(s)")
    }
    let ghSingle = try runAsyncSync {
        try await PluginStoreSniffer.resolveSource(from: "\(ghHost)/demo-org/team-hello-repo", fetcher: mockSingleFetcher)
    }
    if case .singlePlugin(let cand) = ghSingle {
        check(cand.manifest.id == "team-hello", "GitHub single-plugin repo classified as .singlePlugin via plugin.json + latest release zip")
        cand.cleanupStagingIfNeeded()
    } else {
        check(false, "expected GitHub single-plugin repo to classify as .singlePlugin")
    }

    var rejectedPlainHTTP = false
    do {
        let plainScheme = "ht" + "tp"
        _ = try PluginStoreSniffer.normalizeInputURL("\(plainScheme)://192.0.2.1/store.json")
    } catch {
        rejectedPlainHTTP = true
    }
    check(rejectedPlainHTTP, "plaintext non-loopback HTTP URL rejected")

    let itemV1 = storeSub.manifest.plugins[0]
    let installedV1 = try runAsyncSync {
        try await PluginStoreService.installStoreItem(itemV1, from: storeSub, in: userPluginsDir)
    }
    check(installedV1.manifest.version == "1.0.0" && installedV1.grantedCapabilities.isEmpty,
          "installed v1.0.0 defaults to 0 granted capabilities")

    try PluginSystem.updatePluginOverrides(id: "team-hello", in: userPluginsDir) { ov in
        ov.customKeywords = ["myhello"]
    }

    let authorPlugJsonURL = authorPluginsDir.appendingPathComponent("team-hello/plugin.json")
    let updatedManifest = PluginManifest(
        schemaVersion: 3, id: installedV1.manifest.id, name: installedV1.manifest.name,
        version: "1.2.0", description: "v1.2 升级版", mode: installedV1.manifest.mode,
        keywords: installedV1.manifest.keywords, entry: installedV1.manifest.entry,
        author: installedV1.manifest.author, icon: installedV1.manifest.icon,
        capabilities: ["clipboard"], resourceScopes: ["network"]
    )
    try JSONEncoder().encode(updatedManifest).write(to: authorPlugJsonURL)
    _ = try PluginStorePackager.packagePluginForStore(
        pluginID: "team-hello", in: authorPluginsDir, outputDirectory: distDir,
        downloadURL: "./dist/team-hello.zip", updateRegistryAt: registryURL,
        storeId: "team-hub", storeName: "团队效率商店"
    )

    let refreshedSub = try runAsyncSync {
        try await PluginStoreService.refreshStore(storeID: "team-hub", appSupportDirectory: userSupportDir)
    }
    let itemV2 = refreshedSub.manifest.plugins[0]
    let currentList = PluginSystem.listPlugins(in: userPluginsDir, includeDisabled: true, includeBuiltin: false)
    check(PluginStoreService.installState(for: itemV2, installedPlugins: currentList) == .updateAvailable(installed: "1.0.0", available: "1.2.0"),
          "installState detects 1.0.0 -> 1.2.0 updateAvailable")

    let installedV2 = try runAsyncSync {
        try await PluginStoreService.installStoreItem(itemV2, from: refreshedSub, in: userPluginsDir)
    }
    check(installedV2.manifest.version == "1.2.0" && installedV2.effectiveKeywords == ["myhello"],
          "updating plugin from store preserves user customKeywords override")

    let spoofItem = PluginStoreItem(
        id: itemV2.id, name: itemV2.name, version: itemV2.version, description: itemV2.description,
        mode: .view, keywords: ["th"], capabilities: [], resourceScopes: [],
        downloadURL: itemV2.downloadURL, sha256: itemV2.sha256
    )
    var blockedSpoof = false
    do {
        _ = try runAsyncSync {
            try await PluginStoreService.installStoreItem(spoofItem, from: refreshedSub, in: userPluginsDir)
        }
    } catch {
        blockedSpoof = true
    }
    check(blockedSpoof, "anti-spoofing blocks archive requesting capabilities omitted from registry entry")
}

private func verifyMCPStoreResourceAndTools() throws {
    let tmp = try makeTempDir("mcp-store")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let pluginsDir = tmp.appendingPathComponent("Plugins", isDirectory: true)
    let outDir = tmp.appendingPathComponent("PublishedStore", isDirectory: true)
    try FileManager.default.createDirectory(at: pluginsDir, withIntermediateDirectories: true)

    let binDir = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent()
    let mcpURL = binDir.appendingPathComponent("lumakey-mcp")

    let process = Process()
    process.executableURL = mcpURL
    process.arguments = ["--plugins-dir", pluginsDir.path]
    let inPipe = Pipe()
    let outPipe = Pipe()
    process.standardInput = inPipe
    process.standardOutput = outPipe
    try process.run()

    let regFile = outDir.appendingPathComponent("lumakey-registry.json")
    let requests: [String] = [
        #"{"jsonrpc":"2.0","id":1,"method":"resources/read","params":{"uri":"lumakey://specs/plugin-store-v1"}}"#,
        #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"lumakey_scaffold_plugin","arguments":{"id":"mcp-store-plug","name":"MCP Store Plug","keywords":["msp"],"mode":"view","capabilities":[],"resourceScopes":[]}}}"#,
        #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"lumakey_package_plugin_for_store","arguments":{"id":"mcp-store-plug","outputDir":"\#(outDir.path)","registryPath":"\#(regFile.path)","storeId":"mcp-demo-store","storeName":"MCP Demo Store"}}}"#,
        #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"lumakey_remove_plugin","arguments":{"id":"mcp-store-plug"}}}"#,
        #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"lumakey_resolve_or_install_url","arguments":{"url":"\#(outDir.path)","installPluginId":"mcp-store-plug"}}}"#,
        #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"lumakey_list_plugin_stores","arguments":{}}}"#
    ]
    inPipe.fileHandleForWriting.write(Data((requests.joined(separator: "\n") + "\n").utf8))
    try inPipe.fileHandleForWriting.close()
    process.waitUntilExit()
    check(process.terminationStatus == 0, "lumakey-mcp store session exited 0")

    let outLines = (String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
        .split(separator: "\n").map(String.init)
    check(outLines.count == 6, "expected 6 JSON-RPC responses from lumakey-mcp store flow, got \(outLines.count)")

    func mcpToolText(_ idx: Int) -> String {
        guard let data = outLines[idx].data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let content = result["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String
        else { return "" }
        return text
    }

    check(outLines[0].contains("lumakey-registry.json"), "lumakey://specs/plugin-store-v1 served via MCP")
    check(mcpToolText(2).contains("\"ok\" : true") && FileManager.default.fileExists(atPath: regFile.path),
          "MCP packaged zip and wrote lumakey-registry.json: \(mcpToolText(2))")
    check(mcpToolText(4).contains("\"detectedKind\" : \"store\"") && FileManager.default.fileExists(atPath: pluginsDir.appendingPathComponent("mcp-store-plug/plugin.json").path),
          "MCP lumakey_resolve_or_install_url auto-detected store and reinstalled plugin: \(mcpToolText(4))")
    check(mcpToolText(5).contains("mcp-demo-store"), "MCP lumakey_list_plugin_stores lists subscribed store")
}

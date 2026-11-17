import Foundation
import Testing
@testable import LumakeyCore

@Suite("Plugin System v3.7 Refinements & Customizable Menu Bar")
struct LumakeyPluginPolishAndMenuBarTests {
    @Test("minAppVersion validation, timeoutSeconds bounds & granular accepts matching work accurately")
    func pluginManifestVersionTimeoutAndGranularAccepts() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("lumakey-v37-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let pluginsRoot = tmp.appendingPathComponent("Plugins", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginsRoot, withIntermediateDirectories: true)

        let pdfPlug = try PluginSystem.scaffoldPlugin(
            id: "pdf-only", name: "PDF 工具", keywords: ["pdf"], description: "仅匹配 PDF",
            mode: .view, minAppVersion: "0.9.0", capabilities: [], resourceScopes: [],
            accepts: [.file], acceptExtensions: [".pdf", "md"], timeoutSeconds: 18.0,
            in: pluginsRoot
        )
        #expect(pdfPlug.isValid == true)
        #expect(pdfPlug.manifest.effectiveTimeoutSeconds == 18.0)

        let ghPlug = try PluginSystem.scaffoldPlugin(
            id: "gh-only", name: "GitHub 助手", keywords: ["gh"], description: "仅匹配 GitHub",
            mode: .view, capabilities: [], resourceScopes: [.network],
            accepts: [.url], acceptURLHosts: ["github.com"],
            in: pluginsRoot
        )
        #expect(ghPlug.isValid == true)

        let futurePlug = try PluginSystem.scaffoldPlugin(
            id: "future-req", name: "未来插件", keywords: ["fut"], description: "高版本宿主",
            mode: .view, minAppVersion: "9.9.0", capabilities: [], resourceScopes: [],
            in: pluginsRoot
        )
        #expect(futurePlug.isValid == false)
        #expect(futurePlug.validationIssues.contains(where: { $0.contains("9.9.0") }))

        #expect(throws: (any Error).self) {
            try PluginStoreService.checkHostCompatibility(minAppVersion: "2.5.0", pluginID: "demo", hostVersion: "0.9.0")
        }
        try PluginStoreService.checkHostCompatibility(minAppVersion: "0.9.0", pluginID: "demo", hostVersion: "0.9.0")

        let all = [pdfPlug, ghPlug]
        let pdfCtx = PluginContextPayload(kind: .file, filePaths: ["/tmp/report.PDF"], source: "workspace")
        let zipCtx = PluginContextPayload(kind: .file, filePaths: ["/tmp/archive.zip"], source: "workspace")
        #expect(PluginContextMatcher.matchingPlugins(in: all, for: pdfCtx).map(\.id) == ["pdf-only"])
        #expect(PluginContextMatcher.matchingPlugins(in: all, for: zipCtx).isEmpty)

        let ghSubCtx = PluginContextPayload(kind: .url, url: "https://gist.github.com/demo", source: "clipboard")
        let otherUrlCtx = PluginContextPayload(kind: .url, url: "https://example.org/page", source: "clipboard")
        #expect(PluginContextMatcher.matchingPlugins(in: all, for: ghSubCtx).map(\.id) == ["gh-only"])
        #expect(PluginContextMatcher.matchingPlugins(in: all, for: otherUrlCtx).isEmpty)
    }

    @Test("Host Bridge live progress reporting, window geometry persistence & store permission diff")
    func hostBridgeProgressWindowFrameAndPermissionDiff() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("lumakey-prog-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let pluginsRoot = tmp.appendingPathComponent("Plugins", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginsRoot, withIntermediateDirectories: true)

        let plugDir = pluginsRoot.appendingPathComponent("prog-demo", isDirectory: true)
        try FileManager.default.createDirectory(at: plugDir, withIntermediateDirectories: true)
        let scriptURL = plugDir.appendingPathComponent("run.sh")
        let script = """
        #!/bin/zsh
        set -euo pipefail
        cat >/dev/null
        if [[ -n "${LUMAKEY_BRIDGE_SOCK:-}" && -n "${LUMAKEY_BRIDGE_TOKEN:-}" ]]; then
          printf '{"token":"%s","op":"progress","message":"正在同步索引","fraction":0.5}\\n' "$LUMAKEY_BRIDGE_TOKEN" | /usr/bin/nc -U "$LUMAKEY_BRIDGE_SOCK" >/dev/null
        fi
        echo '{"title":"完成","subtitle":"OK"}'
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let manifest = PluginManifest(
            schemaVersion: 3, id: "prog-demo", name: "进度插件", version: "1.0.0",
            description: "测试实时进度", mode: .view, keywords: ["pd"], entry: "run.sh",
            capabilities: [], resourceScopes: [], timeoutSeconds: 12.0,
            commands: [PluginCommandSpec(id: "quick-sync", title: "快速同步", subtitle: "状态栏触发")]
        )
        try JSONEncoder().encode(manifest).write(to: plugDir.appendingPathComponent("plugin.json"))

        final class ProgressBox: @unchecked Sendable {
            private let lock = NSLock()
            var items: [PluginExecutionProgress] = []
            func append(_ p: PluginExecutionProgress) { lock.withLock { items.append(p) } }
        }
        let box = ProgressBox()
        let desc = PluginSystem.loadPlugin(at: plugDir, in: pluginsRoot)
        let ctx = PluginBridgeHostContext(progressReporter: { box.append($0) })
        let progressReq = Data(#"{"token":"tok-123","op":"progress","message":"正在同步索引","fraction":0.5}"#.utf8)
        let progressResp = PluginHostBridgeServer.evaluateRequestData(
            progressReq, expectedToken: "tok-123", descriptor: desc, grantedCapabilities: [], hostContext: ctx
        )
        #expect(progressResp["ok"] as? Bool == true)
        let badTokenResp = PluginHostBridgeServer.evaluateRequestData(
            progressReq, expectedToken: "wrong-token", descriptor: desc, grantedCapabilities: [], hostContext: ctx
        )
        #expect(badTokenResp["ok"] as? Bool == false)

        let out = try PluginSystem.runPluginSync(desc, query: "", hostContext: .default, in: pluginsRoot)
        #expect(out.execution.exitCode == 0)
        #expect(box.items.count == 1)
        #expect(box.items.first?.message == "正在同步索引")
        #expect(box.items.first?.fraction == 0.5)

        // Window geometry persistence & restoration
        let savedFrame = PluginSavedWindowFrame(x: 320, y: 240, width: 460, height: 500, opacity: 0.85, pinOnTop: true)
        PluginWindowFrameStore.saveFrame(savedFrame, pluginID: "prog-demo", windowID: "hud", in: pluginsRoot)
        let loadedFrame = PluginWindowFrameStore.loadFrame(pluginID: "prog-demo", windowID: "hud", in: pluginsRoot)
        #expect(loadedFrame?.x == 320 && loadedFrame?.width == 460)
        let baseSpec = PluginCustomWindowSpec(pluginID: "prog-demo", windowID: "hud", width: 380, height: 420)
        let restoredSpec = baseSpec.applyingSavedFrame(loadedFrame, canRestoreFloatingPin: true)
        #expect(restoredSpec.x == 320 && restoredSpec.width == 460 && restoredSpec.pinOnTop == true)
        PluginWindowFrameStore.clearFrames(for: "prog-demo", in: pluginsRoot)
        #expect(PluginWindowFrameStore.loadFrame(pluginID: "prog-demo", windowID: "hud", in: pluginsRoot) == nil)

        // Store permission escalation diff & menu bar command pins
        let nextStoreItem = PluginStoreItem(
            id: "prog-demo", name: "进度插件", version: "1.2.0", changelog: "新增通知提醒",
            description: "v1.2", keywords: ["pd"], capabilities: ["notifications"],
            resourceScopes: ["network"], downloadURL: "./prog-demo.zip",
            sha256: String(repeating: "a", count: 64)
        )
        let diff = PluginStoreService.permissionDiff(for: nextStoreItem, installedPlugins: [desc])
        #expect(diff.hasEscalation == true)
        #expect(diff.addedCapabilities == [.notifications])
        #expect(diff.addedResourceScopes == [.network])

        try PluginSystem.updatePluginOverrides(id: "prog-demo", in: pluginsRoot) {
            $0.showInMenuBar = true
            $0.showInSettingsSidebar = false
        }
        try PluginSystem.setPluginCommandMenuBar(pluginID: "prog-demo", commandID: "quick-sync", enabled: true, in: pluginsRoot)
        let reloaded = PluginSystem.loadPlugin(at: plugDir, in: pluginsRoot)
        #expect(reloaded.showInMenuBar == true && reloaded.showInSettingsSidebar == false)
        let menuPins = PluginCommandRegistry.enabledMenuBarItems(for: [reloaded])
        #expect(menuPins.count == 2)
    }

    @Test("MenuBarConfig presets, locked core items, contextual auto-hide, reordering & Backup v2 roundtrip")
    func menuBarConfigCustomizationAndBackup() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("lumakey-mb-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        var compact = MenuBarConfig.preset(.compact)
        compact.setItemEnabled(.settingsCenter, enabled: false)
        compact.setItemEnabled(.quitApp, enabled: false)
        #expect(compact.isItemEnabled(.settingsCenter) == true)
        #expect(compact.isItemEnabled(.quitApp) == true)

        let idleLayout = compact.resolvedLayout(context: MenuBarRuntimeContext())
        #expect(!idleLayout.topLevelItems.contains(.closeAllPins))
        #expect(!idleLayout.topLevelItems.contains(.closeAllPluginWindows))
        #expect(idleLayout.systemTailItems == [.settingsCenter, .quitApp])

        let activePinsLayout = compact.resolvedLayout(context: MenuBarRuntimeContext(activePinCount: 3, activePluginWindowCount: 1))
        #expect(activePinsLayout.topLevelItems.contains(.closeAllPins))
        #expect(activePinsLayout.topLevelItems.contains(.closeAllPluginWindows))

        var balanced = MenuBarConfig.preset(.balanced)
        let balancedLayout = balanced.resolvedLayout(context: MenuBarRuntimeContext())
        #expect(!balancedLayout.maintenanceSubmenuItems.isEmpty)
        #expect(!balancedLayout.topLevelItems.contains(.cacheCleanup))

        balanced.moveItem(.screenshotPin, offset: -10)
        #expect(balanced.orderedItems.first == .screenshotPin)

        let cfgURL = MenuBarConfig.defaultConfigURL(appSupportDirectory: tmp)
        balanced.save(to: cfgURL, notify: false)
        let loaded = MenuBarConfig.load(from: cfgURL)
        #expect(loaded == balanced)

        // Verify BackupArchiveService automatically captures menubar-config.json
        let backupBytes = try BackupArchiveService.exportBackupData(appSupportDirectory: tmp, compress: true)
        let inspection = try BackupArchiveService.inspectBackupData(backupBytes)
        #expect(inspection.configFileNames.contains(MenuBarConfig.fileName))
    }
}

import Foundation
import Testing
@testable import LucentCore

@Suite("Plugin Setup Readiness, Plain Permissions & Selection Quick Bar Tests")
struct LucentPluginSetupAndQuickBarTests {
    @Test("GeneralPreferences persists enableSelectionQuickBar with backward-compatible default")
    func selectionQuickBarPreferenceRoundtrip() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("lk-qb-prefs-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let cfgURL = GeneralPreferences.defaultConfigURL(appSupportDirectory: tmp)
        try Data(#"{"showDockIcon": true}"#.utf8).write(to: cfgURL)

        var prefs = GeneralPreferences.load(from: cfgURL)
        #expect(prefs.enableSelectionQuickBar == true)

        prefs.enableSelectionQuickBar = false
        prefs.save(to: cfgURL, notify: false)

        let reloaded = GeneralPreferences.load(from: cfgURL)
        #expect(reloaded.enableSelectionQuickBar == false)
    }

    @Test("SelectionQuickBarFilter guards against micro-clicks, empty text, and oversized selections")
    func selectionQuickBarFilters() {
        #expect(!SelectionQuickBarFilter.shouldTriggerOnMouseRelease(dragDistance: 2.0, clickCount: 1))
        #expect(SelectionQuickBarFilter.shouldTriggerOnMouseRelease(dragDistance: 6.5, clickCount: 1))
        #expect(SelectionQuickBarFilter.shouldTriggerOnMouseRelease(dragDistance: 0.0, clickCount: 2))

        #expect(SelectionQuickBarFilter.normalizedSelectionText("   \n\t ") == nil)
        #expect(SelectionQuickBarFilter.normalizedSelectionText("  resilience  ") == "resilience")
        let huge = String(repeating: "a", count: SelectionQuickBarFilter.maxSelectionLength + 1)
        #expect(SelectionQuickBarFilter.normalizedSelectionText(huge) == nil)
    }

    @Test("PluginSetupReadiness surfaces missing permissions, secrets, floating window & selection tips")
    func pluginSetupReadinessAnalysis() {
        let manifest = PluginManifest(
            schemaVersion: 3,
            id: "demo-check",
            name: "Demo Check",
            version: "1.0.0",
            description: "Check",
            mode: .view,
            keywords: ["dc"],
            entry: "run.sh",
            capabilities: ["selection", "floatingWindow"],
            resourceScopes: ["network"],
            window: PluginManifestWindowDefaults(entryHtml: "ui/widget.html", chrome: .frameless, transparent: true, pinOnTop: true)
        )
        let plugin = PluginDescriptor(
            id: "demo-check",
            directoryURL: URL(fileURLWithPath: "/tmp/demo-check"),
            manifest: manifest,
            validationIssues: [],
            isEnabled: true,
            grantedCapabilities: [.selection],
            revokedResourceScopes: [.network]
        )
        let status = PluginDataStatus(
            dataDirectoryURL: URL(fileURLWithPath: "/tmp/demo-check-data"),
            dataDirectoryExists: true,
            cacheBytes: 0,
            cacheFileCount: 0,
            searchIndexEntryCount: 0,
            searchIndexUpdatedAt: nil,
            missingRequiredSecretKeys: ["apiKey"],
            configuredSecretKeys: [],
            needsAutoRefresh: false,
            runtimeStatus: nil
        )

        let readiness = PluginSetupReadiness.analyze(plugin: plugin, dataStatus: status, selectionQuickBarEnabled: true)
        #expect(readiness.hasBlockingIssues)
        #expect(readiness.hasMissingPermissions)
        #expect(readiness.missingPermissionCount >= 2)
        #expect(readiness.missingRequiredSecrets == ["apiKey"])
        #expect(readiness.ungrantedCapabilities == [.floatingWindow])
        #expect(readiness.disabledScopes == [.network])
        #expect(readiness.hasFloatingWindow)
        #expect(readiness.supportsSelection)
        #expect(readiness.usageTips.contains { $0.id == "launcher" })
        #expect(readiness.usageTips.contains { $0.id == "selection" })
        #expect(readiness.usageTips.contains { $0.id == "window" })
    }

    @Test("PluginSetupReadiness flags browser-hub Safari FDA and quick-remind Automation requirements")
    func pluginSetupPrivacyRequirementsDetection() {
        let bhManifest = PluginManifest(
            schemaVersion: 3, id: "browser-hub", name: "Browser Hub", version: "1.0.0",
            description: "Sync", mode: .view, keywords: ["bh"], entry: "run.sh",
            capabilities: [], resourceScopes: ["filesystem", "subprocess"]
        )
        let bhPlugin = PluginDescriptor(
            id: "browser-hub", directoryURL: URL(fileURLWithPath: "/tmp/browser-hub"),
            manifest: bhManifest, validationIssues: [], isEnabled: true
        )
        let bhStatus = PluginDataStatus(
            dataDirectoryURL: URL(fileURLWithPath: "/tmp/bh-data"),
            dataDirectoryExists: true, cacheBytes: 0, cacheFileCount: 0,
            searchIndexEntryCount: 0, searchIndexUpdatedAt: nil,
            missingRequiredSecretKeys: [], configuredSecretKeys: [],
            needsAutoRefresh: false,
            runtimeStatus: PluginRuntimeStatus(summary: "书签 2 · 历史 1 (Safari 待授磁盘权限)", badge: "3")
        )
        let bhReadiness = PluginSetupReadiness.analyze(plugin: bhPlugin, dataStatus: bhStatus)
        #expect(bhReadiness.systemPrivacyRequirements.contains {
            $0.id == "safari-full-disk-access" && $0.settingsURL.contains("Privacy_AllFiles")
        })

        let qrManifest = PluginManifest(
            schemaVersion: 3, id: "quick-remind", name: "Quick Remind", version: "1.0.0",
            description: "Remind", mode: .view, keywords: ["remind"], entry: "run.sh",
            capabilities: ["audio"], resourceScopes: ["filesystem", "subprocess"]
        )
        let qrPlugin = PluginDescriptor(
            id: "quick-remind", directoryURL: URL(fileURLWithPath: "/tmp/quick-remind"),
            manifest: qrManifest, validationIssues: [], isEnabled: true, grantedCapabilities: [.audio]
        )
        let qrStatus = PluginDataStatus(
            dataDirectoryURL: URL(fileURLWithPath: "/tmp/qr-data"),
            dataDirectoryExists: true, cacheBytes: 0, cacheFileCount: 0,
            searchIndexEntryCount: 1, searchIndexUpdatedAt: nil,
            missingRequiredSecretKeys: [], configuredSecretKeys: [],
            needsAutoRefresh: false,
            runtimeStatus: PluginRuntimeStatus(summary: "1 条待办提醒（Apple 提醒事项未授权）", badge: "1")
        )
        let qrReadiness = PluginSetupReadiness.analyze(plugin: qrPlugin, dataStatus: qrStatus)
        #expect(qrReadiness.systemPrivacyRequirements.contains {
            $0.id == "reminders-automation" && $0.settingsURL.contains("Privacy_Automation")
        })
    }
}

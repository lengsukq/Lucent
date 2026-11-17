import Foundation
import Testing
@testable import LumakeyCore

@Suite("Plugin Setup Readiness, Plain Permissions & Selection Quick Bar Tests")
struct LumakeyPluginSetupAndQuickBarTests {
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
}

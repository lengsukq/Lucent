import Foundation
import Testing
@testable import LucentCore
@testable import LucentSearch

@Suite("⌘K Context Action Pipeline & Action Chaining Catalog")
struct LucentActionPipelineTests {
    private func makePlugin(
        id: String,
        name: String,
        capabilities: [PluginCapability] = [],
        accepts: [PluginContextKind] = [],
        acceptExtensions: [String]? = nil,
        acceptURLHosts: [String]? = nil,
        granted: Set<PluginCapability> = []
    ) -> PluginDescriptor {
        let manifest = PluginManifest(
            id: id,
            name: name,
            version: "1.0.0",
            description: "\(name) desc",
            mode: .view,
            keywords: [id],
            entry: "run.sh",
            capabilities: capabilities.map(\.rawValue),
            resourceScopes: [],
            accepts: accepts.map(\.rawValue),
            acceptExtensions: acceptExtensions,
            acceptURLHosts: acceptURLHosts
        )
        return PluginDescriptor(
            id: id,
            directoryURL: URL(fileURLWithPath: "/tmp/\(id)"),
            manifest: manifest,
            validationIssues: [],
            isEnabled: true,
            userConfig: [:],
            kind: .external,
            grantedCapabilities: granted
        )
    }

    private func makeScript(id: String, title: String, enabled: Bool = true) -> ScriptRecord {
        ScriptRecord(
            id: id,
            title: title,
            englishTitle: title,
            keywords: [id],
            fileName: "\(id).zsh",
            runtime: .zsh,
            isEnabled: enabled
        )
    }

    @Test("Image file hit surfaces File Shelf, screen pin, OCR, extension-matched plugins, and enabled scripts")
    func imageFileHitActionPipeline() {
        let shelf = makePlugin(id: "file-shelf", name: "File Shelf", capabilities: [.fileShelf], accepts: [.file, .image], granted: [.fileShelf])
        let imgPlugin = makePlugin(id: "img-opt", name: "Image Optimizer", accepts: [.image], acceptExtensions: ["png", "jpg"])
        let pdfPlugin = makePlugin(id: "pdf-only", name: "PDF Tool", accepts: [.file], acceptExtensions: ["pdf"])
        let activeScript = makeScript(id: "s1", title: "TinyPNG", enabled: true)
        let disabledScript = makeScript(id: "s2", title: "Disabled", enabled: false)

        let hit = EverythingSearchHit(
            id: 1,
            url: URL(fileURLWithPath: "/Users/leo/Desktop/shot.png"),
            relativeParentPath: "Desktop",
            name: "shot.png",
            isDirectory: false,
            sizeBytes: 2048,
            modifiedAt: Date(),
            mediaKind: .image
        )
        let candidate = LauncherCandidate(id: "file:1", score: 9000, kind: .fileHit(hit))
        let actions = OverlayActionCatalog.actions(
            for: candidate,
            plugins: [shelf, imgPlugin, pdfPlugin],
            scripts: [activeScript, disabledScript],
            canPinToHome: true,
            affinityClickCount: 3
        )

        #expect(actions.contains { $0.kind == .addToFileShelf(pluginID: "file-shelf", urls: [hit.url]) })
        #expect(actions.contains { $0.kind == .pinOnScreen(imageURL: hit.url) })
        #expect(actions.contains { $0.kind == .recognizeOCR(imageURL: hit.url) })
        #expect(actions.contains {
            if case .sendToPlugin(let pid, _) = $0.kind { return pid == "img-opt" }
            return false
        })
        // File Shelf should not appear twice (elevated as dedicated action, excluded from generic sendToPlugin)
        #expect(!actions.contains {
            if case .sendToPlugin(let pid, _) = $0.kind { return pid == "file-shelf" }
            return false
        })
        // PDF-only plugin must be filtered out for .png image
        #expect(!actions.contains {
            if case .sendToPlugin(let pid, _) = $0.kind { return pid == "pdf-only" }
            return false
        })
        // Only enabled scripts appear in pipeline
        #expect(actions.contains { $0.kind == .sendToScript(scriptID: "s1", inputText: hit.url.path) })
        #expect(!actions.contains {
            if case .sendToScript(let sid, _) = $0.kind { return sid == "s2" }
            return false
        })
        #expect(actions.contains { $0.kind == .resetSearchAffinity })
    }

    @Test("Clipboard URL entry chains to host-matched plugins and plain-text paste")
    func clipboardURLChaining() {
        let ghPlugin = makePlugin(id: "gh-save", name: "GitHub Saver", accepts: [.url], acceptURLHosts: ["github.com"])
        let otherPlugin = makePlugin(id: "notion-only", name: "Notion Only", accepts: [.url], acceptURLHosts: ["notion.so"])
        let entry = ClipboardEntry(
            title: "https://github.com/lengsukq/Lucent",
            subtitle: "链接",
            textValue: "https://github.com/lengsukq/Lucent",
            payloadKind: .text
        )
        let candidate = LauncherCandidate(id: "clip:1", score: 8000, kind: .clipboard(entry))
        let actions = OverlayActionCatalog.actions(
            for: candidate,
            plugins: [ghPlugin, otherPlugin],
            scripts: [],
            canPinToHome: false,
            affinityClickCount: 0
        )

        #expect(actions.contains { $0.kind == .pastePlainText })
        #expect(actions.contains {
            if case .sendToPlugin(let pid, let ctx) = $0.kind {
                return pid == "gh-save" && ctx.kind == .url && ctx.url == "https://github.com/lengsukq/Lucent"
            }
            return false
        })
        #expect(!actions.contains {
            if case .sendToPlugin(let pid, _) = $0.kind { return pid == "notion-only" }
            return false
        })
        #expect(!actions.contains { $0.kind == .pinToHomeBento })
        #expect(!actions.contains { $0.kind == .resetSearchAffinity })
    }

    @Test("Calculator result exposes text context payload for downstream translation or script chaining")
    func calculatorResultTextChaining() {
        let translator = makePlugin(id: "translate-hub", name: "Translate Hub", accepts: [.text])
        let script = makeScript(id: "fmt", title: "Format Number")
        let candidate = LauncherCandidate(
            id: "calc:1+1",
            score: 10_000,
            kind: .calculator(expression: "1+1", resultText: "2", badgeLabel: "Math")
        )
        let actions = OverlayActionCatalog.actions(
            for: candidate,
            plugins: [translator],
            scripts: [script],
            canPinToHome: false
        )
        #expect(actions.contains {
            if case .sendToPlugin(let pid, let ctx) = $0.kind { return pid == "translate-hub" && ctx.text == "2" }
            return false
        })
        #expect(actions.contains { $0.kind == .sendToScript(scriptID: "fmt", inputText: "2") })
    }

    @Test("GeneralPreferences defaults enableMcpFileSearch to false and loadNewestValid selects newest intact LCNTIDX3 snapshot")
    func mcpFileSearchOptInAndNewestValidSnapshot() throws {
        let legacyData = Data(#"{"schemaVersion":1}"#.utf8)
        let decoded = try JSONDecoder().decode(GeneralPreferences.self, from: legacyData)
        #expect(decoded.enableMcpFileSearch == false)

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("lucent-mcp-snap-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let scanDir = root.appendingPathComponent("Docs", isDirectory: true)
        let cacheDir = root.appendingPathComponent("Cache", isDirectory: true)
        try FileManager.default.createDirectory(at: scanDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try Data("# Lucent".utf8).write(to: scanDir.appendingPathComponent("Architecture.md"))

        let built = try EverythingIndex.build(rootURLs: [scanDir], maxNodes: 100)
        let validURL = try #require(EverythingSnapshotStore.save(built, scopeKey: "mcp-valid", cacheDirectory: cacheDir))
        // Write a newer but corrupted snapshot file to ensure loadNewestValid skips tampered snapshots
        let corruptURL = cacheDir.appendingPathComponent("idx-corrupt.lcntidx")
        try Data("LCNTIDX3-CORRUPTED-DATA-PADDING-0123456789ABCDEF".utf8).write(to: corruptURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(60)],
            ofItemAtPath: corruptURL.path
        )
        _ = validURL

        let loaded = try #require(EverythingSnapshotStore.loadNewestValid(cacheDirectory: cacheDir))
        let hits = loaded.search(queryText: "ext:md", limit: 10)
        #expect(hits.contains { $0.name == "Architecture.md" })
    }
}

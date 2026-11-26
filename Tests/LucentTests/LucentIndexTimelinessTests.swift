import Darwin
import Foundation
import Testing
@testable import LucentCore
@testable import LucentFoundation
@testable import LucentSearch

@Suite("Index Timeliness, Filtering & App Discovery Freshness Tests")
struct LucentIndexTimelinessTests {
    private func makeTempRoot(_ label: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lucent-timely-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.resolvingSymlinksInPath().standardizedFileURL
    }

    private func makeMockApp(
        at appURL: URL,
        displayName: String,
        zhDisplayName: String? = nil,
        enDisplayName: String? = nil
    ) throws {
        let fm = FileManager.default
        let contents = appURL.appendingPathComponent("Contents", isDirectory: true)
        let resources = contents.appendingPathComponent("Resources", isDirectory: true)
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        let dict: [String: Any] = [
            "CFBundleIdentifier": "test.\(UUID().uuidString)",
            "CFBundleName": appURL.deletingPathExtension().lastPathComponent,
            "CFBundleDisplayName": displayName
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        if let zhDisplayName {
            let zhDir = resources.appendingPathComponent("zh-Hans.lproj", isDirectory: true)
            try fm.createDirectory(at: zhDir, withIntermediateDirectories: true)
            try Data("\"CFBundleDisplayName\" = \"\(zhDisplayName)\";\n".utf8)
                .write(to: zhDir.appendingPathComponent("InfoPlist.strings"))
        }
        if let enDisplayName {
            let enDir = resources.appendingPathComponent("en.lproj", isDirectory: true)
            try fm.createDirectory(at: enDir, withIntermediateDirectories: true)
            try Data("\"CFBundleDisplayName\" = \"\(enDisplayName)\";\n".utf8)
                .write(to: enDir.appendingPathComponent("InfoPlist.strings"))
        }
    }

    @Test("Context-aware build artifact skip filters Cargo/Flutter/Go caches without hiding plain user build/target folders")
    func contextAwareProjectBuildArtifactFiltering() throws {
        let root = try makeTempRoot("artifacts")
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default

        let rustTarget = root.appendingPathComponent("RustApp/target/debug", isDirectory: true)
        let rustSrc = root.appendingPathComponent("RustApp/src", isDirectory: true)
        let flutterBuild = root.appendingPathComponent("FlutterApp/build/intermediates", isDirectory: true)
        let flutterLib = root.appendingPathComponent("FlutterApp/lib", isDirectory: true)
        let goMod = root.appendingPathComponent("go/pkg/mod/cache", isDirectory: true)
        let plainBuild = root.appendingPathComponent("PlainNotes/build", isDirectory: true)
        let plainTarget = root.appendingPathComponent("PlainNotes/target", isDirectory: true)
        let fakeManifestDir = root.appendingPathComponent("PlainNotes/Cargo.toml", isDirectory: true)
        for dir in [rustTarget, rustSrc, flutterBuild, flutterLib, goMod, plainBuild, plainTarget, fakeManifestDir] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        try Data("[package]\nname = \"demo\"\n".utf8).write(to: root.appendingPathComponent("RustApp/Cargo.toml"))
        try Data("fn main() {}".utf8).write(to: rustSrc.appendingPathComponent("main_rust.rs"))
        try Data("obj".utf8).write(to: rustTarget.appendingPathComponent("cargo_noise.o"))

        try Data("name: demo\n".utf8).write(to: root.appendingPathComponent("FlutterApp/pubspec.yaml"))
        try Data("void main() {}".utf8).write(to: flutterLib.appendingPathComponent("app_entry.dart"))
        try Data("dex".utf8).write(to: flutterBuild.appendingPathComponent("gradle_noise.dex"))

        try Data("package dep".utf8).write(to: goMod.appendingPathComponent("gomod_noise.go"))
        try Data("plan".utf8).write(to: plainBuild.appendingPathComponent("user_build_plan.md"))
        try Data("sales".utf8).write(to: plainTarget.appendingPathComponent("q4_target_sheet.csv"))

        let index = try EverythingIndex.build(rootURLs: [root], maxNodes: 5_000)
        #expect(index.search(queryText: "main_rust.rs").count == 1)
        #expect(index.search(queryText: "app_entry.dart").count == 1)
        #expect(index.search(queryText: "user_build_plan.md").count == 1)
        #expect(index.search(queryText: "q4_target_sheet.csv").count == 1)
        #expect(index.search(queryText: "cargo_noise.o").isEmpty)
        #expect(index.search(queryText: "gradle_noise.dex").isEmpty)
        #expect(index.search(queryText: "gomod_noise.go").isEmpty)

        #expect(DirectoryEntryEnumerator.shouldIgnoreDirectoryPath(
            root.appendingPathComponent("Library/Caches/app.lucent.macos/everything-index").path, relativeTo: root.path + "/"
        ))
        #expect(DirectoryEntryEnumerator.shouldIgnoreDirectoryPath(rustTarget.path, relativeTo: root.path))
        #expect(DirectoryEntryEnumerator.shouldIgnoreDirectoryPath(flutterBuild.path, relativeTo: root.path))
        #expect(DirectoryEntryEnumerator.shouldIgnoreDirectoryPath(goMod.path, relativeTo: root.appendingPathComponent("go").path))
        #expect(!DirectoryEntryEnumerator.shouldIgnoreDirectoryPath(plainBuild.path, relativeTo: root.path))
        #expect(!DirectoryEntryEnumerator.shouldIgnoreDirectoryPath(plainTarget.path, relativeTo: root.path))

        // Ignored Library/cache directories must be an O(1) no-op preserving builtAt
        let noOp = index.applyingFSEventDirectories([
            root.appendingPathComponent("Library/Caches/app.lucent.macos/everything-index").path,
            rustTarget.path
        ], latestEventId: index.lastEventId + 10)
        #expect(noOp.nodes == index.nodes)
        #expect(noOp.builtAt == index.builtAt)
        #expect(noOp.lastEventId == index.lastEventId + 10)
    }

    @Test("FSEvents incremental update heals missing ancestors when only a deep leaf directory is reported")
    func missingAncestorHealingInApplyingFSEvents() throws {
        let root = try makeTempRoot("ancestor-heal")
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default

        let projects = root.appendingPathComponent("Projects", isDirectory: true)
        try fm.createDirectory(at: projects, withIntermediateDirectories: true)
        try Data("seed".utf8).write(to: projects.appendingPathComponent("seed.md"))

        let initial = try EverythingIndex.build(rootURLs: [root], maxNodes: 2_000)

        let deepLeaf = projects.appendingPathComponent("Alpha/Beta/Gamma", isDirectory: true)
        try fm.createDirectory(at: deepLeaf, withIntermediateDirectories: true)
        try Data("fresh".utf8).write(to: deepLeaf.appendingPathComponent("deep_invoice_2026.pdf"))

        let updated = initial.applyingFSEventDirectories([deepLeaf.path])
        #expect(updated.search(queryText: "deep_invoice_2026.pdf").count == 1)
    }

    @Test("Offline directory swap with pre-snapshot nested subdir ctime/mtime refreshes entire replaced subtree")
    func directoryReplacementAndCtimeReconciliation() async throws {
        let root = try makeTempRoot("replace-dir")
        let staging = try makeTempRoot("staging")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: staging)
        }
        let fm = FileManager.default

        let targetSub = root.appendingPathComponent("Workspace/Module/Sub", isDirectory: true)
        try fm.createDirectory(at: targetSub, withIntermediateDirectories: true)
        try Data("v1".utf8).write(to: targetSub.appendingPathComponent("stale_old.txt"))

        // Create and backdate staging/Module/Sub BEFORE building initial snapshot so Sub's ctime < initial.builtAt
        let replacement = staging.appendingPathComponent("Module", isDirectory: true)
        let replacementSub = replacement.appendingPathComponent("Sub", isDirectory: true)
        try fm.createDirectory(at: replacementSub, withIntermediateDirectories: true)
        try Data("v2".utf8).write(to: replacementSub.appendingPathComponent("swapped_fresh.txt"))
        let pastDate = Date(timeIntervalSinceNow: -3_600)
        try fm.setAttributes([.modificationDate: pastDate], ofItemAtPath: replacementSub.path)
        try fm.setAttributes([.modificationDate: pastDate], ofItemAtPath: replacement.path)

        try await Task.sleep(for: .milliseconds(80))
        let initial = try EverythingIndex.build(rootURLs: [root], maxNodes: 2_000)
        #expect(initial.search(queryText: "stale_old.txt").count == 1)

        try await Task.sleep(for: .milliseconds(40))
        let moduleURL = root.appendingPathComponent("Workspace/Module", isDirectory: true)
        try fm.removeItem(at: moduleURL)
        try fm.moveItem(at: replacement, to: moduleURL)

        let viaReconcile = initial.reconcilingFilesystemChangesSinceSnapshot(safetyMarginSeconds: 0)
        #expect(viaReconcile.search(queryText: "swapped_fresh.txt").count == 1)
        #expect(viaReconcile.search(queryText: "stale_old.txt").isEmpty)
    }

    @Test("App discovery detects .lproj/Info.plist updates, English names, symlinks deterministically, and ignores fake .app files")
    func appFingerprintAndDeterministicDiscovery() throws {
        let root = try makeTempRoot("app-fresh")
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default

        let appsDir = root.appendingPathComponent("Applications", isDirectory: true)
        let externalStore = root.appendingPathComponent("Caskroom", isDirectory: true)
        try fm.createDirectory(at: appsDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: externalStore, withIntermediateDirectories: true)

        let toolApp = appsDir.appendingPathComponent("PulseNote.app", isDirectory: true)
        try makeMockApp(at: toolApp, displayName: "PulseNote Old", zhDisplayName: "脉冲笔记")
        // Regular non-directory file ending in .app must be ignored
        try Data("not-a-bundle".utf8).write(to: appsDir.appendingPathComponent("notes.app"))
        // Lexicographically earlier symlink to PulseNote.app must NOT hijack real bundle's ID/name
        try fm.createSymbolicLink(at: appsDir.appendingPathComponent("AAA_PulseAlias.app"), withDestinationURL: toolApp)

        let wecomApp = appsDir.appendingPathComponent("企业微信.app", isDirectory: true)
        try makeMockApp(at: wecomApp, displayName: "企业微信", zhDisplayName: "企业微信", enDisplayName: "WeCom")

        let deepDir = appsDir.appendingPathComponent("VendorSuite/SubTools", isDirectory: true)
        try fm.createDirectory(at: deepDir, withIntermediateDirectories: true)
        try makeMockApp(at: deepDir.appendingPathComponent("DeepHelper.app", isDirectory: true), displayName: "DeepHelper")

        let externalTarget = externalStore.appendingPathComponent("LinkedTool.app", isDirectory: true)
        try fm.createSymbolicLink(at: appsDir.appendingPathComponent("LinkedTool.app"), withDestinationURL: externalTarget)

        let fp0 = LauncherEngine.applicationDirectoriesFingerprint(roots: [appsDir])
        let apps0 = LauncherEngine.discoverInstalledApps(roots: [appsDir])
        #expect(apps0.contains { $0.id == toolApp.path && $0.name == "脉冲笔记" })
        #expect(!apps0.contains { $0.englishName == "AAA_PulseAlias" })
        #expect(!apps0.contains { $0.englishName == "notes" })
        #expect(apps0.contains { $0.name == "企业微信" && $0.englishName == "WeCom" })
        #expect(apps0.contains { $0.name == "DeepHelper" })
        #expect(!apps0.contains { $0.englishName == "LinkedTool" })
        #expect(LauncherEngine.rankCandidates(query: "wecom", filter: .all, apps: apps0, plugins: []).first?.id == wecomApp.path)

        // Updating ONLY zh-Hans.lproj/InfoPlist.strings must change fingerprint and refresh localized name
        let zhStrings = toolApp.appendingPathComponent("Contents/Resources/zh-Hans.lproj/InfoPlist.strings")
        try Data("\"CFBundleDisplayName\" = \"流光速记\";\n".utf8).write(to: zhStrings)
        let fp1 = LauncherEngine.applicationDirectoriesFingerprint(roots: [appsDir])
        #expect(fp1 != fp0)
        #expect(LauncherEngine.discoverInstalledApps(roots: [appsDir]).contains { $0.name == "流光速记" })

        // Resolving previously broken symlink target changes fingerprint and exposes LinkedTool
        try makeMockApp(at: externalTarget, displayName: "LinkedTool")
        let fp2 = LauncherEngine.applicationDirectoriesFingerprint(roots: [appsDir])
        #expect(fp2 != fp1)
        #expect(LauncherEngine.discoverInstalledApps(roots: [appsDir]).contains { $0.englishName == "LinkedTool" })
    }

    @Test("FSEventWatcher maxWaitInterval prevents starvation during continuous bursts and ignores hidden files/subtrees")
    func watcherMaxWaitPreventsStarvationAndIgnoresHiddenFiles() async throws {
        guard EverythingFSEventWatcher.currentEventId() > 0 else { return }
        let root = try makeTempRoot("watcher-maxwait")
        defer { try? FileManager.default.removeItem(at: root) }

        let recorder = TimelinessDirRecorder()
        let watcher = try #require(EverythingFSEventWatcher(
            roots: [root],
            sinceEventId: nil,
            debounceInterval: 0.25,
            maxWaitInterval: 0.45,
            ignoreNonStructuralFileModifications: true,
            ignoreHiddenItems: true
        ) { batch in
            recorder.record(batch.directories)
        })
        defer { watcher.stop() }
        // Let any delayed FSEvent from creating `root` settle before testing hidden-file suppression
        watcher.flushAsync()
        try await Task.sleep(for: .milliseconds(150))
        recorder.clear()

        let hiddenSub = root.appendingPathComponent(".staging", isDirectory: true)
        try FileManager.default.createDirectory(at: hiddenSub, withIntermediateDirectories: true)
        try Data("ds".utf8).write(to: root.appendingPathComponent(".DS_Store"))
        try Data("tmp".utf8).write(to: hiddenSub.appendingPathComponent("visible_inside_hidden.txt"))
        try await Task.sleep(for: .milliseconds(600))
        #expect(recorder.snapshot().isEmpty)

        let expectedRoot = EverythingFSEventWatcher.canonicalKernelPath(root.path)
        var flushedStep: Int?
        for step in 0..<12 {
            try Data("\(step)".utf8).write(to: root.appendingPathComponent("burst_\(step).txt"))
            try await Task.sleep(for: .milliseconds(100))
            if recorder.snapshot().contains(expectedRoot) {
                flushedStep = step
                break
            }
        }
        #expect(flushedStep != nil && (flushedStep ?? 99) < 10)
    }
}

private final class TimelinessDirRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var dirs: Set<String> = []
    func record(_ items: Set<String>) { lock.lock(); dirs.formUnion(items); lock.unlock() }
    func clear() { lock.lock(); dirs.removeAll(); lock.unlock() }
    func snapshot() -> Set<String> { lock.lock(); defer { lock.unlock() }; return dirs }
}

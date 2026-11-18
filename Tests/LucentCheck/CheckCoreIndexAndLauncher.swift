import AppKit
import Foundation
import LucentCore

func testVolumeAndMedia() throws {
    check(VolumeInspector.classifyFormat(fsType: "ntfs", isReadOnly: true) == .ntfsReadOnly, "ntfs ro")
    check(VolumeInspector.classifyFormat(fsType: "macfuse", isReadOnly: false) == .ntfsFuseWritable, "fuse rw")
    check(VolumeInspector.inspect(url: URL(fileURLWithPath: "/")) != nil, "root volume statfs")
    check(LucentError.readOnlyVolume("TestNTFS").diagnostic.title.contains("只读"), "readonly volume diagnostic")
    check(LucentSortOrder.ascending.toggled == .descending, "sort order toggle")

    let tmp = try makeTempDir("media")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let imgURL = tmp.appendingPathComponent("sample.png")
    try renderTextPNG(text: "LUCENT 2026", to: imgURL)
    let dims = MediaClassifier.readImageDimensions(at: imgURL)
    check(dims == CGSize(width: 480, height: 140), "image dimensions")
    check(MediaClassifier.makeThumbnail(at: imgURL, maxPixelSize: 120) != nil, "thumbnail generation")

    let vision = try VisionService.analyzeTextAndBarcodes(at: imgURL)
    check(vision.recognizedText.uppercased().contains("LUCENT"), "Vision OCR text recognized: '\(vision.recognizedText)'")
    print("[ok] VolumeInspector + MediaClassifier + VisionService OCR")
}

func testDirectoryAndBatchRename() throws {
    let tmp = try makeTempDir("rename")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let a = tmp.appendingPathComponent("a.txt")
    let b = tmp.appendingPathComponent("b.txt")
    try "hello".write(to: a, atomically: true, encoding: .utf8)
    try "world".write(to: b, atomically: true, encoding: .utf8)

    let hash = try DirectoryScanner.computeSHA256(for: a)
    check(hash.count == 64, "sha256 length")

    let scanned = try DirectoryScanner.sortEntries(
        DirectoryScanner.scanDirectory(at: tmp, includeHidden: false),
        by: .name,
        order: .ascending
    )
    check(scanned.count == 2, "scanned 2 files")

    let rule = BatchRenameRule(prefix: "v_", useIndexNumbering: true, startNumber: 1, zeroPadWidth: 2)
    let plan = BatchRenamePlanner.plan(entries: scanned, rule: rule)
    check(plan.allSatisfy { !$0.hasConflict }, "clean rename plan")
    try BatchRenamePlanner.apply(plan)
    check(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("v_a_01.txt").path), "renamed a")

    let collideRule = BatchRenameRule(findText: "a_01", replaceText: "b_02")
    let rescanned = try DirectoryScanner.scanDirectory(at: tmp, includeHidden: false)
    let badPlan = BatchRenamePlanner.plan(entries: rescanned, rule: collideRule)
    check(badPlan.contains(where: \.hasConflict), "collision detected")
    print("[ok] DirectoryScanner + BatchRenamePlanner")
}

func testEverythingLauncherUnitsAndClipboard() throws {
    let tmp = try makeTempDir("everything")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let rootA = tmp.appendingPathComponent("rootA", isDirectory: true)
    let rootB = tmp.appendingPathComponent("rootB", isDirectory: true)
    let sub = rootA.appendingPathComponent("src", isDirectory: true)
    try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: rootB, withIntermediateDirectories: true)
    try "let x = 1".write(to: sub.appendingPathComponent("App.swift"), atomically: true, encoding: .utf8)
    try "".write(to: sub.appendingPathComponent("clip.mp4"), atomically: true, encoding: .utf8)
    try "".write(to: rootB.appendingPathComponent("note.md"), atomically: true, encoding: .utf8)

    let multiIndex = try EverythingIndex.build(rootURLs: [rootA, rootB])
    check(multiIndex.nodes.count == 4, "multi-root indexed 4 nodes, got \(multiIndex.nodes.count)")
    check(multiIndex.search(queryText: "ext:swift path:src").first?.url.path.hasSuffix("rootA/src/App.swift") == true, "multi-root url resolution")
    check(multiIndex.search(queryText: "video: | folder:").count == 2, "dsl or clause")

    let py = PinyinHelper.convert("活动监视器")
    check(py.full == "huodongjianshiqi" && py.initials == "hdjsq", "pinyin conversion got \(py)")
    check(SafeMathEvaluator.evaluate("2 ^ 10") == "1024", "power math eval")
    check(SafeMathEvaluator.evaluate("0xff + 1") == "256", "hex math eval")
    check(SafeMathEvaluator.evaluate("((bad input))") == nil, "invalid math safe nil")

    check(UnitAndCommandEngine.evaluate("255 in hex")?.resultText == "0xFF", "dec to hex")
    check(UnitAndCommandEngine.evaluate("0xff in dec")?.resultText == "255", "hex to dec")
    check(UnitAndCommandEngine.evaluate("2048 mb to gb")?.resultText == "2 GB", "mb to gb")
    check(UnitAndCommandEngine.evaluate("30 c to f")?.resultText == "86 °F", "c to f")
    check(UnitAndCommandEngine.evaluate("10 km to mi")?.resultText.contains("6.214") == true, "km to mi")
    check(UnitAndCommandEngine.matchCommands(query: "x", volumes: []).isEmpty, "single-letter command no false match")

    let fakeApp = InstalledAppItem(name: "活动监视器", englishName: "Activity Monitor", url: URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
    let inlineFileHits = LauncherEngine.rankCandidates(query: "f ext:swift", apps: [fakeApp], plugins: [], everythingIndex: multiIndex)
    check(inlineFileHits.contains(where: { if case .fileHit = $0.kind { return true }; return false }), "inline launcher file hit")
    let zhHit = LauncherEngine.rankCandidates(query: "hdjsq", apps: [fakeApp], plugins: [])
    check(!zhHit.isEmpty, "localized pinyin initials match")

    check(ClipboardService.parseHexColor("#3478f6") == "#3478F6", "hex color normalization")
    let e1 = ClipboardEntry(title: "#3478F6", subtitle: "HEX", textValue: "#3478f6", isPinned: true, payloadKind: .colorHex("#3478F6"))
    let e2 = ClipboardEntry(title: "other", subtitle: "text", textValue: "hello", payloadKind: .text)
    let e1Again = ClipboardEntry(title: "#3478F6", subtitle: "HEX", textValue: "#3478f6", isPinned: false, payloadKind: .colorHex("#3478F6"))
    var list = ClipboardService.insert(e1, into: [])
    list = ClipboardService.insert(e2, into: list)
    list = ClipboardService.insert(e1Again, into: list)
    check(list.count == 2 && list.first?.isPinned == true, "clipboard dedupe preserves pin at top")
    print("[ok] EverythingIndex + UnitAndCommandEngine + ClipboardService + LauncherEngine")
}

func testPluginAndMCPSubprocess() throws {
    check(!PluginSystem.isSafePluginID("../escape"), "unsafe id rejected")
    let tmp = try makeTempDir("mcp-plugins")
    defer { try? FileManager.default.removeItem(at: tmp) }

    let binDir = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent()
    let mcpURL = binDir.appendingPathComponent("lucent-mcp")
    check(FileManager.default.isExecutableFile(atPath: mcpURL.path), "lucent-mcp binary exists at \(mcpURL.path)")

    let process = Process()
    process.executableURL = mcpURL
    process.arguments = ["--plugins-dir", tmp.path]
    let inPipe = Pipe(); let outPipe = Pipe()
    process.standardInput = inPipe; process.standardOutput = outPipe
    try process.run()

    let requests: [String] = [
        #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#,
        #"{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}"#,
        #"{"jsonrpc":"2.0","id":2,"method":"resources/read","params":{"uri":"lucent://specs/plugin-v3"}}"#,
        #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"lucent_scaffold_plugin","arguments":{"id":"demo-echo","name":"Demo Echo","keywords":["echo"],"mode":"script","capabilities":[],"resourceScopes":[]}}}"#,
        #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"lucent_validate_plugin","arguments":{"id":"demo-echo"}}}"#,
        #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"lucent_run_plugin_test","arguments":{"id":"demo-echo","query":"ping"}}}"#
    ]
    try inPipe.fileHandleForWriting.write(contentsOf: Data((requests.joined(separator: "\n") + "\n").utf8))
    try inPipe.fileHandleForWriting.close()
    process.waitUntilExit()
    check(process.terminationStatus == 0, "lucent-mcp exited 0")

    let outString = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let lines = outString.split(separator: "\n").map(String.init)
    check(lines.count == 5, "expected 5 JSON-RPC responses, got \(lines.count)")

    func toolText(at lineIndex: Int) -> String {
        guard let data = lines[lineIndex].data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let content = result["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else { return "" }
        return text
    }

    check(lines[0].contains("lucent-mcp"), "initialize response")
    check(lines[1].contains("Lucent Plugin Specification"), "spec resource content")
    check(toolText(at: 2).contains("demo-echo") && toolText(at: 2).contains("\"valid\" : true"), "scaffold result")
    let validateObj = (try? JSONSerialization.jsonObject(with: Data(toolText(at: 3).utf8)) as? [String: Any]) ?? [:]
    check((validateObj["valid"] as? Bool) == true, "scaffolded plugin validates cleanly")
    check(toolText(at: 4).contains("[demo-echo] ok"), "script plugin executed via MCP")
    print("[ok] PluginSystem + real lucent-mcp stdio JSON-RPC subprocess")
}

func testV03MarkdownOmniMosAndMemory() throws {
    check(MediaClassifier.classify(url: URL(fileURLWithPath: "/tmp/readme.md"), isDirectory: false) == .markdown, "md classifies as .markdown")
    check(MediaClassifier.classify(url: URL(fileURLWithPath: "/tmp/notes.markdown"), isDirectory: false) == .markdown, "markdown classifies as .markdown")
    check(MediaClassifier.classify(url: URL(fileURLWithPath: "/tmp/main.swift"), isDirectory: false) == .text, "swift classifies as .text")

    let sampleMD = """
    ---
    title: Lucent v0.3
    author: Queensu
    ---

    # Heading One

    Hello **world** with `inline`.

    > [!TIP]
    > Smooth scroll enabled.

    - [x] Done task
    - [ ] Open task

    | Name | Kind |
    | --- | --- |
    | Mos | Mouse |

    ```swift
    let x = 42
    ```
    """
    let blocks = MarkdownDocumentParser.parse(sampleMD)
    check(blocks.contains(where: { if case .frontmatter = $0 { return true }; return false }), "markdown frontmatter parsed")
    check(blocks.contains(where: { if case .heading(_, 1, "Heading One") = $0 { return true }; return false }), "markdown H1 parsed")
    check(blocks.contains(where: { if case .alert(_, .tip, _) = $0 { return true }; return false }), "markdown tip callout parsed")
    check(blocks.contains(where: { if case .taskList = $0 { return true }; return false }), "markdown task list parsed")
    check(blocks.contains(where: { if case .table = $0 { return true }; return false }), "markdown table parsed")
    check(blocks.contains(where: { if case .codeBlock(_, "swift", _) = $0 { return true }; return false }), "markdown fenced code block parsed")
    check(MarkdownDocumentParser.headings(in: blocks).count == 1, "markdown heading TOC extraction")

    let tmp = try makeTempDir("v03-omni")
    defer { try? FileManager.default.removeItem(at: tmp) }
    try sampleMD.write(to: tmp.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
    let index = try EverythingIndex.build(rootURLs: [tmp])
    let clip = ClipboardEntry(title: "readme snippet", subtitle: "text", textValue: "readme note", payloadKind: .text)
    let fakeApp = InstalledAppItem(name: "活动监视器", englishName: "Activity Monitor", url: URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))

    let allHits = LauncherEngine.rankCandidates(
        query: "readme", filter: .all, apps: [fakeApp], plugins: [], clipboardItems: [clip], everythingIndex: index
    )
    check(allHits.contains(where: { if case .fileHit = $0.kind { return true }; return false }), "unified search matches files without f prefix")
    check(allHits.contains(where: { if case .clipboard = $0.kind { return true }; return false }), "unified search matches clipboard items")
    check(UnitAndCommandEngine.matchCommands(query: "mos", volumes: []).contains(where: { $0.command == .toggleMosEnabled }), "mos command matched")

    let timeoutRes = try ProcessSupervisor.shared.run(executableURL: URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"], timeoutSeconds: 0.25)
    check(timeoutRes.timedOut == true && ProcessSupervisor.shared.activeCount == 0, "ProcessSupervisor kills timed-out subprocess")

    let mosURL = tmp.appendingPathComponent("mos-config.json")
    var cfg = MosConfig()
    cfg.enabled = true; cfg.reverseWheelDirection = false; cfg.stepPixels = 48; cfg.excludedBundleIDs = ["com.microsoft.rdc.macos"]
    cfg.save(to: mosURL)
    check(MosConfig.load(from: mosURL) == cfg, "MosConfig JSON persistence roundtrip")
    MosEngine.shared.stopTapAndReleaseAll()
    check(MosEngine.shared.isTapActive == false, "MosEngine releases event tap cleanly")
    check(MemoryStats.currentPhysicalFootprintMB() > 0, "MemoryStats reports positive physical footprint")
    MemoryStats.reclaimFreeHeapPages()
    print("[ok] v0.3 Markdown + OmniSearch + ProcessSupervisor + Mos + MemoryStats")
}

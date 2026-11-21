import Foundation
import LucentCore

func testV099ScriptLibraryAndMCP() throws {
    let tmp = try makeTempDir("v099-scripts-mcp")
    defer { try? FileManager.default.removeItem(at: tmp) }

    let binDir = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent()
    let mcpURL = binDir.appendingPathComponent("lucent-mcp")
    check(FileManager.default.isExecutableFile(atPath: mcpURL.path), "lucent-mcp exists for script library check")

    let layoutURL = tmp.appendingPathComponent("home-layout.json")
    let process = Process()
    process.executableURL = mcpURL
    process.arguments = ["--plugins-dir", tmp.path, "--home-layout", layoutURL.path]
    let inPipe = Pipe()
    let outPipe = Pipe()
    process.standardInput = inPipe
    process.standardOutput = outPipe
    try process.run()

    func rpcLine(_ id: Int, _ method: String, _ params: [String: Any]) throws -> String {
        let obj: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    let svgIcon = """
    <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
      <rect x="4" y="4" width="56" height="56" rx="15" fill="#14B8A6"/>
      <path d="M20 32 L44 32" stroke="#FFFFFF" stroke-width="4"/>
    </svg>
    """
    let pyCode = """
    #!/usr/bin/env python3
    # @lucent.title: 旧注释标题
    import os
    print('MCP_SCRIPT:' + os.environ.get('LUCENT_QUERY', ''))
    """

    let requests: [String] = [
        try rpcLine(1, "resources/list", [:]),
        try rpcLine(2, "resources/read", ["uri": "lucent://specs/scripts-v1"]),
        try rpcLine(3, "tools/call", [
            "name": "lucent_upsert_script",
            "arguments": [
                "id": "ai-slugger",
                "title": "标题转 URL 别名",
                "englishTitle": "Title to Slug",
                "subtitle": "AI 绘制图标与自动命名示例",
                "keywords": ["!slug"],
                "runtime": "customShebang",
                "fileExtension": "py",
                "code": pyCode,
                "outputMode": "copyToClipboard",
                "iconSvg": svgIcon,
                "accentColor": "teal",
                "hotKey": "⌃⌥J"
            ]
        ]),
        try rpcLine(4, "tools/call", [
            "name": "lucent_upsert_script",
            "arguments": [
                "id": "bad-svg",
                "title": "Bad SVG",
                "iconSvg": "<svg><script>alert(1)</script></svg>"
            ]
        ]),
        try rpcLine(5, "tools/call", [
            "name": "lucent_run_script_test",
            "arguments": ["id": "ai-slugger", "query": "hello-world"]
        ]),
        try rpcLine(6, "tools/call", [
            "name": "lucent_upsert_home_item",
            "arguments": [
                "section": "bento",
                "id": "tile-slugger",
                "kind": "script",
                "scriptID": "ai-slugger",
                "index": 0
            ]
        ]),
        try rpcLine(7, "tools/call", [
            "name": "lucent_list_scripts",
            "arguments": ["includeCode": true]
        ]),
        try rpcLine(8, "tools/call", [
            "name": "lucent_remove_script",
            "arguments": ["id": "ai-slugger"]
        ])
    ]

    let payload = Data((requests.joined(separator: "\n") + "\n").utf8)
    try inPipe.fileHandleForWriting.write(contentsOf: payload)
    try inPipe.fileHandleForWriting.close()
    process.waitUntilExit()
    check(process.terminationStatus == 0, "lucent-mcp exited 0 during script library check")

    let outText = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let lines = outText.split(separator: "\n").map(String.init)
    check(lines.count == 8, "expected 8 JSON-RPC responses for script library check, got \(lines.count)")

    func toolResult(at index: Int) -> (text: String, isError: Bool) {
        guard let data = lines[index].data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any] else { return ("", true) }
        let content = result["content"] as? [[String: Any]]
        let text = content?.first?["text"] as? String ?? ""
        let isErr = result["isError"] as? Bool ?? false
        return (text, isErr)
    }

    check(lines[0].contains("lucent://specs/scripts-v1"), "resources/list exposes lucent://specs/scripts-v1")
    check(lines[1].contains("Lucent Quick Scripts Library Specification"), "resources/read returns scripts-v1 spec")
    check(toolResult(at: 2).text.contains("\"hasCustomSvgIcon\" : true") && !toolResult(at: 2).isError, "lucent_upsert_script saves custom SVG icon & bilingual script")
    check(toolResult(at: 3).isError == true, "lucent_upsert_script rejects unsafe <script> inside iconSvg")
    check(toolResult(at: 4).text.contains("MCP_SCRIPT:hello-world") && !toolResult(at: 4).isError, "lucent_run_script_test executes customShebang script cleanly")
    check(toolResult(at: 5).text.contains("\"scriptID\" : \"ai-slugger\"") && !toolResult(at: 5).isError, "lucent_upsert_home_item pins script to Bento Tiles")
    check(toolResult(at: 6).text.contains("标题转 URL 别名") && !toolResult(at: 6).text.contains("旧注释标题") && toolResult(at: 6).text.contains("#14B8A6"), "lucent_list_scripts syncs magic header directive to match MCP title and preserves SVG markup")
    check(toolResult(at: 7).text.contains("\"removed\" : true"), "lucent_remove_script deletes script and custom SVG")

    try verifyMCPReadOnlyFileSearchGate(mcpBinary: mcpURL)
    print("[ok] v0.9.9 Standalone Script Library, Custom SVG Icon Crafting, Custom Shebang & lucent-mcp")
}

private func verifyMCPReadOnlyFileSearchGate(mcpBinary: URL) throws {
    let tmp = try makeTempDir("mcp-file-search")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let pluginsDir = tmp.appendingPathComponent("Plugins", isDirectory: true)
    let scanDir = tmp.appendingPathComponent("Notes", isDirectory: true)
    let privateDir = scanDir.appendingPathComponent("Private", isDirectory: true)
    let cacheDir = tmp.appendingPathComponent("IndexCache", isDirectory: true)
    for d in [pluginsDir, scanDir, privateDir, cacheDir] {
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    }
    try Data("public".utf8).write(to: scanDir.appendingPathComponent("Roadmap.md"))
    try Data("secret".utf8).write(to: privateDir.appendingPathComponent("Secret.md"))

    let idx = try EverythingIndex.build(rootURLs: [scanDir], maxNodes: 100)
    check(EverythingSnapshotStore.save(idx, scopeKey: "mcp-check", cacheDirectory: cacheDir) != nil, "saved LCNTIDX3 snapshot for MCP search")

    let prefsURL = tmp.appendingPathComponent("general-preferences.json")
    func runSearchCall() throws -> String {
        let p = Process()
        p.executableURL = mcpBinary
        p.arguments = ["--plugins-dir", pluginsDir.path, "--general-prefs", prefsURL.path, "--index-cache", cacheDir.path]
        let inPipe = Pipe(); let outPipe = Pipe()
        p.standardInput = inPipe; p.standardOutput = outPipe
        try p.run()
        let req = #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"lucent_search_files","arguments":{"query":"ext:md","limit":10}}}"# + "\n"
        try inPipe.fileHandleForWriting.write(contentsOf: Data(req.utf8))
        try inPipe.fileHandleForWriting.close()
        p.waitUntilExit()
        check(p.terminationStatus == 0, "lucent-mcp file search exited 0")
        return String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    // 1. Disabled by default (opt-in privacy gate)
    var prefs = GeneralPreferences(excludedIndexPaths: [privateDir.path], enableMcpFileSearch: false)
    prefs.save(to: prefsURL, notify: false)
    let deniedResp = try runSearchCall()
    check(deniedResp.contains("mcp_file_search_disabled") && deniedResp.contains(#""isError":true"#),
          "lucent_search_files blocked by default until opted in")

    // 2. Enabled -> returns matching .md file while filtering excluded private directory
    prefs.enableMcpFileSearch = true
    prefs.save(to: prefsURL, notify: false)
    let allowedResp = try runSearchCall()
    check(allowedResp.contains("Roadmap.md") && !allowedResp.contains("Secret.md") && allowedResp.contains(#""isError":false"#),
          "lucent_search_files queries LCNTIDX3 snapshot and respects excludedIndexPaths")
}

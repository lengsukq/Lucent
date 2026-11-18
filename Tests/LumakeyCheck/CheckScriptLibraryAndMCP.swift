import Foundation
import LumakeyCore

func testV099ScriptLibraryAndMCP() throws {
    let tmp = try makeTempDir("v099-scripts-mcp")
    defer { try? FileManager.default.removeItem(at: tmp) }

    let binDir = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent()
    let mcpURL = binDir.appendingPathComponent("lumakey-mcp")
    check(FileManager.default.isExecutableFile(atPath: mcpURL.path), "lumakey-mcp exists for script library check")

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
    # @lumakey.title: 旧注释标题
    import os
    print('MCP_SCRIPT:' + os.environ.get('LUMAKEY_QUERY', ''))
    """

    let requests: [String] = [
        try rpcLine(1, "resources/list", [:]),
        try rpcLine(2, "resources/read", ["uri": "lumakey://specs/scripts-v1"]),
        try rpcLine(3, "tools/call", [
            "name": "lumakey_upsert_script",
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
            "name": "lumakey_upsert_script",
            "arguments": [
                "id": "bad-svg",
                "title": "Bad SVG",
                "iconSvg": "<svg><script>alert(1)</script></svg>"
            ]
        ]),
        try rpcLine(5, "tools/call", [
            "name": "lumakey_run_script_test",
            "arguments": ["id": "ai-slugger", "query": "hello-world"]
        ]),
        try rpcLine(6, "tools/call", [
            "name": "lumakey_upsert_home_item",
            "arguments": [
                "section": "bento",
                "id": "tile-slugger",
                "kind": "script",
                "scriptID": "ai-slugger",
                "index": 0
            ]
        ]),
        try rpcLine(7, "tools/call", [
            "name": "lumakey_list_scripts",
            "arguments": ["includeCode": true]
        ]),
        try rpcLine(8, "tools/call", [
            "name": "lumakey_remove_script",
            "arguments": ["id": "ai-slugger"]
        ])
    ]

    let payload = Data((requests.joined(separator: "\n") + "\n").utf8)
    try inPipe.fileHandleForWriting.write(contentsOf: payload)
    try inPipe.fileHandleForWriting.close()
    process.waitUntilExit()
    check(process.terminationStatus == 0, "lumakey-mcp exited 0 during script library check")

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

    check(lines[0].contains("lumakey://specs/scripts-v1"), "resources/list exposes lumakey://specs/scripts-v1")
    check(lines[1].contains("Lumakey Quick Scripts Library Specification"), "resources/read returns scripts-v1 spec")
    check(toolResult(at: 2).text.contains("\"hasCustomSvgIcon\" : true") && !toolResult(at: 2).isError, "lumakey_upsert_script saves custom SVG icon & bilingual script")
    check(toolResult(at: 3).isError == true, "lumakey_upsert_script rejects unsafe <script> inside iconSvg")
    check(toolResult(at: 4).text.contains("MCP_SCRIPT:hello-world") && !toolResult(at: 4).isError, "lumakey_run_script_test executes customShebang script cleanly")
    check(toolResult(at: 5).text.contains("\"scriptID\" : \"ai-slugger\"") && !toolResult(at: 5).isError, "lumakey_upsert_home_item pins script to Bento Tiles")
    check(toolResult(at: 6).text.contains("标题转 URL 别名") && !toolResult(at: 6).text.contains("旧注释标题") && toolResult(at: 6).text.contains("#14B8A6"), "lumakey_list_scripts syncs magic header directive to match MCP title and preserves SVG markup")
    check(toolResult(at: 7).text.contains("\"removed\" : true"), "lumakey_remove_script deletes script and custom SVG")

    print("[ok] v0.9.9 Standalone Script Library, Custom SVG Icon Crafting, Custom Shebang & lumakey-mcp")
}

import Foundation
import LumakeyCore

func testV095HomeLayoutAndMCPOrchestration() throws {
    let tmp = try makeTempDir("v095-home-mcp")
    defer { try? FileManager.default.removeItem(at: tmp) }

    let binDir = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent()
    let mcpURL = binDir.appendingPathComponent("lumakey-mcp")
    check(FileManager.default.isExecutableFile(atPath: mcpURL.path), "lumakey-mcp exists for home layout check")

    let layoutURL = tmp.appendingPathComponent("home-layout.json")
    let process = Process()
    process.executableURL = mcpURL
    process.arguments = ["--plugins-dir", tmp.path, "--home-layout", layoutURL.path]
    let inPipe = Pipe()
    let outPipe = Pipe()
    process.standardInput = inPipe
    process.standardOutput = outPipe
    try process.run()

    let requests: [String] = [
        #"{"jsonrpc":"2.0","id":1,"method":"resources/list","params":{}}"#,
        #"{"jsonrpc":"2.0","id":2,"method":"resources/read","params":{"uri":"lumakey://specs/home-layout-v1"}}"#,
        #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"lumakey_get_home_layout","arguments":{"includeCandidates":true}}}"#,
        #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"lumakey_update_home_layout","arguments":{"createProfile":{"id":"work","name":"工作台","symbol":"hammer.fill","preset":"developer","activate":true},"bentoColumns":4,"hiddenSections":["utilityStrip"]}}}"#,
        #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"lumakey_upsert_home_item","arguments":{"section":"bento","id":"tile-gh","kind":"bookmark","url":"https://github.com/lengsukq/Lumakey","customTitle":"Lumakey Repo","accentColor":"indigo","index":0}}}"#,
        #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"lumakey_upsert_home_item","arguments":{"section":"dock","id":"dock-calc","kind":"nativeApp","path":"/System/Applications/Calculator.app"}}}"#,
        #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"lumakey_upsert_home_item","arguments":{"section":"shelf","shelfID":"ai-links","shelfTitle":"AI 书签","id":"bm-unsafe","kind":"bookmark","url":"javascript:alert(1)"}}}"#,
        #"{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"lumakey_remove_home_item","arguments":{"id":"tile-gh","section":"bento"}}}"#
    ]
    let payload = Data((requests.joined(separator: "\n") + "\n").utf8)
    try inPipe.fileHandleForWriting.write(contentsOf: payload)
    try inPipe.fileHandleForWriting.close()
    process.waitUntilExit()
    check(process.terminationStatus == 0, "lumakey-mcp exited 0 during home layout orchestration")

    let outText = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let lines = outText.split(separator: "\n").map(String.init)
    check(lines.count == 8, "expected 8 JSON-RPC responses for home layout check, got \(lines.count)")

    func toolResult(at index: Int) -> (text: String, isError: Bool) {
        guard let data = lines[index].data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any] else { return ("", true) }
        let content = result["content"] as? [[String: Any]]
        let text = content?.first?["text"] as? String ?? ""
        let isErr = result["isError"] as? Bool ?? false
        return (text, isErr)
    }

    check(lines[0].contains("lumakey://specs/home-layout-v1"), "resources/list exposes lumakey://specs/home-layout-v1")
    check(lines[1].contains("Lumakey Home Layout & Multi-Profile Specification"), "resources/read returns home-layout-v1 spec")
    check(toolResult(at: 2).text.contains("builtinActions") && toolResult(at: 2).text.contains("activeProfileID"), "lumakey_get_home_layout returns active profile and candidates")
    check(toolResult(at: 3).text.contains("\"activeProfileID\" : \"work\"") && !toolResult(at: 3).isError, "lumakey_update_home_layout creates & activates 'work' profile")
    check(toolResult(at: 4).text.contains("Lumakey Repo") && toolResult(at: 4).text.contains("\"upserted\" : true"), "lumakey_upsert_home_item adds bookmark Bento tile")
    check(toolResult(at: 5).text.contains("dock-calc") && toolResult(at: 5).text.contains("\"upserted\" : true"), "lumakey_upsert_home_item pins nativeApp to Omni Dock")
    check(toolResult(at: 6).isError == true, "lumakey_upsert_home_item rejects unsafe javascript: scheme")
    check(toolResult(at: 7).text.contains("\"removedCount\" : 1"), "lumakey_remove_home_item removes targeted Bento tile")

    let persisted = HomeLayoutConfig.loadOrBootstrap(from: layoutURL)
    check(persisted.activeProfileID == "work", "persisted home-layout.json keeps 'work' profile active")
    check(persisted.activeProfile.bentoColumns == .four, "persisted profile keeps 4-column Bento density")
    check(!persisted.activeProfile.isSectionVisible(.utilityStrip), "persisted profile hides utilityStrip")
    check(persisted.activeProfile.dockItems.contains(where: { $0.id == "dock-calc" }), "persisted profile retains pinned Calculator in dock")

    print("[ok] v0.9.5 Modular Home Layout, Multi-Profile & lumakey-mcp Live Orchestration")
}

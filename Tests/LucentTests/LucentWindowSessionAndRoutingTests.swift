import Darwin
import Foundation
import LucentCore
import LucentFoundation
import Testing

@Suite("Window Session, Reuse & Cross-Plugin Context Routing")
struct LucentWindowSessionAndRoutingTests {
    private func makeTempDir(prefix: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writePlugin(
        id: String,
        in root: URL,
        entryScript: String,
        capabilities: [String] = [],
        resourceScopes: [String] = [],
        accepts: [String] = [],
        persistSession: Bool? = nil
    ) throws -> PluginDescriptor {
        let dir = root.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let entryURL = dir.appendingPathComponent("run.sh")
        try Data(entryScript.utf8).write(to: entryURL)
        Darwin.chmod(entryURL.path, 0o755)
        let htmlURL = dir.appendingPathComponent("ui.html")
        try Data("<html><body>ok</body></html>".utf8).write(to: htmlURL)

        var windowDict: [String: Any] = ["entryHtml": "ui.html", "chrome": "frameless", "transparent": true]
        if let persistSession { windowDict["persistSession"] = persistSession }
        let manifest: [String: Any] = [
            "schemaVersion": 3,
            "id": id,
            "name": "Test \(id)",
            "version": "1.0.0",
            "description": "Test plugin \(id)",
            "mode": "view",
            "keywords": [id],
            "entry": "run.sh",
            "capabilities": capabilities,
            "resourceScopes": resourceScopes,
            "accepts": accepts,
            "window": windowDict
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted])
        try data.write(to: dir.appendingPathComponent("plugin.json"))
        return PluginSystem.loadPlugin(at: dir, in: root)
    }

    @Test("Window-bound NDJSON session round-trips and cleans up child process on stop")
    func windowSessionRoundTripAndCleanup() throws {
        let root = try makeTempDir(prefix: "lc-win-session")
        defer { try? FileManager.default.removeItem(at: root) }

        let script = """
        #!/bin/zsh
        read -r BOOTSTRAP
        echo '{"type":"boot","ok":true}'
        while IFS= read -r LINE; do
          echo "{\\"type\\":\\"echo\\",\\"payload\\":$LINE}"
        done
        """
        let desc = try writePlugin(id: "echo-session", in: root, entryScript: script)
        #expect(desc.isValid)

        let bootSem = DispatchSemaphore(value: 0)
        let echoSem = DispatchSemaphore(value: 0)
        let box = TestSessionCaptureBox()

        let session = try PluginWindowSessionProcess(
            descriptor: desc,
            arguments: ["--session"],
            pluginsRoot: root,
            onEventLine: { lineData in
                guard let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      let kind = obj["type"] as? String else { return }
                let cmdVal = (kind == "echo") ? ((obj["payload"] as? [String: Any])?["cmd"] as? String) : nil
                box.recordEvent(kind: kind, echoedCmd: cmdVal)
                if kind == "boot" { bootSem.signal() }
                if kind == "echo" { echoSem.signal() }
            },
            onExit: { code, err in
                box.recordExit(code: code, stderr: err)
            }
        )

        let childPID = session.processIdentifier
        #expect(childPID > 0)
        #expect(bootSem.wait(timeout: .now() + 4) == .success, "boot wait failed; exit=\(box.snapshotExit())")

        let sent = session.sendLineData(Data("{\"cmd\":\"ping\"}".utf8))
        #expect(sent)
        #expect(echoSem.wait(timeout: .now() + 4) == .success)
        #expect(box.snapshotEchoCmd() == "ping")
        #expect(box.hasTypes(["boot", "echo"]))

        session.stop(waitGraceSeconds: 0.35)
        Thread.sleep(forTimeInterval: 0.08)
        let aliveAfterStop = (kill(childPID, 0) == 0)
        #expect(!aliveAfterStop)
    }

    @Test("contextRouter capability gates match/route, excludes caller, and validates files")
    func contextRouterBridgeGatesAndDispatch() throws {
        let root = try makeTempDir(prefix: "lc-ctx-router")
        defer { try? FileManager.default.removeItem(at: root) }

        let sender = try writePlugin(
            id: "sender-plug", in: root, entryScript: "#!/bin/zsh\nexit 0\n",
            capabilities: ["contextRouter"], accepts: ["file", "text"]
        )
        let sampleFile = root.appendingPathComponent("note.txt")
        try Data("hello".utf8).write(to: sampleFile)

        let box = TestSessionCaptureBox()

        let hostCtx = PluginBridgeHostContext(
            contextMatcher: { sourceID, payload in
                #expect(sourceID == "sender-plug")
                #expect(payload.kind == .file)
                return [
                    PluginContextRouteCandidate(
                        id: "file-shelf", name: "File Shelf", categoryTag: "Files",
                        symbolName: "tray.full", accentColor: "teal"
                    )
                ]
            },
            contextRouter: { targetID, payload in
                box.recordRoute(target: targetID, paths: payload.filePaths ?? [])
                return true
            }
        ).scoped(to: sender)

        // 1. Denied when not granted through PluginHostBridgeServer
        let deniedReq = try JSONSerialization.data(withJSONObject: [
            "token": "tok", "capability": "contextRouter", "action": "match",
            "params": ["kind": "file", "filePaths": [sampleFile.path]]
        ])
        let deniedResp = PluginHostBridgeServer.evaluateRequestData(
            deniedReq, expectedToken: "tok", descriptor: sender, grantedCapabilities: [], hostContext: hostCtx
        )
        #expect(deniedResp["ok"] as? Bool == false)
        #expect(deniedResp["error"] as? String == "capability_not_granted")

        // 2. Match succeeds when granted
        let matchResp = PluginHostBridgeHandlers.dispatch(
            capability: .contextRouter, action: "match",
            params: ["kind": "file", "filePaths": [sampleFile.path]], hostContext: hostCtx
        )
        #expect(matchResp["ok"] as? Bool == true)
        let dataObj = matchResp["data"] as? [String: Any]
        let matched = dataObj?["plugins"] as? [[String: Any]] ?? []
        #expect(matched.count == 1)
        #expect(matched.first?["id"] as? String == "file-shelf")

        // 3. Self-routing is rejected
        let selfRouteResp = PluginHostBridgeHandlers.dispatch(
            capability: .contextRouter, action: "route",
            params: ["targetPluginId": "sender-plug", "kind": "file", "filePaths": [sampleFile.path]],
            hostContext: hostCtx
        )
        #expect(selfRouteResp["ok"] as? Bool == false)

        // 4. Valid target routing succeeds
        let routeResp = PluginHostBridgeHandlers.dispatch(
            capability: .contextRouter, action: "route",
            params: ["targetPluginId": "file-shelf", "kind": "file", "filePaths": [sampleFile.path]],
            hostContext: hostCtx
        )
        #expect(routeResp["ok"] as? Bool == true)
        let routed = box.snapshotRoute()
        #expect(routed.target == "file-shelf")
        #expect(routed.paths == [sampleFile.standardizedFileURL.path])
    }

    @Test("Custom window models support persistSession=false, reuseIfOpen, and legacy JSON decoding")
    func customWindowReuseAndPersistSession() throws {
        let root = try makeTempDir(prefix: "lc-win-model")
        defer { try? FileManager.default.removeItem(at: root) }

        let plug = try writePlugin(
            id: "ephemeral-win", in: root, entryScript: "#!/bin/zsh\nexit 0\n",
            capabilities: ["floatingWindow"], persistSession: false
        )
        #expect(plug.manifest.window?.persistSession == false)

        let launch = PluginWindowLaunchEffect(windowID: "main", initialStateJSON: "{\"a\":1}", reuseIfOpen: true)
        let resolved = PluginCustomWindowSpec.resolve(plugin: plug, launch: launch)
        #expect(resolved.shouldReuseIfOpen)

        // Legacy persisted JSON without reuseIfOpen must still decode cleanly
        let legacyJSON = """
        {
          "pluginID": "ephemeral-win",
          "windowID": "main",
          "width": 400,
          "height": 500,
          "minWidth": 200,
          "minHeight": 120,
          "resizable": false,
          "chrome": "frameless",
          "transparent": true,
          "pinOnTop": true,
          "clickThrough": false,
          "showInDock": false,
          "opacity": 1.0
        }
        """
        let decoded = try JSONDecoder().decode(PluginCustomWindowSpec.self, from: Data(legacyJSON.utf8))
        #expect(!decoded.shouldReuseIfOpen)
    }

    @Test("PluginWindowFileActionPolicy normalizes paths and blocks direct open for apps/installers")
    func fileActionPolicySafety() throws {
        let root = try makeTempDir(prefix: "lc-file-policy")
        defer { try? FileManager.default.removeItem(at: root) }

        let pdf = root.appendingPathComponent("report.pdf")
        let pkg = root.appendingPathComponent("installer.pkg")
        let cmd = root.appendingPathComponent("script.command")
        let folder = root.appendingPathComponent("received", isDirectory: true)
        try Data("pdf".utf8).write(to: pdf)
        try Data("pkg".utf8).write(to: pkg)
        try Data("cmd".utf8).write(to: cmd)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let resolved = PluginWindowFileActionPolicy.resolveExistingURLs(from: [
            "relative/path.txt",
            "/nonexistent/missing-file.pdf",
            pdf.path,
            pdf.path,
            folder.path
        ])
        #expect(resolved.count == 2)
        #expect(resolved[0].path == pdf.standardizedFileURL.path)
        #expect(resolved[1].path == folder.standardizedFileURL.path)

        #expect(PluginWindowFileActionPolicy.isSafeForDirectOpen(pdf))
        #expect(PluginWindowFileActionPolicy.isSafeForDirectOpen(folder))
        #expect(!PluginWindowFileActionPolicy.isSafeForDirectOpen(pkg))
        #expect(!PluginWindowFileActionPolicy.isSafeForDirectOpen(cmd))
        #expect(!PluginWindowFileActionPolicy.isSafeForDirectOpen(URL(fileURLWithPath: "/Applications/Safari.app")))
    }
}

private final class TestSessionCaptureBox: @unchecked Sendable {
    private let lock = NSLock()
    private var receivedTypes: [String] = []
    private var echoedCmd = ""
    private var routedTarget = ""
    private var routedPaths: [String] = []
    private var exitCode: Int32?
    private var exitStderr = ""

    func recordExit(code: Int32, stderr: String) {
        lock.withLock { exitCode = code; exitStderr = stderr }
    }

    func snapshotExit() -> String {
        lock.withLock { "code=\(exitCode.map(String.init) ?? "running") stderr=\(exitStderr)" }
    }

    func recordEvent(kind: String, echoedCmd: String?) {
        lock.withLock {
            receivedTypes.append(kind)
            if let echoedCmd { self.echoedCmd = echoedCmd }
        }
    }

    func snapshotEchoCmd() -> String { lock.withLock { echoedCmd } }
    func hasTypes(_ expected: [String]) -> Bool { lock.withLock { expected.allSatisfy(receivedTypes.contains) } }

    func recordRoute(target: String, paths: [String]) {
        lock.withLock { routedTarget = target; routedPaths = paths }
    }

    func snapshotRoute() -> (target: String, paths: [String]) {
        lock.withLock { (routedTarget, routedPaths) }
    }
}

import Foundation
import PluginKit

let cliArgs = Array(CommandLine.arguments.dropFirst())

if cliArgs.contains("--self-test") {
    runLocalSendSelfTest()
    exit(0)
}

if cliArgs.contains("--session") {
    let firstLine = readLine(strippingNewline: true) ?? "{}"
    let bootstrap = PluginInput.read(arguments: cliArgs, stdinData: Data(firstLine.utf8))
    let runtime = LocalSendSessionRuntime(bootstrapInput: bootstrap)
    runtime.runUntilExit()
    exit(0)
}

let input = PluginInput.read(arguments: cliArgs)
let title = input.pick("LocalSend 局域网快传", "LocalSend LAN Transfer")

if cliArgs.contains("--sync") {
    PluginOutput.emit(ViewPayload(title: title))
    exit(0)
}

var pending: [String: Any] = [:]
if let ctx = input.context {
    pending["kind"] = ctx.kind
    pending["source"] = ctx.source
    if !ctx.filePaths.isEmpty { pending["filePaths"] = ctx.filePaths }
    if let text = ctx.text, !text.isEmpty { pending["text"] = text }
    if let url = ctx.url, !url.isEmpty { pending["url"] = url }
} else if cliArgs.contains("--send-clipboard") {
    let clip = readClipboardFallback(input: input)
    if !clip.isEmpty {
        let isURL = URL(string: clip).flatMap { ($0.scheme == "http" || $0.scheme == "https") && $0.host != nil } ?? false
        pending["kind"] = isURL ? "url" : "text"
        pending["source"] = "clipboard"
        pending["text"] = clip
        if isURL { pending["url"] = clip }
    }
} else if !input.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
    let q = input.query.trimmingCharacters(in: .whitespacesAndNewlines)
    if !isSearchTriggerPrefix(q) {
        pending["kind"] = "text"
        pending["source"] = "query"
        pending["text"] = q
    }
}

var initialState: [String: Any] = [:]
if !pending.isEmpty {
    initialState["pendingContext"] = pending
    initialState["nonce"] = UUID().uuidString
}
let stateJSON = (try? JSONSerialization.data(withJSONObject: initialState))
    .flatMap { String(data: $0, encoding: .utf8) }
let launchSpec = WindowLaunchSpec(
    windowID: "main",
    initialStateJSON: stateJSON,
    reuseIfOpen: true
)
PluginOutput.emit(ViewPayload(
    title: title,
    effect: PostActionEffect(closeOverlay: true, openWindow: launchSpec)
))

private func isSearchTriggerPrefix(_ raw: String) -> Bool {
    guard !raw.contains(where: \.isWhitespace) else { return false }
    let lower = raw.lowercased()
    let triggers = ["localsend", "ls", "send", "drop", "airdrop", "局域网快传", "局域网", "快传", "传文件", "互传", "手机传文件"]
    return triggers.contains { $0.hasPrefix(lower) }
}

private func readClipboardFallback(input: PluginInput) -> String {
    let direct = input.clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
    if !direct.isEmpty { return direct }
    guard input.grantedCapabilities.contains("clipboard") else { return "" }
    let resp = HostBridgeClient(input: input).call(capability: "clipboard", action: "read")
    return resp.string("text").trimmingCharacters(in: .whitespacesAndNewlines)
}

/// 沙箱内端到端自检：验证 X.509 指纹、路径穿越防御、PIN 限流与本地回环 HTTPS 文件/文本收发闭环。
private func runLocalSendSelfTest() {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("ls-selftest-\(UUID().uuidString.prefix(8))", isDirectory: true)
    let dataDir = root.appendingPathComponent("data", isDirectory: true)
    let saveDir = root.appendingPathComponent("downloads", isDirectory: true)
    defer { try? fm.removeItem(at: root) }

    func require(_ cond: Bool, _ msg: String) {
        if !cond {
            fputs("SELF-TEST FAILED: \(msg)\n", stderr)
            exit(1)
        }
    }

    let safeParts = LocalSendFileSafety.sanitizedRelativeComponents(from: "../../etc/passwd")
    require(safeParts == ["etc", "passwd"], "path traversal must strip .. segments")
    let dest1 = try! LocalSendFileSafety.resolveUniqueDestinationURL(baseDirectory: saveDir, rawFileName: "../evil/demo.txt")
    require(dest1.path.hasPrefix(saveDir.standardizedFileURL.path + "/"), "destination stays inside saveDir")

    let identity = LocalSendTLSIdentity(dataDirectory: dataDir)
    defer { identity.cleanup() }
    require(identity.fingerprint.count == 64, "fingerprint is 64-char SHA-256 hex")
    require(identity.secIdentity != nil, "self-signed SecIdentity works under Seatbelt: \(identity.tlsInitError ?? "ok")")

    let cfg = LocalSendSessionConfig(
        alias: "SelfTest-Receiver", port: 0, useHttps: true, receiveMode: .quickSave,
        receivePin: "2468", saveDirectory: saveDir, dataDirectory: dataDir,
        autoRouteFilesToShelf: false, autoCopyReceivedText: false, isEnglish: true
    )
    let server = LocalSendHTTPServer(config: cfg, identity: identity)
    defer { server.stop() }

    require(server.verifyPin("0000") == 401, "wrong PIN returns 401")
    for _ in 0..<3 { _ = server.verifyPin("0000") }
    require(server.verifyPin("0000") == 429, "5th failed PIN triggers 429 lockout")

    let openCfg = LocalSendSessionConfig(
        alias: "SelfTest-Receiver", port: 0, useHttps: true, receiveMode: .quickSave,
        receivePin: "", saveDirectory: saveDir, dataDirectory: dataDir,
        autoRouteFilesToShelf: false, autoCopyReceivedText: false, isEnglish: true
    )
    let openServer = LocalSendHTTPServer(config: openCfg, identity: identity)
    defer { openServer.stop() }

    let readySem = DispatchSemaphore(value: 0)
    let receivedFileSem = DispatchSemaphore(value: 0)
    let receivedTextSem = DispatchSemaphore(value: 0)
    let stateBox = SelfTestBox()
    openServer.onStatusChanged = { st in
        if st.listening {
            stateBox.setListen(port: st.port, proto: st.protocolName)
            readySem.signal()
        }
    }
    openServer.onTransferCompleted = { ev in
        if let paths = ev["filePaths"] as? [String] {
            stateBox.setReceived(paths: paths)
            receivedFileSem.signal()
        } else if let txt = ev["text"] as? String {
            stateBox.setReceived(text: txt)
            receivedTextSem.signal()
        }
    }
    openServer.start(preferredPort: 0)
    require(readySem.wait(timeout: .now() + 5) == .success && stateBox.listenPort > 0, "server starts listening")
    require(stateBox.listenProto == "https", "server runs over HTTPS")

    let srcFile = root.appendingPathComponent("hello-sample.bin")
    let samplePayload = Data(repeating: 0x5A, count: 131_072)
    try! samplePayload.write(to: srcFile)

    let peer = LocalSendPeer(
        fingerprint: identity.fingerprint, alias: "Loopback", ip: "127.0.0.1", port: Int(stateBox.listenPort),
        protocolName: stateBox.listenProto, deviceModel: "macOS", deviceType: "desktop",
        isFavorite: false, isLumaLinkPaired: false, lastSeenEpoch: 0
    )
    let sendDoneSem = DispatchSemaphore(value: 0)
    let client = LocalSendClient(
        selfDeviceInfoProvider: {
            LocalSendDeviceInfo(alias: "Sender", version: "2.1", deviceModel: "macOS", deviceType: "desktop", fingerprint: "SENDER-FP", port: 53317, protocolName: "https", download: false, announce: nil)
        },
        onEvent: { ev in
            if (ev["type"] as? String) == "transferCompleted" { stateBox.setSend(ok: true, err: ""); sendDoneSem.signal() }
            if (ev["type"] as? String) == "transferFailed" { stateBox.setSend(ok: false, err: (ev["error"] as? String) ?? "unknown"); sendDoneSem.signal() }
        }
    )
    client.sendFiles(transferId: "t1", paths: [srcFile.path], to: peer, pin: nil)
    let waited = sendDoneSem.wait(timeout: .now() + 10)
    require(waited == .success && stateBox.sendOK, "HTTPS file upload succeeded (err=\(stateBox.sendErr), waited=\(waited))")
    require(receivedFileSem.wait(timeout: .now() + 5) == .success && stateBox.receivedPaths.count == 1, "receiver saved file")
    let savedData = try! Data(contentsOf: URL(fileURLWithPath: stateBox.receivedPaths[0]))
    require(savedData == samplePayload, "received file bytes match exactly")

    stateBox.setSend(ok: false, err: "")
    client.sendText(transferId: "t2", text: "https://localsend.org/test", to: peer, pin: nil)
    let waited2 = sendDoneSem.wait(timeout: .now() + 5)
    require(waited2 == .success && stateBox.sendOK, "HTTPS text transfer succeeded (err=\(stateBox.sendErr))")
    require(receivedTextSem.wait(timeout: .now() + 5) == .success && stateBox.receivedText == "https://localsend.org/test", "receiver got exact text")

    let historyStore = LocalSendHistoryStore(dataDirectory: dataDir)
    historyStore.record(completedEvent: ["direction": "receive", "sessionId": "h1", "peerAlias": "iPhone", "filePaths": [srcFile.path], "totalBytes": samplePayload.count])
    let reloaded = LocalSendHistoryStore(dataDirectory: dataDir).snapshot()
    require(reloaded.count == 1 && (reloaded[0]["id"] as? String) == "h1", "history persists across sessions")
    historyStore.remove(id: "h1")
    require(LocalSendHistoryStore(dataDirectory: dataDir).snapshot().isEmpty, "history deletion persists")

    print("{\"ok\":true,\"protocol\":\"\(stateBox.listenProto)\",\"port\":\(stateBox.listenPort),\"fingerprint\":\"\(identity.fingerprint.prefix(12))\"}")
}

private final class SelfTestBox: @unchecked Sendable {
    private let lock = NSLock()
    var listenPort: UInt16 = 0
    var listenProto = ""
    var receivedPaths: [String] = []
    var receivedText = ""
    var sendOK = false
    var sendErr = ""
    func setListen(port: UInt16, proto: String) { lock.withLock { listenPort = port; listenProto = proto } }
    func setReceived(paths: [String]) { lock.withLock { receivedPaths = paths } }
    func setReceived(text: String) { lock.withLock { receivedText = text } }
    func setSend(ok: Bool, err: String) { lock.withLock { sendOK = ok; sendErr = err } }
}

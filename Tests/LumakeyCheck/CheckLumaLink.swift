import CoreGraphics
import Foundation
import LumakeyCore

func testV080LumaLink() throws {
    let dir = try makeTempDir("lumalink")
    defer { try? FileManager.default.removeItem(at: dir) }

    // 1. Config persistence (default disabled) & backward-compatible decode
    let defaultCfg = LumaLinkConfig()
    check(!defaultCfg.enabled, "LumaLink defaults to disabled for zero resident footprint")
    check(!defaultCfg.rdpEnabled && defaultCfg.rdpPort == 3389, "LumaLink RDP defaults to disabled on port 3389")
    let legacyJSON = #"{"enabled":true,"preferredPort":59480,"pairedDevices":[]}"#.data(using: .utf8)!
    let decodedLegacy = try JSONDecoder().decode(LumaLinkConfig.self, from: legacyJSON)
    check(decodedLegacy.enabled && !decodedLegacy.rdpEnabled && decodedLegacy.rdpPort == 3389, "Legacy LumaLinkConfig JSON decodes cleanly with RDP defaults")
    let cfgURL = dir.appendingPathComponent("lumalink-config.json")
    let cfg = LumaLinkConfig(
        enabled: true,
        preferredPort: 59481,
        autoRestoreDisplayOnDisconnect: true,
        muteMacWhenCurtainEnabled: true,
        rdpEnabled: true,
        rdpPort: 3399,
        pairedDevices: [LumaLinkPairedDevice(name: "Pixel 9", token: "tok123")]
    )
    cfg.save(to: cfgURL)
    let loaded = LumaLinkConfig.load(from: cfgURL)
    check(loaded == cfg, "LumaLinkConfig round-trip persistence")

    // 2. Binary framing + partial chunk accumulator
    let req = LumaLinkRequest(id: "r1", action: "display.set", token: "tok123", displayID: 1, modeKey: "1280x720@2x_60")
    let jsonA = try JSONEncoder().encode(req)
    let resp = LumaLinkResponse(id: "r1", ok: true, hostName: "Mac mini")
    let jsonB = try JSONEncoder().encode(resp)
    var stream = Data()
    stream.append(LumaLinkFraming.encodeFrame(jsonA))
    stream.append(LumaLinkFraming.encodeFrame(jsonB))

    var acc = LumaLinkFrameAccumulator()
    let split = stream.count / 2
    let part1 = try acc.append(stream.prefix(split))
    let part2 = try acc.append(stream.suffix(from: split))
    let decodedFrames = part1 + part2
    check(decodedFrames.count == 2, "chunked LumaLinkFrameAccumulator recovers 2 frames")
    let decodedReq = try JSONDecoder().decode(LumaLinkRequest.self, from: decodedFrames[0])
    check(decodedReq.action == "display.set" && decodedReq.modeKey == "1280x720@2x_60", "LumaLinkRequest JSON fidelity")

    // 3. Oversized frame rejection
    var badAcc = LumaLinkFrameAccumulator()
    var badHeader = UInt32(LumaLinkFraming.maxFrameBytes + 1).bigEndian
    var badErr = false
    do {
        _ = try badAcc.append(Data(bytes: &badHeader, count: 4))
    } catch {
        badErr = true
    }
    check(badErr, "LumaLinkFrameAccumulator rejects oversized frames")

    // 4. Live display enumeration & audio query sanity (non-destructive)
    let displays = LumaLinkDisplayService.shared.listDisplays()
    check(!displays.isEmpty || CGMainDisplayID() == 0, "listDisplays enumerates active displays safely")
    let audio = LumaLinkSystemControlService.shared.readAudioState()
    check((0...100).contains(audio.volumePercent), "readAudioState returns bounded volume percent")

    // 5. RDP Sidecar cert generation & permission output parsing (non-destructive)
    let certDir = dir.appendingPathComponent("RemoteCerts", isDirectory: true)
    try LumaLinkRdpSidecarService.ensureSelfSignedCertificate(in: certDir)
    check(FileManager.default.fileExists(atPath: certDir.appendingPathComponent("server.key").path), "RDP self-signed key created")
    check(FileManager.default.fileExists(atPath: certDir.appendingPathComponent("server.crt").path), "RDP self-signed cert created")
    let parsedPerm = LumaLinkRdpSidecarService.parsePermissionOutput("screen_recording=granted\naccessibility=denied\n")
    check(parsedPerm.screenRecording && !parsedPerm.accessibility, "RDP permission parser extracts TCC flags accurately")
    let rdpStatus = LumaLinkRdpSidecarService.shared.currentStatus(refreshPermissions: false)
    check(!rdpStatus.enabled && !rdpStatus.running, "RDP sidecar remains disabled when toggled off")

    // 6. CoreAudio virtual mic enumeration & binary framing probe (non-destructive)
    let bridgeStatus = LumaLinkAudioBridgeService.shared.status(preferredName: "")
    check(!bridgeStatus.virtualMicActive && !bridgeStatus.speakerTapActive, "Audio bridge idle by default")
    let micHeader = Data([0x4C, 0x41, 0x4D, 0x31, 0xC0, 0x5D, 0x01, 0x00, 0x00, 0x00])
    var binAcc = LumaLinkFrameAccumulator()
    let binFrames = try binAcc.append(LumaLinkFraming.encodeFrame(micHeader))
    check(binFrames.count == 1 && binFrames[0].first != 0x7B, "Binary audio frame distinguishes from JSON payloads")

    // 7. RDP process guard: BoundedPipeBuffer, PID record, owned path filter, and group termination
    let pipeBuf = BoundedPipeBuffer(maxBytes: 256)
    pipeBuf.append(Data(repeating: 0x41, count: 400))
    pipeBuf.append(Data("TAIL-OK".utf8))
    let snapStr = pipeBuf.snapshotString()
    check(snapStr.count <= 256 && snapStr.hasSuffix("TAIL-OK"), "BoundedPipeBuffer caps size and preserves tail")

    let pidDir = dir.appendingPathComponent("PidGuard", isDirectory: true)
    let sampleRec = LumaLinkRdpPidRecord(pid: 12345, pgid: 12345, ownerPID: 99_999_999, port: 3389, binaryPath: "/Applications/Lumakey.app/Contents/Helpers/macos-rdp-daemon")
    LumaLinkRdpProcessGuard.writePidRecord(sampleRec, in: pidDir)
    check(LumaLinkRdpProcessGuard.readPidRecord(in: pidDir) == sampleRec, "RDP PID record round-trip")
    LumaLinkRdpProcessGuard.cleanupStaleProcesses(in: pidDir)
    check(LumaLinkRdpProcessGuard.readPidRecord(in: pidDir) == nil, "Stale RDP PID file cleaned up")

    let liveOwnerRec = LumaLinkRdpPidRecord(pid: 99_999_998, pgid: 99_999_998, ownerPID: 1, port: 3389, binaryPath: "/Applications/Lumakey.app/Contents/Helpers/macos-rdp-daemon")
    LumaLinkRdpProcessGuard.writePidRecord(liveOwnerRec, in: pidDir)
    LumaLinkRdpProcessGuard.cleanupStaleProcesses(in: pidDir)
    check(LumaLinkRdpProcessGuard.readPidRecord(in: pidDir) == nil, "PID record with ownerPID=1 cleaned up")

    check(LumaLinkRdpProcessGuard.isLumakeyOwnedDaemonPath("/Applications/Lumakey.app/Contents/Helpers/macos-rdp-daemon"), "Recognizes Lumakey app helper path")
    check(!LumaLinkRdpProcessGuard.isLumakeyOwnedDaemonPath("/Volumes/lightlsle/dependencies/build/mac-remote-host/MacRemoteRDPServer.app/Contents/MacOS/macos-rdp-daemon"), "Does not match external MacRemoteHost binary")

    let sleeper = Process()
    sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
    sleeper.arguments = ["30"]
    try sleeper.run()
    let sleepPID = sleeper.processIdentifier
    _ = Darwin.setpgid(sleepPID, sleepPID)
    check(LumaLinkRdpProcessGuard.isProcessAlive(sleepPID), "Test sleeper started")
    LumaLinkRdpProcessGuard.terminateProcessAndGroup(pid: sleepPID, pgid: sleepPID, graceSeconds: 0.2)
    sleeper.waitUntilExit()
    check(!LumaLinkRdpProcessGuard.isProcessAlive(sleepPID), "terminateProcessAndGroup kills test process cleanly")

    // 8. Stale Host Bridge UDS socket cleanup
    let sockDir = dir.appendingPathComponent("SockDir", isDirectory: true)
    try FileManager.default.createDirectory(at: sockDir, withIntermediateDirectories: true)
    let deadSock = sockDir.appendingPathComponent("b-99999999-dead000001.sock")
    let liveSock = sockDir.appendingPathComponent("b-\(ProcessInfo.processInfo.processIdentifier)-live000001.sock")
    try Data().write(to: deadSock)
    try Data().write(to: liveSock)
    PluginDataPaths.cleanupStaleSocketFiles(in: sockDir)
    check(!FileManager.default.fileExists(atPath: deadSock.path), "Dead PID UDS socket file cleaned up")
    check(FileManager.default.fileExists(atPath: liveSock.path), "Live PID UDS socket file preserved")

    // 9. ProcessSupervisor synchronous SIGKILL fallback on exit
    let supDone = DispatchSemaphore(value: 0)
    DispatchQueue.global(qos: .userInitiated).async {
        _ = try? ProcessSupervisor.shared.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "trap '' TERM; sleep 30"],
            timeoutSeconds: 15
        )
        supDone.signal()
    }
    let waitDeadline = Date().addingTimeInterval(1.5)
    while ProcessSupervisor.shared.activeCount == 0 && Date() < waitDeadline {
        Thread.sleep(forTimeInterval: 0.02)
    }
    check(ProcessSupervisor.shared.activeCount >= 1, "SIGTERM-ignoring subprocess registered in ProcessSupervisor")
    ProcessSupervisor.shared.terminateAll(waitGracePeriodSeconds: 0.2)
    check(supDone.wait(timeout: .now() + 1.5) == .success, "terminateAll synchronously force-kills SIGTERM-ignoring subprocess")
    check(ProcessSupervisor.shared.activeCount == 0, "ProcessSupervisor activeCount returns to 0")

    LumaLinkServer.shared.stopAll(waitUntilFinished: true)
    print("[ok] v0.8.0 LumaLink Protocol + Framing + Config + RDP Sidecar + Process Guard + Audio Bridge probe")
}

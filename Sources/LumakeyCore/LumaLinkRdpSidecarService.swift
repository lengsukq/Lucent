import Foundation

public struct LumaLinkRdpStatus: Codable, Sendable, Hashable {
    public var enabled: Bool
    public var running: Bool
    public var port: UInt16
    public var binaryFound: Bool
    public var binaryPath: String?
    public var screenRecordingGranted: Bool
    public var accessibilityGranted: Bool
    public var lastError: String?

    public init(
        enabled: Bool = false,
        running: Bool = false,
        port: UInt16 = 3389,
        binaryFound: Bool = false,
        binaryPath: String? = nil,
        screenRecordingGranted: Bool = false,
        accessibilityGranted: Bool = false,
        lastError: String? = nil
    ) {
        self.enabled = enabled
        self.running = running
        self.port = port
        self.binaryFound = binaryFound
        self.binaryPath = binaryPath
        self.screenRecordingGranted = screenRecordingGranted
        self.accessibilityGranted = accessibilityGranted
        self.lastError = lastError
    }
}

public final class LumaLinkRdpSidecarService: @unchecked Sendable {
    public static let shared = LumaLinkRdpSidecarService()

    private let lock = NSLock()
    private var process: Process?
    private var bonjourService: NetService?
    private var _enabled = false
    private var _port: UInt16 = 3389
    private var _localAudioEnabled = true
    private var _lastError: String?
    private var _lastScreenRecording = false
    private var _lastAccessibility = false
    private var cachedBinaryPath: String?

    public var onStatusChanged: (@MainActor @Sendable () -> Void)?

    private init() {}

    public func currentStatus(refreshPermissions: Bool = false) -> LumaLinkRdpStatus {
        let bin = resolveBinaryPath()
        if refreshPermissions, let bin {
            let perm = Self.queryDaemonPermissions(binaryPath: bin)
            lock.withLock {
                _lastScreenRecording = perm.screenRecording
                _lastAccessibility = perm.accessibility
            }
        }
        return lock.withLock {
            LumaLinkRdpStatus(
                enabled: _enabled,
                running: process?.isRunning == true,
                port: _port,
                binaryFound: bin != nil,
                binaryPath: bin,
                screenRecordingGranted: _lastScreenRecording,
                accessibilityGranted: _lastAccessibility,
                lastError: _lastError
            )
        }
    }

    public func resolveBinaryPath() -> String? {
        if let cached = lock.withLock({ cachedBinaryPath }),
           FileManager.default.isExecutableFile(atPath: cached) {
            return cached
        }
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let candidates: [String?] = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/macos-rdp-daemon").path,
            Bundle.main.sharedSupportURL?.appendingPathComponent("macos-rdp-daemon").path,
            "\(home)/.local/share/lumakey/macos-rdp-daemon",
            "/usr/local/sbin/macos-rdp-daemon",
            "/Volumes/lightlsle/dependencies/build/mac-remote-host/MacRemoteRDPServer.app/Contents/MacOS/macos-rdp-daemon",
            "/Volumes/lightlsle/dependencies/build/macos-rdp-server-macos14-final/macos-rdp-daemon"
        ]
        for case let path? in candidates where fm.isExecutableFile(atPath: path) {
            lock.withLock { cachedBinaryPath = path }
            return path
        }
        return nil
    }

    public static func defaultCertDirectoryURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("Lumakey/Remote", isDirectory: true)
    }

    public static func ensureSelfSignedCertificate(in dir: URL = defaultCertDirectoryURL()) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let keyURL = dir.appendingPathComponent("server.key")
        let crtURL = dir.appendingPathComponent("server.crt")
        if fm.fileExists(atPath: keyURL.path), fm.fileExists(atPath: crtURL.path) {
            return
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        proc.arguments = [
            "req", "-x509", "-newkey", "rsa:2048", "-nodes",
            "-keyout", keyURL.path,
            "-out", crtURL.path,
            "-days", "3650",
            "-subj", "/CN=LumaLinkRDP"
        ]
        let pipe = Pipe()
        proc.standardError = pipe
        proc.standardOutput = pipe
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let errText = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "openssl 失败"
            throw NSError(domain: "LumaLinkRdpSidecar", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errText])
        }
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
    }

    public static func queryDaemonPermissions(binaryPath: String) -> (screenRecording: Bool, accessibility: Bool) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        proc.arguments = ["--check-permissions"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        guard (try? proc.run()) != nil else { return (false, false) }
        proc.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return parsePermissionOutput(output)
    }

    public static func parsePermissionOutput(_ output: String) -> (screenRecording: Bool, accessibility: Bool) {
        let lines = output.split(whereSeparator: \.isNewline).map { String($0) }
        let sr = lines.contains { $0.trimmingCharacters(in: .whitespaces) == "screen_recording=granted" }
        let ax = lines.contains { $0.trimmingCharacters(in: .whitespaces) == "accessibility=granted" }
        return (sr, ax)
    }

    public func sync(enabled: Bool, port: UInt16, localAudioEnabled: Bool = true) {
        let resolvedPort = port == 0 ? 3389 : port
        if !enabled {
            lock.withLock {
                _enabled = false
                _port = resolvedPort
                _localAudioEnabled = localAudioEnabled
                _lastError = nil
            }
            stop()
            return
        }

        let alreadyRunning = lock.withLock { () -> Bool in
            _enabled = true
            let samePort = _port == resolvedPort
            let sameLocalAudio = _localAudioEnabled == localAudioEnabled
            _port = resolvedPort
            _localAudioEnabled = localAudioEnabled
            return samePort && sameLocalAudio && process?.isRunning == true
        }
        if alreadyRunning { return }

        stopChildOnly()
        guard let bin = resolveBinaryPath() else {
            lock.withLock { _lastError = "未找到 macos-rdp-daemon 助手程序" }
            notifyStatusChanged()
            return
        }

        let perm = Self.queryDaemonPermissions(binaryPath: bin)
        lock.withLock {
            _lastScreenRecording = perm.screenRecording
            _lastAccessibility = perm.accessibility
        }

        do {
            let certDir = Self.defaultCertDirectoryURL()
            try Self.ensureSelfSignedCertificate(in: certDir)

            let child = Process()
            child.executableURL = URL(fileURLWithPath: bin)
            child.arguments = ["--port", "\(resolvedPort)", "--log-level", "info"]
            var env = ProcessInfo.processInfo.environment
            env["RDP_CERT_DIR"] = certDir.path
            env["RDP_UPDATE_ENABLED"] = "0"
            env["RDP_ALLOW_IDLE_SLEEP"] = "1"
            env["RDP_AUDIO_LOCAL"] = localAudioEnabled ? "1" : "0"
            child.environment = env

            let errPipe = Pipe()
            child.standardError = errPipe
            child.standardOutput = FileHandle.nullDevice
            child.terminationHandler = { [weak self] finished in
                guard let self else { return }
                let stillExpected = self.lock.withLock { () -> Bool in
                    let wasCurrent = (self.process === finished)
                    if wasCurrent { self.process = nil }
                    return wasCurrent && self._enabled
                }
                if stillExpected && finished.terminationStatus != 0 {
                    let msg = String(data: errPipe.fileHandleForReading.availableData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    self.lock.withLock {
                        self._lastError = (msg?.isEmpty == false) ? msg : "RDP 引擎退出 (\(finished.terminationStatus))"
                    }
                }
                self.notifyStatusChanged()
            }

            try child.run()
            lock.withLock {
                process = child
                _lastError = nil
            }
            publishBonjour(port: Int32(resolvedPort))
            notifyStatusChanged()
        } catch {
            lock.withLock { _lastError = error.localizedDescription }
            notifyStatusChanged()
        }
    }

    public func stop() {
        lock.withLock { _enabled = false }
        stopChildOnly()
        notifyStatusChanged()
    }

    private func stopChildOnly() {
        unpublishBonjour()
        let proc = lock.withLock { () -> Process? in
            let p = process
            process = nil
            return p
        }
        guard let proc, proc.isRunning else { return }
        proc.terminate()
        let deadline = Date().addingTimeInterval(0.45)
        while proc.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if proc.isRunning {
            kill(proc.processIdentifier, SIGKILL)
        }
    }

    private func publishBonjour(port: Int32) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.bonjourService?.stop()
            let svc = NetService(domain: "local.", type: "_rdp._tcp.", name: Host.current().localizedName ?? "Mac", port: port)
            svc.publish()
            self.bonjourService = svc
        }
    }

    private func unpublishBonjour() {
        DispatchQueue.main.async { [weak self] in
            self?.bonjourService?.stop()
            self?.bonjourService = nil
        }
    }

    private func notifyStatusChanged() {
        let cb = onStatusChanged
        guard let cb else { return }
        Task { @MainActor in cb() }
    }
}

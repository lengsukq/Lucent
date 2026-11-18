import Darwin
import dnssd
import Foundation
import LucentFoundation

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
    private var processPGID: Int32 = 0
    private var activeErrHandle: FileHandle?
    private var activeErrBuffer: BoundedPipeBuffer?
    private var dnsServiceRef: DNSServiceRef?
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
        let envOverride = ProcessInfo.processInfo.environment["LUCENT_RDP_HELPER_PATH"]
        let appSupportHelper = Self.defaultCertDirectoryURL().appendingPathComponent("macos-rdp-daemon").path
        let candidates: [String?] = [
            envOverride,
            Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/macos-rdp-daemon").path,
            Bundle.main.sharedSupportURL?.appendingPathComponent("macos-rdp-daemon").path,
            appSupportHelper,
            "\(home)/.local/share/lucent/macos-rdp-daemon",
            "/opt/homebrew/bin/macos-rdp-daemon",
            "/opt/homebrew/sbin/macos-rdp-daemon",
            "/usr/local/bin/macos-rdp-daemon",
            "/usr/local/sbin/macos-rdp-daemon"
        ]
        for case let path? in candidates where fm.isExecutableFile(atPath: path) {
            lock.withLock { cachedBinaryPath = path }
            return path
        }
        return nil
    }

    @discardableResult
    public func installHelperBinary(from sourceURL: URL) throws -> URL {
        let fm = FileManager.default
        let destDir = Self.defaultCertDirectoryURL()
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        let destURL = destDir.appendingPathComponent("macos-rdp-daemon", isDirectory: false)
        if fm.fileExists(atPath: destURL.path) {
            try fm.removeItem(at: destURL)
        }
        try fm.copyItem(at: sourceURL, to: destURL)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destURL.path)
        lock.withLock { cachedBinaryPath = destURL.path; _lastError = nil }
        return destURL
    }

    public static func defaultCertDirectoryURL() -> URL {
        LucentAppPaths.defaultAppSupportDirectory().appendingPathComponent("Remote", isDirectory: true)
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
            let same = (_port == resolvedPort && _localAudioEnabled == localAudioEnabled && process?.isRunning == true)
            _port = resolvedPort
            _localAudioEnabled = localAudioEnabled
            return same
        }
        if alreadyRunning { return }

        stopChildOnly()
        let certDir = Self.defaultCertDirectoryURL()
        LumaLinkRdpProcessGuard.cleanupStaleProcesses(in: certDir)
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
            try Self.ensureSelfSignedCertificate(in: certDir)

            let child = Process()
            child.executableURL = URL(fileURLWithPath: bin)
            child.arguments = ["--port", "\(resolvedPort)", "--log-level", "info"]
            child.environment = PluginSandboxProfileBuilder.sanitizedEnvironment(
                pluginVariables: [
                    "RDP_CERT_DIR": certDir.path,
                    "RDP_UPDATE_ENABLED": "0",
                    "RDP_ALLOW_IDLE_SLEEP": "1",
                    "RDP_AUDIO_LOCAL": localAudioEnabled ? "1" : "0"
                ],
                isolatedTmpDirectory: FileManager.default.temporaryDirectory
            )

            let errPipe = Pipe()
            let errHandle = errPipe.fileHandleForReading
            let errBuffer = BoundedPipeBuffer(maxBytes: 8_192)
            errBuffer.attach(to: errHandle)
            child.standardError = errPipe
            child.standardOutput = FileHandle.nullDevice
            child.terminationHandler = { [weak self] finished in
                let msg = errBuffer.drainAndDetach(from: errHandle)
                guard let self else { return }
                let stillExpected = self.lock.withLock { () -> Bool in
                    let wasCurrent = (self.process === finished)
                    if wasCurrent {
                        self.process = nil
                        self.processPGID = 0
                        self.activeErrHandle = nil
                        self.activeErrBuffer = nil
                        LumaLinkRdpProcessGuard.removePidRecord(in: certDir)
                    }
                    return wasCurrent && self._enabled
                }
                if stillExpected && finished.terminationStatus != 0 {
                    self.lock.withLock {
                        self._lastError = msg.isEmpty ? "RDP 引擎退出 (\(finished.terminationStatus))" : msg
                    }
                }
                self.notifyStatusChanged()
            }

            try child.run()
            let pid = child.processIdentifier
            _ = Darwin.setpgid(pid, pid)
            let pgid = LumaLinkRdpProcessGuard.processGroupID(for: pid)
            lock.withLock {
                process = child
                processPGID = pgid
                activeErrHandle = errHandle
                activeErrBuffer = errBuffer
                _lastError = nil
            }
            LumaLinkRdpProcessGuard.writePidRecord(
                LumaLinkRdpPidRecord(pid: pid, pgid: pgid, port: resolvedPort, binaryPath: bin),
                in: certDir
            )
            publishBonjour(port: resolvedPort)
            notifyStatusChanged()
        } catch {
            lock.withLock { _lastError = error.localizedDescription }
            notifyStatusChanged()
        }
    }

    public func cleanupOrphanedDaemonIfNeeded() {
        let exclude = lock.withLock { process?.isRunning == true ? (process?.processIdentifier ?? 0) : 0 }
        LumaLinkRdpProcessGuard.cleanupStaleProcesses(in: Self.defaultCertDirectoryURL(), excludePID: exclude)
    }

    public func stop() {
        lock.withLock { _enabled = false }
        stopChildOnly()
        cleanupOrphanedDaemonIfNeeded()
        notifyStatusChanged()
    }

    private func stopChildOnly() {
        unpublishBonjour()
        let (proc, pgid, errHandle) = lock.withLock { () -> (Process?, Int32, FileHandle?) in
            let p = process; let g = processPGID; let h = activeErrHandle
            process = nil; processPGID = 0; activeErrHandle = nil; activeErrBuffer = nil
            return (p, g, h)
        }
        if let errHandle {
            errHandle.readabilityHandler = nil
            try? errHandle.close()
        }
        if let proc, proc.isRunning {
            LumaLinkRdpProcessGuard.terminateProcessAndGroup(pid: proc.processIdentifier, pgid: pgid)
        }
        LumaLinkRdpProcessGuard.removePidRecord(in: Self.defaultCertDirectoryURL())
    }

    private func publishBonjour(port: UInt16) {
        lock.withLock {
            if let existing = dnsServiceRef {
                DNSServiceRefDeallocate(existing)
                dnsServiceRef = nil
            }
            var ref: DNSServiceRef?
            let hostName = Host.current().localizedName ?? "Mac"
            let err = DNSServiceRegister(&ref, 0, 0, hostName, "_rdp._tcp.", "local.", nil, port.bigEndian, 0, nil, nil, nil)
            if err == DNSServiceErrorType(kDNSServiceErr_NoError) {
                dnsServiceRef = ref
            }
        }
    }

    private func unpublishBonjour() {
        lock.withLock {
            if let existing = dnsServiceRef {
                DNSServiceRefDeallocate(existing)
                dnsServiceRef = nil
            }
        }
    }

    private func notifyStatusChanged() {
        guard let cb = onStatusChanged else { return }
        Task { @MainActor in cb() }
    }
}

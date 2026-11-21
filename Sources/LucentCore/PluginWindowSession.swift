import Darwin
import Foundation
import LucentFoundation

/// 绑定到插件自由窗口生命周期的沙箱化 NDJSON 会话子进程（单窗最多 1 个；关窗或禁用插件即强杀进程组，零后台常驻）。
public final class PluginWindowSessionProcess: @unchecked Sendable {
    public static let maxLineBytes = 262_144
    private static let maxStderrBytes = 8_192

    public let pluginID: String
    private let lock = NSLock()
    private let writeQueue = DispatchQueue(label: LucentIdentifiers.scoped("plugin-session.write"), qos: .userInitiated)
    private let process: Process
    private let stdinPipe: Pipe
    private let stdoutPipe: Pipe
    private let stderrPipe: Pipe
    private let isolatedTmpDir: URL
    private let bridgeServer: PluginHostBridgeServer?
    private let pid: Int32
    private let pgid: pid_t
    private let onEventLine: @Sendable (Data) -> Void
    private let onExit: @Sendable (Int32, String) -> Void

    private var stderrBuffer = Data()
    private var isStopped = false
    private var exitDelivered = false
    private var stdinClosed = false

    public var isRunning: Bool {
        lock.withLock { !isStopped && process.isRunning }
    }

    public var processIdentifier: Int32 { pid }

    public init(
        descriptor: PluginDescriptor,
        arguments: [String] = ["--session"],
        hostContext: PluginBridgeHostContext = .default,
        pluginsRoot: URL? = nil,
        onEventLine: @escaping @Sendable (Data) -> Void,
        onExit: @escaping @Sendable (Int32, String) -> Void
    ) throws {
        guard !descriptor.isBuiltin else {
            throw LucentError.pluginExecutionFailed("内置插件不支持窗口会话子进程")
        }
        guard descriptor.isValid else {
            throw LucentError.pluginInvalid(descriptor.validationIssues.joined(separator: "；"))
        }
        let stateRoot = pluginsRoot ?? descriptor.directoryURL.deletingLastPathComponent()
        guard descriptor.isEnabled && PluginSystem.isPluginEnabled(id: descriptor.id, in: stateRoot) else {
            throw LucentError.pluginExecutionFailed("插件 '\(descriptor.displayName)' 当前已禁用")
        }

        let latestGrants = descriptor.grantedCapabilities
            .union(PluginSystem.grantedCapabilities(id: descriptor.id, in: stateRoot))
            .intersection(Set(descriptor.declaredCapabilities))
        let latestRevoked = descriptor.revokedResourceScopes
            .union(PluginSystem.revokedResourceScopes(id: descriptor.id, in: stateRoot))
        let effectiveScopes = Set(descriptor.declaredResourceScopes).subtracting(latestRevoked)

        let activeLocale = L10n.current
        let activeTheme = AppThemeConfig.load().selectedTheme
        let dataDir = PluginDataPaths.ensureDataDirectory(for: descriptor.id, pluginsRoot: stateRoot)
        let tmpDir = PluginDataPaths.ensureIsolatedTmpDirectory(for: descriptor.id, pluginsRoot: stateRoot)

        var pluginVars: [String: String] = [
            "LUCENT_LOCALE": activeLocale.rawValue,
            "LUCENT_THEME": activeTheme.rawValue,
            "LUCENT_SESSION": "1"
        ]
        if let dataDir { pluginVars["LUCENT_DATA_DIR"] = dataDir.path }

        let bridge: PluginHostBridgeServer?
        if !descriptor.declaredCapabilities.isEmpty {
            let server = try PluginHostBridgeServer(
                descriptor: descriptor,
                grantedCapabilities: latestGrants,
                hostContext: hostContext
            )
            pluginVars["LUCENT_BRIDGE_SOCK"] = server.socketPath
            pluginVars["LUCENT_BRIDGE_TOKEN"] = server.token
            bridge = server
        } else {
            bridge = nil
        }

        let entryURL = descriptor.directoryURL.appendingPathComponent(descriptor.manifest.entry).standardizedFileURL
        let bootstrapData = try PluginSystem.buildStdinContextData(
            for: descriptor,
            query: "",
            clipboardText: "",
            contextPayload: nil,
            bridgeSocketPath: bridge?.socketPath,
            bridgeToken: bridge?.token,
            grantedCapabilities: latestGrants,
            dataDirectoryURL: dataDir,
            locale: activeLocale,
            theme: activeTheme,
            in: stateRoot
        )
        let cleanEnv = PluginSandboxProfileBuilder.sanitizedEnvironment(
            pluginVariables: pluginVars,
            isolatedTmpDirectory: tmpDir
        )
        let execCmd = PluginSandboxProfileBuilder.prepareExecutionCommand(
            entryURL: entryURL,
            arguments: arguments,
            descriptor: descriptor,
            grantedScopes: effectiveScopes,
            dataDirectory: dataDir,
            isolatedTmpDirectory: tmpDir,
            stateRoot: stateRoot,
            bridgeSocketPath: bridge?.socketPath
        )

        let proc = Process()
        proc.executableURL = execCmd.executableURL
        proc.arguments = execCmd.arguments
        proc.currentDirectoryURL = descriptor.directoryURL
        proc.environment = cleanEnv

        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        _ = Darwin.fcntl(inPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)

        do {
            try proc.run()
        } catch {
            bridge?.stop()
            try? FileManager.default.removeItem(at: tmpDir)
            throw error
        }

        let childPID = proc.processIdentifier
        _ = setpgid(childPID, childPID)
        let resolvedPGID = getpgid(childPID)
        let childPGID = resolvedPGID > 1 ? resolvedPGID : childPID
        ProcessSupervisor.shared.registerExternalGroup(pid: childPID, pgid: childPGID)

        self.pluginID = descriptor.id
        self.process = proc
        self.stdinPipe = inPipe
        self.stdoutPipe = outPipe
        self.stderrPipe = errPipe
        self.isolatedTmpDir = tmpDir
        self.bridgeServer = bridge
        self.pid = childPID
        self.pgid = childPGID
        self.onEventLine = onEventLine
        self.onExit = onExit

        startOutputReaders()
        proc.terminationHandler = { [weak self] finished in
            self?.handleProcessTerminated(status: finished.terminationStatus)
        }
        _ = sendLineData(bootstrapData)
    }

    deinit {
        stop(waitGraceSeconds: 0)
    }

    @discardableResult
    public func sendLineData(_ jsonData: Data) -> Bool {
        guard !jsonData.isEmpty, jsonData.count <= Self.maxLineBytes else { return false }
        let active = lock.withLock { !isStopped && !stdinClosed }
        guard active else { return false }
        var framed = Data()
        framed.reserveCapacity(jsonData.count + 1)
        for byte in jsonData where byte != 0x0A && byte != 0x0D {
            framed.append(byte)
        }
        framed.append(0x0A)
        let payload = framed
        let writeHandle = stdinPipe.fileHandleForWriting
        writeQueue.async { [weak self] in
            guard let self, self.lock.withLock({ !self.isStopped && !self.stdinClosed }) else { return }
            Self.writeAll(payload, to: writeHandle)
        }
        return true
    }

    public func stop(waitGraceSeconds: TimeInterval = 0.12) {
        let shouldTerminate = lock.withLock { () -> Bool in
            guard !isStopped else { return false }
            isStopped = true
            stdinClosed = true
            return true
        }
        guard shouldTerminate else { return }
        writeQueue.sync {
            try? stdinPipe.fileHandleForWriting.close()
        }
        if process.isRunning {
            ProcessCancellationHandle.terminateGroupOrPID(
                pid: pid,
                pgid: pgid,
                waitGraceSeconds: waitGraceSeconds
            )
        }
        cleanupResources()
    }

    private func startOutputReaders() {
        let outHandle = stdoutPipe.fileHandleForReading
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            defer { try? outHandle.close() }
            let fd = outHandle.fileDescriptor
            var buf = [UInt8](repeating: 0, count: 4_096)
            var pending = Data()
            while true {
                let n = Darwin.read(fd, &buf, buf.count)
                if n < 0 && errno == EINTR { continue }
                if n <= 0 { break }
                pending.append(contentsOf: buf.prefix(n))
                while let nl = pending.firstIndex(of: 0x0A) {
                    let line = Data(pending[..<nl])
                    pending.removeSubrange(...nl)
                    guard let self, !self.lock.withLock({ self.isStopped }) else { return }
                    if !line.isEmpty && line.count <= Self.maxLineBytes {
                        self.onEventLine(line)
                    }
                }
                if pending.count > Self.maxLineBytes {
                    pending.removeAll(keepingCapacity: false)
                }
            }
        }

        let errHandle = stderrPipe.fileHandleForReading
        DispatchQueue.global(qos: .utility).async { [weak self] in
            defer { try? errHandle.close() }
            let fd = errHandle.fileDescriptor
            var buf = [UInt8](repeating: 0, count: 4_096)
            while true {
                let n = Darwin.read(fd, &buf, buf.count)
                if n < 0 && errno == EINTR { continue }
                if n <= 0 { break }
                self?.appendStderr(Data(buf.prefix(n)))
            }
        }
    }

    private func appendStderr(_ chunk: Data) {
        lock.withLock {
            stderrBuffer.append(chunk)
            if stderrBuffer.count > Self.maxStderrBytes {
                stderrBuffer.removeFirst(stderrBuffer.count - Self.maxStderrBytes)
            }
        }
    }

    private func handleProcessTerminated(status: Int32) {
        let (shouldNotify, stderrText) = lock.withLock { () -> (Bool, String) in
            stdinClosed = true
            guard !exitDelivered else { return (false, "") }
            exitDelivered = true
            let text = String(data: stderrBuffer, encoding: .utf8) ?? ""
            return (!isStopped, text)
        }
        cleanupResources()
        if shouldNotify {
            onExit(status, stderrText)
        }
    }

    private func cleanupResources() {
        ProcessSupervisor.shared.unregisterExternalGroup(pid: pid)
        bridgeServer?.stop()
        try? FileManager.default.removeItem(at: isolatedTmpDir)
    }

    private static func writeAll(_ data: Data, to handle: FileHandle) {
        let fd = handle.fileDescriptor
        guard fd >= 0 else { return }
        data.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            var offset = 0
            while offset < ptr.count {
                let written = Darwin.write(fd, base.advanced(by: offset), min(16_384, ptr.count - offset))
                if written > 0 { offset += written }
                else if written < 0 && errno == EINTR { continue }
                else { break }
            }
        }
    }
}

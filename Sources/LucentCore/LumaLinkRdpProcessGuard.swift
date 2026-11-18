import Darwin
import Foundation
import LucentFoundation

public final class BoundedPipeBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let maxBytes: Int
    private var storage = Data()

    public init(maxBytes: Int = 8_192) {
        self.maxBytes = max(256, maxBytes)
    }

    public func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.withLock {
            storage.append(chunk)
            if storage.count > maxBytes {
                storage.removeFirst(storage.count - maxBytes)
            }
        }
    }

    public func attach(to handle: FileHandle) {
        handle.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            if data.isEmpty {
                fh.readabilityHandler = nil
                return
            }
            self?.append(data)
        }
    }

    public func drainAndDetach(from handle: FileHandle) -> String {
        handle.readabilityHandler = nil
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            append(chunk)
        }
        try? handle.close()
        return snapshotString()
    }

    public func snapshotString() -> String {
        lock.withLock {
            String(data: storage, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
    }
}

public struct LumaLinkRdpPidRecord: Codable, Sendable, Equatable {
    public let pid: Int32
    public let pgid: Int32
    public let ownerPID: Int32
    public let port: UInt16
    public let binaryPath: String
    public let startedAt: TimeInterval

    public init(
        pid: Int32,
        pgid: Int32,
        ownerPID: Int32 = ProcessInfo.processInfo.processIdentifier,
        port: UInt16,
        binaryPath: String,
        startedAt: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.pid = pid
        self.pgid = pgid
        self.ownerPID = ownerPID
        self.port = port
        self.binaryPath = binaryPath
        self.startedAt = startedAt
    }
}

public enum LumaLinkRdpProcessGuard {
    public static func pidFileURL(in certDir: URL) -> URL {
        certDir.appendingPathComponent("rdp-daemon.pid", isDirectory: false)
    }

    public static func writePidRecord(_ record: LumaLinkRdpPidRecord, in certDir: URL) {
        AtomicJSONStore.save(record, to: pidFileURL(in: certDir), formatting: [.sortedKeys])
    }

    public static func readPidRecord(in certDir: URL) -> LumaLinkRdpPidRecord? {
        AtomicJSONStore.decode(LumaLinkRdpPidRecord.self, from: pidFileURL(in: certDir))
    }

    public static func removePidRecord(in certDir: URL) {
        try? FileManager.default.removeItem(at: pidFileURL(in: certDir))
    }

    public static func isProcessAlive(_ pid: Int32) -> Bool {
        guard pid > 1 else { return false }
        if Darwin.kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    public static func processGroupID(for pid: Int32) -> Int32 {
        let pgid = Darwin.getpgid(pid)
        return pgid > 1 ? pgid : pid
    }

    public static func executablePath(for pid: Int32) -> String? {
        guard pid > 1 else { return nil }
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let len = proc_pidpath(pid, &buf, UInt32(buf.count))
        guard len > 0 else { return nil }
        let bytes = buf.prefix(Int(len)).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    public static func parentPID(for pid: Int32) -> Int32? {
        guard pid > 1 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let rc = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
        guard rc == size else { return nil }
        return Int32(info.pbi_ppid)
    }

    public static func isLucentOwnedDaemonPath(_ path: String) -> Bool {
        guard !path.isEmpty, URL(fileURLWithPath: path).lastPathComponent == "macos-rdp-daemon" else {
            return false
        }
        if path.contains("/Lucent.app/Contents/Helpers/macos-rdp-daemon")
            || path.contains("/Lucent.app/Contents/Resources/macos-rdp-daemon")
            || path.contains("/Library/Application Support/Lucent/Remote/macos-rdp-daemon") {
            return true
        }
        let homeLocal = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/lucent/macos-rdp-daemon").path
        if path == homeLocal { return true }
        if path == Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/macos-rdp-daemon").path {
            return true
        }
        if let shared = Bundle.main.sharedSupportURL?.appendingPathComponent("macos-rdp-daemon").path, path == shared {
            return true
        }
        return false
    }

    public static func terminateProcessAndGroup(pid: Int32, pgid: Int32, graceSeconds: TimeInterval = 0.45) {
        guard pid > 1 else { return }
        let ownPGID = getpgrp()
        let resolvedPGID = pgid > 1 ? pgid : processGroupID(for: pid)
        let useGroup = resolvedPGID > 1 && resolvedPGID != ownPGID

        if useGroup { _ = Darwin.kill(-resolvedPGID, SIGTERM) }
        _ = Darwin.kill(pid, SIGTERM)

        let deadline = Date().addingTimeInterval(max(0, graceSeconds))
        while isProcessAlive(pid) && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if isProcessAlive(pid) {
            if useGroup { _ = Darwin.kill(-resolvedPGID, SIGKILL) }
            _ = Darwin.kill(pid, SIGKILL)
            let killDeadline = Date().addingTimeInterval(0.15)
            while isProcessAlive(pid) && Date() < killDeadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
    }

    public static func cleanupStaleProcesses(in certDir: URL, excludePID: Int32 = 0) {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        if let record = readPidRecord(in: certDir) {
            let ownedByOtherLiveHost = record.ownerPID > 1 && record.ownerPID != selfPID && isProcessAlive(record.ownerPID)
            if !ownedByOtherLiveHost {
                if record.pid > 1, record.pid != excludePID, isProcessAlive(record.pid),
                   let path = executablePath(for: record.pid),
                   URL(fileURLWithPath: path).lastPathComponent == "macos-rdp-daemon" {
                    terminateProcessAndGroup(pid: record.pid, pgid: record.pgid)
                }
                removePidRecord(in: certDir)
            }
        }

        let byteCount = proc_listallpids(nil, 0)
        guard byteCount > 0 else { return }
        let capacity = Int(byteCount) / MemoryLayout<pid_t>.size + 64
        var pids = [pid_t](repeating: 0, count: capacity)
        let actualBytes = pids.withUnsafeMutableBytes { buf -> Int32 in
            guard let base = buf.baseAddress else { return 0 }
            return proc_listallpids(base, Int32(buf.count))
        }
        guard actualBytes > 0 else { return }
        let count = Int(actualBytes) / MemoryLayout<pid_t>.size
        for pid in pids.prefix(count) {
            guard pid > 1, pid != excludePID, pid != selfPID else { continue }
            guard parentPID(for: pid) == 1,
                  let path = executablePath(for: pid),
                  isLucentOwnedDaemonPath(path)
            else { continue }
            terminateProcessAndGroup(pid: pid, pgid: processGroupID(for: pid))
        }
    }
}

extension LumaLinkRdpSidecarService {
    public static func ensureSelfSignedCertificate(in dir: URL = defaultCertDirectoryURL()) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let keyURL = dir.appendingPathComponent("server.key")
        let crtURL = dir.appendingPathComponent("server.crt")
        if fm.fileExists(atPath: keyURL.path), fm.fileExists(atPath: crtURL.path) {
            return
        }
        let result = try ProcessSupervisor.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/openssl"),
            arguments: [
                "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                "-keyout", keyURL.path,
                "-out", crtURL.path,
                "-days", "3650",
                "-subj", "/CN=LumaLinkRDP"
            ],
            environment: ["PATH": "/usr/bin:/bin", "TMPDIR": fm.temporaryDirectory.path],
            inheritHostEnvironment: false,
            timeoutSeconds: 10.0,
            maxOutputBytes: 8_192
        )
        if result.timedOut || result.exitCode != 0 {
            let errText = result.stderr.isEmpty ? "openssl 生成证书失败 (\(result.exitCode))" : result.stderr
            throw NSError(domain: "LumaLinkRdpSidecar", code: Int(result.exitCode), userInfo: [NSLocalizedDescriptionKey: errText])
        }
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
    }

    public static func queryDaemonPermissions(binaryPath: String) -> (screenRecording: Bool, accessibility: Bool) {
        guard let result = try? ProcessSupervisor.shared.run(
            executableURL: URL(fileURLWithPath: binaryPath),
            arguments: ["--check-permissions"],
            environment: ["PATH": "/usr/bin:/bin", "HOME": FileManager.default.homeDirectoryForCurrentUser.path],
            inheritHostEnvironment: false,
            timeoutSeconds: 3.0,
            maxOutputBytes: 4_096
        ), !result.timedOut else {
            return (false, false)
        }
        return parsePermissionOutput(result.stdout)
    }

    public static func parsePermissionOutput(_ output: String) -> (screenRecording: Bool, accessibility: Bool) {
        let lines = output.split(whereSeparator: \.isNewline).map { String($0) }
        let sr = lines.contains { $0.trimmingCharacters(in: .whitespaces) == "screen_recording=granted" }
        let ax = lines.contains { $0.trimmingCharacters(in: .whitespaces) == "accessibility=granted" }
        return (sr, ax)
    }
}

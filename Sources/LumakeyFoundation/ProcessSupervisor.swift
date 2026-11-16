import Darwin
import Dispatch
import Foundation

public struct ProcessRunResult: Sendable, Hashable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let durationMs: Int
    public let timedOut: Bool
    public let wasCancelled: Bool

    public init(exitCode: Int32, stdout: String, stderr: String, durationMs: Int, timedOut: Bool, wasCancelled: Bool = false) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.durationMs = durationMs
        self.timedOut = timedOut
        self.wasCancelled = wasCancelled
    }
}

public final class ProcessSupervisor: @unchecked Sendable {
    public static let shared = ProcessSupervisor()

    private let lock = NSLock()
    private var activeGroups: [Int32: pid_t] = [:]

    private init() {}

    public var activeCount: Int {
        lock.withLock { activeGroups.count }
    }

    public func run(
        executableURL: URL,
        arguments: [String] = [],
        currentDirectoryURL: URL? = nil,
        environment: [String: String]? = nil,
        inheritHostEnvironment: Bool = true,
        stdinData: Data? = nil,
        timeoutSeconds: Double = 8.0,
        maxOutputBytes: Int = 65_536,
        cancellationHandle: ProcessCancellationHandle? = nil
    ) throws -> ProcessRunResult {
        if cancellationHandle?.isCancelled == true {
            return ProcessRunResult(exitCode: 15, stdout: "", stderr: "", durationMs: 0, timedOut: false, wasCancelled: true)
        }
        let started = ContinuousClock.now
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        if !inheritHostEnvironment {
            process.environment = environment ?? [:]
        } else if let environment, !environment.isEmpty {
            var merged = ProcessInfo.processInfo.environment
            for (k, v) in environment { merged[k] = v }
            process.environment = merged
        }

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        _ = Darwin.fcntl(stdinPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)

        try process.run()
        let pid = process.processIdentifier
        _ = setpgid(pid, pid)
        let resolvedPGID = getpgid(pid)
        let pgid = resolvedPGID > 1 ? resolvedPGID : pid
        lock.withLock { activeGroups[pid] = pgid }
        cancellationHandle?.bind(pid: pid, pgid: pgid)

        let timeoutFlag = LockedBox(false)
        let timerItem = DispatchWorkItem { [weak self] in
            timeoutFlag.withValue { $0 = true }
            ProcessCancellationHandle.terminateGroupOrPID(pid: pid, pgid: pgid)
            self?.removePID(pid)
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeoutSeconds, execute: timerItem)

        defer {
            timerItem.cancel()
            removePID(pid)
        }

        let outBox = LockedBox(Data())
        let errBox = LockedBox(Data())
        let ioGroup = DispatchGroup()

        // 先启动 stdout / stderr 异步排空读取，再异步流式写入 stdin，彻底消除 >64KB 双向管道互锁死锁
        ioGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let chunk = Self.readBoundedAndDrain(handle: stdoutPipe.fileHandleForReading, maxBytes: maxOutputBytes)
            outBox.withValue { $0 = chunk }
            ioGroup.leave()
        }

        ioGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let chunk = Self.readBoundedAndDrain(handle: stderrPipe.fileHandleForReading, maxBytes: maxOutputBytes)
            errBox.withValue { $0 = chunk }
            ioGroup.leave()
        }

        let writeHandle = stdinPipe.fileHandleForWriting
        if let stdinData, !stdinData.isEmpty {
            ioGroup.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer {
                    try? writeHandle.close()
                    ioGroup.leave()
                }
                Self.writeAllSafely(stdinData, to: writeHandle)
            }
        } else {
            try? writeHandle.close()
        }

        process.waitUntilExit()
        ioGroup.wait()

        let elapsed = started.duration(to: .now)
        let ms = Int(elapsed.components.seconds * 1000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
        return ProcessRunResult(
            exitCode: process.terminationStatus,
            stdout: String(data: outBox.snapshot(), encoding: .utf8) ?? "",
            stderr: String(data: errBox.snapshot(), encoding: .utf8) ?? "",
            durationMs: ms,
            timedOut: timeoutFlag.snapshot(),
            wasCancelled: cancellationHandle?.isCancelled ?? false
        )
    }

    public func terminateAll(waitGracePeriodSeconds: TimeInterval = 0) {
        let snapshot = lock.withLock {
            let copy = activeGroups
            activeGroups.removeAll()
            return copy
        }
        let entries = snapshot.filter { $0.key > 0 }
        guard !entries.isEmpty else { return }
        if waitGracePeriodSeconds <= 0 {
            for (pid, pgid) in entries {
                ProcessCancellationHandle.terminateGroupOrPID(pid: pid, pgid: pgid)
            }
            return
        }
        let ownPGID = getpgrp()
        for (pid, pgid) in entries {
            if pgid > 1 && pgid != ownPGID { _ = kill(-pgid, SIGTERM) }
            _ = kill(pid, SIGTERM)
        }
        let deadline = Date().addingTimeInterval(waitGracePeriodSeconds)
        while Date() < deadline && entries.contains(where: { kill($0.key, 0) == 0 || errno == EPERM }) {
            Thread.sleep(forTimeInterval: 0.015)
        }
        for (pid, pgid) in entries where kill(pid, 0) == 0 || errno == EPERM {
            if pgid > 1 && pgid != ownPGID { _ = kill(-pgid, SIGKILL) }
            _ = kill(pid, SIGKILL)
        }
    }

    private func removePID(_ pid: Int32) {
        lock.withLock { _ = activeGroups.removeValue(forKey: pid) }
    }

    private static func writeAllSafely(_ data: Data, to handle: FileHandle) {
        let fd = handle.fileDescriptor
        guard fd >= 0 else { return }
        data.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            var offset = 0
            while offset < ptr.count {
                let step = min(16_384, ptr.count - offset)
                let written = Darwin.write(fd, base.advanced(by: offset), step)
                if written > 0 {
                    offset += written
                } else if written < 0 && errno == EINTR {
                    continue
                } else {
                    break
                }
            }
        }
    }

    /// 收集前 `maxBytes` 输出后继续排空剩余管道字节直至 EOF 再关闭句柄，防止提前断管导致正常收尾的子进程收到 `SIGPIPE` 异常崩溃。
    private static func readBoundedAndDrain(handle: FileHandle, maxBytes: Int) -> Data {
        defer { try? handle.close() }
        var collected = Data()
        let safeCap = max(0, maxBytes)
        while collected.count < safeCap {
            let remaining = safeCap - collected.count
            guard let chunk = try? handle.read(upToCount: min(8_192, remaining)), !chunk.isEmpty else {
                return collected
            }
            collected.append(chunk)
        }
        while let overflow = try? handle.read(upToCount: 16_384), !overflow.isEmpty {}
        return collected
    }
}

private final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T

    init(_ value: T) {
        self.value = value
    }

    func withValue(_ mutate: (inout T) -> Void) {
        lock.withLock { mutate(&value) }
    }

    func snapshot() -> T {
        lock.withLock { value }
    }
}

public enum MemoryStats {
    public static func currentPhysicalFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / 1_048_576.0
    }

    public static func reclaimFreeHeapPages() {
        malloc_zone_pressure_relief(nil, 0)
    }
}

import Darwin
import Foundation

public final class ProcessCancellationHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var targetPID: Int32 = 0
    private var targetPGID: pid_t = 0

    public init() {}

    public var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    public func bind(pid: Int32, pgid: pid_t) {
        let shouldCancel = lock.withLock { () -> Bool in
            targetPID = pid
            targetPGID = pgid
            return cancelled
        }
        if shouldCancel {
            Self.terminateGroupOrPID(pid: pid, pgid: pgid)
        }
    }

    public func cancel() {
        let (pid, pgid) = lock.withLock { () -> (Int32, pid_t) in
            cancelled = true
            return (targetPID, targetPGID)
        }
        if pid > 0 {
            Self.terminateGroupOrPID(pid: pid, pgid: pgid)
        }
    }

    public static func terminateGroupOrPID(pid: Int32, pgid: pid_t, waitGraceSeconds: TimeInterval = 0) {
        let ownPGID = getpgrp()
        let useGroup = pgid > 1 && pgid != ownPGID
        if useGroup {
            _ = kill(-pgid, SIGTERM)
        }
        if pid > 0 {
            _ = kill(pid, SIGTERM)
        }
        let forceKill: @Sendable () -> Void = {
            if useGroup { _ = kill(-pgid, SIGKILL) }
            if pid > 0 { _ = kill(pid, SIGKILL) }
        }
        if waitGraceSeconds > 0 {
            let deadline = Date().addingTimeInterval(waitGraceSeconds)
            while pid > 0 && (kill(pid, 0) == 0 || errno == EPERM) && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.015)
            }
            if pid > 0 && (kill(pid, 0) == 0 || errno == EPERM) {
                forceKill()
            }
        } else {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.15, execute: forceKill)
        }
    }
}

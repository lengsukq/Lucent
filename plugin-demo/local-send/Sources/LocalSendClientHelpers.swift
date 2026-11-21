import Foundation
import IOKit.pwr_mgt

struct LocalSendPreparedFile {
    let meta: LocalSendFileMetadata
    let fileURL: URL?
    let inlineData: Data?
}

final class LockedStringBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    func set(_ next: String?) { lock.withLock { value = next } }
    func get() -> String? { lock.withLock { value } }
}

final class LocalSendUploadProgressDelegate: NSObject, URLSessionTaskDelegate, URLSessionDelegate, @unchecked Sendable {
    private let trust: LocalSendTrustDelegate
    private let onBytesSent: @Sendable (Int64) -> Void
    private var lastEmit: CFAbsoluteTime = 0

    init(expectedFingerprint: String?, onBytesSent: @escaping @Sendable (Int64) -> Void) {
        self.trust = LocalSendTrustDelegate(expectedFingerprint: expectedFingerprint)
        self.onBytesSent = onBytesSent
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        trust.urlSession(session, didReceive: challenge, completionHandler: completionHandler)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastEmit >= 0.1 || totalBytesSent >= totalBytesExpectedToSend {
            lastEmit = now
            onBytesSent(totalBytesSent)
        }
    }
}

enum LocalSendClientHelpers {
    static func expandPaths(_ rawPaths: [String]) -> [LocalSendPreparedFile] {
        let fm = FileManager.default
        var results: [LocalSendPreparedFile] = []
        for raw in rawPaths {
            let url = URL(fileURLWithPath: raw).standardizedFileURL
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if !isDir.boolValue {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                let fid = UUID().uuidString
                let meta = LocalSendFileMetadata(
                    id: fid, fileName: url.lastPathComponent, size: size,
                    fileType: LocalSendFileSafety.mimeType(for: url), sha256: nil, preview: nil
                )
                results.append(LocalSendPreparedFile(meta: meta, fileURL: url, inlineData: nil))
            } else if let enumerator = fm.enumerator(
                at: url, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]
            ) {
                let rootName = url.lastPathComponent
                let basePrefix = url.path.hasSuffix("/") ? url.path : url.path + "/"
                for case let child as URL in enumerator {
                    guard (try? child.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                    let rel = child.path.hasPrefix(basePrefix) ? String(child.path.dropFirst(basePrefix.count)) : child.lastPathComponent
                    let size = (try? child.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                    let fid = UUID().uuidString
                    let meta = LocalSendFileMetadata(
                        id: fid, fileName: "\(rootName)/\(rel)", size: size,
                        fileType: LocalSendFileSafety.mimeType(for: child), sha256: nil, preview: nil
                    )
                    results.append(LocalSendPreparedFile(meta: meta, fileURL: child, inlineData: nil))
                }
            }
        }
        return results
    }

    static func registerPeerOverHTTP(
        selfInfo: LocalSendDeviceInfo, ip: String, port: Int, scheme: String, timeout: TimeInterval
    ) -> LocalSendDeviceInfo? {
        guard let url = URL(string: "\(scheme)://\(ip):\(port)/api/localsend/v2/register") else { return nil }
        var me = selfInfo
        me.announce = nil
        guard let body = try? JSONEncoder().encode(me) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeout
        cfg.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: cfg, delegate: LocalSendTrustDelegate(expectedFingerprint: nil), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let sem = DispatchSemaphore(value: 0)
        var result: LocalSendDeviceInfo?
        session.dataTask(with: req) { data, resp, _ in
            defer { sem.signal() }
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200, let data else { return }
            result = try? JSONDecoder().decode(LocalSendDeviceInfo.self, from: data)
        }.resume()
        _ = sem.wait(timeout: .now() + timeout + 0.25)
        return result
    }

    static func updateSleepAssertion(active: Bool, assertionID: inout IOPMAssertionID, reason: String) {
        if active && assertionID == 0 {
            var id: IOPMAssertionID = 0
            if IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason as CFString,
                &id
            ) == kIOReturnSuccess {
                assertionID = id
            }
        } else if !active && assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
    }
}

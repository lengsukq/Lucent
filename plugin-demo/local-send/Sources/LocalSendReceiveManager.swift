import Foundation
import IOKit.pwr_mgt

struct LocalSendIncomingDecision {
    let accepted: Bool
    let acceptedFileIDs: Set<String>?
}

/// 管理 LocalSend 接收会话生命周期、流式 `.part` 写盘、原子落盘与 IOKit 防休眠守卫。
final class LocalSendReceiveManager: @unchecked Sendable {
    private final class Session {
        let sessionId: String
        let sender: LocalSendDeviceInfo
        let files: [String: LocalSendFileMetadata]
        var tokens: [String: String] = [:]
        var receivedBytesByFile: [String: Int64] = [:]
        var savedURLs: [URL] = []
        var completedFileIDs: Set<String> = []
        var activePartURLs: [String: URL] = [:]
        var activeHandles: [String: FileHandle] = [:]
        var isCancelled = false
        var lastProgressEmit: CFAbsoluteTime = 0

        init(sessionId: String, sender: LocalSendDeviceInfo, files: [String: LocalSendFileMetadata]) {
            self.sessionId = sessionId; self.sender = sender; self.files = files
        }

        var totalBytes: Int64 { files.values.reduce(0) { $0 + max(0, $1.size) } }
        var totalReceivedBytes: Int64 { receivedBytesByFile.values.reduce(0, +) }
    }

    private let lock = NSLock()
    private let queue: DispatchQueue
    private let saveDirectory: URL
    private var sessions: [String: Session] = [:]
    private var pendingPrompts: [String: (LocalSendIncomingDecision) -> Void] = [:]
    private var sleepAssertionID: IOPMAssertionID = 0

    var onIncomingPrompt: (@Sendable ([String: Any]) -> Void)?
    var onTransferProgress: (@Sendable ([String: Any]) -> Void)?
    var onTransferCompleted: (@Sendable ([String: Any]) -> Void)?

    init(saveDirectory: URL, queue: DispatchQueue) {
        self.saveDirectory = saveDirectory
        self.queue = queue
    }

    deinit { stopAll() }

    func handlePrepareUpload(
        request req: LocalSendPrepareUploadRequest,
        remoteIP: String,
        receiveMode: LocalSendReceiveMode,
        reply: @escaping (Int, Data?) -> Void
    ) {
        let sessionId = UUID().uuidString
        let session = Session(sessionId: sessionId, sender: req.info, files: req.files)
        let finishAccept: (LocalSendIncomingDecision) -> Void = { [weak self] decision in
            guard let self else { reply(500, nil); return }
            guard decision.accepted else {
                reply(403, Data("{\"message\":\"Rejected by user\"}".utf8))
                return
            }
            if let inlineText = Self.extractInlineTextIfSelfContained(req.files) {
                reply(204, nil)
                self.emitTextCompleted(sessionId: sessionId, sender: req.info, text: inlineText)
                return
            }
            var tokens: [String: String] = [:]
            for fileID in req.files.keys {
                if let allowed = decision.acceptedFileIDs, !allowed.contains(fileID) { continue }
                tokens[fileID] = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            }
            session.tokens = tokens
            self.lock.withLock { self.sessions[sessionId] = session }
            self.refreshSleepAssertion()
            let resp = LocalSendPrepareUploadResponse(sessionId: sessionId, files: tokens)
            reply(200, try? JSONEncoder().encode(resp))
        }

        if receiveMode == .quickSave {
            finishAccept(LocalSendIncomingDecision(accepted: true, acceptedFileIDs: nil))
            return
        }

        lock.withLock { pendingPrompts[sessionId] = finishAccept }
        let fileSummaries: [[String: Any]] = req.files.values.map {
            ["id": $0.id, "fileName": $0.fileName, "size": $0.size, "fileType": $0.fileType, "preview": $0.preview ?? ""]
        }
        onIncomingPrompt?([
            "type": "incomingRequest",
            "sessionId": sessionId,
            "senderAlias": req.info.alias,
            "senderModel": req.info.deviceModel ?? "",
            "remoteIP": remoteIP,
            "totalBytes": session.totalBytes,
            "files": fileSummaries
        ])
        queue.asyncAfter(deadline: .now() + LocalSendConstants.incomingPromptTimeoutSeconds) { [weak self] in
            if let expired = self?.lock.withLock({ self?.pendingPrompts.removeValue(forKey: sessionId) }) {
                expired(LocalSendIncomingDecision(accepted: false, acceptedFileIDs: nil))
            }
        }
    }

    func beginUpload(head: HTTPRequestHead) -> LocalSendHTTPConnection.UploadStartResult {
        guard let sid = head.queryItems["sessionId"],
              let fid = head.queryItems["fileId"],
              let tok = head.queryItems["token"] else {
            return .reject(status: 400, message: "Missing sessionId/fileId/token")
        }
        let (session, meta) = lock.withLock { () -> (Session?, LocalSendFileMetadata?) in
            let s = sessions[sid]
            let validTok = (s != nil && !s!.isCancelled && s!.tokens[fid] == tok)
            return (validTok ? s : nil, validTok ? s?.files[fid] : nil)
        }
        guard let session, let meta else {
            return .reject(status: 403, message: "Invalid upload token")
        }
        do {
            let finalURL = try LocalSendFileSafety.resolveUniqueDestinationURL(baseDirectory: saveDirectory, rawFileName: meta.fileName)
            let partURL = finalURL.deletingLastPathComponent()
                .appendingPathComponent(".localsend-\(UUID().uuidString.prefix(8)).part")
            FileManager.default.createFile(atPath: partURL.path, contents: nil)
            let handle = try FileHandle(forWritingTo: partURL)
            lock.withLock {
                session.activePartURLs[fid] = partURL
                session.activeHandles[fid] = handle
                session.receivedBytesByFile[fid] = 0
            }
            return .accept(
                writeChunk: { [weak self] data in
                    try handle.write(contentsOf: data)
                    self?.recordUploadChunk(session: session, fileID: fid, delta: Int64(data.count))
                },
                finish: { [weak self] success in
                    self?.finalizeUploadFile(session: session, fileID: fid, partURL: partURL, finalURL: finalURL, handle: handle, success: success)
                }
            )
        } catch {
            return .reject(status: 500, message: error.localizedDescription)
        }
    }

    func respondToIncoming(sessionId: String, accepted: Bool) {
        let cb = lock.withLock { pendingPrompts.removeValue(forKey: sessionId) }
        cb?(LocalSendIncomingDecision(accepted: accepted, acceptedFileIDs: nil))
    }

    func cancelSession(sessionId: String) {
        respondToIncoming(sessionId: sessionId, accepted: false)
        if let session = lock.withLock({ sessions.removeValue(forKey: sessionId) }) {
            abortSession(session)
        }
        refreshSleepAssertion()
    }

    func stopAll() {
        let (activeSessions, prompts) = lock.withLock { () -> ([Session], [(LocalSendIncomingDecision) -> Void]) in
            let s = Array(sessions.values); sessions.removeAll()
            let p = Array(pendingPrompts.values); pendingPrompts.removeAll()
            return (s, p)
        }
        for respond in prompts { respond(LocalSendIncomingDecision(accepted: false, acceptedFileIDs: nil)) }
        for s in activeSessions { abortSession(s) }
        releaseSleepAssertion()
    }

    private func recordUploadChunk(session: Session, fileID: String, delta: Int64) {
        let emitPair: (Int64, Int64)? = lock.withLock {
            session.receivedBytesByFile[fileID, default: 0] += delta
            let now = CFAbsoluteTimeGetCurrent()
            if now - session.lastProgressEmit >= 0.12 {
                session.lastProgressEmit = now
                return (session.totalReceivedBytes, session.totalBytes)
            }
            return nil
        }
        if let (done, total) = emitPair {
            onTransferProgress?([
                "type": "transferProgress", "direction": "receive", "sessionId": session.sessionId,
                "peerAlias": session.sender.alias, "transferredBytes": done, "totalBytes": max(total, done),
                "fraction": total > 0 ? min(1.0, Double(done) / Double(total)) : 1.0
            ])
        }
    }

    private func finalizeUploadFile(
        session: Session, fileID: String, partURL: URL, finalURL: URL, handle: FileHandle, success: Bool
    ) {
        try? handle.close()
        let doneURLs: [URL]? = lock.withLock {
            session.activeHandles.removeValue(forKey: fileID)
            session.activePartURLs.removeValue(forKey: fileID)
            guard success && !session.isCancelled else {
                try? FileManager.default.removeItem(at: partURL)
                return nil
            }
            do {
                try FileManager.default.moveItem(at: partURL, to: finalURL)
                session.savedURLs.append(finalURL)
                session.completedFileIDs.insert(fileID)
                if session.completedFileIDs.count >= session.tokens.count {
                    sessions.removeValue(forKey: session.sessionId)
                    return session.savedURLs
                }
                return nil
            } catch {
                try? FileManager.default.removeItem(at: partURL)
                return nil
            }
        }
        refreshSleepAssertion()
        if let savedURLs = doneURLs {
            onTransferCompleted?([
                "type": "transferCompleted", "direction": "receive", "sessionId": session.sessionId,
                "peerAlias": session.sender.alias, "filePaths": savedURLs.map(\.path), "totalBytes": session.totalReceivedBytes
            ])
        }
    }

    private func emitTextCompleted(sessionId: String, sender: LocalSendDeviceInfo, text: String) {
        let isURL = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { ($0.scheme == "http" || $0.scheme == "https") && $0.host != nil } ?? false
        onTransferCompleted?([
            "type": "transferCompleted", "direction": "receive", "sessionId": sessionId,
            "peerAlias": sender.alias, "text": text, "kind": isURL ? "url" : "text"
        ])
    }

    private func abortSession(_ session: Session) {
        session.isCancelled = true
        for (_, h) in session.activeHandles { try? h.close() }
        for (_, p) in session.activePartURLs { try? FileManager.default.removeItem(at: p) }
        session.activeHandles.removeAll()
        session.activePartURLs.removeAll()
    }

    private func refreshSleepAssertion() {
        lock.withLock {
            let need = !sessions.isEmpty
            if need && sleepAssertionID == 0 {
                var id: IOPMAssertionID = 0
                if IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Lucent LocalSend Receive" as CFString, &id) == kIOReturnSuccess {
                    sleepAssertionID = id
                }
            } else if !need && sleepAssertionID != 0 {
                IOPMAssertionRelease(sleepAssertionID)
                sleepAssertionID = 0
            }
        }
    }

    private func releaseSleepAssertion() {
        lock.withLock {
            if sleepAssertionID != 0 { IOPMAssertionRelease(sleepAssertionID); sleepAssertionID = 0 }
        }
    }

    private static func extractInlineTextIfSelfContained(_ files: [String: LocalSendFileMetadata]) -> String? {
        guard files.count == 1, let single = files.values.first,
              single.fileType.lowercased().hasPrefix("text/plain"),
              let preview = single.preview, !preview.isEmpty,
              preview.utf8.count <= LocalSendConstants.maxInlineTextPreviewBytes,
              Int64(preview.utf8.count) == single.size || single.size == 0 else { return nil }
        return preview
    }
}

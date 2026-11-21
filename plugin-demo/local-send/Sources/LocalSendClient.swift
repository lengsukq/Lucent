import Foundation
import IOKit.pwr_mgt

final class LocalSendClient: @unchecked Sendable {
    private final class ActiveSend {
        let transferId: String
        let peer: LocalSendPeer
        var sessionId: String?
        var currentTask: URLSessionTask?
        var cancelled = false
        init(transferId: String, peer: LocalSendPeer) { self.transferId = transferId; self.peer = peer }
    }

    private enum PrepareOutcome {
        case accepted(sessionId: String, tokens: [String: String])
        case acceptedNoUpload
        case pinRequired
        case failed(String)
    }

    private let lock = NSLock()
    private let selfDeviceInfoProvider: @Sendable () -> LocalSendDeviceInfo
    private let onEvent: @Sendable ([String: Any]) -> Void
    private var activeSends: [String: ActiveSend] = [:]
    private var sleepAssertionID: IOPMAssertionID = 0

    init(
        selfDeviceInfoProvider: @escaping @Sendable () -> LocalSendDeviceInfo,
        onEvent: @escaping @Sendable ([String: Any]) -> Void
    ) {
        self.selfDeviceInfoProvider = selfDeviceInfoProvider
        self.onEvent = onEvent
    }

    deinit { cancelAll() }

    func sendFiles(transferId: String, paths: [String], to peer: LocalSendPeer, pin: String?) {
        let prepared = LocalSendClientHelpers.expandPaths(paths)
        guard !prepared.isEmpty else {
            onEvent(["type": "transferFailed", "direction": "send", "transferId": transferId, "error": "没有可发送的有效文件"])
            return
        }
        startSend(transferId: transferId, items: prepared, to: peer, pin: pin)
    }

    func sendText(transferId: String, text: String, to peer: LocalSendPeer, pin: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            onEvent(["type": "transferFailed", "direction": "send", "transferId": transferId, "error": "发送文本不能为空"])
            return
        }
        let data = Data(text.utf8)
        let fid = UUID().uuidString
        let preview = data.count <= LocalSendConstants.maxInlineTextPreviewBytes ? text : String(text.prefix(1024))
        let meta = LocalSendFileMetadata(id: fid, fileName: "\(fid.prefix(8)).txt", size: Int64(data.count), fileType: "text/plain", sha256: nil, preview: preview)
        startSend(transferId: transferId, items: [LocalSendPreparedFile(meta: meta, fileURL: nil, inlineData: data)], to: peer, pin: pin)
    }

    func cancel(transferId: String) {
        let send = lock.withLock { activeSends[transferId] }
        guard let send else { return }
        send.cancelled = true
        send.currentTask?.cancel()
        if let sid = send.sessionId { sendCancelRequest(peer: send.peer, sessionId: sid) }
    }

    func cancelAll() {
        let all = lock.withLock { Array(activeSends.values) }
        for s in all { cancel(transferId: s.transferId) }
        lock.withLock { LocalSendClientHelpers.updateSleepAssertion(active: false, assertionID: &sleepAssertionID, reason: "Lucent LocalSend Upload") }
    }

    private func startSend(transferId: String, items: [LocalSendPreparedFile], to peer: LocalSendPeer, pin: String?) {
        let state = ActiveSend(transferId: transferId, peer: peer)
        lock.withLock {
            activeSends[transferId] = state
            LocalSendClientHelpers.updateSleepAssertion(active: true, assertionID: &sleepAssertionID, reason: "Lucent LocalSend Upload")
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            defer {
                self.lock.withLock {
                    _ = self.activeSends.removeValue(forKey: transferId)
                    LocalSendClientHelpers.updateSleepAssertion(active: !self.activeSends.isEmpty, assertionID: &self.sleepAssertionID, reason: "Lucent LocalSend Upload")
                }
            }
            self.runSendLifecycle(state: state, items: items, pin: pin)
        }
    }

    private func runSendLifecycle(state: ActiveSend, items: [LocalSendPreparedFile], pin: String?) {
        let totalBytes = items.reduce(Int64(0)) { $0 + max(0, $1.meta.size) }
        onEvent([
            "type": "transferProgress", "direction": "send", "transferId": state.transferId,
            "peerAlias": state.peer.alias, "status": "waiting", "transferredBytes": 0, "totalBytes": totalBytes, "fraction": 0.0
        ])
        var filesDict: [String: LocalSendFileMetadata] = [:]
        for item in items { filesDict[item.meta.id] = item.meta }
        let prepReq = LocalSendPrepareUploadRequest(info: selfDeviceInfoProvider(), files: filesDict)
        switch performPrepareUpload(state: state, request: prepReq, pin: pin) {
        case .acceptedNoUpload:
            onEvent(completedPayload(state: state, items: items, totalBytes: totalBytes, fileCount: items.count))
        case .pinRequired:
            onEvent(["type": "transferPinRequired", "direction": "send", "transferId": state.transferId, "peerFingerprint": state.peer.fingerprint, "peerAlias": state.peer.alias])
        case .failed(let msg):
            onEvent(["type": "transferFailed", "direction": "send", "transferId": state.transferId, "peerAlias": state.peer.alias, "error": msg])
        case .accepted(let sessionId, let tokens):
            state.sessionId = sessionId
            uploadApprovedItems(state: state, sessionId: sessionId, tokens: tokens, items: items, totalBytes: totalBytes)
        }
    }

    private func uploadApprovedItems(
        state: ActiveSend, sessionId: String, tokens: [String: String], items: [LocalSendPreparedFile], totalBytes: Int64
    ) {
        var completedBytes: Int64 = 0
        var uploadedCount = 0
        for item in items {
            if state.cancelled {
                onEvent(["type": "transferFailed", "direction": "send", "transferId": state.transferId, "peerAlias": state.peer.alias, "error": "已取消发送"])
                return
            }
            guard let token = tokens[item.meta.id] else { continue }
            let baseDone = completedBytes
            let err = uploadSingleItem(state: state, sessionId: sessionId, token: token, item: item) { sentInFile in
                let agg = baseDone + sentInFile
                let frac = totalBytes > 0 ? min(1.0, Double(agg) / Double(totalBytes)) : 1.0
                self.onEvent([
                    "type": "transferProgress", "direction": "send", "transferId": state.transferId,
                    "peerAlias": state.peer.alias, "status": "sending", "fileName": item.meta.fileName,
                    "transferredBytes": agg, "totalBytes": totalBytes, "fraction": frac
                ])
            }
            if let err {
                onEvent(["type": "transferFailed", "direction": "send", "transferId": state.transferId, "peerAlias": state.peer.alias, "error": err])
                return
            }
            completedBytes += item.meta.size
            uploadedCount += 1
        }
        onEvent(completedPayload(state: state, items: items, totalBytes: totalBytes, fileCount: uploadedCount))
    }

    private func completedPayload(
        state: ActiveSend, items: [LocalSendPreparedFile], totalBytes: Int64, fileCount: Int
    ) -> [String: Any] {
        var ev: [String: Any] = [
            "type": "transferCompleted",
            "direction": "send",
            "transferId": state.transferId,
            "peerAlias": state.peer.alias,
            "totalBytes": totalBytes,
            "fileCount": fileCount
        ]
        let paths = items.compactMap { $0.fileURL?.path }
        if !paths.isEmpty {
            ev["filePaths"] = paths
        } else if let data = items.first?.inlineData, let txt = String(data: data, encoding: .utf8), !txt.isEmpty {
            ev["text"] = txt
        }
        return ev
    }

    private func performPrepareUpload(state: ActiveSend, request: LocalSendPrepareUploadRequest, pin: String?) -> PrepareOutcome {
        var comps = URLComponents(string: "\(state.peer.baseURLString)/api/localsend/v2/prepare-upload")
        if let pin, !pin.isEmpty { comps?.queryItems = [URLQueryItem(name: "pin", value: pin)] }
        guard let url = comps?.url, let body = try? JSONEncoder().encode(request) else { return .failed("无法构造发送请求") }
        var urlReq = URLRequest(url: url, timeoutInterval: 65)
        urlReq.httpMethod = "POST"
        urlReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlReq.httpBody = body

        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 65
        let session = URLSession(configuration: cfg, delegate: LocalSendTrustDelegate(expectedFingerprint: state.peer.fingerprint), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let sem = DispatchSemaphore(value: 0)
        var outcome: PrepareOutcome = .failed("等待对方响应超时")
        let task = session.dataTask(with: urlReq) { data, resp, err in
            defer { sem.signal() }
            if let err { outcome = .failed(err.localizedDescription); return }
            guard let http = resp as? HTTPURLResponse else { outcome = .failed("无有效响应"); return }
            switch http.statusCode {
            case 204: outcome = .acceptedNoUpload
            case 200:
                if let data, let parsed = try? JSONDecoder().decode(LocalSendPrepareUploadResponse.self, from: data) {
                    outcome = .accepted(sessionId: parsed.sessionId, tokens: parsed.files)
                } else { outcome = .failed("对方返回了无法解析的会话数据") }
            case 401: outcome = .pinRequired
            case 403: outcome = .failed("对方拒绝了此次接收请求")
            case 409: outcome = .failed("对方正忙于其他传输，请稍后再试")
            case 429: outcome = .failed("PIN 尝试次数过多，请稍后重试")
            default: outcome = .failed("对方返回状态码 \(http.statusCode)")
            }
        }
        state.currentTask = task
        task.resume()
        _ = sem.wait(timeout: .now() + 68)
        return outcome
    }

    private func uploadSingleItem(
        state: ActiveSend, sessionId: String, token: String, item: LocalSendPreparedFile,
        onProgress: @escaping @Sendable (Int64) -> Void
    ) -> String? {
        var comps = URLComponents(string: "\(state.peer.baseURLString)/api/localsend/v2/upload")
        comps?.queryItems = [
            URLQueryItem(name: "sessionId", value: sessionId),
            URLQueryItem(name: "fileId", value: item.meta.id),
            URLQueryItem(name: "token", value: token)
        ]
        guard let url = comps?.url else { return "无效上传地址" }
        var req = URLRequest(url: url, timeoutInterval: 3600)
        req.httpMethod = "POST"
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        req.setValue("\(item.meta.size)", forHTTPHeaderField: "Content-Length")

        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 300
        cfg.timeoutIntervalForResource = 3600
        let delegate = LocalSendUploadProgressDelegate(expectedFingerprint: state.peer.fingerprint, onBytesSent: onProgress)
        let session = URLSession(configuration: cfg, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let sem = DispatchSemaphore(value: 0)
        let box = LockedStringBox()
        let completion: @Sendable (Data?, URLResponse?, Error?) -> Void = { _, resp, err in
            defer { sem.signal() }
            if let err { box.set(err.localizedDescription); return }
            guard let http = resp as? HTTPURLResponse else { box.set("上传无响应"); return }
            if http.statusCode != 200 && http.statusCode != 204 { box.set("上传失败（HTTP \(http.statusCode)）") }
        }
        let task = item.fileURL.map { session.uploadTask(with: req, fromFile: $0, completionHandler: completion) }
            ?? session.uploadTask(with: req, from: item.inlineData ?? Data(), completionHandler: completion)
        state.currentTask = task
        task.resume()
        _ = sem.wait(timeout: .distantFuture)
        return box.get()
    }

    private func sendCancelRequest(peer: LocalSendPeer, sessionId: String) {
        var comps = URLComponents(string: "\(peer.baseURLString)/api/localsend/v2/cancel")
        comps?.queryItems = [URLQueryItem(name: "sessionId", value: sessionId)]
        guard let url = comps?.url else { return }
        var req = URLRequest(url: url, timeoutInterval: 3)
        req.httpMethod = "POST"
        let session = URLSession(configuration: .ephemeral, delegate: LocalSendTrustDelegate(expectedFingerprint: peer.fingerprint), delegateQueue: nil)
        session.dataTask(with: req) { _, _, _ in session.finishTasksAndInvalidate() }.resume()
    }
}

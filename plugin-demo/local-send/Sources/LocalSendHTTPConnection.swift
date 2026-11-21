import Foundation
import Network

/// 面向单条 `NWConnection` 的流式 HTTP/1.1 请求处理器。
final class LocalSendHTTPConnection: @unchecked Sendable {
    private static let maxHeaderBytes = 32_768
    private static let maxControlBodyBytes = 2_097_152

    enum UploadStartResult {
        case accept(writeChunk: (Data) throws -> Void, finish: (Bool) -> Void)
        case reject(status: Int, message: String)
    }

    private let connection: NWConnection
    private let queue: DispatchQueue
    private let remoteIP: String
    private var rawBuffer = Data()
    private var head: HTTPRequestHead?
    private var uploadSink: ((Data) throws -> Void)?
    private var uploadFinish: ((Bool) -> Void)?
    private var uploadReceivedBytes: Int64 = 0
    private var chunkDecoder: HTTPChunkedDecoder?
    private var closed = false

    private let onControlRequest: (HTTPRequestHead, Data, @escaping (Int, Data?) -> Void) -> Void
    private let onUploadStart: (HTTPRequestHead) -> UploadStartResult
    private let onClosed: () -> Void

    init(
        connection: NWConnection,
        queue: DispatchQueue,
        remoteIP: String,
        onControlRequest: @escaping (HTTPRequestHead, Data, @escaping (Int, Data?) -> Void) -> Void,
        onUploadStart: @escaping (HTTPRequestHead) -> UploadStartResult,
        onClosed: @escaping () -> Void
    ) {
        self.connection = connection
        self.queue = queue
        self.remoteIP = remoteIP
        self.onControlRequest = onControlRequest
        self.onUploadStart = onUploadStart
        self.onClosed = onClosed
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] st in
            if case .failed = st { self?.abort() }
            else if case .cancelled = st { self?.abort() }
        }
        connection.start(queue: queue)
        receiveNext()
    }

    private func receiveNext() {
        guard !closed else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, err in
            guard let self, !self.closed else { return }
            if let data, !data.isEmpty { self.consumeBytes(data) }
            if self.closed { return }
            if err != nil { self.abort(); return }
            if isComplete { self.handleEOF() } else { self.receiveNext() }
        }
    }

    private func consumeBytes(_ chunk: Data) {
        if let head {
            if head.path == "/api/localsend/v2/upload" {
                feedUploadBody(chunk, head: head)
            } else {
                rawBuffer.append(chunk)
                if rawBuffer.count > Self.maxControlBodyBytes {
                    sendResponse(status: 413, body: Data("{\"message\":\"Payload too large\"}".utf8))
                    return
                }
                checkControlComplete(head: head)
            }
            return
        }

        rawBuffer.append(chunk)
        let sep = Data("\r\n\r\n".utf8)
        guard let range = rawBuffer.range(of: sep) else {
            if rawBuffer.count > Self.maxHeaderBytes { sendResponse(status: 431, body: nil) }
            return
        }
        let headerData = Data(rawBuffer[..<range.lowerBound])
        let remainder = Data(rawBuffer[range.upperBound...])
        rawBuffer.removeAll(keepingCapacity: false)

        guard let parsed = LocalSendHTTPParser.parseHead(headerData, remoteIP: remoteIP) else {
            sendResponse(status: 400, body: Data("{\"message\":\"Malformed HTTP request\"}".utf8))
            return
        }
        self.head = parsed

        if parsed.headers["expect"]?.lowercased() == "100-continue" {
            connection.send(content: Data("HTTP/1.1 100 Continue\r\n\r\n".utf8), completion: .idempotent)
        }

        if parsed.path == "/api/localsend/v2/upload" {
            switch onUploadStart(parsed) {
            case .reject(let code, let msg):
                let body = (try? JSONSerialization.data(withJSONObject: ["message": msg])) ?? Data()
                sendResponse(status: code, body: body)
            case .accept(let writer, let finish):
                uploadSink = writer
                uploadFinish = finish
                if parsed.isChunked { chunkDecoder = HTTPChunkedDecoder() }
                if !remainder.isEmpty { feedUploadBody(remainder, head: parsed) }
                else if !parsed.isChunked, parsed.contentLength == 0 { completeUpload(success: true) }
            }
        } else {
            rawBuffer = remainder
            checkControlComplete(head: parsed)
        }
    }

    private func checkControlComplete(head: HTTPRequestHead) {
        if head.isChunked {
            var decoder = chunkDecoder ?? HTTPChunkedDecoder()
            var assembled = Data()
            decoder.pending.append(rawBuffer)
            rawBuffer.removeAll()
            do {
                try decoder.drain { assembled.append($0) }
                chunkDecoder = decoder
                if decoder.finished { dispatchControl(head: head, body: assembled) }
            } catch {
                sendResponse(status: 400, body: nil)
            }
            return
        }
        let expected = Int(head.contentLength ?? 0)
        if rawBuffer.count >= expected {
            dispatchControl(head: head, body: Data(rawBuffer.prefix(expected)))
        }
    }

    private func dispatchControl(head: HTTPRequestHead, body: Data) {
        onControlRequest(head, body) { [weak self] status, responseBody in
            self?.sendResponse(status: status, body: responseBody)
        }
    }

    private func feedUploadBody(_ data: Data, head: HTTPRequestHead) {
        guard let sink = uploadSink else { return }
        do {
            if head.isChunked {
                var decoder = chunkDecoder ?? HTTPChunkedDecoder()
                decoder.pending.append(data)
                try decoder.drain { chunk in
                    self.uploadReceivedBytes += Int64(chunk.count)
                    try sink(chunk)
                }
                chunkDecoder = decoder
                if decoder.finished { completeUpload(success: true) }
            } else {
                var slice = data
                if let expected = head.contentLength {
                    let remain = Int(max(0, expected - uploadReceivedBytes))
                    if slice.count > remain { slice = Data(slice.prefix(remain)) }
                }
                if !slice.isEmpty {
                    uploadReceivedBytes += Int64(slice.count)
                    try sink(slice)
                }
                if let expected = head.contentLength, uploadReceivedBytes >= expected {
                    completeUpload(success: true)
                }
            }
        } catch {
            completeUpload(success: false, errorStatus: 500)
        }
    }

    private func handleEOF() {
        if let head, head.path == "/api/localsend/v2/upload" {
            let ok = !head.isChunked && (head.contentLength == nil || uploadReceivedBytes >= (head.contentLength ?? 0))
            completeUpload(success: ok, errorStatus: ok ? 200 : 499)
        } else if let head {
            dispatchControl(head: head, body: rawBuffer)
        } else {
            abort()
        }
    }

    private func completeUpload(success: Bool, errorStatus: Int = 500) {
        let fin = uploadFinish
        uploadSink = nil
        uploadFinish = nil
        fin?(success)
        if success { sendResponse(status: 200, body: nil) }
        else { sendResponse(status: errorStatus, body: Data("{\"message\":\"Upload interrupted\"}".utf8)) }
    }

    private func sendResponse(status: Int, body: Data?) {
        guard !closed else { return }
        closed = true
        let wire = LocalSendHTTPParser.buildResponseData(status: status, body: body)
        connection.send(content: wire, completion: .contentProcessed { [weak self] _ in
            guard let self else { return }
            self.connection.cancel()
            self.onClosed()
        })
    }

    func forceClose() {
        abort()
    }

    private func abort() {
        guard !closed else { return }
        closed = true
        let fin = uploadFinish
        uploadSink = nil
        uploadFinish = nil
        fin?(false)
        connection.cancel()
        onClosed()
    }
}

import Foundation

struct HTTPRequestHead: Sendable {
    let method: String
    let path: String
    let queryItems: [String: String]
    let headers: [String: String]
    let contentLength: Int64?
    let isChunked: Bool
    let remoteIP: String
}

struct HTTPChunkedDecoder {
    var pending = Data()
    var currentChunkRemaining: Int?
    var waitingTrailingCRLF = false
    var finished = false

    mutating func drain(onData: (Data) throws -> Void) throws {
        let crlf = Data("\r\n".utf8)
        while !finished {
            if waitingTrailingCRLF {
                guard pending.count >= 2 else { return }
                pending.removeFirst(2)
                waitingTrailingCRLF = false
            }
            if let rem = currentChunkRemaining {
                if rem == 0 {
                    finished = true
                    return
                }
                guard !pending.isEmpty else { return }
                let take = min(rem, pending.count)
                let slice = Data(pending.prefix(take))
                pending.removeFirst(take)
                try onData(slice)
                let left = rem - take
                if left == 0 {
                    currentChunkRemaining = nil
                    waitingTrailingCRLF = true
                } else {
                    currentChunkRemaining = left
                }
            } else {
                guard let range = pending.range(of: crlf) else { return }
                let lineData = Data(pending[..<range.lowerBound])
                pending.removeSubrange(..<range.upperBound)
                let sizeToken = (String(data: lineData, encoding: .ascii) ?? "")
                    .split(separator: ";").first?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                guard let size = Int(sizeToken, radix: 16), size >= 0 else {
                    throw NSError(domain: "LocalSendHTTP", code: 400)
                }
                currentChunkRemaining = size
                if size == 0 {
                    finished = true
                    return
                }
            }
        }
    }
}

enum LocalSendHTTPParser {
    static func parseHead(_ data: Data, remoteIP: String) -> HTTPRequestHead? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let lines = text.components(separatedBy: "\r\n")
        guard let first = lines.first else { return nil }
        let parts = first.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0]).uppercased()
        let rawTarget = String(parts[1])
        let comps = URLComponents(string: "http://localhost" + rawTarget)
        let path = comps?.path ?? rawTarget
        var query: [String: String] = [:]
        for item in comps?.queryItems ?? [] {
            if let v = item.value { query[item.name] = v }
        }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let k = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let v = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[k] = v
        }
        let contentLen = headers["content-length"].flatMap { Int64($0) }
        let isChunked = headers["transfer-encoding"]?.lowercased().contains("chunked") == true
        return HTTPRequestHead(
            method: method, path: path, queryItems: query, headers: headers,
            contentLength: contentLen, isChunked: isChunked, remoteIP: remoteIP
        )
    }

    static func buildResponseData(status: Int, body: Data?) -> Data {
        let reason: String = switch status {
        case 200: "OK"
        case 204: "No Content"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 409: "Conflict"
        case 413: "Payload Too Large"
        case 429: "Too Many Requests"
        default: "Internal Server Error"
        }
        let bodyBytes = (status == 204) ? Data() : (body ?? Data())
        var header = "HTTP/1.1 \(status) \(reason)\r\n"
        if !bodyBytes.isEmpty { header += "Content-Type: application/json; charset=utf-8\r\n" }
        header += "Content-Length: \(bodyBytes.count)\r\nConnection: close\r\n\r\n"
        var wire = Data(header.utf8)
        wire.append(bodyBytes)
        return wire
    }
}

import Foundation
import LucentCore

private final class MockWebDAVStore: @unchecked Sendable {
    static let shared = MockWebDAVStore()

    private let lock = NSLock()
    private var expectedAuthHeader: String = ""
    private var validRootPrefix: String = "/dav/"
    private var collections: Set<String> = ["/dav/"]
    private var files: [String: (data: Data, modified: Date)] = [:]
    private(set) var recordedMethods: [String] = []

    func reset(username: String, password: String, rootPrefix: String = "/dav/") {
        lock.withLock {
            let token = Data("\(username):\(password)".utf8).base64EncodedString()
            expectedAuthHeader = "Basic \(token)"
            validRootPrefix = rootPrefix
            collections = [rootPrefix]
            files = [:]
            recordedMethods = []
        }
    }

    func handle(request: URLRequest) -> (statusCode: Int, headers: [String: String], body: Data) {
        lock.withLock {
            let method = (request.httpMethod ?? "GET").uppercased()
            let rawPath = request.url?.path ?? "/"
            let isDirHint = request.url?.absoluteString.hasSuffix("/") == true
            let normDirPath = rawPath.hasSuffix("/") ? rawPath : (rawPath + "/")
            recordedMethods.append("\(method) \(isDirHint ? normDirPath : rawPath)")

            let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
            guard auth == expectedAuthHeader else {
                return (401, ["WWW-Authenticate": "Basic realm=\"MockDAV\""], Data("Unauthorized".utf8))
            }
            guard normDirPath.hasPrefix(validRootPrefix) || rawPath.hasPrefix(validRootPrefix) else {
                return (404, [:], Data("Not Found".utf8))
            }

            switch method {
            case "PROPFIND":
                let depth = request.value(forHTTPHeaderField: "Depth") ?? "1"
                guard collections.contains(normDirPath) else {
                    return (404, [:], Data("Collection Not Found".utf8))
                }
                let xml = buildMultiStatusXML(dirPath: normDirPath, depth: depth)
                return (207, ["Content-Type": "application/xml; charset=utf-8"], Data(xml.utf8))

            case "MKCOL":
                if collections.contains(normDirPath) {
                    return (405, [:], Data("Already Exists".utf8))
                }
                guard collections.contains(parentCollectionPath(of: normDirPath)) else {
                    return (409, [:], Data("Parent Missing".utf8))
                }
                collections.insert(normDirPath)
                return (201, [:], Data())

            case "PUT":
                guard collections.contains(parentCollectionPath(of: rawPath)) else {
                    return (409, [:], Data("Parent Missing".utf8))
                }
                let bodyData = Self.extractBody(from: request)
                let existed = files[rawPath] != nil
                files[rawPath] = (data: bodyData, modified: Date())
                return (existed ? 204 : 201, [:], Data())

            case "GET":
                guard let entry = files[rawPath] else {
                    return (404, [:], Data("Not Found".utf8))
                }
                return (200, ["Content-Type": "application/octet-stream"], entry.data)

            case "DELETE":
                guard files.removeValue(forKey: rawPath) != nil else {
                    return (404, [:], Data("Not Found".utf8))
                }
                return (204, [:], Data())

            default:
                return (405, [:], Data())
            }
        }
    }

    private func parentCollectionPath(of path: String) -> String {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        guard let idx = trimmed.lastIndex(of: "/") else { return "/" }
        return String(trimmed[...idx])
    }

    private func buildMultiStatusXML(dirPath: String, depth: String) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"

        var rows = """
        <?xml version="1.0" encoding="utf-8"?>
        <d:multistatus xmlns:d="DAV:">
          <d:response>
            <d:href>\(dirPath)</d:href>
            <d:propstat>
              <d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop>
              <d:status>HTTP/1.1 200 OK</d:status>
            </d:propstat>
          </d:response>
        """
        if depth != "0" {
            for (filePath, info) in files.sorted(by: { $0.key < $1.key }) {
                guard parentCollectionPath(of: filePath) == dirPath else { continue }
                let modStr = df.string(from: info.modified)
                rows += """
                  <d:response>
                    <d:href>\(filePath)</d:href>
                    <d:propstat>
                      <d:prop>
                        <d:resourcetype/>
                        <d:getcontentlength>\(info.data.count)</d:getcontentlength>
                        <d:getlastmodified>\(modStr)</d:getlastmodified>
                      </d:prop>
                      <d:status>HTTP/1.1 200 OK</d:status>
                    </d:propstat>
                  </d:response>
                """
            }
        }
        rows += "\n</d:multistatus>"
        return rows
    }

    private static func extractBody(from request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var out = Data()
        let bufSize = 16_384
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let readCount = stream.read(buffer, maxLength: bufSize)
            if readCount > 0 { out.append(buffer, count: readCount) } else { break }
        }
        return out
    }
}

private final class MockWebDAVURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let result = MockWebDAVStore.shared.handle(request: request)
        let url = request.url ?? URL(string: "https://dav.mock.local/")!
        let response = HTTPURLResponse(url: url, statusCode: result.statusCode, httpVersion: "HTTP/1.1", headerFields: result.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !result.body.isEmpty { client?.urlProtocol(self, didLoad: result.body) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class AsyncTestBox<T>: @unchecked Sendable {
    var result: Result<T, Error>?
}

private func runBlockingAsync<T>(_ block: @escaping @Sendable () async throws -> T) throws -> T {
    let sem = DispatchSemaphore(value: 0)
    let box = AsyncTestBox<T>()
    Task.detached {
        do { box.result = .success(try await block()) } catch { box.result = .failure(error) }
        sem.signal()
    }
    sem.wait()
    return try box.result!.get()
}

func verifyWebDAVClientWithMockProtocol(archiveData: Data, expectedSHA256: String) throws {
    MockWebDAVStore.shared.reset(username: "alice", password: "correct-app-password", rootPrefix: "/dav/")
    let sessionCfg = URLSessionConfiguration.ephemeral
    sessionCfg.protocolClasses = [MockWebDAVURLProtocol.self]

    try runBlockingAsync {
        let baseCfg = WebDAVConfig(
            serverURL: "https://dav.mock.local/dav/",
            username: "alice",
            remoteDirectory: "LucentBackups/MacStudio",
            keepLatestCount: 2
        )

        let badAuthClient = WebDAVClient(config: baseCfg, password: "wrong-password", sessionConfiguration: sessionCfg)
        var got401 = false
        do { _ = try await badAuthClient.testConnection() } catch WebDAVError.unauthorized(let code) { got401 = (code == 401) }
        check(got401, "WebDAVClient 401 Basic Auth rejection")

        let badPathCfg = WebDAVConfig(serverURL: "https://dav.mock.local/wrong-root/", username: "alice")
        let badPathClient = WebDAVClient(config: badPathCfg, password: "correct-app-password", sessionConfiguration: sessionCfg)
        var got404 = false
        do { _ = try await badPathClient.testConnection() } catch WebDAVError.notFound { got404 = true }
        check(got404, "WebDAVClient 404 root path detection")

        let client = WebDAVClient(config: baseCfg, password: "correct-app-password", sessionConfiguration: sessionCfg)
        let connMsg = try await client.testConnection()
        check(connMsg.contains("207"), "WebDAVClient testConnection PROPFIND 207 OK: \(connMsg)")

        try await client.ensureRemoteDirectory()
        try await client.ensureRemoteDirectory()

        _ = try await client.uploadBackup(data: archiveData, fileName: "lucent-backup-20261113-100001.lucentbackup")
        _ = try await client.uploadBackup(data: archiveData, fileName: "lucent-backup-20261113-100002.lucentbackup")
        _ = try await client.uploadBackup(data: archiveData, fileName: "lucent-backup-20261113-100003.lucentbackup")

        let remoteBackups = try await client.listBackups()
        check(remoteBackups.count == 2, "keepLatestCount=2 rotated oldest snapshot, remaining \(remoteBackups.count)")
        check(remoteBackups.map(\.fileName) == [
            "lucent-backup-20261113-100003.lucentbackup",
            "lucent-backup-20261113-100002.lucentbackup"
        ], "Remaining snapshots are newest 2 in descending order")

        let downloaded = try await client.downloadBackup(item: remoteBackups[0])
        check(downloaded == archiveData, "Downloaded backup matches uploaded archive byte-for-byte")
        let verifiedDownload = try BackupArchiveService.inspectBackupData(downloaded)
        check(verifiedDownload.payloadSHA256 == expectedSHA256, "Downloaded archive SHA-256 verified")

        try await client.deleteBackup(item: remoteBackups[1])
        let afterDelete = try await client.listBackups()
        check(afterDelete.count == 1 && afterDelete[0].fileName == "lucent-backup-20261113-100003.lucentbackup", "DELETE removed target remote backup")
    }
}

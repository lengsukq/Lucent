import CryptoKit
import Darwin
import Foundation

public struct SubprocessOutput: Sendable, Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let timedOut: Bool

    public init(exitCode: Int32, stdout: String, stderr: String, timedOut: Bool = false) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
    }
}

public enum SubprocessRunner {
    public static func run(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        stdinText: String? = nil,
        timeoutSeconds: Double = 4.0
    ) -> SubprocessOutput {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = arguments
        if let environment {
            proc.environment = environment
        }

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        var inPipe: Pipe? = nil
        if stdinText != nil {
            let p = Pipe()
            proc.standardInput = p
            inPipe = p
        } else {
            proc.standardInput = FileHandle.nullDevice
        }

        final class DataBox: @unchecked Sendable {
            var data = Data()
        }
        let outBox = DataBox()
        let errBox = DataBox()
        let group = DispatchGroup()

        do {
            try proc.run()
        } catch {
            return SubprocessOutput(exitCode: -1, stdout: "", stderr: error.localizedDescription, timedOut: false)
        }

        if let stdinText, let inPipe {
            if let data = stdinText.data(using: .utf8) {
                try? inPipe.fileHandleForWriting.write(contentsOf: data)
            }
            try? inPipe.fileHandleForWriting.close()
        }

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outBox.data = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        let waitSem = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            proc.waitUntilExit()
            waitSem.signal()
        }

        var didTimeout = false
        if waitSem.wait(timeout: .now() + max(0.2, timeoutSeconds)) == .timedOut {
            didTimeout = true
            proc.terminate()
            if waitSem.wait(timeout: .now() + 0.3) == .timedOut {
                Darwin.kill(proc.processIdentifier, SIGKILL)
                _ = waitSem.wait(timeout: .now() + 0.5)
            }
        }
        _ = group.wait(timeout: .now() + 1.0)

        let outStr = String(decoding: outBox.data, as: UTF8.self)
        let errStr = String(decoding: errBox.data, as: UTF8.self)
        return SubprocessOutput(
            exitCode: didTimeout ? -1 : proc.terminationStatus,
            stdout: outStr,
            stderr: errStr,
            timedOut: didTimeout
        )
    }

    public static func locateExecutable(
        named name: String,
        extraDirectories: [String] = []
    ) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var dirs = extraDirectories
        if let rawPath = ProcessInfo.processInfo.environment["PATH"] {
            dirs.append(contentsOf: rawPath.split(separator: ":").map(String.init))
        }
        dirs.append(contentsOf: [
            "\(home)/.local/bin",
            "\(home)/.npm-global/bin",
            "\(home)/.nvm/current/bin",
            "\(home)/.volta/bin",
            "\(home)/.bun/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ])
        var seen = Set<String>()
        for dir in dirs where !dir.isEmpty && seen.insert(dir).inserted {
            let candidate = (dir as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}

public struct SyncHTTPResponse: Sendable {
    public let statusCode: Int
    public let data: Data
    public let headers: [String: String]
    public let errorDescription: String?

    public var text: String {
        String(decoding: data, as: UTF8.self)
    }

    public var isSuccess: Bool {
        (200...299).contains(statusCode) && errorDescription == nil
    }

    public func jsonObject() -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

public enum SyncHTTPClient {
    private static let sharedSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpMaximumConnectionsPerHost = 8
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    public static func request(
        url: URL,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Data? = nil,
        timeoutSeconds: Double = 6.0
    ) -> SyncHTTPResponse {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeoutSeconds)
        req.httpMethod = method
        for (k, v) in headers {
            req.setValue(v, forHTTPHeaderField: k)
        }
        req.httpBody = body

        final class ResultBox: @unchecked Sendable {
            var response: SyncHTTPResponse = SyncHTTPResponse(statusCode: 0, data: Data(), headers: [:], errorDescription: "timeout")
        }
        let box = ResultBox()
        let sem = DispatchSemaphore(value: 0)

        let task = sharedSession.dataTask(with: req) { data, resp, err in
            let http = resp as? HTTPURLResponse
            var hdrs: [String: String] = [:]
            for (k, v) in http?.allHeaderFields ?? [:] {
                hdrs[String(describing: k)] = String(describing: v)
            }
            box.response = SyncHTTPResponse(
                statusCode: http?.statusCode ?? 0,
                data: data ?? Data(),
                headers: hdrs,
                errorDescription: err?.localizedDescription
            )
            sem.signal()
        }
        task.resume()
        if sem.wait(timeout: .now() + timeoutSeconds + 1.5) == .timedOut {
            task.cancel()
        }
        return box.response
    }
}

public enum DigestUtils {
    public static func sha1Hex(_ text: String) -> String {
        Insecure.SHA1.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public static func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

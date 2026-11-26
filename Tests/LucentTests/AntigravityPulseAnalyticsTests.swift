import Foundation
import Testing
@testable import LucentCore

@Suite("Antigravity Pulse v1.4.0 Analytics & Official statusLine Quota Tests")
struct AntigravityPulseAnalyticsTests {
    private static func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func runBinary(
        _ binURL: URL,
        args: [String],
        stdin: Data,
        envOverrides: [String: String]
    ) throws -> (exitCode: Int32, stdout: Data, stderr: Data) {
        let proc = Process()
        proc.executableURL = binURL
        proc.arguments = args
        var env = ProcessInfo.processInfo.environment
        for (k, v) in envOverrides { env[k] = v }
        proc.environment = env

        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        try proc.run()
        if !stdin.isEmpty { inPipe.fileHandleForWriting.write(stdin) }
        try? inPipe.fileHandleForWriting.close()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return (proc.terminationStatus, outData, errData)
    }

    @Test("Manifest, dashboard assets, and window capability boundaries stay valid")
    func manifestAndDashboardAssetsValid() throws {
        let pluginDir = Self.repoRoot().appendingPathComponent("plugin-demo/antigravity-pulse", isDirectory: true)
        let manifestURL = pluginDir.appendingPathComponent("plugin.json")
        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: data)

        #expect(manifest.id == "antigravity-pulse")
        #expect(manifest.version == "1.4.0")
        #expect(manifest.resourceScopes == ["filesystem"])
        #expect(manifest.commands?.contains(where: { $0.id == "open-dashboard" }) == true)
        #expect(PluginCustomWindowSpec.resolveSafeHTMLFileURL(relativePath: "ui/dashboard.html", bundleDirectory: pluginDir) != nil)
        #expect(PluginCustomWindowSpec.resolveSafeHTMLFileURL(relativePath: "ui/widget.html", bundleDirectory: pluginDir) != nil)

        let dashSpec = PluginCustomWindowSpec(
            pluginID: manifest.id,
            windowID: "antigravity-pulse-dashboard",
            htmlPath: "ui/dashboard.html",
            width: 1100, height: 760, resizable: true,
            chrome: .standard, transparent: false, pinOnTop: false, showInDock: true, reuseIfOpen: true
        )
        #expect(!dashSpec.requiresFloatingCapability)
        #expect(dashSpec.isSatisfied(by: [.floatingWindow]))
    }

    @Test("Official statusLine hook recording, heatmap aggregation, and full-quota auto inference work end-to-end")
    func statusLineQuotaAndAnalyticsPipeline() throws {
        let binURL = Self.repoRoot().appendingPathComponent("plugin-demo/antigravity-pulse/bin/antigravity-pulse")
        guard FileManager.default.isExecutableFile(atPath: binURL.path) else {
            return
        }

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("agpulse-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let fakeHome = tmp.appendingPathComponent("home", isDirectory: true)
        let dataDir = tmp.appendingPathComponent("data", isDirectory: true)
        let logsDir = fakeHome.appendingPathComponent(".gemini/antigravity/brain/sess-alpha/.system_generated/logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let now = Date()
        let tsToday = iso.string(from: now.addingTimeInterval(-600))
        let tsYesterday = iso.string(from: now.addingTimeInterval(-86_400))

        // Synthetic transcript spanning yesterday & today across two real Gemini 4 variants.
        // Today Neon XHigh: 1_000_000 in ($2.50) + 10_000_000 cache ($2.50) + 200_000 out ($3.00) = $8.00
        let transcriptLines = [
            #"{"type":"USER_INPUT","content":"Build dashboard analytics"}"#,
            #"{"type":"PLANNER_RESPONSE","step_index":1,"created_at":"\#(tsYesterday)","model":"gemini-4-hydrogen-medium","input_tokens":500000,"cache_read_tokens":2000000,"output_tokens":100000,"status":"DONE"}"#,
            #"{"type":"PLANNER_RESPONSE","step_index":2,"created_at":"\#(tsToday)","model":"gemini-4-neon-xhigh","input_tokens":1000000,"cache_read_tokens":10000000,"output_tokens":200000,"status":"DONE"}"#
        ].joined(separator: "\n") + "\n"
        try Data(transcriptLines.utf8).write(to: logsDir.appendingPathComponent("transcript.jsonl"))

        let reset5h = iso.string(from: now.addingTimeInterval(3 * 3600))
        let reset7d = iso.string(from: now.addingTimeInterval(5 * 86_400))
        // Simulate official agy CLI statusLine JSON: 5h remaining = 60% (used = 40% -> inferred 5h full = $8.00 / 0.40 = $20.00)
        let statusLineJSON = """
        {
          "plan_tier": "Pro",
          "model": { "id": "gemini-4-neon-xhigh", "display_name": "Gemini 4 Neon (XHigh)" },
          "quota": {
            "gemini-5h": { "remaining_fraction": 0.60, "reset_time": "\(reset5h)", "reset_in_seconds": 10800 },
            "gemini-weekly": { "remaining_fraction": 0.80, "reset_time": "\(reset7d)", "reset_in_seconds": 432000 },
            "claude-5h": { "remaining_fraction": 0.90, "reset_time": "\(reset5h)", "reset_in_seconds": 10800 }
          }
        }
        """

        let env = ["HOME": fakeHome.path, "LUCENT_DATA_DIR": dataDir.path]
        let recRes = try Self.runBinary(binURL, args: ["--record-statusline", dataDir.path], stdin: Data(statusLineJSON.utf8), envOverrides: env)
        #expect(recRes.exitCode == 0)
        #expect(FileManager.default.fileExists(atPath: dataDir.appendingPathComponent("agy-quota.json").path))

        // 1) Default shared quota mode: local usedInQuotaUSD is tracked, full-quota inference stays disabled!
        let pluginReq = Data(#"{"locale":"zh-Hans","dataDir":"\#(dataDir.path)","config":{"currency":"USD","usdToCnyRate":"7.25"}}"#.utf8)
        let sharedRes = try Self.runBinary(binURL, args: ["--analytics", "365d"], stdin: pluginReq, envOverrides: env)
        #expect(sharedRes.exitCode == 0)
        let sharedRoot = try #require(try JSONSerialization.jsonObject(with: sharedRes.stdout) as? [String: Any])
        let sharedQuota = try #require(sharedRoot["quota"] as? [String: Any])
        #expect((sharedQuota["available"] as? Bool) == true)
        #expect((sharedQuota["exclusiveQuota"] as? Bool) == false)
        #expect(sharedQuota["monthlyFullQuotaUSD"] == nil || sharedQuota["monthlyFullQuotaUSD"] is NSNull)
        let shared5h = try #require(sharedQuota["window5h"] as? [String: Any])
        #expect(abs(((shared5h["usedInQuotaUSD"] as? Double) ?? 0) - 8.0) < 0.05)
        #expect(shared5h["fullQuotaUSD"] == nil || shared5h["fullQuotaUSD"] is NSNull)

        // 2) Switch currency to CNY @ 7.50 and opt into exclusiveQuota = true to enable full-quota inference.
        let prefRes = try Self.runBinary(
            binURL,
            args: ["--set-prefs", #"{"currency":"CNY","usdToCnyRate":7.5,"exclusiveQuota":true}"#],
            stdin: pluginReq,
            envOverrides: env
        )
        #expect(prefRes.exitCode == 0)

        // Run --analytics 365d and verify compact wire size (< 110 KB, safe under Lucent's 128 KiB stdout limit), heatmap, streaks & exclusive quota!
        let anaRes = try Self.runBinary(binURL, args: ["--analytics", "365d"], stdin: pluginReq, envOverrides: env)
        #expect(anaRes.exitCode == 0)
        #expect(anaRes.stdout.count < 110_000)
        let root = try #require(try JSONSerialization.jsonObject(with: anaRes.stdout) as? [String: Any])
        #expect((root["ok"] as? Bool) == true)
        #expect((root["currency"] as? String) == "CNY")
        #expect(abs(((root["usdToCnyRate"] as? Double) ?? 0) - 7.5) < 0.001)
        #expect(!((root["heatmapStartDate"] as? String) ?? "").isEmpty)
        #expect(!((root["heatmapEndDate"] as? String) ?? "").isEmpty)

        let heatmap = try #require(root["heatmap"] as? [[String: Any]])
        #expect(heatmap.count == 2)

        let streaks = try #require(root["streaks"] as? [String: Any])
        #expect(((streaks["activeDaysYear"] as? Int) ?? 0) >= 2)
        #expect(((streaks["currentStreakDays"] as? Int) ?? 0) >= 2)

        let quota = try #require(root["quota"] as? [String: Any])
        #expect((quota["available"] as? Bool) == true)
        #expect((quota["exclusiveQuota"] as? Bool) == true)
        #expect((quota["planTier"] as? String) == "Pro")
        let win5h = try #require(quota["window5h"] as? [String: Any])
        let usedUSD = (win5h["usedInQuotaUSD"] as? Double) ?? 0
        let fullUSD = (win5h["fullQuotaUSD"] as? Double) ?? 0
        #expect(abs(usedUSD - 8.0) < 0.05)
        #expect(abs(fullUSD - 20.0) < 0.15)
        #expect((quota["otherGroups"] as? [[String: Any]])?.count == 1)

        // Run --day-detail for today
        let todayKey = {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
            return f.string(from: now)
        }()
        let dayRes = try Self.runBinary(binURL, args: ["--day-detail", todayKey], stdin: pluginReq, envOverrides: env)
        #expect(dayRes.exitCode == 0)
        let dayRoot = try #require(try JSONSerialization.jsonObject(with: dayRes.stdout) as? [String: Any])
        #expect(((dayRoot["totalTokens"] as? Int) ?? 0) == 11_200_000)
        #expect(((dayRoot["sessions"] as? [[String: Any]])?.count ?? 0) == 1)

        // 3) Verify --copy-share-image and --save-share-image PNG validation & disk staging.
        let badReq = Data(#"{"locale":"zh-Hans","dataDir":"\#(dataDir.path)","query":"not-a-valid-png"}"#.utf8)
        let badRes = try Self.runBinary(binURL, args: ["--copy-share-image"], stdin: badReq, envOverrides: env)
        #expect(badRes.exitCode == 0)
        let badRoot = try #require(try JSONSerialization.jsonObject(with: badRes.stdout) as? [String: Any])
        #expect((badRoot["ok"] as? Bool) == false)

        // Minimal valid 1x1 PNG (67 bytes)
        let valid1x1PNG = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        let pngReq = Data(#"{"locale":"zh-Hans","dataDir":"\#(dataDir.path)","query":"\#(valid1x1PNG)"}"#.utf8)
        let copyRes = try Self.runBinary(binURL, args: ["--copy-share-image"], stdin: pngReq, envOverrides: env)
        #expect(copyRes.exitCode == 0)
        let copyRoot = try #require(try JSONSerialization.jsonObject(with: copyRes.stdout) as? [String: Any])
        #expect((copyRoot["ok"] as? Bool) == true)
        #expect((copyRoot["width"] as? Int) == 1)
        #expect((copyRoot["height"] as? Int) == 1)
        #expect(FileManager.default.fileExists(atPath: dataDir.appendingPathComponent("share-card.png").path))

        let saveRes = try Self.runBinary(binURL, args: ["--save-share-image"], stdin: pngReq, envOverrides: env)
        #expect(saveRes.exitCode == 0)
        let saveRoot = try #require(try JSONSerialization.jsonObject(with: saveRes.stdout) as? [String: Any])
        #expect((saveRoot["ok"] as? Bool) == true)
        let savedPath = try #require(saveRoot["path"] as? String)
        #expect(savedPath.hasPrefix(fakeHome.appendingPathComponent("Desktop").path))
        #expect(FileManager.default.fileExists(atPath: savedPath))
    }
}

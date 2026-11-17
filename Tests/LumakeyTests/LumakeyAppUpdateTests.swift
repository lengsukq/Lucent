import Foundation
import Testing
@testable import LumakeyCore

@Suite("App Self-Update & Plugin Auto-Update Engine")
struct LumakeyAppUpdateTests {
    @Test("AppVersionComparator, GitHub Release JSON parsing, SHA-256 extraction & MenuBar update promotion")
    func appUpdateParsingComparatorAndMenuPromotion() throws {
        #expect(AppVersionComparator.isRemoteNewer(remote: "v1.0.0", current: "0.9.0") == true)
        #expect(AppVersionComparator.isRemoteNewer(remote: "0.9.0", current: "0.9.0") == false)
        #expect(AppVersionComparator.isRemoteNewer(remote: "0.9.1", current: "0.9.1-beta.2") == true)
        #expect(AppVersionComparator.isRemoteNewer(remote: "0.9.1-beta.1", current: "0.9.1") == false)

        let now = Date(timeIntervalSince1970: 1_800_100_000)
        #expect(UpdateCheckFrequency.manualOnly.isDue(lastCheckedTimestamp: 0, now: now) == false)
        #expect(UpdateCheckFrequency.onEveryLaunch.isDue(lastCheckedTimestamp: now.timeIntervalSince1970 - 5, now: now) == true)
        #expect(UpdateCheckFrequency.daily.isDue(lastCheckedTimestamp: now.timeIntervalSince1970 - 3_600, now: now) == false)
        #expect(UpdateCheckFrequency.daily.isDue(lastCheckedTimestamp: now.timeIntervalSince1970 - 90_000, now: now) == true)

        let sampleReleaseJSON = Data("""
        {
          "tag_name": "v1.2.0",
          "name": "Lumakey 1.2.0",
          "body": "Faster search & new update center",
          "html_url": "./releases/v1.2.0",
          "draft": false,
          "prerelease": false,
          "published_at": "2026-11-17T08:00:00Z",
          "assets": [
            {
              "name": "Lumakey.dmg",
              "browser_download_url": "./dist/Lumakey.dmg",
              "size": 10485760
            },
            {
              "name": "Lumakey.dmg.sha256",
              "browser_download_url": "./dist/Lumakey.dmg.sha256",
              "size": 92
            }
          ]
        }
        """.utf8)
        let parsed = try AppUpdateService.parseGitHubReleasesJSON(sampleReleaseJSON, includePrerelease: false)
        #expect(parsed?.normalizedVersion == "1.2.0")
        #expect(parsed?.dmgAssetName == "Lumakey.dmg")
        #expect(parsed?.sha256AssetURL?.hasSuffix("Lumakey.dmg.sha256") == true)

        let shaLine = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef  Lumakey.dmg\n"
        #expect(AppUpdateService.parseFirstSHA256Hex(from: shaLine, matchingFileName: "Lumakey.dmg") == String(repeating: "0123456789abcdef", count: 4))

        let compact = MenuBarConfig.preset(.compact)
        let normalLayout = compact.resolvedLayout(context: MenuBarRuntimeContext())
        #expect(!normalLayout.topLevelItems.contains(.checkForUpdates))
        let alertLayout = compact.resolvedLayout(context: MenuBarRuntimeContext(availableAppUpdateVersion: "1.2.0"))
        #expect(alertLayout.topLevelItems.contains(.checkForUpdates))
    }

    @Test("Local TCC-resign command formatting and executable Terminal launcher script generation")
    func localResignCommandAndTerminalScript() throws {
        #expect(AppUpdateService.localResignCommand(forAppBundleURL: nil) == AppUpdateService.localResignOneLiner)
        #expect(
            AppUpdateService.localResignCommand(forAppBundleURL: URL(fileURLWithPath: "/Applications/Lumakey.app"))
                == AppUpdateService.localResignOneLiner
        )

        let customAppURL = URL(fileURLWithPath: "/Users/tester/My Apps/Bob's/Lumakey.app")
        let customCmd = AppUpdateService.localResignCommand(forAppBundleURL: customAppURL)
        #expect(customCmd == "\(AppUpdateService.localResignOneLiner) -s -- '/Users/tester/My Apps/Bob'\\''s/Lumakey.app'")

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumakey-resign-script-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let scriptURL = try AppUpdateService.writeLocalResignTerminalScript(
            forAppBundleURL: customAppURL,
            directory: tmpDir
        )
        #expect(scriptURL.lastPathComponent == "lumakey-local-resign.command")
        let attrs = try FileManager.default.attributesOfItem(atPath: scriptURL.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
        #expect((perms & 0o111) != 0)

        let scriptBody = try String(contentsOf: scriptURL, encoding: .utf8)
        #expect(scriptBody.hasPrefix("#!/usr/bin/env bash\n"))
        #expect(scriptBody.contains(customCmd))
        #expect(scriptBody.contains("EXIT_CODE=$?"))
    }
}

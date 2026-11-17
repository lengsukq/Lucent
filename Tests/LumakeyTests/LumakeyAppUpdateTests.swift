import Foundation
import Testing
@testable import LumakeyCore
@testable import LumakeyFoundation

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

    @Test("In-app auto-update identity resolution & atomic DMG installer script generation")
    func autoUpdateIdentityResolutionAndInstallScript() throws {
        let secOutput = """
          1) 1111111111111111111111111111111111111111 "Apple Development: Teammate (TEAM1)"
          2) 2222222222222222222222222222222222222222 "Apple Development: Personal (TEAM2)"
          3) 3333333333333333333333333333333333333333 "Lumakey Local Signer"
             3 valid identities found
        """
        let parsed = AppUpdateInstaller.parseCodesigningIdentityNames(fromSecurityOutput: secOutput)
        #expect(parsed == [
            "Apple Development: Teammate (TEAM1)",
            "Apple Development: Personal (TEAM2)",
            "Lumakey Local Signer"
        ])

        let adHocStatus = CodeSigningStatus(
            mode: .adHoc(hardenedRuntime: false),
            bundleIdentifier: "app.lumakey.macos",
            isStableForTCC: false,
            badgeTitle: "Ad-hoc",
            explanation: "ad-hoc"
        )
        let personalStatus = CodeSigningStatus(
            mode: .appleDevelopment(commonName: "Apple Development: Personal (TEAM2)", teamID: "TEAM2"),
            bundleIdentifier: "app.lumakey.macos",
            teamIdentifier: "TEAM2",
            isStableForTCC: true,
            badgeTitle: "Dev",
            explanation: "dev"
        )

        #expect(
            AppUpdateInstaller.resolveLocalSigningIdentity(currentStatus: personalStatus, availableIdentities: parsed)
                == "Apple Development: Personal (TEAM2)"
        )
        #expect(
            AppUpdateInstaller.resolveLocalSigningIdentity(currentStatus: adHocStatus, availableIdentities: parsed)
                == "Lumakey Local Signer"
        )
        #expect(
            AppUpdateInstaller.resolveLocalSigningIdentity(
                currentStatus: adHocStatus,
                availableIdentities: [
                    "Apple Development: Teammate (TEAM1)",
                    "Apple Development: Personal (TEAM2)"
                ]
            ) == nil
        )
        #expect(
            AppUpdateInstaller.resolveLocalSigningIdentity(
                currentStatus: adHocStatus,
                availableIdentities: ["Apple Development: Personal (TEAM2)"]
            ) == "Apple Development: Personal (TEAM2)"
        )

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumakey-auto-upd-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let plan = AppInstallPlan(
            dmgURL: URL(fileURLWithPath: "/Users/tester/Downloads/Lumakey-1.2.0.dmg"),
            targetAppURL: URL(fileURLWithPath: "/Applications/Lumakey.app"),
            preferredSignIdentity: "Lumakey Local Signer",
            currentPID: 99999
        )
        let scriptURL = try AppUpdateInstaller.writeAutoUpdateInstallScript(plan: plan, directory: tmpDir)
        let scriptText = try String(contentsOf: scriptURL, encoding: .utf8)
        #expect(scriptText.contains("WAIT_PID=99999"))
        #expect(scriptText.contains("PREFERRED_SIGN_ID='Lumakey Local Signer'"))
        #expect(scriptText.contains("hdiutil attach -nobrowse -readonly"))
        #expect(scriptText.contains("resign_stage"))
        #expect(scriptText.contains("open \"$TARGET_APP\""))

        let syntaxCheck = try ProcessSupervisor.shared.run(
            executableURL: URL(fileURLWithPath: "/bin/bash"),
            arguments: ["-n", scriptURL.path],
            timeoutSeconds: 5
        )
        #expect(syntaxCheck.exitCode == 0)
    }
}

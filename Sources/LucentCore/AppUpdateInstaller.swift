import Foundation
import LucentFoundation

public struct AppInstallPlan: Sendable, Equatable {
    public let dmgURL: URL
    public let targetAppURL: URL
    public let preferredSignIdentity: String?
    public let currentPID: Int32

    public init(
        dmgURL: URL,
        targetAppURL: URL,
        preferredSignIdentity: String? = nil,
        currentPID: Int32 = ProcessInfo.processInfo.processIdentifier
    ) {
        self.dmgURL = dmgURL
        self.targetAppURL = targetAppURL
        self.preferredSignIdentity = preferredSignIdentity
        self.currentPID = currentPID
    }
}

public enum AppUpdateInstaller {
    public static let localSignerCommonName = "Lucent Local Signer"

    public static func defaultTargetAppURL(bundle: Bundle = .main) -> URL {
        let current = bundle.bundleURL.standardizedFileURL
        if current.pathExtension == "app" {
            return current
        }
        return URL(fileURLWithPath: "/Applications/Lucent.app")
    }

    public static func canInstallInPlace(
        targetAppURL: URL = defaultTargetAppURL(),
        fileManager: FileManager = .default
    ) -> Bool {
        guard targetAppURL.pathExtension == "app" else { return false }
        let parentDir = targetAppURL.deletingLastPathComponent()
        return fileManager.isWritableFile(atPath: parentDir.path)
    }

    public static func parseCodesigningIdentityNames(fromSecurityOutput output: String) -> [String] {
        var names: [String] = []
        for rawLine in output.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let firstQuote = trimmed.firstIndex(of: "\""),
                  let lastQuote = trimmed.lastIndex(of: "\""),
                  firstQuote < lastQuote else { continue }
            let name = String(trimmed[trimmed.index(after: firstQuote)..<lastQuote])
            if !name.isEmpty, !names.contains(name) {
                names.append(name)
            }
        }
        return names
    }

    public static func queryKeychainSigningIdentities() -> [String] {
        let securityURL = URL(fileURLWithPath: "/usr/bin/security")
        guard FileManager.default.isExecutableFile(atPath: securityURL.path),
              let result = try? ProcessSupervisor.shared.run(
                  executableURL: securityURL,
                  arguments: ["find-identity", "-v", "-p", "codesigning"],
                  timeoutSeconds: 5
              ),
              result.exitCode == 0 else {
            return []
        }
        return parseCodesigningIdentityNames(fromSecurityOutput: result.stdout)
    }

    /// Selects a non-ambiguous local certificate so in-app updates preserve macOS TCC grants.
    public static func resolveLocalSigningIdentity(
        currentStatus: CodeSigningStatus = CodeSigningInspector.inspect(),
        availableIdentities: [String]? = nil
    ) -> String? {
        let identities = availableIdentities ?? queryKeychainSigningIdentities()
        if let currentAuthority = currentStatus.mode.authorityCommonName,
           identities.contains(currentAuthority) {
            return currentAuthority
        }
        if identities.contains(localSignerCommonName) {
            return localSignerCommonName
        }
        for prefix in ["Developer ID Application:", "Apple Development:", "Mac Developer:"] {
            let matches = identities.filter { $0.hasPrefix(prefix) }
            if matches.count == 1 {
                return matches[0]
            }
        }
        return nil
    }

    public static func buildAutoUpdateInstallScript(plan: AppInstallPlan) -> String {
        let dmgQuoted = shellSingleQuoted(plan.dmgURL.standardizedFileURL.path)
        let targetQuoted = shellSingleQuoted(plan.targetAppURL.standardizedFileURL.path)
        let signQuoted = shellSingleQuoted(plan.preferredSignIdentity ?? "")

        return """
        #!/usr/bin/env bash
        set -euo pipefail

        WAIT_PID=\(plan.currentPID)
        DMG_PATH=\(dmgQuoted)
        TARGET_APP=\(targetQuoted)
        PREFERRED_SIGN_ID=\(signQuoted)

        WORK_TMP="$(mktemp -d)"
        MOUNT_DIR="$WORK_TMP/mnt"
        STAGE_DIR="$WORK_TMP/stage"
        STAGE_APP="$STAGE_DIR/Lucent.app"
        BACKUP_APP="$WORK_TMP/Lucent.prev.app"
        MOUNTED=0

        cleanup() {
          if [ "$MOUNTED" -eq 1 ]; then
            hdiutil detach "$MOUNT_DIR" -force >/dev/null 2>&1 || true
          fi
          rm -rf "$WORK_TMP"
        }
        trap cleanup EXIT

        WAITED=0
        while kill -0 "$WAIT_PID" 2>/dev/null; do
          if [ "$WAITED" -ge 80 ]; then
            exit 1
          fi
          sleep 0.15
          WAITED=$((WAITED + 1))
        done

        mkdir -p "$MOUNT_DIR" "$STAGE_DIR"
        hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT_DIR" "$DMG_PATH" >/dev/null
        MOUNTED=1

        SRC_APP="$MOUNT_DIR/Lucent.app"
        if [ ! -d "$SRC_APP" ]; then
          SRC_APP="$(find "$MOUNT_DIR" -maxdepth 2 -name "*.app" -print | head -n 1 || true)"
        fi
        [ -d "$SRC_APP" ] || exit 1

        codesign --verify --deep --strict "$SRC_APP"

        resign_stage() {
          [ -n "$PREFERRED_SIGN_ID" ] || return 1
          local info ent_file
          info="$(codesign -dv --verbose=2 "$STAGE_APP" 2>&1 || true)"
          if ! printf '%s\\n' "$info" | grep -Eq 'Signature=adhoc|code object is not signed'; then
            return 0
          fi
          ent_file="$WORK_TMP/Lucent.entitlements"
          if ! codesign -d --entitlements - --xml "$STAGE_APP" > "$ent_file" 2>/dev/null || ! grep -q "<plist" "$ent_file"; then
            cat > "$ent_file" <<'PLIST'
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>com.apple.security.automation.apple-events</key>
            <true/>
            <key>com.apple.security.device.audio-input</key>
            <true/>
        </dict>
        </plist>
        PLIST
          fi
          if [ -x "$STAGE_APP/Contents/Helpers/macos-rdp-daemon" ]; then
            codesign --force --sign "$PREFERRED_SIGN_ID" --identifier "app.lucent.macos.rdp" "$STAGE_APP/Contents/Helpers/macos-rdp-daemon"
          fi
          if [ -x "$STAGE_APP/Contents/MacOS/lucent-mcp" ]; then
            codesign --force --sign "$PREFERRED_SIGN_ID" --identifier "app.lucent.macos.mcp" "$STAGE_APP/Contents/MacOS/lucent-mcp"
          fi
          codesign --force --entitlements "$ent_file" --sign "$PREFERRED_SIGN_ID" --identifier "app.lucent.macos" "$STAGE_APP"
          codesign --verify --deep --strict "$STAGE_APP"
        }

        ditto "$SRC_APP" "$STAGE_APP"
        xattr -dr com.apple.quarantine "$STAGE_APP" 2>/dev/null || true

        if [ -n "$PREFERRED_SIGN_ID" ]; then
          if ! resign_stage; then
            rm -rf "$STAGE_APP"
            ditto "$SRC_APP" "$STAGE_APP"
            xattr -dr com.apple.quarantine "$STAGE_APP" 2>/dev/null || true
          fi
        fi

        TARGET_PARENT="$(dirname "$TARGET_APP")"
        mkdir -p "$TARGET_PARENT"
        MOVED_OLD=0
        if [ -d "$TARGET_APP" ]; then
          mv "$TARGET_APP" "$BACKUP_APP"
          MOVED_OLD=1
        fi

        if ! mv "$STAGE_APP" "$TARGET_APP"; then
          if [ "$MOVED_OLD" -eq 1 ] && [ -d "$BACKUP_APP" ]; then
            mv "$BACKUP_APP" "$TARGET_APP" || true
          fi
          exit 1
        fi

        LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        if [ -x "$LSREGISTER" ]; then
          "$LSREGISTER" -f "$TARGET_APP" >/dev/null 2>&1 || true
        fi
        open "$TARGET_APP"
        """
    }

    @discardableResult
    public static func writeAutoUpdateInstallScript(
        plan: AppInstallPlan,
        directory: URL = FileManager.default.temporaryDirectory
    ) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scriptURL = directory.appendingPathComponent("lucent-auto-update-\(UUID().uuidString.prefix(8)).sh", isDirectory: false)
        let body = buildAutoUpdateInstallScript(plan: plan)
        try Data(body.utf8).write(to: scriptURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    /// Spawns a detached updater script that waits for the current app PID to exit, swaps the bundle, and relaunches.
    public static func launchDetachedAutoUpdate(plan: AppInstallPlan) throws {
        let scriptURL = try writeAutoUpdateInstallScript(plan: plan)
        let logsDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        let logURL = logsDir.appendingPathComponent("Lucent-updater.log", isDirectory: false)
        let quotedScript = shellSingleQuoted(scriptURL.path)
        let quotedLog = shellSingleQuoted(logURL.path)

        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/bin/bash")
        launcher.arguments = ["-c", "nohup /bin/bash \(quotedScript) >\(quotedLog) 2>&1 </dev/null &"]
        try launcher.run()
    }

    public static func shellSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

import Foundation

private struct RawStatusLineInput: Decodable {
    struct ModelInfo: Decodable {
        let id: String?
        let display_name: String?
    }
    let plan_tier: String?
    let model: ModelInfo?
    let quota: [String: AgyQuotaBucket]?
}

struct HookOperationResult: Codable {
    let ok: Bool
    let message: String
    let status: StatusLineHookStatus
}

func defaultPulseDataDir() -> String {
    let home = pulseUserHomePath()
    return "\(home)/Library/Application Support/Lucent/PluginData/antigravity-pulse"
}

func pulseQuotaFilePath(dataDir: String) -> String {
    let dir = dataDir.isEmpty ? defaultPulseDataDir() : dataDir
    return URL(fileURLWithPath: dir, isDirectory: true).appendingPathComponent("agy-quota.json").path
}

func aiAuditQuotaFilePath() -> String {
    let home = pulseUserHomePath()
    return "\(home)/.config/ai-audit/agy-quota.json"
}

private func agySettingsFilePath() -> String {
    let home = pulseUserHomePath()
    return "\(home)/.gemini/antigravity-cli/settings.json"
}

private func isAgyCLIInstalled() -> Bool {
    let fm = FileManager.default
    let home = pulseUserHomePath()
    let candidates = [
        "\(home)/.local/bin/agy",
        "/opt/homebrew/bin/agy",
        "/usr/local/bin/agy",
        "\(home)/.gemini/antigravity-cli/settings.json"
    ]
    return candidates.contains { fm.fileExists(atPath: $0) }
}

/// Parses Antigravity CLI's official `statusLine` stdin JSON payload and atomically writes non-empty quota snapshots.
/// Throttles identical snapshots within 10s so frequent 300ms TUI refreshes cause zero unnecessary disk churn.
@discardableResult
func recordAgyStatusLinePayload(rawData: Data, dataDir: String) -> Bool {
    guard !rawData.isEmpty,
          let parsed = try? JSONDecoder().decode(RawStatusLineInput.self, from: rawData),
          let quota = parsed.quota, !quota.isEmpty else {
        return false
    }

    let nowMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
    let next = AgyQuotaSnapshotFile(
        observed_at: nowMs,
        plan_tier: parsed.plan_tier?.trimmingCharacters(in: .whitespacesAndNewlines),
        model_id: parsed.model?.id?.trimmingCharacters(in: .whitespacesAndNewlines),
        model_name: parsed.model?.display_name?.trimmingCharacters(in: .whitespacesAndNewlines),
        quota: quota
    )

    let outPath = pulseQuotaFilePath(dataDir: dataDir)
    let outURL = URL(fileURLWithPath: outPath)
    if let prevData = try? Data(contentsOf: outURL),
       let prev = try? JSONDecoder().decode(AgyQuotaSnapshotFile.self, from: prevData) {
        if nowMs - prev.observed_at < 10_000,
           prev.plan_tier == next.plan_tier,
           prev.model_id == next.model_id,
           prev.quota == next.quota {
            return true
        }
    }

    let fm = FileManager.default
    try? fm.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let encoded = try? JSONEncoder().encode(next) else { return false }
    do {
        try encoded.write(to: outURL, options: .atomic)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: outPath)
        return true
    } catch {
        return false
    }
}

func inspectStatusLineHookStatus() -> StatusLineHookStatus {
    let settingsPath = agySettingsFilePath()
    let agyPresent = isAgyCLIInstalled()
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let sl = obj["statusLine"] as? [String: Any],
          let cmd = (sl["command"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
          !cmd.isEmpty else {
        return StatusLineHookStatus(
            installed: false, managedByPulse: false, managedByOther: nil,
            settingsPath: settingsPath, agyInstalled: agyPresent
        )
    }
    let enabled = (sl["enabled"] as? Bool) ?? true
    let isPulse = cmd.contains("antigravity-pulse") && cmd.contains("--record-statusline")
    if isPulse {
        return StatusLineHookStatus(
            installed: enabled, managedByPulse: true, managedByOther: nil,
            settingsPath: settingsPath, agyInstalled: agyPresent
        )
    }
    let otherLabel = cmd.contains("ai-audit-hook") ? "phone_ai_audit (ai-audit-hook)" : cmd
    return StatusLineHookStatus(
        installed: enabled, managedByPulse: false, managedByOther: otherLabel,
        settingsPath: settingsPath, agyInstalled: agyPresent
    )
}

private func shellSingleQuote(_ path: String) -> String {
    "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

func installStatusLineHook(binaryPath: String, dataDir: String, isEn: Bool) -> HookOperationResult {
    let current = inspectStatusLineHookStatus()
    if let other = current.managedByOther {
        let isAudit = other.contains("ai-audit-hook")
        let msg = isAudit
            ? (isEn
                ? "Detected existing phone_ai_audit statusLine hook; Antigravity Pulse reads its quota file automatically without overwriting your config."
                : "检测到已安装 phone_ai_audit 的 statusLine 钩子；Antigravity Pulse 会自动兼容读取其配额快照，无需覆盖原配置。")
            : (isEn
                ? "Existing custom statusLine detected (\(other)). Left untouched to preserve your setup."
                : "检测到已有自定义 statusLine（\(other)），已保留原配置未覆盖。")
        return HookOperationResult(ok: isAudit, message: msg, status: current)
    }

    let settingsPath = agySettingsFilePath()
    let settingsURL = URL(fileURLWithPath: settingsPath)
    let fm = FileManager.default
    var root: [String: Any] = [:]
    if let data = try? Data(contentsOf: settingsURL) {
        guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return HookOperationResult(
                ok: false,
                message: isEn ? "Failed to parse ~/.gemini/antigravity-cli/settings.json" : "无法解析 ~/.gemini/antigravity-cli/settings.json，已取消修改",
                status: current
            )
        }
        root = parsed
        let backupPath = settingsPath + ".agpulse.bak"
        if !fm.fileExists(atPath: backupPath) {
            try? data.write(to: URL(fileURLWithPath: backupPath), options: .atomic)
        }
    } else {
        try? fm.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    let resolvedDir = dataDir.isEmpty ? defaultPulseDataDir() : dataDir
    let cmd = "\(shellSingleQuote(binaryPath)) --record-statusline \(shellSingleQuote(resolvedDir))"
    root["statusLine"] = [
        "type": "command",
        "command": cmd,
        "enabled": true,
        "padding": 0,
        "stack_with_default": true
    ] as [String: Any]

    guard let outData = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else {
        return HookOperationResult(
            ok: false,
            message: isEn ? "Failed to encode settings.json" : "编码 settings.json 失败",
            status: current
        )
    }
    do {
        try outData.write(to: settingsURL, options: .atomic)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settingsPath)
        let updated = inspectStatusLineHookStatus()
        let msg = isEn
            ? "Enabled official agy statusLine sync (stack_with_default: true). Open any agy CLI session to sync live quota."
            : "已启用官方 agy statusLine 自动同步（保留默认状态栏）。打开任意 agy 终端会话即可自动刷新官方实时额度。"
        return HookOperationResult(ok: true, message: msg, status: updated)
    } catch {
        return HookOperationResult(
            ok: false,
            message: isEn ? "Failed to write settings.json: \(error.localizedDescription)" : "写入 settings.json 失败：\(error.localizedDescription)",
            status: current
        )
    }
}

func uninstallStatusLineHook(isEn: Bool) -> HookOperationResult {
    let current = inspectStatusLineHookStatus()
    guard current.managedByPulse else {
        return HookOperationResult(
            ok: true,
            message: isEn ? "No Antigravity Pulse statusLine entry to remove." : "当前未配置 Antigravity Pulse 的 statusLine 钩子。",
            status: current
        )
    }
    let settingsPath = agySettingsFilePath()
    let settingsURL = URL(fileURLWithPath: settingsPath)
    guard let data = try? Data(contentsOf: settingsURL),
          var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return HookOperationResult(ok: false, message: isEn ? "Could not read settings.json" : "无法读取 settings.json", status: current)
    }
    root.removeValue(forKey: "statusLine")
    guard let outData = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else {
        return HookOperationResult(ok: false, message: isEn ? "Failed to encode settings.json" : "编码 settings.json 失败", status: current)
    }
    do {
        try outData.write(to: settingsURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settingsPath)
        return HookOperationResult(
            ok: true,
            message: isEn ? "Removed Antigravity Pulse statusLine hook." : "已移除官方 statusLine 同步钩子并恢复默认状态栏。",
            status: inspectStatusLineHookStatus()
        )
    } catch {
        return HookOperationResult(ok: false, message: error.localizedDescription, status: current)
    }
}

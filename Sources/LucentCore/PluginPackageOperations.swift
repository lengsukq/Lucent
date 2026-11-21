import LucentFoundation
import Foundation

extension PluginSystem {
    @discardableResult
    public static func scaffoldPlugin(
        id: String,
        name: String,
        keywords: [String],
        description: String,
        mode: PluginMode = .script,
        minAppVersion: String? = nil,
        author: String? = nil,
        icon: String? = nil,
        hotkey: String? = nil,
        includeInGlobalSearch: Bool? = nil,
        searchIndexInGlobalSearch: Bool? = nil,
        backupExclude: [String]? = nil,
        config: [PluginConfigField]? = nil,
        capabilities: [PluginCapability] = [],
        resourceScopes: [PluginResourceScope] = [],
        accepts: [PluginContextKind]? = nil,
        acceptExtensions: [String]? = nil,
        acceptURLHosts: [String]? = nil,
        timeoutSeconds: Double? = nil,
        commands: [PluginCommandSpec]? = nil,
        in rootDir: URL = defaultPluginsDirectory()
    ) throws -> PluginDescriptor {
        guard isSafePluginID(id) else {
            throw LucentError.pluginInvalid("插件 id '\(id)' 不合法，仅支持小写字母、数字和连字符。")
        }
        guard !PluginBuiltinRegistry.isBuiltin(id: id) else {
            throw LucentError.pluginInvalid("插件 id '\(id)' 为内置插件保留前缀。")
        }
        let pluginDir = rootDir.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)

        let entryName = "run.sh"
        let scriptContent = scaffoldScriptBody(id: id, name: name, mode: mode, capabilities: capabilities)
        let scriptURL = pluginDir.appendingPathComponent(entryName)
        try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let manifest = PluginManifest(
            schemaVersion: 3,
            id: id, name: name, version: "1.0.0", minAppVersion: minAppVersion,
            description: description, mode: mode,
            keywords: keywords.isEmpty ? [id] : keywords, entry: entryName,
            author: author, icon: icon, hotkey: hotkey,
            includeInGlobalSearch: includeInGlobalSearch,
            searchIndexInGlobalSearch: searchIndexInGlobalSearch,
            backupExclude: backupExclude,
            config: config,
            capabilities: capabilities.map(\.rawValue),
            resourceScopes: resourceScopes.map(\.rawValue),
            accepts: accepts.map { $0.map(\.rawValue) },
            acceptExtensions: acceptExtensions,
            acceptURLHosts: acceptURLHosts,
            timeoutSeconds: timeoutSeconds,
            commands: commands
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: pluginDir.appendingPathComponent("plugin.json"), options: .atomic)
        return loadPlugin(at: pluginDir, in: rootDir)
    }

    private static func scaffoldScriptBody(id: String, name: String, mode: PluginMode, capabilities: [PluginCapability]) -> String {
        if let firstCap = capabilities.first {
            let defaultAction: String = switch firstCap {
            case .clipboard, .selection: "read"
            case .window, .floatingWindow: "open"
            case .screenCapture, .notifications, .systemControl, .lumaLinkStatus: "status"
            case .audio: "stop"
            case .ocr: "recognize"
            case .everythingSearch: "search"
            case .displayInfo, .audioDevices: "list"
            case .fileShelf: "open"
            case .contextRouter: "match"
            }
            return """
            #!/bin/zsh
            set -euo pipefail
            PAYLOAD="$(cat)"
            BRIDGE_RESP="$(printf '{"token":"%s","capability":"\(firstCap.rawValue)","action":"\(defaultAction)","params":{}}\\n' "${LUCENT_BRIDGE_TOKEN:-}" | /usr/bin/nc -U "${LUCENT_BRIDGE_SOCK:-}" 2>/dev/null || echo '{"ok":false,"message":"Host Bridge 未就绪"}')"
            if [[ "\(mode.rawValue)" == "script" ]]; then
              echo "[\(id)] $BRIDGE_RESP"
              exit 0
            fi
            OK_FLAG="$(printf '%s' "$BRIDGE_RESP" | /usr/bin/plutil -extract ok raw -o - - 2>/dev/null || echo false)"
            if [[ "$OK_FLAG" == "true" || "$OK_FLAG" == "1" ]]; then
              printf '{"title":"%s","subtitle":"Host Bridge 调用成功 (\(firstCap.rawValue))","badge":"V3","items":[{"title":"Host Bridge 已就绪","subtitle":"\(firstCap.rawValue).\(defaultAction)","icon":"checkmark.shield.fill"}]}\\n' "\(name)"
            else
              MSG="$(printf '%s' "$BRIDGE_RESP" | /usr/bin/plutil -extract message raw -o - - 2>/dev/null || echo '未授权')"
              ERR="$(printf '%s' "$BRIDGE_RESP" | /usr/bin/plutil -extract error raw -o - - 2>/dev/null || echo 'capability_not_granted')"
              MSG_SAFE="${MSG//\\"/\\\\\\"}"
              ERR_SAFE="${ERR//\\"/\\\\\\"}"
              printf '{"title":"%s","subtitle":"%s","badge":"AUTH","items":[{"title":"请在插件中心授权 \(firstCap.rawValue)","subtitle":"%s","icon":"lock.shield"}]}\\n' "\(name)" "$MSG_SAFE" "$ERR_SAFE"
            fi
            """
        }
        if mode == .script {
            return """
            #!/bin/zsh
            set -euo pipefail
            PAYLOAD="$(cat)"
            if [[ $# -gt 0 ]]; then
              echo "[\(id)] args=$* ok: $PAYLOAD"
            else
              echo "[\(id)] ok: $PAYLOAD"
            fi
            """
        }
        return """
        #!/bin/zsh
        set -euo pipefail
        PAYLOAD="$(cat)"
        Q="$(printf '%s' "$PAYLOAD" | /usr/bin/plutil -extract query raw -o - - 2>/dev/null || true)"
        Q_SAFE="${Q//\\"/\\\\\\"}"
        cat <<EOF
        {"title":"\(name)","subtitle":"[\(id)] ok · 查询参数: ${Q_SAFE}","badge":"VIEW","metrics":[{"key":"ID","value":"\(id)"},{"key":"Query","value":"${Q_SAFE:-empty}"}],"items":[{"title":"复制查询内容","subtitle":"${Q_SAFE:-无输入}","icon":"doc.on.doc","badge":"Copy","copyText":"${Q_SAFE}"}]}
        EOF
        """
    }

    public static func removePlugin(id: String, in rootDir: URL = defaultPluginsDirectory()) throws {
        guard isSafePluginID(id) else {
            throw LucentError.pluginInvalid("插件 id '\(id)' 不合法")
        }
        let pluginDir = rootDir.appendingPathComponent(id, isDirectory: true).standardizedFileURL
        guard pluginDir.path.hasPrefix(rootDir.standardizedFileURL.path + "/") else {
            throw LucentError.pluginInvalid("目标插件路径越界")
        }
        guard FileManager.default.fileExists(atPath: pluginDir.path) else {
            throw LucentError.pluginInvalid("未找到插件目录：\(id)")
        }
        if let secretKeys = secretFieldKeys(id: id, in: rootDir), !secretKeys.isEmpty {
            PluginKeychainStore.deleteSecrets(
                pluginID: id, fieldKeys: Array(secretKeys),
                service: PluginDataPaths.keychainService(forPluginsRoot: rootDir),
                customVaultURL: PluginDataPaths.scopedVaultFileURL(forPluginsRoot: rootDir)
            )
        }
        try FileManager.default.removeItem(at: pluginDir)
        PluginDataPaths.removeDataDirectory(for: id, pluginsRoot: rootDir)
        var snap = loadStateSnapshot(in: rootDir)
        if snap.plugins.removeValue(forKey: id) != nil {
            try? saveStateSnapshot(snap, in: rootDir)
        }
        if id == LumaLinkServer.companionPluginID,
           rootDir.standardizedFileURL.path == defaultPluginsDirectory().standardizedFileURL.path {
            var cfg = LumaLinkServer.shared.currentConfig()
            cfg.enabled = false
            LumaLinkServer.shared.apply(config: cfg, persist: true)
        }
    }

    @discardableResult
    public static func importPluginDirectory(
        from sourceDir: URL,
        in rootDir: URL = defaultPluginsDirectory(),
        overwrite: Bool = true
    ) throws -> PluginDescriptor {
        let candidate = loadPlugin(at: sourceDir, snapshot: PluginStateSnapshot(), in: rootDir)
        guard candidate.isValid else {
            let reason = candidate.validationIssues.joined(separator: "；")
            throw LucentError.pluginInvalid("导入失败：\(reason)")
        }
        let targetDir = rootDir.appendingPathComponent(candidate.manifest.id, isDirectory: true)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: targetDir.path) {
            guard overwrite else { throw LucentError.pluginInvalid("插件 '\(candidate.manifest.id)' 已存在") }
            try FileManager.default.removeItem(at: targetDir)
        }
        try FileManager.default.copyItem(at: sourceDir, to: targetDir)
        let entryURL = targetDir.appendingPathComponent(candidate.manifest.entry).standardizedFileURL
        if entryURL.path.hasPrefix(targetDir.standardizedFileURL.path + "/"),
           FileManager.default.fileExists(atPath: entryURL.path) {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: entryURL.path)
        }
        return loadPlugin(at: targetDir, in: rootDir)
    }

    @discardableResult
    public static func exportPlugin(
        id: String,
        to destinationParentDir: URL,
        in rootDir: URL = defaultPluginsDirectory()
    ) throws -> URL {
        guard isSafePluginID(id) else { throw LucentError.pluginInvalid("插件 id '\(id)' 不合法") }
        let sourceDir = rootDir.appendingPathComponent(id, isDirectory: true)
        guard FileManager.default.fileExists(atPath: sourceDir.path) else {
            throw LucentError.pluginInvalid("插件 '\(id)' 不存在")
        }
        try FileManager.default.createDirectory(at: destinationParentDir, withIntermediateDirectories: true)
        let outDir = destinationParentDir.appendingPathComponent(id, isDirectory: true)
        if FileManager.default.fileExists(atPath: outDir.path) {
            try FileManager.default.removeItem(at: outDir)
        }
        try FileManager.default.copyItem(at: sourceDir, to: outDir)
        return outDir
    }
}

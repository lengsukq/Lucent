import Foundation

extension PluginSystem {
    @discardableResult
    public static func scaffoldPlugin(
        id: String,
        name: String,
        keywords: [String],
        description: String,
        mode: PluginMode = .script,
        author: String? = nil,
        icon: String? = nil,
        hotkey: String? = nil,
        config: [PluginConfigField]? = nil,
        capabilities: [PluginCapability] = [],
        resourceScopes: [PluginResourceScope] = [],
        accepts: [PluginContextKind]? = nil,
        commands: [PluginCommandSpec]? = nil,
        in rootDir: URL = defaultPluginsDirectory()
    ) throws -> PluginDescriptor {
        guard isSafePluginID(id) else {
            throw LumakeyError.pluginInvalid("插件 id '\(id)' 不合法，仅支持小写字母、数字和连字符。")
        }
        guard !PluginBuiltinRegistry.isBuiltin(id: id) else {
            throw LumakeyError.pluginInvalid("插件 id '\(id)' 为内置插件保留前缀。")
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
            id: id, name: name, version: "1.0.0", description: description,
            mode: mode, keywords: keywords.isEmpty ? [id] : keywords, entry: entryName,
            author: author, icon: icon, hotkey: hotkey, config: config,
            capabilities: capabilities.map(\.rawValue),
            resourceScopes: resourceScopes.map(\.rawValue),
            accepts: accepts.map { $0.map(\.rawValue) },
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
            case .audio: "stop"
            case .ocr: "recognize"
            case .everythingSearch: "search"
            case .displayInfo: "list"
            case .systemControl, .lumaLinkStatus: "status"
            }
            return """
            #!/bin/zsh
            set -euo pipefail
            PAYLOAD="$(cat)"
            BRIDGE_RESP="$(printf '{"token":"%s","capability":"\(firstCap.rawValue)","action":"\(defaultAction)","params":{}}\\n' "${LUMAKEY_BRIDGE_TOKEN:-}" | /usr/bin/nc -U "${LUMAKEY_BRIDGE_SOCK:-}" 2>/dev/null || echo '{"ok":false,"message":"Host Bridge 未就绪"}')"
            if [[ "\(mode.rawValue)" == "script" ]]; then
              echo "[\(id)] $BRIDGE_RESP"
              exit 0
            fi
            /usr/bin/python3 -c '
            import json, sys
            resp = json.loads(sys.argv[1]) if sys.argv[1].strip().startswith("{") else {"ok": False, "message": sys.argv[1]}
            if not resp.get("ok"):
                print(json.dumps({"title": sys.argv[2], "subtitle": resp.get("message", "未授权"), "badge": "AUTH", "items": [{"title": "请在插件中心授权 \(firstCap.rawValue)", "subtitle": resp.get("error", "capability_not_granted"), "icon": "lock.shield"}]}))
            else:
                print(json.dumps({"title": sys.argv[2], "subtitle": "Host Bridge 调用成功 (\(firstCap.rawValue))", "badge": "V3", "markdown": json.dumps(resp.get("data", {}), ensure_ascii=False)}))
            ' "$BRIDGE_RESP" "\(name)"
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
            throw LumakeyError.pluginInvalid("插件 id '\(id)' 不合法")
        }
        let pluginDir = rootDir.appendingPathComponent(id, isDirectory: true).standardizedFileURL
        guard pluginDir.path.hasPrefix(rootDir.standardizedFileURL.path + "/") else {
            throw LumakeyError.pluginInvalid("目标插件路径越界")
        }
        guard FileManager.default.fileExists(atPath: pluginDir.path) else {
            throw LumakeyError.pluginInvalid("未找到插件目录：\(id)")
        }
        if let secretKeys = secretFieldKeys(id: id, in: rootDir), !secretKeys.isEmpty {
            PluginKeychainStore.deleteSecrets(
                pluginID: id,
                fieldKeys: Array(secretKeys),
                service: PluginDataPaths.keychainService(forPluginsRoot: rootDir)
            )
        }
        try FileManager.default.removeItem(at: pluginDir)
        PluginDataPaths.removeDataDirectory(for: id, pluginsRoot: rootDir)
        var snap = loadStateSnapshot(in: rootDir)
        if snap.plugins.removeValue(forKey: id) != nil {
            try? saveStateSnapshot(snap, in: rootDir)
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
            throw LumakeyError.pluginInvalid("导入失败：\(reason)")
        }
        let targetDir = rootDir.appendingPathComponent(candidate.manifest.id, isDirectory: true)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: targetDir.path) {
            guard overwrite else { throw LumakeyError.pluginInvalid("插件 '\(candidate.manifest.id)' 已存在") }
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
        guard isSafePluginID(id) else { throw LumakeyError.pluginInvalid("插件 id '\(id)' 不合法") }
        let sourceDir = rootDir.appendingPathComponent(id, isDirectory: true)
        guard FileManager.default.fileExists(atPath: sourceDir.path) else {
            throw LumakeyError.pluginInvalid("插件 '\(id)' 不存在")
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

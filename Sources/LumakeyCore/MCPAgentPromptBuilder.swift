import LumakeyFoundation; import LumakeySearch; import LumakeyMedia; import LumakeySystem
import Foundation

public enum MCPAgentPromptBuilder {
    public static func resolveExecutablePath(
        bundleURL: URL = Bundle.main.bundleURL,
        executableURL: URL? = Bundle.main.executableURL
    ) -> (path: String, exists: Bool) {
        let fm = FileManager.default
        var candidates: [String] = [
            bundleURL.appendingPathComponent("Contents/MacOS/lumakey-mcp").path
        ]
        if let execURL = executableURL {
            candidates.append(execURL.deletingLastPathComponent().appendingPathComponent("lumakey-mcp").path)
        }
        candidates.append("/Applications/Lumakey.app/Contents/MacOS/lumakey-mcp")

        for path in candidates where fm.isExecutableFile(atPath: path) {
            return (path, true)
        }
        let fallback = candidates[0]
        return (fallback, fm.fileExists(atPath: fallback))
    }

    public static func buildConfigJSON(executablePath: String) -> String {
        let payload: [String: Any] = [
            "mcpServers": [
                "lumakey": [
                    "command": executablePath,
                    "args": [String]()
                ]
            ]
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ), let text = String(data: data, encoding: .utf8) else {
            let escaped = executablePath
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "{\n  \"mcpServers\": {\n    \"lumakey\": {\n      \"command\": \"\(escaped)\",\n      \"args\": []\n    }\n  }\n}"
        }
        return text
    }

    private static func shellQuoted(_ path: String) -> String {
        let escaped = path.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    public static func buildAgentPrompt(
        executablePath: String,
        pluginsDirectoryPath: String = PluginSystem.defaultPluginsDirectory().path,
        extraTask: String = "",
        language: AppLanguageID = .zhHans
    ) -> String {
        let configJSON = buildConfigJSON(executablePath: executablePath)
        let quotedExec = shellQuoted(executablePath)
        let trimmedTask = extraTask.trimmingCharacters(in: .whitespacesAndNewlines)

        switch language {
        case .zhHans:
            var lines: [String] = [
                "请帮我将本机安装的 macOS 原生效率中枢「流光 Lumakey」内置的 MCP Server (`lumakey-mcp`) 接入到你当前的 MCP 工具环境中，并完成连通性自检。",
                "",
                "### 1. 本机连接参数（已自动填入真实路径）",
                "- Server 名称：`lumakey`",
                "- 传输协议：`stdio`（标准输入输出 JSON-RPC 2.0，按需唤醒、零后台常驻端口）",
                "- 可执行文件绝对路径：`\(executablePath)`",
                "- 启动参数 (`args`)：`[]`",
                "- 插件热重载目录：`\(pluginsDirectoryPath)`（Lumakey 宿主 350ms 自动热重载）",
                "",
                "### 2. 请按你所在的客户端方式完成接入",
                "- **方式 A（支持 CLI 注册的 Agent）**：直接执行对应命令注册",
                "  - Claude Code：`claude mcp add --transport stdio lumakey -- \(quotedExec)`",
                "  - Codex CLI：`codex mcp add lumakey -- \(quotedExec)`",
                "  - Gemini CLI：`gemini mcp add lumakey \(quotedExec)`",
                "- **方式 B（使用 JSON 配置文件的客户端，如 Cursor `~/.cursor/mcp.json`、Windsurf `~/.codeium/windsurf/mcp_config.json`、Claude Desktop `~/Library/Application Support/Claude/claude_desktop_config.json` 等）**：请合并写入以下配置（**务必保留文件内已有的其他 `mcpServers` 配置，切勿覆盖丢失**）：",
                "```json",
                configJSON,
                "```",
                "",
                "### 3. 接入后验证与协作规范",
                "1. 写入配置后，若当前客户端需要重启或刷新会话才能加载新 MCP 工具，请明确提示我；若已即时生效，请直接调用 `lumakey_list_plugins` 与 `lumakey_app_permissions` 验证连通性。",
                "2. 开发、修改或排查任何 Lumakey 插件前，请先通过 MCP `resources/read` 读取 `lumakey://specs/plugin-v3`（打包或发布自定义插件商店时读取 `lumakey://specs/plugin-store-v1`）。",
                "3. 严格遵守 Lumakey 插件边界：禁止编写后台常驻守护进程或死循环；`plugin.json` 必须显式声明 `capabilities` 与 `resourceScopes`（纯沙盒均填 `[]`）；优先使用 `mode: \"view\"` 输出结构化卡片；每次修改后必须调用 `lumakey_validate_plugin` 与 `lumakey_run_plugin_test` 完成校验。"
            ]
            if !trimmedTask.isEmpty {
                lines.append("")
                lines.append("### 4. 接入完成后请继续帮我执行")
                lines.append(trimmedTask)
            }
            return lines.joined(separator: "\n")

        case .english:
            var lines: [String] = [
                "Please connect my local macOS productivity hub **Lumakey**'s built-in native MCP server (`lumakey-mcp`) to your current MCP environment and verify connectivity.",
                "",
                "### 1. Local Connection Parameters",
                "- Server Name: `lumakey`",
                "- Transport: `stdio` (JSON-RPC 2.0 over stdin/stdout, on-demand, zero resident port)",
                "- Executable Path: `\(executablePath)`",
                "- Arguments (`args`): `[]`",
                "- Live-Reload Plugins Directory: `\(pluginsDirectoryPath)` (auto hot-reloaded in 350ms)",
                "",
                "### 2. Registration Instructions (Pick What Matches Your Client)",
                "- **Option A (CLI-based Agents)**:",
                "  - Claude Code: `claude mcp add --transport stdio lumakey -- \(quotedExec)`",
                "  - Codex CLI: `codex mcp add lumakey -- \(quotedExec)`",
                "  - Gemini CLI: `gemini mcp add lumakey \(quotedExec)`",
                "- **Option B (JSON config clients such as Cursor `~/.cursor/mcp.json`, Windsurf `~/.codeium/windsurf/mcp_config.json`, Claude Desktop `~/Library/Application Support/Claude/claude_desktop_config.json`)**: Merge the entry below into `mcpServers` (**preserve any existing `mcpServers` entries without overwriting them**):",
                "```json",
                configJSON,
                "```",
                "",
                "### 3. Post-Connection Verification & Plugin Rules",
                "1. After configuring, let me know if your client requires a session reload/restart to load new MCP tools; otherwise immediately call `lumakey_list_plugins` and `lumakey_app_permissions` to confirm connectivity.",
                "2. Before creating or editing any Lumakey plugin, read `lumakey://specs/plugin-v3` via MCP `resources/read` (and `lumakey://specs/plugin-store-v1` when packaging or building a plugin registry).",
                "3. Follow Lumakey's architecture strictly: never create resident daemons or infinite loops; explicitly declare `capabilities` and `resourceScopes` in `plugin.json` (`[]` for pure sandbox); prefer `mode: \"view\"` structured cards; always run `lumakey_validate_plugin` and `lumakey_run_plugin_test` after changes."
            ]
            if !trimmedTask.isEmpty {
                lines.append("")
                lines.append("### 4. Follow-Up Task After Connecting")
                lines.append(trimmedTask)
            }
            return lines.joined(separator: "\n")
        }
    }
}

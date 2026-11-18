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
        scriptsDirectoryPath: String = ScriptLibraryStore.defaultScriptsDirectory().path,
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
                "- 快捷脚本库目录：`\(scriptsDirectoryPath)`（单文件脚本与自定义 SVG 图标实时双向同步）",
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
                "### 3. 接入后验证与协作规范（脚本库、图标绘制、插件与主页定制）",
                "1. 写入配置后，若当前客户端需要重启或刷新会话才能加载新 MCP 工具，请明确提示我；若已即时生效，请直接调用 `lumakey_list_plugins`、`lumakey_list_scripts` 与 `lumakey_app_permissions` 验证连通性。",
                "2. **创建或管理快捷脚本（Quick Scripts）**：单文件自动化或快捷操作优先读取 `lumakey://specs/scripts-v1` 并使用 `lumakey_upsert_script`（支持 Zsh / Bash / Python 3 / AppleScript / Swift 及 Node、Deno、Ruby 等自定义 Shebang）。每次创建脚本时，请主动为脚本设计**清晰的中英双语名称（`title` / `englishTitle`）与触发词（`keywords`）**，并通过 `iconSvg` **直接绘制精美的 `64×64` 专属矢量 `<svg>` 图标**（或搭配 SF Symbol 与 `accentColor`），保存后务必调用 `lumakey_run_script_test` 实测通过。",
                "3. **开发完整扩展插件或定制启动页**：多视图交互插件请读取 `lumakey://specs/plugin-v3`（商店打包读取 `lumakey://specs/plugin-store-v1`）；定制启动页 Bento 磁贴、混合高频坞、胶囊架或固定快捷脚本（`kind: \"script\"`）前请读取 `lumakey://specs/home-layout-v1` 并调用 `lumakey_get_home_layout`。",
                "4. **严守架构红线**：禁止编写后台常驻守护进程或死循环；插件 `plugin.json` 必须显式声明 `capabilities` 与 `resourceScopes`（脚本按需最小声明 `allowedScopes`）；修改插件后必须运行 `lumakey_validate_plugin` 与 `lumakey_run_plugin_test`。"
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
                "- Quick Scripts Directory: `\(scriptsDirectoryPath)` (two-way synced scripts & custom SVG icons)",
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
                "### 3. Post-Connection Verification, Quick Scripts & Plugin Rules",
                "1. After configuring, let me know if your client requires a session reload/restart to load new MCP tools; otherwise immediately call `lumakey_list_plugins`, `lumakey_list_scripts`, and `lumakey_app_permissions` to confirm connectivity.",
                "2. **Quick Scripts, Naming & Custom SVG Icon Drawing**: For lightweight quick actions or single-file automations, read `lumakey://specs/scripts-v1` and use `lumakey_upsert_script` (supports Zsh, Bash, Python 3, AppleScript, Swift, and custom `#!` shebangs like Node/Deno/Ruby). Always craft **clear bilingual names (`title` / `englishTitle`) and trigger `keywords`**, draw a **bespoke `64×64` vector `<svg>` icon via `iconSvg`** (or pair an SF Symbol with `accentColor`), and verify execution with `lumakey_run_script_test`.",
                "3. **Full Plugins & Home Layout**: Read `lumakey://specs/plugin-v3` before building multi-view plugins (`lumakey://specs/plugin-store-v1` for store packaging); read `lumakey://specs/home-layout-v1` and call `lumakey_get_home_layout` before pinning scripts (`kind: \"script\"`), plugins, or bookmarks onto Launcher Home tiles and dock.",
                "4. **Architecture Guardrails**: Never create resident daemons or infinite loops; explicitly declare `capabilities` and `resourceScopes` in `plugin.json` (and minimal `allowedScopes` for scripts); always run `lumakey_validate_plugin` and `lumakey_run_plugin_test` after plugin edits."
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

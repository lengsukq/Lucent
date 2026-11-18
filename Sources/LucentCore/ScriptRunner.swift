import LucentFoundation
import LucentSearch
import Foundation

public enum ScriptRunner {
    public static let maxEnvPayloadUTF8Bytes: Int = 49_152

    public static func runSync(
        _ script: ScriptRecord,
        query: String = "",
        clipboardText: String = "",
        selectedText: String = "",
        store: ScriptLibraryStore = .shared,
        cancellationHandle: ProcessCancellationHandle? = nil
    ) throws -> ScriptRunOutcome {
        guard script.isEnabled else {
            throw LucentError.pluginExecutionFailed("脚本「\(script.displayTitle)」当前处于停用状态")
        }
        let scriptsDir = store.scriptsDirectory.resolvingSymlinksInPath().standardizedFileURL
        let fileURL = store.scriptURL(for: script).resolvingSymlinksInPath().standardizedFileURL
        guard fileURL.path.hasPrefix(scriptsDir.path + "/"),
              FileManager.default.fileExists(atPath: fileURL.path) else {
            throw LucentError.pluginInvalid("未找到脚本文件：\(script.fileName)")
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fileURL.path)

        let isolatedTmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("lucent-script-\(script.id)-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(
            at: isolatedTmp,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: isolatedTmp) }

        var vars: [String: String] = [
            "LUCENT_SCRIPT_ID": script.id,
            "LUCENT_SCRIPT_TITLE": script.title,
            "LUCENT_QUERY": truncateUTF8(query, maxBytes: maxEnvPayloadUTF8Bytes),
            "LUCENT_SELECTED_TEXT": truncateUTF8(selectedText, maxBytes: maxEnvPayloadUTF8Bytes),
            "LUCENT_CLIPBOARD": script.passClipboard ? truncateUTF8(clipboardText, maxBytes: maxEnvPayloadUTF8Bytes) : "",
            "LUCENT_LOCALE": L10n.current.rawValue,
            "LUCENT_THEME": AppThemeConfig.load().selectedTheme.rawValue
        ]
        if script.runtime == .swift {
            vars["CLANG_MODULE_CACHE_PATH"] = isolatedTmp.appendingPathComponent("clang-cache", isDirectory: true).path
        }
        let cleanEnv = PluginSandboxProfileBuilder.sanitizedEnvironment(
            pluginVariables: vars,
            isolatedTmpDirectory: isolatedTmp
        )

        let (invokedExec, invokedArgs) = try resolveInvocation(
            for: script,
            scriptURL: fileURL,
            query: truncateUTF8(query, maxBytes: 16_384)
        )
        let execCmd = PluginSandboxProfileBuilder.wrapExecutionCommand(
            executableURL: invokedExec,
            arguments: invokedArgs,
            workingScopeDirectory: scriptsDir,
            grantedScopes: script.allowedScopes,
            dataDirectory: nil,
            isolatedTmpDirectory: isolatedTmp,
            stateRoot: scriptsDir,
            allowSwiftToolchain: script.runtime == .swift
        )

        let runResult: ProcessRunResult
        do {
            runResult = try ProcessSupervisor.shared.run(
                executableURL: execCmd.executableURL,
                arguments: execCmd.arguments,
                currentDirectoryURL: scriptsDir,
                environment: cleanEnv,
                inheritHostEnvironment: false,
                stdinData: query.isEmpty ? nil : Data(query.utf8),
                timeoutSeconds: script.timeoutSeconds,
                maxOutputBytes: 131_072,
                cancellationHandle: cancellationHandle
            )
        } catch {
            if script.runtime == .customShebang && !script.allowedScopes.contains(.subprocess) {
                throw LucentError.pluginExecutionFailed(
                    "自定义 Shebang 脚本启动失败（若使用了 Homebrew / Node / Deno / Ruby 等外部解释器，请在脚本权限中勾选「外部子进程 subprocess」）：\(error.localizedDescription)"
                )
            }
            throw LucentError.pluginExecutionFailed("脚本启动失败：\(error.localizedDescription)")
        }

        if runResult.wasCancelled { throw CancellationError() }
        if runResult.timedOut {
            throw LucentError.pluginExecutionFailed("脚本「\(script.displayTitle)」执行超时（\(Int(script.timeoutSeconds))s）已被自动终止")
        }
        var stderrText = runResult.stderr
        if (runResult.exitCode == 126 || runResult.exitCode == 127 || stderrText.contains("Operation not permitted")),
           !script.allowedScopes.contains(.subprocess) {
            stderrText += L10n.pick(
                "\n[提示] 若脚本依赖 Homebrew 工具或 Node/Deno/Ruby/Git 等外部命令，请在脚本设置中开启「外部子进程 (subprocess)」作用域。",
                "\n[Hint] Enable the 'subprocess' scope if this script invokes Homebrew, Node, Deno, Ruby, or external CLI tools."
            )
        }
        return ScriptRunOutcome(
            scriptID: script.id,
            exitCode: runResult.exitCode,
            stdout: runResult.stdout,
            stderr: stderrText,
            durationMs: runResult.durationMs
        )
    }

    public static func runAsync(
        _ script: ScriptRecord,
        query: String = "",
        clipboardText: String = "",
        selectedText: String = "",
        store: ScriptLibraryStore = .shared
    ) async throws -> ScriptRunOutcome {
        let cancelHandle = ProcessCancellationHandle()
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                try runSync(
                    script,
                    query: query,
                    clipboardText: clipboardText,
                    selectedText: selectedText,
                    store: store,
                    cancellationHandle: cancelHandle
                )
            }.value
        } onCancel: {
            cancelHandle.cancel()
        }
    }

    public static func truncateUTF8(_ text: String, maxBytes: Int) -> String {
        guard text.utf8.count > maxBytes else { return text }
        var out = ""
        out.reserveCapacity(maxBytes)
        var used = 0
        for scalar in text.unicodeScalars {
            let len = scalar.utf8.count
            if used + len > maxBytes { break }
            out.unicodeScalars.append(scalar)
            used += len
        }
        return out
    }

    private static func resolveInvocation(
        for script: ScriptRecord,
        scriptURL: URL,
        query: String
    ) throws -> (executable: URL, arguments: [String]) {
        let trailingArgs = query.isEmpty ? [] : [query]
        switch script.runtime {
        case .zsh:
            return (URL(fileURLWithPath: "/bin/zsh"), [scriptURL.path] + trailingArgs)
        case .bash:
            return (URL(fileURLWithPath: "/bin/bash"), [scriptURL.path] + trailingArgs)
        case .python3:
            let py = HostToolingStatus.detectPython3Path() ?? "/usr/bin/python3"
            return (URL(fileURLWithPath: py), [scriptURL.path] + trailingArgs)
        case .appleScript:
            return (URL(fileURLWithPath: "/usr/bin/osascript"), [scriptURL.path] + trailingArgs)
        case .swift:
            return (URL(fileURLWithPath: "/usr/bin/swift"), [scriptURL.path] + trailingArgs)
        case .customShebang:
            let raw = (try? String(contentsOf: scriptURL, encoding: .utf8)) ?? ""
            let firstLine = raw.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces) ?? ""
            guard firstLine.hasPrefix("#!"), firstLine.count > 2 else {
                throw LucentError.pluginInvalid("自定义 Shebang 脚本首行必须以 '#!' 声明解释器路径（如 #!/usr/bin/env node）")
            }
            return (scriptURL, trailingArgs)
        }
    }
}

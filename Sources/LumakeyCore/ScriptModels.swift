import LumakeyFoundation; import LumakeySearch; import LumakeyMedia; import LumakeySystem
import Foundation

public enum ScriptRuntime: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case zsh
    case bash
    case python3
    case appleScript
    case swift
    case customShebang

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .zsh: "Zsh"
        case .bash: "Bash"
        case .python3: "Python 3"
        case .appleScript: "AppleScript"
        case .swift: "Swift"
        case .customShebang: L10n.pick("自定义 Shebang", "Custom Shebang")
        }
    }

    public var badgeLabel: String {
        switch self {
        case .zsh: "ZSH"
        case .bash: "BASH"
        case .python3: "PY3"
        case .appleScript: "OSA"
        case .swift: "SWIFT"
        case .customShebang: "SHEBANG"
        }
    }

    public var defaultFileExtension: String {
        switch self {
        case .zsh: "zsh"
        case .bash: "sh"
        case .python3: "py"
        case .appleScript: "applescript"
        case .swift: "swift"
        case .customShebang: "sh"
        }
    }

    public var defaultTemplateCode: String {
        switch self {
        case .zsh:
            """
            #!/bin/zsh
            set -euo pipefail

            echo "Hello from Lumakey Zsh! Query: ${LUMAKEY_QUERY:-none}"
            """
        case .bash:
            """
            #!/bin/bash
            set -euo pipefail

            echo "Hello from Lumakey Bash! Query: ${LUMAKEY_QUERY:-none}"
            """
        case .python3:
            """
            #!/usr/bin/env python3
            import os

            query = os.environ.get("LUMAKEY_QUERY", "").strip()
            print(f"Python3 Quick Action: {query or 'ready'}")
            """
        case .appleScript:
            """
            tell application "Finder"
                if (count of Finder windows) > 0 then
                    return POSIX path of (target of front window as alias)
                else
                    return POSIX path of (desktop as alias)
                end if
            end tell
            """
        case .swift:
            """
            #!/usr/bin/env swift
            import Foundation

            let query = ProcessInfo.processInfo.environment["LUMAKEY_QUERY"] ?? ""
            print("Swift Quick Action: \\(query.isEmpty ? "ready" : query)")
            """
        case .customShebang:
            """
            #!/usr/bin/env node
            const query = process.env.LUMAKEY_QUERY || "";
            console.log(`Node Quick Action: ${query || "ready"}`);
            """
        }
    }

    public static func infer(fileExtension: String, firstLine: String) -> ScriptRuntime {
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("#!") {
            if trimmed.contains("python") { return .python3 }
            if trimmed.contains("osascript") { return .appleScript }
            if trimmed.contains("swift") { return .swift }
            if trimmed.hasSuffix("/zsh") || trimmed.contains("env zsh") { return .zsh }
            if trimmed.hasSuffix("/bash") || trimmed.contains("env bash") { return .bash }
            return .customShebang
        }
        switch fileExtension.lowercased() {
        case "py": return .python3
        case "applescript", "scpt": return .appleScript
        case "swift": return .swift
        case "bash": return .bash
        case "zsh", "sh": return .zsh
        default: return .customShebang
        }
    }
}

public enum ScriptOutputMode: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case toast
    case inlinePreview
    case copyToClipboard
    case pasteToFrontApp
    case openReader

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .toast: L10n.pick("静默执行 + 状态提示", "Silent + Toast")
        case .inlinePreview: L10n.pick("浮窗右侧预览输出", "Inline Side Preview")
        case .copyToClipboard: L10n.pick("结果复制到剪贴板", "Copy Output")
        case .pasteToFrontApp: L10n.pick("结果粘贴回原窗口", "Paste to Active App")
        case .openReader: L10n.pick("独立阅读窗打开", "Open in Reader")
        }
    }

    public var shortBadge: String {
        switch self {
        case .toast: L10n.pick("轻提示", "Toast")
        case .inlinePreview: L10n.pick("浮窗预览", "Preview")
        case .copyToClipboard: L10n.pick("复制结果", "Copy")
        case .pasteToFrontApp: L10n.pick("回填粘贴", "Paste")
        case .openReader: L10n.pick("阅读窗", "Reader")
        }
    }
}

public struct ScriptRecord: Identifiable, Codable, Sendable, Hashable, Equatable {
    public var id: String
    public var title: String
    public var englishTitle: String?
    public var subtitle: String
    public var englishSubtitle: String?
    public var keywords: [String]
    public var category: String
    public var fileName: String
    public var runtime: ScriptRuntime
    public var outputMode: ScriptOutputMode
    public var icon: String
    public var accentColor: String
    public var isEnabled: Bool
    public var includeInGlobalSearch: Bool
    public var pinnedInQuickBar: Bool
    public var showInMenuBar: Bool
    public var hotKey: String?
    public var allowedScopes: Set<PluginResourceScope>
    public var passClipboard: Bool
    public var timeoutSeconds: Double
    public var lastSyncedHash: String?
    public var updatedAt: Date

    public init(
        id: String,
        title: String,
        englishTitle: String? = nil,
        subtitle: String = "",
        englishSubtitle: String? = nil,
        keywords: [String] = [],
        category: String = "效率",
        fileName: String,
        runtime: ScriptRuntime = .zsh,
        outputMode: ScriptOutputMode = .inlinePreview,
        icon: String = "terminal.fill",
        accentColor: String = "teal",
        isEnabled: Bool = true,
        includeInGlobalSearch: Bool = true,
        pinnedInQuickBar: Bool = false,
        showInMenuBar: Bool = false,
        hotKey: String? = nil,
        allowedScopes: Set<PluginResourceScope> = [],
        passClipboard: Bool = false,
        timeoutSeconds: Double = 10.0,
        lastSyncedHash: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.englishTitle = englishTitle
        self.subtitle = subtitle
        self.englishSubtitle = englishSubtitle
        self.keywords = keywords
        self.category = category
        self.fileName = fileName
        self.runtime = runtime
        self.outputMode = outputMode
        self.icon = icon
        self.accentColor = accentColor
        self.isEnabled = isEnabled
        self.includeInGlobalSearch = includeInGlobalSearch
        self.pinnedInQuickBar = pinnedInQuickBar
        self.showInMenuBar = showInMenuBar
        self.hotKey = hotKey
        self.allowedScopes = allowedScopes
        self.passClipboard = passClipboard
        self.timeoutSeconds = min(max(timeoutSeconds, 3.0), 30.0)
        self.lastSyncedHash = lastSyncedHash
        self.updatedAt = updatedAt
    }

    public var displayTitle: String {
        if L10n.isEnglish, let en = englishTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !en.isEmpty {
            return en
        }
        return title
    }

    public var displaySubtitle: String {
        if L10n.isEnglish, let en = englishSubtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !en.isEmpty {
            return en
        }
        return subtitle.isEmpty ? fileName : subtitle
    }

    public var symbolIconName: String {
        let trimmed = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.contains("/") || trimmed.lowercased().hasSuffix(".svg") || trimmed.lowercased().hasSuffix(".png") {
            return "terminal.fill"
        }
        return trimmed
    }

    public func customIconURL(in scriptsDirectory: URL) -> URL? {
        let trimmed = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("/") || trimmed.lowercased().hasSuffix(".svg") || trimmed.lowercased().hasSuffix(".png") else {
            return nil
        }
        guard !trimmed.hasPrefix("/"), !trimmed.contains(".."), !trimmed.contains("\\") else { return nil }
        let rootStd = scriptsDirectory.resolvingSymlinksInPath().standardizedFileURL.path
        let candidate = scriptsDirectory.appendingPathComponent(trimmed, isDirectory: false).resolvingSymlinksInPath().standardizedFileURL
        guard candidate.path.hasPrefix(rootStd + "/"), FileManager.default.fileExists(atPath: candidate.path) else {
            return nil
        }
        return candidate
    }
}

public struct ScriptRunOutcome: Sendable, Hashable {
    public let scriptID: String
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let durationMs: Int

    public init(scriptID: String, exitCode: Int32, stdout: String, stderr: String, durationMs: Int) {
        self.scriptID = scriptID
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.durationMs = durationMs
    }

    public var combinedOutput: String {
        let out = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let err = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !out.isEmpty && !err.isEmpty { return "\(out)\n\(err)" }
        return !out.isEmpty ? out : err
    }
}

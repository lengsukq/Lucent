import Foundation

/// 自定义插件窗口通用文件动作的安全与路径归一化策略（纯逻辑、无 UI 依赖）。
public enum PluginWindowFileActionPolicy {
    public static let maxPathsPerRequest = 64

    /// 禁止经由 `files.open` 直接启动的应用程序、安装包与可执行脚本后缀；此类文件会降级为在访达中定位展示。
    private static let directOpenBlockedExtensions: Set<String> = [
        "app", "action", "command", "inetloc", "mpkg", "osascript",
        "pkg", "scpt", "scptd", "terminal", "tool", "workflow"
    ]

    public static func resolveExistingURLs(
        from rawPaths: [String],
        maxCount: Int = maxPathsPerRequest
    ) -> [URL] {
        let cap = max(1, min(maxCount, maxPathsPerRequest))
        let fm = FileManager.default
        var seen = Set<String>()
        var urls: [URL] = []
        urls.reserveCapacity(min(rawPaths.count, cap))

        for raw in rawPaths {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("/") else { continue }
            let url = URL(fileURLWithPath: trimmed).standardizedFileURL
            guard fm.fileExists(atPath: url.path) else { continue }
            if seen.insert(url.path).inserted {
                urls.append(url)
                if urls.count >= cap { break }
            }
        }
        return urls
    }

    public static func isSafeForDirectOpen(_ url: URL) -> Bool {
        let standardized = url.standardizedFileURL
        guard standardized.isFileURL else { return false }
        let ext = standardized.pathExtension.lowercased()
        if directOpenBlockedExtensions.contains(ext) {
            return false
        }
        if let values = try? standardized.resourceValues(forKeys: [.isApplicationKey]),
           values.isApplication == true {
            return false
        }
        return true
    }
}

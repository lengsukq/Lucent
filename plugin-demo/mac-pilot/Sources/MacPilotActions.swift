import Darwin
import Foundation
import PluginKit

struct SystemPane {
    let id: String
    let zhTitle: String
    let enTitle: String
    let uri: String
    let icon: String
    let keywords: [String]
}

let systemPanes: [SystemPane] = [
    SystemPane(id: "bluetooth", zhTitle: "蓝牙设置", enTitle: "Bluetooth", uri: "x-apple.systempreferences:com.apple.BluetoothSettings", icon: "dot.radiowaves.left.and.right", keywords: ["蓝牙", "lanya", "bluetooth", "bt"]),
    SystemPane(id: "displays", zhTitle: "显示器与分辨率", enTitle: "Displays", uri: "x-apple.systempreferences:com.apple.Displays-Settings.extension", icon: "display", keywords: ["显示器", "xianshiqi", "display", "monitor", "分辨率"]),
    SystemPane(id: "sound", zhTitle: "声音与输入输出", enTitle: "Sound", uri: "x-apple.systempreferences:com.apple.Sound-Settings.extension", icon: "speaker.wave.3.fill", keywords: ["声音", "shengyin", "sound", "audio", "麦克风"]),
    SystemPane(id: "network", zhTitle: "网络与代理", enTitle: "Network", uri: "x-apple.systempreferences:com.apple.Network-Settings.extension", icon: "network", keywords: ["网络", "wangluo", "network", "proxy", "代理"]),
    SystemPane(id: "wifi", zhTitle: "Wi-Fi 无线局域网", enTitle: "Wi-Fi", uri: "x-apple.systempreferences:com.apple.wifi-settings-extension", icon: "wifi", keywords: ["wifi", "无线网", "wlan"]),
    SystemPane(id: "battery", zhTitle: "电池与能耗", enTitle: "Battery", uri: "x-apple.systempreferences:com.apple.Battery-Settings.extension", icon: "battery.100percent", keywords: ["电池", "dianchi", "battery", "电源"]),
    SystemPane(id: "keyboard", zhTitle: "键盘与快捷键", enTitle: "Keyboard", uri: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension", icon: "keyboard", keywords: ["键盘", "jianpan", "keyboard"]),
    SystemPane(id: "trackpad", zhTitle: "触控板与手势", enTitle: "Trackpad", uri: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension", icon: "rectangle.and.hand.point.up.left.fill", keywords: ["触控板", "chukongban", "trackpad"]),
    SystemPane(id: "notifications", zhTitle: "通知与专注模式", enTitle: "Notifications", uri: "x-apple.systempreferences:com.apple.Notifications-Settings.extension", icon: "bell.badge.fill", keywords: ["通知", "tongzhi", "notifications"]),
    SystemPane(id: "accessibility", zhTitle: "隐私 › 辅助功能授权", enTitle: "Privacy > Accessibility", uri: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility", icon: "figure.wave.circle.fill", keywords: ["辅助功能", "fuzhugongneng", "accessibility", "ax权限"]),
    SystemPane(id: "screen-recording", zhTitle: "隐私 › 屏幕录制授权", enTitle: "Privacy > Screen Recording", uri: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture", icon: "record.circle", keywords: ["屏幕录制", "录屏权限", "screen recording"]),
    SystemPane(id: "full-disk", zhTitle: "隐私 › 完全磁盘访问权限", enTitle: "Privacy > Full Disk Access", uri: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles", icon: "externaldrive.badge.checkmark", keywords: ["完全磁盘访问", "磁盘权限", "full disk access"]),
    SystemPane(id: "login-items", zhTitle: "通用 › 登录项与后台扩展", enTitle: "General > Login Items", uri: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension", icon: "person.badge.key.fill", keywords: ["登录项", "开机自启", "login items", "startup"]),
    SystemPane(id: "storage", zhTitle: "通用 › 储存空间清理", enTitle: "General > Storage", uri: "x-apple.systempreferences:com.apple.settings.Storage", icon: "internaldrive.fill", keywords: ["储存空间", "磁盘空间", "storage"]),
    SystemPane(id: "wallpaper", zhTitle: "墙纸与屏幕保护程序", enTitle: "Wallpaper", uri: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension", icon: "photo.on.rectangle", keywords: ["壁纸", "墙纸", "wallpaper"]),
    SystemPane(id: "security", zhTitle: "隐私与安全性总览", enTitle: "Privacy & Security", uri: "x-apple.systempreferences:com.apple.preference.security", icon: "lock.shield.fill", keywords: ["隐私", "安全性", "仍要打开", "security", "gatekeeper"])
]

private let fileTemplates: [String: (stem: String, body: String)] = [
    "md": ("Untitled", "# Untitled\n\n"),
    "txt": ("Untitled", ""),
    "json": ("data", "{\n  \n}\n"),
    "py": ("script", "#!/usr/bin/env python3\n\n"),
    "sh": ("run", "#!/usr/bin/env bash\nset -euo pipefail\n\n")
]

func syncPanesSearchIndex(dataDir: String, enabled: Bool, isEn: Bool) {
    guard !dataDir.isEmpty else { return }
    if !enabled { PluginOutput.writeSearchIndex([], to: dataDir); return }
    let items: [SearchIndexItem] = systemPanes.map { p in
        SearchIndexItem(
            id: "pane-\(p.id)",
            title: isEn ? p.enTitle : p.zhTitle,
            subtitle: isEn ? "Open macOS System Settings pane" : "直达 macOS 系统设置 · \(p.enTitle)",
            url: p.uri, icon: p.icon, tags: p.keywords, priority: 32
        )
    }
    PluginOutput.writeSearchIndex(items, to: dataDir)
}

func formatBytes(_ bytes: Int64) -> String {
    var val = Double(max(0, bytes))
    for u in ["B", "KB", "MB", "GB", "TB"] {
        if val < 1024.0 || u == "TB" {
            return u == "B" ? "\(Int(val)) B" : String(format: "%.1f %@", val, u)
        }
        val /= 1024.0
    }
    return String(format: "%.1f TB", val)
}

struct ExternalVolume {
    let name: String
    let path: String
    let total: Int64
    let free: Int64
}

func listExternalVolumes(root: URL = URL(fileURLWithPath: "/Volumes", isDirectory: true)) -> [ExternalVolume] {
    let fm = FileManager.default
    guard let entries = try? fm.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: [.isSymbolicLinkKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey],
        options: [.skipsHiddenFiles]
    ) else { return [] }
    let rootSysNum = (try? fm.attributesOfItem(atPath: "/")[.systemNumber]) as? Int
    var out: [ExternalVolume] = []
    for entry in entries.sorted(by: { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }) {
        guard let vals = try? entry.resourceValues(forKeys: [.isSymbolicLinkKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
              vals.isSymbolicLink != true else { continue }
        let entrySysNum = (try? fm.attributesOfItem(atPath: entry.path)[.systemNumber]) as? Int
        if let rootSysNum, let entrySysNum, entrySysNum == rootSysNum { continue }
        out.append(ExternalVolume(
            name: entry.lastPathComponent, path: entry.path,
            total: Int64(vals.volumeTotalCapacity ?? 0), free: Int64(vals.volumeAvailableCapacity ?? 0)
        ))
    }
    return out
}

func resolveActiveFinderDir(input: PluginInput) -> URL {
    let fm = FileManager.default
    if let rawCtx = input.rawJSON["context"] as? [String: Any],
       let explicit = (rawCtx["directory"] as? String) ?? (rawCtx["path"] as? String),
       !explicit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        let expanded = (explicit as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: expanded, isDirectory: &isDir) {
            let url = URL(fileURLWithPath: expanded).standardizedFileURL
            return isDir.boolValue ? url : url.deletingLastPathComponent()
        }
    }
    if let firstPath = input.context?.primaryFilePath {
        let expanded = (firstPath as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: expanded, isDirectory: &isDir) {
            let url = URL(fileURLWithPath: expanded).standardizedFileURL
            return isDir.boolValue ? url : url.deletingLastPathComponent()
        }
    }
    let osa = SubprocessRunner.run(
        executable: "/usr/bin/osascript",
        arguments: ["-e", #"tell application "Finder" to if (count of Finder windows) > 0 then get POSIX path of (target of front window as alias)"#],
        timeoutSeconds: 1.8
    )
    let finderOut = osa.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    var isDir: ObjCBool = false
    if !finderOut.isEmpty && fm.fileExists(atPath: finderOut, isDirectory: &isDir) && isDir.boolValue {
        return URL(fileURLWithPath: finderOut).standardizedFileURL
    }
    return fm.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true).standardizedFileURL
}

func createUniqueBlankFile(in folder: URL, requestedName: String, defaultExt: String) -> URL {
    let fm = FileManager.default
    try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
    let cleanReq = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
    let ext = defaultExt.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
    let resolvedExt = ext.isEmpty ? "md" : ext
    var (stemDefault, body) = fileTemplates[resolvedExt] ?? ("Untitled", "")

    let baseName: String
    if !cleanReq.isEmpty {
        if cleanReq.contains(".") && !cleanReq.hasPrefix(".") {
            baseName = cleanReq
            body = fileTemplates[URL(fileURLWithPath: cleanReq).pathExtension.lowercased()]?.body ?? ""
        } else {
            baseName = "\(cleanReq).\(resolvedExt)"
        }
    } else {
        baseName = "\(stemDefault).\(resolvedExt)"
    }

    let baseURL = URL(fileURLWithPath: baseName)
    let stem = baseURL.deletingPathExtension().lastPathComponent
    let suffix = baseURL.pathExtension.isEmpty ? "" : ".\(baseURL.pathExtension)"
    var cand = folder.appendingPathComponent(baseName)
    var idx = 2
    while fm.fileExists(atPath: cand.path) {
        cand = folder.appendingPathComponent("\(stem)-\(idx)\(suffix)")
        idx += 1
    }
    try? body.write(to: cand, atomically: true, encoding: .utf8)
    if suffix == ".py" || suffix == ".sh" {
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cand.path)
    }
    return cand
}

struct RunningAppInfo {
    let pid: Int32
    let name: String
    let rssKB: Int
}

func listUserApps(filterQuery: String) -> [RunningAppInfo] {
    let q = filterQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let res = SubprocessRunner.run(executable: "/bin/ps", arguments: ["-axo", "pid=,rss=,comm="], timeoutSeconds: 2.0)
    let ownPID = Darwin.getpid()
    var seen: [String: RunningAppInfo] = [:]
    for rawLine in res.stdout.components(separatedBy: .newlines) {
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { continue }
        let parts = trimmed.split(maxSplits: 2, whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count >= 3, let pid = Int32(parts[0]), let rssKB = Int(parts[1]) else { continue }
        let comm = parts[2]
        guard pid != ownPID, let appRange = comm.range(of: ".app/Contents/MacOS/"), !comm.contains("/System/Library/") else { continue }
        let appName = (String(comm[..<appRange.lowerBound]) as NSString).lastPathComponent
        if appName == "Lucent" || (!q.isEmpty && !appName.lowercased().contains(q)) { continue }
        if let prev = seen[appName], prev.rssKB >= rssKB { continue }
        seen[appName] = RunningAppInfo(pid: pid, name: appName, rssKB: rssKB)
    }
    return Array(seen.values.sorted { $0.rssKB > $1.rssKB }.prefix(18))
}

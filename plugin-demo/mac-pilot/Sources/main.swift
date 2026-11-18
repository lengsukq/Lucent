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

private let systemPanes: [SystemPane] = [
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

private func syncPanesSearchIndex(dataDir: String, enabled: Bool, isEn: Bool) {
    guard !dataDir.isEmpty else { return }
    if !enabled {
        PluginOutput.writeSearchIndex([], to: dataDir)
        return
    }
    let items: [SearchIndexItem] = systemPanes.map { p in
        SearchIndexItem(
            id: "pane-\(p.id)",
            title: isEn ? p.enTitle : p.zhTitle,
            subtitle: isEn ? "Open macOS System Settings pane" : "直达 macOS 系统设置 · \(p.enTitle)",
            url: p.uri,
            icon: p.icon,
            tags: p.keywords,
            priority: 32
        )
    }
    PluginOutput.writeSearchIndex(items, to: dataDir)
}

private func formatBytes(_ bytes: Int64) -> String {
    var val = Double(max(0, bytes))
    let units = ["B", "KB", "MB", "GB", "TB"]
    for u in units {
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

private func listExternalVolumes(root: URL = URL(fileURLWithPath: "/Volumes", isDirectory: true)) -> [ExternalVolume] {
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
        let total = Int64(vals.volumeTotalCapacity ?? 0)
        let free = Int64(vals.volumeAvailableCapacity ?? 0)
        out.append(ExternalVolume(name: entry.lastPathComponent, path: entry.path, total: total, free: free))
    }
    return out
}

private func resolveActiveFinderDir(input: PluginInput) -> URL {
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

private func createUniqueBlankFile(in folder: URL, requestedName: String, defaultExt: String) -> URL {
    let fm = FileManager.default
    try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
    let cleanReq = requestedName
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: ":", with: "_")
    let ext = defaultExt.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
    let resolvedExt = ext.isEmpty ? "md" : ext
    var (stemDefault, body) = fileTemplates[resolvedExt] ?? ("Untitled", "")

    let baseName: String
    if !cleanReq.isEmpty {
        if cleanReq.contains(".") && !cleanReq.hasPrefix(".") {
            baseName = cleanReq
            let fExt = URL(fileURLWithPath: cleanReq).pathExtension.lowercased()
            body = fileTemplates[fExt]?.body ?? ""
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

private func listUserApps(filterQuery: String) -> [RunningAppInfo] {
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
        guard pid != ownPID,
              let appRange = comm.range(of: ".app/Contents/MacOS/"),
              !comm.contains("/System/Library/") else { continue }
        let prefixPath = String(comm[..<appRange.lowerBound])
        let appName = (prefixPath as NSString).lastPathComponent
        if appName == "Lumakey" { continue }
        if !q.isEmpty && !appName.lowercased().contains(q) { continue }
        if let prev = seen[appName], prev.rssKB >= rssKB { continue }
        seen[appName] = RunningAppInfo(pid: pid, name: appName, rssKB: rssKB)
    }
    return Array(seen.values.sorted { $0.rssKB > $1.rssKB }.prefix(18))
}

let input = PluginInput.read()
let isEn = input.isEnglish
let query = input.query.trimmingCharacters(in: .whitespacesAndNewlines)
let dataDir = input.dataDir
let bridge = HostBridgeClient(input: input, timeoutSeconds: 4)

let syncPanes = input.cfgBool("syncSettingsPanesToSearch", default: true)
syncPanesSearchIndex(dataDir: dataDir, enabled: syncPanes, isEn: isEn)

let argv = input.arguments
var flag = argv.first ?? ""
var toast: String? = nil

if flag == "--sleep" {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    proc.arguments = ["sleepnow"]
    try? proc.run()
    PluginOutput.emit(ViewPayload(
        schemaVersion: 2,
        title: isEn ? "Putting Mac to Sleep…" : "正在让 Mac 进入睡眠…",
        badge: "SLEEP",
        effect: PostActionEffect(toast: isEn ? "Mac going to sleep" : "已发送睡眠指令", closeOverlay: true)
    ))
    exit(0)
}

if flag == "--mute-toggle" {
    _ = bridge.call(capability: "systemControl", action: "setMute", params: ["muted": "toggle"])
    toast = isEn ? "Toggled system mute" : "已切换系统静音状态"
    flag = "--audio"
}

if flag == "--caffeine-toggle" {
    _ = bridge.call(capability: "systemControl", action: "setCaffeine")
    toast = isEn ? "Toggled Keep-Awake (Caffeine)" : "已切换防休眠常亮保护"
    flag = "--audio"
}

if flag == "--set-vol", argv.count >= 2, let rawPct = Int(argv[1]) {
    let pct = min(max(rawPct, 0), 100)
    _ = bridge.call(capability: "systemControl", action: "setVolume", params: ["percent": pct])
    toast = isEn ? "Volume set to \(pct)%" : "系统音量已设为 \(pct)%"
    flag = "--audio"
}

if flag == "--panes" {
    let q = query.lowercased()
    let rows: [ViewItem] = systemPanes.compactMap { p in
        if !q.isEmpty {
            let matched = p.zhTitle.lowercased().contains(q)
                || p.enTitle.lowercased().contains(q)
                || p.keywords.contains(where: { $0.lowercased().contains(q) })
            if !matched { return nil }
        }
        return ViewItem(
            id: "pane-\(p.id)",
            title: isEn ? p.enTitle : p.zhTitle,
            subtitle: p.uri,
            icon: p.icon,
            badge: "SETTINGS",
            openURL: p.uri
        )
    }
    PluginOutput.emit(ViewPayload(
        schemaVersion: 2,
        title: isEn ? "macOS System Settings Panes" : "macOS 系统设置分栏直达",
        subtitle: isEn
            ? "\(rows.count) pane(s) synced to 0ms launcher search"
            : "共 \(rows.count) 项高频分栏（已同步 ⌥Space 免前缀搜索）",
        badge: "SETTINGS",
        items: rows,
        effect: PostActionEffect(reloadSearchIndex: true)
    ))
    exit(0)
}

if ["--finder", "--new-file", "--open-term"].contains(flag) {
    let targetDir: URL
    if (flag == "--new-file" || flag == "--open-term"), argv.count >= 2 {
        targetDir = URL(fileURLWithPath: argv[1]).standardizedFileURL
    } else {
        targetDir = resolveActiveFinderDir(input: input)
    }
    let defExt = input.cfgString("defaultNewFileExt", default: "md")
    if flag == "--new-file" {
        let ext = argv.count >= 3 ? argv[2] : defExt
        let created = createUniqueBlankFile(in: targetDir, requestedName: query, defaultExt: ext)
        toast = isEn ? "Created \(created.lastPathComponent)" : "已新建文件：\(created.lastPathComponent)"
    } else if flag == "--open-term" {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = ["-a", "Terminal", targetDir.path]
        try? proc.run()
        toast = isEn ? "Opened in Terminal" : "已在终端打开该目录"
    }

    var items: [ViewItem] = [
        ViewItem(
            id: "copy-finder-path",
            title: isEn ? "Copy Directory Path: \(targetDir.lastPathComponent)" : "复制当前目录路径：\(targetDir.lastPathComponent)",
            subtitle: targetDir.path,
            icon: "doc.on.doc.fill",
            badge: "PATH",
            copyText: targetDir.path
        ),
        ViewItem(
            id: "open-in-term",
            title: isEn ? "Open Directory in Terminal" : "在「终端 (Terminal)」中打开此目录",
            subtitle: targetDir.path,
            icon: "terminal.fill",
            badge: "TERM",
            commandArgs: ["--open-term", targetDir.path]
        )
    ]
    for (ext, label) in [("md", "Markdown (.md)"), ("txt", "Plain Text (.txt)"), ("json", "JSON (.json)"), ("py", "Python (.py)")] {
        let sub: String
        if isEn {
            sub = !query.isEmpty ? "File name from search bar: '\(query)'" : "Creates Untitled.\(ext) safely without overwriting"
        } else {
            sub = !query.isEmpty ? "使用搜索框文件名「\(query)」创建" : "防重名安全创建 Untitled.\(ext)"
        }
        items.append(ViewItem(
            id: "mk-\(ext)",
            title: isEn ? "New \(label) File Here" : "在此目录新建空白 \(label) 文件",
            subtitle: sub,
            icon: "doc.badge.plus",
            badge: ".\(ext.uppercased())",
            commandArgs: ["--new-file", targetDir.path, ext]
        ))
    }
    PluginOutput.emit(ViewPayload(
        schemaVersion: 2,
        title: isEn ? "Finder Helper · \(targetDir.lastPathComponent)" : "访达目录助手 · \(targetDir.lastPathComponent)",
        subtitle: targetDir.path,
        badge: "FINDER",
        items: items,
        effect: toast.map { PostActionEffect(toast: $0) }
    ))
    exit(0)
}

if ["--volumes", "--eject-one", "--eject-all"].contains(flag) {
    let volumesRoot = ProcessInfo.processInfo.environment["LUMAKEY_VOLUMES_ROOT"]
        .map { URL(fileURLWithPath: $0, isDirectory: true) }
        ?? URL(fileURLWithPath: "/Volumes", isDirectory: true)

    if flag == "--eject-one", argv.count >= 2 {
        let res = SubprocessRunner.run(executable: "/usr/sbin/diskutil", arguments: ["eject", argv[1]], timeoutSeconds: 6.0)
        let errTrim = res.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if isEn {
            toast = res.exitCode == 0 ? "Safely ejected volume" : (errTrim.isEmpty ? "Eject failed" : errTrim)
        } else {
            toast = res.exitCode == 0 ? "已安全推出磁盘" : "推出失败：\(String(errTrim.prefix(48)))"
        }
    } else if flag == "--eject-all" {
        for v in listExternalVolumes(root: volumesRoot) {
            _ = SubprocessRunner.run(executable: "/usr/sbin/diskutil", arguments: ["eject", v.path], timeoutSeconds: 6.0)
        }
        toast = isEn ? "Ejected external volumes" : "已请求安全推出全部外置卷"
    }

    let vols = listExternalVolumes(root: volumesRoot)
    var vItems: [ViewItem] = []
    if vols.count >= 2 {
        vItems.append(ViewItem(
            id: "eject-all-btn",
            title: isEn ? "Safely Eject All (\(vols.count) Volumes)" : "一键安全推出全部外置磁盘 (\(vols.count) 个)",
            subtitle: isEn ? "Unmounts all non-root mounted volumes cleanly" : "依次安全卸载所有外置卷与 DMG 镜像",
            icon: "eject.circle.fill",
            badge: "EJECT ALL",
            commandArgs: ["--eject-all"]
        ))
    }
    for v in vols {
        vItems.append(ViewItem(
            id: "vol-\(v.name)",
            title: v.name,
            subtitle: "\(v.path) · Free \(formatBytes(v.free)) / \(formatBytes(v.total))",
            icon: "externaldrive.fill",
            badge: "EJECT",
            commandArgs: ["--eject-one", v.path]
        ))
    }
    if vItems.isEmpty {
        vItems.append(ViewItem(
            id: "no-vols",
            title: isEn ? "No External Volumes Mounted" : "当前未检测到已挂载的外置磁盘或镜像",
            subtitle: isEn ? "/Volumes contains only system root volume" : "插入 U 盘、移动硬盘或挂载 DMG 后可在此一键安全推出",
            icon: "checkmark.seal.fill",
            badge: "CLEAN"
        ))
    }
    PluginOutput.emit(ViewPayload(
        schemaVersion: 2,
        title: isEn ? "External Disks & DMG Ejector" : "外置磁盘与镜像安全推出",
        subtitle: isEn ? "\(vols.count) external volume(s)" : "当前共 \(vols.count) 个外置挂载卷",
        badge: "\(vols.count) VOL",
        items: vItems,
        effect: toast.map { PostActionEffect(toast: $0) }
    ))
    exit(0)
}

if ["--apps", "--quit-app", "--kill-app"].contains(flag) {
    if flag == "--quit-app", argv.count >= 2 {
        let escaped = argv[1].replacingOccurrences(of: "\"", with: "\\\"")
        _ = SubprocessRunner.run(executable: "/usr/bin/osascript", arguments: ["-e", "tell application \"\(escaped)\" to quit"], timeoutSeconds: 3.0)
        toast = isEn ? "Sent Quit to \(argv[1])" : "已通知「\(argv[1])」优雅退出"
    } else if flag == "--kill-app", argv.count >= 2, let pid = Int32(argv[1]), pid > 1 {
        if Darwin.kill(pid, SIGKILL) == 0 {
            toast = isEn ? "Force terminated process" : "已强制结束该进程"
        }
    }
    let apps = listUserApps(filterQuery: query)
    let aItems: [ViewItem] = apps.map { a in
        let memMB = Int((Double(a.rssKB) / 1024.0).rounded())
        return ViewItem(
            id: "app-\(a.pid)",
            title: a.name,
            subtitle: "PID \(a.pid) · RAM \(memMB) MB",
            icon: "app.fill",
            badge: "\(memMB) MB",
            actions: [
                ViewAction(id: "q-\(a.pid)", label: isEn ? "Quit" : "退出", commandArgs: ["--quit-app", a.name]),
                ViewAction(
                    id: "k-\(a.pid)",
                    label: isEn ? "Force Quit" : "强制退出",
                    style: "destructive",
                    commandArgs: ["--kill-app", String(a.pid)],
                    confirmMessage: isEn
                        ? "Force quit \(a.name) (PID \(a.pid))?"
                        : "确认强制结束「\(a.name)」(PID \(a.pid))？未保存内容可能丢失。"
                )
            ]
        )
    }
    PluginOutput.emit(ViewPayload(
        schemaVersion: 2,
        title: isEn ? "Running Apps Manager" : "运行中应用管家",
        subtitle: isEn ? "Sorted by memory footprint" : "按实时物理内存占用排序 · 支持优雅退出与强退",
        badge: "\(apps.count) APPS",
        items: aItems,
        effect: toast.map { PostActionEffect(toast: $0) }
    ))
    exit(0)
}

if !query.isEmpty, query.allSatisfy(\.isNumber), let qPct = Int(query), (0...100).contains(qPct) {
    _ = bridge.call(capability: "systemControl", action: "setVolume", params: ["percent": qPct])
    toast = isEn ? "Volume set to \(qPct)%" : "已将系统音量调节为 \(qPct)%"
}

let st = bridge.call(capability: "systemControl", action: "status")
let vol = st.ok ? st.int("volumePercent", default: 50) : 50
let muted = st.ok ? st.bool("isMuted", default: false) : false
let caf = st.ok ? st.bool("caffeineActive", default: false) : false

let summary = isEn
    ? "Vol \(vol)% \(muted ? "(Muted)" : "") · Caffeine \(caf ? "ON" : "OFF")"
    : "音量 \(vol)%\(muted ? "（已静音）" : "") · 防休眠\(caf ? "开启" : "关闭")"
let statusBadge = caf ? "CAFFEINE" : "\(vol)%"
PluginOutput.writeRuntimeStatus(summary: summary, badge: statusBadge, to: dataDir)

var mainItems: [ViewItem] = []
if !st.ok {
    mainItems.append(ViewItem(
        id: "grant-sys-bridge",
        title: isEn ? "Grant 'systemControl' Permission in Plugin Settings →" : "首次使用请点此开启「系统控制 (systemControl)」桥接权限 →",
        subtitle: isEn ? "Required to adjust macOS volume, mute & sleep prevention" : "授权后即可一键调节音量档位、静音与防休眠常亮",
        icon: "lock.open.display",
        badge: "GRANT",
        openURL: "lumakey://settings/plugin/mac-pilot"
    ))
}

mainItems.append(contentsOf: [
    ViewItem(
        id: "audio-row",
        title: isEn
            ? "System Audio: \(muted ? "Muted" : "\(vol)%") (Type 0–100 to set)"
            : "系统音量：\(muted ? "已静音" : "\(vol)%")（搜索框直接输 0–100 可精准设音量）",
        subtitle: isEn ? "Quick presets & mute toggle" : "一键切换静音或常用音量档位",
        icon: muted ? "speaker.slash.fill" : "speaker.wave.3.fill",
        badge: muted ? "MUTED" : "\(vol)%",
        actions: [
            ViewAction(id: "m-tog", label: isEn ? (muted ? "Unmute" : "Mute") : (muted ? "取消静音" : "静音"), commandArgs: ["--mute-toggle"]),
            ViewAction(id: "v-25", label: "25%", commandArgs: ["--set-vol", "25"]),
            ViewAction(id: "v-50", label: "50%", commandArgs: ["--set-vol", "50"]),
            ViewAction(id: "v-80", label: "80%", commandArgs: ["--set-vol", "80"])
        ]
    ),
    ViewItem(
        id: "caf-row",
        title: isEn
            ? "Keep Mac Awake (Caffeine): \(caf ? "ACTIVE" : "OFF")"
            : "防休眠常亮保护 (Caffeine)：\(caf ? "已开启" : "未开启")",
        subtitle: isEn
            ? "Prevents idle display dimming & sleep during downloads or builds"
            : "跑编译、传大文件或阅读长文时阻止自动息屏睡眠",
        icon: caf ? "cup.and.saucer.fill" : "cup.and.saucer",
        badge: caf ? "ON" : "OFF",
        commandArgs: ["--caffeine-toggle"]
    ),
    ViewItem(
        id: "nav-finder",
        title: isEn
            ? "Finder Helper: New Blank File / Copy Path / Terminal →"
            : "访达助手：在当前窗口新建空白文件 / 复制路径 / 终端打开 →",
        subtitle: isEn
            ? "Supports .md, .txt, .json, .py with collision-safe naming"
            : "支持新建 .md / .txt / .json / .py，自动防重名",
        icon: "doc.badge.plus",
        badge: "FINDER",
        commandArgs: ["--finder"]
    ),
    ViewItem(
        id: "nav-panes",
        title: isEn
            ? "macOS System Settings Deep Links (16 Panes) →"
            : "直达 macOS 系统设置分栏（蓝牙 / 显示器 / 权限等 16 项）→",
        subtitle: isEn
            ? "Also searchable directly from ⌥Space without prefix"
            : "已同步 ⌥Space 免前缀索引，搜「蓝牙」「显示器」秒达",
        icon: "gear.badge.checkmark",
        badge: "16 PANES",
        commandArgs: ["--panes"]
    ),
    ViewItem(
        id: "nav-vols",
        title: isEn ? "Safely Eject External Disks & DMGs →" : "安全推出外置磁盘与 DMG 镜像 →",
        subtitle: isEn ? "Inspect free space and unmount cleanly" : "查看挂载卷剩余容量并一键安全推出",
        icon: "eject.circle.fill",
        badge: "VOLUMES",
        commandArgs: ["--volumes"]
    ),
    ViewItem(
        id: "nav-apps",
        title: isEn ? "Running Apps Manager (Quit / Force Quit) →" : "运行中应用管家（按内存排序 / 优雅退出 / 强退）→",
        subtitle: isEn ? "Inspect active GUI apps and reclaim RAM" : "查看前台应用内存占用并快速退出",
        icon: "app.badge.checkmark",
        badge: "APPS",
        commandArgs: ["--apps"]
    )
])

PluginOutput.emit(ViewPayload(
    schemaVersion: 2,
    title: isEn ? "Mac Pilot · Desktop Control Center" : "桌面中控台 · Mac 快捷控制与访达助手",
    subtitle: summary,
    badge: "PILOT",
    metrics: [
        KeyValue(key: isEn ? "Volume" : "当前音量", value: muted ? "Muted" : "\(vol)%"),
        KeyValue(key: isEn ? "Caffeine" : "防休眠", value: caf ? "ON" : "OFF"),
        KeyValue(key: isEn ? "Settings" : "设置直达", value: "16 Panes")
    ],
    items: mainItems,
    effect: PostActionEffect(
        toast: toast,
        reloadSearchIndex: true,
        statusSummary: summary,
        statusBadge: statusBadge
    )
))

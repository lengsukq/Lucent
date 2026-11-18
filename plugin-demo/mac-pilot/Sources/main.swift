import Darwin
import Foundation
import PluginKit

private func emitFinderCard(flag: String, argv: [String], query: String, input: PluginInput, isEn: Bool) -> Never {
    let targetDir: URL = ((flag == "--new-file" || flag == "--open-term") && argv.count >= 2)
        ? URL(fileURLWithPath: argv[1]).standardizedFileURL
        : resolveActiveFinderDir(input: input)
    let defExt = input.cfgString("defaultNewFileExt", default: "md")
    var toast: String? = nil
    if flag == "--new-file" {
        let ext = argv.count >= 3 ? argv[2] : defExt
        let created = createUniqueBlankFile(in: targetDir, requestedName: query, defaultExt: ext)
        toast = isEn ? "Created \(created.lastPathComponent)" : "已新建文件：\(created.lastPathComponent)"
    } else if flag == "--open-term" {
        _ = SubprocessRunner.run(executable: "/usr/bin/open", arguments: ["-a", "Terminal", targetDir.path], timeoutSeconds: 2.0)
        toast = isEn ? "Opened in Terminal" : "已在终端打开该目录"
    }

    var items: [ViewItem] = [
        ViewItem(id: "copy-finder-path", title: isEn ? "Copy Directory Path: \(targetDir.lastPathComponent)" : "复制当前目录路径：\(targetDir.lastPathComponent)", subtitle: targetDir.path, icon: "doc.on.doc.fill", badge: "PATH", copyText: targetDir.path),
        ViewItem(id: "open-in-term", title: isEn ? "Open Directory in Terminal" : "在「终端 (Terminal)」中打开此目录", subtitle: targetDir.path, icon: "terminal.fill", badge: "TERM", commandArgs: ["--open-term", targetDir.path])
    ]
    for (ext, label) in [("md", "Markdown (.md)"), ("txt", "Plain Text (.txt)"), ("json", "JSON (.json)"), ("py", "Python (.py)")] {
        let sub = isEn
            ? (!query.isEmpty ? "File name from search bar: '\(query)'" : "Creates Untitled.\(ext) safely without overwriting")
            : (!query.isEmpty ? "使用搜索框文件名「\(query)」创建" : "防重名安全创建 Untitled.\(ext)")
        items.append(ViewItem(id: "mk-\(ext)", title: isEn ? "New \(label) File Here" : "在此目录新建空白 \(label) 文件", subtitle: sub, icon: "doc.badge.plus", badge: ".\(ext.uppercased())", commandArgs: ["--new-file", targetDir.path, ext]))
    }
    PluginOutput.emit(ViewPayload(schemaVersion: 2, title: isEn ? "Finder Helper · \(targetDir.lastPathComponent)" : "访达目录助手 · \(targetDir.lastPathComponent)", subtitle: targetDir.path, badge: "FINDER", items: items, effect: toast.map { PostActionEffect(toast: $0) }))
    exit(0)
}

private func emitVolumesCard(flag: String, argv: [String], isEn: Bool) -> Never {
    let volumesRoot = ProcessInfo.processInfo.environment["LUCENT_VOLUMES_ROOT"]
        .map { URL(fileURLWithPath: $0, isDirectory: true) } ?? URL(fileURLWithPath: "/Volumes", isDirectory: true)
    var toast: String? = nil
    if flag == "--eject-one", argv.count >= 2 {
        let res = SubprocessRunner.run(executable: "/usr/sbin/diskutil", arguments: ["eject", argv[1]], timeoutSeconds: 6.0)
        let errTrim = res.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        toast = isEn
            ? (res.exitCode == 0 ? "Safely ejected volume" : (errTrim.isEmpty ? "Eject failed" : errTrim))
            : (res.exitCode == 0 ? "已安全推出磁盘" : "推出失败：\(String(errTrim.prefix(48)))")
    } else if flag == "--eject-all" {
        for v in listExternalVolumes(root: volumesRoot) {
            _ = SubprocessRunner.run(executable: "/usr/sbin/diskutil", arguments: ["eject", v.path], timeoutSeconds: 6.0)
        }
        toast = isEn ? "Ejected external volumes" : "已请求安全推出全部外置卷"
    }

    let vols = listExternalVolumes(root: volumesRoot)
    var vItems: [ViewItem] = []
    if vols.count >= 2 {
        vItems.append(ViewItem(id: "eject-all-btn", title: isEn ? "Safely Eject All (\(vols.count) Volumes)" : "一键安全推出全部外置磁盘 (\(vols.count) 个)", subtitle: isEn ? "Unmounts all non-root mounted volumes cleanly" : "依次安全卸载所有外置卷与 DMG 镜像", icon: "eject.circle.fill", badge: "EJECT ALL", commandArgs: ["--eject-all"]))
    }
    for v in vols {
        vItems.append(ViewItem(id: "vol-\(v.name)", title: v.name, subtitle: "\(v.path) · Free \(formatBytes(v.free)) / \(formatBytes(v.total))", icon: "externaldrive.fill", badge: "EJECT", commandArgs: ["--eject-one", v.path]))
    }
    if vItems.isEmpty {
        vItems.append(ViewItem(id: "no-vols", title: isEn ? "No External Volumes Mounted" : "当前未检测到已挂载的外置磁盘或镜像", subtitle: isEn ? "/Volumes contains only system root volume" : "插入 U 盘、移动硬盘或挂载 DMG 后可在此一键安全推出", icon: "checkmark.seal.fill", badge: "CLEAN"))
    }
    PluginOutput.emit(ViewPayload(schemaVersion: 2, title: isEn ? "External Disks & DMG Ejector" : "外置磁盘与镜像安全推出", subtitle: isEn ? "\(vols.count) external volume(s)" : "当前共 \(vols.count) 个外置挂载卷", badge: "\(vols.count) VOL", items: vItems, effect: toast.map { PostActionEffect(toast: $0) }))
    exit(0)
}

private func emitAppsCard(flag: String, argv: [String], query: String, isEn: Bool) -> Never {
    var toast: String? = nil
    if flag == "--quit-app", argv.count >= 2 {
        let escaped = argv[1].replacingOccurrences(of: "\"", with: "\\\"")
        _ = SubprocessRunner.run(executable: "/usr/bin/osascript", arguments: ["-e", "tell application \"\(escaped)\" to quit"], timeoutSeconds: 3.0)
        toast = isEn ? "Sent Quit to \(argv[1])" : "已通知「\(argv[1])」优雅退出"
    } else if flag == "--kill-app", argv.count >= 2, let pid = Int32(argv[1]), pid > 1, Darwin.kill(pid, SIGKILL) == 0 {
        toast = isEn ? "Force terminated process" : "已强制结束该进程"
    }
    let apps = listUserApps(filterQuery: query)
    let aItems: [ViewItem] = apps.map { a in
        let memMB = Int((Double(a.rssKB) / 1024.0).rounded())
        return ViewItem(
            id: "app-\(a.pid)", title: a.name, subtitle: "PID \(a.pid) · RAM \(memMB) MB", icon: "app.fill", badge: "\(memMB) MB",
            actions: [
                ViewAction(id: "q-\(a.pid)", label: isEn ? "Quit" : "退出", commandArgs: ["--quit-app", a.name]),
                ViewAction(id: "k-\(a.pid)", label: isEn ? "Force Quit" : "强制退出", style: "destructive", commandArgs: ["--kill-app", String(a.pid)], confirmMessage: isEn ? "Force quit \(a.name) (PID \(a.pid))?" : "确认强制结束「\(a.name)」(PID \(a.pid))？未保存内容可能丢失。")
            ]
        )
    }
    PluginOutput.emit(ViewPayload(schemaVersion: 2, title: isEn ? "Running Apps Manager" : "运行中应用管家", subtitle: isEn ? "Sorted by memory footprint" : "按实时物理内存占用排序 · 支持优雅退出与强退", badge: "\(apps.count) APPS", items: aItems, effect: toast.map { PostActionEffect(toast: $0) }))
    exit(0)
}

let input = PluginInput.read()
let isEn = input.isEnglish
let query = input.query.trimmingCharacters(in: .whitespacesAndNewlines)
let dataDir = input.dataDir
let bridge = HostBridgeClient(input: input, timeoutSeconds: 4)
syncPanesSearchIndex(dataDir: dataDir, enabled: input.cfgBool("syncSettingsPanesToSearch", default: true), isEn: isEn)

let argv = input.arguments
var flag = argv.first ?? ""
var toast: String? = nil

if flag == "--sleep" {
    _ = SubprocessRunner.run(executable: "/usr/bin/pmset", arguments: ["sleepnow"], timeoutSeconds: 2.0)
    PluginOutput.emit(ViewPayload(schemaVersion: 2, title: isEn ? "Putting Mac to Sleep…" : "正在让 Mac 进入睡眠…", badge: "SLEEP", effect: PostActionEffect(toast: isEn ? "Mac going to sleep" : "已发送睡眠指令", closeOverlay: true)))
    exit(0)
}
if flag == "--mute-toggle" {
    _ = bridge.call(capability: "systemControl", action: "setMute", params: ["muted": "toggle"])
    toast = isEn ? "Toggled system mute" : "已切换系统静音状态"; flag = "--audio"
}
if flag == "--caffeine-toggle" {
    _ = bridge.call(capability: "systemControl", action: "setCaffeine")
    toast = isEn ? "Toggled Keep-Awake (Caffeine)" : "已切换防休眠常亮保护"; flag = "--audio"
}
if flag == "--set-vol", argv.count >= 2, let rawPct = Int(argv[1]) {
    let pct = min(max(rawPct, 0), 100)
    _ = bridge.call(capability: "systemControl", action: "setVolume", params: ["percent": pct])
    toast = isEn ? "Volume set to \(pct)%" : "系统音量已设为 \(pct)%"; flag = "--audio"
}
if flag == "--panes" {
    let q = query.lowercased()
    let rows: [ViewItem] = systemPanes.compactMap { p in
        if !q.isEmpty, !p.zhTitle.lowercased().contains(q) && !p.enTitle.lowercased().contains(q) && !p.keywords.contains(where: { $0.lowercased().contains(q) }) { return nil }
        return ViewItem(id: "pane-\(p.id)", title: isEn ? p.enTitle : p.zhTitle, subtitle: p.uri, icon: p.icon, badge: "SETTINGS", openURL: p.uri)
    }
    PluginOutput.emit(ViewPayload(schemaVersion: 2, title: isEn ? "macOS System Settings Panes" : "macOS 系统设置分栏直达", subtitle: isEn ? "\(rows.count) pane(s) synced to 0ms launcher search" : "共 \(rows.count) 项高频分栏（已同步 ⌥Space 免前缀搜索）", badge: "SETTINGS", items: rows, effect: PostActionEffect(reloadSearchIndex: true)))
    exit(0)
}
if ["--finder", "--new-file", "--open-term"].contains(flag) { emitFinderCard(flag: flag, argv: argv, query: query, input: input, isEn: isEn) }
if ["--volumes", "--eject-one", "--eject-all"].contains(flag) { emitVolumesCard(flag: flag, argv: argv, isEn: isEn) }
if ["--apps", "--quit-app", "--kill-app"].contains(flag) { emitAppsCard(flag: flag, argv: argv, query: query, isEn: isEn) }

if !query.isEmpty, query.allSatisfy(\.isNumber), let qPct = Int(query), (0...100).contains(qPct) {
    _ = bridge.call(capability: "systemControl", action: "setVolume", params: ["percent": qPct])
    toast = isEn ? "Volume set to \(qPct)%" : "已将系统音量调节为 \(qPct)%"
}

let st = bridge.call(capability: "systemControl", action: "status")
let vol = st.ok ? st.int("volumePercent", default: 50) : 50
let muted = st.ok ? st.bool("isMuted", default: false) : false
let caf = st.ok ? st.bool("caffeineActive", default: false) : false
let summary = isEn ? "Vol \(vol)% \(muted ? "(Muted)" : "") · Caffeine \(caf ? "ON" : "OFF")" : "音量 \(vol)%\(muted ? "（已静音）" : "") · 防休眠\(caf ? "开启" : "关闭")"
let statusBadge = caf ? "CAFFEINE" : "\(vol)%"
PluginOutput.writeRuntimeStatus(summary: summary, badge: statusBadge, to: dataDir)

var mainItems: [ViewItem] = []
if !st.ok {
    mainItems.append(ViewItem(id: "grant-sys-bridge", title: isEn ? "Grant 'systemControl' Permission in Plugin Settings →" : "首次使用请点此开启「系统控制 (systemControl)」桥接权限 →", subtitle: isEn ? "Required to adjust macOS volume, mute & sleep prevention" : "授权后即可一键调节音量档位、静音与防休眠常亮", icon: "lock.open.display", badge: "GRANT", openURL: "lucent://settings/plugin/mac-pilot"))
}
mainItems.append(contentsOf: [
    ViewItem(id: "audio-row", title: isEn ? "System Audio: \(muted ? "Muted" : "\(vol)%") (Type 0–100 to set)" : "系统音量：\(muted ? "已静音" : "\(vol)%")（搜索框直接输 0–100 可精准设音量）", subtitle: isEn ? "Quick presets & mute toggle" : "一键切换静音或常用音量档位", icon: muted ? "speaker.slash.fill" : "speaker.wave.3.fill", badge: muted ? "MUTED" : "\(vol)%", actions: [
        ViewAction(id: "m-tog", label: isEn ? (muted ? "Unmute" : "Mute") : (muted ? "取消静音" : "静音"), commandArgs: ["--mute-toggle"]),
        ViewAction(id: "v-25", label: "25%", commandArgs: ["--set-vol", "25"]),
        ViewAction(id: "v-50", label: "50%", commandArgs: ["--set-vol", "50"]),
        ViewAction(id: "v-80", label: "80%", commandArgs: ["--set-vol", "80"])
    ]),
    ViewItem(id: "caf-row", title: isEn ? "Keep Mac Awake (Caffeine): \(caf ? "ACTIVE" : "OFF")" : "防休眠常亮保护 (Caffeine)：\(caf ? "已开启" : "未开启")", subtitle: isEn ? "Prevents idle display dimming & sleep during downloads or builds" : "跑编译、传大文件或阅读长文时阻止自动息屏睡眠", icon: caf ? "cup.and.saucer.fill" : "cup.and.saucer", badge: caf ? "ON" : "OFF", commandArgs: ["--caffeine-toggle"]),
    ViewItem(id: "nav-finder", title: isEn ? "Finder Helper: New Blank File / Copy Path / Terminal →" : "访达助手：在当前窗口新建空白文件 / 复制路径 / 终端打开 →", subtitle: isEn ? "Supports .md, .txt, .json, .py with collision-safe naming" : "支持新建 .md / .txt / .json / .py，自动防重名", icon: "doc.badge.plus", badge: "FINDER", commandArgs: ["--finder"]),
    ViewItem(id: "nav-panes", title: isEn ? "macOS System Settings Deep Links (16 Panes) →" : "直达 macOS 系统设置分栏（蓝牙 / 显示器 / 权限等 16 项）→", subtitle: isEn ? "Also searchable directly from ⌥Space without prefix" : "已同步 ⌥Space 免前缀索引，搜「蓝牙」「显示器」秒达", icon: "gear.badge.checkmark", badge: "16 PANES", commandArgs: ["--panes"]),
    ViewItem(id: "nav-vols", title: isEn ? "Safely Eject External Disks & DMGs →" : "安全推出外置磁盘与 DMG 镜像 →", subtitle: isEn ? "Inspect free space and unmount cleanly" : "查看挂载卷剩余容量并一键安全推出", icon: "eject.circle.fill", badge: "VOLUMES", commandArgs: ["--volumes"]),
    ViewItem(id: "nav-apps", title: isEn ? "Running Apps Manager (Quit / Force Quit) →" : "运行中应用管家（按内存排序 / 优雅退出 / 强退）→", subtitle: isEn ? "Inspect active GUI apps and reclaim RAM" : "查看前台应用内存占用并快速退出", icon: "app.badge.checkmark", badge: "APPS", commandArgs: ["--apps"])
])

PluginOutput.emit(ViewPayload(
    schemaVersion: 2, title: isEn ? "Mac Pilot · Desktop Control Center" : "桌面中控台 · Mac 快捷控制与访达助手",
    subtitle: summary, badge: "PILOT",
    metrics: [KeyValue(key: isEn ? "Volume" : "当前音量", value: muted ? "Muted" : "\(vol)%"), KeyValue(key: isEn ? "Caffeine" : "防休眠", value: caf ? "ON" : "OFF"), KeyValue(key: isEn ? "Settings" : "设置直达", value: "16 Panes")],
    items: mainItems, effect: PostActionEffect(toast: toast, reloadSearchIndex: true, statusSummary: summary, statusBadge: statusBadge)
))

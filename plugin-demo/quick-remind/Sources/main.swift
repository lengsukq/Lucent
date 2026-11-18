import Foundation
import PluginKit

let input = PluginInput.read()
let now = ProcessInfo.processInfo.environment["LUCENT_NOW_ISO"].flatMap(parseISODate) ?? Date()
let isEn = input.isEnglish
let dataDir = input.dataDir
let bridge = HostBridgeClient(input: input, timeoutSeconds: 3)

var query = input.query.trimmingCharacters(in: .whitespacesAndNewlines)
let argv = input.arguments
if query.isEmpty, argv.isEmpty, let ctxText = input.context?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !ctxText.isEmpty {
    query = ctxText
}

let syncApple = input.cfgBool("syncAppleReminders", default: true)
let appleList = input.cfgString("appleListName", default: "")
let snoozeMins = input.cfgInt("snoozeMinutes", default: 10, min: 1, max: 180)
let isoFmt = makeISOFormatter()

var itemsDB = loadReminders(dataDir: dataDir)
var flag = argv.first ?? ""
var toast: String? = nil
var appleSyncFailed = false

if flag == "--pomo" {
    query = isEn ? "25m Pomodoro Focus Break" : "25m 番茄钟休息一下"
    flag = "--add"
}

if flag == "--sync" {
    let activeCnt = itemsDB.filter { !$0.done }.count
    toast = isEn ? "Synced \(activeCnt) active reminder(s)" : "已同步提醒索引（当前 \(activeCnt) 条待办）"
} else if flag == "--speak", argv.count >= 2 {
    _ = bridge.call(capability: "audio", action: "speak", params: ["text": argv[1], "language": isEn ? "en-US" : "zh-CN"])
    toast = isEn ? "Reading reminder aloud…" : "正在语音播报提醒…"
} else if flag == "--done", argv.count >= 2 {
    let rid = argv[1]
    if let i = itemsDB.firstIndex(where: { $0.id == rid }) {
        let rep = itemsDB[i].repeat
        if rep != "once" && !itemsDB[i].done {
            let nxt = advanceNextOccurrence(dueISO: itemsDB[i].dueISO, repeatRule: rep, now: now)
            itemsDB[i].dueISO = isoFmt.string(from: nxt)
            itemsDB[i].dueDisplay = formatDueDisplay(nxt)
            toast = isEn
                ? "Scheduled next (\(rep)): \(itemsDB[i].dueDisplay)"
                : "已推进至下一周期 (\(rep))：\(itemsDB[i].dueDisplay)"
        } else {
            itemsDB[i].done.toggle()
            toast = isEn ? "Completed reminder" : (itemsDB[i].done ? "已标记完成" : "已恢复为待办")
        }
    }
} else if flag == "--snooze", argv.count >= 2 {
    let rid = argv[1]
    if let i = itemsDB.firstIndex(where: { $0.id == rid }) {
        let nxt = now.addingTimeInterval(Double(snoozeMins * 60))
        itemsDB[i].dueISO = isoFmt.string(from: nxt)
        itemsDB[i].dueDisplay = formatDueDisplay(nxt)
        itemsDB[i].done = false
        if syncApple && !syncToAppleReminders(title: itemsDB[i].title, due: nxt, listName: appleList) {
            appleSyncFailed = true
        }
        let suffix = appleSyncFailed ? (isEn ? " (Apple unauthorized)" : "（Apple 提醒未授权，仅本地延后）") : ""
        toast = (isEn ? "Snoozed +\(snoozeMins)m" : "已推迟 \(snoozeMins) 分钟（\(formatTimeHM(nxt))）") + suffix
    }
} else if flag == "--delete", argv.count >= 2 {
    itemsDB.removeAll { $0.id == argv[1] }
    toast = isEn ? "Deleted reminder" : "已删除该条提醒"
} else if flag == "--clear-done" {
    itemsDB.removeAll(where: \.done)
    toast = isEn ? "Cleared completed reminders" : "已清理全部已完成提醒"
} else if (flag.isEmpty || flag == "--add") && !query.isEmpty {
    if let parsed = parseNaturalReminder(query, now: now) {
        let dueISO = isoFmt.string(from: parsed.due)
        let rid = String(DigestUtils.sha1Hex("\(dueISO):\(parsed.body):\(itemsDB.count)").prefix(8))
        let syncedOK = syncApple ? syncToAppleReminders(title: parsed.body, due: parsed.due, listName: appleList) : false
        if syncApple && !syncedOK {
            appleSyncFailed = true
        }
        itemsDB.insert(ReminderRecord(
            id: rid,
            title: parsed.body,
            dueISO: dueISO,
            dueDisplay: formatDueDisplay(parsed.due),
            repeat: parsed.repeatRule,
            done: false,
            appleSynced: syncedOK
        ), at: 0)
        let syncNote: String
        if isEn {
            syncNote = syncedOK ? " (Synced to Reminders.app)" : (appleSyncFailed ? " (Saved locally; Reminders Automation unauthorized)" : "")
        } else {
            syncNote = syncedOK ? "（已同步系统提醒事项）" : (appleSyncFailed ? "（已本地保存；Apple 提醒事项未授权）" : "")
        }
        toast = isEn
            ? "Reminder set for \(formatTimeHM(parsed.due))\(syncNote)"
            : "已设定 \(formatTimeHM(parsed.due)) 提醒：\(parsed.body)\(syncNote)"
        query = ""
    } else {
        toast = isEn
            ? "Could not parse time in '\(query)'; try '10m \(query)'"
            : "未识别到时间前缀，可尝试「10m \(query)」或「18:30 \(query)」"
    }
} else if flag == "--add" && query.isEmpty {
    toast = isEn
        ? "Type a reminder first, e.g. '10m drink water', or click Pomodoro below"
        : "请先输入提醒内容（如「10m 喝水」），或直接点击下方一键开启番茄钟"
} else if (flag.isEmpty || flag == "--list") && toast == nil {
    let activeCnt = itemsDB.filter { !$0.done }.count
    toast = isEn
        ? "\(activeCnt) active reminder(s)"
        : (activeCnt > 0 ? "当前 \(activeCnt) 条待办提醒" : "暂无待办提醒，可输入「10m 喝水」或开启番茄钟")
}

let (summary, badge) = saveReminders(dataDir: dataDir, items: itemsDB, isEn: isEn, appleDenied: appleSyncFailed)

var ordered = itemsDB.sorted { a, b in
    let da = a.done ? 1 : 0, db = b.done ? 1 : 0
    if da != db { return da < db }
    return a.dueISO < b.dueISO
}
if flag == "--list", !query.isEmpty {
    let qLower = query.lowercased()
    ordered = ordered.filter { $0.title.lowercased().contains(qLower) }
}

var cardItems: [ViewItem] = []
if appleSyncFailed {
    cardItems.append(ViewItem(
        id: "reminders-automation-guide",
        title: isEn
            ? "Authorize 'Automation -> Reminders' to Sync to Apple Reminders"
            : "授予「自动化 -> 提醒事项」权限以同步至系统提醒",
        subtitle: isEn
            ? "Saved locally inside Lucent. Allow Lucent -> Reminders in Privacy & Security, or turn off Apple Sync in plugin settings."
            : "提醒已安全保存在 Lucent 本地；如需写入系统「提醒事项」，请前往系统设置授权或关闭同步开关。",
        icon: "lock.shield.fill",
        badge: "PERMISSION",
        openURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
    ))
}

cardItems.append(ViewItem(
    id: "quick-pomo",
    title: isEn ? "Start 25-Min Pomodoro Focus Timer" : "🍅 一键开启 25 分钟番茄钟专注提醒",
    subtitle: isEn
        ? "Or type '10m drink water', '18:30 package', 'tomorrow 09:00 report' in search bar"
        : "也可直接在上方输入「10m 喝水」「18:30 拿快递」「明天 9:00 周报 每天」回车创建",
    icon: "timer",
    badge: "25 MIN",
    commandArgs: ["--pomo"]
))

var dueCount = 0
for r in ordered.prefix(25) {
    let (relText, isDue) = formatRelative(dueISO: r.dueISO, now: now, isEn: isEn)
    if isDue && !r.done { dueCount += 1 }
    let repTag = r.repeat == "once" ? "" : " · 🔁 \(r.repeat)"
    let syncTag = r.appleSynced ? " ·  Reminders" : ""
    cardItems.append(ViewItem(
        id: "rem-\(r.id)",
        title: (r.done ? "✓ " : (isDue ? "🔔 " : "⏰ ")) + r.title,
        subtitle: r.done ? "Completed · \(r.dueDisplay)" : "\(relText)\(repTag)\(syncTag)",
        icon: r.done ? "checkmark.circle.fill" : (isDue ? "bell.and.waves.left.and.right.fill" : "clock.fill"),
        badge: r.done ? "DONE" : (isDue ? "DUE!" : r.repeat.uppercased()),
        copyText: r.title,
        actions: [
            ViewAction(id: "done-\(r.id)", label: isEn ? (r.done ? "Reopen" : "Done") : (r.done ? "恢复" : "知道了"), style: "primary", commandArgs: ["--done", r.id]),
            ViewAction(id: "snz-\(r.id)", label: isEn ? "+\(snoozeMins)m" : "推迟\(snoozeMins)分", commandArgs: ["--snooze", r.id]),
            ViewAction(id: "spk-\(r.id)", label: isEn ? "Speak" : "朗读", commandArgs: ["--speak", r.title]),
            ViewAction(id: "del-\(r.id)", label: isEn ? "Delete" : "删除", style: "destructive", commandArgs: ["--delete", r.id])
        ]
    ))
}

if itemsDB.contains(where: \.done) {
    cardItems.append(ViewItem(
        id: "clear-done-row",
        title: isEn ? "Clear Completed Reminders" : "清理已完成的提醒记录",
        subtitle: isEn ? "Keep your reminder board tidy" : "一键移除已完成的旧提醒",
        icon: "trash",
        badge: "CLEAN",
        commandArgs: ["--clear-done"]
    ))
}

let openTotal = itemsDB.filter { !$0.done }.count
let notif: NotificationSpec? = (flag == "--add" && toast != nil)
    ? NotificationSpec(title: isEn ? "Quick Remind" : "闪电提醒已设定", body: toast!, sound: true)
    : nil

PluginOutput.emit(ViewPayload(
    schemaVersion: 2,
    title: isEn ? "Quick Remind · Timers & Reminders" : "闪电提醒 · 自然语言倒计时与提醒看板",
    subtitle: summary,
    badge: dueCount > 0 ? "\(dueCount) DUE" : "\(openTotal) ACTIVE",
    metrics: [
        KeyValue(key: isEn ? "Active" : "待触发", value: String(openTotal)),
        KeyValue(key: isEn ? "Due Now" : "已到点", value: String(dueCount)),
        KeyValue(key: isEn ? "Snooze" : "默认推迟", value: "\(snoozeMins) min")
    ],
    items: cardItems,
    effect: PostActionEffect(
        toast: toast,
        reloadSearchIndex: true,
        statusSummary: summary,
        statusBadge: badge,
        notification: notif
    )
))

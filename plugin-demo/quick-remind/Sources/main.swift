import Foundation
import PluginKit

struct ReminderRecord: Codable {
    var id: String
    var title: String
    var dueISO: String
    var dueDisplay: String
    var `repeat`: String
    var done: Bool
    var appleSynced: Bool
}

private func makeISOFormatter() -> ISO8601DateFormatter {
    let f = ISO8601DateFormatter()
    f.timeZone = .current
    f.formatOptions = [.withInternetDateTime]
    return f
}

private func parseISODate(_ raw: String) -> Date? {
    let f1 = makeISOFormatter()
    if let d = f1.date(from: raw) { return d }
    let df = DateFormatter()
    df.locale = Locale(identifier: "en_US_POSIX")
    df.timeZone = .current
    for fmt in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm"] {
        df.dateFormat = fmt
        if let d = df.date(from: raw) { return d }
    }
    return nil
}

private func formatDueDisplay(_ date: Date) -> String {
    let df = DateFormatter()
    df.locale = Locale(identifier: "en_US_POSIX")
    df.timeZone = .current
    df.dateFormat = "yyyy-MM-dd HH:mm"
    return df.string(from: date)
}

private func formatTimeHM(_ date: Date) -> String {
    let df = DateFormatter()
    df.locale = Locale(identifier: "en_US_POSIX")
    df.timeZone = .current
    df.dateFormat = "HH:mm"
    return df.string(from: date)
}

private func formatMonthDayHM(_ date: Date) -> String {
    let df = DateFormatter()
    df.locale = Locale(identifier: "en_US_POSIX")
    df.timeZone = .current
    df.dateFormat = "MM-dd HH:mm"
    return df.string(from: date)
}

private func parseNaturalReminder(_ raw: String, now: Date) -> (due: Date, body: String, repeatRule: String)? {
    var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    for prefix in ["remind ", "timer ", "alarm ", "提醒 ", "提醒我 "] {
        if text.lowercased().hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
    }
    guard !text.isEmpty else { return nil }

    var repeatRule = "once"
    let repPatterns: [(String, String)] = [
        (#"\s*(?:每天|每日|daily|every\s*day)\s*$"#, "daily"),
        (#"\s*(?:工作日|weekdays?)\s*$"#, "weekdays"),
        (#"\s*(?:每周|weekly)\s*$"#, "weekly")
    ]
    for (pat, rule) in repPatterns {
        if let re = try? NSRegularExpression(pattern: pat, options: [.caseInsensitive]) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let m = re.firstMatch(in: text, range: range), let r = Range(m.range(at: 0), in: text) {
                repeatRule = rule
                text = String(text[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
    }

    let relRe = try! NSRegularExpression(
        pattern: #"^(?:in\s+)?(\d+(?:\.\d+)?)\s*(s|sec|secs|秒|m|min|mins|分钟|分|h|hr|hrs|hour|hours|小时)(?:后)?\s*(.*)$"#,
        options: [.caseInsensitive]
    )
    let nsText = NSRange(text.startIndex..<text.endIndex, in: text)
    if let m = relRe.firstMatch(in: text, range: nsText),
       let valR = Range(m.range(at: 1), in: text),
       let unitR = Range(m.range(at: 2), in: text),
       let bodyR = Range(m.range(at: 3), in: text),
       let val = Double(text[valR]) {
        let unit = text[unitR].lowercased()
        let rawBody = text[bodyR].trimmingCharacters(in: .whitespacesAndNewlines)
        let isAsciiUnit = unit.unicodeScalars.allSatisfy(\.isASCII)
        let body = rawBody.isEmpty ? (isAsciiUnit ? "Time is up!" : "时间到啦") : rawBody
        let secs: Double
        if ["s", "sec", "secs", "秒"].contains(unit) {
            secs = max(5.0, Double(Int(val)))
        } else if ["h", "hr", "hrs", "hour", "hours", "小时"].contains(unit) {
            secs = Double(Int(val * 3600.0))
        } else {
            secs = Double(Int(val * 60.0))
        }
        return (now.addingTimeInterval(secs), body, repeatRule)
    }

    let clkRe = try! NSRegularExpression(
        pattern: #"^(?:(今天|今晚|明天|后天|today|tonight|tomorrow)\s*)?(\d{1,2})[:：点时](\d{0,2})(?:分)?\s*(.*)$"#,
        options: [.caseInsensitive]
    )
    if let m = clkRe.firstMatch(in: text, range: nsText),
       let hrR = Range(m.range(at: 2), in: text),
       let mnR = Range(m.range(at: 3), in: text),
       let bodyR = Range(m.range(at: 4), in: text),
       var hour = Int(text[hrR]) {
        let dayWord = m.range(at: 1).location != NSNotFound
            ? (Range(m.range(at: 1), in: text).map { text[$0].lowercased() } ?? "")
            : ""
        let mnStr = String(text[mnR])
        let minute = mnStr.isEmpty ? 0 : (Int(mnStr) ?? -1)
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        if ["今晚", "tonight"].contains(dayWord) && hour < 12 {
            hour += 12
        }
        let rawBody = text[bodyR].trimmingCharacters(in: .whitespacesAndNewlines)
        let body = rawBody.isEmpty ? "Scheduled Reminder" : rawBody

        var dayOffset = 0
        if ["明天", "tomorrow"].contains(dayWord) {
            dayOffset = 1
        } else if dayWord == "后天" {
            dayOffset = 2
        }

        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        guard var target = cal.date(from: comps) else { return nil }
        if dayOffset > 0, let shifted = cal.date(byAdding: .day, value: dayOffset, to: target) {
            target = shifted
        } else if dayOffset == 0 && target <= now, let nextDay = cal.date(byAdding: .day, value: 1, to: target) {
            target = nextDay
        }
        return (target, body, repeatRule)
    }
    return nil
}

private func syncToAppleReminders(title: String, due: Date, listName: String) -> Bool {
    if ProcessInfo.processInfo.environment["LUMAKEY_MOCK_APPLE_REMINDERS"] == "ok" {
        return true
    }
    if ProcessInfo.processInfo.environment["LUMAKEY_MOCK_APPLE_REMINDERS"] == "deny" {
        return false
    }
    let script = """
    on run argv
        set remTitle to item 1 of argv
        set yr to (item 2 of argv) as integer
        set mo to (item 3 of argv) as integer
        set dy to (item 4 of argv) as integer
        set hr to (item 5 of argv) as integer
        set mn to (item 6 of argv) as integer
        set sc to (item 7 of argv) as integer
        set targetList to item 8 of argv

        set dueDate to current date
        set year of dueDate to yr
        set month of dueDate to mo
        set day of dueDate to dy
        set hours of dueDate to hr
        set minutes of dueDate to mn
        set seconds of dueDate to sc

        tell application "Reminders"
            if targetList is not "" and (exists list targetList) then
                tell list targetList to make new reminder with properties {name:remTitle, remind me date:dueDate}
            else
                tell default list to make new reminder with properties {name:remTitle, remind me date:dueDate}
            end if
        end tell
    end run
    """
    let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: due)
    let args = [
        "-e", script,
        title,
        String(c.year ?? 2026), String(c.month ?? 1), String(c.day ?? 1),
        String(c.hour ?? 9), String(c.minute ?? 0), String(c.second ?? 0),
        listName.trimmingCharacters(in: .whitespacesAndNewlines)
    ]
    let res = SubprocessRunner.run(executable: "/usr/bin/osascript", arguments: args, timeoutSeconds: 1.5)
    return res.exitCode == 0 && !res.timedOut
}

private func loadReminders(dataDir: String) -> [ReminderRecord] {
    guard !dataDir.isEmpty else { return [] }
    let fileURL = URL(fileURLWithPath: dataDir, isDirectory: true).appendingPathComponent("reminders.json")
    guard let data = try? Data(contentsOf: fileURL),
          let decoded = try? JSONDecoder().decode([ReminderRecord].self, from: data) else {
        return []
    }
    return decoded
}

private func saveReminders(dataDir: String, items: [ReminderRecord], isEn: Bool, appleDenied: Bool) -> (summary: String, badge: String) {
    let openItems = items.filter { !$0.done }
    let suffix = appleDenied
        ? (isEn ? " (Reminders Automation unauthorized)" : "（Apple 提醒事项未授权）")
        : ""
    let summary = (isEn ? "\(openItems.count) active reminder(s)" : "\(openItems.count) 条待办提醒") + suffix
    let badge = String(openItems.count)
    guard !dataDir.isEmpty else { return (summary, badge) }

    let dirURL = URL(fileURLWithPath: dataDir, isDirectory: true)
    try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
    let trimmed = Array(items.prefix(150))
    if let jsonData = try? PluginOutput.encodeJSON(trimmed, pretty: true) {
        try? jsonData.write(to: dirURL.appendingPathComponent("reminders.json"), options: .atomic)
    }

    let idx: [SearchIndexItem] = openItems.prefix(60).map { r in
        SearchIndexItem(
            id: "rem-\(r.id)",
            title: "⏰ \(r.title)",
            subtitle: "Due \(r.dueDisplay) · \(r.repeat)",
            icon: "bell.badge.fill",
            tags: ["remind", "提醒", r.title.lowercased()],
            priority: 48,
            commandArgs: ["--list"]
        )
    }
    PluginOutput.writeSearchIndex(idx, to: dataDir)
    PluginOutput.writeRuntimeStatus(summary: summary, badge: badge, to: dataDir)
    return (summary, badge)
}

private func advanceNextOccurrence(dueISO: String, repeatRule: String, now: Date) -> Date {
    let cal = Calendar.current
    var cur = parseISODate(dueISO) ?? now
    if repeatRule == "daily" {
        repeat {
            cur = cal.date(byAdding: .day, value: 1, to: cur) ?? cur.addingTimeInterval(86_400)
        } while cur <= now
        return cur
    }
    if repeatRule == "weekly" {
        repeat {
            cur = cal.date(byAdding: .day, value: 7, to: cur) ?? cur.addingTimeInterval(604_800)
        } while cur <= now
        return cur
    }
    if repeatRule == "weekdays" {
        repeat {
            cur = cal.date(byAdding: .day, value: 1, to: cur) ?? cur.addingTimeInterval(86_400)
            let wd = cal.component(.weekday, from: cur) // 1=Sun, 7=Sat
            if cur > now && wd != 1 && wd != 7 { break }
        } while true
        return cur
    }
    return cur
}

private func formatRelative(dueISO: String, now: Date, isEn: Bool) -> (label: String, isDue: Bool) {
    guard let due = parseISODate(dueISO) else { return ("Unknown", false) }
    let diff = Int(due.timeIntervalSince(now))
    let stamp = formatMonthDayHM(due)
    if diff <= 0 {
        let minsAgo = abs(diff) / 60
        let label = isEn
            ? "DUE (\(minsAgo)m ago · \(stamp))"
            : "已到点（\(minsAgo) 分钟前 · \(stamp)）"
        return (label, true)
    }
    if diff < 3600 {
        let mins = max(1, (diff + 59) / 60)
        return (isEn ? "in \(mins) min (\(stamp))" : "\(mins) 分钟后（\(stamp)）", false)
    }
    let hours = diff / 3600
    let remM = (diff % 3600) / 60
    return (isEn ? "in \(hours)h \(remM)m (\(stamp))" : "\(hours) 小时 \(remM) 分后（\(stamp)）", false)
}

let input = PluginInput.read()
let now = ProcessInfo.processInfo.environment["LUMAKEY_NOW_ISO"].flatMap(parseISODate) ?? Date()
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
            ? "Saved locally inside Lumakey. Allow Lumakey -> Reminders in Privacy & Security, or turn off Apple Sync in plugin settings."
            : "提醒已安全保存在 Lumakey 本地；如需写入系统「提醒事项」，请前往系统设置授权或关闭同步开关。",
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
            ViewAction(
                id: "done-\(r.id)",
                label: isEn ? (r.done ? "Reopen" : "Done") : (r.done ? "恢复" : "知道了"),
                style: "primary",
                commandArgs: ["--done", r.id]
            ),
            ViewAction(
                id: "snz-\(r.id)",
                label: isEn ? "+\(snoozeMins)m" : "推迟\(snoozeMins)分",
                commandArgs: ["--snooze", r.id]
            ),
            ViewAction(
                id: "spk-\(r.id)",
                label: isEn ? "Speak" : "朗读",
                commandArgs: ["--speak", r.title]
            ),
            ViewAction(
                id: "del-\(r.id)",
                label: isEn ? "Delete" : "删除",
                style: "destructive",
                commandArgs: ["--delete", r.id]
            )
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

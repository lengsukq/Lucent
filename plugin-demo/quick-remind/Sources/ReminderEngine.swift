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

func makeISOFormatter() -> ISO8601DateFormatter {
    let f = ISO8601DateFormatter()
    f.timeZone = .current
    f.formatOptions = [.withInternetDateTime]
    return f
}

func parseISODate(_ raw: String) -> Date? {
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

func formatDueDisplay(_ date: Date) -> String {
    let df = DateFormatter()
    df.locale = Locale(identifier: "en_US_POSIX")
    df.timeZone = .current
    df.dateFormat = "yyyy-MM-dd HH:mm"
    return df.string(from: date)
}

func formatTimeHM(_ date: Date) -> String {
    let df = DateFormatter()
    df.locale = Locale(identifier: "en_US_POSIX")
    df.timeZone = .current
    df.dateFormat = "HH:mm"
    return df.string(from: date)
}

func formatMonthDayHM(_ date: Date) -> String {
    let df = DateFormatter()
    df.locale = Locale(identifier: "en_US_POSIX")
    df.timeZone = .current
    df.dateFormat = "MM-dd HH:mm"
    return df.string(from: date)
}

func parseNaturalReminder(_ raw: String, now: Date) -> (due: Date, body: String, repeatRule: String)? {
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
        if ["今晚", "tonight"].contains(dayWord) && hour < 12 { hour += 12 }
        let rawBody = text[bodyR].trimmingCharacters(in: .whitespacesAndNewlines)
        let body = rawBody.isEmpty ? "Scheduled Reminder" : rawBody
        let dayOffset = ["明天", "tomorrow"].contains(dayWord) ? 1 : (dayWord == "后天" ? 2 : 0)

        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = hour; comps.minute = minute; comps.second = 0
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

func syncToAppleReminders(title: String, due: Date, listName: String) -> Bool {
    if ProcessInfo.processInfo.environment["LUCENT_MOCK_APPLE_REMINDERS"] == "ok" { return true }
    if ProcessInfo.processInfo.environment["LUCENT_MOCK_APPLE_REMINDERS"] == "deny" { return false }
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
        "-e", script, title,
        String(c.year ?? 2026), String(c.month ?? 1), String(c.day ?? 1),
        String(c.hour ?? 9), String(c.minute ?? 0), String(c.second ?? 0),
        listName.trimmingCharacters(in: .whitespacesAndNewlines)
    ]
    let res = SubprocessRunner.run(executable: "/usr/bin/osascript", arguments: args, timeoutSeconds: 1.5)
    return res.exitCode == 0 && !res.timedOut
}

func loadReminders(dataDir: String) -> [ReminderRecord] {
    guard !dataDir.isEmpty else { return [] }
    let fileURL = URL(fileURLWithPath: dataDir, isDirectory: true).appendingPathComponent("reminders.json")
    guard let data = try? Data(contentsOf: fileURL),
          let decoded = try? JSONDecoder().decode([ReminderRecord].self, from: data) else { return [] }
    return decoded
}

func saveReminders(dataDir: String, items: [ReminderRecord], isEn: Bool, appleDenied: Bool) -> (summary: String, badge: String) {
    let openItems = items.filter { !$0.done }
    let suffix = appleDenied ? (isEn ? " (Reminders Automation unauthorized)" : "（Apple 提醒事项未授权）") : ""
    let summary = (isEn ? "\(openItems.count) active reminder(s)" : "\(openItems.count) 条待办提醒") + suffix
    let badge = String(openItems.count)
    guard !dataDir.isEmpty else { return (summary, badge) }

    let dirURL = URL(fileURLWithPath: dataDir, isDirectory: true)
    try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
    if let jsonData = try? PluginOutput.encodeJSON(Array(items.prefix(150)), pretty: true) {
        try? jsonData.write(to: dirURL.appendingPathComponent("reminders.json"), options: .atomic)
    }

    let idx: [SearchIndexItem] = openItems.prefix(60).map { r in
        SearchIndexItem(
            id: "rem-\(r.id)", title: "⏰ \(r.title)", subtitle: "Due \(r.dueDisplay) · \(r.repeat)",
            icon: "bell.badge.fill", tags: ["remind", "提醒", r.title.lowercased()],
            priority: 48, commandArgs: ["--list"]
        )
    }
    PluginOutput.writeSearchIndex(idx, to: dataDir)
    PluginOutput.writeRuntimeStatus(summary: summary, badge: badge, to: dataDir)
    return (summary, badge)
}

func advanceNextOccurrence(dueISO: String, repeatRule: String, now: Date) -> Date {
    let cal = Calendar.current
    var cur = parseISODate(dueISO) ?? now
    if repeatRule == "daily" {
        repeat { cur = cal.date(byAdding: .day, value: 1, to: cur) ?? cur.addingTimeInterval(86_400) } while cur <= now
        return cur
    }
    if repeatRule == "weekly" {
        repeat { cur = cal.date(byAdding: .day, value: 7, to: cur) ?? cur.addingTimeInterval(604_800) } while cur <= now
        return cur
    }
    if repeatRule == "weekdays" {
        repeat {
            cur = cal.date(byAdding: .day, value: 1, to: cur) ?? cur.addingTimeInterval(86_400)
            let wd = cal.component(.weekday, from: cur)
            if cur > now && wd != 1 && wd != 7 { break }
        } while true
        return cur
    }
    return cur
}

func formatRelative(dueISO: String, now: Date, isEn: Bool) -> (label: String, isDue: Bool) {
    guard let due = parseISODate(dueISO) else { return ("Unknown", false) }
    let diff = Int(due.timeIntervalSince(now))
    let stamp = formatMonthDayHM(due)
    if diff <= 0 {
        let minsAgo = abs(diff) / 60
        return (isEn ? "DUE (\(minsAgo)m ago · \(stamp))" : "已到点（\(minsAgo) 分钟前 · \(stamp)）", true)
    }
    if diff < 3600 {
        let mins = max(1, (diff + 59) / 60)
        return (isEn ? "in \(mins) min (\(stamp))" : "\(mins) 分钟后（\(stamp)）", false)
    }
    return (isEn ? "in \(diff / 3600)h \((diff % 3600) / 60)m (\(stamp))" : "\(diff / 3600) 小时 \((diff % 3600) / 60) 分后（\(stamp)）", false)
}

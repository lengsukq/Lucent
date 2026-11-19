import Foundation
import PluginKit

struct SymbolAlertRule: Codable {
    var enabled: Bool
    var highPrice: Double?
    var lowPrice: Double?
}

struct AlertsStore: Codable {
    var cooldownMinutes: Int
    var rules: [String: SymbolAlertRule]
}

struct AlertTriggerRecord: Codable {
    var lastTriggeredAt: TimeInterval
    var lastTriggeredPrice: Double
    var isBreached: Bool
}

struct AlertTriggeredInfo: Codable {
    let symbol: String
    let direction: String
    let targetPrice: Double
    let currentPrice: Double
    let message: String
    let notificationSent: Bool
}

struct SymbolAlertSummary: Codable {
    let enabled: Bool
    let highPrice: Double?
    let lowPrice: Double?
    let cooldownMinutes: Int
}

private func alertsFileURL(dataDir: String) -> URL? {
    guard !dataDir.isEmpty else { return nil }
    return URL(fileURLWithPath: dataDir, isDirectory: true).appendingPathComponent("alerts.json")
}

private func alertStateFileURL(dataDir: String) -> URL? {
    guard !dataDir.isEmpty else { return nil }
    return URL(fileURLWithPath: dataDir, isDirectory: true).appendingPathComponent("alert_state.json")
}

func loadAlertsStore(dataDir: String, input: PluginInput) -> AlertsStore {
    let cfgCooldown = input.cfgInt("alertCooldownMin", default: 15, min: 1, max: 240)
    if let url = alertsFileURL(dataDir: dataDir),
       let data = try? Data(contentsOf: url),
       var decoded = try? JSONDecoder().decode(AlertsStore.self, from: data) {
        if decoded.cooldownMinutes < 1 { decoded.cooldownMinutes = cfgCooldown }
        return decoded
    }

    let cfgHigh = Double(input.cfgString("alertHighAu9999"))
    let cfgLow = Double(input.cfgString("alertLowAu9999"))
    let validHigh = (cfgHigh ?? 0) > 0 ? cfgHigh : nil
    let validLow = (cfgLow ?? 0) > 0 ? cfgLow : nil
    var rules: [String: SymbolAlertRule] = [:]
    if validHigh != nil || validLow != nil {
        rules["AU9999"] = SymbolAlertRule(enabled: true, highPrice: validHigh, lowPrice: validLow)
    }
    return AlertsStore(cooldownMinutes: cfgCooldown, rules: rules)
}

func saveAlertsStore(dataDir: String, store: AlertsStore) -> Bool {
    guard let url = alertsFileURL(dataDir: dataDir),
          let data = try? JSONEncoder().encode(store) else { return false }
    do {
        try data.write(to: url, options: .atomic)
        return true
    } catch {
        return false
    }
}

private func loadAlertStates(dataDir: String) -> [String: AlertTriggerRecord] {
    guard let url = alertStateFileURL(dataDir: dataDir),
          let data = try? Data(contentsOf: url),
          let decoded = try? JSONDecoder().decode([String: AlertTriggerRecord].self, from: data) else {
        return [:]
    }
    return decoded
}

private func saveAlertStates(dataDir: String, states: [String: AlertTriggerRecord]) {
    guard let url = alertStateFileURL(dataDir: dataDir),
          let data = try? JSONEncoder().encode(states) else { return }
    try? data.write(to: url, options: .atomic)
}

func resetAlertStateForSymbol(dataDir: String, symbol: String) {
    var states = loadAlertStates(dataDir: dataDir)
    states.removeValue(forKey: "\(symbol):high")
    states.removeValue(forKey: "\(symbol):low")
    saveAlertStates(dataDir: dataDir, states: states)
}

func summarizeAlert(store: AlertsStore, symbol: GoldSymbol) -> SymbolAlertSummary {
    let rule = store.rules[symbol.rawValue]
    let high = (rule?.highPrice ?? 0) > 0 ? rule?.highPrice : nil
    let low = (rule?.lowPrice ?? 0) > 0 ? rule?.lowPrice : nil
    let active = (rule?.enabled ?? false) && (high != nil || low != nil)
    return SymbolAlertSummary(enabled: active, highPrice: high, lowPrice: low, cooldownMinutes: store.cooldownMinutes)
}

func evaluateAndNotifyAlerts(
    dataDir: String, quote: GoldQuote, symbol: GoldSymbol, input: PluginInput, isEn: Bool
) -> AlertTriggeredInfo? {
    let store = loadAlertsStore(dataDir: dataDir, input: input)
    guard let rule = store.rules[quote.symbol], rule.enabled else { return nil }

    let now = Date().timeIntervalSince1970
    let cooldownSec = TimeInterval(max(1, store.cooldownMinutes) * 60)
    let bridge = HostBridgeClient(input: input)
    var states = loadAlertStates(dataDir: dataDir)
    var statesChanged = false
    var triggered: AlertTriggeredInfo? = nil

    func checkRule(direction: String, targetOpt: Double?) {
        guard let target = targetOpt, target > 0 else { return }
        let key = "\(quote.symbol):\(direction)"
        var rec = states[key] ?? AlertTriggerRecord(lastTriggeredAt: 0, lastTriggeredPrice: 0, isBreached: false)

        let hysteresis = max(0.15, target * 0.0003)
        let isHigh = (direction == "high")
        let breachedNow = isHigh ? (quote.price >= target) : (quote.price <= target)
        let resetNow = isHigh ? (quote.price < target - hysteresis) : (quote.price > target + hysteresis)

        if breachedNow {
            if !rec.isBreached && (now - rec.lastTriggeredAt) >= cooldownSec {
                let symName = isEn ? symbol.englishName : symbol.displayName
                let title = isEn
                    ? "Gold Alert · \(quote.symbol) \(isHigh ? "Above" : "Below") \(String(format: "%.2f", target))"
                    : "金价预警 · \(symName) \(isHigh ? "突破" : "跌破") ¥\(String(format: "%.2f", target))"
                let body = isEn
                    ? "Current: ¥\(String(format: "%.2f", quote.price))/g (\(String(format: "%+.2f", quote.changePct))%) @ \(quote.time)"
                    : "当前报价：¥\(String(format: "%.2f", quote.price))/克（\(String(format: "%+.2f", quote.changePct))%）· \(quote.time)"

                let resp = bridge.call(capability: "notifications", action: "send", params: [
                    "title": title,
                    "subtitle": isEn ? "Shanghai Gold Exchange" : "上海黄金交易所实时监控",
                    "body": body,
                    "sound": true
                ])
                rec.lastTriggeredAt = now
                rec.lastTriggeredPrice = quote.price
                rec.isBreached = true
                states[key] = rec
                statesChanged = true

                if triggered == nil {
                    triggered = AlertTriggeredInfo(
                        symbol: quote.symbol, direction: direction, targetPrice: target,
                        currentPrice: quote.price, message: title, notificationSent: resp.ok
                    )
                }
            } else if !rec.isBreached {
                rec.isBreached = true
                states[key] = rec
                statesChanged = true
            }
        } else if resetNow && rec.isBreached {
            rec.isBreached = false
            states[key] = rec
            statesChanged = true
        }
    }

    checkRule(direction: "high", targetOpt: rule.highPrice)
    checkRule(direction: "low", targetOpt: rule.lowPrice)
    if statesChanged { saveAlertStates(dataDir: dataDir, states: states) }
    return triggered
}

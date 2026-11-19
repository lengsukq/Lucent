import Foundation
import PluginKit

private struct SwitchResultPayload: Codable {
    let ok: Bool
    let error: String?
    let message: String?
}

private struct SaveAlertInput: Codable {
    let symbol: String
    let enabled: Bool
    let highPrice: Double?
    let lowPrice: Double?
    let cooldownMinutes: Int?
}

private struct SaveAlertResult: Codable {
    let ok: Bool
    let alerts: SymbolAlertSummary?
    let error: String?
}

private struct SnapDockResult: Codable {
    let ok: Bool
    let edge: String
    let x: Double
    let y: Double
}

private func activeSymbolFile(dataDir: String) -> URL? {
    guard !dataDir.isEmpty else { return nil }
    return URL(fileURLWithPath: dataDir, isDirectory: true).appendingPathComponent("active_symbol.txt")
}

private func saveActiveSymbol(dataDir: String, symbol: GoldSymbol) {
    guard let url = activeSymbolFile(dataDir: dataDir) else { return }
    try? symbol.rawValue.write(to: url, atomically: true, encoding: .utf8)
}

private func popActiveSymbol(dataDir: String) -> GoldSymbol? {
    guard let url = activeSymbolFile(dataDir: dataDir),
          let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
    try? FileManager.default.removeItem(at: url)
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : GoldSymbol(raw: trimmed)
}

let input = PluginInput.read()
let isEn = input.isEnglish
let defaultSym = GoldSymbol(raw: input.cfgString("defaultSymbol", default: "AU9999"))
let defaultStyle = WindowStyle(rawValue: input.cfgString("defaultMode", default: "standard")) ?? .standard
let refreshSec = input.cfgInt("refreshIntervalSec", default: 5, min: 2, max: 60)
let colorScheme = input.cfgString("colorScheme", default: "cn")
let themeStyle = input.cfgString("themeStyle", default: "white")
let flag = input.arguments.first ?? ""

if flag == "--get-alerts" {
    emitEncodableJSON(loadAlertsStore(dataDir: input.dataDir, input: input))
    exit(0)
}

if flag == "--save-alerts" {
    let rawJson = !input.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? input.query
        : (input.arguments.count >= 2 ? input.arguments[1] : "")
    guard let data = rawJson.data(using: .utf8),
          let req = try? JSONDecoder().decode(SaveAlertInput.self, from: data) else {
        emitEncodableJSON(SaveAlertResult(ok: false, alerts: nil, error: "invalid_payload"))
        exit(0)
    }

    let sym = GoldSymbol(raw: req.symbol)
    var store = loadAlertsStore(dataDir: input.dataDir, input: input)
    if let cd = req.cooldownMinutes { store.cooldownMinutes = max(1, min(240, cd)) }
    let cleanHigh = (req.highPrice ?? 0) > 0 ? req.highPrice : nil
    let cleanLow = (req.lowPrice ?? 0) > 0 ? req.lowPrice : nil
    store.rules[sym.rawValue] = SymbolAlertRule(
        enabled: req.enabled && (cleanHigh != nil || cleanLow != nil), highPrice: cleanHigh, lowPrice: cleanLow
    )
    let saved = saveAlertsStore(dataDir: input.dataDir, store: store)
    resetAlertStateForSymbol(dataDir: input.dataDir, symbol: sym.rawValue)
    emitEncodableJSON(SaveAlertResult(ok: saved, alerts: summarizeAlert(store: store, symbol: sym), error: saved ? nil : "save_failed"))
    exit(0)
}

if flag == "--quote" {
    let rawArg = input.arguments.count >= 2 ? input.arguments[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
    let targetSym = rawArg.isEmpty ? (popActiveSymbol(dataDir: input.dataDir) ?? defaultSym) : GoldSymbol(raw: rawArg)
    let quotes = resolveQuotes(dataDir: input.dataDir)
    let summary = summarizeAlert(store: loadAlertsStore(dataDir: input.dataDir, input: input), symbol: targetSym)
    let dockState = readDockState(dataDir: input.dataDir, consumeSnap: true)

    if let q = quotes[targetSym] {
        let series = resolveIntradaySeries(dataDir: input.dataDir, symbol: targetSym, quote: q)
        let triggered = evaluateAndNotifyAlerts(dataDir: input.dataDir, quote: q, symbol: targetSym, input: input, isEn: isEn)
        emitEncodableJSON(GoldSnapshotPayload(
            ok: true, symbol: q.symbol, name: isEn ? targetSym.englishName : q.name, unit: isEn ? "CNY/g" : q.unit,
            price: q.price, preClose: q.preClose, open: q.open, high: q.high, low: q.low, bid: q.bid, ask: q.ask,
            change: q.change, changePct: q.changePct, time: q.time, date: q.date,
            source: isEn ? "Sina Finance · Live" : q.source, colorScheme: colorScheme, themeStyle: themeStyle,
            defaultMode: defaultStyle.rawValue, refreshIntervalSec: refreshSec, series: series,
            alerts: summary, alertTriggered: triggered, dockState: dockState, error: nil
        ))
    } else {
        emitEncodableJSON(GoldSnapshotPayload(
            ok: false, symbol: targetSym.rawValue, name: isEn ? targetSym.englishName : targetSym.displayName,
            unit: isEn ? "CNY/g" : "元/克", price: 0, preClose: 0, open: 0, high: 0, low: 0, bid: 0, ask: 0,
            change: 0, changePct: 0, time: "--:--:--", date: "", source: isEn ? "Offline" : "离线",
            colorScheme: colorScheme, themeStyle: themeStyle, defaultMode: defaultStyle.rawValue,
            refreshIntervalSec: refreshSec, series: [], alerts: summary, alertTriggered: nil, dockState: dockState,
            error: isEn ? "Failed to fetch live gold quote. Check network permission." : "实时行情拉取失败，请检查网络或插件联网权限"
        ))
    }
    exit(0)
}

if flag == "--check-frame" {
    let winId = input.arguments.count >= 2 ? input.arguments[1] : "gold-monitor-hud"
    let mode = input.arguments.count >= 3 ? input.arguments[2] : "standard"
    let returnMode = input.arguments.count >= 4 ? input.arguments[3] : "standard"
    emitEncodableJSON(checkWindowEdgeState(dataDir: input.dataDir, windowId: winId, mode: mode, returnMode: returnMode))
    exit(0)
}

if flag == "--snap-dock" {
    let edge = input.arguments.count >= 2 ? input.arguments[1] : "right"
    let winId = input.arguments.count >= 3 ? input.arguments[2] : "gold-monitor-hud"
    let frames = loadAllWindowFrames(dataDir: input.dataDir)
    let cur = frames[winId] ?? frames["gold-monitor-hud"]
        ?? WindowFrameRecord(x: 1300, y: 760, width: 212, height: 96, opacity: 1.0, pinOnTop: true, updatedAtEpoch: nil)
    let origin = computeSnapOrigin(edge: edge, sourceFrame: cur, targetW: 212, targetH: 96)
    emitEncodableJSON(SnapDockResult(ok: true, edge: edge, x: origin.x, y: origin.y))
    exit(0)
}

if flag == "--switch-mini" || flag == "--switch-standard" || flag == "--switch-dock" {
    if input.arguments.count >= 2 { saveActiveSymbol(dataDir: input.dataDir, symbol: GoldSymbol(raw: input.arguments[1])) }
    let targetStyle: WindowStyle = flag == "--switch-mini" ? .mini : (flag == "--switch-dock" ? .dock : .standard)
    let br = openFloatingWindow(style: targetStyle, input: input, isEn: isEn)
    emitEncodableJSON(SwitchResultPayload(ok: br.ok, error: br.error, message: br.message))
    exit(0)
}

let quotes = resolveQuotes(dataDir: input.dataDir)
if flag == "--card" {
    PluginOutput.emit(buildQuoteViewPayload(quotes: quotes, primarySymbol: defaultSym, isEn: isEn, openedStyle: nil, bridgeResult: nil, toast: nil))
    exit(0)
}

let targetStyle: WindowStyle = flag == "--open-mini" ? .mini : (flag == "--open-dock" ? .dock : (flag == "--open-floating" ? .standard : defaultStyle))
let bridgeResp = openFloatingWindow(style: targetStyle, input: input, isEn: isEn)
let toast: String? = bridgeResp.ok ? (
    targetStyle == .dock ? (isEn ? "Edge-Docked Gold Strip Opened" : "已打开靠边超精简金价挂件")
        : (targetStyle == .mini ? (isEn ? "Mini Gold Ticker Opened" : "已打开 Mini 极简金价悬浮条")
            : (isEn ? "Floating Gold HUD Opened" : "已打开置顶黄金悬浮窗"))
) : nil
PluginOutput.emit(buildQuoteViewPayload(quotes: quotes, primarySymbol: defaultSym, isEn: isEn, openedStyle: targetStyle, bridgeResult: bridgeResp, toast: toast))

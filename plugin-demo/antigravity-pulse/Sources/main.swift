import Darwin
import Foundation
import PluginKit

private struct SnapResultPayload: Codable {
    let ok: Bool
    let x: Double
    let y: Double
    let edge: String
}

private struct PrefsUpdateResponse: Codable {
    let ok: Bool
    let currency: String
    let usdToCnyRate: Double
    let exclusiveQuota: Bool
}

// Fast path for official Antigravity CLI `statusLine` hook (raw JSON piped directly to stdin; <5ms, zero log scan).
let rawCLIArgs = Array(CommandLine.arguments.dropFirst())
if rawCLIArgs.first == "--record-statusline" {
    let targetDir = rawCLIArgs.count >= 2 ? rawCLIArgs[1] : defaultPulseDataDir()
    let stdinData = Darwin.isatty(STDIN_FILENO) != 0 ? Data() : FileHandle.standardInput.readDataToEndOfFile()
    _ = recordAgyStatusLinePayload(rawData: stdinData, dataDir: targetDir)
    exit(0)
}

let input = PluginInput.read()
let isEn = input.isEnglish
let defaultMode = HUDMode.parse(input.cfgString("defaultMode", default: "dock"))
let themeStyle = input.cfgString("themeStyle", default: "auto")
let refreshSec = input.cfgInt("refreshIntervalSec", default: 3, min: 2, max: 60)
let contextOverrideK = input.cfgString("contextWindowK", default: "auto")
let includeCliLogs = input.cfgBool("includeCliLogs", default: true)
let cacheAlertsEnabled = input.cfgBool("cacheDropAlertEnabled", default: true)
let sessionDoneAlertEnabled = input.cfgBool("sessionDoneAlertEnabled", default: true)
let flag = input.arguments.first ?? ""

if flag == "--focus-session" {
    let sid = input.arguments.count >= 2 ? input.arguments[1] : ""
    let title = input.arguments.count >= 3 ? input.arguments[2] : ""
    emitEncodableJSON(focusAntigravityConversation(sessionId: sid, title: title, isEn: isEn))
    exit(0)
}

if flag == "--check-frame" {
    let winId = input.arguments.count >= 2 ? input.arguments[1] : PulseConstants.windowID
    let mode = input.arguments.count >= 3 ? input.arguments[2] : "dock"
    let returnMode = input.arguments.count >= 4 ? input.arguments[3] : "standard"
    emitEncodableJSON(checkWindowEdgeState(dataDir: input.dataDir, windowId: winId, mode: mode, returnMode: returnMode))
    exit(0)
}

if flag == "--snap-dock" {
    let edge = input.arguments.count >= 2 ? input.arguments[1] : "right"
    let winId = input.arguments.count >= 3 ? input.arguments[2] : PulseConstants.windowID
    let frames = loadAllWindowFrames(dataDir: input.dataDir)
    let fallback = WindowFrameRecord(
        x: 900, y: 400, width: PulseConstants.standardHudWidth, height: PulseConstants.standardHudHeight,
        opacity: 1.0, pinOnTop: true, updatedAtEpoch: nil
    )
    let src = frames[winId] ?? frames[PulseConstants.windowID] ?? fallback
    let dsz = dockTargetSize(for: edge)
    let origin = computeSnapOrigin(edge: edge, sourceFrame: src, targetW: dsz.w, targetH: dsz.h)
    saveDockState(dataDir: input.dataDir, state: DockLaunchState(edge: edge, fromMode: "dock", pendingSnap: false))
    updateSavedWindowFrame(dataDir: input.dataDir, windowId: winId, x: origin.x, y: origin.y, width: dsz.w, height: dsz.h)
    emitEncodableJSON(SnapResultPayload(ok: true, x: origin.x, y: origin.y, edge: edge))
    exit(0)
}

if flag == "--set-prefs" {
    var prefs = loadDashboardPrefs(dataDir: input.dataDir, input: input)
    if input.arguments.count >= 2, let data = input.arguments[1].data(using: .utf8),
       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        if let cur = obj["currency"] as? String {
            prefs.currency = cur.uppercased() == "CNY" ? "CNY" : "USD"
        }
        if let rate = (obj["usdToCnyRate"] as? NSNumber)?.doubleValue, rate.isFinite {
            prefs.usdToCnyRate = min(20.0, max(1.0, rate))
        }
        if let excl = obj["exclusiveQuota"] as? Bool {
            prefs.exclusiveQuota = excl
        }
        saveDashboardPrefs(dataDir: input.dataDir, prefs: prefs)
    }
    emitEncodableJSON(PrefsUpdateResponse(
        ok: true, currency: prefs.currency, usdToCnyRate: prefs.usdToCnyRate, exclusiveQuota: prefs.exclusiveQuota
    ))
    exit(0)
}

if flag == "--setup-statusline" {
    let binPath = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
    emitEncodableJSON(installStatusLineHook(binaryPath: binPath, dataDir: input.dataDir, isEn: isEn))
    exit(0)
}

if flag == "--remove-statusline" {
    emitEncodableJSON(uninstallStatusLineHook(isEn: isEn))
    exit(0)
}

if flag == "--analytics" {
    let rangeKey = input.arguments.count >= 2 ? input.arguments[1] : "365d"
    emitEncodableJSON(buildAnalyticsPayload(
        rangeKey: rangeKey,
        includeCliLogs: includeCliLogs,
        themeStyle: themeStyle,
        dataDir: input.dataDir,
        input: input,
        isEn: isEn
    ))
    exit(0)
}

if flag == "--day-detail" {
    let dateKey = input.arguments.count >= 2 ? input.arguments[1] : localDateKey(for: Date())
    emitEncodableJSON(buildDayDetailPayload(dateKey: dateKey, includeCliLogs: includeCliLogs, dataDir: input.dataDir, isEn: isEn))
    exit(0)
}

if flag == "--copy-share-image" {
    emitEncodableJSON(handleCopyShareImage(input: input, isEn: isEn))
    exit(0)
}

if flag == "--save-share-image" {
    emitEncodableJSON(handleSaveShareImage(input: input, isEn: isEn))
    exit(0)
}

let requestedSessionId: String? = (flag == "--snapshot" && input.arguments.count >= 2) ? input.arguments[1] : nil
let outcome = scanTranscripts(options: ScanOptions(
    includeCliLogs: includeCliLogs,
    contextWindowOverrideK: contextOverrideK,
    requestedSessionId: requestedSessionId,
    dataDir: input.dataDir,
    isEn: isEn
))
let prefs = loadDashboardPrefs(dataDir: input.dataDir, input: input)
let officialQuota = evaluateOfficialQuota(
    dataDir: input.dataDir,
    hotFiles: outcome.hotFiles,
    exclusiveQuota: prefs.exclusiveQuota,
    now: Date().timeIntervalSince1970,
    isEn: isEn
)

if flag == "--focus-session-card" {
    let sid = input.arguments.count >= 2 ? input.arguments[1] : ""
    let title = input.arguments.count >= 3 ? input.arguments[2] : ""
    let res = focusAntigravityConversation(sessionId: sid, title: title, isEn: isEn)
    PluginOutput.emit(buildLauncherCardPayload(
        outcome: outcome, isEn: isEn, openedMode: nil, bridgeResult: nil, quota: officialQuota, prefs: prefs, customToast: res.message
    ))
    exit(0)
}

if flag == "--snapshot" {
    let alertBanner = evaluatePulseAlerts(
        outcome: outcome,
        cacheAlertsEnabled: cacheAlertsEnabled,
        sessionDoneAlertEnabled: sessionDoneAlertEnabled,
        input: input,
        isEn: isEn
    )
    let dockState = readDockState(dataDir: input.dataDir, consumeSnap: true)
    emitEncodableJSON(PulseSnapshot(
        ok: true, error: nil,
        scannedFiles: outcome.scannedFiles, parsedFilesNow: outcome.parsedFilesNow,
        scanDurationMs: outcome.scanDurationMs, refreshedAt: formatShortClock(Date().timeIntervalSince1970),
        refreshIntervalSec: refreshSec, defaultMode: defaultMode.rawValue, themeStyle: themeStyle,
        currency: prefs.currency, usdToCnyRate: prefs.usdToCnyRate,
        runningCount: outcome.runningCount, completedCount: outcome.completedCount,
        activeSession: outcome.activeSession, recentSessions: outcome.recentSessions,
        window5h: outcome.window5h, windowToday: outcome.windowToday, window7d: outcome.window7d,
        officialQuota: officialQuota, alertBanner: alertBanner, dockState: dockState
    ))
    exit(0)
}

if flag == "--open-dashboard" {
    let bridgeResp = openDashboardWindow(input: input, isEn: isEn)
    PluginOutput.emit(buildLauncherCardPayload(
        outcome: outcome, isEn: isEn, openedMode: nil, openedDashboard: true, bridgeResult: bridgeResp, quota: officialQuota, prefs: prefs
    ))
    exit(0)
}

if flag == "--open-floating" || flag == "--open-standard" || flag == "--open-dock" || flag == "--open-mini" {
    let targetMode: HUDMode = flag == "--open-standard" ? .standard : (flag == "--open-dock" || flag == "--open-mini" ? .dock : defaultMode)
    let bridgeResp = openFloatingHUD(mode: targetMode, input: input, isEn: isEn)
    PluginOutput.emit(buildLauncherCardPayload(
        outcome: outcome, isEn: isEn, openedMode: targetMode, bridgeResult: bridgeResp, quota: officialQuota, prefs: prefs
    ))
    exit(0)
}

PluginOutput.emit(buildLauncherCardPayload(outcome: outcome, isEn: isEn, openedMode: nil, bridgeResult: nil, quota: officialQuota, prefs: prefs))

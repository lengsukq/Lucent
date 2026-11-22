import CoreGraphics
import Foundation
import LucentFoundation
import LucentSystem

extension PluginWindowControlRouter {
    func dispatch(
        _ action: String,
        params: [String: Any],
        hostContext: PluginBridgeHostContext
    ) -> [String: Any] {
        let cap = PluginCapability.windowControl
        switch action {
        case "status", "list":
            let snapshot = status(preferredPID: hostContext.preferredWindowTargetPID?())
            var payload: [String: Any] = [
                "accessibilityGranted": snapshot.trusted,
                "settingsURL": PluginSystemTCCKind.accessibility.systemSettingsURLString,
                "displays": snapshot.displays.map(Self.encodeDisplay),
                "windows": snapshot.windows.map { Self.encodeWindow($0, displays: snapshot.displays) },
                "canUndo": snapshot.canUndo
            ]
            if let active = snapshot.activeWindow {
                payload["activeWindow"] = Self.encodeWindow(active, displays: snapshot.displays)
            }
            return PluginHostBridgeHandlers.okJSON(cap, action, payload)

        case "requestPermission":
            let st = PluginHostTCCBroker.requestAccessOnBehalfOfPlugin(.accessibility)
            return PluginHostBridgeHandlers.okJSON(cap, action, [
                "granted": st.isGranted,
                "status": st.rawValue,
                "settingsURL": PluginSystemTCCKind.accessibility.systemSettingsURLString
            ])

        case "snap":
            guard let rawPreset = params["preset"] as? String,
                  let preset = WindowSnapPreset(rawValue: rawPreset) else {
                return PluginHostBridgeHandlers.errorJSON(
                    "invalid_params",
                    "缺少合法的 preset 参数（如 leftHalf / rightHalf / maximize / center / nextDisplay / restore）",
                    capability: cap
                )
            }
            let gap = CGFloat((params["gap"] as? NSNumber)?.doubleValue ?? 0)
            let explicitPID = (params["pid"] as? NSNumber)?.int32Value
            let windowIndex = (params["windowIndex"] as? NSNumber)?.intValue
            let outcome = snap(
                preset: preset,
                gap: gap,
                explicitPID: explicitPID,
                windowIndex: windowIndex,
                preferredPID: hostContext.preferredWindowTargetPID?()
            )
            if outcome.status == "permission_denied" {
                return PluginHostBridgeHandlers.errorJSON(
                    "tcc_not_granted", outcome.message, capability: cap
                )
            }
            if outcome.status == "applied", params["showFeedback"] as? Bool == true,
               let feedback = hostContext.windowControlFeedback {
                let appLabel = outcome.window?.appName ?? ""
                let dispLabel = outcome.display?.name ?? ""
                let sub = [appLabel, dispLabel].filter { !$0.isEmpty }.joined(separator: " · ")
                feedback(preset.localizedTitle, sub, preset.symbolName)
            }
            var data: [String: Any] = [
                "status": outcome.status,
                "preset": preset.rawValue,
                "message": outcome.message
            ]
            if let win = outcome.window {
                data["window"] = Self.encodeWindow(win, displays: outcome.display.map { [$0] } ?? [])
            }
            if let applied = outcome.appliedFrame {
                data["appliedFrame"] = Self.encodeRect(applied)
            }
            if let disp = outcome.display {
                data["display"] = Self.encodeDisplay(disp)
            }
            return PluginHostBridgeHandlers.okJSON(cap, action, data)

        case "applyWorkspace":
            guard let rawSlots = params["slots"] as? [[String: Any]], !rawSlots.isEmpty else {
                return PluginHostBridgeHandlers.errorJSON("invalid_params", "缺少非空 slots 窗口布局数组", capability: cap)
            }
            let slots = rawSlots.compactMap(Self.decodeSlot)
            guard !slots.isEmpty else {
                return PluginHostBridgeHandlers.errorJSON("invalid_params", "slots 中不包含合法的窗口槽位定义", capability: cap)
            }
            let gap = CGFloat((params["gap"] as? NSNumber)?.doubleValue ?? 0)
            let launchMissing = params["launchMissing"] as? Bool ?? true
            let workspaceName = (params["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let outcome = applyWorkspace(slots: slots, gap: gap, launchMissing: launchMissing)
            if outcome.status == "permission_denied" {
                return PluginHostBridgeHandlers.errorJSON(
                    "tcc_not_granted",
                    L10n.pick("宿主尚未获得「辅助功能」权限", "Accessibility permission is not granted to Lucent"),
                    capability: cap
                )
            }
            if outcome.movedCount > 0, params["showFeedback"] as? Bool == true,
               let feedback = hostContext.windowControlFeedback {
                let title = workspaceName.isEmpty
                    ? L10n.pick("工作区布局已应用", "Workspace Applied")
                    : workspaceName
                let sub = L10n.pick(
                    "已排列 \(outcome.movedCount) 个窗口" + (outcome.skippedCount > 0 ? " · 跳过 \(outcome.skippedCount)" : ""),
                    "Arranged \(outcome.movedCount) window(s)" + (outcome.skippedCount > 0 ? " · \(outcome.skippedCount) skipped" : "")
                )
                feedback(title, sub, "rectangle.3.group.fill")
            }
            return PluginHostBridgeHandlers.okJSON(cap, action, [
                "status": outcome.status,
                "movedCount": outcome.movedCount,
                "skippedCount": outcome.skippedCount,
                "missingApps": outcome.missingApps,
                "launchedApps": outcome.launchedApps,
                "usedFallbackDisplay": outcome.usedFallbackDisplay
            ])

        default:
            return PluginHostBridgeHandlers.errorJSON(
                "invalid_action",
                "windowControl 支持 status / list / requestPermission / snap / applyWorkspace",
                capability: cap
            )
        }
    }

    private static func decodeSlot(_ raw: [String: Any]) -> WindowWorkspaceSlot? {
        guard let bundleID = (raw["bundleID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bundleID.isEmpty, bundleID.count <= 256,
              let rx = (raw["rx"] as? NSNumber)?.doubleValue,
              let ry = (raw["ry"] as? NSNumber)?.doubleValue,
              let rw = (raw["rw"] as? NSNumber)?.doubleValue,
              let rh = (raw["rh"] as? NSNumber)?.doubleValue,
              rx.isFinite, ry.isFinite, rw.isFinite, rh.isFinite else {
            return nil
        }
        let appName = ((raw["appName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { $0.isEmpty ? nil : String($0.prefix(128)) } ?? bundleID
        let title = (raw["windowTitle"] as? String).map { String($0.prefix(256)) }
        let windowIndex = (raw["windowIndex"] as? NSNumber)?.intValue ?? 0
        let displayIndex = (raw["displayIndex"] as? NSNumber)?.intValue ?? 0
        let displayID = (raw["displayID"] as? NSNumber)?.uint32Value
        return WindowWorkspaceSlot(
            bundleID: bundleID, appName: appName, windowTitle: title,
            windowIndex: windowIndex, displayIndex: displayIndex, displayID: displayID,
            rx: rx, ry: ry, rw: rw, rh: rh
        )
    }

    private static func encodeRect(_ rect: CGRect) -> [String: Any] {
        [
            "x": Int(rect.minX.rounded()),
            "y": Int(rect.minY.rounded()),
            "width": Int(rect.width.rounded()),
            "height": Int(rect.height.rounded())
        ]
    }

    private static func encodeDisplay(_ d: SystemDisplayRect) -> [String: Any] {
        [
            "displayID": d.displayID,
            "name": d.name,
            "isMain": d.isMain,
            "index": d.index,
            "frame": encodeRect(d.frame),
            "visibleFrame": encodeRect(d.visibleFrame)
        ]
    }

    private static func encodeWindow(_ w: ManagedWindowInfo, displays: [SystemDisplayRect]) -> [String: Any] {
        let matchedDisplay = displays.first(where: { $0.displayID == w.displayID })
            ?? (displays.indices.contains(w.displayIndex) ? displays[w.displayIndex] : displays.first)
        let norm = matchedDisplay.map { WindowLayoutGeometry.normalizedRect(of: w.frame, in: $0.visibleFrame) }
            ?? NormalizedWindowRect(rx: 0, ry: 0, rw: 1, rh: 1)
        return [
            "pid": w.pid,
            "bundleID": w.bundleID,
            "appName": w.appName,
            "title": w.title,
            "windowIndex": w.windowIndex,
            "displayID": w.displayID,
            "displayIndex": w.displayIndex,
            "displayName": matchedDisplay?.name ?? "",
            "isFocused": w.isFocused,
            "isMinimized": w.isMinimized,
            "isResizable": w.isResizable,
            "frame": encodeRect(w.frame),
            "rx": (norm.rx * 10_000).rounded() / 10_000,
            "ry": (norm.ry * 10_000).rounded() / 10_000,
            "rw": (norm.rw * 10_000).rounded() / 10_000,
            "rh": (norm.rh * 10_000).rounded() / 10_000
        ]
    }
}

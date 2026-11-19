import AppKit
import ApplicationServices
import Foundation

struct FocusResult: Codable {
    let ok: Bool
    let focused: Bool
    let matchedBy: String
    let axTrusted: Bool
    let message: String
}

private func axStringAttr(_ el: AXUIElement, _ attr: String) -> String {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, attr as CFString, &ref) == .success, let val = ref else { return "" }
    if let s = val as? String { return s }
    if let u = val as? URL { return u.absoluteString }
    return ""
}

private func findConversationLink(
    in windows: [AXUIElement],
    sessionId: String,
    title: String
) -> (window: AXUIElement, link: AXUIElement, matchedBy: String, sawAnyLink: Bool)? {
    let cleanId = sessionId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let uuidNeedle = cleanId.isEmpty ? "" : "/c/\(cleanId)"

    var sawAnyLink = false
    var titleFallback: (AXUIElement, AXUIElement)?

    for win in windows {
        var queue: [AXUIElement] = [win]
        var idx = 0
        while idx < queue.count && idx < 5000 {
            let el = queue[idx]
            idx += 1

            let role = axStringAttr(el, kAXRoleAttribute)
            if role == "AXLink" {
                sawAnyLink = true
                if !uuidNeedle.isEmpty {
                    let urlStr = axStringAttr(el, kAXURLAttribute).lowercased()
                    if urlStr.contains(uuidNeedle) {
                        return (win, el, "ax_uuid", true)
                    }
                }
                if titleFallback == nil && !cleanTitle.isEmpty {
                    let desc = axStringAttr(el, kAXDescriptionAttribute).trimmingCharacters(in: .whitespacesAndNewlines)
                    let axTitle = axStringAttr(el, kAXTitleAttribute).trimmingCharacters(in: .whitespacesAndNewlines)
                    if desc == cleanTitle || axTitle == cleanTitle {
                        titleFallback = (win, el)
                    }
                }
            }

            var childrenRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &childrenRef) == .success,
               let children = childrenRef as? [AXUIElement], !children.isEmpty {
                queue.append(contentsOf: children)
            }
        }
    }

    if let fb = titleFallback {
        return (fb.0, fb.1, "ax_title", sawAnyLink)
    }
    return nil
}

private func readAXWindows(_ axApp: AXUIElement) -> [AXUIElement] {
    var winsRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &winsRef) == .success,
          let wins = winsRef as? [AXUIElement] else { return [] }
    return wins
}

func focusAntigravityConversation(sessionId: String, title: String, isEn: Bool) -> FocusResult {
    let running = NSWorkspace.shared.runningApplications.first {
        ($0.bundleIdentifier ?? "").lowercased() == "com.google.antigravity"
    }
    guard let app = running else {
        let appURL = URL(fileURLWithPath: "/Applications/Antigravity.app")
        if FileManager.default.fileExists(atPath: appURL.path) {
            NSWorkspace.shared.open(appURL)
        }
        return FocusResult(
            ok: true, focused: false, matchedBy: "launched", axTrusted: AXIsProcessTrusted(),
            message: isEn ? "Launched Antigravity" : "已启动 Antigravity"
        )
    }

    app.activate(options: [.activateAllWindows])

    guard AXIsProcessTrusted() else {
        return FocusResult(
            ok: true, focused: false, matchedBy: "app_only", axTrusted: false,
            message: isEn ? "Activated Antigravity (grant Accessibility for direct jump)" : "已切回 Antigravity（开启辅助功能可直达指定对话）"
        )
    }

    let axApp = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)

    var windows = readAXWindows(axApp)
    for win in windows {
        var minRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(win, kAXMinimizedAttribute as CFString, &minRef) == .success,
           (minRef as? Bool) == true {
            AXUIElementSetAttributeValue(win, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
    }

    var match = findConversationLink(in: windows, sessionId: sessionId, title: title)
    if match == nil {
        Thread.sleep(forTimeInterval: 0.18)
        windows = readAXWindows(axApp)
        match = findConversationLink(in: windows, sessionId: sessionId, title: title)
    }

    if let hit = match {
        AXUIElementPerformAction(hit.window, kAXRaiseAction as CFString)
        AXUIElementPerformAction(hit.link, "AXScrollToVisible" as CFString)
        let pressErr = AXUIElementPerformAction(hit.link, kAXPressAction as CFString)
        app.activate(options: [.activateAllWindows])
        if pressErr == .success {
            return FocusResult(
                ok: true, focused: true, matchedBy: hit.matchedBy, axTrusted: true,
                message: isEn ? "Switched directly to conversation" : "已直达对应对话"
            )
        }
    }

    if let firstWin = windows.first {
        AXUIElementPerformAction(firstWin, kAXRaiseAction as CFString)
    }
    return FocusResult(
        ok: true, focused: false, matchedBy: "app_only", axTrusted: true,
        message: isEn ? "Activated Antigravity · title copied" : "已切回 Antigravity · 标题已复制"
    )
}

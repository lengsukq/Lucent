import LumakeyFoundation; import LumakeySearch; import LumakeyMedia; import LumakeySystem
import AppKit
import ApplicationServices
import Carbon
import Foundation

enum PluginSelectionFallback {
    private static let excludedBundleIDs: Set<String> = [
        "com.apple.keychainaccess",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop"
    ]

    private struct PasteboardItemSnapshot {
        let entries: [(NSPasteboard.PasteboardType, Data)]
    }

    @MainActor
    static func copySelectionWithPasteboardRestore(
        appElement: AXUIElement,
        bundleIdentifier: String
    ) -> String {
        guard !excludedBundleIDs.contains(bundleIdentifier) else { return "" }

        let pasteboard = NSPasteboard.general
        let initialChangeCount = pasteboard.changeCount
        let snapshot = snapshotPasteboard(pasteboard)

        if let copyItem = findEnabledCopyMenuItem(in: appElement),
           AXUIElementPerformAction(copyItem, kAXPressAction as CFString) == .success {
            if waitForPasteboardChange(pasteboard, from: initialChangeCount, maxSteps: 10) {
                return extractCopiedTextAndRestore(pasteboard: pasteboard, snapshot: snapshot)
            }
        }

        postSimulatedCommandCopy()
        if waitForPasteboardChange(pasteboard, from: initialChangeCount, maxSteps: 18) {
            return extractCopiedTextAndRestore(pasteboard: pasteboard, snapshot: snapshot)
        }

        return ""
    }

    @MainActor
    private static func snapshotPasteboard(_ pasteboard: NSPasteboard) -> [PasteboardItemSnapshot] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        return items.compactMap { item in
            var entries: [(NSPasteboard.PasteboardType, Data)] = []
            for type in item.types {
                if let data = item.data(forType: type) {
                    entries.append((type, data))
                }
            }
            return entries.isEmpty ? nil : PasteboardItemSnapshot(entries: entries)
        }
    }

    @MainActor
    private static func restorePasteboard(_ pasteboard: NSPasteboard, snapshot: [PasteboardItemSnapshot]) {
        pasteboard.clearContents()
        guard !snapshot.isEmpty else { return }
        let items: [NSPasteboardItem] = snapshot.map { snap in
            let item = NSPasteboardItem()
            for (type, data) in snap.entries {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(items)
    }

    @MainActor
    private static func extractCopiedTextAndRestore(
        pasteboard: NSPasteboard,
        snapshot: [PasteboardItemSnapshot]
    ) -> String {
        let text = pasteboard.string(forType: .string) ?? ""
        restorePasteboard(pasteboard, snapshot: snapshot)
        return text
    }

    @MainActor
    private static func waitForPasteboardChange(
        _ pasteboard: NSPasteboard,
        from initialChangeCount: Int,
        maxSteps: Int
    ) -> Bool {
        for _ in 0..<maxSteps {
            if pasteboard.changeCount != initialChangeCount {
                return true
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return pasteboard.changeCount != initialChangeCount
    }

    @MainActor
    private static func postSimulatedCommandCopy() {
        let source = CGEventSource(stateID: .privateState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false) else {
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }

    private static func findEnabledCopyMenuItem(in appElement: AXUIElement) -> AXUIElement? {
        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
              let menuBarObj = menuBarRef,
              CFGetTypeID(menuBarObj) == AXUIElementGetTypeID() else {
            return nil
        }
        let menuBar = unsafeDowncast(menuBarObj, to: AXUIElement.self)
        for topItem in axChildren(of: menuBar).dropFirst() {
            for subMenu in axChildren(of: topItem) {
                if let match = findCopyMenuItem(in: subMenu, depth: 0) {
                    return match
                }
            }
        }
        return nil
    }

    private static func findCopyMenuItem(in menu: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth <= 1 else { return nil }
        for item in axChildren(of: menu) {
            if isPureCommandCMenuItem(item), isAXEnabled(item) {
                return item
            }
            if depth == 0 {
                for sub in axChildren(of: item) {
                    if let nested = findCopyMenuItem(in: sub, depth: 1) {
                        return nested
                    }
                }
            }
        }
        return nil
    }

    private static func isPureCommandCMenuItem(_ item: AXUIElement) -> Bool {
        var charRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(item, kAXMenuItemCmdCharAttribute as CFString, &charRef) == .success,
              let cmdChar = charRef as? String,
              cmdChar.uppercased() == "C" else {
            return false
        }
        var modRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(item, kAXMenuItemCmdModifiersAttribute as CFString, &modRef) == .success,
           let mods = modRef as? Int {
            return mods == 0
        }
        return true
    }

    private static func isAXEnabled(_ element: AXUIElement) -> Bool {
        var enabledRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &enabledRef) == .success,
              let enabled = enabledRef as? Bool else {
            return false
        }
        return enabled
    }

    private static func axChildren(of element: AXUIElement) -> [AXUIElement] {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref) == .success,
              let array = ref as? [AXUIElement] else {
            return []
        }
        return array
    }
}

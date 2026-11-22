import ApplicationServices
import CoreGraphics
import Foundation

enum SystemWindowAXHelpers {
    static let axTimeoutSeconds: Float = 0.15
    static let enhancedUIName = "AXEnhancedUserInterface"

    static func standardAXWindows(of appEl: AXUIElement) -> [AXUIElement] {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &ref) == .success,
              let list = ref as? [AXUIElement] else { return [] }
        return list.filter { win in
            AXUIElementSetMessagingTimeout(win, axTimeoutSeconds)
            let role = stringAttr(win, kAXRoleAttribute as CFString) ?? ""
            let subrole = stringAttr(win, kAXSubroleAttribute as CFString) ?? ""
            guard role == (kAXWindowRole as String) else { return false }
            return subrole.isEmpty || subrole == (kAXStandardWindowSubrole as String)
        }
    }

    static func pickWindow(in windows: [AXUIElement], windowIndex: Int, titleHint: String?) -> AXUIElement {
        if let hint = titleHint?.trimmingCharacters(in: .whitespacesAndNewlines), !hint.isEmpty,
           let matched = windows.first(where: { stringAttr($0, kAXTitleAttribute as CFString) == hint }) {
            return matched
        }
        if windows.indices.contains(windowIndex) { return windows[windowIndex] }
        return windows[0]
    }

    static func readFrame(of win: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(win, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posVal = posRef, let sizeVal = sizeRef,
              CFGetTypeID(posVal) == AXValueGetTypeID(), CFGetTypeID(sizeVal) == AXValueGetTypeID() else { return nil }
        var pt = CGPoint.zero
        var sz = CGSize.zero
        guard AXValueGetValue(posVal as! AXValue, .cgPoint, &pt),
              AXValueGetValue(sizeVal as! AXValue, .cgSize, &sz),
              sz.width.isFinite, sz.height.isFinite else { return nil }
        return CGRect(origin: pt, size: sz)
    }

    @discardableResult
    static func setPosition(_ pt: CGPoint, on win: AXUIElement) -> Bool {
        var mutable = pt
        guard let val = AXValueCreate(.cgPoint, &mutable) else { return false }
        return AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, val) == .success
    }

    @discardableResult
    static func setSize(_ sz: CGSize, on win: AXUIElement) -> Bool {
        var mutable = sz
        guard let val = AXValueCreate(.cgSize, &mutable) else { return false }
        return AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, val) == .success
    }

    static func stringAttr(_ el: AXUIElement, _ attr: CFString) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr, &ref) == .success else { return nil }
        return ref as? String
    }

    static func boolAttr(_ el: AXUIElement, _ attr: CFString) -> Bool? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr, &ref) == .success else { return nil }
        return (ref as? NSNumber)?.boolValue
    }

    static func elementAttr(_ el: AXUIElement, _ attr: CFString) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr, &ref) == .success,
              let val = ref, CFGetTypeID(val) == AXUIElementGetTypeID() else { return nil }
        return (val as! AXUIElement)
    }
}

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import LucentFoundation

public struct DetectedAXControlRegion: Equatable, Sendable {
    public let quartzFrame: CGRect
    public let roleLabel: String
    public let depth: Int

    public init(quartzFrame: CGRect, roleLabel: String, depth: Int) {
        self.quartzFrame = quartzFrame
        self.roleLabel = roleLabel
        self.depth = depth
    }
}

/// Asynchronous, timeout-guarded Accessibility sub-control detector inspired by AirSnip ADR 0039.
/// Runs `AXUIElementCopyElementAtPosition` off the main thread so hung target apps never stall the overlay.
public final class AccessibilityElementMatcher: @unchecked Sendable {
    public static let shared = AccessibilityElementMatcher()

    private let workerQueue = DispatchQueue(label: "app.lucent.capture.ax-matcher", qos: .userInteractive)

    private init() {}

    public var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    public func probeHierarchy(
        atQuartzPoint pt: CGPoint,
        excludingPID: pid_t,
        timeoutMs: Int = 140
    ) async -> [DetectedAXControlRegion] {
        guard AXIsProcessTrusted() else { return [] }
        return await withTaskGroup(of: [DetectedAXControlRegion]?.self) { group in
            group.addTask {
                await withCheckedContinuation { cont in
                    self.workerQueue.async {
                        cont.resume(returning: Self.querySync(at: pt, excludingPID: excludingPID))
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(timeoutMs))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? []
        }
    }

    private static func querySync(at pt: CGPoint, excludingPID: pid_t) -> [DetectedAXControlRegion] {
        let systemWide = AXUIElementCreateSystemWide()
        let messagingTimeout: Float = 0.12
        AXUIElementSetMessagingTimeout(systemWide, messagingTimeout)

        var hitRef: AXUIElement?
        let status = AXUIElementCopyElementAtPosition(systemWide, Float(pt.x), Float(pt.y), &hitRef)
        guard status == .success, let leaf = hitRef else { return [] }

        var pid: pid_t = 0
        AXUIElementGetPid(leaf, &pid)
        guard pid != 0, pid != excludingPID else { return [] }
        AXUIElementSetMessagingTimeout(leaf, messagingTimeout)

        var chain: [DetectedAXControlRegion] = []
        var current: AXUIElement? = leaf
        var visited = 0

        while let el = current, visited < 10 {
            visited += 1
            AXUIElementSetMessagingTimeout(el, messagingTimeout)
            let role = stringAttr(el, kAXRoleAttribute as CFString) ?? ""
            if role == (kAXApplicationRole as String) || role == "AXMenuBar" { break }
            if let rect = frameOfElement(el),
               rect.width >= 14, rect.height >= 12,
               rect.contains(pt) {
                let roleDesc = stringAttr(el, kAXRoleDescriptionAttribute as CFString)
                    ?? cleanRoleName(role)
                let title = stringAttr(el, kAXTitleAttribute as CFString)
                    ?? stringAttr(el, kAXDescriptionAttribute as CFString)
                    ?? ""
                let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                let shortTitle = trimmed.count > 20 ? String(trimmed.prefix(20)) + "…" : trimmed
                let label = shortTitle.isEmpty ? roleDesc : "\(roleDesc) · \(shortTitle)"
                if chain.last.map({ !nearlyEqual($0.quartzFrame, rect) }) ?? true {
                    chain.append(DetectedAXControlRegion(quartzFrame: rect, roleLabel: label, depth: chain.count))
                }
            }
            if role == (kAXWindowRole as String) { break }
            current = elementAttr(el, kAXParentAttribute as CFString)
        }
        _ = messagingTimeout
        return chain
    }

    private static func frameOfElement(_ element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posVal = posRef, let sizeVal = sizeRef,
              CFGetTypeID(posVal) == AXValueGetTypeID(),
              CFGetTypeID(sizeVal) == AXValueGetTypeID() else {
            return nil
        }
        var pt = CGPoint.zero
        var sz = CGSize.zero
        guard AXValueGetValue(posVal as! AXValue, .cgPoint, &pt),
              AXValueGetValue(sizeVal as! AXValue, .cgSize, &sz),
              sz.width.isFinite, sz.height.isFinite else {
            return nil
        }
        return CGRect(origin: pt, size: sz)
    }

    private static func stringAttr(_ element: AXUIElement, _ attr: CFString) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr, &ref) == .success else { return nil }
        return ref as? String
    }

    private static func elementAttr(_ element: AXUIElement, _ attr: CFString) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr, &ref) == .success,
              let val = ref, CFGetTypeID(val) == AXUIElementGetTypeID() else { return nil }
        return (val as! AXUIElement)
    }

    private static func cleanRoleName(_ raw: String) -> String {
        raw.hasPrefix("AX") ? String(raw.dropFirst(2)) : raw
    }

    private static func nearlyEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 3 && abs(a.minY - b.minY) < 3
            && abs(a.width - b.width) < 4 && abs(a.height - b.height) < 4
    }
}

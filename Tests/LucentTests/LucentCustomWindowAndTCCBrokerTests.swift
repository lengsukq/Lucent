import AppKit
import Foundation
import Testing
@testable import LucentCore
@testable import LucentFoundation

@Suite("Plugin v3.6 Custom Window Canvas, Host TCC Broker & Extended Bridge Verification")
struct LucentCustomWindowAndTCCBrokerTests {
    private func makeIsolatedDir(_ label: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lk-win-tcc-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("PluginCustomWindowSpec enforces path-traversal isolation, opacity floor, capability tiers and deep links")
    func customWindowSpecValidationAndDeepLinks() throws {
        let dir = try makeIsolatedDir("spec")
        defer { try? FileManager.default.removeItem(at: dir) }

        let uiDir = dir.appendingPathComponent("ui", isDirectory: true)
        try FileManager.default.createDirectory(at: uiDir, withIntermediateDirectories: true)
        let htmlFile = uiDir.appendingPathComponent("widget.html")
        try "<html><body>ok</body></html>".write(to: htmlFile, atomically: true, encoding: .utf8)

        #expect(PluginCustomWindowSpec.isSafeRelativeAssetPath("ui/widget.html"))
        #expect(!PluginCustomWindowSpec.isSafeRelativeAssetPath("../secret.html"))
        #expect(!PluginCustomWindowSpec.isSafeRelativeAssetPath("/etc/passwd"))
        #expect(!PluginCustomWindowSpec.isSafeRelativeAssetPath("~/widget.html"))
        #expect(PluginCustomWindowSpec.resolveSafeHTMLFileURL(relativePath: "ui/widget.html", bundleDirectory: dir) != nil)
        #expect(PluginCustomWindowSpec.resolveSafeHTMLFileURL(relativePath: "ui/missing.html", bundleDirectory: dir) == nil)

        let stdSpec = PluginCustomWindowSpec(
            pluginID: "demo-win", windowID: "main", htmlPath: "ui/widget.html",
            width: 80, height: 40, chrome: .standard, transparent: false, pinOnTop: false, opacity: 0.01
        )
        #expect(stdSpec.width == 180)
        #expect(stdSpec.height == 96)
        #expect(stdSpec.opacity == PluginCustomWindowSpec.minOpacity)
        #expect(!stdSpec.requiresFloatingCapability)
        #expect(stdSpec.showInDock)
        #expect(stdSpec.requiredCapability == .window)
        #expect(stdSpec.isSatisfied(by: [.window]))
        #expect(stdSpec.isSatisfied(by: [.floatingWindow]))
        #expect(!stdSpec.isSatisfied(by: []))

        let hudSpec = PluginCustomWindowSpec(
            pluginID: "demo-win", windowID: "hud", htmlPath: "ui/widget.html",
            chrome: .frameless, transparent: true, pinOnTop: true
        )
        #expect(hudSpec.requiresFloatingCapability)
        #expect(!hudSpec.showInDock)
        #expect(hudSpec.withShowInDock(true).showInDock)
        #expect(hudSpec.requiredCapability == .floatingWindow)
        #expect(!hudSpec.isSatisfied(by: [.window]))
        #expect(hudSpec.isSatisfied(by: [.floatingWindow]))

        let explicitDockFloat = PluginCustomWindowSpec(
            pluginID: "demo-win", windowID: "hud2", htmlPath: "ui/widget.html",
            chrome: .frameless, transparent: true, pinOnTop: true, showInDock: true
        )
        #expect(explicitDockFloat.showInDock)
        let savedFrame = PluginSavedWindowFrame(x: 100, y: 120, width: 320, height: 220, opacity: 0.9, pinOnTop: true)
        #expect(explicitDockFloat.applyingSavedFrame(savedFrame, canRestoreFloatingPin: true).showInDock)

        let deepURL = try #require(URL(string: "lucent://window/demo-hud/hud?html=ui/widget.html&chrome=frameless&transparent=1&pin=1&showInDock=1&w=392&h=488&opacity=0.92"))
        guard case .pluginCustomWindow(let parsed) = PluginDeepLinkParser.parse(deepURL) else {
            Issue.record("Expected .pluginCustomWindow deep link target")
            return
        }
        #expect(parsed.pluginID == "demo-hud")
        #expect(parsed.windowID == "hud")
        #expect(parsed.htmlPath == "ui/widget.html")
        #expect(parsed.chrome == .frameless && parsed.transparent && parsed.pinOnTop && parsed.showInDock)
        #expect(parsed.width == 392 && parsed.height == 488)
        #expect(abs(parsed.opacity - 0.92) < 0.001)

        let badTraversalURL = try #require(URL(string: "lucent://window/demo-hud?html=../escape.html"))
        #expect(PluginDeepLinkParser.parse(badTraversalURL) == nil)
    }

    @Test("PluginHostTCCBroker and PluginPermissionAudit map plugin capabilities to host-brokered macOS TCC")
    func hostTCCBrokerAndPermissionAuditMapping() throws {
        let dir = try makeIsolatedDir("audit")
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(PluginHostTCCBroker.requiredTCC(for: .selection) == .accessibility)
        #expect(PluginHostTCCBroker.requiredTCC(for: .screenCapture) == .screenRecording)
        #expect(PluginHostTCCBroker.requiredTCC(for: .notifications) == .notifications)
        #expect(PluginHostTCCBroker.requiredTCC(for: .window) == nil)
        #expect(PluginHostTCCBroker.requiredTCC(for: .floatingWindow) == nil)

        let allSnapshots = PluginHostTCCBroker.allTCCSnapshot()
        #expect(allSnapshots.count == PluginSystemTCCKind.allCases.count)
        for snap in allSnapshots {
            let settingsURL = snap["settingsURL"] as? String ?? ""
            #expect(settingsURL.hasPrefix("x-apple.systempreferences:"))
        }

        let plug = try PluginSystem.scaffoldPlugin(
            id: "vis-agent",
            name: "Vision Agent",
            keywords: ["vis"],
            description: "Screen + HUD test",
            mode: .view,
            capabilities: [.floatingWindow, .screenCapture, .notifications, .selection],
            resourceScopes: [],
            in: dir
        )
        #expect(plug.isValid)
        let perms = Set(PluginPermissionAudit.declaredPermissions(for: plug))
        #expect(perms.contains(.floatingWindow))
        #expect(perms.contains(.screenCapture))
        #expect(perms.contains(.screenRecording))
        #expect(perms.contains(.notifications))
        #expect(perms.contains(.systemNotifications))
        #expect(perms.contains(.selection))
        #expect(perms.contains(.accessibility))
    }

    @Test("PluginHostBridgeHandlers enforces window vs floatingWindow escalation rules and dispatches pasteBack, writeImage & notifications")
    func hostBridgeCustomWindowPasteBackAndMediaDispatch() throws {
        let dir = try makeIsolatedDir("bridge")
        defer { try? FileManager.default.removeItem(at: dir) }

        let uiDir = dir.appendingPathComponent("ui", isDirectory: true)
        try FileManager.default.createDirectory(at: uiDir, withIntermediateDirectories: true)
        try "<h1>HUD</h1>".write(to: uiDir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)

        let box = LockedBridgeCaptureBox()
        let ctx = PluginBridgeHostContext(
            pluginID: "win-plug",
            pluginName: "Win Plug",
            pluginDirectoryURL: dir,
            pasteBackHandler: { text in
                box.lastPastedText = text
                return PluginPasteBackOutcome(
                    writtenToClipboard: true, pastedToActiveApp: true,
                    accessibilityGranted: true, message: "ok"
                )
            },
            customWindowOpener: { spec in
                box.openedSpecs.append(spec)
                return true
            },
            customWindowCloser: { pid, wid in
                box.closedWindows.append("\(pid):\(wid)")
                return true
            }
        )

        // 1. Escalation blocked: `.window` capability cannot open frameless/pinned floating HUD
        let blocked = PluginHostBridgeHandlers.dispatch(
            capability: .window,
            action: "open",
            params: ["htmlPath": "ui/index.html", "chrome": "frameless", "pinOnTop": true],
            hostContext: ctx
        )
        #expect((blocked["ok"] as? Bool) == false)
        #expect((blocked["error"] as? String) == "capability_escalation_blocked")
        #expect(box.openedSpecs.isEmpty)

        // 2. Standard window succeeds under `.window`
        let stdOK = PluginHostBridgeHandlers.dispatch(
            capability: .window,
            action: "open",
            params: ["htmlPath": "ui/index.html", "width": 600, "height": 420],
            hostContext: ctx
        )
        #expect((stdOK["ok"] as? Bool) == true)
        #expect(box.openedSpecs.count == 1)
        #expect(box.openedSpecs.first?.chrome == .standard)
        #expect(box.openedSpecs.first?.showInDock == true)

        // 3. Frameless transparent HUD succeeds under `.floatingWindow` (defaults to showInDock = false)
        let floatOK = PluginHostBridgeHandlers.dispatch(
            capability: .floatingWindow,
            action: "open",
            params: ["windowID": "hud", "htmlPath": "ui/index.html", "chrome": "frameless", "transparent": true],
            hostContext: ctx
        )
        #expect((floatOK["ok"] as? Bool) == true)
        #expect(box.openedSpecs.last?.pinOnTop == true)
        #expect(box.openedSpecs.last?.transparent == true)
        #expect(box.openedSpecs.last?.showInDock == false)

        // 3b. Floating HUD may explicitly opt into Dock visibility
        let floatDockOK = PluginHostBridgeHandlers.dispatch(
            capability: .floatingWindow,
            action: "open",
            params: ["windowID": "hud-dock", "htmlPath": "ui/index.html", "chrome": "frameless", "showInDock": true],
            hostContext: ctx
        )
        #expect((floatDockOK["ok"] as? Bool) == true)
        #expect(box.openedSpecs.last?.showInDock == true)

        let closeOK = PluginHostBridgeHandlers.dispatch(
            capability: .floatingWindow, action: "close", params: ["windowID": "hud"], hostContext: ctx
        )
        #expect((closeOK["ok"] as? Bool) == true)
        #expect(box.closedWindows == ["win-plug:hud"])

        // 4. `selection.pasteBack`
        let pasteRes = PluginHostBridgeHandlers.dispatch(
            capability: .selection, action: "pasteBack", params: ["text": "Hello back!"], hostContext: ctx
        )
        #expect((pasteRes["ok"] as? Bool) == true)
        #expect(box.lastPastedText == "Hello back!")

        // 5. `notifications.send` & `screenCapture.status`
        let noteRes = PluginHostBridgeHandlers.dispatch(
            capability: .notifications,
            action: "send",
            params: ["title": "Bridge Test", "body": "Delivered via Host Broker", "sound": false],
            hostContext: ctx
        )
        #expect((noteRes["ok"] as? Bool) == true)

        let capStatus = PluginHostBridgeHandlers.dispatch(
            capability: .screenCapture, action: "status", params: [:], hostContext: ctx
        )
        #expect((capStatus["ok"] as? Bool) == true)

        // 6. `clipboard.writeImage` validation on tiny generated PNG
        let img = NSImage(size: NSSize(width: 8, height: 8))
        img.lockFocus()
        NSColor.systemTeal.setFill()
        NSBezierPath.fill(NSRect(x: 0, y: 0, width: 8, height: 8))
        img.unlockFocus()
        let imgURL = dir.appendingPathComponent("dot.png")
        let tiff = try #require(img.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: tiff))
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: imgURL)

        let imgWrite = PluginHostBridgeHandlers.dispatch(
            capability: .clipboard, action: "writeImage", params: ["imagePath": imgURL.path], hostContext: ctx
        )
        #expect((imgWrite["ok"] as? Bool) == true)
    }
}

private final class LockedBridgeCaptureBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _opened: [PluginCustomWindowSpec] = []
    private var _closed: [String] = []
    private var _pasted: String?

    var openedSpecs: [PluginCustomWindowSpec] {
        get { lock.withLock { _opened } }
        set { lock.withLock { _opened = newValue } }
    }
    var closedWindows: [String] {
        get { lock.withLock { _closed } }
        set { lock.withLock { _closed = newValue } }
    }
    var lastPastedText: String? {
        get { lock.withLock { _pasted } }
        set { lock.withLock { _pasted = newValue } }
    }
}

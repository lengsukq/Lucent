import LucentFoundation
import LucentMedia
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct PluginCapturedScreenFile: Sendable, Hashable, Equatable {
    public let cancelled: Bool
    public let imagePath: String?
    public let width: Int
    public let height: Int

    public init(cancelled: Bool, imagePath: String? = nil, width: Int = 0, height: Int = 0) {
        self.cancelled = cancelled; self.imagePath = imagePath
        self.width = width; self.height = height
    }
}

public struct PluginPasteBackOutcome: Sendable, Hashable, Equatable {
    public let writtenToClipboard: Bool
    public let pastedToActiveApp: Bool
    public let accessibilityGranted: Bool
    public let message: String

    public init(writtenToClipboard: Bool, pastedToActiveApp: Bool, accessibilityGranted: Bool, message: String) {
        self.writtenToClipboard = writtenToClipboard; self.pastedToActiveApp = pastedToActiveApp
        self.accessibilityGranted = accessibilityGranted; self.message = message
    }
}

enum PluginScreenAndWindowBridge {
    static func writeImageToPasteboard(imagePath: String) -> [String: Any] {
        let url = URL(fileURLWithPath: imagePath).standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return PluginHostBridgeHandlers.errorJSON("invalid_params", "图片文件不存在：\(imagePath)", capability: .clipboard)
        }
        guard let image = NSImage(contentsOf: url),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return PluginHostBridgeHandlers.errorJSON("decode_failed", "无法解码图片文件：\(imagePath)", capability: .clipboard)
        }
        let wrote = runOnMain {
            let pb = NSPasteboard.general; pb.clearContents()
            let item = NSPasteboardItem()
            item.setData(pngData, forType: .png); item.setData(tiff, forType: .tiff)
            return pb.writeObjects([item])
        }
        return PluginHostBridgeHandlers.okJSON(.clipboard, "writeImage", [
            "written": wrote, "width": bitmap.pixelsWide, "height": bitmap.pixelsHigh, "bytes": pngData.count
        ])
    }

    static func handlePasteBack(params: [String: Any], hostContext: PluginBridgeHostContext) -> [String: Any] {
        guard let text = params["text"] as? String, !text.isEmpty else {
            return PluginHostBridgeHandlers.errorJSON("invalid_params", "缺少非空 text 参数", capability: .selection)
        }
        if let handler = hostContext.pasteBackHandler {
            let outcome = handler(text)
            return PluginHostBridgeHandlers.okJSON(.selection, "pasteBack", [
                "writtenToClipboard": outcome.writtenToClipboard,
                "pastedToActiveApp": outcome.pastedToActiveApp,
                "accessibilityGranted": outcome.accessibilityGranted,
                "settingsURL": PluginSystemTCCKind.accessibility.systemSettingsURLString,
                "message": outcome.message
            ])
        }
        let wrote = hostContext.clipboardWriter(text)
        let axGranted = PluginHostTCCBroker.requestAccessOnBehalfOfPlugin(.accessibility).isGranted
        return PluginHostBridgeHandlers.okJSON(.selection, "pasteBack", [
            "writtenToClipboard": wrote, "pastedToActiveApp": false, "accessibilityGranted": axGranted,
            "settingsURL": PluginSystemTCCKind.accessibility.systemSettingsURLString,
            "message": L10n.pick("已写入剪贴板（请按 ⌘V 粘贴）", "Copied to clipboard (press ⌘V to paste)")
        ])
    }

    static func handleScreenCapture(
        action: String, params: [String: Any], hostContext: PluginBridgeHostContext
    ) -> [String: Any] {
        switch action {
        case "status":
            return PluginHostBridgeHandlers.okJSON(.screenCapture, action, PluginHostTCCBroker.statusPayload(for: .screenRecording))
        case "requestPermission":
            let st = PluginHostTCCBroker.requestAccessOnBehalfOfPlugin(.screenRecording)
            return PluginHostBridgeHandlers.okJSON(.screenCapture, action, [
                "granted": st.isGranted, "status": st.rawValue,
                "settingsURL": PluginSystemTCCKind.screenRecording.systemSettingsURLString
            ])
        case "sampleColor":
            guard PluginHostTCCBroker.requestAccessOnBehalfOfPlugin(.screenRecording).isGranted else {
                return tccDeniedError(for: .screenCapture, label: L10n.pick("屏幕录制", "Screen Recording"))
            }
            let mousePt = runOnMain { NSEvent.mouseLocation }
            let targetX = (params["x"] as? NSNumber)?.doubleValue ?? Double(mousePt.x)
            let targetY = (params["y"] as? NSNumber)?.doubleValue ?? Double(mousePt.y)
            guard let mainImg = CGDisplayCreateImage(CGMainDisplayID()) else {
                return PluginHostBridgeHandlers.errorJSON("capture_failed", "无法采样主显示器图像", capability: .screenCapture)
            }
            let bounds = CGDisplayBounds(CGMainDisplayID()), pt = CGPoint(x: targetX, y: targetY)
            return PluginHostBridgeHandlers.okJSON(.screenCapture, action, [
                "hex": ScreenshotCompositor.samplePixelColor(in: mainImg, point: pt, screenBounds: bounds),
                "rgb": ScreenshotCompositor.samplePixelRGBString(in: mainImg, point: pt, screenBounds: bounds),
                "x": Int(round(targetX)), "y": Int(round(targetY))
            ])
        case "captureMainDisplay":
            guard PluginHostTCCBroker.requestAccessOnBehalfOfPlugin(.screenRecording).isGranted else {
                return tccDeniedError(for: .screenCapture, label: L10n.pick("屏幕录制", "Screen Recording"))
            }
            guard let mainImg = CGDisplayCreateImage(CGMainDisplayID()),
                  let savedURL = try? writeTempCapturePNG(mainImg, pluginID: hostContext.pluginID ?? "plugin") else {
                return PluginHostBridgeHandlers.errorJSON("capture_failed", "主屏快照采集失败", capability: .screenCapture)
            }
            return PluginHostBridgeHandlers.okJSON(.screenCapture, action, [
                "cancelled": false, "imagePath": savedURL.path, "width": mainImg.width, "height": mainImg.height
            ])
        case "captureInteractive":
            guard let captureFn = hostContext.interactiveCaptureHandler else {
                return PluginHostBridgeHandlers.errorJSON("unsupported_context", "当前运行环境不支持交互式选区截图", capability: .screenCapture)
            }
            do {
                let res = try captureFn()
                var payload: [String: Any] = ["cancelled": res.cancelled, "width": res.width, "height": res.height]
                if let p = res.imagePath { payload["imagePath"] = p }
                return PluginHostBridgeHandlers.okJSON(.screenCapture, action, payload)
            } catch {
                return PluginHostBridgeHandlers.errorJSON("capture_failed", error.localizedDescription, capability: .screenCapture)
            }
        default:
            return PluginHostBridgeHandlers.errorJSON(
                "invalid_action", "screenCapture 支持 status / requestPermission / sampleColor / captureMainDisplay / captureInteractive",
                capability: .screenCapture
            )
        }
    }

    static func handleNotifications(
        action: String, params: [String: Any], hostContext: PluginBridgeHostContext
    ) -> [String: Any] {
        switch action {
        case "status":
            return PluginHostBridgeHandlers.okJSON(.notifications, action, PluginHostTCCBroker.statusPayload(for: .notifications))
        case "requestPermission":
            let st = PluginHostTCCBroker.requestAccessOnBehalfOfPlugin(.notifications)
            return PluginHostBridgeHandlers.okJSON(.notifications, action, [
                "granted": st.isGranted, "status": st.rawValue,
                "settingsURL": PluginSystemTCCKind.notifications.systemSettingsURLString
            ])
        case "send":
            let payload = PluginNotificationPayload(
                title: (params["title"] as? String) ?? "",
                subtitle: params["subtitle"] as? String,
                body: (params["body"] as? String) ?? "",
                sound: params["sound"] as? Bool
            )
            guard let rec = PluginNotificationService.shared.post(
                payload, pluginID: hostContext.pluginID ?? "external-plugin", pluginName: hostContext.pluginName ?? "Plugin"
            ) else {
                return PluginHostBridgeHandlers.errorJSON("invalid_params", "通知 title 与 body 不能同时为空", capability: .notifications)
            }
            return PluginHostBridgeHandlers.okJSON(.notifications, action, [
                "id": rec.id, "deliveredToSystemCenter": rec.deliveredToSystemCenter, "title": rec.payload.title
            ])
        default:
            return PluginHostBridgeHandlers.errorJSON("invalid_action", "notifications 支持 status / requestPermission / send", capability: .notifications)
        }
    }

    static func handleCustomWindow(
        capability: PluginCapability, action: String, params: [String: Any], hostContext: PluginBridgeHostContext
    ) -> [String: Any] {
        guard let pluginID = hostContext.pluginID, PluginSystem.isSafePluginID(pluginID) else {
            return PluginHostBridgeHandlers.errorJSON("missing_plugin_context", "缺少有效插件上下文", capability: capability)
        }
        switch action {
        case "open":
            var spec = PluginCustomWindowSpec.fromBridgeParams(
                pluginID: pluginID, params: params, defaults: hostContext.manifestWindowDefaults
            )
            if capability == .window && spec.requiresFloatingCapability {
                return PluginHostBridgeHandlers.errorJSON(
                    "capability_escalation_blocked", "无边框/透明/置顶/穿透浮窗需声明并授权 'floatingWindow'", capability: capability
                )
            }
            if let rel = spec.htmlPath {
                guard let dir = hostContext.pluginDirectoryURL,
                      PluginCustomWindowSpec.resolveSafeHTMLFileURL(relativePath: rel, bundleDirectory: dir) != nil else {
                    return PluginHostBridgeHandlers.errorJSON("invalid_html_path", "窗口 HTML 路径不存在或越界：\(rel)", capability: capability)
                }
            } else if (spec.html ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return PluginHostBridgeHandlers.errorJSON("missing_html", "请提供 htmlPath 或内联 html 内容", capability: capability)
            }
            if capability == .floatingWindow && !params.keys.contains("pinOnTop") {
                spec = PluginCustomWindowSpec(
                    pluginID: spec.pluginID, windowID: spec.windowID, title: spec.title,
                    htmlPath: spec.htmlPath, html: spec.html, width: spec.width, height: spec.height,
                    minWidth: spec.minWidth, minHeight: spec.minHeight, resizable: spec.resizable,
                    chrome: spec.chrome, transparent: spec.transparent, pinOnTop: true,
                    clickThrough: spec.clickThrough, showInDock: spec.showInDock, opacity: spec.opacity, x: spec.x, y: spec.y,
                    initialStateJSON: spec.initialStateJSON
                )
            }
            let opened = hostContext.customWindowOpener?(spec) ?? false
            return PluginHostBridgeHandlers.okJSON(capability, action, [
                "opened": opened, "pluginID": spec.pluginID, "windowID": spec.windowID,
                "chrome": spec.chrome.rawValue, "pinOnTop": spec.pinOnTop, "showInDock": spec.showInDock
            ])
        case "close":
            let winID = PluginCustomWindowSpec.sanitizeWindowID((params["windowID"] as? String) ?? "main")
            return PluginHostBridgeHandlers.okJSON(capability, action, [
                "closed": hostContext.customWindowCloser?(pluginID, winID) ?? false, "windowID": winID
            ])
        default:
            return PluginHostBridgeHandlers.errorJSON("invalid_action", "\(capability.rawValue) 仅支持 open / close", capability: capability)
        }
    }

    static func writeTempCapturePNG(_ cgImage: CGImage, pluginID: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lucent-plugin-captures", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fileURL = dir.appendingPathComponent("\(pluginID)-\(UUID().uuidString.prefix(8)).png")
        guard let dest = CGImageDestinationCreateWithURL(fileURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw LucentError.visionFailed("无法创建临时截图文件")
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { throw LucentError.visionFailed("写入临时截图 PNG 失败") }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        return fileURL
    }

    private static func tccDeniedError(for cap: PluginCapability, label: String) -> [String: Any] {
        PluginHostBridgeHandlers.errorJSON(
            "tcc_not_granted", L10n.pick("宿主尚未获得 macOS「\(label)」权限，请在系统设置中放行 Lucent", "\(label) TCC not yet granted to Lucent"),
            capability: cap
        )
    }

    private static func runOnMain<T: Sendable>(_ work: @MainActor @Sendable () -> T) -> T {
        if Thread.isMainThread { return MainActor.assumeIsolated(work) }
        return DispatchQueue.main.sync { MainActor.assumeIsolated(work) }
    }
}

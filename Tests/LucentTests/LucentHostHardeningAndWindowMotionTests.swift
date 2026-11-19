import CoreGraphics
import Darwin
import Foundation
import Testing
@testable import LucentCore
@testable import LucentFoundation

@Suite("Host Bridge Hardening & Native Floating Window Motion Geometry")
struct LucentHostHardeningAndWindowMotionTests {
    private func makeIsolatedDir(_ label: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lk-hardening-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func sendUDSLineAndCloseEarly(socketPath: String, payload: String, readReply: Bool) -> String? {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { Darwin.close(fd) }
        var noSigPipe: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(socketPath.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            buf.copyBytes(from: bytes.map(UInt8.init(bitPattern:)))
        }
        let connected = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return nil }
        let data = Data((payload + "\n").utf8)
        data.withUnsafeBytes { ptr in
            if let base = ptr.baseAddress {
                _ = Darwin.write(fd, base, data.count)
            }
        }
        guard readReply else { return nil }
        var buf = [UInt8](repeating: 0, count: 2048)
        let n = Darwin.read(fd, &buf, buf.count)
        guard n > 0 else { return nil }
        return String(decoding: buf.prefix(n), as: UTF8.self)
    }

    @Test("PluginHostBridgeServer survives rapid client disconnect (SIGPIPE) and immediate teardown without deinit crash")
    func bridgeServerHandlesAbruptDisconnectAndImmediateDeinit() throws {
        let dir = try makeIsolatedDir("bridge-stress")
        defer { try? FileManager.default.removeItem(at: dir) }

        let plug = try PluginSystem.scaffoldPlugin(
            id: "bridge-stress-plug",
            name: "Bridge Stress",
            keywords: ["bs"],
            description: "Bridge hardening test",
            mode: .view,
            capabilities: [.clipboard],
            resourceScopes: [],
            in: dir
        )

        let hostCtx = PluginBridgeHostContext(
            clipboardReader: {
                usleep(8_000)
                return "hardened-ok"
            }
        )

        for round in 0..<24 {
            var server: PluginHostBridgeServer? = try PluginHostBridgeServer(
                descriptor: plug,
                grantedCapabilities: [.clipboard],
                hostContext: hostCtx
            )
            let sockPath = try #require(server?.socketPath)
            let token = try #require(server?.token)
            let req = "{\"token\":\"\(token)\",\"capability\":\"clipboard\",\"action\":\"read\",\"params\":{}}"

            if round % 3 == 0 {
                let reply = sendUDSLineAndCloseEarly(socketPath: sockPath, payload: req, readReply: true)
                #expect(reply?.contains("hardened-ok") == true)
            } else {
                // Close peer immediately before host writes response, then drop server immediately.
                _ = sendUDSLineAndCloseEarly(socketPath: sockPath, payload: req, readReply: false)
                _ = sendUDSLineAndCloseEarly(socketPath: sockPath, payload: req, readReply: false)
            }
            server?.stop()
            server = nil
            #expect(!FileManager.default.fileExists(atPath: sockPath))
        }
    }

    @Test("PluginDataPaths.cleanupStaleTmpDirectories sweeps orphaned .tmp-* dirs without touching user data")
    func staleTmpDirectoryCleanup() throws {
        let root = try makeIsolatedDir("tmp-sweep")
        defer { try? FileManager.default.removeItem(at: root) }
        let pluginsRoot = root.appendingPathComponent("Plugins", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginsRoot, withIntermediateDirectories: true)

        let dataDir = try #require(PluginDataPaths.ensureDataDirectory(for: "gold-test", pluginsRoot: pluginsRoot))
        let keepFile = dataDir.appendingPathComponent("window-frames.json")
        try "{}".write(to: keepFile, atomically: true, encoding: .utf8)

        let staleTmp = dataDir.appendingPathComponent(".tmp-STALE123", isDirectory: true)
        try FileManager.default.createDirectory(at: staleTmp, withIntermediateDirectories: true)
        let pastDate = Date().addingTimeInterval(-600)
        try FileManager.default.setAttributes([.modificationDate: pastDate], ofItemAtPath: staleTmp.path)

        let freshTmp = dataDir.appendingPathComponent(".tmp-FRESH456", isDirectory: true)
        try FileManager.default.createDirectory(at: freshTmp, withIntermediateDirectories: true)

        PluginDataPaths.cleanupStaleTmpDirectories(in: pluginsRoot, olderThanSeconds: 300)

        #expect(!FileManager.default.fileExists(atPath: staleTmp.path))
        #expect(FileManager.default.fileExists(atPath: freshTmp.path))
        #expect(FileManager.default.fileExists(atPath: keepFile.path))
    }

    @Test("PluginWindowGeometry sanitizes non-finite inputs, prevents off-screen loss, and computes multi-screen snap & anchor math")
    func windowGeometrySanitizationAndMotionMath() {
        #expect(PluginWindowGeometry.finiteDouble(.nan, fallback: 42) == 42)
        #expect(PluginWindowGeometry.finiteDouble(.infinity, fallback: 42) == 42)
        #expect(PluginWindowGeometry.finiteDouble(128.5, fallback: 42) == 128.5)
        #expect(PluginWindowGeometry.clampDurationMs(.nan) == PluginWindowGeometry.defaultDurationMs)
        #expect(PluginWindowGeometry.clampDurationMs(9999) == PluginWindowGeometry.maxDurationMs)
        #expect(PluginWindowGeometry.clampDurationMs(-20) == 0)

        let stdCompact = PluginWindowGeometry.clampSize(width: 80, height: 40, allowCompactFloating: false)
        #expect(stdCompact == CGSize(width: 180, height: 96))
        let floatPill = PluginWindowGeometry.clampSize(width: 80, height: 40, allowCompactFloating: true)
        #expect(floatPill == CGSize(width: 80, height: 40))
        let floatNan = PluginWindowGeometry.clampSize(width: .nan, height: .infinity, allowCompactFloating: true)
        #expect(floatNan == CGSize(width: 64, height: 36))

        let mainScreen = PluginWindowScreenRect(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944),
            displayID: 1, isMain: true
        )
        let rightScreen = PluginWindowScreenRect(
            frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 1512, y: 0, width: 1920, height: 1055),
            displayID: 2, isMain: false
        )

        let picked = PluginWindowGeometry.bestScreen(
            for: CGRect(x: 1700, y: 400, width: 320, height: 220),
            screens: [mainScreen, rightScreen]
        )
        #expect(picked.displayID == 2)

        // Window pushed wildly off-screen must be recovered fully into visible bounds
        let lostRect = CGRect(x: -9999, y: 9999, width: 352, height: 240)
        let safeRect = PluginWindowGeometry.clampFrameToVisible(lostRect, visibleFrame: mainScreen.visibleFrame, margin: 8)
        #expect(safeRect.minX == 8)
        #expect(safeRect.maxY == mainScreen.visibleFrame.maxY - 8)

        // Free drag clamping never lets a window vanish off the left or right edge
        let draggedOffLeft = PluginWindowGeometry.clampDragOrigin(
            CGPoint(x: -500, y: 400), size: CGSize(width: 220, height: 120),
            visibleFrame: mainScreen.visibleFrame, keepFullyOnScreen: true
        )
        #expect(draggedOffLeft.x == 0)

        let partialDrag = PluginWindowGeometry.clampDragOrigin(
            CGPoint(x: -500, y: 400), size: CGSize(width: 220, height: 120),
            visibleFrame: mainScreen.visibleFrame, keepFullyOnScreen: false
        )
        #expect(partialDrag.x + 220 >= PluginWindowGeometry.minVisibleDragInset)

        // Anchored morph keeps top-right corner pinned when shrinking
        let expanded = CGRect(x: 1100, y: 600, width: 352, height: 240)
        let morphed = PluginWindowGeometry.anchoredFrame(
            current: expanded, targetSize: CGSize(width: 88, height: 140), anchor: .topRight
        )
        #expect(morphed.maxX == expanded.maxX)
        #expect(morphed.maxY == expanded.maxY)

        // Edge snap for left, right, and top
        let snapLeft = PluginWindowGeometry.snappedFrame(
            current: expanded, targetSize: CGSize(width: 88, height: 140),
            edge: .left, margin: 8, visibleFrame: mainScreen.visibleFrame
        )
        #expect(snapLeft.minX == 8)

        let snapRight = PluginWindowGeometry.snappedFrame(
            current: expanded, targetSize: CGSize(width: 88, height: 140),
            edge: .right, margin: 8, visibleFrame: mainScreen.visibleFrame
        )
        #expect(snapRight.maxX == mainScreen.visibleFrame.maxX - 8)

        let snapTop = PluginWindowGeometry.snappedFrame(
            current: expanded, targetSize: CGSize(width: 220, height: 48),
            edge: .top, margin: 6, visibleFrame: mainScreen.visibleFrame
        )
        #expect(snapTop.maxY == mainScreen.visibleFrame.maxY - 6)

        // Edge metrics & proximity payload
        let metrics = PluginWindowGeometry.computeEdgeMetrics(frame: snapRight, visibleFrame: mainScreen.visibleFrame)
        #expect(metrics.nearestEdge == .right)
        #expect(metrics.distRight == 8)
        #expect(metrics.edgeWithin(threshold: 28) == .right)
        #expect(!metrics.outOfBounds)

        let payload = PluginWindowGeometry.framePayload(frame: snapTop, screen: mainScreen, edgeThreshold: 28)
        let edges = payload["edges"] as? [String: Any]
        #expect((edges?["nearEdge"] as? String) == "top")
        #expect((payload["width"] as? Int) == 220)
        #expect((payload["height"] as? Int) == 48)
    }
}

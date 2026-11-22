import CoreGraphics
import Foundation
import LucentFoundation

public struct SystemDisplayRect: Codable, Equatable, Hashable, Sendable {
    public let displayID: UInt32
    public let name: String
    public let isMain: Bool
    public let index: Int
    /// Full display frame in Quartz global coordinates (origin top-left of primary display).
    public let frame: CGRect
    /// Usable work area excluding menu bar and Dock, in Quartz global coordinates.
    public let visibleFrame: CGRect

    public init(
        displayID: UInt32,
        name: String,
        isMain: Bool,
        index: Int,
        frame: CGRect,
        visibleFrame: CGRect
    ) {
        self.displayID = displayID
        self.name = name
        self.isMain = isMain
        self.index = index
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}

public struct ManagedWindowInfo: Codable, Equatable, Hashable, Sendable {
    public let pid: Int32
    public let bundleID: String
    public let appName: String
    public let title: String
    public let windowIndex: Int
    public let frame: CGRect
    public let displayID: UInt32
    public let displayIndex: Int
    public let isFocused: Bool
    public let isMinimized: Bool
    public let isResizable: Bool

    public init(
        pid: Int32,
        bundleID: String,
        appName: String,
        title: String,
        windowIndex: Int,
        frame: CGRect,
        displayID: UInt32,
        displayIndex: Int,
        isFocused: Bool,
        isMinimized: Bool,
        isResizable: Bool
    ) {
        self.pid = pid
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.windowIndex = windowIndex
        self.frame = frame
        self.displayID = displayID
        self.displayIndex = displayIndex
        self.isFocused = isFocused
        self.isMinimized = isMinimized
        self.isResizable = isResizable
    }

    public var stableUndoKey: String {
        "\(pid):\(windowIndex)"
    }
}

public enum WindowSnapPreset: String, Codable, CaseIterable, Sendable, Hashable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case leftThird, centerThird, rightThird, leftTwoThirds, rightTwoThirds
    case topLeft, topRight, bottomLeft, bottomRight
    case maximize, center, almostMax
    case nextDisplay, prevDisplay
    case restore

    public var localizedTitle: String {
        switch self {
        case .leftHalf: L10n.pick("左半屏", "Left Half")
        case .rightHalf: L10n.pick("右半屏", "Right Half")
        case .topHalf: L10n.pick("上半屏", "Top Half")
        case .bottomHalf: L10n.pick("下半屏", "Bottom Half")
        case .leftThird: L10n.pick("左三分之一", "Left Third")
        case .centerThird: L10n.pick("中三分之一", "Center Third")
        case .rightThird: L10n.pick("右三分之一", "Right Third")
        case .leftTwoThirds: L10n.pick("左三分之二", "Left Two Thirds")
        case .rightTwoThirds: L10n.pick("右三分之二", "Right Two Thirds")
        case .topLeft: L10n.pick("左上四分屏", "Top Left")
        case .topRight: L10n.pick("右上四分屏", "Top Right")
        case .bottomLeft: L10n.pick("左下四分屏", "Bottom Left")
        case .bottomRight: L10n.pick("右下四分屏", "Bottom Right")
        case .maximize: L10n.pick("最大化铺满", "Maximize")
        case .center: L10n.pick("居中窗口", "Center")
        case .almostMax: L10n.pick("几乎满屏", "Almost Maximize")
        case .nextDisplay: L10n.pick("移到下一屏", "Next Display")
        case .prevDisplay: L10n.pick("移到上一屏", "Previous Display")
        case .restore: L10n.pick("撤销上次分屏", "Restore Window")
        }
    }

    public var symbolName: String {
        switch self {
        case .leftHalf, .leftThird, .leftTwoThirds: "rectangle.lefthalf.filled"
        case .rightHalf, .rightThird, .rightTwoThirds: "rectangle.righthalf.filled"
        case .topHalf: "rectangle.tophalf.filled"
        case .bottomHalf: "rectangle.bottomhalf.filled"
        case .centerThird, .center: "rectangle.center.inset.filled"
        case .topLeft, .topRight, .bottomLeft, .bottomRight: "rectangle.split.2x2"
        case .maximize, .almostMax: "arrow.up.left.and.arrow.down.right"
        case .nextDisplay, .prevDisplay: "display.2"
        case .restore: "arrow.uturn.backward.circle.fill"
        }
    }
}

public struct NormalizedWindowRect: Codable, Equatable, Hashable, Sendable {
    public let rx: Double
    public let ry: Double
    public let rw: Double
    public let rh: Double

    public init(rx: Double, ry: Double, rw: Double, rh: Double) {
        self.rx = rx
        self.ry = ry
        self.rw = rw
        self.rh = rh
    }
}

public struct WindowWorkspaceSlot: Codable, Equatable, Hashable, Sendable {
    public let bundleID: String
    public let appName: String
    public let windowTitle: String?
    public let windowIndex: Int
    public let displayIndex: Int
    public let displayID: UInt32?
    public let rx: Double
    public let ry: Double
    public let rw: Double
    public let rh: Double

    public init(
        bundleID: String,
        appName: String,
        windowTitle: String? = nil,
        windowIndex: Int = 0,
        displayIndex: Int = 0,
        displayID: UInt32? = nil,
        rx: Double,
        ry: Double,
        rw: Double,
        rh: Double
    ) {
        self.bundleID = bundleID
        self.appName = appName
        self.windowTitle = windowTitle
        self.windowIndex = max(0, windowIndex)
        self.displayIndex = max(0, displayIndex)
        self.displayID = displayID
        self.rx = rx
        self.ry = ry
        self.rw = rw
        self.rh = rh
    }
}

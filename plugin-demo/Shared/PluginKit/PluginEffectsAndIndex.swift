import Foundation

public struct NotificationSpec: Codable, Sendable, Equatable {
    public var title: String
    public var subtitle: String?
    public var body: String
    public var sound: Bool?

    public init(title: String, subtitle: String? = nil, body: String, sound: Bool? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.sound = sound
    }
}

public struct WindowLaunchSpec: Codable, Sendable, Equatable {
    public var windowID: String?
    public var title: String?
    public var htmlPath: String?
    public var html: String?
    public var width: Int?
    public var height: Int?
    public var minWidth: Int?
    public var minHeight: Int?
    public var resizable: Bool?
    public var chrome: String?
    public var transparent: Bool?
    public var pinOnTop: Bool?
    public var clickThrough: Bool?
    public var showInDock: Bool?
    public var opacity: Double?
    public var x: Int?
    public var y: Int?
    public var initialStateJSON: String?

    public init(
        windowID: String? = nil,
        title: String? = nil,
        htmlPath: String? = nil,
        html: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        minWidth: Int? = nil,
        minHeight: Int? = nil,
        resizable: Bool? = nil,
        chrome: String? = nil,
        transparent: Bool? = nil,
        pinOnTop: Bool? = nil,
        clickThrough: Bool? = nil,
        showInDock: Bool? = nil,
        opacity: Double? = nil,
        x: Int? = nil,
        y: Int? = nil,
        initialStateJSON: String? = nil
    ) {
        self.windowID = windowID
        self.title = title
        self.htmlPath = htmlPath
        self.html = html
        self.width = width
        self.height = height
        self.minWidth = minWidth
        self.minHeight = minHeight
        self.resizable = resizable
        self.chrome = chrome
        self.transparent = transparent
        self.pinOnTop = pinOnTop
        self.clickThrough = clickThrough
        self.showInDock = showInDock
        self.opacity = opacity
        self.x = x
        self.y = y
        self.initialStateJSON = initialStateJSON
    }
}

public struct PostActionEffect: Codable, Sendable, Equatable {
    public var toast: String?
    public var closeOverlay: Bool?
    public var reloadSearchIndex: Bool?
    public var statusSummary: String?
    public var statusBadge: String?
    public var openReaderPath: String?
    public var openImagePath: String?
    public var pinImagePath: String?
    public var openFloatingPanel: Bool?
    public var floatingPanelPinOnTop: Bool?
    public var floatingPanelIntervalSeconds: Int?
    public var floatingPanelArgs: [String]?
    public var openWindow: WindowLaunchSpec?
    public var pasteText: String?
    public var notification: NotificationSpec?

    public init(
        toast: String? = nil,
        closeOverlay: Bool? = nil,
        reloadSearchIndex: Bool? = nil,
        statusSummary: String? = nil,
        statusBadge: String? = nil,
        openReaderPath: String? = nil,
        openImagePath: String? = nil,
        pinImagePath: String? = nil,
        openFloatingPanel: Bool? = nil,
        floatingPanelPinOnTop: Bool? = nil,
        floatingPanelIntervalSeconds: Int? = nil,
        floatingPanelArgs: [String]? = nil,
        openWindow: WindowLaunchSpec? = nil,
        pasteText: String? = nil,
        notification: NotificationSpec? = nil
    ) {
        self.toast = toast
        self.closeOverlay = closeOverlay
        self.reloadSearchIndex = reloadSearchIndex
        self.statusSummary = statusSummary
        self.statusBadge = statusBadge
        self.openReaderPath = openReaderPath
        self.openImagePath = openImagePath
        self.pinImagePath = pinImagePath
        self.openFloatingPanel = openFloatingPanel
        self.floatingPanelPinOnTop = floatingPanelPinOnTop
        self.floatingPanelIntervalSeconds = floatingPanelIntervalSeconds
        self.floatingPanelArgs = floatingPanelArgs
        self.openWindow = openWindow
        self.pasteText = pasteText
        self.notification = notification
    }
}

public struct SearchIndexItem: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var subtitle: String?
    public var url: String?
    public var copyText: String?
    public var icon: String?
    public var tintColor: String?
    public var badge: String?
    public var tags: [String]?
    public var pinned: Bool?
    public var priority: Int?
    public var commandArgs: [String]?
    public var includeInGlobalSearch: Bool?

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        url: String? = nil,
        copyText: String? = nil,
        icon: String? = nil,
        tintColor: String? = nil,
        badge: String? = nil,
        tags: [String]? = nil,
        pinned: Bool? = nil,
        priority: Int? = nil,
        commandArgs: [String]? = nil,
        includeInGlobalSearch: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.url = url
        self.copyText = copyText
        self.icon = icon
        self.tintColor = tintColor
        self.badge = badge
        self.tags = tags
        self.pinned = pinned
        self.priority = priority
        self.commandArgs = commandArgs
        self.includeInGlobalSearch = includeInGlobalSearch
    }
}

public struct SearchIndexEnvelope: Codable, Sendable, Equatable {
    public var items: [SearchIndexItem]

    public init(items: [SearchIndexItem]) {
        self.items = items
    }
}

public struct RuntimeStatusFile: Codable, Sendable, Equatable {
    public var summary: String
    public var badge: String?

    public init(summary: String, badge: String? = nil) {
        self.summary = summary
        self.badge = badge
    }
}

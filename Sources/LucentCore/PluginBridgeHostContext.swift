import AppKit
import Foundation
import LucentSearch

public struct PluginContextRouteCandidate: Codable, Sendable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let categoryTag: String
    public let symbolName: String
    public let accentColor: String

    public init(id: String, name: String, categoryTag: String, symbolName: String, accentColor: String) {
        self.id = id
        self.name = name
        self.categoryTag = categoryTag
        self.symbolName = symbolName
        self.accentColor = accentColor
    }

    public func toJSONObject() -> [String: Any] {
        [
            "id": id,
            "name": name,
            "categoryTag": categoryTag,
            "symbolName": symbolName,
            "accentColor": accentColor
        ]
    }
}

public struct PluginBridgeHostContext: Sendable {
    public let everythingIndex: EverythingIndex?
    public let clipboardReader: @Sendable () -> String
    public let clipboardWriter: @Sendable (String) -> Bool
    public let selectionReader: @Sendable () -> PluginSelectionSnapshot
    public let preCapturedSelection: PluginSelectionSnapshot?
    public let pluginID: String?
    public let pluginName: String?
    public let pluginDirectoryURL: URL?
    public let manifestWindowDefaults: PluginManifestWindowDefaults?
    public let pasteBackHandler: (@Sendable (String) -> PluginPasteBackOutcome)?
    public let interactiveCaptureHandler: (@Sendable () throws -> PluginCapturedScreenFile)?
    public let customWindowOpener: (@Sendable (PluginCustomWindowSpec) -> Bool)?
    public let customWindowCloser: (@Sendable (String, String) -> Bool)?
    public let fileShelfAction: (@Sendable (String, Bool) -> Bool)?
    public let allowsAudioDevices: Bool
    public let audioFeedback: (@Sendable (String, String) -> Void)?
    public let progressReporter: (@Sendable (PluginExecutionProgress) -> Void)?
    public let contextMatcher: (@Sendable (String?, PluginContextPayload) -> [PluginContextRouteCandidate])?
    public let contextRouter: (@Sendable (String, PluginContextPayload) -> Bool)?

    public init(
        everythingIndex: EverythingIndex? = nil,
        clipboardReader: (@Sendable () -> String)? = nil,
        clipboardWriter: (@Sendable (String) -> Bool)? = nil,
        selectionReader: (@Sendable () -> PluginSelectionSnapshot)? = nil,
        preCapturedSelection: PluginSelectionSnapshot? = nil,
        pluginID: String? = nil,
        pluginName: String? = nil,
        pluginDirectoryURL: URL? = nil,
        manifestWindowDefaults: PluginManifestWindowDefaults? = nil,
        pasteBackHandler: (@Sendable (String) -> PluginPasteBackOutcome)? = nil,
        interactiveCaptureHandler: (@Sendable () throws -> PluginCapturedScreenFile)? = nil,
        customWindowOpener: (@Sendable (PluginCustomWindowSpec) -> Bool)? = nil,
        customWindowCloser: (@Sendable (String, String) -> Bool)? = nil,
        fileShelfAction: (@Sendable (String, Bool) -> Bool)? = nil,
        allowsAudioDevices: Bool = false,
        audioFeedback: (@Sendable (String, String) -> Void)? = nil,
        progressReporter: (@Sendable (PluginExecutionProgress) -> Void)? = nil,
        contextMatcher: (@Sendable (String?, PluginContextPayload) -> [PluginContextRouteCandidate])? = nil,
        contextRouter: (@Sendable (String, PluginContextPayload) -> Bool)? = nil
    ) {
        self.everythingIndex = everythingIndex
        self.clipboardReader = clipboardReader ?? {
            Self.runOnMainSync { NSPasteboard.general.string(forType: .string) ?? "" }
        }
        self.clipboardWriter = clipboardWriter ?? { text in
            Self.runOnMainSync {
                NSPasteboard.general.clearContents()
                return NSPasteboard.general.setString(text, forType: .string)
            }
        }
        self.selectionReader = selectionReader ?? {
            PluginSelectionReader.captureFrontmostSelection(enableManualAccessibility: true)
        }
        self.preCapturedSelection = preCapturedSelection
        self.pluginID = pluginID
        self.pluginName = pluginName
        self.pluginDirectoryURL = pluginDirectoryURL
        self.manifestWindowDefaults = manifestWindowDefaults
        self.pasteBackHandler = pasteBackHandler
        self.interactiveCaptureHandler = interactiveCaptureHandler
        self.customWindowOpener = customWindowOpener
        self.customWindowCloser = customWindowCloser
        self.fileShelfAction = fileShelfAction
        self.allowsAudioDevices = allowsAudioDevices
        self.audioFeedback = audioFeedback
        self.progressReporter = progressReporter
        self.contextMatcher = contextMatcher
        self.contextRouter = contextRouter
    }

    public func scoped(to descriptor: PluginDescriptor) -> PluginBridgeHostContext {
        PluginBridgeHostContext(
            everythingIndex: everythingIndex,
            clipboardReader: clipboardReader,
            clipboardWriter: clipboardWriter,
            selectionReader: selectionReader,
            preCapturedSelection: preCapturedSelection,
            pluginID: descriptor.id,
            pluginName: descriptor.displayName,
            pluginDirectoryURL: descriptor.directoryURL,
            manifestWindowDefaults: descriptor.manifest.window,
            pasteBackHandler: pasteBackHandler,
            interactiveCaptureHandler: interactiveCaptureHandler,
            customWindowOpener: customWindowOpener,
            customWindowCloser: customWindowCloser,
            fileShelfAction: fileShelfAction,
            allowsAudioDevices: allowsAudioDevices,
            audioFeedback: audioFeedback,
            progressReporter: progressReporter,
            contextMatcher: contextMatcher,
            contextRouter: contextRouter
        )
    }

    public static let `default` = PluginBridgeHostContext()

    private static func runOnMainSync<T: Sendable>(_ work: @MainActor @Sendable () -> T) -> T {
        if Thread.isMainThread { return MainActor.assumeIsolated(work) }
        return DispatchQueue.main.sync { MainActor.assumeIsolated(work) }
    }
}

import AppKit
import Foundation
import LucentCore

@MainActor
final class PluginFloatingPanelController: ObservableObject {
    let pluginID: String
    private weak var viewModel: AppViewModel?

    @Published private(set) var payload: PluginViewPayload?
    @Published private(set) var plainTextFallback: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRefreshing: Bool = false
    @Published private(set) var isPaused: Bool = false
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var lastDurationMs: Int?
    @Published private(set) var refreshIntervalSeconds: Int
    @Published private(set) var arguments: [String]
    @Published private(set) var query: String

    private var isWindowActive = false
    private var fetchTask: Task<Void, Never>?
    private var periodicLoopTask: Task<Void, Never>?

    static let intervalChoices: [Int] = [0, 15, 30, 60, 120, 300]

    init(
        request: PluginFloatingPanelRequest,
        viewModel: AppViewModel,
        seedPayload: PluginViewPayload? = nil
    ) {
        self.pluginID = request.pluginID
        self.viewModel = viewModel
        self.refreshIntervalSeconds = request.refreshIntervalSeconds
        self.arguments = request.arguments
        self.query = request.query
        if let seedPayload {
            self.payload = seedPayload
            self.lastUpdatedAt = Date()
        }
    }

    var plugin: PluginDescriptor? {
        viewModel?.plugins.first(where: { $0.id == pluginID })
    }

    var missingCapabilities: [PluginCapability] {
        guard let plugin, !plugin.isBuiltin else { return [] }
        return plugin.declaredCapabilities.filter { !plugin.grantedCapabilities.contains($0) }
    }

    func applyUpdatedRequest(_ request: PluginFloatingPanelRequest, seedPayload: PluginViewPayload?) {
        arguments = request.arguments
        query = request.query
        refreshIntervalSeconds = request.refreshIntervalSeconds
        if let seedPayload {
            payload = seedPayload
            plainTextFallback = nil
            errorMessage = nil
            lastUpdatedAt = Date()
        }
        if isWindowActive {
            if seedPayload == nil { refreshNow() }
            restartPeriodicLoop()
        }
    }

    func start() {
        guard !isWindowActive else { return }
        isWindowActive = true
        if payload == nil {
            refreshNow()
        }
        restartPeriodicLoop()
    }

    func stop() {
        isWindowActive = false
        periodicLoopTask?.cancel()
        periodicLoopTask = nil
        fetchTask?.cancel()
        fetchTask = nil
        isRefreshing = false
    }

    func setInterval(_ seconds: Int) {
        refreshIntervalSeconds = PluginFloatingPanelRequest.clampInterval(seconds)
        if refreshIntervalSeconds > 0 { isPaused = false }
        restartPeriodicLoop()
    }

    func togglePaused() {
        isPaused.toggle()
        if !isPaused { refreshNow() }
        restartPeriodicLoop()
    }

    func grantMissingCapabilitiesAndRefresh() {
        guard let vm = viewModel, let plugin else { return }
        for cap in missingCapabilities {
            try? vm.setPluginCapabilityGranted(plugin, capability: cap, granted: true)
        }
        refreshNow()
    }

    func openPluginSettings() {
        viewModel?.openPluginSettings(id: pluginID)
    }

    func handleOpenURL(_ url: URL) {
        viewModel?.handlePluginOpenURL(url)
    }

    func refreshNow(actionArguments: [String]? = nil) {
        guard let vm = viewModel, let currentPlugin = plugin else {
            errorMessage = L10n.pick("未找到插件 '\(pluginID)'", "Plugin '\(pluginID)' not found")
            return
        }
        guard currentPlugin.isBuiltin || currentPlugin.isEnabled else {
            errorMessage = L10n.pick("插件「\(currentPlugin.displayName)」当前已禁用", "Plugin '\(currentPlugin.displayName)' is disabled")
            return
        }

        fetchTask?.cancel()
        isRefreshing = true
        let effectiveArgs = actionArguments ?? arguments
        let activeQuery = actionArguments == nil ? query : ""
        let clipText = vm.clipboardItems.first(where: { $0.textValue != nil })?.textValue
            ?? NSPasteboard.general.string(forType: .string)
            ?? ""
        let bridgeContext = vm.makePluginBridgeContext()

        fetchTask = Task { [weak self] in
            do {
                let resolved = try await PluginSystem.runPluginAsync(
                    currentPlugin,
                    query: activeQuery,
                    clipboardText: clipText,
                    arguments: effectiveArgs,
                    hostContext: bridgeContext
                )
                guard !Task.isCancelled, let self else { return }
                self.isRefreshing = false
                self.lastDurationMs = resolved.execution.durationMs
                self.lastUpdatedAt = Date()

                if resolved.execution.exitCode == 0 {
                    self.viewModel?.reloadPlugins()
                }
                if let effect = resolved.viewPayload?.effect {
                    self.viewModel?.applyPluginPostActionEffect(
                        effect,
                        sourcePlugin: currentPlugin,
                        fromFloatingPanel: true
                    )
                }

                if let newPayload = resolved.viewPayload {
                    let isActionAckOnly = actionArguments != nil
                        && (newPayload.items?.isEmpty ?? true)
                        && (newPayload.metrics?.isEmpty ?? true)
                        && (newPayload.markdown?.isEmpty ?? true)
                    if isActionAckOnly {
                        self.errorMessage = nil
                        self.refreshNow(actionArguments: nil)
                        return
                    }
                    self.payload = newPayload
                    self.plainTextFallback = nil
                    self.errorMessage = nil
                } else if resolved.execution.exitCode == 0 {
                    self.payload = nil
                    self.plainTextFallback = resolved.plainText
                    self.errorMessage = resolved.viewParseDiagnostic
                } else {
                    self.errorMessage = resolved.plainText.isEmpty
                        ? L10n.pick("插件退出码 \(resolved.execution.exitCode)", "Exit code \(resolved.execution.exitCode)")
                        : resolved.plainText
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.isRefreshing = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func restartPeriodicLoop() {
        periodicLoopTask?.cancel()
        periodicLoopTask = nil
        guard isWindowActive, !isPaused, refreshIntervalSeconds > 0 else { return }
        let interval = refreshIntervalSeconds
        periodicLoopTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, let self, self.isWindowActive, !self.isPaused else { return }
                if !self.isRefreshing {
                    self.refreshNow()
                }
            }
        }
    }
}

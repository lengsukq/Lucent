import AppKit
import Foundation
import LumakeyCore
import SwiftUI

enum PluginCenterTab: String, CaseIterable, Identifiable {
    case gallery = "精选市场"
    case mcp = "MCP 接入"
    case permissions = "权限清单"
    case scaffold = "脚手架"
    var id: String { rawValue }
}

@MainActor
final class PluginCenterController: ObservableObject {
    @Published var activeTab: PluginCenterTab = .gallery
    @Published var selectedPluginID: String?
    @Published var configDraft: [String: String] = [:]
    @Published var hasUnsavedTextEdits: Bool = false
    @Published var testQuery: String = ""
    @Published var isRunning: Bool = false
    @Published var latestOutput: PluginResolvedOutput?
    @Published var statusNote: String = "350ms 防抖实时热重载就绪"
    @Published var isWatcherOnline: Bool = false
    @Published var showUnusedPermissions: Bool = false
    @Published var mcpExtraTask: String = ""

    @Published var newID: String = "uuid-card"
    @Published var newName: String = "UUID 视图卡"
    @Published var newKeywords: String = "uuidcard"
    @Published var newMode: PluginMode = .view
    @Published var newCapabilities: Set<PluginCapability> = []
    @Published var newResourceScopes: Set<PluginResourceScope> = []

    private var watcher: PluginDirectoryWatcher?
    private var runTask: Task<Void, Never>?
    private var autoSaveTask: Task<Void, Never>?
    private var pendingSavePlugin: PluginDescriptor?
    private weak var pendingSaveViewModel: AppViewModel?

    func startWatching(syncing viewModel: AppViewModel) {
        viewModel.reloadPlugins()
        if watcher == nil {
            watcher = PluginDirectoryWatcher(debounceInterval: 0.35) { [weak self, weak viewModel] changes in
                Task { @MainActor in
                    guard let self, let viewModel else { return }
                    if changes.contains(.bundle) {
                        viewModel.reloadPluginsAndHotKeys()
                        self.syncSelection(from: viewModel.plugins)
                    } else if changes.contains(.searchIndex) {
                        viewModel.reloadPluginSearchIndex()
                    }
                    let df = DateFormatter()
                    df.dateFormat = "HH:mm:ss"
                    self.statusNote = "已热重载 · \(df.string(from: Date()))"
                }
            }
        }
        isWatcherOnline = watcher?.isWatching ?? false
        syncSelection(from: viewModel.plugins)
    }

    func stopWatching() {
        flushPendingSaveIfNeeded()
        runTask?.cancel(); runTask = nil
        watcher?.stop(); watcher = nil
        isWatcherOnline = false
    }

    func flushPendingSaveIfNeeded() {
        autoSaveTask?.cancel()
        autoSaveTask = nil
        guard hasUnsavedTextEdits, let plugin = pendingSavePlugin, let vm = pendingSaveViewModel else { return }
        saveConfig(for: plugin, viewModel: vm, silent: true)
    }

    func syncSelection(from plugins: [PluginDescriptor]) {
        if let currentID = selectedPluginID,
           let matched = plugins.first(where: { $0.id == currentID }) {
            if configDraft.isEmpty {
                configDraft = matched.isBuiltin ? matched.userConfig : PluginSystem.resolvedUserConfigWithSecrets(for: matched)
            }
            return
        }
        if let first = plugins.first {
            select(first)
        } else {
            flushPendingSaveIfNeeded()
            selectedPluginID = nil
            configDraft = [:]
            hasUnsavedTextEdits = false
        }
    }

    func select(_ plugin: PluginDescriptor) {
        if selectedPluginID != nil, selectedPluginID != plugin.id { flushPendingSaveIfNeeded() }
        else { autoSaveTask?.cancel() }
        selectedPluginID = plugin.id
        pendingSavePlugin = plugin
        configDraft = plugin.isBuiltin ? plugin.userConfig : PluginSystem.resolvedUserConfigWithSecrets(for: plugin)
        hasUnsavedTextEdits = false
    }

    func binding(for field: PluginConfigField) -> Binding<String> {
        let fallback = field.defaultValue ?? ""
        return Binding(get: { self.configDraft[field.key] ?? fallback }, set: { self.configDraft[field.key] = $0 })
    }

    func autoSaveTextBinding(for field: PluginConfigField, plugin: PluginDescriptor, viewModel: AppViewModel) -> Binding<String> {
        let fallback = field.defaultValue ?? ""
        return Binding(
            get: { self.configDraft[field.key] ?? fallback },
            set: { [weak self] next in
                guard let self else { return }
                self.configDraft[field.key] = next
                self.hasUnsavedTextEdits = true
                self.pendingSavePlugin = plugin
                self.pendingSaveViewModel = viewModel
                self.scheduleDebouncedSave(for: plugin, viewModel: viewModel)
            }
        )
    }

    private func scheduleDebouncedSave(for plugin: PluginDescriptor, viewModel: AppViewModel) {
        autoSaveTask?.cancel()
        autoSaveTask = Task { [weak self, weak viewModel] in
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled, let self, let viewModel else { return }
            self.saveConfig(for: plugin, viewModel: viewModel, silent: true)
        }
    }

    func boolBinding(for field: PluginConfigField) -> Binding<Bool> {
        let fallback = (field.defaultValue ?? "false").lowercased() == "true"
        return Binding(
            get: { (self.configDraft[field.key].map { $0.lowercased() == "true" }) ?? fallback },
            set: { self.configDraft[field.key] = $0 ? "true" : "false" }
        )
    }

    func setEnabled(_ plugin: PluginDescriptor, isEnabled: Bool, viewModel: AppViewModel) {
        do {
            try viewModel.setPluginEnabled(plugin, isEnabled: isEnabled)
            statusNote = "\(plugin.displayName) 已\(isEnabled ? "启用" : "禁用")"
        } catch {
            statusNote = error.localizedDescription
        }
    }

    func setCapabilityGranted(_ plugin: PluginDescriptor, capability: PluginCapability, granted: Bool, viewModel: AppViewModel) {
        do {
            try viewModel.setPluginCapabilityGranted(plugin, capability: capability, granted: granted)
            statusNote = "\(plugin.displayName) · \(capability.title) 已\(granted ? "授权" : "收回")"
            viewModel.serviceMessage = statusNote
        } catch {
            statusNote = error.localizedDescription
        }
    }

    func setResourceScopeGranted(_ plugin: PluginDescriptor, scope: PluginResourceScope, granted: Bool, viewModel: AppViewModel) {
        do {
            try viewModel.setPluginResourceScopeGranted(plugin, scope: scope, granted: granted)
            statusNote = "\(plugin.displayName) · \(scope.title) 已\(granted ? "放行" : "沙箱拦截")"
            viewModel.serviceMessage = statusNote
        } catch {
            statusNote = error.localizedDescription
        }
    }

    func saveConfig(for plugin: PluginDescriptor, viewModel: AppViewModel, silent: Bool = false) {
        autoSaveTask?.cancel()
        autoSaveTask = nil
        do {
            try PluginSystem.updatePluginConfig(id: plugin.id, values: configDraft)
            hasUnsavedTextEdits = false
            pendingSavePlugin = nil
            viewModel.reloadPluginsAndHotKeys()
            if !silent {
                configDraft = plugin.isBuiltin ? plugin.userConfig : PluginSystem.resolvedUserConfigWithSecrets(for: plugin)
                statusNote = L10n.pick("已保存 \(plugin.displayName) 配置", "Saved \(plugin.displayName) preferences")
                viewModel.serviceMessage = statusNote
            }
        } catch {
            statusNote = error.localizedDescription
        }
    }

    func runAsync(_ plugin: PluginDescriptor, arguments: [String] = [], viewModel: AppViewModel) {
        flushPendingSaveIfNeeded()
        runTask?.cancel()
        isRunning = true
        let query = testQuery
        let clip = NSPasteboard.general.string(forType: .string) ?? ""
        let bridgeContext = viewModel.makePluginBridgeContext()
        runTask = Task { [weak self, weak viewModel] in
            do {
                let resolved = try await PluginSystem.runPluginAsync(
                    plugin, query: query, clipboardText: clip,
                    arguments: arguments, hostContext: bridgeContext
                )
                guard !Task.isCancelled, let self else { return }
                self.isRunning = false
                self.latestOutput = resolved
                viewModel?.pluginOutputText = resolved.plainText
                viewModel?.reloadPlugins()
                if plugin.id == LumaLinkServer.companionPluginID {
                    viewModel?.refreshLumaLinkStatus(refreshPermissions: false)
                }
                self.statusNote = "\(plugin.displayName) 完成 (\(resolved.execution.durationMs) ms)"
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.isRunning = false
                let msg = (error as? LumakeyError)?.diagnostic.reason ?? error.localizedDescription
                self.statusNote = msg
                viewModel?.pluginOutputText = msg
            }
        }
    }

    func installStarter(_ tpl: PluginStarterTemplate, viewModel: AppViewModel) {
        do {
            let installed = try PluginStarterGallery.install(templateID: tpl.id, overwrite: true)
            viewModel.reloadPluginsAndHotKeys()
            viewModel.openPluginSettings(id: installed.id)
        } catch {
            statusNote = error.localizedDescription
        }
    }

    func scaffoldCustom(viewModel: AppViewModel) {
        let kws = newKeywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let caps = PluginCapability.allCases.filter { newCapabilities.contains($0) }
        let scopes = PluginResourceScope.allCases.filter { newResourceScopes.contains($0) }
        do {
            let created = try PluginSystem.scaffoldPlugin(
                id: newID, name: newName, keywords: kws,
                description: "通过 Lumakey 插件中心创建", mode: newMode,
                capabilities: caps, resourceScopes: scopes
            )
            viewModel.reloadPluginsAndHotKeys()
            viewModel.openPluginSettings(id: created.id)
        } catch let err as LumakeyError {
            viewModel.diagnostic = err.diagnostic; statusNote = err.diagnostic.reason
        } catch {
            statusNote = error.localizedDescription
        }
    }

    func remove(_ plugin: PluginDescriptor, viewModel: AppViewModel) {
        guard !plugin.isBuiltin else {
            statusNote = "内置原生插件不可卸载，可通过开关随时停用（零后台消耗）"
            return
        }
        do {
            try PluginSystem.removePlugin(id: plugin.id)
            if latestOutput?.pluginID == plugin.id { latestOutput = nil }
            viewModel.reloadPluginsAndHotKeys()
            syncSelection(from: viewModel.plugins)
            statusNote = "已移除插件：\(plugin.displayName)"
        } catch {
            statusNote = error.localizedDescription
        }
    }

    func importFromFinder(viewModel: AppViewModel) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.prompt = "导入插件目录"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try PluginSystem.importPluginDirectory(from: url, overwrite: true)
            viewModel.reloadPluginsAndHotKeys()
            viewModel.openPluginSettings(id: imported.id)
        } catch {
            statusNote = (error as? LumakeyError)?.diagnostic.reason ?? error.localizedDescription
        }
    }

    func exportToFinder(_ plugin: PluginDescriptor) {
        guard !plugin.isBuiltin else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.prompt = "导出到此文件夹"
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        if let outURL = try? PluginSystem.exportPlugin(id: plugin.id, to: dest) {
            NSWorkspace.shared.activateFileViewerSelecting([outURL])
            statusNote = "已导出至 \(outURL.path)"
        }
    }

    func openPluginsDirectoryInFinder() {
        let dir = PluginSystem.defaultPluginsDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }
}

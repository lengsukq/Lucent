import AppKit
import Foundation
import LucentCore

@MainActor
extension MenuBarAndWindowCoordinator {
    func openPluginFloatingPanel(
        request req: PluginFloatingPanelRequest,
        seedPayload: PluginViewPayload? = nil,
        activateApp: Bool = true
    ) {
        let key = "pluginPanel:\(req.pluginID)"
        let ctrl: PluginFloatingPanelController
        if let existingCtrl = pluginPanelControllers[key] {
            existingCtrl.applyUpdatedRequest(req, seedPayload: seedPayload)
            ctrl = existingCtrl
        } else {
            let created = PluginFloatingPanelController(request: req, viewModel: viewModel, seedPayload: seedPayload)
            pluginPanelControllers[key] = created
            ctrl = created
        }
        let plugName = viewModel.plugins.first(where: { $0.id == req.pluginID })?.displayName ?? req.pluginID
        presentWindow(
            key: key,
            title: "\(plugName) · 悬浮面板",
            size: NSSize(width: 520, height: 600),
            minSize: NSSize(width: 420, height: 360),
            pinOnTop: req.pinOnTop,
            activateApp: activateApp
        ) {
            PluginFloatingPanelWindowView(controller: ctrl, windowKey: key)
        }
        FloatingWindowSessionStore.upsertPluginFloatingPanel(
            ctrl.currentRequest(pinOnTop: WindowLevelStore.shared.isPinned(key))
        )
    }

    func persistActivePluginFloatingPanels() {
        let requests = pluginPanelControllers
            .sorted { $0.key < $1.key }
            .map { (key, ctrl) in
                ctrl.currentRequest(pinOnTop: WindowLevelStore.shared.isPinned(key))
            }
        FloatingWindowSessionStore.update { $0.pluginFloatingPanels = requests }
    }

    func restoreFloatingWindowsIfNeeded() {
        guard viewModel.generalPreferences.restoreFloatingWindowsOnLaunch else { return }
        PluginCustomWebWindowController.shared.restorePersistedWindows(viewModel: viewModel)
        restorePersistedPluginFloatingPanels()
        PinWindowController.shared.restorePersistedPins()
    }

    private func restorePersistedPluginFloatingPanels() {
        let savedPanels = FloatingWindowSessionStore.load().pluginFloatingPanels
        guard !savedPanels.isEmpty else { return }
        for req in savedPanels {
            guard let plugin = viewModel.plugins.first(where: { $0.id == req.pluginID }),
                  plugin.isValid,
                  (plugin.isBuiltin || plugin.isEnabled) else {
                FloatingWindowSessionStore.removePluginFloatingPanel(pluginID: req.pluginID)
                continue
            }
            openPluginFloatingPanel(request: req, seedPayload: nil, activateApp: false)
        }
    }
}

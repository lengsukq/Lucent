import AppKit
import Carbon
import LumakeyCore

extension MenuBarAndWindowCoordinator: NSMenuDelegate {
    func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        applyStatusBarImage(to: item)
        item.button?.imagePosition = .imageLeading
        item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
        updateStatusButtonTooltip(for: item)
        let menu = NSMenu()
        menu.delegate = self
        populateStatusMenu(menu)
        item.menu = menu
        self.statusItem = item
    }

    func refreshStatusBarIcon() {
        guard let item = statusItem else { return }
        applyStatusBarImage(to: item)
    }

    private func applyStatusBarImage(to item: NSStatusItem) {
        let style = viewModel.generalPreferences.menuBarIconStyle
        if style == .prism3D {
            item.button?.image = LumakeyBrandIcon.statusBarImage(pointSize: 16.5)
        } else {
            item.button?.image = NSImage(systemSymbolName: style.symbolName, accessibilityDescription: L10n.translate("流光 Lumakey"))
        }
    }

    func refreshLocalizedChrome() {
        refreshStatusBarIcon()
        if let item = statusItem {
            updateStatusButtonTooltip(for: item)
            if let menu = item.menu { populateStatusMenu(menu) }
        }
        for (key, win) in windows {
            if let base = windowBaseTitles[key] { win.title = L10n.translate(base) }
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem?.menu else { return }
        if let item = statusItem { updateStatusButtonTooltip(for: item) }
        populateStatusMenu(menu)
    }

    private func updateStatusButtonTooltip(for item: NSStatusItem) {
        let hk = hotKeyManager.currentConfig.effectiveChord(for: .launcher)?.displayString
        let base = L10n.translate("流光 Lumakey")
        item.button?.toolTip = hk.map { "\(base) (\($0))" } ?? base
    }

    func buildDockMenu() -> NSMenu {
        let menu = NSMenu()
        if !windows.isEmpty {
            for (_, win) in windows.sorted(by: { $0.key < $1.key }) {
                let frontTitle = L10n.pick("前置：\(win.title)", "Bring to Front: \(win.title)")
                let mItem = makeCallbackMenuItem(title: frontTitle) {
                    if win.isMiniaturized { win.deminiaturize(nil) }
                    win.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
                }
                menu.addItem(mItem)
            }
            menu.addItem(.separator())
        }
        let dockItems: [MenuBarBuiltinItemID] = [
            .fileWorkspace, .networkMonitor, .launcherAll, .screenshotPin,
            .gifRecord, .backupSync, .checkForUpdates, .switchLanguage, .settingsCenter
        ]
        for id in dockItems {
            menu.addItem(makeBuiltinMenuItem(id, context: currentRuntimeContext()))
        }
        return menu
    }

    func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        populateStatusMenu(menu)
        return menu
    }

    func populateStatusMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let ctx = currentRuntimeContext()
        let config = viewModel.menuBarConfig
        let layout = config.resolvedLayout(context: ctx)

        var previousGroup: MenuBarItemGroup? = nil
        for itemID in layout.topLevelItems {
            if let prev = previousGroup, prev != itemID.group {
                menu.addItem(.separator())
            }
            menu.addItem(makeBuiltinMenuItem(itemID, context: ctx))
            previousGroup = itemID.group
        }

        if config.showPinnedPluginsSection {
            appendPinnedPluginsAndScripts(to: menu)
        }

        if !layout.maintenanceSubmenuItems.isEmpty {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            let subRoot = NSMenuItem(title: L10n.pick("维护与系统工具", "Maintenance & Tools"), action: nil, keyEquivalent: "")
            subRoot.image = NSImage(systemSymbolName: "wrench.and.screwdriver", accessibilityDescription: nil)
            let submenu = NSMenu(title: subRoot.title)
            for mID in layout.maintenanceSubmenuItems {
                submenu.addItem(makeBuiltinMenuItem(mID, context: ctx))
            }
            subRoot.submenu = submenu
            menu.addItem(subRoot)
        }

        if !layout.systemTailItems.isEmpty {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            for tailID in layout.systemTailItems {
                if tailID == .quitApp && layout.systemTailItems.count > 1 {
                    menu.addItem(.separator())
                }
                menu.addItem(makeBuiltinMenuItem(tailID, context: ctx))
            }
        }
    }

    private func currentRuntimeContext() -> MenuBarRuntimeContext {
        let pulseCfg = SystemPulseWindowController.shared.state.config
        let hasLumaLink = viewModel.lumaLinkConfig.enabled
            || viewModel.plugins.contains { $0.id == LumaLinkServer.companionPluginID && $0.isEnabled && $0.isValid }
        let updater = AppUpdateCoordinator.shared
        return MenuBarRuntimeContext(
            activePinCount: PinWindowController.shared.activePinCount,
            activePluginWindowCount: PluginCustomWebWindowController.shared.activeWindowCount,
            isSystemPulseFloatingVisible: pulseCfg.floatingEnabled,
            isLumaLinkAvailableOrEnabled: hasLumaLink,
            availableAppUpdateVersion: updater.availableAppRelease?.normalizedVersion,
            availablePluginUpdateCount: updater.pendingPluginUpdates.count
        )
    }

    private func makeBuiltinMenuItem(_ id: MenuBarBuiltinItemID, context: MenuBarRuntimeContext) -> NSMenuItem {
        let title: String = switch id {
        case .closeAllPins where context.activePinCount > 0:
            "\(id.localizedTitle) (\(context.activePinCount))"
        case .closeAllPluginWindows where context.activePluginWindowCount > 0:
            "\(id.localizedTitle) (\(context.activePluginWindowCount))"
        case .checkForUpdates where context.availableAppUpdateVersion != nil:
            L10n.pick(
                "发现新版本 v\(context.availableAppUpdateVersion ?? "") · 查看更新",
                "Update Available v\(context.availableAppUpdateVersion ?? "")"
            )
        case .checkForUpdates where context.availablePluginUpdateCount > 0:
            L10n.pick(
                "发现 \(context.availablePluginUpdateCount) 款插件可升级 · 查看更新",
                "\(context.availablePluginUpdateCount) Plugin Update(s) Available"
            )
        case .switchLanguage:
            L10n.pick("切换界面语言：English", "Switch Language: 简体中文")
        default:
            id.localizedTitle
        }

        let item = makeCallbackMenuItem(title: title) { [weak self] in
            self?.performMenuAction(id)
        }
        item.image = NSImage(systemSymbolName: id.symbolName, accessibilityDescription: nil)

        switch id {
        case .systemPulseWidget:
            item.state = SystemPulseWindowController.shared.state.config.floatingEnabled ? .on : .off
        case .menuBarTelemetryReadout:
            item.state = SystemPulseWindowController.shared.state.config.showInMenuBar ? .on : .off
        case .mosSettings:
            item.state = viewModel.mosConfig.enabled ? .on : .off
        default:
            break
        }

        if let hkAction = id.associatedHotKeyAction,
           let chord = hotKeyManager.currentConfig.effectiveChord(for: hkAction) {
            applyMenuShortcut(chord: chord, to: item)
        } else if id == .settingsCenter {
            item.keyEquivalent = ","
            item.keyEquivalentModifierMask = [.command]
        } else if id == .quitApp {
            item.keyEquivalent = "q"
            item.keyEquivalentModifierMask = [.command]
        }
        return item
    }

    func makeCallbackMenuItem(title: String, callback: @escaping () -> Void) -> NSMenuItem {
        MenuBarCallbackItem(title: title, callback: callback)
    }

    func applyMenuShortcut(chord: HotKeyChord, to item: NSMenuItem) {
        if let keyEq = Self.menuKeyEquivalent(for: chord.keyCode) {
            item.keyEquivalent = keyEq
            item.keyEquivalentModifierMask = chord.modifierFlags
        } else {
            item.title = "\(item.title)   (\(chord.displayString))"
        }
    }

    private static func menuKeyEquivalent(for keyCode: Int) -> String? {
        if keyCode == kVK_Space { return " " }
        if keyCode == kVK_Return { return "\r" }
        if keyCode == kVK_Tab { return "\t" }
        if keyCode == kVK_Delete { return "\u{08}" }
        if keyCode == kVK_Escape { return "\u{1b}" }
        guard let label = HotKeyChord.keyLabel(for: keyCode), label.count == 1 else { return nil }
        return label.lowercased()
    }

    private func performMenuAction(_ id: MenuBarBuiltinItemID) {
        switch id {
        case .launcherAll: panelController.show(filter: .all)
        case .filesFilter: panelController.show(filter: .files)
        case .clipboardFilter: panelController.show(filter: .clipboard)
        case .systemPulseWidget: SystemPulseWindowController.shared.toggleFloatingWidget()
        case .systemPulseSnapEdge: SystemPulseWindowController.shared.snapToNearestEdge()
        case .menuBarTelemetryReadout: SystemPulseWindowController.shared.toggleMenuBarReadout()
        case .networkMonitor: open(route: .networkMonitor)
        case .screenshotPin: viewModel.captureAndPinScreenshot()
        case .screenshotOCR: viewModel.captureAndAnalyzeOCR()
        case .gifRecord: viewModel.startGifRecording()
        case .closeAllPins: PinWindowController.shared.closeAll()
        case .closeAllPluginWindows: PluginCustomWebWindowController.shared.closeAll()
        case .backupSync: open(route: .settings(.backup))
        case .lumaLinkConsole: openLumaLinkConsole()
        case .cacheCleanup: open(route: .settings(.cache))
        case .mosSettings: open(route: .settings(.mos))
        case .reclaimMemory: viewModel.reclaimAllIdleMemoryNow()
        case .fileWorkspace: open(route: .workspace)
        case .switchLanguage: viewModel.cycleAppLanguage()
        case .checkForUpdates:
            open(route: .settings(.about))
            AppUpdateCoordinator.shared.checkNow(viewModel: viewModel)
        case .settingsCenter: open(route: .settings(.general))
        case .quitApp: NSApp.terminate(nil)
        }
    }
}

@MainActor
private final class MenuBarCallbackItem: NSMenuItem {
    private let callback: () -> Void
    init(title: String, callback: @escaping () -> Void) {
        self.callback = callback
        super.init(title: title, action: #selector(handleTap), keyEquivalent: "")
        self.target = self
    }
    @available(*, unavailable) required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func handleTap() { callback() }
}

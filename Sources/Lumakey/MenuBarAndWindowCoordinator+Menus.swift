import AppKit
import LumakeyCore

extension MenuBarAndWindowCoordinator {
    func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: L10n.translate("流光 Lumakey"))
        item.button?.imagePosition = .imageLeading
        item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
        item.button?.toolTip = L10n.translate("流光 Lumakey (⌥Space)")
        item.menu = buildStatusMenu()
        self.statusItem = item
    }

    func refreshLocalizedChrome() {
        statusItem?.button?.toolTip = L10n.translate("流光 Lumakey (⌥Space)")
        statusItem?.menu = buildStatusMenu()
        for (key, win) in windows {
            if let base = windowBaseTitles[key] { win.title = L10n.translate(base) }
        }
    }

    func buildDockMenu() -> NSMenu {
        let menu = NSMenu()
        if !windows.isEmpty {
            for (_, win) in windows.sorted(by: { $0.key < $1.key }) {
                let frontTitle = L10n.pick("前置：\(win.title)", "Bring to Front: \(win.title)")
                addMenuItem(to: menu, rawTitle: frontTitle, key: "", translate: false) {
                    if win.isMiniaturized { win.deminiaturize(nil) }
                    win.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
                }
            }
            menu.addItem(.separator())
        }
        addMenuItem(to: menu, rawTitle: "文件与外置磁盘工作台", key: "⌥E") { [weak self] in self?.open(route: .workspace) }
        addMenuItem(to: menu, rawTitle: "本机网络流量与去向监控", key: "⌥N") { [weak self] in self?.open(route: .networkMonitor) }
        addMenuItem(to: menu, rawTitle: "统一搜索快捷台", key: "⌥Space") { [weak self] in self?.panelController.show(filter: .all) }
        addMenuItem(to: menu, rawTitle: "选区截图钉屏", key: "⌥A") { [weak self] in self?.viewModel.captureAndPinScreenshot() }
        addMenuItem(to: menu, rawTitle: "区域 GIF 动图录制", key: "⌥G") { [weak self] in self?.viewModel.startGifRecording() }
        addMenuItem(to: menu, rawTitle: "导出与云备份", key: "") { [weak self] in self?.open(route: .settings(.backup)) }
        let langLabel = L10n.pick("切换语言：English", "Switch Language: 简体中文")
        addMenuItem(to: menu, rawTitle: langLabel, key: "", translate: false) { [weak self] in self?.viewModel.cycleAppLanguage() }
        addMenuItem(to: menu, rawTitle: "设置中心", key: "⌘,") { [weak self] in self?.open(route: .settings(.general)) }
        return menu
    }

    func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()
        addMenuItem(to: menu, rawTitle: "呼出统一搜索快捷台", key: "⌥Space") { [weak self] in self?.panelController.show(filter: .all) }
        addMenuItem(to: menu, rawTitle: "文件极速过滤", key: "⌥F") { [weak self] in self?.panelController.show(filter: .files) }
        addMenuItem(to: menu, rawTitle: "剪贴板历史过滤", key: "⌥C") { [weak self] in self?.panelController.show(filter: .clipboard) }
        menu.addItem(.separator())
        addMenuItem(to: menu, rawTitle: "系统脉搏监控悬浮窗", key: "⌥M") { SystemPulseWindowController.shared.toggleFloatingWidget() }
        addMenuItem(to: menu, rawTitle: "系统脉搏：立即贴边自动隐藏", key: "") { SystemPulseWindowController.shared.snapToNearestEdge() }
        addMenuItem(to: menu, rawTitle: "菜单栏显示实时功耗与网速", key: "") { SystemPulseWindowController.shared.toggleMenuBarReadout() }
        addMenuItem(to: menu, rawTitle: "本机网络流量与去向监控", key: "⌥N") { [weak self] in self?.open(route: .networkMonitor) }
        menu.addItem(.separator())
        addMenuItem(to: menu, rawTitle: "选区截图钉屏", key: "⌥A") { [weak self] in self?.viewModel.captureAndPinScreenshot() }
        addMenuItem(to: menu, rawTitle: "选区截图离线识字", key: "⌥O") { [weak self] in self?.viewModel.captureAndAnalyzeOCR() }
        addMenuItem(to: menu, rawTitle: "区域 GIF 动图录制", key: "⌥G") { [weak self] in self?.viewModel.startGifRecording() }
        addMenuItem(to: menu, rawTitle: "关闭全部钉图", key: "") { PinWindowController.shared.closeAll() }
        menu.addItem(.separator())
        addMenuItem(to: menu, rawTitle: "导出、备份与 WebDAV 云同步", key: "") { [weak self] in self?.open(route: .settings(.backup)) }
        addMenuItem(to: menu, rawTitle: "流光随行手机远控与极速 RDP", key: "") { [weak self] in self?.openLumaLinkConsole() }
        addMenuItem(to: menu, rawTitle: "应用缓存与存储清理", key: "") { [weak self] in self?.open(route: .settings(.cache)) }
        addMenuItem(to: menu, rawTitle: "鼠标平滑与滚轮反转", key: "") { [weak self] in self?.open(route: .settings(.mos)) }
        addMenuItem(to: menu, rawTitle: "立即释放空闲内存", key: "") { [weak self] in self?.viewModel.reclaimAllIdleMemoryNow() }
        addMenuItem(to: menu, rawTitle: "文件与外置磁盘工作台 · 附加", key: "⌥E") { [weak self] in self?.open(route: .workspace) }
        let langLabel = L10n.pick("切换界面语言：English", "Switch Language: 简体中文")
        addMenuItem(to: menu, rawTitle: langLabel, key: "", translate: false) { [weak self] in self?.viewModel.cycleAppLanguage() }
        addMenuItem(to: menu, rawTitle: "设置与插件 MCP 中心", key: "⌘,") { [weak self] in self?.open(route: .settings(.general)) }
        menu.addItem(.separator())
        addMenuItem(to: menu, rawTitle: "退出 流光 Lumakey", key: "⌘Q") { NSApp.terminate(nil) }
        return menu
    }

    private func addMenuItem(to menu: NSMenu, rawTitle: String, key: String, translate: Bool = true, action: @escaping () -> Void) {
        let localized = translate ? L10n.translate(rawTitle) : rawTitle
        menu.addItem(MenuBarCallbackItem(title: key.isEmpty ? localized : "\(localized)   (\(key))", callback: action))
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

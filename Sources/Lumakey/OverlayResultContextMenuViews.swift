import AppKit
import LumakeyCore
import SwiftUI

extension OverlayUnifiedRowsView {
    @ViewBuilder
    func rowContextMenu(_ candidate: LauncherCandidate) -> some View {
        switch candidate.kind {
        case .app(let app):
            let pinned = AppUsageTrackerController.shared.isPinned(app)
            Button { AppUsageTrackerController.shared.togglePin(app) } label: {
                Label(pinned ? "取消钉住" : "钉在常用栏", systemImage: pinned ? "pin.slash" : "pin.fill")
            }
            pinToHomeSubmenu(for: candidate)
            Button { NSWorkspace.shared.activateFileViewerSelecting([app.url]) } label: { Label("在访达中显示", systemImage: "folder") }
            Button(role: .destructive) { AppUsageTrackerController.shared.resetStats(for: app.id) } label: {
                Label("重置使用记录", systemImage: "arrow.counterclockwise")
            }
        case .fileHit(let hit):
            pinToHomeSubmenu(for: candidate)
            Button { NSWorkspace.shared.activateFileViewerSelecting([hit.url]) } label: { Label("在访达中显示", systemImage: "folder") }
            Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(hit.url.path, forType: .string) } label: {
                Label("复制完整路径", systemImage: "doc.on.doc")
            }
            if let ctx = PluginContextMatcher.payloadFromFiles([hit.url], source: "everything") { contextPluginSubmenu(ctx) }
        case .clipboard(let entry):
            Button { viewModel.executeClipboardEntry(entry) } label: { Label("复制到剪贴板 (↩)", systemImage: "doc.on.doc") }
            Button { viewModel.executeClipboardEntry(entry, autoPaste: true) } label: { Label("直接粘贴到原窗口 (⇧↩)", systemImage: "arrow.turn.down.left") }
            if !entry.fileURLs.isEmpty {
                Button { NSWorkspace.shared.activateFileViewerSelecting(entry.fileURLs) } label: { Label("在访达中显示 (⌘R)", systemImage: "folder") }
            }
            Button { viewModel.toggleClipboardPin(entry) } label: {
                Label(entry.isPinned ? "取消收藏" : "永久收藏", systemImage: entry.isPinned ? "pin.slash" : "pin.fill")
            }
            if let ctx = PluginContextMatcher.payloadFromClipboard(entry) { contextPluginSubmenu(ctx) }
        case .plugin(let plugin):
            Button { viewModel.enterPluginScopedOverlay(plugin) } label: { Label("进入插件专属列表 (Tab)", systemImage: "list.bullet.rectangle") }
            pinToHomeSubmenu(for: candidate)
            Button { viewModel.togglePluginOverlayPin(plugin) } label: {
                Label(plugin.pinnedInOverlay ? "从快捷按钮移除" : "添加到快捷按钮", systemImage: plugin.pinnedInOverlay ? "bolt.slash.fill" : "bolt.circle.fill")
            }
            Button { viewModel.openPluginSettings(id: plugin.id) } label: { Label("打开插件独立设置 (⌘,)", systemImage: "slider.horizontal.3") }
        case .pluginCommand(let cmd):
            Button { viewModel.executeCandidate(candidate) } label: { Label("立即执行子功能", systemImage: "play.fill") }
            pinToHomeSubmenu(for: candidate)
            Button { viewModel.togglePluginCommandQuickButton(cmd) } label: {
                Label(cmd.isQuickButtonEnabled ? "从快捷按钮移除" : "添加到快捷按钮", systemImage: cmd.isQuickButtonEnabled ? "bolt.slash.fill" : "bolt.circle.fill")
            }
            Button { viewModel.openPluginSettings(id: cmd.pluginID) } label: { Label("打开所属插件设置 (⌘,)", systemImage: "slider.horizontal.3") }
        case .pluginItem(let entry):
            Button { viewModel.executeCandidate(candidate) } label: {
                Label(entry.url != nil ? "打开网页" : "执行", systemImage: entry.url != nil ? "safari" : "play.fill")
            }
            pinToHomeSubmenu(for: candidate)
            if let args = entry.commandArgs, !args.isEmpty, let plugin = viewModel.plugins.first(where: { $0.id == entry.pluginID }) {
                Button { viewModel.runPlugin(plugin, query: "", arguments: args, showInline: true) } label: {
                    Label("在插件中管理", systemImage: "slider.horizontal.3")
                }
            }
            Button { viewModel.openPluginSettings(id: entry.pluginID) } label: { Label("打开所属插件设置", systemImage: "gearshape") }
            Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(entry.copyText ?? entry.url ?? entry.title, forType: .string) } label: {
                Label("复制内容", systemImage: "doc.on.doc")
            }
        case .script(let m):
            Button { viewModel.executeCandidate(candidate) } label: { Label(L10n.pick("立即运行脚本 (↩)", "Run Script (↩)"), systemImage: "play.fill") }
            pinToHomeSubmenu(for: candidate)
            Button { viewModel.toggleScriptQuickBarPin(m.script) } label: {
                Label(m.script.pinnedInQuickBar ? L10n.pick("从快捷按钮栏移除", "Remove from Quick Bar") : L10n.pick("添加到快捷按钮栏", "Add to Quick Bar"), systemImage: m.script.pinnedInQuickBar ? "bolt.slash.fill" : "bolt.circle.fill")
            }
            Button { viewModel.toggleScriptMenuBarPin(m.script) } label: {
                Label(m.script.showInMenuBar ? L10n.pick("从状态栏菜单移除", "Remove from Menu Bar") : L10n.pick("挂载到状态栏菜单", "Pin to Menu Bar"), systemImage: "menubar.rectangle")
            }
            Button { viewModel.openScriptSettings(selecting: m.script.id) } label: { Label(L10n.pick("编辑快捷脚本 (⌘,)", "Edit Script (⌘,)"), systemImage: "slider.horizontal.3") }
            Button { NSWorkspace.shared.activateFileViewerSelecting([ScriptLibraryStore.shared.scriptURL(for: m.script)]) } label: {
                Label(L10n.pick("在访达中显示", "Reveal in Finder"), systemImage: "folder")
            }
        case .snippet:
            Button { viewModel.executeCandidate(candidate) } label: { Label("复制短语", systemImage: "doc.on.doc") }
            pinToHomeSubmenu(for: candidate)
        default:
            Button { viewModel.executeCandidate(candidate) } label: { Label("执行", systemImage: "play.fill") }
        }
    }

    @ViewBuilder
    private func pinToHomeSubmenu(for candidate: LauncherCandidate) -> some View {
        if viewModel.homeLaunchItem(from: candidate) != nil {
            Menu(L10n.pick("钉到启动页", "Pin to Home")) {
                Button {
                    viewModel.pinCandidateToHome(candidate, destination: .bento)
                } label: {
                    Label(L10n.pick("Bento 大磁贴区", "Bento Tiles"), systemImage: "square.grid.3x2.fill")
                }
                Button {
                    viewModel.pinCandidateToHome(candidate, destination: .dock)
                } label: {
                    Label(L10n.pick("混合高频坞", "Omni Dock"), systemImage: "dock.rectangle")
                }
                let shelves = viewModel.homeLayoutConfig.activeProfile.pillShelves
                ForEach(shelves) { shelf in
                    Button {
                        viewModel.pinCandidateToHome(candidate, destination: .shelf(shelf.id), shelfTitle: shelf.title)
                    } label: {
                        Label(L10n.pick("胶囊架：\(shelf.title)", "Shelf: \(shelf.title)"), systemImage: shelf.symbol)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func contextPluginSubmenu(_ ctx: PluginContextPayload) -> some View {
        let matched = PluginContextMatcher.matchingPlugins(in: viewModel.plugins, for: ctx)
        if !matched.isEmpty {
            Menu("发送到扩展插件") {
                ForEach(matched) { plugin in
                    Button(plugin.displayName) { viewModel.runPluginWithContext(plugin, context: ctx) }
                }
            }
        }
    }
}

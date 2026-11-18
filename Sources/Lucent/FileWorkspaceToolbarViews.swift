import LucentCore
import SwiftUI

struct WorkspaceTopToolbar: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ExplorerLayoutMode.allCases) { mode in
                    Button(mode.title) { viewModel.layoutMode = mode }
                        .buttonStyle(GlassPillButtonStyle(prominent: viewModel.layoutMode == mode))
                }
                Button("新建标签") { viewModel.addTab(pane: viewModel.activePane) }.buttonStyle(GlassPillButtonStyle())
                Button("新建目录") { viewModel.beginCreateFolder(in: viewModel.activePane) }
                    .buttonStyle(GlassPillButtonStyle()).help("在此目录新建文件夹 (⇧⌘N)")
                Button("批量重命名") { viewModel.showBatchRenameSheet = true }.buttonStyle(GlassPillButtonStyle())
                Button("秒搜目录") { viewModel.openQuickDirectorySearchFromWorkspace() }
                    .buttonStyle(GlassPillButtonStyle()).help("在快捷台中秒搜此目录 (⌥⌘F)")

                Spacer(minLength: 8)
                Button { viewModel.showWorkspacePreview.toggle() } label: {
                    Label(L10n.pick("预览栏", "Preview"), systemImage: "sidebar.right")
                }
                .buttonStyle(GlassPillButtonStyle(prominent: viewModel.showWorkspacePreview))
                .help("展开或收起右侧文件实时预览栏")
                Button("快捷台 (⌥Space)") { viewModel.showOverlay(filter: .all) }.buttonStyle(GlassPillButtonStyle())
                Button("流量 (⌥N)") { viewModel.openRoute(.networkMonitor) }.buttonStyle(GlassPillButtonStyle())
                Button("截图 (⌥A)") { viewModel.captureAndPinScreenshot() }.buttonStyle(GlassPillButtonStyle(prominent: true))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .liquidGlassCard(cornerRadius: LiquidRadii.bento)
    }
}

struct WorkspacePaneHeaderToolbar: View {
    @ObservedObject var viewModel: AppViewModel
    let pane: PaneSide
    let state: PaneState
    @FocusState private var isSearchFieldFocused: Bool

    private var abbreviatedPath: String {
        let raw = state.currentDirectory.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if raw == home { return "~" }
        return raw.hasPrefix(home + "/") ? "~" + raw.dropFirst(home.count) : raw
    }

    var body: some View {
        VStack(spacing: 6) {
            tabAndPathRow
            navigationAndControlsRow
        }
        .onChange(of: viewModel.workspaceSearchFocusToken) { _, _ in
            if viewModel.activePane == pane {
                isSearchFieldFocused = true
            }
        }
    }

    private var tabAndPathRow: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(state.tabs) { tab in
                        HStack(spacing: 4) {
                            Button(tab.title) { viewModel.activePane = pane; viewModel.selectTab(tab.id, in: pane) }
                                .buttonStyle(GlassPillButtonStyle(prominent: tab.id == state.activeTabID, compact: true))
                            if state.tabs.count > 1 {
                                Button { viewModel.closeTab(tab.id, in: pane) } label: {
                                    Image(systemName: "xmark.circle.fill").font(.caption2).foregroundStyle(.secondary)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    Button { viewModel.activePane = pane; viewModel.addTab(pane: pane) } label: {
                        Image(systemName: "plus").font(.system(size: 10, weight: .bold)).foregroundStyle(LiquidColors.textSecondary)
                            .frame(width: 22, height: 22).background(LiquidColors.pillSurface, in: Circle())
                            .overlay { Circle().strokeBorder(LiquidColors.pillBorder, lineWidth: 0.7) }
                    }.buttonStyle(.plain).help("新建标签页")
                }
            }
            Spacer(minLength: 6)
            HStack(spacing: 4) {
                Image(systemName: "folder").font(.system(size: 10, weight: .semibold)).foregroundStyle(LiquidColors.textSecondary)
                Text(abbreviatedPath).font(.caption2.monospaced()).foregroundStyle(LiquidColors.textSecondary)
                    .lineLimit(1).truncationMode(.head)
            }
            .padding(.horizontal, 8).padding(.vertical, 3.5)
            .background(LiquidColors.pillSurface.opacity(0.65), in: Capsule())
            .help(state.currentDirectory.path)
        }
    }

    private var navigationAndControlsRow: some View {
        let isDual = viewModel.layoutMode == .dual
        return HStack(spacing: isDual ? 5 : 6) {
            navIconPill(symbol: "chevron.left", disabled: state.history.isEmpty, compact: isDual) {
                viewModel.activePane = pane; viewModel.goBack(pane: pane)
            }
            navIconPill(symbol: "arrow.up", compact: isDual) {
                viewModel.activePane = pane; viewModel.navigate(pane: pane, to: state.currentDirectory.deletingLastPathComponent())
            }
            navIconPill(symbol: state.isScanning ? "hourglass" : "arrow.clockwise", compact: isDual, helpText: "强制重新扫描目录") {
                viewModel.activePane = pane; viewModel.refreshDirectory(pane: pane, forceRescan: true)
            }
            navIconPill(symbol: "folder.badge.plus", compact: isDual, helpText: "在此目录新建文件夹 (⇧⌘N)") {
                viewModel.beginCreateFolder(in: pane)
            }

            paneSearchBar(isDual: isDual)
            displayModeStrip
            sortControls(isDual: isDual)
        }
    }

    private func paneSearchBar(isDual: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(.secondary)
            TextField(
                isDual ? "搜索文件 (⌘F)…" : "搜索文件名 / 拼音 / .mp4 (⌘F)…",
                text: Binding(
                    get: { state.filterText },
                    set: { text in viewModel.updateWorkspaceFilterText(text, in: pane) }
                )
            )
            .focused($isSearchFieldFocused)
            .textFieldStyle(.plain)
            .font(.caption)
            .onExitCommand {
                if !state.filterText.isEmpty { viewModel.updateWorkspaceFilterText("", in: pane) }
                isSearchFieldFocused = false
            }

            if state.isSearchingSubfolders {
                ProgressView().controlSize(.mini)
            }
            Button {
                viewModel.toggleWorkspaceRecursiveSearch(in: pane)
            } label: {
                Text(isDual ? "子级" : "含子目录")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(state.recursiveSearch ? Color.white : LiquidColors.textSecondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(state.recursiveSearch ? Color.accentColor.opacity(0.85) : LiquidColors.pillSurface, in: Capsule())
            }
            .buttonStyle(.plain)
            .help("开启后自动递归搜索当前目录下的所有子文件夹")

            if !state.filterText.isEmpty {
                Button { viewModel.updateWorkspaceFilterText("", in: pane) } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .frame(minWidth: isDual ? 112 : 164, maxWidth: .infinity)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(LiquidColors.pillBorder, lineWidth: 0.7) }
    }

    private func navIconPill(
        symbol: String, disabled: Bool = false, prominent: Bool = false, compact: Bool = false, helpText: String? = nil, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.caption.weight(.semibold))
                .foregroundStyle(prominent ? Color.white : LiquidColors.textPrimary)
                .padding(.horizontal, compact ? 7.5 : 10).padding(.vertical, 5)
                .background {
                    if prominent { Capsule().fill(LiquidColors.accentGradient) } else { Capsule().fill(LiquidColors.pillSurface) }
                }
                .overlay { Capsule().strokeBorder(LiquidColors.pillBorder, lineWidth: 0.75) }
        }
        .buttonStyle(.plain).disabled(disabled).opacity(disabled ? 0.45 : 1.0).help(helpText ?? "")
    }

    private var displayModeStrip: some View {
        HStack(spacing: 2) {
            ForEach(WorkspaceDisplayMode.allCases) { mode in
                Button {
                    viewModel.activePane = pane; viewModel.mutatePane(pane) { $0.displayMode = mode }
                } label: {
                    Image(systemName: mode.symbolName).font(.caption)
                        .foregroundStyle(state.displayMode == mode ? Color.white : LiquidColors.textSecondary)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(state.displayMode == mode ? Color.accentColor : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain).help("\(mode.title)视图")
            }
        }
        .padding(2).background(.ultraThinMaterial, in: Capsule())
    }

    private func sortControls(isDual: Bool) -> some View {
        HStack(spacing: isDual ? 4 : 5) {
            Menu {
                ForEach(SortField.allCases) { field in
                    Button {
                        viewModel.mutatePane(pane) { $0.sortField = field }; viewModel.refreshDirectory(pane: pane)
                    } label: {
                        if state.sortField == field { Label(field.title, systemImage: "checkmark") } else { Text(field.title) }
                    }
                }
                Divider()
                Button {
                    viewModel.mutatePane(pane) { $0.foldersFirst.toggle() }; viewModel.refreshDirectory(pane: pane)
                } label: { Label("文件夹置顶", systemImage: state.foldersFirst ? "checkmark" : "folder") }
                Button {
                    viewModel.mutatePane(pane) { $0.showHidden.toggle() }
                    viewModel.refreshDirectory(pane: pane)
                    viewModel.refreshWorkspaceSubfolderSearch(for: pane)
                } label: { Label("显示隐藏文件", systemImage: state.showHidden ? "checkmark" : "eye") }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.up.arrow.down").font(.system(size: 10, weight: .semibold))
                    Text(state.sortField.title).font(.caption.weight(.semibold))
                    Image(systemName: "chevron.down").font(.system(size: 8.5, weight: .bold)).foregroundStyle(LiquidColors.textSecondary)
                }
                .foregroundStyle(LiquidColors.textPrimary).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, isDual ? 8.5 : 10).padding(.vertical, 5)
                .background(LiquidColors.pillSurface, in: Capsule(style: .continuous))
                .overlay { Capsule(style: .continuous).strokeBorder(LiquidColors.pillBorder, lineWidth: 0.8) }
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize(horizontal: true, vertical: false)

            navIconPill(
                symbol: state.sortOrder == .ascending ? "arrow.up" : "arrow.down",
                compact: isDual, helpText: state.sortOrder == .ascending ? "升序排列" : "降序排列"
            ) {
                viewModel.mutatePane(pane) { $0.sortOrder = $0.sortOrder.toggled }; viewModel.refreshDirectory(pane: pane)
            }

            if !isDual {
                navIconPill(symbol: state.foldersFirst ? "folder.badge.gearshape" : "folder", prominent: state.foldersFirst, helpText: "文件夹置顶显示") {
                    viewModel.mutatePane(pane) { $0.foldersFirst.toggle() }; viewModel.refreshDirectory(pane: pane)
                }
                navIconPill(symbol: state.showHidden ? "eye.fill" : "eye.slash", prominent: state.showHidden, helpText: "显示隐藏文件") {
                    viewModel.mutatePane(pane) { $0.showHidden.toggle() }
                    viewModel.refreshDirectory(pane: pane)
                    viewModel.refreshWorkspaceSubfolderSearch(for: pane)
                }
            }
        }
    }
}

struct WorkspacePaneFooterStatusBar: View {
    let state: PaneState
    var isDual: Bool = false
    let visibleCount: Int
    let selectionSummary: String?
    let serviceMessage: String?

    var body: some View {
        HStack(spacing: 8) {
            let isFiltered = !state.filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.mediaFilter != .all
            let countLabel = !isFiltered ? "共 \(state.entries.count) 项" : "匹配 \(visibleCount) 项"
            let selPart = selectionSummary.map { " · \($0)" } ?? ""
            let detailPart = isDual ? "" : " · \(state.displayMode.title)视图 · 按\(state.sortField.title)\(state.sortOrder == .ascending ? "升序" : "降序")"
            Text("\(countLabel)\(selPart)\(detailPart)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(selectionSummary == nil ? Color.secondary : LiquidColors.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 6)
            if let serviceMessage, !serviceMessage.isEmpty {
                Text(serviceMessage).font(.caption2).foregroundStyle(.cyan).lineLimit(1).truncationMode(.tail)
            } else if let cap = state.volumeSummary?.capacityText {
                Text(cap).font(.caption2.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 4)
    }
}

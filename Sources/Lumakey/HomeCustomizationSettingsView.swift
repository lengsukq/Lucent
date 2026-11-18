import AppKit
import LumakeyCore
import SwiftUI

@MainActor
private final class HomeSettingsUIState: ObservableObject {
    @Published var editorContext: HomeItemEditorContext? = nil
    @Published var newProfileName: String = ""
    @Published var newShelfTitle: String = ""
    @Published var inspectingDestination: HomeItemDestination = .bento
}

struct HomeCustomizationSettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @StateObject private var ui = HomeSettingsUIState()

    private var config: HomeLayoutConfig { viewModel.homeLayoutConfig }
    private var profile: HomeProfile { config.activeProfile }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionHeroHeader(
                    symbol: "square.grid.3x2.fill", topColor: .cyan, bottomColor: .indigo,
                    title: L10n.pick("启动页布局、书签架与多场景编排", "Home Page Layout, Shelves & Profiles"),
                    subtitle: L10n.pick(
                        "自由编排 Bento 磁贴、混合高频坞与分组书签胶囊架，支持多场景 Profile 切换与 lumakey-mcp 智能定制。",
                        "Customize Bento tiles, Omni Dock, and bookmark shelves across profiles or via lumakey-mcp."
                    )
                ) {
                    HStack(spacing: 8) {
                        if config.lastUndoProfile != nil {
                            Button(L10n.pick("撤回修改", "Undo")) {
                                viewModel.mutateHomeLayout { _ = $0.undoLastChange() }
                            }
                            .buttonStyle(GlassPillButtonStyle())
                        }
                        Button(L10n.pick("呼出预览 (⌥Space)", "Preview (⌥Space)")) {
                            viewModel.showOverlay(filter: .all)
                        }
                        .buttonStyle(GlassPillButtonStyle(prominent: true))
                    }
                }

                profilesAndPresetsCard
                sectionsAndDensityCard
                shelvesAndItemsManagerCard
            }
            .padding(.trailing, 4)
        }
        .sheet(item: $ui.editorContext) { ctx in
            HomeItemEditorSheet(viewModel: viewModel, context: ctx) { ui.editorContext = nil }
        }
    }

    private var profilesAndPresetsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(L10n.pick("多场景 Profile 与官方预设", "Scene Profiles & Presets"), systemImage: "person.2.crop.square.stack.fill")
                    .font(.callout.weight(.semibold))
                Spacer()
                if config.profiles.count > 1 {
                    Button(role: .destructive) { viewModel.mutateHomeLayout { try? _ = $0.deleteProfile(id: profile.id) } } label: {
                        Text(L10n.pick("删除当前场景", "Delete Profile")).font(.caption2)
                    }.buttonStyle(GlassPillButtonStyle(compact: true))
                }
            }

            FlowWrapLayout(horizontalSpacing: 7, verticalSpacing: 7) {
                ForEach(config.profiles) { p in
                    Button { viewModel.mutateHomeLayout { _ = $0.selectProfile(id: p.id) } } label: {
                        Label(p.name, systemImage: p.symbol)
                    }.buttonStyle(GlassPillButtonStyle(prominent: p.id == config.activeProfileID, compact: true))
                }
            }

            HStack(spacing: 8) {
                GlassInputField(symbol: "plus.circle", placeholder: L10n.pick("新建场景名称（如：工作模式 / 专注写作）", "New profile name (e.g. Work / Focus)"), text: $ui.newProfileName)
                Button(L10n.pick("新建并切换", "Create Profile")) {
                    let clean = ui.newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !clean.isEmpty else { return }
                    viewModel.mutateHomeLayout { _ = try? $0.createProfile(name: clean, symbol: "sparkles", preset: .balanced) }
                    ui.newProfileName = ""
                }.buttonStyle(GlassPillButtonStyle(compact: true))
            }

            Divider().opacity(0.22)

            HStack(spacing: 7) {
                Text(L10n.pick("一键套用预设：", "Apply Preset:")).font(.caption2.weight(.semibold)).foregroundStyle(LiquidColors.textSecondary)
                ForEach(HomeLayoutPreset.allCases) { preset in
                    Button(preset.title) { viewModel.mutateHomeLayout { $0.applyPreset(preset) } }
                        .buttonStyle(GlassPillButtonStyle(compact: true)).help(preset.subtitle)
                }
                Spacer()
            }
        }
        .padding(14).liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
    }

    private var sectionsAndDensityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L10n.pick("四大分区显隐、顺序与网格密度", "Sections Visibility, Order & Density"), systemImage: "rectangle.3.group.fill")
                .font(.callout.weight(.semibold))

            FlowWrapLayout(horizontalSpacing: 16, verticalSpacing: 8) {
                HStack(spacing: 6) {
                    Text(L10n.pick("Bento 列数：", "Bento Columns:")).font(.caption2.weight(.semibold)).foregroundStyle(LiquidColors.textSecondary)
                    ForEach(HomeBentoColumns.allCases) { col in
                        Button(col.title) { viewModel.mutateHomeLayout { $0.activeProfile.bentoColumns = col } }
                            .buttonStyle(GlassPillButtonStyle(prominent: profile.bentoColumns == col, compact: true))
                    }
                }
                HStack(spacing: 6) {
                    Text(L10n.pick("高频坞容量：", "Dock Rows:")).font(.caption2.weight(.semibold)).foregroundStyle(LiquidColors.textSecondary)
                    ForEach([1, 2], id: \.self) { rows in
                        let title = rows == 1 ? L10n.pick("1 排 (8 格)", "1 Row (8)") : L10n.pick("2 排 (16 格)", "2 Rows (16)")
                        Button(title) { viewModel.mutateHomeLayout { $0.activeProfile.dockRows = rows } }
                            .buttonStyle(GlassPillButtonStyle(prominent: profile.dockRows == rows, compact: true))
                    }
                }
            }

            FlowWrapLayout(horizontalSpacing: 16, verticalSpacing: 8) {
                HStack(spacing: 6) {
                    Text(L10n.pick("混合坞补位：", "Dock Fill:")).font(.caption2.weight(.semibold)).foregroundStyle(LiquidColors.textSecondary)
                    ForEach(HomeDockFillMode.allCases) { mode in
                        Button(mode.title) { viewModel.mutateHomeLayout { $0.activeProfile.dockFillMode = mode } }
                            .buttonStyle(GlassPillButtonStyle(prominent: profile.dockFillMode == mode, compact: true))
                    }
                }
                HStack(spacing: 7) {
                    Text(L10n.pick("精简底部状态栏重复按钮", "Compact footer bar")).font(.caption)
                    Toggle("", isOn: Binding(
                        get: { profile.compactFooterBar },
                        set: { val in viewModel.mutateHomeLayout { $0.activeProfile.compactFooterBar = val } }
                    )).toggleStyle(.switch).controlSize(.mini).labelsHidden()
                }
            }

            VStack(spacing: 5) {
                ForEach(Array(profile.sectionOrder.enumerated()), id: \.element.id) { idx, sec in
                    let vis = profile.isSectionVisible(sec)
                    HStack(spacing: 9) {
                        Image(systemName: sec.symbolName).foregroundStyle(vis ? LiquidColors.accentPrimary : .secondary).frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(sec.title).font(.caption.weight(.semibold))
                            Text(sec.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button { viewModel.mutateHomeLayout { $0.activeProfile.moveSection(sec, offset: -1) } } label: {
                            Image(systemName: "chevron.up").font(.system(size: 10, weight: .bold))
                        }.buttonStyle(.plain).disabled(idx == 0)
                        Button { viewModel.mutateHomeLayout { $0.activeProfile.moveSection(sec, offset: 1) } } label: {
                            Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                        }.buttonStyle(.plain).disabled(idx >= profile.sectionOrder.count - 1)
                        Toggle("", isOn: Binding(
                            get: { vis },
                            set: { on in viewModel.mutateHomeLayout { $0.activeProfile.setSectionVisible(sec, visible: on) } }
                        )).toggleStyle(.switch).controlSize(.mini).labelsHidden()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(LiquidColors.pillSurface.opacity(vis ? 0.6 : 0.28), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .padding(14).liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
    }

    private var shelvesAndItemsManagerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(L10n.pick("分区条目与分组书签架管理", "Items & Bookmark Shelves"), systemImage: "list.bullet.rectangle.portrait.fill")
                    .font(.callout.weight(.semibold))
                Spacer()
                Button(L10n.pick("+ 添加启动项", "+ Add Item")) {
                    ui.editorContext = HomeItemEditorContext(destination: ui.inspectingDestination)
                }.buttonStyle(GlassPillButtonStyle(prominent: true, compact: true))
            }

            FlowWrapLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                Button(L10n.pick("Bento 磁贴 (\(profile.bentoItems.count))", "Bento (\(profile.bentoItems.count))")) { ui.inspectingDestination = .bento }
                    .buttonStyle(GlassPillButtonStyle(prominent: ui.inspectingDestination == .bento, compact: true))
                Button(L10n.pick("混合坞已钉项 (\(profile.dockItems.count))", "Pinned Dock (\(profile.dockItems.count))")) { ui.inspectingDestination = .dock }
                    .buttonStyle(GlassPillButtonStyle(prominent: ui.inspectingDestination == .dock, compact: true))
                ForEach(profile.pillShelves) { shelf in
                    Button("\(shelf.title) (\(shelf.items.count))") { ui.inspectingDestination = .shelf(shelf.id) }
                        .buttonStyle(GlassPillButtonStyle(prominent: ui.inspectingDestination == .shelf(shelf.id), compact: true))
                }
                Button(L10n.pick("搜索词条 (\(profile.utilityChips.count))", "Chips (\(profile.utilityChips.count))")) { ui.inspectingDestination = .utilityChips }
                    .buttonStyle(GlassPillButtonStyle(prominent: ui.inspectingDestination == .utilityChips, compact: true))
            }

            HStack(spacing: 8) {
                GlassInputField(symbol: "bookmark.fill", placeholder: L10n.pick("新增书签/插件胶囊分组（如：AI 常用 / 团队文档）", "New shelf title (e.g. AI Tools / Team Docs)"), text: $ui.newShelfTitle)
                Button(L10n.pick("新建分组架", "Add Shelf")) {
                    let clean = ui.newShelfTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !clean.isEmpty, profile.pillShelves.count < 6 else { return }
                    let id = "shelf-\(UUID().uuidString.prefix(6).lowercased())"
                    viewModel.mutateHomeLayout {
                        $0.activeProfile.pillShelves.append(HomePillShelf(id: id, title: clean, symbol: "bookmark.fill", accentColor: "cyan"))
                    }
                    ui.inspectingDestination = .shelf(id)
                    ui.newShelfTitle = ""
                }.buttonStyle(GlassPillButtonStyle(compact: true))
            }

            let items = itemsForDestination(ui.inspectingDestination)
            if items.isEmpty {
                Text(L10n.pick("当前分组暂无手动固定项，点击右上角「+ 添加启动项」或在搜索结果右键一键钉入。", "No items in this section yet. Click '+ Add Item' or right-click any search result to pin."))
                    .font(.caption).foregroundStyle(.secondary).padding(.vertical, 6)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    let vis = viewModel.resolvedHomeVisual(for: item)
                    HStack(spacing: 9) {
                        if let iconURL = vis.customIconURL, let nsImg = IconCache.shared.pluginIcon(for: iconURL, pointSize: 18) {
                            Image(nsImage: nsImg).resizable().scaledToFit().frame(width: 17, height: 17)
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous)).frame(width: 18)
                        } else {
                            Image(systemName: vis.symbolName).foregroundStyle(PluginVisualPalette.tint(from: vis.accentColor)).frame(width: 18)
                        }
                        Text(vis.title).font(.caption.weight(.semibold)).lineLimit(1)
                        Text(vis.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Button { viewModel.mutateHomeLayout { _ = $0.moveItem(id: item.id, in: ui.inspectingDestination, offset: -1) } } label: {
                            Image(systemName: "chevron.up").font(.system(size: 10, weight: .bold))
                        }.buttonStyle(.plain).disabled(idx == 0)
                        Button { viewModel.mutateHomeLayout { _ = $0.moveItem(id: item.id, in: ui.inspectingDestination, offset: 1) } } label: {
                            Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                        }.buttonStyle(.plain).disabled(idx >= items.count - 1)
                        Button { ui.editorContext = HomeItemEditorContext(destination: ui.inspectingDestination, existingItem: item) } label: {
                            Image(systemName: "pencil").font(.caption)
                        }.buttonStyle(.plain)
                        Button(role: .destructive) { viewModel.mutateHomeLayout { _ = $0.removeItem(id: item.id, from: ui.inspectingDestination) } } label: {
                            Image(systemName: "trash").font(.caption).foregroundStyle(.orange)
                        }.buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5.5)
                    .background(LiquidColors.pillSurface.opacity(0.55), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
            }
        }
        .padding(14).liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
    }

    private func itemsForDestination(_ dest: HomeItemDestination) -> [HomeLaunchItem] {
        switch dest {
        case .bento: profile.bentoItems
        case .dock: profile.dockItems
        case .shelf(let id): profile.pillShelves.first(where: { $0.id == id })?.items ?? []
        case .utilityChips: profile.utilityChips
        case .utilityRight: profile.utilityRightItems
        }
    }
}

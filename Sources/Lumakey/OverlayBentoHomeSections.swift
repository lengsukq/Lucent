import AppKit
import LumakeyCore
import SwiftUI

extension OverlayBentoHomeView {
    @ViewBuilder
    var pillShelvesSection: some View {
        let visibleShelves = profile.pillShelves.filter { !$0.isHidden }
        VStack(alignment: .leading, spacing: 7) {
            ForEach(visibleShelves) { shelf in
                let items = viewModel.resolvedShelfItems(for: shelf)
                if !items.isEmpty || isEditingHome {
                    shelfRow(shelf: shelf, items: items)
                }
            }
        }
    }

    private func shelfRow(shelf: HomePillShelf, items: [HomeLaunchItem]) -> some View {
        let shelfTint = PluginVisualPalette.tint(from: shelf.accentColor, fallback: .orange)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                Label(shelf.title, systemImage: shelf.symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(shelfTint)
                ForEach(items) { item in
                    let vis = viewModel.resolvedHomeVisual(for: item)
                    let itemTint = PluginVisualPalette.tint(from: vis.accentColor, fallback: shelfTint)
                    Button {
                        if isEditingHome && !item.id.hasPrefix("legacy-") {
                            activateShelfEditor(shelfID: shelf.id, item: item)
                        } else {
                            viewModel.executeHomeLaunchItem(item)
                        }
                    } label: {
                        HStack(spacing: 5.5) {
                            if let iconURL = vis.customIconURL,
                               let nsImg = IconCache.shared.pluginIcon(for: iconURL, pointSize: 14) {
                                Image(nsImage: nsImg).resizable().scaledToFit().frame(width: 13, height: 13)
                                    .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                            } else {
                                Image(systemName: vis.symbolName)
                                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(itemTint)
                            }
                            Text(vis.title)
                                .font(.caption.weight(.semibold)).foregroundStyle(LiquidColors.textPrimary).lineLimit(1)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(LiquidColors.pillSurface, in: Capsule(style: .continuous))
                        .overlay { Capsule(style: .continuous).strokeBorder(itemTint.opacity(0.35), lineWidth: 0.8) }
                    }
                    .buttonStyle(LiquidBentoTileStyle(cornerRadius: 999))
                    .help(vis.subtitle)
                    .contextMenu { shelfItemContextMenu(item, shelf: shelf) }
                }
                if isEditingHome {
                    Button("+") { activateShelfEditor(shelfID: shelf.id, item: nil) }
                        .buttonStyle(GlassPillButtonStyle(compact: true))
                }
            }
            .padding(.horizontal, 4)
        }
    }

    var utilityStripSection: some View {
        HStack(spacing: 8) {
            if !profile.utilityChips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Text(L10n.pick("试试输入", "Try")).font(.caption2.weight(.semibold)).foregroundStyle(LiquidColors.textSecondary)
                        ForEach(profile.utilityChips) { chip in
                            let vis = viewModel.resolvedHomeVisual(for: chip)
                            Button(vis.title) { viewModel.executeHomeLaunchItem(chip) }
                                .buttonStyle(GlassPillButtonStyle(compact: true))
                                .contextMenu { itemContextMenu(chip, in: .utilityChips) }
                        }
                    }
                }
            }
            Spacer(minLength: 6)
            ForEach(profile.utilityRightItems) { item in
                let vis = viewModel.resolvedHomeVisual(for: item)
                Button { viewModel.executeHomeLaunchItem(item) } label: {
                    Label(vis.title, systemImage: vis.symbolName)
                }
                .buttonStyle(GlassPillButtonStyle(compact: true))
                .contextMenu { itemContextMenu(item, in: .utilityRight) }
            }
            Button {
                withAnimation(LiquidMotion.snappySpring) { toggleInlineEditMode() }
            } label: {
                Label(L10n.pick("定制", "Customize"), systemImage: "slider.horizontal.below.square.filled.and.square")
            }
            .buttonStyle(GlassPillButtonStyle(prominent: isEditingHome, compact: true))
        }
    }

    @ViewBuilder
    var homeBackgroundContextMenu: some View {
        Button {
            withAnimation(LiquidMotion.snappySpring) { toggleInlineEditMode() }
        } label: {
            Label(
                isEditingHome ? L10n.pick("完成主页编辑", "Finish Editing") : L10n.pick("就地编辑启动页", "Edit Home Inline"),
                systemImage: "slider.horizontal.3"
            )
        }
        Button { openEditor(for: .bento, existing: nil) } label: {
            Label(L10n.pick("添加磁贴 / 插件 / 书签…", "Add Tile / Plugin / Bookmark…"), systemImage: "plus.circle")
        }
        Menu(L10n.pick("切换主页预设", "Apply Preset")) {
            ForEach(HomeLayoutPreset.allCases) { preset in
                Button(preset.title) { viewModel.mutateHomeLayout { $0.applyPreset(preset) } }
            }
        }
        if config.profiles.count > 1 {
            Menu(L10n.pick("切换场景 Profile", "Switch Profile")) {
                ForEach(config.profiles) { p in
                    Button(p.id == config.activeProfileID ? "✓ \(p.name)" : p.name) {
                        viewModel.mutateHomeLayout { _ = $0.selectProfile(id: p.id) }
                    }
                }
            }
        }
        Divider()
        Button { viewModel.openRoute(.settings(.homeLayout)) } label: {
            Label(L10n.pick("打开启动页完整设置…", "Open Home Layout Settings…"), systemImage: "gearshape")
        }
    }

    @ViewBuilder
    func itemContextMenu(_ item: HomeLaunchItem, in dest: HomeItemDestination) -> some View {
        Button { viewModel.executeHomeLaunchItem(item) } label: {
            Label(L10n.pick("立即打开 / 执行", "Open / Run"), systemImage: "play.fill")
        }
        Button { openEditor(for: dest, existing: item) } label: {
            Label(L10n.pick("编辑标题、图标与配色…", "Edit Title, Icon & Color…"), systemImage: "pencil")
        }
        Button { viewModel.mutateHomeLayout { _ = $0.moveItem(id: item.id, in: dest, offset: -1) } } label: {
            Label(L10n.pick("前移", "Move Earlier"), systemImage: "arrow.left")
        }
        Button { viewModel.mutateHomeLayout { _ = $0.moveItem(id: item.id, in: dest, offset: 1) } } label: {
            Label(L10n.pick("后移", "Move Later"), systemImage: "arrow.right")
        }
        if dest != .dock {
            Button {
                viewModel.mutateHomeLayout { try? $0.upsertItem(item, in: .dock) }
            } label: {
                Label(L10n.pick("同时钉到混合高频坞", "Also Pin to Dock"), systemImage: "dock.rectangle")
            }
        }
        Divider()
        Button(role: .destructive) {
            viewModel.mutateHomeLayout { _ = $0.removeItem(id: item.id, from: dest) }
        } label: {
            Label(L10n.pick("从启动页移除", "Remove from Home"), systemImage: "trash")
        }
    }

    @ViewBuilder
    func dockSlotContextMenu(_ slot: HomeResolvedDockSlot) -> some View {
        Button { viewModel.executeHomeLaunchItem(slot.item) } label: {
            Label(L10n.pick("打开", "Open"), systemImage: "play.fill")
        }
        Button { viewModel.toggleHomeDockSlotPin(slot) } label: {
            Label(
                slot.isExplicitlyPinned ? L10n.pick("取消钉住", "Unpin") : L10n.pick("固定在高频坞", "Pin to Dock"),
                systemImage: slot.isExplicitlyPinned ? "pin.slash" : "pin.fill"
            )
        }
        if slot.isExplicitlyPinned {
            Button { openEditor(for: .dock, existing: slot.item) } label: {
                Label(L10n.pick("编辑名称与图标…", "Edit Appearance…"), systemImage: "pencil")
            }
            Button { viewModel.mutateHomeLayout { _ = $0.moveItem(id: slot.item.id, in: .dock, offset: -1) } } label: {
                Label(L10n.pick("左移", "Move Left"), systemImage: "arrow.left")
            }
            Button { viewModel.mutateHomeLayout { _ = $0.moveItem(id: slot.item.id, in: .dock, offset: 1) } } label: {
                Label(L10n.pick("右移", "Move Right"), systemImage: "arrow.right")
            }
        }
        Button {
            var copy = slot.item
            if copy.id.hasPrefix("auto-app:") { copy.id = "tile-\(UUID().uuidString.prefix(6).lowercased())" }
            viewModel.mutateHomeLayout { try? $0.upsertItem(copy, in: .bento) }
        } label: {
            Label(L10n.pick("做成顶部大磁贴", "Promote to Bento Tile"), systemImage: "square.grid.3x2.fill")
        }
        if case .nativeApp(let path, _) = slot.item.target {
            Divider()
            Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) } label: {
                Label(L10n.pick("在访达中显示", "Show in Finder"), systemImage: "folder")
            }
        }
    }

    @ViewBuilder
    private func shelfItemContextMenu(_ item: HomeLaunchItem, shelf: HomePillShelf) -> some View {
        Button { viewModel.executeHomeLaunchItem(item) } label: {
            Label(L10n.pick("立即执行", "Run Now"), systemImage: "play.fill")
        }
        if !item.id.hasPrefix("legacy-") {
            Button { activateShelfEditor(shelfID: shelf.id, item: item) } label: {
                Label(L10n.pick("编辑胶囊项…", "Edit Item…"), systemImage: "pencil")
            }
            Button { viewModel.mutateHomeLayout { _ = $0.moveItem(id: item.id, in: .shelf(shelf.id), offset: -1) } } label: {
                Label(L10n.pick("左移", "Move Left"), systemImage: "arrow.left")
            }
            Button { viewModel.mutateHomeLayout { _ = $0.moveItem(id: item.id, in: .shelf(shelf.id), offset: 1) } } label: {
                Label(L10n.pick("右移", "Move Right"), systemImage: "arrow.right")
            }
        }
        Divider()
        Button(role: .destructive) { viewModel.removeLegacyOrHomeShelfItem(item, shelfID: shelf.id) } label: {
            Label(L10n.pick("移除", "Remove"), systemImage: "trash")
        }
    }
}

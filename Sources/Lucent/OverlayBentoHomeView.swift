import AppKit
import LucentCore
import SwiftUI

@MainActor
final class OverlayHomeUIState: ObservableObject {
    @Published var isEditingHome: Bool = false
    @Published var editorContext: HomeItemEditorContext? = nil
}

struct OverlayBentoHomeView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var usageTracker = AppUsageTrackerController.shared
    @StateObject var uiState = OverlayHomeUIState()

    var isEditingHome: Bool { uiState.isEditingHome }
    var config: HomeLayoutConfig { viewModel.homeLayoutConfig }
    var profile: HomeProfile { config.activeProfile }

    func toggleInlineEditMode() {
        uiState.isEditingHome.toggle()
    }

    func openEditor(for destination: HomeItemDestination, existing: HomeLaunchItem?) {
        uiState.editorContext = HomeItemEditorContext(destination: destination, existingItem: existing)
    }

    func activateShelfEditor(shelfID: String, item: HomeLaunchItem?) {
        uiState.editorContext = HomeItemEditorContext(destination: .shelf(shelfID), existingItem: item)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 11) {
                if config.profiles.count > 1 || isEditingHome {
                    topProfileAndEditStrip
                }
                ForEach(profile.visibleSections) { section in
                    sectionView(for: section)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(WindowDragRegion())
        .contextMenu { homeBackgroundContextMenu }
        .sheet(item: $uiState.editorContext) { ctx in
            HomeItemEditorSheet(viewModel: viewModel, context: ctx) { uiState.editorContext = nil }
        }
        .onAppear { usageTracker.ensureSystemProbe(for: viewModel.installedApps) }
        .onChange(of: viewModel.installedApps) { _, apps in usageTracker.ensureSystemProbe(for: apps) }
    }

    private var topProfileAndEditStrip: some View {
        HStack(spacing: 6) {
            ForEach(config.profiles) { p in
                let active = p.id == config.activeProfileID
                Button {
                    withAnimation(LiquidMotion.snappySpring) {
                        viewModel.mutateHomeLayout { _ = $0.selectProfile(id: p.id) }
                    }
                } label: {
                    Label(p.name, systemImage: p.symbol)
                }
                .buttonStyle(GlassPillButtonStyle(prominent: active, compact: true))
            }
            Spacer(minLength: 4)
            if isEditingHome {
                Menu(L10n.pick("套用预设", "Presets")) {
                    ForEach(HomeLayoutPreset.allCases) { preset in
                        Button(preset.title) { viewModel.mutateHomeLayout { $0.applyPreset(preset) } }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                if config.lastUndoProfile != nil {
                    Button(L10n.pick("撤回", "Undo")) {
                        viewModel.mutateHomeLayout { _ = $0.undoLastChange() }
                    }
                    .buttonStyle(GlassPillButtonStyle(compact: true))
                }
                Button(L10n.pick("+ 添加项", "+ Add")) { openEditor(for: .bento, existing: nil) }
                    .buttonStyle(GlassPillButtonStyle(compact: true))
                Button(L10n.pick("更多设置", "Settings")) { viewModel.openRoute(.settings(.homeLayout)) }
                    .buttonStyle(GlassPillButtonStyle(compact: true))
                Button(L10n.pick("完成", "Done")) {
                    withAnimation(LiquidMotion.snappySpring) { uiState.isEditingHome = false }
                }
                .buttonStyle(GlassPillButtonStyle(prominent: true, compact: true))
            } else {
                Button {
                    withAnimation(LiquidMotion.snappySpring) { uiState.isEditingHome = true }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(GlassPillButtonStyle(compact: true))
                .help(L10n.pick("就地编辑当前主页布局", "Edit Home Layout"))
            }
        }
    }

    @ViewBuilder
    private func sectionView(for section: HomeSectionKind) -> some View {
        switch section {
        case .bentoGrid: bentoGridSection
        case .omniDock: omniDockSection
        case .pillShelves: pillShelvesSection
        case .utilityStrip: utilityStripSection
        }
    }

    private var bentoGridSection: some View {
        let cols = profile.bentoColumns.rawValue
        let compact = cols == 4
        let cardHeight: CGFloat = compact ? 64 : 74
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: cols), spacing: 10) {
            ForEach(Array(profile.bentoItems.enumerated()), id: \.element.id) { index, item in
                bentoTileCard(item: item, index: index, compact: compact, height: cardHeight)
            }
            if isEditingHome && profile.bentoItems.count < 16 {
                Button { openEditor(for: .bento, existing: nil) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(LiquidColors.accentPrimary)
                        Text(L10n.pick("添加磁贴 / 书签", "Add Tile"))
                            .font(.caption.weight(.semibold)).foregroundStyle(LiquidColors.textSecondary)
                    }
                    .frame(height: cardHeight).frame(maxWidth: .infinity)
                    .liquidGlassCard(cornerRadius: LiquidRadii.bento)
                }
                .buttonStyle(LiquidBentoTileStyle(cornerRadius: LiquidRadii.bento))
            }
        }
    }

    private func bentoTileCard(item: HomeLaunchItem, index: Int, compact: Bool, height: CGFloat) -> some View {
        let vis = viewModel.resolvedHomeVisual(for: item)
        let pair = PluginVisualPalette.colors(accentColor: vis.accentColor, isBuiltin: true)
        return Button {
            if isEditingHome { openEditor(for: .bento, existing: item) }
            else { viewModel.executeHomeLaunchItem(item) }
        } label: {
            HStack(alignment: .center, spacing: compact ? 9 : 12) {
                leadingVisualIcon(vis, size: compact ? 36 : 42, colors: pair)
                VStack(alignment: .leading, spacing: 2.5) {
                    Text(vis.title).font((compact ? Font.caption : Font.callout).weight(.semibold))
                        .foregroundStyle(LiquidColors.textPrimary).lineLimit(1)
                    Text(vis.subtitle).font(.caption2).foregroundStyle(LiquidColors.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 2)
                if isEditingHome {
                    HStack(spacing: 3) {
                        Button { viewModel.mutateHomeLayout { _ = $0.moveItem(id: item.id, in: .bento, offset: -1) } } label: {
                            Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                        }.buttonStyle(.plain)
                        Button { viewModel.mutateHomeLayout { _ = $0.moveItem(id: item.id, in: .bento, offset: 1) } } label: {
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                        }.buttonStyle(.plain)
                        Button { viewModel.mutateHomeLayout { _ = $0.removeItem(id: item.id, from: .bento) } } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(.orange)
                        }.buttonStyle(.plain)
                    }
                } else if let hint = vis.hotkeyHint ?? (index < 9 ? "⌘\(index + 1)" : nil) {
                    LiquidKeyHintBadge(keyText: hint)
                }
            }
            .padding(.horizontal, compact ? 10 : 13)
            .frame(height: height).frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlassCard(cornerRadius: LiquidRadii.bento)
            .contentShape(RoundedRectangle(cornerRadius: LiquidRadii.bento, style: .continuous))
        }
        .buttonStyle(LiquidBentoTileStyle(cornerRadius: LiquidRadii.bento))
        .liquidHoverLift(cornerRadius: LiquidRadii.bento, scale: 1.015, staggerDelay: Double(index) * 0.018)
        .contextMenu { itemContextMenu(item, in: .bento) }
    }

    private var omniDockSection: some View {
        let slots = viewModel.resolvedHomeDockSlots()
        let pinnedCount = slots.filter(\.isExplicitlyPinned).count
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(L10n.pick("混合高频坞（支持本机应用 · 自制插件 · 网页书签 · 目录）", "Omni Dock (Apps · Plugins · Bookmarks · Folders)"))
                    .font(.caption.weight(.semibold)).foregroundStyle(LiquidColors.textSecondary).lineLimit(1)
                Spacer()
                if isEditingHome {
                    Button(L10n.pick("+ 钉入坞栏", "+ Pin to Dock")) { openEditor(for: .dock, existing: nil) }
                        .buttonStyle(GlassPillButtonStyle(compact: true))
                } else {
                    Text(L10n.pick("已钉 \(pinnedCount) · 共 \(slots.count) 格", "Pinned \(pinnedCount) · \(slots.count) slots"))
                        .font(.caption2.monospacedDigit()).foregroundStyle(LiquidColors.textSecondary)
                }
            }
            .padding(.horizontal, 4)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 6) {
                ForEach(slots) { slot in dockSlotTile(slot) }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .liquidGlassCard(cornerRadius: LiquidRadii.bento)
        }
    }

    private func dockSlotTile(_ slot: HomeResolvedDockSlot) -> some View {
        let vis = slot.visual
        let pinned = slot.isExplicitlyPinned
        let pair = PluginVisualPalette.colors(accentColor: vis.accentColor, isBuiltin: false)
        let tileShape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button {
            if isEditingHome && pinned { openEditor(for: .dock, existing: slot.item) }
            else { viewModel.executeHomeLaunchItem(slot.item) }
        } label: {
            VStack(spacing: 4) {
                leadingVisualIcon(vis, size: 36, colors: pair)
                Text(vis.title).font(.caption2.weight(.medium)).foregroundStyle(LiquidColors.textPrimary).lineLimit(1)
                Text(vis.badgeText ?? (pinned ? L10n.pick("已钉住", "Pinned") : " "))
                    .font(.system(size: 9.5, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(pinned ? Color.orange : LiquidColors.textSecondary.opacity(0.85)).lineLimit(1)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 5.5).padding(.horizontal, 3)
            .background(LiquidColors.pillSurface.opacity(pinned ? 0.50 : 0.34), in: tileShape)
            .overlay { if pinned { tileShape.strokeBorder(Color.orange.opacity(0.38), lineWidth: 0.85) } }
            .contentShape(tileShape)
        }
        .buttonStyle(LiquidBentoTileStyle(cornerRadius: 12))
        .liquidHoverLift(cornerRadius: 12, scale: 1.03, staggerDelay: 0.04)
        .help("\(vis.title) · \(vis.subtitle)")
        .contextMenu { dockSlotContextMenu(slot) }
    }

    @ViewBuilder
    private func leadingVisualIcon(_ vis: HomeResolvedVisual, size: CGFloat, colors: (top: Color, bottom: Color)) -> some View {
        if let appURL = vis.nativeAppURL {
            Image(nsImage: IconCache.shared.appIcon(for: appURL)).resizable().scaledToFit().frame(width: size, height: size)
        } else if let iconURL = vis.customIconURL, let nsImg = IconCache.shared.pluginIcon(for: iconURL, pointSize: size) {
            Image(nsImage: nsImg).resizable().scaledToFit().frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        } else if let fileURL = vis.localFileURL {
            Image(nsImage: IconCache.shared.fileIcon(isDirectory: vis.isDirectory, extensionLowercased: fileURL.pathExtension.lowercased()))
                .resizable().scaledToFit().frame(width: size * 0.88, height: size * 0.88)
        } else {
            SquircleBadge(symbol: vis.symbolName, topColor: colors.top, bottomColor: colors.bottom, size: size)
        }
    }
}

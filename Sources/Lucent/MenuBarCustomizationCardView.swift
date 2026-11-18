import AppKit
import LucentCore
import SwiftUI

@MainActor
private final class MenuBarCardUIState: ObservableObject {
    @Published var isExpanded: Bool = false
}

struct MenuBarCustomizationCardView: View {
    @ObservedObject var viewModel: AppViewModel
    @StateObject private var uiState = MenuBarCardUIState()

    private var config: MenuBarConfig { viewModel.menuBarConfig }

    private var editableItems: [MenuBarBuiltinItemID] {
        config.orderedItems.filter { !$0.isLockedVisible }
    }

    private var pinnedPluginItems: [PluginQuickButtonItem] {
        PluginCommandRegistry.enabledMenuBarItems(for: viewModel.plugins)
    }

    private var activeHotKeyConfig: HotKeyBindingConfig {
        HotKeyBindingConfig.load()
    }

    private var visibleCountSummary: String {
        let layout = config.resolvedLayout()
        let topCount = layout.topLevelItems.count + layout.systemTailItems.count + (layout.maintenanceSubmenuItems.isEmpty ? 0 : 1)
        return L10n.pick("一级菜单 \(topCount) 项", "\(topCount) top-level")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Label(L10n.pick("顶部状态栏菜单自定义", "Status Bar Menu Customization"), systemImage: "menubar.rectangle")
                    .font(.callout.weight(.semibold))
                Text(visibleCountSummary)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(LiquidColors.accentPrimary)
                    .padding(.horizontal, 8).padding(.vertical, 2.5)
                    .background(LiquidColors.pillSurface, in: Capsule())
                Spacer()
                Button(uiState.isExpanded ? L10n.pick("收起详细排序", "Collapse") : L10n.pick("自定义条目与排序", "Customize Items")) {
                    withAnimation(LiquidMotion.snappySpring) { uiState.isExpanded.toggle() }
                }
                .buttonStyle(GlassPillButtonStyle(prominent: uiState.isExpanded, compact: true))
            }

            HStack(spacing: 7) {
                Text(L10n.pick("布局预设：", "Preset:"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LiquidColors.textSecondary)
                ForEach(MenuBarPreset.allCases) { preset in
                    let active = config.matchingPreset == preset
                    Button(preset.title) {
                        mutateConfig { $0 = MenuBarConfig.preset(preset) }
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: active, compact: true))
                    .help(preset.subtitle)
                }
                if config.matchingPreset == nil {
                    Text(L10n.pick("自定义配置", "Custom"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.cyan)
                        .padding(.horizontal, 7).padding(.vertical, 2.5)
                        .background(LiquidColors.pillSurface, in: Capsule())
                }
                Spacer()
            }

            FlowWrapLayout(horizontalSpacing: 16, verticalSpacing: 8) {
                Toggle(L10n.pick("无活跃窗口时自动隐藏清理项", "Auto-hide idle cleanup items"), isOn: Binding(
                    get: { config.hideContextualItemsWhenIdle },
                    set: { val in mutateConfig { $0.hideContextualItemsWhenIdle = val } }
                ))
                .fixedSize(horizontal: true, vertical: false)

                Toggle(L10n.pick("低频维护项收纳进二级菜单", "Fold maintenance into submenu"), isOn: Binding(
                    get: { config.foldMaintenanceIntoSubmenu },
                    set: { val in mutateConfig { $0.foldMaintenanceIntoSubmenu = val } }
                ))
                .fixedSize(horizontal: true, vertical: false)

                Toggle(L10n.pick("显示已挂载插件与子功能", "Show pinned plugins & commands"), isOn: Binding(
                    get: { config.showPinnedPluginsSection },
                    set: { val in mutateConfig { $0.showPinnedPluginsSection = val } }
                ))
                .fixedSize(horizontal: true, vertical: false)
            }
            .font(.caption)

            if !pinnedPluginItems.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "puzzlepiece.extension.fill").font(.caption2).foregroundStyle(.cyan)
                    Text(L10n.pick("已挂载插件项 (\(pinnedPluginItems.count))：", "Pinned plugin items (\(pinnedPluginItems.count)):"))
                        .font(.caption2.weight(.semibold)).foregroundStyle(LiquidColors.textSecondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(pinnedPluginItems) { pItem in
                                Button(pItem.title) { viewModel.openPluginSettings(id: pItem.pluginID) }
                                    .buttonStyle(GlassPillButtonStyle(compact: true))
                            }
                        }
                    }
                }
            }

            if uiState.isExpanded {
                Divider().opacity(0.22)
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.pick("勾选要展示的功能入口，或点击 ↑ ↓ 调整状态栏菜单顺序（设置中心与退出始终保留在底部）：", "Toggle visibility or click ↑ ↓ to reorder status bar menu items (Settings & Quit stay locked at bottom):"))
                        .font(.caption2)
                        .foregroundStyle(LiquidColors.textSecondary)

                    ForEach(Array(editableItems.enumerated()), id: \.element.id) { index, item in
                        itemConfigRow(item: item, index: index, total: editableItems.count)
                    }
                }
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
    }

    private func itemConfigRow(item: MenuBarBuiltinItemID, index: Int, total: Int) -> some View {
        let enabled = config.isItemEnabled(item)
        let shortcutLabel = item.associatedHotKeyAction
            .flatMap { activeHotKeyConfig.effectiveChord(for: $0)?.displayString }

        return HStack(spacing: 9) {
            Image(systemName: item.symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(enabled ? LiquidColors.accentPrimary : LiquidColors.textSecondary)
                .frame(width: 18)

            Text(item.localizedTitle)
                .font(.caption.weight(enabled ? .medium : .regular))
                .foregroundStyle(enabled ? LiquidColors.textPrimary : LiquidColors.textSecondary)
                .lineLimit(1)

            if item.isContextualDynamicItem {
                Text(L10n.pick("按需动态", "Dynamic"))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.mint)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(LiquidColors.pillSurface, in: Capsule())
            } else if item.isMaintenanceItem && config.foldMaintenanceIntoSubmenu {
                Text(L10n.pick("二级菜单", "Submenu"))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(LiquidColors.textSecondary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(LiquidColors.pillSurface, in: Capsule())
            }

            Spacer(minLength: 4)

            if let shortcutLabel {
                Text(shortcutLabel)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(LiquidColors.textSecondary)
                    .padding(.horizontal, 6).padding(.vertical, 1.5)
                    .background(LiquidColors.pillSurface, in: Capsule())
            }

            HStack(spacing: 2) {
                Button { mutateConfig { $0.moveItem(item, offset: -1) } } label: {
                    Image(systemName: "chevron.up").font(.system(size: 10, weight: .bold)).frame(width: 20, height: 20)
                }
                .buttonStyle(.plain).disabled(index == 0).opacity(index == 0 ? 0.3 : 0.85)

                Button { mutateConfig { $0.moveItem(item, offset: 1) } } label: {
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).frame(width: 20, height: 20)
                }
                .buttonStyle(.plain).disabled(index >= total - 1).opacity(index >= total - 1 ? 0.3 : 0.85)
            }

            Toggle("", isOn: Binding(
                get: { enabled },
                set: { val in mutateConfig { $0.setItemEnabled(item, enabled: val) } }
            ))
            .toggleStyle(.switch).controlSize(.mini).labelsHidden()
        }
        .padding(.horizontal, 10).padding(.vertical, 5.5)
        .background(LiquidColors.pillSurface.opacity(enabled ? 0.65 : 0.3), in: RoundedRectangle(cornerRadius: LiquidRadii.row, style: .continuous))
    }

    private func mutateConfig(_ transform: (inout MenuBarConfig) -> Void) {
        var next = viewModel.menuBarConfig
        transform(&next)
        viewModel.menuBarConfig = next
        next.save()
    }
}

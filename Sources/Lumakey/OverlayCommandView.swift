import AppKit
import LumakeyCore
import SwiftUI

struct OverlayCommandView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var themeManager = ThemeManager.shared

    private var showsBentoHome: Bool {
        viewModel.omniFilter == .all
            && viewModel.scopedPluginID == nil
            && viewModel.overlayQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var shouldShowSideLens: Bool {
        (viewModel.effectiveLensVisible && !showsBentoHome)
            || viewModel.inlineResultBody != nil
            || viewModel.inlinePluginViewPayload != nil
    }

    private var effectivePlaceholder: String {
        if let scoped = viewModel.activeScopedPlugin {
            let pName = L10n.translate(scoped.manifest.name)
            return L10n.pick("在「\(pName)」中筛选词条或输入参数按 ↩ 执行...", "Filter items or pass arguments to \"\(pName)\" and press ↩...")
        }
        return viewModel.omniFilter.placeholder
    }

    var body: some View {
        VStack(spacing: 0) {
            topGrabberStrip
            searchCapsuleBar
            Divider().opacity(0.28)

            HStack(spacing: 0) {
                mainBodyColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(LiquidMotion.snappySpring, value: showsBentoHome)

                if shouldShowSideLens {
                    Divider().opacity(0.28)
                    OverlaySideLensView(viewModel: viewModel)
                        .frame(width: 320)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .animation(LiquidMotion.snappySpring, value: viewModel.showOverlayLens)
            .animation(nil, value: viewModel.omniFilter)

            Divider().opacity(0.28)
            OverlayBottomFooterBar(viewModel: viewModel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .liquidGlassShell(cornerRadius: LiquidRadii.panel)
    }

    private var topGrabberStrip: some View {
        ZStack {
            WindowDragRegion { viewModel.recenterFloatingPanel() }
            Capsule(style: .continuous)
                .fill(LiquidColors.textSecondary.opacity(0.32))
                .frame(width: 40, height: 4)
        }
        .frame(height: 14)
        .help("拖拽移动悬浮窗；双击居中重置位置")
    }

    private var searchCapsuleBar: some View {
        let searchShape = RoundedRectangle(cornerRadius: LiquidRadii.searchBar, style: .continuous)
        let hasQuery = !viewModel.overlayQuery.isEmpty
        return HStack(alignment: .center, spacing: 10) {
            SquircleBadge(
                symbol: viewModel.activeScopedPlugin?.manifest.icon ?? viewModel.omniFilter.symbolName,
                topColor: filterBadgeColors.0,
                bottomColor: filterBadgeColors.1,
                size: 36
            )
            .contentTransition(.symbolEffect(.replace))
            .onTapGesture { viewModel.bumpFocusToken() }

            if let scoped = viewModel.activeScopedPlugin {
                OverlayScopedPluginCapsule(plugin: scoped) {
                    withAnimation(LiquidMotion.snappySpring) {
                        viewModel.scopedPluginID = nil
                        viewModel.inlinePluginViewPayload = nil
                        viewModel.activeInlinePlugin = nil
                    }
                    viewModel.bumpFocusToken()
                }
                .transition(.scale(scale: 0.88).combined(with: .opacity))
            }

            AutoFocusSearchField(
                text: $viewModel.overlayQuery,
                placeholder: effectivePlaceholder,
                focusToken: viewModel.focusToken,
                onAction: { action in viewModel.handleOverlayKeyAction(action) },
                onQuickSelectIndex: { index in viewModel.quickExecuteCandidate(at: index) },
                onCopyCandidate: { viewModel.copySelectedCandidateValue() },
                onSecondarySubmit: { viewModel.executeSecondaryCandidateAction() }
            )
            .frame(maxWidth: .infinity, minHeight: 38, maxHeight: 42)

            if hasQuery {
                Button {
                    withAnimation(LiquidMotion.snappySpring) {
                        viewModel.overlayQuery = ""
                        viewModel.inlineResultBody = nil
                        viewModel.inlinePluginViewPayload = nil
                        viewModel.activeInlinePlugin = nil
                    }
                    viewModel.bumpFocusToken()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(LiquidColors.textSecondary)
                }
                .buttonStyle(.plain)
                .transition(.scale(scale: 0.80).combined(with: .opacity))
            }

            Button {
                withAnimation(LiquidMotion.snappySpring) {
                    viewModel.showOverlayLens.toggle()
                }
                viewModel.syncOverlayPreviewToSelection()
                viewModel.bumpFocusToken()
            } label: {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(viewModel.effectiveLensVisible ? LiquidColors.accentPrimary : LiquidColors.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(viewModel.effectiveLensVisible ? LiquidColors.accentPrimary.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("展开/收起右侧实时预览 (⌘Y)")

            filterCapsuleBar
        }
        .animation(LiquidMotion.snappySpring, value: hasQuery)
        .animation(LiquidMotion.snappySpring, value: viewModel.scopedPluginID)
        .padding(.horizontal, 8)
        .frame(height: 52)
        .background {
            ZStack {
                searchShape.fill(.ultraThinMaterial)
                searchShape.fill(LiquidColors.inputFieldSurface)
            }
            .contentShape(searchShape)
            .onTapGesture { viewModel.bumpFocusToken() }
        }
        .overlay { searchShape.strokeBorder(LiquidColors.inputFieldBorder, lineWidth: 1.0) }
        .padding(.horizontal, 16)
        .frame(height: 58)
        .padding(.bottom, 2)
    }

    private var filterCapsuleBar: some View {
        let pillShape = RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous)
        return HStack(spacing: 3) {
            ForEach(OmniFilter.allCases) { filter in
                let active = viewModel.omniFilter == filter
                let segShape = RoundedRectangle(cornerRadius: max(7, LiquidRadii.control - 2.5), style: .continuous)
                Button {
                    var tx = Transaction()
                    tx.disablesAnimations = true
                    withTransaction(tx) {
                        if filter != .plugins { viewModel.scopedPluginID = nil }
                        viewModel.setOmniFilter(filter)
                    }
                } label: {
                    Text(filter.title)
                        .font(.caption.weight(active ? .semibold : .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .foregroundStyle(active ? Color.white : LiquidColors.textPrimary.opacity(0.78))
                        .background {
                            if active {
                                segShape.fill(LiquidColors.accentGradient)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(LiquidColors.pillSurface, in: pillShape)
        .overlay { pillShape.strokeBorder(LiquidColors.pillBorder, lineWidth: 0.8) }
    }

    @ViewBuilder
    private var mainBodyColumn: some View {
        if showsBentoHome {
            OverlayBentoHomeView(viewModel: viewModel)
                .transition(.opacity.combined(with: .scale(scale: 0.988)))
        } else {
            VStack(spacing: 0) {
                if viewModel.omniFilter == .files {
                    OverlayEverythingFilterStrip(viewModel: viewModel)
                    Divider().opacity(0.18)
                } else if viewModel.omniFilter == .clipboard {
                    OverlayClipboardCategoryStrip(viewModel: viewModel)
                    Divider().opacity(0.18)
                } else if viewModel.omniFilter == .plugins {
                    OverlayPluginFilterStrip(viewModel: viewModel)
                    Divider().opacity(0.18)
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 4) {
                            OverlayUnifiedRowsView(viewModel: viewModel)
                        }
                        .id("\(viewModel.omniFilter.rawValue):\(viewModel.scopedPluginID ?? "all")")
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                    .onChange(of: viewModel.overlaySelectedIndex) { _, newIdx in
                        guard newIdx >= 0, newIdx < viewModel.displayedCandidates.count else { return }
                        let targetID = "\(viewModel.omniFilter.rawValue):\(viewModel.displayedCandidates[newIdx].id)"
                        withAnimation(LiquidMotion.snappySpring) {
                            proxy.scrollTo(targetID, anchor: .center)
                        }
                    }
                }
            }
            .transition(.opacity)
        }
    }

    private var filterBadgeColors: (Color, Color) {
        let isPrism = themeManager.current == .prismPulse
        switch viewModel.omniFilter {
        case .all: return isPrism ? (.cyan, .purple) : (.blue, .indigo)
        case .files: return isPrism ? (.teal, .indigo) : (.blue, .teal)
        case .clipboard: return (.orange, .pink)
        case .plugins: return (.purple, .indigo)
        }
    }
}

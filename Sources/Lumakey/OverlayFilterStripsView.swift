import AppKit
import LumakeyCore
import SwiftUI

struct OverlayEverythingFilterStrip: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(viewModel.availableEverythingScopes) { scope in
                    let active = viewModel.everythingScope == scope
                    Button(scope.title) {
                        viewModel.rebuildEverythingIndex(scope: scope)
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: active))
                }
                Divider().frame(height: 16).opacity(0.35)
                ForEach(["ext:swift", "ext:md", "pic:", "video:", "folder:"], id: \.self) { token in
                    Button(token) {
                        viewModel.overlayQuery = viewModel.overlayQuery.isEmpty ? token : "\(viewModel.overlayQuery) \(token)"
                        viewModel.bumpFocusToken()
                    }
                    .buttonStyle(GlassPillButtonStyle())
                }
                if viewModel.isIndexingEverything {
                    ProgressView().controlSize(.small).padding(.leading, 4)
                } else {
                    Text(L10n.pick("\(viewModel.everythingNodeCount) 节点", "\(viewModel.everythingNodeCount) nodes"))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(LiquidColors.textSecondary)
                        .padding(.leading, 4)
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 24)
            .padding(.vertical, 7)
        }
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.94),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }
}

struct OverlayClipboardCategoryStrip: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ClipboardCategory.allCases) { cat in
                Button(cat.localizedTitle) {
                    viewModel.clipboardCategory = cat
                }
                .buttonStyle(GlassPillButtonStyle(prominent: viewModel.clipboardCategory == cat))
            }
            Spacer()
            if viewModel.canUndoClipboardDelete {
                Button(L10n.pick("撤回 ⌘Z", "Undo ⌘Z")) {
                    _ = viewModel.undoLastClipboardDelete()
                }
                .buttonStyle(GlassPillButtonStyle(prominent: true))
            }
            Button {
                viewModel.toggleClipboardPause()
            } label: {
                Label(
                    viewModel.isClipboardPaused ? L10n.pick("恢复记录", "Resume") : L10n.pick("暂停记录", "Pause"),
                    systemImage: viewModel.isClipboardPaused ? "play.fill" : "pause.fill"
                )
            }
            .buttonStyle(GlassPillButtonStyle(prominent: viewModel.isClipboardPaused))
            Button("清空非收藏") {
                viewModel.clearUnpinnedClipboard()
            }
            .buttonStyle(GlassPillButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }
}

struct OverlayBottomFooterBar: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ZStack {
            WindowDragRegion()
            HStack(spacing: 10) {
                if viewModel.isRunningPlugin || !viewModel.syncingPluginIDs.isEmpty {
                    ProgressView().controlSize(.small)
                } else {
                    LumakeyBrandIconView(size: 17)
                }
                Text(L10n.translate(viewModel.serviceMessage ?? "⌘1..9 瞬启候选 · ⌘C 复制结果 · ⌘↩ 切换快捷按钮/打开"))
                    .font(.caption2)
                    .foregroundStyle(LiquidColors.textSecondary)
                    .lineLimit(1)
                Spacer()

                let isHomeEmpty = viewModel.omniFilter == .all
                    && viewModel.scopedPluginID == nil
                    && viewModel.overlayQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let compactFooter = viewModel.homeLayoutConfig.activeProfile.compactFooterBar

                if !viewModel.enabledQuickButtons.isEmpty && !(isHomeEmpty && compactFooter) {
                    HStack(spacing: 6) {
                        ForEach(viewModel.enabledQuickButtons.prefix(5)) { item in
                            Button {
                                viewModel.executeQuickButton(item)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: item.symbolName)
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .foregroundStyle(.orange)
                                    Text(L10n.translate(item.shortTitle))
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .foregroundStyle(LiquidColors.textPrimary)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(LiquidColors.pillSurface, in: Capsule(style: .continuous))
                                .overlay {
                                    Capsule(style: .continuous)
                                        .strokeBorder(Color.orange.opacity(0.35), lineWidth: 0.7)
                                }
                            }
                            .buttonStyle(.plain)
                            .help("\(L10n.translate(item.title)) · \(L10n.translate(item.pluginName))")
                            .contextMenu {
                                Button("立即运行") { viewModel.executeQuickButton(item) }
                                Button("打开插件设置") { viewModel.openPluginSettings(id: item.pluginID) }
                                Button("从快捷按钮移除") { viewModel.removeQuickButton(item) }
                            }
                        }
                    }
                    Divider().frame(height: 14).opacity(0.35)
                }

                Button { viewModel.openRoute(.workspace) } label: {
                    Label("文件台 ⌥E", systemImage: "sidebar.squares.left").font(.caption2)
                }
                .buttonStyle(.plain).foregroundStyle(LiquidColors.textSecondary)

                if !compactFooter {
                    Button { viewModel.startGifRecording() } label: {
                        Image(systemName: "record.circle.fill").font(.caption).foregroundStyle(.pink)
                    }
                    .buttonStyle(.plain).help("区域 / 窗口 GIF 动图录制 (⌥G)")

                    Button { viewModel.openRoute(.networkMonitor) } label: {
                        Image(systemName: "network").font(.caption).foregroundStyle(LiquidColors.textSecondary)
                    }
                    .buttonStyle(.plain).help("本机网络流量与去向监控 (⌥N)")

                    Button { SystemPulseWindowController.shared.toggleFloatingWidget() } label: {
                        Image(systemName: "waveform.path.ecg").font(.caption).foregroundStyle(LiquidColors.textSecondary)
                    }
                    .buttonStyle(.plain).help("系统脉搏悬浮监控 (⌥M)")

                    Button { viewModel.openRoute(.settings(.backup)) } label: {
                        Image(systemName: "externaldrive.badge.icloud").font(.caption).foregroundStyle(LiquidColors.textSecondary)
                    }
                    .buttonStyle(.plain).help("数据导出与 WebDAV 云同步")

                    Button { viewModel.openRoute(.settings(.mos)) } label: {
                        Image(systemName: "computermouse.fill").font(.caption)
                            .foregroundStyle(viewModel.mosTapActive ? .cyan : LiquidColors.textSecondary)
                    }
                    .buttonStyle(.plain).help("鼠标平滑滚动与滚轮方向")
                }

                Button { viewModel.openRoute(.settings(.homeLayout)) } label: {
                    Image(systemName: "square.grid.3x2.fill").font(.caption)
                }
                .buttonStyle(.plain).foregroundStyle(LiquidColors.textSecondary).help(L10n.pick("启动页定制与场景切换", "Customize Home Layout"))

                Button { viewModel.openRoute(.settings(.general)) } label: {
                    Image(systemName: "gearshape.fill").font(.caption)
                }
                .buttonStyle(.plain).foregroundStyle(LiquidColors.textSecondary).help("设置、热键与插件中心 (⌘,)")

                Button { viewModel.isOverlayPinned.toggle() } label: {
                    Image(systemName: viewModel.isOverlayPinned ? "pin.fill" : "pin").font(.caption)
                        .foregroundStyle(viewModel.isOverlayPinned ? .cyan : LiquidColors.textSecondary)
                }
                .buttonStyle(.plain).help("固定悬浮窗不被失焦收起")

                Divider().frame(height: 14).opacity(0.35)
                KeycapPill(title: "过滤", keyText: "⇥")
                KeycapPill(title: "预览", keyText: "⌘Y")
                KeycapPill(title: "执行", keyText: "↩", prominent: true)
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 36)
        .background(LiquidColors.pillSurface.opacity(0.55))
    }
}

import LucentCore
import SwiftUI

struct FileWorkspaceView: View {
    @ObservedObject var viewModel: AppViewModel

    private var shouldShowPreviewSidebar: Bool {
        guard viewModel.showWorkspacePreview else { return false }
        if viewModel.layoutMode == .dual {
            return viewModel.selectedEntry != nil
        }
        return true
    }

    var body: some View {
        let isDual = viewModel.layoutMode == .dual
        HStack(spacing: isDual ? 8 : 10) {
            LocationSidebarView(viewModel: viewModel)
                .frame(width: isDual ? 172 : 194)

            VStack(spacing: 10) {
                WorkspaceTopToolbar(viewModel: viewModel)
                HStack(spacing: isDual ? 8 : 10) {
                    FilePaneView(viewModel: viewModel, pane: .left, state: viewModel.leftPane)
                        .frame(minWidth: 0, maxWidth: .infinity)
                    if isDual {
                        FilePaneView(viewModel: viewModel, pane: .right, state: viewModel.rightPane)
                            .frame(minWidth: 0, maxWidth: .infinity)
                    }
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity)

            if shouldShowPreviewSidebar {
                SidePreviewPanelView(viewModel: viewModel)
                    .frame(width: isDual ? 276 : 320)
            }
        }
        .frame(minWidth: 980, minHeight: 560)
    }
}

private struct LocationSidebarView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("位置与磁盘")
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button { viewModel.refreshLocations() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(viewModel.locations) { item in
                        let isActive = viewModel.activePaneState.currentDirectory.standardizedFileURL.path == item.url.standardizedFileURL.path
                        Button {
                            viewModel.navigate(pane: viewModel.activePane, to: item.url)
                        } label: {
                            HStack(alignment: .center, spacing: 9) {
                                SquircleBadge(
                                    symbol: item.kind.symbolName,
                                    topColor: item.kind == .external ? .orange : .cyan,
                                    bottomColor: item.kind == .external ? .red : .blue,
                                    size: 26
                                )
                                VStack(alignment: .leading, spacing: 1.5) {
                                    Text(item.name)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(LiquidColors.textPrimary)
                                        .lineLimit(1)
                                    if let vol = item.volumeSummary {
                                        Text(vol.formatKind.badgeText)
                                            .font(.system(size: 10))
                                            .foregroundStyle(vol.formatKind == .ntfsReadOnly ? .orange : .secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 2)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(isActive ? LiquidColors.highlightGlow : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("宿主机工具链")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                ToolRow(label: "ntfs-3g", available: viewModel.toolingStatus.ntfs3gPath != nil)
                ToolRow(label: "ffmpeg", available: viewModel.toolingStatus.ffmpegPath != nil)
                ToolRow(label: "ffprobe", available: viewModel.toolingStatus.ffprobePath != nil)
            }
        }
        .padding(11)
        .liquidGlassCard(cornerRadius: LiquidRadii.bento)
    }
}

private struct ToolRow: View {
    let label: String
    let available: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(label).font(.caption2.monospaced()).lineLimit(1)
            Spacer(minLength: 4)
            Text(available ? "已就绪" : "未安装")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(available ? .green : .secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

private struct FilePaneView: View {
    @ObservedObject var viewModel: AppViewModel
    let pane: PaneSide
    let state: PaneState

    var body: some View {
        let visible = state.visibleEntries
        return VStack(spacing: 7) {
            WorkspacePaneHeaderToolbar(viewModel: viewModel, pane: pane, state: state)
            categoryFilterStrip
            if let summary = state.volumeSummary, summary.formatKind == .ntfsReadOnly {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill").foregroundStyle(.orange)
                    Text("NTFS 只读卷（\(summary.capacityText)）：仅开放浏览、播放、OCR 与校验，已保护禁止写入。")
                        .font(.caption2)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(8)
                .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
            }
            if let diag = state.diagnostic {
                Text("\(diag.title)：\(diag.reason) \(diag.nextStep)")
                    .font(.caption2).foregroundStyle(.red).padding(6)
            }
            WorkspaceEntriesContentView(viewModel: viewModel, pane: pane, state: state, entries: visible)
            WorkspaceFloatingActionBar(viewModel: viewModel, pane: pane)
            Divider().opacity(0.22)
            WorkspacePaneFooterStatusBar(
                state: state,
                isDual: viewModel.layoutMode == .dual,
                visibleCount: visible.count,
                selectionSummary: viewModel.selectionSummaryText(in: pane),
                serviceMessage: viewModel.activePane == pane ? viewModel.serviceMessage : nil
            )
        }
        .padding(10)
        .liquidGlassCard(cornerRadius: LiquidRadii.bento)
        .overlay {
            if viewModel.activePane == pane && viewModel.layoutMode == .dual {
                RoundedRectangle(cornerRadius: LiquidRadii.bento, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.48), lineWidth: 1.4)
            }
        }
    }

    private var categoryFilterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(WorkspaceMediaFilter.allCases) { filter in
                    let count = state.categoryCount(for: filter)
                    Button("\(filter.title) (\(count))") {
                        viewModel.activePane = pane
                        viewModel.mutatePane(pane) { $0.mediaFilter = filter }
                        viewModel.refreshWorkspaceSubfolderSearch(for: pane)
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: state.mediaFilter == filter, compact: true))
                }
                if state.mediaFilter != .all || !state.filterText.isEmpty {
                    Button("重置筛选") { viewModel.clearWorkspaceFilter(in: pane) }
                        .buttonStyle(GlassPillButtonStyle(compact: true))
                }
            }
            .padding(.trailing, 16)
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

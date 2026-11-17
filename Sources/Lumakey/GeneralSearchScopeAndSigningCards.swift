import AppKit
import LumakeyCore
import SwiftUI

struct GeneralSearchScopeCardView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        let excludedPaths = viewModel.generalPreferences.excludedIndexPaths
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("默认文件检索作用域", systemImage: "magnifyingglass.circle.fill").font(.callout.weight(.semibold))
                Text(viewModel.isIndexingEverything ? L10n.pick("索引中…", "Indexing…") : L10n.pick("\(viewModel.everythingNodeCount) 节点", "\(viewModel.everythingNodeCount) nodes"))
                    .font(.caption2.monospacedDigit().weight(.semibold)).foregroundStyle(LiquidColors.accentPrimary)
                    .padding(.horizontal, 8).padding(.vertical, 2.5).background(LiquidColors.pillSurface, in: Capsule())
                Spacer()
                Button(L10n.pick("排除文件夹…", "Exclude Folder…")) { viewModel.addExcludedIndexDirectoryInteractive() }
                    .buttonStyle(GlassPillButtonStyle(compact: true))
                Button("重建磁盘缓存") { viewModel.forceRebuildEverythingIndex() }
                    .buttonStyle(GlassPillButtonStyle(compact: true))
                Button("立即呼出搜文件 (⌥F)") { viewModel.showOverlay(filter: .files) }
                    .buttonStyle(GlassPillButtonStyle(prominent: true, compact: true))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 185), spacing: 8)], spacing: 8) {
                ForEach(viewModel.availableEverythingScopes) { scope in
                    let active = viewModel.everythingScope == scope
                    Button { viewModel.selectDefaultEverythingScope(scope) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: scopeIcon(scope)).foregroundStyle(active ? Color.white : LiquidColors.accentPrimary)
                            Text(scope.title).font(.caption.weight(.semibold)).lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .foregroundStyle(active ? Color.white : LiquidColors.textPrimary)
                        .background(active ? Color.accentColor : LiquidColors.pillSurface, in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous).strokeBorder(LiquidColors.pillBorder, lineWidth: 0.7) }
                    }
                    .buttonStyle(LiquidBentoTileStyle(cornerRadius: LiquidRadii.control))
                }
            }
            Divider().opacity(0.20)
            HStack(alignment: .top, spacing: 8) {
                Text(L10n.pick("自定义忽略路径：", "Excluded Paths:")).font(.caption2.weight(.semibold))
                    .foregroundStyle(LiquidColors.textSecondary).padding(.top, 3)
                if excludedPaths.isEmpty {
                    Text(L10n.pick("未添加额外忽略路径（系统已默认跳过 node_modules、.git、Library 等目录）", "None added (node_modules, .git, Library, etc. are skipped automatically)"))
                        .font(.caption2).foregroundStyle(LiquidColors.textSecondary).padding(.top, 3)
                } else {
                    FlowWrapLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                        ForEach(excludedPaths, id: \.self) { path in
                            HStack(spacing: 4) {
                                Image(systemName: "folder.badge.minus").font(.caption2).foregroundStyle(.orange)
                                Text(abbreviateHome(path)).font(.system(size: 11, design: .monospaced)).lineLimit(1)
                                Button { viewModel.removeExcludedIndexDirectory(path) } label: {
                                    Image(systemName: "xmark.circle.fill").font(.caption2).foregroundStyle(LiquidColors.textSecondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 3.5).background(LiquidColors.pillSurface, in: Capsule())
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14).liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
    }

    private func abbreviateHome(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        return path.hasPrefix(home + "/") ? ("~" + String(path.dropFirst(home.count))) : path
    }

    private func scopeIcon(_ scope: EverythingScope) -> String {
        switch scope {
        case .allVolumes: "externaldrive.fill.badge.checkmark"
        case .quickUserFolders: "folder.fill"
        case .home: "house.fill"
        case .volume: "externaldrive.fill"
        }
    }
}

struct GeneralSigningStatusCardView: View {
    var body: some View {
        let sign = CodeSigningInspector.inspect()
        return HStack(spacing: 12) {
            SquircleBadge(
                symbol: sign.isReadyForPublicDistribution ? "checkmark.seal.fill" : (sign.isStableForTCC ? "lock.shield.fill" : "shield.lefthalf.filled"),
                topColor: sign.isStableForTCC ? .green : .blue,
                bottomColor: sign.isStableForTCC ? .teal : .indigo, size: 32
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(sign.badgeTitle).font(.callout.weight(.semibold))
                Text(sign.explanation).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if !sign.isStableForTCC {
                Button("隐私与安全性…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(GlassPillButtonStyle())
            }
        }
        .padding(12).liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)
    }
}

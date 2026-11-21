import AppKit
import LucentCore
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
            Divider().opacity(0.20)
            Toggle(isOn: Binding(
                get: { viewModel.generalPreferences.enableMcpFileSearch },
                set: { enabled in viewModel.updateGeneralPreferences { $0.enableMcpFileSearch = enabled } }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.pick("允许 lucent-mcp 离线检索本地文件索引（默认关闭）", "Allow lucent-mcp read-only file search (off by default)"))
                        .font(.caption.weight(.semibold))
                    Text(L10n.pick("开启后，已接入的 AI 助手可调用 lucent_search_files 只读检索本地 LCNTIDX3 快照，并严格遵守上方忽略路径。", "Lets connected AI agents call lucent_search_files against the local LCNTIDX3 snapshot while respecting excluded paths above."))
                        .font(.caption2).foregroundStyle(LiquidColors.textSecondary)
                }
            }
            .toggleStyle(.switch)
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

@MainActor
private final class SigningCardUIState: ObservableObject {
    @Published var actionFeedback: String? = nil
}

struct GeneralSigningStatusCardView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var updater = AppUpdateCoordinator.shared
    @StateObject private var ui = SigningCardUIState()

    var body: some View {
        let sign = CodeSigningInspector.inspect()
        let command = AppUpdateService.localResignCommand(forAppBundleURL: Bundle.main.bundleURL)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                SquircleBadge(
                    symbol: sign.isReadyForPublicDistribution
                        ? "checkmark.seal.fill"
                        : (sign.isStableForTCC ? "lock.shield.fill" : "exclamationmark.shield.fill"),
                    topColor: sign.isStableForTCC ? .green : .orange,
                    bottomColor: sign.isStableForTCC ? .teal : .red,
                    size: 32
                )
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(sign.badgeTitle).font(.callout.weight(.semibold))
                        Text(sign.isStableForTCC
                            ? L10n.pick("永久授权签名", "TCC-Permanent")
                            : L10n.pick("未配置永久授权", "Not TCC-Permanent"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(sign.isStableForTCC ? Color.green : Color.orange)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(
                                (sign.isStableForTCC ? Color.green : Color.orange).opacity(0.14),
                                in: Capsule()
                            )
                    }
                    Text(sign.explanation)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if sign.isStableForTCC {
                    Button(L10n.pick("隐私与安全性…", "Privacy & Security…")) {
                        openAccessibilityPrivacySettings()
                    }
                    .buttonStyle(GlassPillButtonStyle(compact: true))
                }
            }

            if !sign.isStableForTCC {
                nonPermanentSigningPrompt(command: command)
            }
        }
        .padding(12).liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)
    }

    private func nonPermanentSigningPrompt(command: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.top, 1)
                Text(L10n.pick(
                    "检测到当前应用不是永久授权签名（更新或重装后，「辅助功能 / 屏幕录制」权限可能会重置）。点击下方按钮即可在终端运行本机保权限重签命令，生成固定证书后永久延续授权。",
                    "This build does not have a TCC-permanent signature yet, so macOS permissions (Accessibility / Screen Recording) may reset on updates. Click below to run the local signing command in Terminal so permissions persist across versions."
                ))
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(command)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 8) {
                Button {
                    updater.runLocalResignCommandInTerminal(viewModel: viewModel)
                    ui.actionFeedback = L10n.pick(
                        "已在终端启动重签命令，请按终端提示完成钥匙串信任确认。",
                        "Launched signing command in Terminal. Follow the prompts there to complete setup."
                    )
                } label: {
                    Label(L10n.pick("在终端运行重签命令", "Run Signing Command in Terminal"), systemImage: "play.fill")
                }
                .buttonStyle(GlassPillButtonStyle(prominent: true, compact: true))

                Button {
                    updater.copyLocalResignCommand(viewModel: viewModel)
                    ui.actionFeedback = L10n.pick("已复制到剪贴板，可在终端粘贴运行。", "Copied command to clipboard.")
                } label: {
                    Label(L10n.pick("复制命令", "Copy Command"), systemImage: "doc.on.doc")
                }
                .buttonStyle(GlassPillButtonStyle(compact: true))

                Spacer()

                Button(L10n.pick("隐私与安全性…", "Privacy & Security…")) {
                    openAccessibilityPrivacySettings()
                }
                .buttonStyle(GlassPillButtonStyle(compact: true))
            }

            if let actionFeedback = ui.actionFeedback {
                Text(actionFeedback)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.32), lineWidth: 0.8)
        }
    }

    private func openAccessibilityPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

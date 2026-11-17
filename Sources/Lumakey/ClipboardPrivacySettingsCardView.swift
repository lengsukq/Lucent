import AppKit
import LumakeyCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
private final class ClipboardPrivacyCardState: ObservableObject {
    @Published var isPickerExpanded: Bool = false
    @Published var searchQuery: String = ""
}

struct ClipboardPrivacySettingsCardView: View {
    @ObservedObject var viewModel: AppViewModel
    @StateObject private var uiState = ClipboardPrivacyCardState()

    private var prefs: GeneralPreferences { viewModel.generalPreferences }

    private struct ResolvedExcludedApp: Identifiable {
        let bundleID: String
        let displayName: String
        let appURL: URL?
        var id: String { bundleID }
    }

    private var resolvedExcludedApps: [ResolvedExcludedApp] {
        prefs.clipboardExcludedBundleIDs.map { bid in
            if let matched = viewModel.installedApps.first(where: {
                Bundle(url: $0.url)?.bundleIdentifier?.caseInsensitiveCompare(bid) == .orderedSame
            }) {
                return ResolvedExcludedApp(bundleID: bid, displayName: matched.displayName, appURL: matched.url)
            }
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                let name = FileManager.default.displayName(atPath: appURL.path)
                    .replacingOccurrences(of: ".app", with: "")
                return ResolvedExcludedApp(bundleID: bid, displayName: name, appURL: appURL)
            }
            return ResolvedExcludedApp(bundleID: bid, displayName: bid, appURL: nil)
        }
    }

    private var candidateInstalledApps: [(app: InstalledAppItem, bundleID: String)] {
        let needle = uiState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var out: [(app: InstalledAppItem, bundleID: String)] = []
        for item in viewModel.installedApps {
            guard let bid = Bundle(url: item.url)?.bundleIdentifier, !bid.isEmpty else { continue }
            if needle.isEmpty {
                out.append((item, bid))
            } else if item.nameLowercased.contains(needle)
                || item.englishNameLowercased.contains(needle)
                || item.pinyinInitials.contains(needle)
                || bid.lowercased().contains(needle) {
                out.append((item, bid))
            }
            if out.count >= 18 { break }
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Label(
                    L10n.pick("剪贴板保留策略与隐私忽略应用", "Clipboard Retention & Excluded Apps"),
                    systemImage: "hand.raised.shield.fill"
                )
                .font(.callout.weight(.semibold))

                Text(L10n.pick(
                    "已忽略 \(prefs.clipboardExcludedBundleIDs.count) 款应用",
                    "\(prefs.clipboardExcludedBundleIDs.count) excluded"
                ))
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(LiquidColors.accentPrimary)
                .padding(.horizontal, 8).padding(.vertical, 2.5)
                .background(LiquidColors.pillSurface, in: Capsule())

                Spacer()

                Button(L10n.pick("从访达选取应用…", "Pick .app…")) {
                    pickAppFromFinder()
                }
                .buttonStyle(GlassPillButtonStyle(compact: true))

                Button(uiState.isPickerExpanded ? L10n.pick("收起应用列表", "Done") : L10n.pick("勾选忽略应用", "Choose Apps")) {
                    withAnimation(LiquidMotion.snappySpring) { uiState.isPickerExpanded.toggle() }
                }
                .buttonStyle(GlassPillButtonStyle(prominent: uiState.isPickerExpanded, compact: true))
            }

            HStack(spacing: 7) {
                Text(L10n.pick("未收藏保留上限：", "Unpinned Limit:"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LiquidColors.textSecondary)
                ForEach(GeneralPreferences.clipboardCapacityPresets, id: \.self) { count in
                    Button(L10n.pick("\(count) 条", "\(count)")) {
                        viewModel.updateGeneralPreferences { $0.clipboardMaxUnpinned = count }
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: prefs.clipboardMaxUnpinned == count, compact: true))
                }

                Divider().frame(height: 14).opacity(0.25).padding(.horizontal, 4)

                Text(L10n.pick("自动过期：", "Auto-Expire:"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LiquidColors.textSecondary)
                ForEach(ClipboardRetentionTTL.allCases) { ttl in
                    Button(ttl.localizedTitle) {
                        viewModel.updateGeneralPreferences { $0.clipboardRetentionTTL = ttl }
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: prefs.clipboardRetentionTTL == ttl, compact: true))
                }
                Spacer()
            }

            Text(L10n.pick(
                "收藏项永久保留且不受条数或过期时间影响；密码管理器隐私剪贴板已默认自动跳过，下方可额外排除终端、网银或私密聊天软件：",
                "Pinned items never expire. Password managers are skipped automatically; add terminals, banking, or private chat apps below:"
            ))
            .font(.caption2)
            .foregroundStyle(LiquidColors.textSecondary)

            if !resolvedExcludedApps.isEmpty {
                FlowWrapLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(resolvedExcludedApps) { entry in
                        HStack(spacing: 5) {
                            if let appURL = entry.appURL {
                                Image(nsImage: IconCache.shared.appIcon(for: appURL))
                                    .resizable().frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "app.dashed").font(.caption2)
                            }
                            Text(entry.displayName)
                                .font(.caption2.weight(.medium))
                                .lineLimit(1)
                            Button {
                                viewModel.updateGeneralPreferences { $0.toggleExcludedApp(bundleID: entry.bundleID) }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(LiquidColors.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(LiquidColors.pillSurface, in: Capsule())
                        .overlay { Capsule().strokeBorder(LiquidColors.pillBorder, lineWidth: 0.7) }
                        .help(entry.bundleID)
                    }
                }
            }

            if uiState.isPickerExpanded {
                Divider().opacity(0.22)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(LiquidColors.textSecondary)
                    TextField(
                        L10n.pick("搜索已安装应用名称、拼音首字母或 Bundle ID…", "Filter installed apps or bundle IDs…"),
                        text: $uiState.searchQuery
                    )
                    .textFieldStyle(.plain)
                    .font(.caption)
                    if !uiState.searchQuery.isEmpty {
                        Button { uiState.searchQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(LiquidColors.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(LiquidColors.pillSurface, in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 6)], spacing: 6) {
                    ForEach(candidateInstalledApps, id: \.bundleID) { pair in
                        let excluded = prefs.isAppExcludedFromClipboard(bundleID: pair.bundleID)
                        Button {
                            viewModel.updateGeneralPreferences { $0.toggleExcludedApp(bundleID: pair.bundleID) }
                        } label: {
                            HStack(spacing: 7) {
                                Image(nsImage: IconCache.shared.appIcon(for: pair.app.url))
                                    .resizable().frame(width: 18, height: 18)
                                Text(pair.app.displayName)
                                    .font(.caption.weight(excluded ? .semibold : .regular))
                                    .lineLimit(1)
                                Spacer(minLength: 2)
                                Image(systemName: excluded ? "checkmark.shield.fill" : "plus.circle")
                                    .font(.caption)
                                    .foregroundStyle(excluded ? Color.orange : LiquidColors.textSecondary)
                            }
                            .padding(.horizontal, 9).padding(.vertical, 6)
                            .background(
                                excluded ? Color.orange.opacity(0.15) : LiquidColors.pillSurface.opacity(0.55),
                                in: RoundedRectangle(cornerRadius: LiquidRadii.row, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
    }

    private func pickAppFromFinder() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK {
            viewModel.updateGeneralPreferences { prefs in
                for url in panel.urls {
                    if let bid = Bundle(url: url)?.bundleIdentifier, !bid.isEmpty,
                       !prefs.isAppExcludedFromClipboard(bundleID: bid) {
                        prefs.toggleExcludedApp(bundleID: bid)
                    }
                }
            }
        }
    }
}

import AppKit
import LumakeyCore
import SwiftUI

struct HomeItemEditorContext: Identifiable {
    let id = UUID()
    var destination: HomeItemDestination
    var existingItem: HomeLaunchItem?
}

enum HomeEditorSourceTab: String, CaseIterable, Identifiable {
    case builtin, plugin, app, bookmark, pathOrQuery
    var id: String { rawValue }
    var title: String {
        switch self {
        case .builtin: L10n.pick("内置能力", "Built-in")
        case .plugin: L10n.pick("自制与插件", "Plugins")
        case .app: L10n.pick("本机应用", "Apps")
        case .bookmark: L10n.pick("书签链接", "Bookmark")
        case .pathOrQuery: L10n.pick("目录与检索", "Path/Query")
        }
    }
}

@MainActor
private final class HomeItemEditorFormState: ObservableObject {
    @Published var activeTab: HomeEditorSourceTab = .builtin
    @Published var selectedBuiltin: HomeBuiltinActionID = .fileWorkspace
    @Published var selectedPluginID: String = ""
    @Published var selectedCommandID: String = ""
    @Published var pluginBehavior: HomePluginLaunchBehavior = .auto
    @Published var selectedAppPath: String = "/System/Library/CoreServices/Finder.app"
    @Published var appFilter: String = ""
    @Published var bookmarkURL: String = "https://"
    @Published var localPathText: String = ""
    @Published var queryText: String = ""
    @Published var isLocalPathMode: Bool = true
    @Published var customTitle: String = ""
    @Published var customSubtitle: String = ""
    @Published var customIcon: String = ""
    @Published var accentColor: String = "cyan"
    @Published var errorNote: String? = nil
}

struct HomeItemEditorSheet: View {
    @ObservedObject var viewModel: AppViewModel
    let context: HomeItemEditorContext
    var onDismiss: () -> Void
    @StateObject private var form = HomeItemEditorFormState()

    private let colorChoices = ["cyan", "blue", "indigo", "purple", "mint", "teal", "green", "orange", "pink", "slate"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(
                    context.existingItem == nil
                        ? L10n.pick("添加启动页磁贴 / 书签 / 快捷入口", "Add Home Launch Item")
                        : L10n.pick("编辑启动项外观与目标", "Edit Home Launch Item"),
                    systemImage: "plus.square.on.square"
                )
                .font(.headline)
                Spacer()
                Button(L10n.pick("取消", "Cancel")) { onDismiss() }
                    .buttonStyle(GlassPillButtonStyle(compact: true))
            }

            HStack(spacing: 5) {
                ForEach(HomeEditorSourceTab.allCases) { tab in
                    Button(tab.title) { form.activeTab = tab; form.errorNote = nil }
                        .buttonStyle(GlassPillButtonStyle(prominent: form.activeTab == tab, compact: true))
                }
            }

            sourceFormSection
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LiquidColors.pillSurface.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.pick("个性化外观覆盖（留空则自动跟随目标原生图标与名称）", "Visual Overrides (leave blank for automatic native title & icon)"))
                    .font(.caption2.weight(.semibold)).foregroundStyle(LiquidColors.textSecondary)
                HStack(spacing: 8) {
                    GlassInputField(symbol: "character", placeholder: L10n.pick("自定义标题（可选）", "Custom title (optional)"), text: $form.customTitle)
                    GlassInputField(symbol: "text.alignleft", placeholder: L10n.pick("副标题（可选）", "Custom subtitle"), text: $form.customSubtitle)
                    GlassInputField(symbol: "sparkles", placeholder: L10n.pick("SF Symbol（如 star.fill）", "SF Symbol"), text: $form.customIcon)
                        .frame(width: 175)
                }
                HStack(spacing: 7) {
                    Text(L10n.pick("主题色：", "Tint:")).font(.caption2.weight(.semibold)).foregroundStyle(LiquidColors.textSecondary)
                    ForEach(colorChoices, id: \.self) { name in
                        Circle().fill(PluginVisualPalette.tint(from: name)).frame(width: 18, height: 18)
                            .overlay { if form.accentColor == name { Circle().strokeBorder(Color.white, lineWidth: 2) } }
                            .onTapGesture { form.accentColor = name }
                    }
                    Spacer()
                }
            }

            if let err = form.errorNote {
                Text(err).font(.caption2.weight(.semibold)).foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button(L10n.pick("保存到启动页", "Save to Home")) { saveItem() }
                    .buttonStyle(GlassPillButtonStyle(prominent: true))
            }
        }
        .padding(18)
        .frame(width: 560)
        .onAppear(perform: populateFromExisting)
    }

    @ViewBuilder
    private var sourceFormSection: some View {
        switch form.activeTab {
        case .builtin:
            FlowWrapLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(HomeBuiltinActionID.allCases) { act in
                    Button {
                        form.selectedBuiltin = act; form.accentColor = act.defaultAccentColor
                    } label: {
                        Label(act.title, systemImage: act.symbolName)
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: form.selectedBuiltin == act, compact: true))
                }
            }
        case .plugin:
            VStack(alignment: .leading, spacing: 8) {
                let validPlugins = viewModel.plugins.filter { $0.isValid && ($0.isBuiltin || $0.isEnabled) }
                if validPlugins.isEmpty {
                    Text(L10n.pick("当前暂无已启用插件", "No enabled plugins available")).font(.caption).foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 10) {
                        let currentName = validPlugins.first(where: { $0.id == form.selectedPluginID })?.displayName
                            ?? validPlugins.first?.displayName ?? ""
                        GlassDropdownMenu(title: L10n.pick("选择插件：", "Plugin:"), value: currentName) {
                            ForEach(validPlugins) { p in
                                Button(p.displayName) {
                                    if form.selectedPluginID != p.id {
                                        form.selectedPluginID = p.id
                                        form.selectedCommandID = ""
                                    }
                                }
                            }
                        }

                        let cmds = viewModel.pluginCommands.filter { $0.pluginID == form.selectedPluginID }
                        if !cmds.isEmpty {
                            let currentAction = cmds.first(where: { $0.command.id == form.selectedCommandID })?.localizedTitle
                                ?? L10n.pick("整个插件入口", "Plugin Entry")
                            GlassDropdownMenu(title: L10n.pick("动作：", "Action:"), value: currentAction) {
                                Button(L10n.pick("整个插件入口", "Plugin Entry")) { form.selectedCommandID = "" }
                                Divider()
                                ForEach(cmds) { c in
                                    Button(c.localizedTitle) { form.selectedCommandID = c.command.id }
                                }
                            }
                        }
                    }
                    if form.selectedCommandID.isEmpty {
                        FlowWrapLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                            Text(L10n.pick("点击行为：", "Click Behavior:"))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(LiquidColors.textSecondary)
                            ForEach(HomePluginLaunchBehavior.allCases) { beh in
                                Button(beh.title) { form.pluginBehavior = beh }
                                    .buttonStyle(GlassPillButtonStyle(prominent: form.pluginBehavior == beh, compact: true))
                            }
                        }
                    }
                }
            }
        case .app:
            VStack(alignment: .leading, spacing: 7) {
                GlassInputField(symbol: "magnifyingglass", placeholder: L10n.pick("筛选已安装应用…", "Filter installed apps…"), text: $form.appFilter)
                let filtered = viewModel.installedApps.filter {
                    form.appFilter.isEmpty || $0.displayName.localizedCaseInsensitiveContains(form.appFilter)
                        || $0.englishName.localizedCaseInsensitiveContains(form.appFilter)
                }.prefix(12)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(filtered)) { app in
                            Button(app.displayName) { form.selectedAppPath = app.id }
                                .buttonStyle(GlassPillButtonStyle(prominent: form.selectedAppPath == app.id, compact: true))
                        }
                    }
                }
                Text(form.selectedAppPath).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
            }
        case .bookmark:
            VStack(alignment: .leading, spacing: 7) {
                GlassInputField(symbol: "link", placeholder: "https://github.com / lumakey://settings/plugins / vscode://...", text: $form.bookmarkURL)
                let indexedLinks = viewModel.pluginSearchEntries.filter { ($0.url ?? "").isEmpty == false }.prefix(8)
                if !indexedLinks.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            Text(L10n.pick("从插件书签快选：", "From indexed bookmarks:")).font(.caption2).foregroundStyle(.secondary)
                            ForEach(Array(indexedLinks)) { entry in
                                Button(entry.title) {
                                    form.bookmarkURL = entry.url ?? ""
                                    if form.customTitle.isEmpty { form.customTitle = entry.title }
                                }
                                .buttonStyle(GlassPillButtonStyle(compact: true))
                            }
                        }
                    }
                }
            }
        case .pathOrQuery:
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Button(L10n.pick("本地文件夹 / 文件路径", "Local Folder / File")) {
                        form.isLocalPathMode = true
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: form.isLocalPathMode, compact: true))

                    Button(L10n.pick("预设搜索词 / 短语", "Preset Search Query")) {
                        form.isLocalPathMode = false
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: !form.isLocalPathMode, compact: true))
                }
                if form.isLocalPathMode {
                    HStack(spacing: 8) {
                        GlassInputField(symbol: "folder", placeholder: "~/Documents/code", text: $form.localPathText)
                        Button(L10n.pick("选择…", "Browse…")) { browseLocalPath() }
                            .buttonStyle(GlassPillButtonStyle(compact: true))
                    }
                } else {
                    GlassInputField(symbol: "magnifyingglass", placeholder: L10n.pick("如 ext:swift / #ai / port 3000 / ;日报", "e.g. ext:swift / port 3000"), text: $form.queryText)
                }
            }
        }
    }

    private func browseLocalPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { form.localPathText = url.path }
    }

    private func populateFromExisting() {
        if form.selectedPluginID.isEmpty {
            form.selectedPluginID = viewModel.plugins.first(where: { $0.isValid })?.id ?? BuiltinPluginID.mos.rawValue
        }
        guard let item = context.existingItem else { return }
        form.customTitle = item.customTitle ?? ""
        form.customSubtitle = item.customSubtitle ?? ""
        form.customIcon = item.customIcon ?? ""
        form.accentColor = item.accentColor ?? "cyan"
        switch item.target {
        case .builtin(let id): form.activeTab = .builtin; form.selectedBuiltin = id
        case .plugin(let pid, let beh): form.activeTab = .plugin; form.selectedPluginID = pid; form.pluginBehavior = beh
        case .pluginCommand(let pid, let cid, _): form.activeTab = .plugin; form.selectedPluginID = pid; form.selectedCommandID = cid
        case .nativeApp(let path, _): form.activeTab = .app; form.selectedAppPath = path
        case .bookmark(let url, _, _): form.activeTab = .bookmark; form.bookmarkURL = url
        case .localPath(let path): form.activeTab = .pathOrQuery; form.isLocalPathMode = true; form.localPathText = path
        case .queryChip(let q, _): form.activeTab = .pathOrQuery; form.isLocalPathMode = false; form.queryText = q
        }
    }

    private func saveItem() {
        let target: HomeLaunchTarget = switch form.activeTab {
        case .builtin: .builtin(form.selectedBuiltin)
        case .plugin:
            form.selectedCommandID.isEmpty
                ? .plugin(pluginID: form.selectedPluginID, behavior: form.pluginBehavior)
                : .pluginCommand(pluginID: form.selectedPluginID, commandID: form.selectedCommandID)
        case .app: .nativeApp(path: form.selectedAppPath)
        case .bookmark: .bookmark(url: form.bookmarkURL.trimmingCharacters(in: .whitespacesAndNewlines))
        case .pathOrQuery:
            form.isLocalPathMode
                ? .localPath(path: (form.localPathText as NSString).expandingTildeInPath)
                : .queryChip(query: form.queryText)
        }
        if let err = HomeLaunchSecurity.validateTarget(target) {
            form.errorNote = err; return
        }
        let itemID = context.existingItem?.id ?? "item-\(UUID().uuidString.prefix(8).lowercased())"
        let built = HomeLaunchItem(
            id: itemID, target: target,
            customTitle: form.customTitle, customSubtitle: form.customSubtitle,
            customIcon: form.customIcon, accentColor: form.accentColor,
            hotkeyHint: context.existingItem?.hotkeyHint
        )
        viewModel.mutateHomeLayout { try? $0.upsertItem(built, in: context.destination) }
        onDismiss()
    }
}

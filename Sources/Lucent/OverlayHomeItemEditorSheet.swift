import AppKit
import LucentCore
import SwiftUI

struct HomeItemEditorContext: Identifiable {
    let id = UUID()
    var destination: HomeItemDestination
    var existingItem: HomeLaunchItem?
}

enum HomeEditorSourceTab: String, CaseIterable, Identifiable {
    case builtin, script, plugin, app, bookmark, pathOrQuery
    var id: String { rawValue }
    var title: String {
        switch self {
        case .builtin: L10n.pick("内置能力", "Built-in")
        case .script: L10n.pick("快捷脚本", "Scripts")
        case .plugin: L10n.pick("扩展插件", "Plugins")
        case .app: L10n.pick("本机应用", "Apps")
        case .bookmark: L10n.pick("书签链接", "Bookmark")
        case .pathOrQuery: L10n.pick("目录与检索", "Path/Query")
        }
    }
}

@MainActor
final class HomeItemEditorFormState: ObservableObject {
    @Published var activeTab: HomeEditorSourceTab = .builtin
    @Published var selectedBuiltin: HomeBuiltinActionID = .fileWorkspace
    @Published var selectedScriptID: String = ""
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
                        ? L10n.pick("添加启动页磁贴 / 脚本 / 快捷入口", "Add Home Launch Item")
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

            HomeItemEditorSourceFormView(viewModel: viewModel, form: form)
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LiquidColors.pillSurface.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.pick("个性化外观覆盖（留空则自动跟随目标原生图标、SVG 图标与名称）", "Visual Overrides (leave blank for native or custom SVG icon & title)"))
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
        .frame(width: 576)
        .onAppear(perform: populateFromExisting)
    }

    private func populateFromExisting() {
        if form.selectedPluginID.isEmpty {
            form.selectedPluginID = viewModel.plugins.first(where: { $0.isValid })?.id ?? BuiltinPluginID.mos.rawValue
        }
        if form.selectedScriptID.isEmpty {
            form.selectedScriptID = viewModel.scripts.first(where: { $0.isEnabled })?.id ?? ""
        }
        guard let item = context.existingItem else { return }
        form.customTitle = item.customTitle ?? ""
        form.customSubtitle = item.customSubtitle ?? ""
        form.customIcon = item.customIcon ?? ""
        form.accentColor = item.accentColor ?? "cyan"
        switch item.target {
        case .builtin(let id): form.activeTab = .builtin; form.selectedBuiltin = id
        case .script(let sid): form.activeTab = .script; form.selectedScriptID = sid
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
        case .script: .script(scriptID: form.selectedScriptID)
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

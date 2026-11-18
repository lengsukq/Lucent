import AppKit
import LucentCore
import SwiftUI

struct HomeItemEditorSourceFormView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var form: HomeItemEditorFormState

    var body: some View {
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
        case .script:
            let enabledScripts = viewModel.scripts.filter(\.isEnabled)
            if enabledScripts.isEmpty {
                HStack(spacing: 8) {
                    Text(L10n.pick("当前暂无已启用的快捷脚本", "No enabled scripts available")).font(.caption).foregroundStyle(.secondary)
                    Button(L10n.pick("打开脚本库新建…", "Open Script Library…")) {
                        viewModel.openRoute(.settings(.scripts))
                    }
                    .buttonStyle(GlassPillButtonStyle(compact: true))
                }
            } else {
                FlowWrapLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(enabledScripts) { sc in
                        Button {
                            form.selectedScriptID = sc.id
                            form.accentColor = sc.accentColor
                        } label: {
                            HStack(spacing: 5) {
                                if let iconURL = sc.customIconURL(in: ScriptLibraryStore.shared.scriptsDirectory),
                                   let nsImg = IconCache.shared.pluginIcon(for: iconURL, pointSize: 14) {
                                    Image(nsImage: nsImg).resizable().scaledToFit().frame(width: 13, height: 13)
                                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                                } else {
                                    Image(systemName: sc.symbolIconName).font(.system(size: 11, weight: .semibold))
                                }
                                Text(sc.displayTitle)
                            }
                        }
                        .buttonStyle(GlassPillButtonStyle(prominent: form.selectedScriptID == sc.id, compact: true))
                    }
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
                GlassInputField(symbol: "link", placeholder: "https://github.com / lucent://settings/scripts / vscode://...", text: $form.bookmarkURL)
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
                    Button(L10n.pick("本地文件夹 / 文件路径", "Local Folder / File")) { form.isLocalPathMode = true }
                        .buttonStyle(GlassPillButtonStyle(prominent: form.isLocalPathMode, compact: true))
                    Button(L10n.pick("预设搜索词 / 短语", "Preset Search Query")) { form.isLocalPathMode = false }
                        .buttonStyle(GlassPillButtonStyle(prominent: !form.isLocalPathMode, compact: true))
                }
                if form.isLocalPathMode {
                    HStack(spacing: 8) {
                        GlassInputField(symbol: "folder", placeholder: "~/Documents/code", text: $form.localPathText)
                        Button(L10n.pick("选择…", "Browse…")) { browseLocalPath() }.buttonStyle(GlassPillButtonStyle(compact: true))
                    }
                } else {
                    GlassInputField(symbol: "magnifyingglass", placeholder: L10n.pick("如 ext:swift / !json / port 3000 / ;日报", "e.g. ext:swift / !json / port 3000"), text: $form.queryText)
                }
            }
        }
    }

    private func browseLocalPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { form.localPathText = url.path }
    }
}

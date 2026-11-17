import CoreGraphics
import Foundation
import LumakeyFoundation

public struct PluginUsageTip: Identifiable, Sendable, Hashable {
    public let id: String
    public let symbol: String
    public let title: String
    public let detail: String

    public init(id: String, symbol: String, title: String, detail: String) {
        self.id = id; self.symbol = symbol; self.title = title; self.detail = detail
    }
}

public struct PluginSystemPrivacyRequirement: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let settingsURL: String

    public init(id: String, title: String, settingsURL: String) {
        self.id = id
        self.title = title
        self.settingsURL = settingsURL
    }
}

public struct PluginSetupReadiness: Sendable, Hashable {
    public let missingRequiredSecrets: [String]
    public let ungrantedCapabilities: [PluginCapability]
    public let disabledScopes: [PluginResourceScope]
    public let missingTCCPermissions: [PluginSystemTCCKind]
    public let systemPrivacyRequirements: [PluginSystemPrivacyRequirement]
    public let hasFloatingWindow: Bool
    public let supportsSelection: Bool
    public let usageTips: [PluginUsageTip]

    public var hasMissingPermissions: Bool {
        !ungrantedCapabilities.isEmpty || !disabledScopes.isEmpty || !missingTCCPermissions.isEmpty || !systemPrivacyRequirements.isEmpty
    }

    public var missingPermissionCount: Int {
        ungrantedCapabilities.count + disabledScopes.count + missingTCCPermissions.count + systemPrivacyRequirements.count
    }

    public var hasBlockingIssues: Bool {
        !missingRequiredSecrets.isEmpty || hasMissingPermissions
    }

    public static func analyze(
        plugin: PluginDescriptor,
        dataStatus: PluginDataStatus? = nil,
        selectionQuickBarEnabled: Bool = true
    ) -> PluginSetupReadiness {
        let missingSecrets = dataStatus?.missingRequiredSecretKeys ?? []
        let ungrantedCaps = plugin.isBuiltin
            ? []
            : plugin.declaredCapabilities.filter { !plugin.grantedCapabilities.contains($0) }
        let disabledScopes = plugin.isBuiltin
            ? []
            : plugin.declaredResourceScopes.filter { !plugin.isResourceScopeGranted($0) }

        var tccSet = Set<PluginSystemTCCKind>()
        var missingTCC: [PluginSystemTCCKind] = []
        for cap in plugin.declaredCapabilities {
            if let tcc = PluginHostTCCBroker.requiredTCC(for: cap),
               tccSet.insert(tcc).inserted,
               !PluginHostTCCBroker.status(for: tcc).isGranted {
                missingTCC.append(tcc)
            }
        }

        let hasFloating = plugin.manifest.window != nil
        let supportsSel = plugin.declaredCapabilities.contains(.selection)
        let privacyReqs = detectSystemPrivacyRequirements(plugin: plugin, dataStatus: dataStatus)
        let tips = buildUsageTips(
            plugin: plugin,
            hasFloatingWindow: hasFloating,
            supportsSelection: supportsSel,
            selectionQuickBarEnabled: selectionQuickBarEnabled
        )

        return PluginSetupReadiness(
            missingRequiredSecrets: missingSecrets,
            ungrantedCapabilities: ungrantedCaps,
            disabledScopes: disabledScopes,
            missingTCCPermissions: missingTCC,
            systemPrivacyRequirements: privacyReqs,
            hasFloatingWindow: hasFloating,
            supportsSelection: supportsSel,
            usageTips: tips
        )
    }

    private static func detectSystemPrivacyRequirements(
        plugin: PluginDescriptor,
        dataStatus: PluginDataStatus?
    ) -> [PluginSystemPrivacyRequirement] {
        var reqs: [PluginSystemPrivacyRequirement] = []
        if plugin.id == "browser-hub" {
            let browsersRaw = (plugin.userConfig["enabledBrowsers"] ?? "edge,chrome,safari").lowercased()
            let needsSafari = browsersRaw.contains("safari")
            let safariDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Safari", isDirectory: true)
            let safariExists = FileManager.default.fileExists(atPath: safariDir.path)
            let safariDeniedByProbe = safariExists && !FileManager.default.isReadableFile(atPath: safariDir.appendingPathComponent("Bookmarks.plist").path)
            let safariDeniedByStatus = dataStatus?.runtimeStatus?.summary.contains("Safari 待授磁盘权限") == true
            if needsSafari && (safariDeniedByProbe || safariDeniedByStatus) {
                reqs.append(PluginSystemPrivacyRequirement(
                    id: "safari-full-disk-access",
                    title: L10n.pick("「完全磁盘访问权限」（用于读取 Safari 书签与历史）", "'Full Disk Access' (to read Safari bookmarks & history)"),
                    settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
                ))
            }
        }
        if plugin.id == "quick-remind",
           let summary = dataStatus?.runtimeStatus?.summary,
           summary.contains("未授权") || summary.localizedCaseInsensitiveContains("Automation") {
            reqs.append(PluginSystemPrivacyRequirement(
                id: "reminders-automation",
                title: L10n.pick("「自动化 -> 提醒事项」（用于同步到 Apple 提醒事项）", "'Automation -> Reminders' (for Apple Reminders sync)"),
                settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
            ))
        }
        return reqs
    }

    private static func buildUsageTips(
        plugin: PluginDescriptor,
        hasFloatingWindow: Bool,
        supportsSelection: Bool,
        selectionQuickBarEnabled: Bool
    ) -> [PluginUsageTip] {
        var tips: [PluginUsageTip] = []
        let primaryKW = plugin.effectiveKeywords.first ?? plugin.id
        let cmdCount = plugin.declaredCommands.count
        let cmdSummary = cmdCount > 0
            ? L10n.pick("按 Tab 进入插件子功能列表（共 \(cmdCount) 项）", "Press Tab to browse its \(cmdCount) command(s)")
            : L10n.pick("按回车直接运行", "Press Return to run")

        tips.append(PluginUsageTip(
            id: "launcher",
            symbol: "command.square.fill",
            title: L10n.pick("快捷台快速唤起", "Launch from Search Bar"),
            detail: L10n.pick(
                "按 ⌥Space 打开快捷台，输入「\(primaryKW)」即可命中；\(cmdSummary)。",
                "Press ⌥Space, type \"\(primaryKW)\" to match this plugin; \(cmdSummary)."
            )
        ))

        if supportsSelection {
            let barState = selectionQuickBarEnabled
                ? L10n.pick("已开启「鼠标划词气泡」：在任意软件中拖选或双击文字后，光标旁会自动出现按钮。", "Selection Quick Bar is ON: highlight text anywhere and click the floating button.")
                : L10n.pick("可在上方开启「鼠标划词悬浮气泡」，选中文字后自动弹出按钮；也可绑定下方全局热键。", "Turn on Selection Quick Bar above to show buttons when highlighting text, or bind a hotkey.")
            tips.append(PluginUsageTip(
                id: "selection",
                symbol: "text.cursor",
                title: L10n.pick("跨应用滑动取词", "Highlight Text Anywhere"),
                detail: barState
            ))
        }

        if hasFloatingWindow {
            tips.append(PluginUsageTip(
                id: "window",
                symbol: "macwindow.on.rectangle",
                title: L10n.pick("独立桌面小悬浮窗", "Desktop Floating Widget"),
                detail: L10n.pick(
                    "点击顶部「打开桌面悬浮窗」可在桌面置顶常显，支持拖拽、折叠、调透明度与自动刷新。",
                    "Click \"Open Floating Widget\" above to pin a translucent live widget on your desktop."
                )
            ))
        }

        let accepts = Set(plugin.manifest.accepts ?? [])
        if accepts.contains("image") || plugin.declaredCapabilities.contains(.ocr) {
            tips.append(PluginUsageTip(
                id: "ocr-image",
                symbol: "text.viewfinder",
                title: L10n.pick("截图 / 图片联动", "Screenshot & Image Actions"),
                detail: L10n.pick(
                    "在 ⌥O 截图识字结果窗或文件预览选中图片后，可直接点击「发送到 \(plugin.displayName)」。",
                    "After ⌥O screenshot OCR or image preview, choose \"Send to \(plugin.displayName)\"."
                )
            ))
        }
        return tips
    }
}

public enum SelectionQuickBarFilter {
    public static let minDragDistance: CGFloat = 6.0
    public static let maxSelectionLength: Int = 600

    public static func shouldTriggerOnMouseRelease(dragDistance: CGFloat, clickCount: Int) -> Bool {
        clickCount >= 2 || dragDistance >= minDragDistance
    }

    public static func normalizedSelectionText(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxSelectionLength else { return nil }
        return trimmed
    }
}

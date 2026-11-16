import Foundation

public enum BuiltinPluginID: String, CaseIterable, Sendable {
    case mos = "builtin-mos"
    case lumaLink = "builtin-lumalink"
    case systemPulse = "builtin-system-pulse"
}

public struct BuiltinPluginConfigPaths: Sendable {
    public let mosURL: URL
    public let lumaLinkURL: URL
    public let monitorURL: URL

    public init(
        mosURL: URL = MosConfig.defaultConfigURL(),
        lumaLinkURL: URL = LumaLinkConfig.defaultConfigURL(),
        monitorURL: URL = SystemMonitorConfig.defaultURL
    ) {
        self.mosURL = mosURL
        self.lumaLinkURL = lumaLinkURL
        self.monitorURL = monitorURL
    }

    public static let `default` = BuiltinPluginConfigPaths()
}

public enum PluginBuiltinRegistry {
    public static func isBuiltin(id: String) -> Bool {
        BuiltinPluginID(rawValue: id) != nil || id.hasPrefix("builtin-")
    }

    public static func descriptors(
        mosConfig: MosConfig? = nil,
        lumaLinkConfig: LumaLinkConfig? = nil,
        monitorConfig: SystemMonitorConfig? = nil,
        configPaths: BuiltinPluginConfigPaths = .default,
        mosTapActive: Bool = MosEngine.shared.isTapActive,
        mosAccessibilityTrusted: Bool = MosEngine.shared.isAccessibilityTrusted,
        lumaLinkSnapshot: LumaLinkRuntimeSnapshot = LumaLinkServer.shared.currentSnapshot(),
        overridesByID: [String: PluginUserOverrides] = [:]
    ) -> [PluginDescriptor] {
        [
            makeMosDescriptor(
                config: mosConfig ?? MosConfig.load(from: configPaths.mosURL),
                tapActive: mosTapActive, trusted: mosAccessibilityTrusted,
                overrides: overridesByID[BuiltinPluginID.mos.rawValue] ?? PluginUserOverrides()
            ),
            makeLumaLinkDescriptor(
                config: lumaLinkConfig ?? LumaLinkConfig.load(from: configPaths.lumaLinkURL),
                snapshot: lumaLinkSnapshot, trusted: mosAccessibilityTrusted,
                overrides: overridesByID[BuiltinPluginID.lumaLink.rawValue] ?? PluginUserOverrides()
            ),
            makeSystemPulseDescriptor(
                config: monitorConfig ?? SystemMonitorConfig.load(from: configPaths.monitorURL),
                overrides: overridesByID[BuiltinPluginID.systemPulse.rawValue] ?? PluginUserOverrides()
            )
        ]
    }

    @discardableResult
    public static func setBuiltinEnabled(
        id: String,
        isEnabled: Bool,
        configPaths: BuiltinPluginConfigPaths = .default
    ) -> Bool {
        guard let builtin = BuiltinPluginID(rawValue: id) else { return false }
        switch builtin {
        case .mos:
            var cfg = MosConfig.load(from: configPaths.mosURL)
            cfg.enabled = isEnabled
            MosEngine.shared.apply(config: cfg, persist: false)
            cfg.save(to: configPaths.mosURL)
        case .lumaLink:
            var cfg = LumaLinkConfig.load(from: configPaths.lumaLinkURL)
            cfg.enabled = isEnabled
            LumaLinkServer.shared.apply(config: cfg, persist: false)
            cfg.save(to: configPaths.lumaLinkURL)
        case .systemPulse:
            var cfg = SystemMonitorConfig.load(from: configPaths.monitorURL)
            cfg.floatingEnabled = isEnabled
            if !isEnabled { cfg.showInMenuBar = false }
            cfg.save(to: configPaths.monitorURL)
        }
        return true
    }

    public static func runBuiltin(
        id: String,
        query: String = "",
        arguments: [String] = [],
        configPaths: BuiltinPluginConfigPaths = .default
    ) -> PluginResolvedOutput? {
        guard let desc = descriptors(configPaths: configPaths).first(where: { $0.id == id }) else { return nil }
        if let firstArg = arguments.first {
            PluginBuiltinCommands.applyActionArgument(
                firstArg, for: id, currentlyEnabled: desc.isEnabled, configPaths: configPaths
            )
        }
        let refreshed = descriptors(configPaths: configPaths).first(where: { $0.id == id }) ?? desc
        let payload = buildViewPayload(for: refreshed, query: query, arguments: arguments)
        let data = (try? JSONEncoder().encode(payload)) ?? Data()
        let json = String(data: data, encoding: .utf8) ?? "{}"
        let exec = PluginExecutionResult(exitCode: 0, stdout: json, stderr: "", durationMs: 1)
        return PluginResolvedOutput(descriptor: refreshed, execution: exec)
    }

    private static func makeMosDescriptor(
        config: MosConfig, tapActive: Bool, trusted: Bool, overrides: PluginUserOverrides
    ) -> PluginDescriptor {
        let status: String = if !config.enabled {
            L10n.pick("已关闭 · 未安装 CGEventTap（零系统事件回调消耗）", "Off · No CGEventTap installed (0% overhead)")
        } else if !trusted {
            L10n.pick("已启用但未获宿主「辅助功能」授权", "Enabled · Waiting for Accessibility permission")
        } else if tapActive {
            L10n.pick("已激活 · 正在平滑拦截物理鼠标滚轮", "Active · Smoothing physical mouse wheel")
        } else {
            L10n.pick("辅助功能已就绪 · 准备激活", "Accessibility granted · Ready")
        }
        let manifest = PluginManifest(
            id: BuiltinPluginID.mos.rawValue,
            name: L10n.pick("鼠标平滑与滚轮反转", "Smooth Mouse & Wheel Reversal"),
            version: "3.0.0",
            description: L10n.pick("自动区分物理鼠标与触控板，提供滚轮反转与 120Hz 平滑插值；关闭即零后台消耗。", "Independently reverses physical mouse wheel & adds 120Hz smooth scrolling while keeping trackpad natural."),
            mode: .view,
            keywords: ["mouse", "scroll", "滚轮", "鼠标平滑"],
            entry: "builtin://mos",
            author: "Lumakey Native",
            icon: "computermouse.fill",
            commands: PluginBuiltinCommands.mosCommands
        )
        return PluginDescriptor(
            id: manifest.id,
            directoryURL: URL(fileURLWithPath: "/Lumakey/Builtin/mos"),
            manifest: manifest,
            validationIssues: [],
            isEnabled: config.enabled,
            userConfig: [
                "reverseWheelDirection": String(config.reverseWheelDirection),
                "smoothScroll": String(config.smoothScroll),
                "stepPixels": String(Int(config.stepPixels)),
                "smoothness": String(format: "%.2f", config.smoothness)
            ],
            kind: .builtin,
            overrides: overrides,
            builtinMetadata: BuiltinPluginMetadata(
                categoryBadge: "BUILTIN",
                requiredPermissions: [.accessibility],
                settingsTarget: "mos",
                statusSummary: status
            )
        )
    }

    private static func makeLumaLinkDescriptor(
        config: LumaLinkConfig,
        snapshot: LumaLinkRuntimeSnapshot,
        trusted: Bool,
        overrides: PluginUserOverrides
    ) -> PluginDescriptor {
        let ip = LumaLinkServer.localIPv4Address() ?? L10n.pick("局域网", "LAN")
        let status: String = if !config.enabled {
            L10n.pick("已关闭 · 零网络监听、零 RDP 子进程、零内存驻留", "Off · Zero network listeners, RDP helpers, or memory")
        } else if let err = snapshot.lastError, !err.isEmpty {
            L10n.pick("监听异常：\(err)", "Listener error: \(err)")
        } else if snapshot.isListening {
            L10n.pick("广播 _lumakey-remote._tcp · \(ip):\(snapshot.port) · 已连 \(snapshot.connectedDeviceCount) 台", "Advertising _lumakey-remote._tcp · \(ip):\(snapshot.port) · \(snapshot.connectedDeviceCount) connected")
        } else {
            L10n.pick("正在启动 Bonjour 监听…", "Starting Bonjour listener…")
        }
        let manifest = PluginManifest(
            id: BuiltinPluginID.lumaLink.rawValue,
            name: L10n.pick("流光随行 · LumaLink 远控伴侣", "LumaLink Remote Companion"),
            version: "3.0.0",
            description: L10n.pick("提供真·分辨率切换、隐私黑屏、中文直发、音频透传与 RDP 加速；关闭即刻回收所有监听与助手进程。", "Native resolution switch, privacy curtain, CJK input, audio & RDP acceleration; zero background processes when off."),
            mode: .view,
            keywords: ["lumalink", "remote", "rdp", "流光随行", "远控"],
            entry: "builtin://lumalink",
            author: "Lumakey Native",
            icon: "ipad.and.iphone",
            commands: PluginBuiltinCommands.lumaLinkCommands
        )
        return PluginDescriptor(
            id: manifest.id,
            directoryURL: URL(fileURLWithPath: "/Lumakey/Builtin/lumalink"),
            manifest: manifest,
            validationIssues: [],
            isEnabled: config.enabled,
            userConfig: [
                "rdpEnabled": String(config.rdpEnabled),
                "rdpPort": String(config.rdpPort),
                "pairedDeviceCount": String(config.pairedDevices.count),
                "accessibilityTrusted": String(trusted)
            ],
            kind: .builtin,
            overrides: overrides,
            builtinMetadata: BuiltinPluginMetadata(
                categoryBadge: "BUILTIN",
                requiredPermissions: [.accessibility, .screenRecording, .localNetwork, .microphoneAndAudio, .displayInfo],
                settingsTarget: "lumaLink",
                statusSummary: status
            )
        )
    }

    private static func makeSystemPulseDescriptor(
        config: SystemMonitorConfig, overrides: PluginUserOverrides
    ) -> PluginDescriptor {
        let active = config.floatingEnabled || config.showInMenuBar
        let status = active
            ? L10n.pick("运行中 · 悬浮窗(\(config.floatingEnabled ? "开" : "关")) 菜单栏(\(config.showInMenuBar ? "开" : "关"))", "Active · Widget(\(config.floatingEnabled ? "ON" : "OFF")) MenuBar(\(config.showInMenuBar ? "ON" : "OFF"))")
            : L10n.pick("已关闭 · 零采样定时器与零悬浮窗口占用", "Off · Zero sampling timers or floating panel overhead")
        let manifest = PluginManifest(
            id: BuiltinPluginID.systemPulse.rawValue,
            name: L10n.pick("系统脉搏桌面监控悬浮窗", "System Pulse Desktop Monitor"),
            version: "3.0.0",
            description: L10n.pick("实时采样 CPU、DVFS 频率、内存、功耗与网速，支持贴边自动隐藏与菜单栏紧凑读数。", "Live CPU, DVFS frequency, memory, power & network speed with edge auto-hide and menu bar readout."),
            mode: .view,
            keywords: ["pulse", "monitor", "cpu", "系统脉搏", "监控"],
            entry: "builtin://system-pulse",
            author: "Lumakey Native",
            icon: "waveform.path.ecg",
            commands: PluginBuiltinCommands.systemPulseCommands
        )
        return PluginDescriptor(
            id: manifest.id,
            directoryURL: URL(fileURLWithPath: "/Lumakey/Builtin/system-pulse"),
            manifest: manifest,
            validationIssues: [],
            isEnabled: active,
            userConfig: [
                "floatingEnabled": String(config.floatingEnabled),
                "showInMenuBar": String(config.showInMenuBar),
                "displayMode": config.displayMode.rawValue
            ],
            kind: .builtin,
            overrides: overrides,
            builtinMetadata: BuiltinPluginMetadata(
                categoryBadge: "BUILTIN",
                requiredPermissions: [.telemetrySampling],
                settingsTarget: "monitor",
                statusSummary: status
            )
        )
    }

    private static func buildViewPayload(for desc: PluginDescriptor, query: String, arguments: [String] = []) -> PluginViewPayload {
        let meta = desc.builtinMetadata
        var metrics: [PluginKeyValue] = [
            PluginKeyValue(key: L10n.pick("运行状态", "Status"), value: desc.isEnabled ? L10n.pick("已启用", "Enabled") : L10n.pick("已关闭（零开销）", "Off (0% overhead)")),
            PluginKeyValue(key: L10n.pick("运行模式", "Mode"), value: L10n.pick("同进程原生 (BUILTIN)", "In-Process Native (BUILTIN)"))
        ]
        for (k, v) in desc.userConfig.sorted(by: { $0.key < $1.key }).prefix(4) {
            metrics.append(PluginKeyValue(key: k, value: v))
        }
        let target = meta?.settingsTarget ?? "plugins"
        let tccText = (meta?.requiredTCCPermissions ?? []).joined(separator: " · ")
        let toggleAction = desc.isEnabled ? "--disable" : "--enable"
        let toggleLabel = desc.isEnabled ? L10n.pick("停用内置服务", "Disable Built-in Service") : L10n.pick("启用内置服务", "Enable Built-in Service")
        return PluginViewPayload(
            title: desc.manifest.name,
            subtitle: meta?.statusSummary ?? desc.manifest.description,
            badge: "BUILTIN",
            markdown: query.isEmpty ? L10n.pick("复用宿主 TCC 权限：\(tccText)", "Shared Host TCC: \(tccText)") : L10n.pick("复用宿主 TCC 权限：\(tccText)\n查询参数：`\(query)`", "Shared Host TCC: \(tccText)\nQuery: `\(query)`"),
            metrics: metrics,
            items: [
                PluginViewItem(
                    explicitID: "\(desc.id)-open-settings",
                    title: L10n.pick("打开完整原生设置视图", "Open Native Settings"),
                    subtitle: L10n.pick("配置详细参数与宿主 TCC 授权状态", "Configure options & inspect host TCC status"),
                    icon: desc.manifest.icon ?? "slider.horizontal.3",
                    badge: L10n.pick("原生面板", "NATIVE"),
                    openURL: "lumakey://settings/\(target)"
                ),
                PluginViewItem(
                    explicitID: "\(desc.id)-toggle",
                    title: toggleLabel,
                    subtitle: L10n.pick("通过统一命令路由原地切换开关（零常驻开销）", "Toggle built-in service in place (zero idle overhead)"),
                    icon: desc.isEnabled ? "pause.circle" : "play.circle.fill",
                    badge: desc.isEnabled ? "ON" : "OFF",
                    commandArgs: [toggleAction]
                )
            ]
        )
    }
}

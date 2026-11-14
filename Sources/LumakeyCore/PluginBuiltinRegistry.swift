import Foundation

public enum BuiltinPluginID: String, CaseIterable, Sendable {
    case mos = "builtin-mos"
    case lumaLink = "builtin-lumalink"
    case systemPulse = "builtin-system-pulse"
}

public enum PluginBuiltinRegistry {
    public static func isBuiltin(id: String) -> Bool {
        BuiltinPluginID(rawValue: id) != nil || id.hasPrefix("builtin-")
    }

    public static func descriptors(
        mosConfig: MosConfig = MosConfig.load(),
        lumaLinkConfig: LumaLinkConfig = LumaLinkConfig.load(),
        monitorConfig: SystemMonitorConfig = SystemMonitorConfig.load(),
        mosTapActive: Bool = MosEngine.shared.isTapActive,
        mosAccessibilityTrusted: Bool = MosEngine.shared.isAccessibilityTrusted,
        lumaLinkSnapshot: LumaLinkRuntimeSnapshot = LumaLinkServer.shared.currentSnapshot()
    ) -> [PluginDescriptor] {
        [
            makeMosDescriptor(config: mosConfig, tapActive: mosTapActive, trusted: mosAccessibilityTrusted),
            makeLumaLinkDescriptor(config: lumaLinkConfig, snapshot: lumaLinkSnapshot, trusted: mosAccessibilityTrusted),
            makeSystemPulseDescriptor(config: monitorConfig)
        ]
    }

    @discardableResult
    public static func setBuiltinEnabled(id: String, isEnabled: Bool) -> Bool {
        guard let builtin = BuiltinPluginID(rawValue: id) else { return false }
        switch builtin {
        case .mos:
            var cfg = MosConfig.load()
            cfg.enabled = isEnabled
            MosEngine.shared.apply(config: cfg, persist: true)
        case .lumaLink:
            var cfg = LumaLinkConfig.load()
            cfg.enabled = isEnabled
            LumaLinkServer.shared.apply(config: cfg, persist: true)
        case .systemPulse:
            var cfg = SystemMonitorConfig.load()
            cfg.floatingEnabled = isEnabled
            if !isEnabled { cfg.showInMenuBar = false }
            cfg.save()
        }
        return true
    }

    public static func runBuiltin(id: String, query: String = "") -> PluginResolvedOutput? {
        guard let desc = descriptors().first(where: { $0.id == id }) else { return nil }
        let payload = buildViewPayload(for: desc, query: query)
        let data = (try? JSONEncoder().encode(payload)) ?? Data()
        let json = String(data: data, encoding: .utf8) ?? "{}"
        let exec = PluginExecutionResult(exitCode: 0, stdout: json, stderr: "", durationMs: 1)
        return PluginResolvedOutput(descriptor: desc, execution: exec)
    }

    private static func makeMosDescriptor(config: MosConfig, tapActive: Bool, trusted: Bool) -> PluginDescriptor {
        let status: String = if !config.enabled {
            "已关闭 · 未安装 CGEventTap（零系统事件回调消耗）"
        } else if !trusted {
            "已启用但未获宿主「辅助功能」授权"
        } else if tapActive {
            "已激活 · 正在平滑拦截物理鼠标滚轮"
        } else {
            "辅助功能已就绪 · 准备激活"
        }
        let manifest = PluginManifest(
            id: BuiltinPluginID.mos.rawValue,
            name: "Mos 鼠标平滑与滚轮方向",
            version: "3.0.0",
            description: "自动区分物理鼠标与触控板，提供滚轮反转与 120Hz 平滑插值；关闭即零后台消耗。",
            mode: .view,
            keywords: ["mos", "mouse", "scroll", "鼠标平滑"],
            entry: "builtin://mos",
            author: "Lumakey Native",
            icon: "computermouse.fill"
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
        trusted: Bool
    ) -> PluginDescriptor {
        let ip = LumaLinkServer.localIPv4Address() ?? "局域网"
        let status: String = if !config.enabled {
            "已关闭 · 零网络监听、零 RDP 子进程、零内存驻留"
        } else if let err = snapshot.lastError, !err.isEmpty {
            "监听异常：\(err)"
        } else if snapshot.isListening {
            "广播 _lumakey-remote._tcp · \(ip):\(snapshot.port) · 已连 \(snapshot.connectedDeviceCount) 台"
        } else {
            "正在启动 Bonjour 监听…"
        }
        let manifest = PluginManifest(
            id: BuiltinPluginID.lumaLink.rawValue,
            name: "流光随行 · LumaLink 远控伴侣",
            version: "3.0.0",
            description: "提供真·分辨率切换、隐私黑屏、中文直发、音频透传与 RDP 加速；关闭即刻回收所有监听与助手进程。",
            mode: .view,
            keywords: ["lumalink", "remote", "rdp", "流光随行", "远控"],
            entry: "builtin://lumalink",
            author: "Lumakey Native",
            icon: "ipad.and.iphone"
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
            builtinMetadata: BuiltinPluginMetadata(
                categoryBadge: "BUILTIN",
                requiredPermissions: [.accessibility, .screenRecording, .localNetwork, .microphoneAndAudio, .displayInfo],
                settingsTarget: "lumaLink",
                statusSummary: status
            )
        )
    }

    private static func makeSystemPulseDescriptor(config: SystemMonitorConfig) -> PluginDescriptor {
        let active = config.floatingEnabled || config.showInMenuBar
        let status = active
            ? "运行中 · 悬浮窗(\(config.floatingEnabled ? "开" : "关")) 菜单栏(\(config.showInMenuBar ? "开" : "关"))"
            : "已关闭 · 零采样定时器与零悬浮窗口占用"
        let manifest = PluginManifest(
            id: BuiltinPluginID.systemPulse.rawValue,
            name: "系统脉搏桌面监控悬浮窗",
            version: "3.0.0",
            description: "实时采样 CPU、DVFS 频率、内存、功耗与网速，支持贴边自动隐藏与菜单栏紧凑读数。",
            mode: .view,
            keywords: ["pulse", "monitor", "cpu", "系统脉搏", "监控"],
            entry: "builtin://system-pulse",
            author: "Lumakey Native",
            icon: "waveform.path.ecg"
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
            builtinMetadata: BuiltinPluginMetadata(
                categoryBadge: "BUILTIN",
                requiredPermissions: [.telemetrySampling],
                settingsTarget: "monitor",
                statusSummary: status
            )
        )
    }

    private static func buildViewPayload(for desc: PluginDescriptor, query: String) -> PluginViewPayload {
        let meta = desc.builtinMetadata
        var metrics: [PluginKeyValue] = [
            PluginKeyValue(key: "运行状态", value: desc.isEnabled ? "已启用" : "已关闭（零开销）"),
            PluginKeyValue(key: "运行模式", value: "同进程原生 (BUILTIN)")
        ]
        for (k, v) in desc.userConfig.sorted(by: { $0.key < $1.key }).prefix(4) {
            metrics.append(PluginKeyValue(key: k, value: v))
        }
        let target = meta?.settingsTarget ?? "plugins"
        let tccText = (meta?.requiredTCCPermissions ?? []).joined(separator: " · ")
        return PluginViewPayload(
            title: desc.manifest.name,
            subtitle: meta?.statusSummary ?? desc.manifest.description,
            badge: "BUILTIN",
            markdown: query.isEmpty ? "复用宿主 TCC 权限：\(tccText)" : "复用宿主 TCC 权限：\(tccText)\n查询参数：`\(query)`",
            metrics: metrics,
            items: [
                PluginViewItem(
                    title: "打开完整原生设置视图",
                    subtitle: "配置详细参数与宿主 TCC 授权状态",
                    icon: desc.manifest.icon ?? "slider.horizontal.3",
                    badge: "原生面板",
                    openURL: "lumakey://settings/\(target)"
                )
            ]
        )
    }
}

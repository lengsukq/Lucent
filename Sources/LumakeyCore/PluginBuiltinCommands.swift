import Foundation

public enum PluginBuiltinCommands {
    public static var mosCommands: [PluginCommandSpec] {
        [
            PluginCommandSpec(
                id: "mos-toggle",
                title: L10n.pick("切换鼠标平滑总开关", "Toggle Mouse Smooth Scroll"),
                subtitle: L10n.pick("一键开启或停用物理鼠标平滑与滚轮方向服务", "Enable or disable physical mouse smooth scroll & wheel direction"),
                keywords: ["鼠标平滑开关", "滚轮开关", "mousesmooth", "toggle mouse"],
                icon: "power",
                arguments: ["--toggle-enabled"],
                passQuery: false
            ),
            PluginCommandSpec(
                id: "mos-reverse",
                title: L10n.pick("切换鼠标滚轮反转方向", "Toggle Mouse Wheel Reversal"),
                subtitle: L10n.pick("独立翻转物理鼠标滚轮方向，不影响触控板手势", "Reverse physical mouse scroll direction independently of trackpad"),
                keywords: ["滚轮反转", "鼠标方向", "wheelreverse", "reverse wheel"],
                icon: "arrow.up.arrow.down.circle",
                arguments: ["--toggle-reverse"],
                passQuery: false
            ),
            PluginCommandSpec(
                id: "mos-smooth",
                title: L10n.pick("切换 120Hz 平滑滚动插值", "Toggle 120Hz Smooth Interpolation"),
                subtitle: L10n.pick("开启或关闭高刷屏物理滚轮像素级平滑插值", "Toggle high-refresh pixel-smooth interpolation for mouse wheels"),
                keywords: ["平滑滚动", "120hz滚动", "smoothscroll", "smooth wheel"],
                icon: "waveform.path",
                arguments: ["--toggle-smooth"],
                passQuery: false
            )
        ]
    }

    public static var lumaLinkCommands: [PluginCommandSpec] {
        [
            PluginCommandSpec(
                id: "lumalink-toggle",
                title: L10n.pick("开关流光随行远控服务", "Toggle LumaLink Remote Companion"),
                subtitle: L10n.pick("一键启停局域网 Bonjour 广播与远控伴侣监听", "Start or stop LAN Bonjour discovery & remote companion listener"),
                keywords: ["远控开关", "流光开关", "togglelumalink", "remote toggle"],
                icon: "power",
                arguments: ["--toggle-enabled"],
                passQuery: false
            ),
            PluginCommandSpec(
                id: "lumalink-rdp",
                title: L10n.pick("切换流光随行 RDP 加速引擎", "Toggle LumaLink RDP Acceleration"),
                subtitle: L10n.pick("切换局域网远程桌面高帧率 RDP 加速开关", "Enable or disable VideoToolbox H.264 RDP acceleration"),
                keywords: ["rdp开关", "远控rdp", "togglerdp", "rdp engine"],
                icon: "bolt.horizontal.circle",
                arguments: ["--toggle-rdp"],
                passQuery: false
            )
        ]
    }

    public static var systemPulseCommands: [PluginCommandSpec] {
        [
            PluginCommandSpec(
                id: "pulse-floating",
                title: L10n.pick("开关系统脉搏桌面悬浮窗", "Toggle System Pulse Floating Widget"),
                subtitle: L10n.pick("显示或收起 CPU/内存/功耗实时监控桌面悬浮窗", "Show or hide the live CPU/RAM/Power floating monitor"),
                keywords: ["脉搏悬浮窗", "监控悬浮窗", "togglepulse", "pulse widget"],
                icon: "pip",
                arguments: ["--toggle-floating"],
                passQuery: false
            ),
            PluginCommandSpec(
                id: "pulse-menubar",
                title: L10n.pick("开关菜单栏实时性能读数", "Toggle Menu Bar Live Readout"),
                subtitle: L10n.pick("在 macOS 顶部菜单栏显示或隐藏紧凑性能与网速读数", "Show or hide compact CPU/Power/Network readout in the menu bar"),
                keywords: ["菜单栏监控", "状态栏网速", "pulsemenubar", "menubar stats"],
                icon: "menubar.rectangle",
                arguments: ["--toggle-menubar"],
                passQuery: false
            )
        ]
    }

    public static func applyActionArgument(
        _ argument: String,
        for pluginID: String,
        currentlyEnabled: Bool,
        configPaths: BuiltinPluginConfigPaths
    ) {
        switch argument {
        case "--toggle-enabled":
            _ = PluginBuiltinRegistry.setBuiltinEnabled(id: pluginID, isEnabled: !currentlyEnabled, configPaths: configPaths)
        case "--enable":
            _ = PluginBuiltinRegistry.setBuiltinEnabled(id: pluginID, isEnabled: true, configPaths: configPaths)
        case "--disable":
            _ = PluginBuiltinRegistry.setBuiltinEnabled(id: pluginID, isEnabled: false, configPaths: configPaths)
        case "--toggle-reverse" where pluginID == BuiltinPluginID.mos.rawValue:
            var cfg = MosConfig.load(from: configPaths.mosURL)
            cfg.reverseWheelDirection.toggle()
            MosEngine.shared.apply(config: cfg, persist: false)
            cfg.save(to: configPaths.mosURL)
        case "--toggle-smooth" where pluginID == BuiltinPluginID.mos.rawValue:
            var cfg = MosConfig.load(from: configPaths.mosURL)
            cfg.smoothScroll.toggle()
            MosEngine.shared.apply(config: cfg, persist: false)
            cfg.save(to: configPaths.mosURL)
        case "--toggle-rdp" where pluginID == BuiltinPluginID.lumaLink.rawValue:
            var cfg = LumaLinkConfig.load(from: configPaths.lumaLinkURL)
            cfg.rdpEnabled.toggle()
            LumaLinkServer.shared.apply(config: cfg, persist: false)
            cfg.save(to: configPaths.lumaLinkURL)
        case "--toggle-floating" where pluginID == BuiltinPluginID.systemPulse.rawValue:
            var cfg = SystemMonitorConfig.load(from: configPaths.monitorURL)
            cfg.floatingEnabled.toggle()
            cfg.save(to: configPaths.monitorURL)
        case "--toggle-menubar" where pluginID == BuiltinPluginID.systemPulse.rawValue:
            var cfg = SystemMonitorConfig.load(from: configPaths.monitorURL)
            cfg.showInMenuBar.toggle()
            cfg.save(to: configPaths.monitorURL)
        default:
            break
        }
    }
}

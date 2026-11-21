import AppKit
import CoreGraphics
import LucentCore
import SwiftUI

struct LumaLinkServiceControlCard: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var deviceServices: DeviceServicesStore
    let companionPlugin: PluginDescriptor?
    let ctrl: PluginCenterController?

    init(viewModel: AppViewModel, companionPlugin: PluginDescriptor?, ctrl: PluginCenterController?) {
        self.viewModel = viewModel
        self._deviceServices = ObservedObject(wrappedValue: viewModel.deviceServices)
        self.companionPlugin = companionPlugin
        self.ctrl = ctrl
    }

    var body: some View {
        let cfg = viewModel.lumaLinkConfig
        let snap = viewModel.lumaLinkStatus
        let rdp = viewModel.lumaLinkRdpStatus
        let ep = LumaLinkServer.shared.resolvedConnectEndpoint()
        let bothOn = cfg.enabled && cfg.rdpEnabled

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                SquircleBadge(symbol: "ipad.and.iphone", topColor: .cyan, bottomColor: .blue, size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.pick("流光随行 · 手机远控与极速桌面", "LumaLink · Phone Remote & Turbo RDP"))
                        .font(.title3.weight(.bold))
                    Text(L10n.pick("控制监听负责扫码配对与快捷控制；手机端查看实时桌面画面请同时开启右侧「极速 RDP 服务」。", "Listener handles pairing & quick controls; enable 'Turbo RDP Service' on the right for live desktop streaming."))
                        .font(.caption).foregroundStyle(LiquidColors.textSecondary)
                }
                Spacer(minLength: 8)
                Button(bothOn ? L10n.pick("全部停用", "Stop All") : L10n.pick("一键全开（远控 + 极速 RDP）", "Start All (Remote + RDP)")) {
                    setServices(listener: !bothOn, rdp: !bothOn)
                }
                .buttonStyle(GlassPillButtonStyle(prominent: !bothOn))
            }

            HStack(alignment: .top, spacing: 10) {
                listenerTile(cfg: cfg, snap: snap, ep: ep)
                rdpTile(cfg: cfg, rdp: rdp)
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: LiquidRadii.bento, solidReadable: true)
    }

    private func listenerTile(
        cfg: LumaLinkConfig, snap: LumaLinkRuntimeSnapshot,
        ep: (host: String, port: UInt16, candidate: LumaLinkNetworkCandidate?, isCustomHost: Bool)
    ) -> some View {
        let dot: Color = !cfg.enabled ? .secondary : (snap.isListening ? .mint : .orange)
        let desc: String = if !cfg.enabled {
            L10n.pick("已关闭 · 零端口监听", "Off · Zero open ports")
        } else if let err = snap.lastError, !err.isEmpty {
            L10n.pick("监听异常：\(err)", "Error: \(err)")
        } else if snap.isListening {
            L10n.pick("监听中 \(ep.host):\(ep.port) · 在线 \(snap.connectedDeviceCount) 台", "Listening \(ep.host):\(ep.port) · \(snap.connectedDeviceCount) live")
        } else {
            L10n.pick("正在启动监听…", "Starting listener…")
        }

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Circle().fill(dot).frame(width: 8, height: 8)
                Text(L10n.pick("① 基础远控监听", "1. Remote Control Listener")).font(.callout.weight(.semibold))
                Spacer()
                Button(cfg.enabled ? L10n.pick("关闭监听", "Turn Off") : L10n.pick("开启监听", "Turn On")) {
                    setServices(listener: !cfg.enabled, rdp: !cfg.enabled ? cfg.rdpEnabled : false)
                }
                .buttonStyle(GlassPillButtonStyle(prominent: !cfg.enabled, compact: true))
            }
            Text(desc).font(.caption2).foregroundStyle(LiquidColors.textSecondary).fixedSize(horizontal: false, vertical: true)
            if !viewModel.mosAccessibilityTrusted {
                Button(L10n.pick("授权辅助功能（支持远控键鼠/音量）", "Grant Accessibility")) {
                    viewModel.requestMosAccessibilityPermission()
                }
                .buttonStyle(GlassPillButtonStyle(compact: true))
            }
        }
        .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LiquidColors.pillSurface, in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous).strokeBorder(LiquidColors.pillBorder, lineWidth: 0.8) }
    }

    private func rdpTile(cfg: LumaLinkConfig, rdp: LumaLinkRdpStatus) -> some View {
        let screenRecOK = CGPreflightScreenCaptureAccess()
        let dot: Color = !cfg.rdpEnabled ? .secondary : (rdp.running ? .green : .orange)
        let desc: String = if !cfg.rdpEnabled {
            L10n.pick("未开启 · 手机提示「开启极速 RDP」时请点右上开启", "Off · Turn on here for mobile live screen streaming")
        } else if rdp.running {
            L10n.pick("极速引擎运行中 · 端口 \(rdp.port) (H.264 硬编)", "Running on port \(rdp.port) (H.264 HW encode)")
        } else if !rdp.binaryFound {
            L10n.pick("缺少 macos-rdp-daemon 助手组件，请点击下方导入", "Missing macos-rdp-daemon helper binary")
        } else if let err = rdp.lastError, !err.isEmpty {
            L10n.pick("未就绪：\(err)", "Not ready: \(err)")
        } else {
            L10n.pick("正在启动极速 RDP 引擎…", "Starting Turbo RDP engine…")
        }

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Circle().fill(dot).frame(width: 8, height: 8)
                Text(L10n.pick("② 极速 RDP 桌面服务", "2. Turbo RDP Service")).font(.callout.weight(.semibold))
                Spacer()
                Button(cfg.rdpEnabled ? L10n.pick("关闭极速 RDP", "Disable RDP") : L10n.pick("开启极速 RDP", "Enable Turbo RDP")) {
                    let turnOn = !cfg.rdpEnabled
                    setServices(listener: turnOn ? true : cfg.enabled, rdp: turnOn)
                }
                .buttonStyle(GlassPillButtonStyle(prominent: !cfg.rdpEnabled, compact: true))
            }
            Text(desc)
                .font(.caption2).foregroundStyle((cfg.rdpEnabled && !rdp.running) ? .orange : LiquidColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                if !rdp.binaryFound {
                    Button(L10n.pick("选择 macos-rdp-daemon…", "Locate macos-rdp-daemon…")) { pickAndInstallRdpHelper() }
                        .buttonStyle(GlassPillButtonStyle(prominent: true, compact: true))
                }
                if cfg.rdpEnabled && !screenRecOK {
                    Button(L10n.pick("授权屏幕录制", "Grant Screen Recording")) {
                        _ = CGRequestScreenCaptureAccess()
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(GlassPillButtonStyle(compact: true))
                }
                Button(L10n.pick("刷新状态", "Refresh")) { viewModel.refreshLumaLinkStatus(refreshPermissions: true) }
                    .buttonStyle(GlassPillButtonStyle(compact: true))
            }
        }
        .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LiquidColors.pillSurface, in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous)
                .strokeBorder(!cfg.rdpEnabled ? Color.cyan.opacity(0.45) : LiquidColors.pillBorder, lineWidth: !cfg.rdpEnabled ? 1.1 : 0.8)
        }
    }

    private func setServices(listener: Bool, rdp: Bool) {
        if listener, let plugin = companionPlugin, !plugin.isEnabled {
            ctrl?.setEnabled(plugin, isEnabled: true, viewModel: viewModel)
        }
        var next = viewModel.lumaLinkConfig
        next.enabled = listener || rdp; next.rdpEnabled = rdp
        viewModel.applyLumaLinkConfig(next)
    }

    private func pickAndInstallRdpHelper() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.prompt = L10n.pick("导入 macos-rdp-daemon", "Import Helper")
        panel.message = L10n.pick("请选择 macos-rdp-daemon 可执行文件", "Select the macos-rdp-daemon binary")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            _ = try LumaLinkRdpSidecarService.shared.installHelperBinary(from: url)
            setServices(listener: true, rdp: true)
            viewModel.serviceMessage = "已导入 macos-rdp-daemon 并启动极速 RDP 服务"
        } catch {
            viewModel.serviceMessage = "导入失败：\(error.localizedDescription)"
        }
    }
}

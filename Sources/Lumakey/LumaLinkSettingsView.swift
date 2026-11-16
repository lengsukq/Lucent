import AppKit
import CoreImage.CIFilterBuiltins
import LumakeyCore
import SwiftUI

struct LumaLinkSettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionHeroHeader(
                    symbol: "ipad.and.iphone", topColor: .cyan, bottomColor: .blue,
                    title: "流光随行 · LumaLink 远控伴侣",
                    subtitle: "为手机端解锁真·分辨率切换、隐私黑屏防窥、中文直发、音量/媒体/防休眠与性能遥测；关闭即零后台驻留。"
                ) {
                    HStack(spacing: 10) {
                        Button(L10n.pick("所有插件", "All Plugins")) {
                            viewModel.activeSettingsSection = .plugins
                        }
                        .buttonStyle(GlassPillButtonStyle(compact: true))
                        Toggle("", isOn: configBinding(\.enabled))
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }
                statusRow
                if viewModel.lumaLinkConfig.enabled {
                    pairingCard
                    rdpEngineCard
                }
                behaviorCard
                if let companion = viewModel.plugins.first(where: { $0.id == LumaLinkServer.companionPluginID }) {
                    PluginCommandSettingsCard(plugin: companion, viewModel: viewModel)
                }
                pairedDevicesCard
            }
            .padding(.trailing, 4)
        }
        .onAppear {
            viewModel.refreshLumaLinkStatus()
        }
    }

    private var statusRow: some View {
        let snap = viewModel.lumaLinkStatus
        let dotColor: Color = if !viewModel.lumaLinkConfig.enabled {
            .secondary
        } else if snap.isListening {
            snap.connectedDeviceCount > 0 ? .green : .cyan
        } else {
            .orange
        }
        let ipText = LumaLinkServer.localIPv4Address() ?? "局域网"
        let summary: String = if !viewModel.lumaLinkConfig.enabled {
            "伴侣服务已关闭（零网络监听 · 零内存驻留）"
        } else if let err = snap.lastError, !err.isEmpty {
            "监听异常：\(err)"
        } else if snap.isListening {
            "正在广播 _lumakey-remote._tcp · \(ipText):\(snap.port) · 已连接 \(snap.connectedDeviceCount) 台手机"
        } else {
            "正在启动 Bonjour 监听…"
        }

        return HStack(spacing: 10) {
            Circle().fill(dotColor).frame(width: 9, height: 9)
            Text(summary).font(.caption.weight(.medium))
            Spacer()
            if !viewModel.mosAccessibilityTrusted {
                Button("授权辅助功能") {
                    viewModel.requestMosAccessibilityPermission()
                }
                .buttonStyle(GlassPillButtonStyle(prominent: true))
            }
            Button("刷新状态") {
                viewModel.refreshLumaLinkStatus()
            }
            .buttonStyle(GlassPillButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)
    }

    private var pairingCard: some View {
        let snap = viewModel.lumaLinkStatus
        let ip = LumaLinkServer.localIPv4Address() ?? "Mac"
        let qrPayload = "lumalink://pair?host=\(ip)&port=\(snap.port)&pin=\(snap.pairingPin)"

        return HStack(spacing: 16) {
            if let qrImage = Self.makeQRImage(from: qrPayload) {
                Image(nsImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .padding(6)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("6 位安全配对码").font(.callout.weight(.semibold))
                Text(snap.pairingPin.isEmpty ? "------" : snap.pairingPin)
                    .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.cyan)
                    .textSelection(.enabled)
                Text("在移动端远控客户端内点击「配对 LumaLink」并输入配对码或扫码；每次成功配对后自动轮换。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("刷新配对码") {
                        viewModel.regenerateLumaLinkPin()
                    }
                    .buttonStyle(GlassPillButtonStyle())
                    Button("复制地址") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("\(ip):\(snap.port) · PIN \(snap.pairingPin)", forType: .string)
                        viewModel.serviceMessage = "已复制 LumaLink 配对信息"
                    }
                    .buttonStyle(GlassPillButtonStyle())
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: LiquidRadii.bento, solidReadable: true)
    }

    private var rdpEngineCard: some View {
        let rdp = viewModel.lumaLinkRdpStatus
        let dotColor: Color = if !viewModel.lumaLinkConfig.rdpEnabled {
            .secondary
        } else if rdp.running {
            .green
        } else if rdp.lastError != nil || !rdp.binaryFound {
            .red
        } else {
            .orange
        }
        let stateText: String = if !viewModel.lumaLinkConfig.rdpEnabled {
            "未开启（关闭状态零进程、零端口占用）"
        } else if rdp.running {
            "VideoToolbox H.264 硬编码已就绪 · 端口 \(rdp.port) · 广播 _rdp._tcp"
        } else if !rdp.binaryFound {
            "未检测到 macos-rdp-daemon 助手程序"
        } else if let err = rdp.lastError, !err.isEmpty {
            "启动失败：\(err)"
        } else {
            "正在准备自签名证书与启动引擎…"
        }

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("极速 RDP 引擎（VideoToolbox H.264 硬编码）")
                        .font(.callout.weight(.semibold))
                    Text("相比标准 VNC 大幅降低 70%+ 流量占用与延迟，支持动态分辨率、双向剪贴板与系统音频透传。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: configBinding(\.rdpEnabled))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            HStack(spacing: 8) {
                Circle().fill(dotColor).frame(width: 8, height: 8)
                Text(stateText).font(.caption.weight(.medium))
                Spacer()
                Text("端口 \(viewModel.lumaLinkConfig.rdpPort)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if rdp.binaryFound && (!rdp.screenRecordingGranted || !rdp.accessibilityGranted) {
                HStack(spacing: 8) {
                    Text("权限检查：屏幕录制 \(rdp.screenRecordingGranted ? "✓" : "未授权") · 辅助功能 \(rdp.accessibilityGranted ? "✓" : "未授权")")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Spacer()
                    if !rdp.screenRecordingGranted {
                        Button("授权屏幕录制") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(GlassPillButtonStyle())
                    }
                    if !rdp.accessibilityGranted {
                        Button("授权辅助功能") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(GlassPillButtonStyle())
                    }
                }
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: LiquidRadii.bento, solidReadable: true)
    }

    private var behaviorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("安全与显示行为").font(.callout.weight(.semibold))
            Toggle("所有手机断开连接时自动还原 Mac 原始分辨率并关闭隐私幕布", isOn: configBinding(\.autoRestoreDisplayOnDisconnect))
            Toggle("开启隐私黑屏幕布时自动静音 Mac 扬声器", isOn: configBinding(\.muteMacWhenCurtainEnabled))
            Toggle("RDP 远控收听声音时 Mac 本地同步出声", isOn: configBinding(\.rdpLocalAudioEnabled))
            let audioSt = LumaLinkAudioBridgeService.shared.status(preferredName: viewModel.lumaLinkConfig.preferredVirtualMicName)
            HStack(spacing: 6) {
                Circle()
                    .fill(audioSt.virtualMicDeviceName != nil ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                if let dev = audioSt.virtualMicDeviceName {
                    Text("虚拟麦克风已就绪：\(dev)（手机麦克风将路由为此 Mac 输入设备）")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("未检测到虚拟声卡（建议 brew install blackhole-2ch 以接收手机麦克风）")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            if !viewModel.mosAccessibilityTrusted {
                Text("提示：中文直接上屏 (⌘V)、Spaces / 调度中心快捷键与远程锁屏需要授予 Lumakey「辅助功能」权限。")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: LiquidRadii.bento, solidReadable: true)
    }

    private var pairedDevicesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("已授权手机设备 (\(viewModel.lumaLinkConfig.pairedDevices.count))")
                .font(.callout.weight(.semibold))
            if viewModel.lumaLinkConfig.pairedDevices.isEmpty {
                Text("暂无已配对手机；首次输入 6 位配对码后将自动记住该设备。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.lumaLinkConfig.pairedDevices) { device in
                    HStack(spacing: 10) {
                        Image(systemName: "iphone")
                            .foregroundStyle(.cyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name).font(.callout.weight(.medium))
                            Text("配对时间：\(FastFormatters.formatModificationDate(Date(timeIntervalSince1970: device.pairedAt)))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("移除") {
                            viewModel.revokeLumaLinkDevice(id: device.id)
                        }
                        .buttonStyle(GlassPillButtonStyle())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(LiquidColors.pillSurface, in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
                }
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: LiquidRadii.bento, solidReadable: true)
    }

    private func configBinding<T>(_ keyPath: WritableKeyPath<LumaLinkConfig, T>) -> Binding<T> {
        Binding(
            get: { viewModel.lumaLinkConfig[keyPath: keyPath] },
            set: { newValue in
                var next = viewModel.lumaLinkConfig
                next[keyPath: keyPath] = newValue
                viewModel.applyLumaLinkConfig(next)
            }
        )
    }

    private static func makeQRImage(from text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 6, y: 6))
        let rep = NSCIImageRep(ciImage: scaled)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }
}

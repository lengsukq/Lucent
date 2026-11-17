import AppKit
import CoreImage.CIFilterBuiltins
import LumakeyCore
import SwiftUI

@MainActor
final class LumaLinkNetworkCardState: ObservableObject {
    @Published var candidates: [LumaLinkNetworkCandidate] = LumaLinkServer.availableNetworkCandidates()
    @Published var customHostDraft: String = ""
    @Published var portDraft: String = ""
    @Published var showCustomHostEditor: Bool = false

    func sync(from config: LumaLinkConfig) {
        candidates = LumaLinkServer.availableNetworkCandidates()
        customHostDraft = config.customConnectHost
        portDraft = String(config.preferredPort)
        if !config.customConnectHost.isEmpty || config.preferredPort != 59480 {
            showCustomHostEditor = true
        }
    }
}

struct LumaLinkNetworkAndPairingCard: View {
    @ObservedObject var viewModel: AppViewModel
    @StateObject private var cardState = LumaLinkNetworkCardState()

    private var endpoint: (host: String, port: UInt16, candidate: LumaLinkNetworkCandidate?, isCustomHost: Bool) {
        let resolved = LumaLinkNetworkResolver.resolveConnectHost(
            config: viewModel.lumaLinkConfig,
            candidates: cardState.candidates
        )
        let p = viewModel.lumaLinkStatus.port > 0 ? viewModel.lumaLinkStatus.port : viewModel.lumaLinkConfig.preferredPort
        return (resolved.host, p, resolved.activeCandidate, resolved.isCustomHost)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            pairingHeaderOrSection
            Divider().opacity(0.22)
            networkSwitcherSection
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: LiquidRadii.bento, solidReadable: true)
        .onAppear { cardState.sync(from: viewModel.lumaLinkConfig) }
        .onChange(of: viewModel.lumaLinkConfig) { _, next in cardState.sync(from: next) }
    }

    @ViewBuilder
    private var pairingHeaderOrSection: some View {
        let snap = viewModel.lumaLinkStatus
        let ep = endpoint
        let cfg = viewModel.lumaLinkConfig
        let pin = snap.pairingPin.isEmpty ? LumaLinkServer.shared.currentSnapshot().pairingPin : snap.pairingPin
        let qrPayload = "lumalink://pair?host=\(ep.host)&port=\(ep.port)&pin=\(pin)"

        if !cfg.enabled {
            HStack(spacing: 12) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 26))
                    .foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.pick("配对码与扫码直连（待启动）", "Pairing PIN & QR Connect (Idle)"))
                        .font(.callout.weight(.semibold))
                    Text(L10n.pick(
                        "点击右侧按钮可同时启动远控监听与极速 RDP 服务，并生成 \(ep.host):\(ep.port) 的 6 位配对码。",
                        "Start both Listener & Turbo RDP and generate your 6-digit PIN for \(ep.host):\(ep.port)."
                    ))
                    .font(.caption2)
                    .foregroundStyle(LiquidColors.textSecondary)
                }
                Spacer()
                Button(L10n.pick("开启远控 + 极速 RDP 并显示配对码", "Enable Remote + RDP & Show PIN")) {
                    var next = cfg
                    next.enabled = true
                    next.rdpEnabled = true
                    viewModel.applyLumaLinkConfig(next)
                }
                .buttonStyle(GlassPillButtonStyle(prominent: true))
            }
        } else {
            HStack(alignment: .center, spacing: 14) {
                if let qrImage = Self.makeQRImage(from: qrPayload) {
                    Image(nsImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 90, height: 90)
                        .padding(5)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(L10n.pick("6 位配对码", "6-Digit PIN"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(LiquidColors.textSecondary)
                        Text(snap.isListening ? L10n.pick("可连接", "Ready") : L10n.pick("启动中", "Starting"))
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundStyle(snap.isListening ? .mint : .orange)
                            .padding(.horizontal, 6).padding(.vertical, 1.5)
                            .background((snap.isListening ? Color.mint : Color.orange).opacity(0.14), in: Capsule())
                    }
                    Text(pin.isEmpty ? "------" : pin)
                        .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.cyan)
                        .textSelection(.enabled)
                    HStack(spacing: 6) {
                        Button(L10n.pick("复制配对码", "Copy PIN")) {
                            copyToPasteboard(pin, toast: "已复制 6 位配对码：\(pin)")
                        }
                        .buttonStyle(GlassPillButtonStyle(prominent: true, compact: true))
                        Button(L10n.pick("换一组", "Rotate")) {
                            viewModel.regenerateLumaLinkPin()
                        }
                        .buttonStyle(GlassPillButtonStyle(compact: true))
                    }
                }

                Divider().frame(height: 82).opacity(0.2)

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.pick("手机端手动连接参数（点击即复制）", "Manual Connect Fields (Click to Copy)"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(LiquidColors.textSecondary)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                        manualFieldChip(label: L10n.pick("主机 IP", "Host / IP"), value: ep.host)
                        manualFieldChip(label: L10n.pick("控制端口", "Port"), value: "\(ep.port)")
                        manualFieldChip(label: L10n.pick("配对码 PIN", "PIN"), value: pin)
                        manualFieldChip(label: "RDP 端口", value: "\(cfg.rdpPort)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var networkSwitcherSection: some View {
        let cfg = viewModel.lumaLinkConfig
        let ep = endpoint
        let autoSelected = cfg.preferredInterface.isEmpty && cfg.customConnectHost.isEmpty
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(L10n.pick("选择连接网卡 / IP", "Select Network Interface / IP"), systemImage: "network")
                    .font(.caption.weight(.semibold))
                Text("\(ep.host):\(ep.port)")
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(.cyan)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.cyan.opacity(0.14), in: Capsule())
                Spacer()
                Button(cardState.showCustomHostEditor ? L10n.pick("收起自定义地址", "Hide Custom") : L10n.pick("自定义域名/端口", "Custom Host/Port")) {
                    withAnimation(.easeInOut(duration: 0.15)) { cardState.showCustomHostEditor.toggle() }
                }
                .buttonStyle(GlassPillButtonStyle(compact: true))
                Button(L10n.pick("刷新网卡", "Refresh")) {
                    viewModel.refreshLumaLinkStatus(refreshPermissions: false)
                    cardState.sync(from: viewModel.lumaLinkConfig)
                }
                .buttonStyle(GlassPillButtonStyle(compact: true))
            }

            FlowWrapLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                interfacePill(
                    title: L10n.pick("自动优选局域网", "Auto (Prefer LAN)"),
                    symbol: "sparkles",
                    selected: autoSelected
                ) {
                    var next = cfg
                    next.preferredInterface = ""
                    next.customConnectHost = ""
                    cardState.customHostDraft = ""
                    viewModel.applyLumaLinkConfig(next)
                }

                ForEach(cardState.candidates) { cand in
                    let isSel = cfg.customConnectHost.isEmpty && (cfg.preferredInterface == cand.id || cfg.preferredInterface == cand.interfaceName)
                    let sym = cand.kind == .lan ? "wifi" : (cand.kind == .tunnel ? "point.3.connected.trianglepath.dotted" : "cable.connector")
                    interfacePill(title: cand.displayLabel, symbol: sym, selected: isSel) {
                        var next = cfg
                        next.preferredInterface = cand.id
                        next.customConnectHost = ""
                        cardState.customHostDraft = ""
                        viewModel.applyLumaLinkConfig(next)
                    }
                }
            }

            if cardState.showCustomHostEditor {
                HStack(spacing: 8) {
                    GlassInputField(
                        symbol: "globe",
                        placeholder: L10n.pick("自定义连接 IP 或 DDNS 域名（留空使用上方所选网卡）", "Custom IP or DDNS hostname"),
                        text: $cardState.customHostDraft
                    )
                    .onSubmit { applyHostAndPortDraft() }

                    GlassInputField(symbol: "number", placeholder: "59480", text: $cardState.portDraft)
                        .frame(width: 96)
                        .onSubmit { applyHostAndPortDraft() }

                    Button(L10n.pick("保存应用", "Apply")) { applyHostAndPortDraft() }
                        .buttonStyle(GlassPillButtonStyle(prominent: true, compact: true))
                }
            }
        }
    }

    private func interfacePill(title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10.5, weight: .semibold))
                Text(title).font(.caption2.weight(.semibold)).lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(selected ? Color.white : LiquidColors.textPrimary)
            .background(selected ? Color.accentColor : LiquidColors.pillSurface, in: Capsule())
            .overlay { Capsule().strokeBorder(LiquidColors.pillBorder, lineWidth: 0.75) }
        }
        .buttonStyle(.plain)
    }

    private func manualFieldChip(label: String, value: String) -> some View {
        Button {
            copyToPasteboard(value, toast: "已复制 \(label)：\(value)")
        } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(.system(size: 9.5)).foregroundStyle(LiquidColors.textSecondary).lineLimit(1)
                    Text(value).font(.caption.monospaced().weight(.bold)).foregroundStyle(LiquidColors.textPrimary).lineLimit(1)
                }
                Spacer(minLength: 2)
                Image(systemName: "doc.on.doc").font(.system(size: 9.5)).foregroundStyle(.cyan)
            }
            .padding(.horizontal, 9).padding(.vertical, 5.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LiquidColors.pillSurface, in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous).strokeBorder(LiquidColors.pillBorder, lineWidth: 0.7) }
        }
        .buttonStyle(.plain)
    }

    private func applyHostAndPortDraft() {
        var next = viewModel.lumaLinkConfig
        let cleanHost = LumaLinkNetworkResolver.sanitizeHostInput(cardState.customHostDraft)
        next.customConnectHost = cleanHost
        cardState.customHostDraft = cleanHost
        if let parsedPort = Int(cardState.portDraft.trimmingCharacters(in: .whitespacesAndNewlines)),
           (1024...65535).contains(parsedPort) {
            next.preferredPort = UInt16(parsedPort)
        } else {
            cardState.portDraft = String(next.preferredPort)
        }
        viewModel.applyLumaLinkConfig(next)
        viewModel.serviceMessage = "已更新流光随行连接地址与端口"
    }

    private func copyToPasteboard(_ text: String, toast: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        viewModel.serviceMessage = toast
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

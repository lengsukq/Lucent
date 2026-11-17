import LumakeyCore
import SwiftUI

struct SinglePluginConfirmSheet: View {
    let candidate: SinglePluginCandidate
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        let m = candidate.manifest
        let caps = m.declaredCapabilities
        let scopes = m.declaredResourceScopes

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                SquircleBadge(
                    symbol: m.icon ?? "puzzlepiece.extension.fill",
                    topColor: .cyan,
                    bottomColor: .indigo,
                    size: 42
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.pick("识别到单个外部插件", "Standalone Plugin Detected"))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.cyan)
                    Text("\(m.localizedName()) · v\(m.version)")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(LiquidColors.textPrimary)
                    Text("ID: \(m.id) · 来源: \(candidate.originDisplay)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(LiquidColors.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
            }

            Text(m.localizedDescription())
                .font(.caption)
                .foregroundStyle(LiquidColors.textPrimary)

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.pick("权限与外部资源声明核验", "Declared Permissions & Scopes"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(LiquidColors.textPrimary)

                if caps.isEmpty && scopes.isEmpty {
                    Label(
                        L10n.pick("纯沙盒插件 `[]`（不申请任何宿主桥接或网络/写盘权限）", "Pure sandbox plugin `[]` (no host bridge or external scopes)"),
                        systemImage: "checkmark.shield.fill"
                    )
                    .font(.caption2)
                    .foregroundStyle(.mint)
                } else {
                    if !caps.isEmpty {
                        Text(L10n.pick("宿主桥接能力（安装后默认关闭，需手动授权）：", "Host Bridge capabilities (OFF by default after install):"))
                            .font(.caption2)
                            .foregroundStyle(LiquidColors.textSecondary)
                        Text(caps.map { "\($0.title) (\($0.rawValue))" }.joined(separator: " · "))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                    if !scopes.isEmpty {
                        Text(L10n.pick("外部资源范围：", "External resource scopes:") + scopes.map(\.shortLabel).joined(separator: " · "))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.purple)
                    }
                }
                if let minVer = m.minAppVersion, !minVer.isEmpty {
                    Text(L10n.pick("要求宿主最低版本：Lumakey v\(minVer)", "Minimum Host Version: Lumakey v\(minVer)"))
                        .font(.caption2)
                        .foregroundStyle(LiquidColors.textSecondary)
                }
                Text("SHA-256: \(String(candidate.sha256.prefix(24)))…")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(LiquidColors.textSecondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LiquidColors.pillSurface, in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))

            HStack {
                Spacer()
                Button(L10n.pick("取消", "Cancel")) { onCancel() }
                    .buttonStyle(GlassPillButtonStyle())
                Button(L10n.pick("确认安装", "Install Plugin")) { onConfirm() }
                    .buttonStyle(GlassPillButtonStyle(prominent: true))
            }
        }
        .padding(18)
        .frame(width: 440)
        .background(LiquidColors.solidCardSurface)
    }
}

struct PluginUpdateEscalationSheet: View {
    let update: PluginStoreAvailableUpdate
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        let item = update.item
        let diff = update.permissionDiff

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                SquircleBadge(
                    symbol: "exclamationmark.shield.fill",
                    topColor: .orange,
                    bottomColor: .pink,
                    size: 42
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.pick("升级权限变更提醒", "Permission Change Notice"))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.orange)
                    Text("\(item.localizedName()) · v\(update.installedVersion) → v\(item.version)")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(LiquidColors.textPrimary)
                    Text(L10n.pick("来源商店：\(update.store.manifest.storeName)", "Store: \(update.store.manifest.storeName)"))
                        .font(.caption2)
                        .foregroundStyle(LiquidColors.textSecondary)
                }
                Spacer()
            }

            if let log = item.changelog?.trimmingCharacters(in: .whitespacesAndNewlines), !log.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.pick("更新说明", "What's New"))
                        .font(.caption.weight(.bold))
                    Text(log)
                        .font(.caption2)
                        .foregroundStyle(LiquidColors.textSecondary)
                }
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LiquidColors.pillSurface, in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.pick("新版本额外声明了以下权限或资源范围：", "This update declares new permissions or resource scopes:"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(LiquidColors.textPrimary)
                if !diff.addedCapabilities.isEmpty {
                    Text(L10n.pick("新增宿主能力（默认不自动开启）：", "Added Host Capabilities (OFF until granted): ") + diff.addedCapabilities.map(\.title).joined(separator: " · "))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                if !diff.addedResourceScopes.isEmpty {
                    Text(L10n.pick("新增 Seatbelt 资源域：", "Added Resource Scopes: ") + diff.addedResourceScopes.map(\.shortLabel).joined(separator: " · "))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.purple)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))

            HStack {
                Spacer()
                Button(L10n.pick("暂不更新", "Cancel")) { onCancel() }
                    .buttonStyle(GlassPillButtonStyle())
                Button(L10n.pick("知悉并更新", "Approve & Update")) { onConfirm() }
                    .buttonStyle(GlassPillButtonStyle(prominent: true))
            }
        }
        .padding(18)
        .frame(width: 450)
        .background(LiquidColors.solidCardSurface)
    }
}

struct PluginStoreSpecGuideSheet: View {
    let onCopyTemplate: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.pick("自定义插件商店与单插件入驻规范", "Custom Store & Plugin Distribution Spec"))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(LiquidColors.textPrimary)
                    Text(L10n.pick("同样已内置于 lumakey-mcp (`lumakey://specs/plugin-store-v1`)，可直接让 AI 助手代为打包生成。", "Also built into lumakey-mcp (`lumakey://specs/plugin-store-v1`) for AI-assisted packaging."))
                        .font(.caption2)
                        .foregroundStyle(LiquidColors.textSecondary)
                }
                Spacer()
                Button(L10n.pick("复制商店 JSON 模板", "Copy JSON Template")) { onCopyTemplate() }
                    .buttonStyle(GlassPillButtonStyle(prominent: true, compact: true))
                Button(L10n.pick("关闭", "Close")) { onClose() }
                    .buttonStyle(GlassPillButtonStyle(compact: true))
            }

            ScrollView {
                MarkdownBlocksStackView(
                    blocks: MarkdownDocumentParser.parse(PluginSystem.specStoreV1Markdown),
                    baseFontSize: 12
                )
                .padding(12)
            }
            .background(LiquidColors.pillSurface, in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
        }
        .padding(18)
        .frame(width: 620, height: 480)
        .background(LiquidColors.solidCardSurface)
    }
}

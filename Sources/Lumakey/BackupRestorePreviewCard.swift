import LumakeyCore
import SwiftUI

struct BackupRestorePreviewCard: View {
    @ObservedObject var state: BackupSettingsViewState
    @ObservedObject var viewModel: AppViewModel
    let pending: PendingBackupRestore

    var body: some View {
        let s = pending.summary
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill").foregroundStyle(.mint)
                Text("恢复前快照核验：\(pending.sourceLabel)").font(.callout.weight(.bold))
                Spacer()
                if s.isCompressed {
                    Text("LZFSE v\(s.schemaVersion)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.cyan)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.cyan.opacity(0.14), in: Capsule())
                }
                Text("SHA-256 \(s.payloadSHA256.prefix(12))")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.mint)
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.mint.opacity(0.14), in: Capsule())
            }
            Text("创建于 \(s.createdAtISO8601) · 来源主机 \(s.hostName) (v\(s.appVersion)) · 大小 \(FastFormatters.formatFileBytes(Int64(s.archiveByteCount)))")
                .font(.caption2).foregroundStyle(LiquidColors.textSecondary)

            FlowWrapLayout(horizontalSpacing: 14, verticalSpacing: 6) {
                Label("\(s.configCount) 项配置文件", systemImage: "slider.horizontal.3")
                Label("\(s.pinnedClipboardCount) 条收藏剪贴板", systemImage: "pin.fill")
                Label("\(s.pluginCount) 个外部插件", systemImage: "puzzlepiece.extension.fill")
                Label("\(s.pluginDataFileCount + s.externalFileCount) 份插件数据与索引", systemImage: "externaldrive.badge.checkmark")
                if s.hasEncryptedSecrets {
                    Label("含口令加密密钥", systemImage: "lock.shield.fill").foregroundStyle(.mint)
                }
            }
            .font(.caption.weight(.semibold)).foregroundStyle(LiquidColors.textPrimary)

            FlowWrapLayout(horizontalSpacing: 16, verticalSpacing: 8) {
                Toggle("恢复配置", isOn: optionBinding(\.restoreConfigs)).fixedSize()
                Toggle("恢复收藏剪贴板", isOn: optionBinding(\.restoreClipboard)).fixedSize()
                Toggle("恢复外部插件包", isOn: optionBinding(\.restorePlugins)).fixedSize()
                Toggle("恢复插件数据与索引", isOn: optionBinding(\.restorePluginData)).fixedSize()
                Toggle("恢复前留存本地回滚快照", isOn: optionBinding(\.createSafetySnapshotBeforeRestore)).fixedSize()
                if s.hasEncryptedSecrets {
                    Toggle("恢复加密插件密钥", isOn: optionBinding(\.restoreEncryptedSecrets)).fixedSize()
                }
            }
            .font(.caption)

            if s.hasEncryptedSecrets && (state.pendingRestore?.options.restoreEncryptedSecrets ?? true) {
                HStack(spacing: 8) {
                    Image(systemName: "key.horizontal.fill").font(.caption).foregroundStyle(.mint)
                    SecureField("输入导出此备份时设置的加密口令", text: passphraseBinding)
                        .textFieldStyle(.plain).font(.caption).foregroundStyle(LiquidColors.textPrimary)
                }
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(LiquidColors.inputFieldSurface, in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous)
                        .strokeBorder(LiquidColors.inputFieldBorder, lineWidth: 0.9)
                }
            }

            HStack(spacing: 8) {
                Spacer()
                Button("取消") { state.pendingRestore = nil }.buttonStyle(GlassPillButtonStyle())
                Button("确认恢复此快照") { state.confirmPendingRestore(viewModel: viewModel) }
                    .buttonStyle(GlassPillButtonStyle(prominent: true))
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: LiquidRadii.bento, solidReadable: true)
    }

    private var passphraseBinding: Binding<String> {
        Binding(
            get: { state.pendingRestore?.passphraseInput ?? "" },
            set: { state.pendingRestore?.passphraseInput = $0 }
        )
    }

    private func optionBinding(_ kp: WritableKeyPath<BackupRestoreOptions, Bool>) -> Binding<Bool> {
        Binding(
            get: { state.pendingRestore?.options[keyPath: kp] ?? true },
            set: { val in state.pendingRestore?.options[keyPath: kp] = val }
        )
    }
}

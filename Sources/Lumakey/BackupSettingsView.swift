import AppKit
import LumakeyCore
import SwiftUI

struct BackupSettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @StateObject private var state = BackupSettingsViewState()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionHeroHeader(
                    symbol: "externaldrive.fill.badge.icloud", topColor: .cyan, bottomColor: .indigo,
                    title: "数据导出、本地备份与 WebDAV 云同步",
                    subtitle: "一键 LZFSE 压缩归档配置、收藏剪贴板、外部插件包及插件数据索引（SHA-256 防篡改），支持可选口令端到端加密迁移插件密钥。"
                ) {
                    Button { state.exportLocalBackupInteractive(viewModel: viewModel) } label: {
                        Label("导出备份包", systemImage: "square.and.arrow.up.fill")
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: true)).disabled(state.isBusy)
                }
                statusBannerSection
                if let pending = state.pendingRestore {
                    BackupRestorePreviewCard(state: state, viewModel: viewModel, pending: pending)
                }
                localArchiveCard
                webdavConfigCard
                remoteHistoryCard
            }
        }
        .onAppear { state.onAppearLoad() }
    }

    @ViewBuilder
    private var statusBannerSection: some View {
        if state.isBusy {
            HStack(spacing: 9) {
                ProgressView().controlSize(.small)
                Text(state.busyLabel).font(.caption.weight(.medium)).foregroundStyle(LiquidColors.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .liquidGlassCard(cornerRadius: LiquidRadii.row, solidReadable: true)
        } else if let banner = state.banner {
            let icon = banner.tone == .success ? "checkmark.seal.fill" : (banner.tone == .error ? "exclamationmark.triangle.fill" : "info.circle.fill")
            let tint: Color = banner.tone == .success ? .mint : (banner.tone == .error ? .orange : .cyan)
            HStack(spacing: 9) {
                Image(systemName: icon).foregroundStyle(tint)
                Text(banner.message).font(.caption).foregroundStyle(LiquidColors.textPrimary)
                Spacer()
                Button { state.banner = nil } label: {
                    Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(LiquidColors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .liquidGlassCard(cornerRadius: LiquidRadii.row, solidReadable: true)
        }
    }

    private var localArchiveCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                SquircleBadge(symbol: "archivebox.fill", topColor: .teal, bottomColor: .blue, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text("本地 .lumakeybackup 快照归档 (v2 压缩)").font(.callout.weight(.semibold)).lineLimit(1)
                    Text("包含宿主配置、短语与使用统计、收藏剪贴板、插件代码包、PluginData 索引数据及声明备份的收件箱文件。")
                        .font(.caption2).foregroundStyle(LiquidColors.textSecondary).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(-1)

                HStack(spacing: 8) {
                    Button("打开配置目录") {
                        let dir = BackupArchiveService.defaultAppSupportDirectory()
                        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(dir)
                    }
                    .buttonStyle(GlassPillButtonStyle())

                    Button("从本地恢复…") { state.chooseLocalBackupForRestore() }
                        .buttonStyle(GlassPillButtonStyle()).disabled(state.isBusy)
                    Button("导出本地备份包") { state.exportLocalBackupInteractive(viewModel: viewModel) }
                        .buttonStyle(GlassPillButtonStyle(prominent: true)).disabled(state.isBusy)
                }
            }

            HStack(spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "lock.shield.fill").font(.caption).foregroundStyle(.cyan)
                    SecureField("可选：设置备份加密口令以端到端加密随包迁移插件 API 密钥（留空则不导出密钥）", text: $state.archivePassphraseInput)
                        .textFieldStyle(.plain).font(.caption).foregroundStyle(LiquidColors.textPrimary)
                    Text("AES-GCM").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.cyan)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.cyan.opacity(0.14), in: Capsule())
                }
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(LiquidColors.inputFieldSurface, in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous).strokeBorder(LiquidColors.inputFieldBorder, lineWidth: 0.9) }

                Button("保存口令") { _ = state.saveArchivePassphrase() }
                    .buttonStyle(GlassPillButtonStyle())
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: LiquidRadii.bento, solidReadable: true)
    }

    private var webdavConfigCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Label("WebDAV 云端自动轮转同步", systemImage: "icloud.and.arrow.up.fill")
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 6)
                FlowWrapLayout(horizontalSpacing: 5, verticalSpacing: 5) {
                    ForEach(WebDAVProviderPreset.allPresets) { preset in
                        let selected = state.selectedPresetID == preset.id
                        Button { state.selectPreset(preset) } label: {
                            HStack(spacing: 4) {
                                Image(systemName: preset.symbol).font(.system(size: 10))
                                Text(preset.name).font(.caption2.weight(.semibold)).lineLimit(1)
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .foregroundStyle(selected ? Color.white : LiquidColors.textPrimary)
                            .background(selected ? Color.accentColor : LiquidColors.pillSurface, in: Capsule())
                            .overlay { Capsule().strokeBorder(LiquidColors.pillBorder, lineWidth: 0.7) }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text(state.activePreset.setupHint)
                .font(.caption2).foregroundStyle(.cyan)

            GlassInputField(symbol: "link", placeholder: "WebDAV 地址，如 https://dav.jianguoyun.com/dav/", text: $state.webdavConfig.serverURL)

            HStack(spacing: 10) {
                GlassInputField(symbol: "person.fill", placeholder: "WebDAV 账号 / 邮箱", text: $state.webdavConfig.username)
                secureKeychainField
            }

            HStack(spacing: 12) {
                GlassInputField(symbol: "folder.fill", placeholder: "远端备份目录（默认 LumakeyBackups）", text: $state.webdavConfig.remoteDirectory)
                    .frame(maxWidth: 280)
                Stepper("保留最近 \(state.webdavConfig.keepLatestCount) 份", value: $state.webdavConfig.keepLatestCount, in: 1...50)
                    .font(.caption.monospacedDigit())
                Spacer()
                Toggle("启动时自动云备份", isOn: $state.webdavConfig.autoBackupOnLaunch)
                    .font(.caption)
            }

            HStack(spacing: 8) {
                Button("保存配置") {
                    if state.persistSettings() {
                        state.banner = BackupStatusBanner(tone: .success, message: "WebDAV 配置与备份加密口令已安全保存")
                    }
                }
                .buttonStyle(GlassPillButtonStyle())
                Button("测试连接") { state.runWebDAVTest() }
                    .buttonStyle(GlassPillButtonStyle())
                    .disabled(state.isBusy || !state.webdavConfig.isConfigured)
                Button("刷新云端列表") { state.refreshRemoteList() }
                    .buttonStyle(GlassPillButtonStyle())
                    .disabled(state.isBusy || !state.webdavConfig.isConfigured)
                Spacer()
                Button { state.uploadBackupToWebDAV(viewModel: viewModel) } label: {
                    Label("立即备份至 WebDAV", systemImage: "icloud.and.arrow.up")
                }
                .buttonStyle(GlassPillButtonStyle(prominent: true))
                .disabled(state.isBusy || !state.webdavConfig.isConfigured)
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: LiquidRadii.bento, solidReadable: true)
    }

    private var secureKeychainField: some View {
        HStack(spacing: 7) {
            Image(systemName: "key.fill").font(.caption).foregroundStyle(.mint)
            SecureField("应用专用密码（加密存本机密钥库）", text: $state.passwordInput)
                .textFieldStyle(.plain).font(.caption).foregroundStyle(LiquidColors.textPrimary)
            Text("Vault").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.mint)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.mint.opacity(0.14), in: Capsule())
        }
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(LiquidColors.inputFieldSurface, in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous).strokeBorder(LiquidColors.inputFieldBorder, lineWidth: 0.9) }
    }

    private var remoteHistoryCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("云端历史快照（\(state.remoteItems.count)）").font(.callout.weight(.semibold))
                Spacer()
                Text("自动轮转保留最新 \(state.webdavConfig.keepLatestCount) 份 .lumakeybackup")
                    .font(.caption2).foregroundStyle(LiquidColors.textSecondary)
            }
            if state.remoteItems.isEmpty {
                Text("暂无已加载的云端备份记录 · 配置 WebDAV 后点击「刷新云端列表」或「立即备份至 WebDAV」。")
                    .font(.caption2).foregroundStyle(LiquidColors.textSecondary).padding(.vertical, 6)
            } else {
                ForEach(state.remoteItems) { item in
                    HStack(spacing: 10) {
                        Image(systemName: "doc.zipper").foregroundStyle(.cyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.fileName).font(.caption.monospaced().weight(.semibold)).lineLimit(1)
                            Text("\(FastFormatters.formatModificationDate(item.sortDate)) · \(FastFormatters.formatFileBytes(item.sizeBytes))")
                                .font(.caption2).foregroundStyle(LiquidColors.textSecondary)
                        }
                        Spacer()
                        Button("从云端下载并恢复") { state.downloadAndStageRemoteRestore(item) }
                            .buttonStyle(GlassPillButtonStyle(prominent: true)).disabled(state.isBusy)
                        Button("删除") { state.deleteRemoteItem(item) }
                            .buttonStyle(GlassPillButtonStyle()).disabled(state.isBusy)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(LiquidColors.pillSurface, in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
                }
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: LiquidRadii.bento, solidReadable: true)
    }
}

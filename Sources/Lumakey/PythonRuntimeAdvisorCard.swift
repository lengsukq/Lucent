import AppKit
import LumakeyCore
import SwiftUI

@MainActor
private final class PythonAdvisorUIState: ObservableObject {
    @Published var feedbackMessage: String? = nil
}

struct PythonRuntimeAdvisorCard: View {
    @ObservedObject var viewModel: AppViewModel
    var targetPlugin: PluginDescriptor? = nil
    @StateObject private var ui = PythonAdvisorUIState()

    static func pluginRequiresPython(_ plugin: PluginDescriptor) -> Bool {
        guard !plugin.isBuiltin else { return false }
        let entryLower = plugin.manifest.entry.lowercased()
        if entryLower.hasSuffix(".py") { return true }
        let entryURL = plugin.directoryURL.appendingPathComponent(plugin.manifest.entry)
        guard let handle = try? FileHandle(forReadingFrom: entryURL),
              let head = try? handle.read(upToCount: 4096) else { return false }
        try? handle.close()
        if head.count >= 4 {
            let magic = [head[0], head[1], head[2], head[3]]
            if magic == [0xCF, 0xFA, 0xED, 0xFE] || magic == [0xCA, 0xFE, 0xBA, 0xBE] {
                return false
            }
        }
        guard let text = String(data: head, encoding: .utf8)?.lowercased() else { return false }
        return text.contains("python3") || text.contains("env python")
    }

    private var shouldShowCard: Bool {
        guard !viewModel.toolingStatus.hasPython3 else { return false }
        if let targetPlugin {
            return Self.pluginRequiresPython(targetPlugin)
        }
        return viewModel.plugins.contains(where: Self.pluginRequiresPython)
    }

    var body: some View {
        if shouldShowCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "terminal.fill")
                        .foregroundStyle(.orange)
                    Text(L10n.pick("检测到 Python 脚本插件缺少运行环境", "Python 3 Runtime Needed for Script Plugin"))
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Button(L10n.pick("重新检测", "Re-check")) {
                        viewModel.refreshToolingStatus()
                        ui.feedbackMessage = viewModel.toolingStatus.hasPython3
                            ? L10n.pick("✓ 已检测到 Python 3 环境", "✓ Python 3 runtime detected")
                            : L10n.pick("仍未检测到可用 Python 3，请先完成安装。", "Python 3 still not found.")
                    }
                    .buttonStyle(GlassPillButtonStyle(compact: true))
                }

                Text(L10n.pick(
                    "官方精选与示例插件均为原生 Swift 可执行程序，无需 Python；当前已安装的自定义脚本插件依赖 Python 3，点击下方即可一键安装。",
                    "Official plugins are native Swift binaries and need no Python. A custom Python script plugin is installed—install Command Line Tools or Python 3 below."
                ))
                .font(.caption2)
                .foregroundStyle(LiquidColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button {
                        installXcodeCommandLineTools()
                    } label: {
                        Label(L10n.pick("一键安装命令行工具 (含 Python 3)", "Install Command Line Tools"), systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: true, compact: true))

                    Button {
                        openHomebrewPythonInstallInTerminal()
                    } label: {
                        Label(L10n.pick("终端用 Homebrew 安装", "Install via Homebrew"), systemImage: "terminal")
                    }
                    .buttonStyle(GlassPillButtonStyle(compact: true))

                    Spacer()
                }

                if let feedbackMessage = ui.feedbackMessage {
                    Text(feedbackMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: LiquidRadii.bento, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LiquidRadii.bento, style: .continuous)
                    .strokeBorder(Color.orange.opacity(0.32), lineWidth: 0.8)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                viewModel.refreshToolingStatus()
            }
        }
    }

    private func installXcodeCommandLineTools() {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        proc.arguments = ["--install"]
        do {
            try proc.run()
            ui.feedbackMessage = L10n.pick(
                "已弹出系统「安装命令行开发者工具」向导，按提示点击安装完成后点「重新检测」即可。",
                "Triggered Apple's Command Line Tools installer dialog. Click Re-check once finished."
            )
        } catch {
            ui.feedbackMessage = L10n.pick(
                "无法自动拉起向导（\(error.localizedDescription)），请尝试右侧「终端用 Homebrew 安装」。",
                "Could not launch xcode-select (\(error.localizedDescription)). Try Terminal install."
            )
        }
    }

    private func openHomebrewPythonInstallInTerminal() {
        let script = """
        #!/usr/bin/env bash
        clear
        echo "=== Lumakey Python 3 环境安装 ==="
        if command -v brew >/dev/null 2>&1; then
          brew install python
        else
          echo "未检测到 Homebrew，改为启动 Apple 官方命令行工具安装向导..."
          xcode-select --install || true
        fi
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lumakey-install-python3.command")
        do {
            try Data(script.utf8).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            let termURL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
            if FileManager.default.fileExists(atPath: termURL.path) {
                NSWorkspace.shared.open([url], withApplicationAt: termURL, configuration: NSWorkspace.OpenConfiguration())
            } else {
                NSWorkspace.shared.open(url)
            }
            ui.feedbackMessage = L10n.pick("已在终端打开安装脚本，完成后点击「重新检测」。", "Opened installer script in Terminal.")
        } catch {
            ui.feedbackMessage = error.localizedDescription
        }
    }
}

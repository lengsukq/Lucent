import LucentFoundation
import Foundation

public enum PluginResourceScope: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case network
    case filesystem
    case subprocess

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .network: L10n.pick("允许访问网络", "Network Access")
        case .filesystem: L10n.pick("允许读写外部文件", "External File Access")
        case .subprocess: L10n.pick("允许调用本机命令行工具", "Run Local CLI Tools")
        }
    }

    public var shortLabel: String {
        switch self {
        case .network: L10n.pick("联网", "Network")
        case .filesystem: L10n.pick("读写文件", "Files")
        case .subprocess: L10n.pick("命令行", "CLI")
        }
    }

    public var summary: String {
        switch self {
        case .network: L10n.pick("用于请求在线翻译、查询 API 余额或同步书签；关闭后将完全断网", "Used for online translation, balance checks, or bookmark sync; turn off to block all network calls")
        case .filesystem: L10n.pick("用于导出表格、读取浏览器书签或扫描本地会话日志；关闭后仅能读写插件自身目录", "Used to export files, read browser bookmarks, or scan local session logs")
        case .subprocess: L10n.pick("用于调用本机已安装的命令行（如 codex、agy、ollama）；关闭后禁止启动外部程序", "Used to invoke local CLI tools (e.g. codex, agy, ollama)")
        }
    }

    public var symbolName: String {
        switch self {
        case .network: "network"
        case .filesystem: "externaldrive.fill"
        case .subprocess: "terminal.fill"
        }
    }
}

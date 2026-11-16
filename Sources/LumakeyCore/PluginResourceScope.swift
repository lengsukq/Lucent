import Foundation

public enum PluginResourceScope: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case network
    case filesystem
    case subprocess

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .network: L10n.pick("网络访问 (Network)", "Network Access")
        case .filesystem: L10n.pick("外部文件读写 (Filesystem)", "Filesystem Read/Write")
        case .subprocess: L10n.pick("外部子进程 (Subprocess)", "External Subprocess")
        }
    }

    public var shortLabel: String {
        switch self {
        case .network: L10n.pick("网络", "Network")
        case .filesystem: L10n.pick("读写盘", "Disk I/O")
        case .subprocess: L10n.pick("子进程", "Subprocess")
        }
    }

    public var summary: String {
        switch self {
        case .network: L10n.pick("插件脚本可能主动发起 HTTP/HTTPS 或网络请求（如查询在线 API）", "Plugin script may perform outbound HTTP/HTTPS or socket requests")
        case .filesystem: L10n.pick("插件脚本可能读写插件数据目录之外的本机用户文件（如笔记或本地缓存）", "Plugin script may read or write user files outside its PluginData sandbox")
        case .subprocess: L10n.pick("插件脚本会调用本机外部命令行工具（如 curl、lsof、python3）", "Plugin script invokes local CLI utilities (e.g. curl, lsof, python3)")
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

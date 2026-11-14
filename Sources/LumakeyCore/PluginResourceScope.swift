import Foundation

public enum PluginResourceScope: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case network
    case filesystem
    case subprocess

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .network: "网络访问 (Network)"
        case .filesystem: "外部文件读写 (Filesystem)"
        case .subprocess: "外部子进程 (Subprocess)"
        }
    }

    public var shortLabel: String {
        switch self {
        case .network: "网络"
        case .filesystem: "读写盘"
        case .subprocess: "子进程"
        }
    }

    public var summary: String {
        switch self {
        case .network: "插件脚本可能主动发起 HTTP/HTTPS 或网络请求（如查询在线 API）"
        case .filesystem: "插件脚本可能读写插件数据目录之外的本机用户文件（如笔记或本地缓存）"
        case .subprocess: "插件脚本会调用本机外部命令行工具（如 curl、lsof、python3）"
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

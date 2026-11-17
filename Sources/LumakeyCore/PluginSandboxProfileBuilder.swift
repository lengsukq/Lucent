import LumakeyFoundation; import LumakeySearch; import LumakeyMedia; import LumakeySystem
import Foundation

/// 外部插件系统级沙箱（macOS Seatbelt `sandbox-exec`）与纯净环境变量构造器。
/// 将 `plugin.json` 的 `resourceScopes` 从静态审计标签升级为内核强制访问控制，并无条件封锁宿主 `.vault` 与钥匙串目录。
public enum PluginSandboxProfileBuilder {
    private static let safeInheritedEnvKeys: Set<String> = [
        "LANG", "LC_ALL", "LC_CTYPE", "USER", "LOGNAME", "__CF_USER_TEXT_ENCODING"
    ]

    /// 检测当前宿主进程是否允许执行 `sandbox-exec`（当宿主自身已处于外层测试/Agent Seatbelt 沙箱中时，XNU 禁止嵌套 `sandbox_apply`）。
    public static let isSeatbeltAvailable: Bool = probeSeatbeltAvailability()

    public static func sanitizedEnvironment(
        pluginVariables: [String: String],
        isolatedTmpDirectory: URL,
        hostEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var env: [String: String] = [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "SHELL": "/bin/zsh",
            "LANG": "en_US.UTF-8",
            "TMPDIR": isolatedTmpDirectory.path
        ]
        for key in safeInheritedEnvKeys {
            if let val = hostEnvironment[key], !val.isEmpty {
                env[key] = val
            }
        }
        for (k, v) in pluginVariables {
            env[k] = v
        }
        return env
    }

    public static func buildProfile(
        pluginDirectory: URL,
        dataDirectory: URL?,
        isolatedTmpDirectory: URL,
        vaultDirectories: [URL],
        bridgeSocketPath: String?,
        allowedScopes: Set<PluginResourceScope>,
        userHomeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String {
        let home = canonicalPath(userHomeDirectory)
        let plugPath = canonicalPath(pluginDirectory)
        let tmpPath = canonicalPath(isolatedTmpDirectory)
        let dataPath = dataDirectory.map(canonicalPath)

        var lines: [String] = [
            "(version 1)",
            "(allow default)"
        ]

        // 1. 网络作用域控制：未授权 .network 时禁止一切 IP 出入站连接，仅放行本次执行的临时 Host Bridge UDS
        if !allowedScopes.contains(.network) {
            lines.append("(deny network-inbound)")
            lines.append("(deny network-outbound (remote ip))")
            if let sock = bridgeSocketPath, !sock.isEmpty {
                let canonicalSock = canonicalPath(URL(fileURLWithPath: sock))
                lines.append("(allow network-outbound (remote unix-socket (path-literal \"\(escapeSBPL(sock))\")))")
                if canonicalSock != sock {
                    lines.append("(allow network-outbound (remote unix-socket (path-literal \"\(escapeSBPL(canonicalSock))\")))")
                }
            }
        }

        // 2. 文件写作用域控制：未授权 .filesystem 时禁止修改用户主目录与外置卷，仅允许写插件专属 PluginData 与隔离临时目录
        if !allowedScopes.contains(.filesystem) {
            lines.append("(deny file-write* (subpath \"\(escapeSBPL(home))\") (subpath \"/Volumes\"))")
            lines.append("(allow file-write* (subpath \"\(escapeSBPL(tmpPath))\"))")
            if let dataPath {
                lines.append("(allow file-write* (subpath \"\(escapeSBPL(dataPath))\"))")
            }
            lines.append("(deny file-read* (subpath \"\(escapeSBPL(home))/.ssh\") (subpath \"\(escapeSBPL(home))/.gnupg\") (subpath \"\(escapeSBPL(home))/.aws\"))")
        }

        // 3. 外部子进程作用域控制：未授权 .subprocess 时拦截包管理器/第三方命令与高敏系统探测工具，仅保留插件自身、基础 Shell/JSON 工具与 Xcode 系统 Python3 运行时
        if !allowedScopes.contains(.subprocess) {
            lines.append("(deny process-exec* (subpath \"/opt/homebrew\") (subpath \"/usr/local\") (subpath \"/Applications\") (subpath \"/usr/sbin\"))")
            lines.append("(deny process-exec* (literal \"/usr/bin/curl\") (literal \"/usr/bin/ssh\") (literal \"/usr/bin/scp\") (literal \"/usr/bin/git\") (literal \"/usr/bin/sftp\"))")
            for devDir in discoverXcodeDeveloperDirectories() {
                let pyBin = "\(devDir)/usr/bin/python3"
                let pyFw = "\(devDir)/Library/Frameworks/Python3.framework"
                lines.append("(allow process-exec* (literal \"\(escapeSBPL(pyBin))\") (subpath \"\(escapeSBPL(pyFw))\"))")
            }
            lines.append("(allow process-exec* (subpath \"\(escapeSBPL(plugPath))\"))")
        }

        // 4. 不可覆盖底线（置于末尾，在 SBPL 后规则优先语义下拥有最高优先级）：严禁任何外部插件读取宿主密钥库或系统钥匙串
        let keychainsPath = "\(home)/Library/Keychains"
        lines.append("(deny file-read* file-write* (subpath \"\(escapeSBPL(keychainsPath))\"))")
        var seenVaults = Set<String>()
        for vaultURL in vaultDirectories {
            for candidate in [vaultURL.standardizedFileURL.path, canonicalPath(vaultURL)] where !candidate.isEmpty {
                if seenVaults.insert(candidate).inserted {
                    lines.append("(deny file-read* file-write* (subpath \"\(escapeSBPL(candidate))\"))")
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    public static func prepareExecutionCommand(
        entryURL: URL,
        arguments: [String],
        descriptor: PluginDescriptor,
        grantedScopes: Set<PluginResourceScope>,
        dataDirectory: URL?,
        isolatedTmpDirectory: URL,
        stateRoot: URL,
        bridgeSocketPath: String?,
        forceSeatbelt: Bool = false
    ) -> (executableURL: URL, arguments: [String], profile: String) {
        var protectedVaults: [URL] = [
            LocalSecretVault.defaultVaultFileURL().deletingLastPathComponent()
        ]
        if let scopedVault = PluginDataPaths.scopedVaultFileURL(forPluginsRoot: stateRoot)?.deletingLastPathComponent() {
            protectedVaults.append(scopedVault)
        }
        let profile = buildProfile(
            pluginDirectory: descriptor.directoryURL,
            dataDirectory: dataDirectory,
            isolatedTmpDirectory: isolatedTmpDirectory,
            vaultDirectories: protectedVaults,
            bridgeSocketPath: bridgeSocketPath,
            allowedScopes: grantedScopes
        )
        if forceSeatbelt || isSeatbeltAvailable {
            return (
                URL(fileURLWithPath: "/usr/bin/sandbox-exec"),
                ["-p", profile, entryURL.path] + arguments,
                profile
            )
        }
        return (entryURL, arguments, profile)
    }

    private static func discoverXcodeDeveloperDirectories() -> [String] {
        var dirs: [String] = ["/Applications/Xcode.app/Contents/Developer"]
        var seen: Set<String> = ["/Applications/Xcode.app/Contents/Developer"]
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: "/Applications")) ?? []
        for name in entries.sorted() where name.hasPrefix("Xcode") && name.hasSuffix(".app") {
            let candidate = "/Applications/\(name)/Contents/Developer"
            if seen.insert(candidate).inserted {
                dirs.append(candidate)
            }
        }
        return dirs
    }

    private static func canonicalPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static func escapeSBPL(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func probeSeatbeltAvailability() -> Bool {
        let sandboxExec = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        guard FileManager.default.isExecutableFile(atPath: sandboxExec.path) else { return false }
        let proc = Process()
        proc.executableURL = sandboxExec
        proc.arguments = ["-p", "(version 1)\n(allow default)", "/usr/bin/true"]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }
}

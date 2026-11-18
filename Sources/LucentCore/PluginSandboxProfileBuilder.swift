import LucentFoundation
import LucentSearch
import Foundation

/// 外部插件与快捷脚本系统级沙箱（macOS Seatbelt `sandbox-exec`）与纯净环境变量构造器。
/// 将 `resourceScopes` 从静态审计标签升级为内核强制访问控制，并无条件封锁宿主 `.vault` 与钥匙串目录。
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
        if let py3 = HostToolingStatus.detectPython3Path() {
            env["LUCENT_PYTHON3"] = py3
        }
        for (k, v) in pluginVariables {
            env[k] = v
        }
        return env
    }

    public static func protectedVaultDirectories(forStateRoot stateRoot: URL) -> [URL] {
        var vaults: [URL] = [LocalSecretVault.defaultVaultFileURL().deletingLastPathComponent()]
        if let scoped = PluginDataPaths.scopedVaultFileURL(forPluginsRoot: stateRoot)?.deletingLastPathComponent() {
            vaults.append(scoped)
        }
        let siblingVault = stateRoot.deletingLastPathComponent()
            .appendingPathComponent(LocalSecretVault.vaultDirectoryName, isDirectory: true)
        vaults.append(siblingVault)
        return vaults
    }

    public static func buildProfile(
        pluginDirectory: URL,
        dataDirectory: URL?,
        isolatedTmpDirectory: URL,
        vaultDirectories: [URL],
        bridgeSocketPath: String?,
        allowedScopes: Set<PluginResourceScope>,
        allowSwiftToolchain: Bool = false,
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

        if !allowedScopes.contains(.filesystem) {
            lines.append("(deny file-write* (subpath \"\(escapeSBPL(home))\") (subpath \"/Volumes\"))")
            lines.append("(allow file-write* (subpath \"\(escapeSBPL(tmpPath))\"))")
            if let dataPath {
                lines.append("(allow file-write* (subpath \"\(escapeSBPL(dataPath))\"))")
            }
            lines.append("(deny file-read* (subpath \"\(escapeSBPL(home))/.ssh\") (subpath \"\(escapeSBPL(home))/.gnupg\") (subpath \"\(escapeSBPL(home))/.aws\"))")
        }

        if !allowedScopes.contains(.subprocess) {
            lines.append("(deny process-exec* (subpath \"/opt/homebrew\") (subpath \"/usr/local\") (subpath \"/Applications\") (subpath \"/usr/sbin\"))")
            lines.append("(deny process-exec* (literal \"/usr/bin/curl\") (literal \"/usr/bin/ssh\") (literal \"/usr/bin/scp\") (literal \"/usr/bin/git\") (literal \"/usr/bin/sftp\"))")
            for devDir in discoverXcodeDeveloperDirectories() {
                let pyBin = "\(devDir)/usr/bin/python3"
                let pyFw = "\(devDir)/Library/Frameworks/Python3.framework"
                lines.append("(allow process-exec* (literal \"\(escapeSBPL(pyBin))\") (subpath \"\(escapeSBPL(pyFw))\"))")
            }
            lines.append("(allow process-exec* (literal \"/opt/homebrew/bin/python3\") (literal \"/usr/local/bin/python3\") (subpath \"/opt/homebrew/Cellar\") (subpath \"/opt/homebrew/opt\") (subpath \"/Library/Frameworks/Python.framework\"))")
            lines.append("(allow process-exec* (subpath \"\(escapeSBPL(plugPath))\"))")
            if allowSwiftToolchain {
                lines.append("(allow process-exec* (subpath \"/Applications/Xcode.app/Contents/Developer\") (subpath \"/Library/Developer/CommandLineTools\"))")
            }
        }

        // 不可覆盖底线（置于末尾，在 SBPL 后规则优先语义下拥有最高优先级）：严禁读取宿主密钥库或系统钥匙串
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

    public static func wrapExecutionCommand(
        executableURL: URL,
        arguments: [String],
        workingScopeDirectory: URL,
        grantedScopes: Set<PluginResourceScope>,
        dataDirectory: URL?,
        isolatedTmpDirectory: URL,
        stateRoot: URL,
        bridgeSocketPath: String? = nil,
        allowSwiftToolchain: Bool = false,
        forceSeatbelt: Bool = false
    ) -> (executableURL: URL, arguments: [String], profile: String) {
        let profile = buildProfile(
            pluginDirectory: workingScopeDirectory,
            dataDirectory: dataDirectory,
            isolatedTmpDirectory: isolatedTmpDirectory,
            vaultDirectories: protectedVaultDirectories(forStateRoot: stateRoot),
            bridgeSocketPath: bridgeSocketPath,
            allowedScopes: grantedScopes,
            allowSwiftToolchain: allowSwiftToolchain
        )
        if forceSeatbelt || isSeatbeltAvailable {
            return (
                URL(fileURLWithPath: "/usr/bin/sandbox-exec"),
                ["-p", profile, executableURL.path] + arguments,
                profile
            )
        }
        return (executableURL, arguments, profile)
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
        wrapExecutionCommand(
            executableURL: entryURL,
            arguments: arguments,
            workingScopeDirectory: descriptor.directoryURL,
            grantedScopes: grantedScopes,
            dataDirectory: dataDirectory,
            isolatedTmpDirectory: isolatedTmpDirectory,
            stateRoot: stateRoot,
            bridgeSocketPath: bridgeSocketPath,
            forceSeatbelt: forceSeatbelt
        )
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
        guard FileManager.default.isExecutableFile(atPath: sandboxExec.path),
              let result = try? ProcessSupervisor.shared.run(
                  executableURL: sandboxExec,
                  arguments: ["-p", "(version 1)\n(allow default)", "/usr/bin/true"],
                  timeoutSeconds: 2.0,
                  maxOutputBytes: 256
              )
        else { return false }
        return result.exitCode == 0 && !result.timedOut
    }
}

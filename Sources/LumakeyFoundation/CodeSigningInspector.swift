import Foundation
import Security

public enum CodeSignatureMode: Sendable, Equatable {
    case developerID(commonName: String, teamID: String?, hardenedRuntime: Bool)
    case appleDevelopment(commonName: String, teamID: String?)
    case customCertificate(commonName: String)
    case adHoc(hardenedRuntime: Bool)
    case unsigned

    public var authorityCommonName: String? {
        switch self {
        case .developerID(let commonName, _, _),
             .appleDevelopment(let commonName, _),
             .customCertificate(let commonName):
            return commonName
        case .adHoc, .unsigned:
            return nil
        }
    }
}

public struct CodeSigningStatus: Sendable, Equatable {
    public let mode: CodeSignatureMode
    public let bundleIdentifier: String
    public let teamIdentifier: String?
    public let isHardenedRuntime: Bool
    public let isStableForTCC: Bool
    public let isReadyForPublicDistribution: Bool
    public let badgeTitle: String
    public let explanation: String

    public init(
        mode: CodeSignatureMode,
        bundleIdentifier: String,
        teamIdentifier: String? = nil,
        isHardenedRuntime: Bool = false,
        isStableForTCC: Bool,
        isReadyForPublicDistribution: Bool = false,
        badgeTitle: String,
        explanation: String
    ) {
        self.mode = mode
        self.bundleIdentifier = bundleIdentifier
        self.teamIdentifier = teamIdentifier
        self.isHardenedRuntime = isHardenedRuntime
        self.isStableForTCC = isStableForTCC
        self.isReadyForPublicDistribution = isReadyForPublicDistribution
        self.badgeTitle = badgeTitle
        self.explanation = explanation
    }
}

public enum CodeSigningInspector {
    private static let adHocFlagMask: UInt32 = 0x0002
    private static let hardenedRuntimeFlagMask: UInt32 = 0x0001_0000

    public static func inspect(bundleURL: URL = Bundle.main.bundleURL) -> CodeSigningStatus {
        let fallbackBundleID = Bundle.main.bundleIdentifier ?? "app.lumakey.macos"
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else {
            return CodeSigningStatus(
                mode: .unsigned,
                bundleIdentifier: fallbackBundleID,
                isStableForTCC: false,
                badgeTitle: L10n.pick("未签名构建版本", "Unsigned Build"),
                explanation: L10n.pick(
                    "当前应用包未携带数字签名，版本覆盖升级后可能需要重新确认系统权限。",
                    "This app bundle is unsigned; macOS TCC permissions may require re-approval after updates."
                )
            )
        }

        var rawInfo: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &rawInfo) == errSecSuccess,
              let info = rawInfo as? [String: Any] else {
            return CodeSigningStatus(
                mode: .unsigned,
                bundleIdentifier: fallbackBundleID,
                isStableForTCC: false,
                badgeTitle: L10n.pick("未能读取签名信息", "Unable to Read Signature"),
                explanation: L10n.pick(
                    "无法解析当前应用包的代码签名元数据。",
                    "Could not inspect code signing metadata for the current app bundle."
                )
            )
        }

        let identifier = (info[kSecCodeInfoIdentifier as String] as? String) ?? fallbackBundleID
        let teamID = info[kSecCodeInfoTeamIdentifier as String] as? String
        let codeFlags = (info[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        let isAdHoc = (codeFlags & adHocFlagMask) != 0
        let isHardened = (codeFlags & hardenedRuntimeFlagMask) != 0

        if !isAdHoc,
           let certs = info[kSecCodeInfoCertificates as String] as? [SecCertificate],
           let leaf = certs.first {
            var commonName: CFString?
            SecCertificateCopyCommonName(leaf, &commonName)
            let cn = (commonName as String?) ?? "Apple Certificate"

            if cn.hasPrefix("Developer ID Application:") || cn.hasPrefix("Apple Distribution:") {
                let runtimeTag = isHardened ? "Hardened Runtime" : L10n.pick("标准运行时", "Standard Runtime")
                let teamLabel = teamID.map { " · Team \($0)" } ?? ""
                return CodeSigningStatus(
                    mode: .developerID(commonName: cn, teamID: teamID, hardenedRuntime: isHardened),
                    bundleIdentifier: identifier,
                    teamIdentifier: teamID,
                    isHardenedRuntime: isHardened,
                    isStableForTCC: true,
                    isReadyForPublicDistribution: isHardened,
                    badgeTitle: L10n.pick("官方分发签名 (\(runtimeTag)\(teamLabel))", "Developer ID Signed (\(runtimeTag)\(teamLabel))"),
                    explanation: L10n.pick(
                        "由 \(cn) 签署，支持跨设备 Gatekeeper 验证并在版本更新后自动延续「辅助功能 / 屏幕录制」授权。",
                        "Signed by \(cn); passes cross-Mac Gatekeeper checks and preserves Accessibility & Screen Recording permissions across updates."
                    )
                )
            }

            if cn.hasPrefix("Apple Development:") || cn.hasPrefix("Mac Developer:") {
                return CodeSigningStatus(
                    mode: .appleDevelopment(commonName: cn, teamID: teamID),
                    bundleIdentifier: identifier,
                    teamIdentifier: teamID,
                    isHardenedRuntime: isHardened,
                    isStableForTCC: true,
                    isReadyForPublicDistribution: false,
                    badgeTitle: L10n.pick("Apple 开发证书签名 (\(teamID ?? "Dev"))", "Apple Development Signed (\(teamID ?? "Dev"))"),
                    explanation: L10n.pick(
                        "已通过 \(cn) 固定身份签名，本机升级免重复授权；对外公开发布请切换为 Developer ID Application 证书并公证。",
                        "Signed with \(cn) for stable local TCC permissions; sign & notarize with Developer ID Application before public distribution."
                    )
                )
            }

            return CodeSigningStatus(
                mode: .customCertificate(commonName: cn),
                bundleIdentifier: identifier,
                teamIdentifier: teamID,
                isHardenedRuntime: isHardened,
                isStableForTCC: true,
                isReadyForPublicDistribution: false,
                badgeTitle: L10n.pick("本机固定证书签名 (\(cn))", "Local Certificate Signed (\(cn))"),
                explanation: L10n.pick(
                    "仅在当前电脑保持「辅助功能 / 屏幕录制」升级免重授权；对外分发给其他用户请使用 Developer ID 签名与公证。",
                    "Preserves Accessibility & Screen Recording permissions on this Mac only; use Developer ID signing & notarization for public releases."
                )
            )
        }

        return CodeSigningStatus(
            mode: .adHoc(hardenedRuntime: isHardened),
            bundleIdentifier: identifier,
            teamIdentifier: nil,
            isHardenedRuntime: isHardened,
            isStableForTCC: false,
            isReadyForPublicDistribution: false,
            badgeTitle: L10n.pick("开源社区构建版 (Ad-hoc 签名)", "Community Build (Ad-hoc Signed)"),
            explanation: L10n.pick(
                "当前为免开发者证书的通用构建包；覆盖更新版本后，如辅助功能或屏幕录制失效，可在「系统设置 › 隐私与安全性」重新勾选流光 Lumakey。",
                "Certificate-free community build; if Accessibility or Screen Recording resets after an update, re-toggle Lumakey in System Settings › Privacy & Security."
            )
        )
    }
}

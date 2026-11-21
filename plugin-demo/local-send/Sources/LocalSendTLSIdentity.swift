import CryptoKit
import Darwin
import Foundation
import Network
import Security

private struct StoredTLSIdentity: Codable {
    let privateKeyRawBase64: String
    let certificateDERBase64: String
    let fingerprint: String
}

/// 零外部依赖的自签名 X.509 v3 (P-256 / ECDSA-SHA256) TLS 身份与指纹校验器。
/// 证书与私钥持久化在隔离的 `LUCENT_DATA_DIR`，仅在 Seatbelt 放行的 `$TMPDIR` 中构建临时钥匙串供 `NWProtocolTLS` 使用，绝不触碰 `~/Library/Keychains`。
final class LocalSendTLSIdentity: @unchecked Sendable {
    let fingerprint: String
    let certificateDER: Data
    let secIdentity: sec_identity_t?
    let tlsInitError: String?

    private let tempKeychainPath: String?

    init(dataDirectory: URL) {
        let loaded = Self.loadOrCreateMaterial(in: dataDirectory)
        self.certificateDER = loaded.certificateDER
        self.fingerprint = loaded.fingerprint

        let built = Self.buildNWIdentity(privateKey: loaded.privateKey, certificateDER: loaded.certificateDER)
        self.secIdentity = built.identity
        self.tempKeychainPath = built.tempKeychainPath
        self.tlsInitError = built.error
    }

    deinit {
        cleanup()
    }

    func cleanup() {
        if let path = tempKeychainPath {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    func makeTLSParameters() -> NWParameters? {
        guard let secIdentity else { return nil }
        let tlsOptions = NWProtocolTLS.Options()
        sec_protocol_options_set_local_identity(tlsOptions.securityProtocolOptions, secIdentity)
        sec_protocol_options_set_min_tls_protocol_version(tlsOptions.securityProtocolOptions, .TLSv12)
        return NWParameters(tls: tlsOptions, tcp: NWProtocolTCP.Options())
    }

    private static func loadOrCreateMaterial(in dataDir: URL) -> (privateKey: P256.Signing.PrivateKey, certificateDER: Data, fingerprint: String) {
        let storeURL = dataDir.appendingPathComponent("tls-identity.json", isDirectory: false)
        if let data = try? Data(contentsOf: storeURL),
           let stored = try? JSONDecoder().decode(StoredTLSIdentity.self, from: data),
           let keyRaw = Data(base64Encoded: stored.privateKeyRawBase64),
           let certDER = Data(base64Encoded: stored.certificateDERBase64),
           let key = try? P256.Signing.PrivateKey(rawRepresentation: keyRaw),
           SecCertificateCreateWithData(nil, certDER as CFData) != nil {
            let fp = sha256Hex(certDER)
            return (key, certDER, fp)
        }
        let key = P256.Signing.PrivateKey()
        let certDER = generateSelfSignedX509DER(privateKey: key)
        let fp = sha256Hex(certDER)
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        let payload = StoredTLSIdentity(
            privateKeyRawBase64: key.rawRepresentation.base64EncodedString(),
            certificateDERBase64: certDER.base64EncodedString(),
            fingerprint: fp
        )
        if let encoded = try? JSONEncoder().encode(payload) {
            try? encoded.write(to: storeURL, options: .atomic)
            Darwin.chmod(storeURL.path, 0o600)
        }
        return (key, certDER, fp)
    }

    private static func buildNWIdentity(
        privateKey: P256.Signing.PrivateKey,
        certificateDER: Data
    ) -> (identity: sec_identity_t?, tempKeychainPath: String?, error: String?) {
        let kcURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ls-id-\(UUID().uuidString.prefix(12)).keychain-db")
        let kcPath = kcURL.path
        try? FileManager.default.removeItem(atPath: kcPath)

        guard let kc = createTemporaryKeychain(atPath: kcPath) else {
            return (nil, nil, "无法在临时沙箱目录创建 TLS 钥匙串")
        }
        Darwin.chmod(kcPath, 0o600)

        let sec1KeyDER = encodeSEC1PrivateKeyDER(privateKey)
        var keyFmt = SecExternalFormat.formatOpenSSL
        var keyType = SecExternalItemType.itemTypePrivateKey
        var importedKeys: CFArray?
        let keyStatus = SecItemImport(sec1KeyDER as CFData, nil, &keyFmt, &keyType, [], nil, kc, &importedKeys)
        guard keyStatus == errSecSuccess else {
            try? FileManager.default.removeItem(atPath: kcPath)
            return (nil, nil, "导入临时私钥失败 (\(keyStatus))")
        }

        var certFmt = SecExternalFormat.formatX509Cert
        var certType = SecExternalItemType.itemTypeCertificate
        var importedCerts: CFArray?
        let certStatus = SecItemImport(certificateDER as CFData, nil, &certFmt, &certType, [], nil, kc, &importedCerts)
        guard certStatus == errSecSuccess,
              let cert = (importedCerts as? [SecCertificate])?.first else {
            try? FileManager.default.removeItem(atPath: kcPath)
            return (nil, nil, "导入临时证书失败 (\(certStatus))")
        }

        var rawIdentity: SecIdentity?
        let idStatus = SecIdentityCreateWithCertificate(kc, cert, &rawIdentity)
        guard idStatus == errSecSuccess, let rawIdentity, let nwIdent = sec_identity_create(rawIdentity) else {
            try? FileManager.default.removeItem(atPath: kcPath)
            return (nil, nil, "构建 TLS 身份失败 (\(idStatus))")
        }
        return (nwIdent, kcPath, nil)
    }

    /// 签名外置 CLI 无 Data Protection Keychain 权限且 Seatbelt 封锁用户钥匙串，需经临时文件钥匙串桥接 `SecIdentity`。
    private static func createTemporaryKeychain(atPath path: String) -> SecKeychain? {
        typealias CreateFn = @convention(c) (
            UnsafePointer<CChar>, UInt32, UnsafeRawPointer?, DarwinBoolean, SecAccess?, UnsafeMutablePointer<SecKeychain?>
        ) -> OSStatus
        guard let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
              let sym = dlsym(handle, "SecKeychainCreate") else { return nil }
        let create = unsafeBitCast(sym, to: CreateFn.self)
        var kc: SecKeychain?
        let pass = UUID().uuidString
        let status = path.withCString { cPath in
            pass.withCString { cPass in
                create(cPath, UInt32(pass.utf8.count), cPass, false, nil, &kc)
            }
        }
        return status == errSecSuccess ? kc : nil
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02X", $0) }.joined()
    }

    // MARK: - Minimal ASN.1 / DER X.509 v3 & SEC1 Encoder

    static func generateSelfSignedX509DER(privateKey: P256.Signing.PrivateKey) -> Data {
        let oidECDSASHA256 = Data([0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x04, 0x03, 0x02])
        let oidECPublicKey = Data([0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01])
        let oidPrime256v1 = Data([0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07])
        let oidCommonName = Data([0x06, 0x03, 0x55, 0x04, 0x03])
        let oidBasicConstraints = Data([0x06, 0x03, 0x55, 0x1D, 0x13])
        let oidExtKeyUsage = Data([0x06, 0x03, 0x55, 0x1D, 0x25])
        let oidServerAuth = Data([0x06, 0x08, 0x2B, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x01])
        let oidClientAuth = Data([0x06, 0x08, 0x2B, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x02])

        let version = derTLV(0xA0, derTLV(0x02, Data([0x02])))
        var serialBytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, serialBytes.count, &serialBytes)
        serialBytes[0] &= 0x7F
        if serialBytes[0] == 0 { serialBytes[0] = 0x01 }
        let serial = derTLV(0x02, Data(serialBytes))
        let sigAlg = derTLV(0x30, oidECDSASHA256)

        let cnAttr = derTLV(0x30, oidCommonName + derTLV(0x0C, Data("LocalSend".utf8)))
        let name = derTLV(0x30, derTLV(0x31, cnAttr))

        let now = Date()
        let notBefore = derUTCTime(now.addingTimeInterval(-86_400))
        let notAfter = derUTCTime(now.addingTimeInterval(86_400 * 3650))
        let validity = derTLV(0x30, notBefore + notAfter)

        let spkiAlg = derTLV(0x30, oidECPublicKey + oidPrime256v1)
        let spkiKey = derTLV(0x03, Data([0x00]) + privateKey.publicKey.x963Representation)
        let spki = derTLV(0x30, spkiAlg + spkiKey)

        let bcExt = derTLV(0x30, oidBasicConstraints + derTLV(0x01, Data([0xFF])) + derTLV(0x04, derTLV(0x30, Data())))
        let ekuExt = derTLV(0x30, oidExtKeyUsage + derTLV(0x04, derTLV(0x30, oidServerAuth + oidClientAuth)))
        let extensions = derTLV(0xA3, derTLV(0x30, bcExt + ekuExt))

        let tbs = derTLV(0x30, version + serial + sigAlg + name + validity + name + spki + extensions)
        let sigDER = (try? privateKey.signature(for: tbs).derRepresentation) ?? Data()
        let sigBitString = derTLV(0x03, Data([0x00]) + sigDER)
        return derTLV(0x30, tbs + sigAlg + sigBitString)
    }

    private static func encodeSEC1PrivateKeyDER(_ privateKey: P256.Signing.PrivateKey) -> Data {
        let oidPrime256v1 = Data([0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07])
        let pubBits = derTLV(0x03, Data([0x00]) + privateKey.publicKey.x963Representation)
        let body = derTLV(0x02, Data([0x01]))
            + derTLV(0x04, privateKey.rawRepresentation)
            + derTLV(0xA0, oidPrime256v1)
            + derTLV(0xA1, pubBits)
        return derTLV(0x30, body)
    }

    private static func derUTCTime(_ date: Date) -> Data {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        fmt.dateFormat = "yyMMddHHmmss'Z'"
        return derTLV(0x17, Data(fmt.string(from: date).utf8))
    }

    private static func derTLV(_ tag: UInt8, _ body: Data) -> Data {
        var out = Data([tag])
        let len = body.count
        if len < 0x80 {
            out.append(UInt8(len))
        } else if len <= 0xFF {
            out.append(0x81); out.append(UInt8(len))
        } else {
            out.append(0x82); out.append(UInt8((len >> 8) & 0xFF)); out.append(UInt8(len & 0xFF))
        }
        out.append(body)
        return out
    }
}

/// 校验远端 LocalSend 自签名 HTTPS 证书指纹的 `URLSessionDelegate`。
final class LocalSendTrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let expectedFingerprint: String?

    init(expectedFingerprint: String?) {
        self.expectedFingerprint = expectedFingerprint?.uppercased()
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        if let expected = expectedFingerprint, !expected.isEmpty {
            let actual = LocalSendTLSIdentity.sha256Hex(SecCertificateCopyData(leaf) as Data)
            guard actual == expected else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

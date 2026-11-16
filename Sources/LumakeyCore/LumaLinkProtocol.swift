import LumakeyFoundation; import LumakeySearch; import LumakeyMedia; import LumakeySystem
import Foundation

public struct LumaLinkPairedDevice: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var token: String
    public var pairedAt: TimeInterval

    public init(id: String = UUID().uuidString, name: String, token: String, pairedAt: TimeInterval = Date().timeIntervalSince1970) {
        self.id = id; self.name = name; self.token = token; self.pairedAt = pairedAt
    }
}

public struct LumaLinkConfig: Codable, Sendable, Hashable {
    public var enabled: Bool = false
    public var preferredPort: UInt16 = 59480
    public var autoRestoreDisplayOnDisconnect: Bool = true
    public var muteMacWhenCurtainEnabled: Bool = true
    public var rdpEnabled: Bool = false
    public var rdpPort: UInt16 = 3389
    public var rdpLocalAudioEnabled: Bool = true
    public var preferredVirtualMicName: String = ""
    public var pairedDevices: [LumaLinkPairedDevice] = []

    enum CodingKeys: String, CodingKey {
        case enabled, preferredPort, autoRestoreDisplayOnDisconnect
        case muteMacWhenCurtainEnabled, rdpEnabled, rdpPort
        case rdpLocalAudioEnabled, preferredVirtualMicName, pairedDevices
    }

    public init(
        enabled: Bool = false, preferredPort: UInt16 = 59480,
        autoRestoreDisplayOnDisconnect: Bool = true, muteMacWhenCurtainEnabled: Bool = true,
        rdpEnabled: Bool = false, rdpPort: UInt16 = 3389,
        rdpLocalAudioEnabled: Bool = true, preferredVirtualMicName: String = "",
        pairedDevices: [LumaLinkPairedDevice] = []
    ) {
        self.enabled = enabled; self.preferredPort = preferredPort
        self.autoRestoreDisplayOnDisconnect = autoRestoreDisplayOnDisconnect
        self.muteMacWhenCurtainEnabled = muteMacWhenCurtainEnabled
        self.rdpEnabled = rdpEnabled; self.rdpPort = rdpPort
        self.rdpLocalAudioEnabled = rdpLocalAudioEnabled
        self.preferredVirtualMicName = preferredVirtualMicName
        self.pairedDevices = pairedDevices
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        preferredPort = try c.decodeIfPresent(UInt16.self, forKey: .preferredPort) ?? 59480
        autoRestoreDisplayOnDisconnect = try c.decodeIfPresent(Bool.self, forKey: .autoRestoreDisplayOnDisconnect) ?? true
        muteMacWhenCurtainEnabled = try c.decodeIfPresent(Bool.self, forKey: .muteMacWhenCurtainEnabled) ?? true
        rdpEnabled = try c.decodeIfPresent(Bool.self, forKey: .rdpEnabled) ?? false
        rdpPort = try c.decodeIfPresent(UInt16.self, forKey: .rdpPort) ?? 3389
        rdpLocalAudioEnabled = try c.decodeIfPresent(Bool.self, forKey: .rdpLocalAudioEnabled) ?? true
        preferredVirtualMicName = try c.decodeIfPresent(String.self, forKey: .preferredVirtualMicName) ?? ""
        pairedDevices = try c.decodeIfPresent([LumaLinkPairedDevice].self, forKey: .pairedDevices) ?? []
    }

    public static func defaultConfigURL() -> URL {
        LumakeyAppPaths.defaultAppSupportDirectory().appendingPathComponent("lumalink-config.json")
    }

    private static func resolvedVaultURL(forConfigURL url: URL, vaultDirectory: URL?) -> URL? {
        if let vaultDirectory {
            return vaultDirectory.appendingPathComponent(LocalSecretVault.vaultFileName, isDirectory: false)
        }
        let std = url.standardizedFileURL
        return std.path == defaultConfigURL().standardizedFileURL.path
            ? nil
            : LocalSecretVault.defaultVaultFileURL(in: std.deletingLastPathComponent())
    }

    public static func load(from url: URL = defaultConfigURL(), vaultDirectory: URL? = nil) -> LumaLinkConfig {
        guard let data = try? Data(contentsOf: url),
              var decoded = try? JSONDecoder().decode(LumaLinkConfig.self, from: data)
        else { return LumaLinkConfig() }
        let vaultURL = resolvedVaultURL(forConfigURL: url, vaultDirectory: vaultDirectory)
        var migratedPlaintext = false
        for idx in decoded.pairedDevices.indices {
            let devID = decoded.pairedDevices[idx].id
            let inlineToken = decoded.pairedDevices[idx].token
            if let vaulted = try? LocalSecretVault.loadValue(
                service: LumakeyAppPaths.lumaLinkKeychainService, account: devID, customVaultURL: vaultURL
            ), !vaulted.isEmpty {
                decoded.pairedDevices[idx].token = vaulted
                if !inlineToken.isEmpty { migratedPlaintext = true }
            } else if !inlineToken.isEmpty {
                try? LocalSecretVault.saveValue(
                    inlineToken, service: LumakeyAppPaths.lumaLinkKeychainService, account: devID, customVaultURL: vaultURL
                )
                migratedPlaintext = true
            }
        }
        if migratedPlaintext { decoded.writeScrubbedJSON(to: url) }
        return decoded
    }

    public func save(to url: URL = defaultConfigURL(), vaultDirectory: URL? = nil) {
        let vaultURL = Self.resolvedVaultURL(forConfigURL: url, vaultDirectory: vaultDirectory)
        for dev in pairedDevices where !dev.token.isEmpty {
            try? LocalSecretVault.saveValue(
                dev.token, service: LumakeyAppPaths.lumaLinkKeychainService, account: dev.id, customVaultURL: vaultURL
            )
        }
        writeScrubbedJSON(to: url)
    }

    private func writeScrubbedJSON(to url: URL) {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var scrubbed = self
        for idx in scrubbed.pairedDevices.indices { scrubbed.pairedDevices[idx].token = "" }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(scrubbed) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

public struct LumaLinkDisplayModeInfo: Codable, Sendable, Hashable {
    public var modeKey: String
    public var label: String
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var pointWidth: Int
    public var pointHeight: Int
    public var refreshHz: Int
    public var isHiDPI: Bool
    public var isCurrent: Bool

    public init(
        modeKey: String, label: String, pixelWidth: Int, pixelHeight: Int,
        pointWidth: Int, pointHeight: Int, refreshHz: Int, isHiDPI: Bool, isCurrent: Bool
    ) {
        self.modeKey = modeKey; self.label = label
        self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight
        self.pointWidth = pointWidth; self.pointHeight = pointHeight
        self.refreshHz = refreshHz; self.isHiDPI = isHiDPI; self.isCurrent = isCurrent
    }
}

public struct LumaLinkDisplayInfo: Codable, Sendable, Hashable {
    public var displayID: UInt32
    public var name: String
    public var isMain: Bool
    public var currentModeKey: String
    public var modes: [LumaLinkDisplayModeInfo]

    public init(displayID: UInt32, name: String, isMain: Bool, currentModeKey: String, modes: [LumaLinkDisplayModeInfo]) {
        self.displayID = displayID; self.name = name; self.isMain = isMain
        self.currentModeKey = currentModeKey; self.modes = modes
    }
}

public struct LumaLinkTelemetry: Codable, Sendable, Hashable {
    public var cpuPercent: Double
    public var memoryUsedGB: Double
    public var memoryTotalGB: Double
    public var memoryPercent: Double
    public var systemWatts: Double
    public var batteryPercent: Int
    public var isCharging: Bool
    public var netDownBytesPerSec: Double
    public var netUpBytesPerSec: Double
    public var thermalState: String
    public var volumePercent: Int
    public var isMuted: Bool
    public var privacyCurtainActive: Bool
    public var caffeineActive: Bool

    public init(
        cpuPercent: Double = 0, memoryUsedGB: Double = 0, memoryTotalGB: Double = 0, memoryPercent: Double = 0,
        systemWatts: Double = 0, batteryPercent: Int = -1, isCharging: Bool = false,
        netDownBytesPerSec: Double = 0, netUpBytesPerSec: Double = 0, thermalState: String = "正常",
        volumePercent: Int = 50, isMuted: Bool = false, privacyCurtainActive: Bool = false, caffeineActive: Bool = false
    ) {
        self.cpuPercent = cpuPercent; self.memoryUsedGB = memoryUsedGB
        self.memoryTotalGB = memoryTotalGB; self.memoryPercent = memoryPercent
        self.systemWatts = systemWatts; self.batteryPercent = batteryPercent; self.isCharging = isCharging
        self.netDownBytesPerSec = netDownBytesPerSec; self.netUpBytesPerSec = netUpBytesPerSec
        self.thermalState = thermalState; self.volumePercent = volumePercent; self.isMuted = isMuted
        self.privacyCurtainActive = privacyCurtainActive; self.caffeineActive = caffeineActive
    }
}

public struct LumaLinkRequest: Codable, Sendable {
    public var id: String
    public var action: String
    public var token: String?
    public var pin: String?
    public var deviceName: String?
    public var displayID: UInt32?
    public var modeKey: String?
    public var command: String?
    public var percent: Int?
    public var text: String?

    public init(
        id: String = UUID().uuidString, action: String, token: String? = nil, pin: String? = nil,
        deviceName: String? = nil, displayID: UInt32? = nil, modeKey: String? = nil,
        command: String? = nil, percent: Int? = nil, text: String? = nil
    ) {
        self.id = id; self.action = action; self.token = token; self.pin = pin
        self.deviceName = deviceName; self.displayID = displayID; self.modeKey = modeKey
        self.command = command; self.percent = percent; self.text = text
    }
}

public struct LumaLinkResponse: Codable, Sendable {
    public var id: String
    public var type: String
    public var ok: Bool
    public var error: String?
    public var hostName: String?
    public var protocolVersion: Int?
    public var requiresPairing: Bool?
    public var token: String?
    public var deviceId: String?
    public var displays: [LumaLinkDisplayInfo]?
    public var telemetry: LumaLinkTelemetry?
    public var clipboardText: String?
    public var rdpEnabled: Bool?
    public var rdpPort: Int?
    public var audio: LumaLinkAudioStatus?

    public init(
        id: String, type: String = "response", ok: Bool, error: String? = nil,
        hostName: String? = nil, protocolVersion: Int? = nil, requiresPairing: Bool? = nil,
        token: String? = nil, deviceId: String? = nil, displays: [LumaLinkDisplayInfo]? = nil,
        telemetry: LumaLinkTelemetry? = nil, clipboardText: String? = nil,
        rdpEnabled: Bool? = nil, rdpPort: Int? = nil, audio: LumaLinkAudioStatus? = nil
    ) {
        self.id = id; self.type = type; self.ok = ok; self.error = error
        self.hostName = hostName; self.protocolVersion = protocolVersion
        self.requiresPairing = requiresPairing; self.token = token; self.deviceId = deviceId
        self.displays = displays; self.telemetry = telemetry; self.clipboardText = clipboardText
        self.rdpEnabled = rdpEnabled; self.rdpPort = rdpPort; self.audio = audio
    }
}

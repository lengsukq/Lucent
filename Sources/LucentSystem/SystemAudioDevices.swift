import CoreAudio
import Foundation

public enum SystemAudioDirection: String, Sendable {
    case input, output

    fileprivate var selector: AudioObjectPropertySelector {
        switch self {
        case .input: kAudioHardwarePropertyDefaultInputDevice
        case .output: kAudioHardwarePropertyDefaultOutputDevice
        }
    }

    fileprivate var scope: AudioObjectPropertyScope {
        self == .input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput
    }
}

public struct SystemAudioDevice: Equatable, Sendable {
    public let uid: String
    public let name: String
    public let input: Bool
    public let output: Bool

    public init(uid: String, name: String, input: Bool, output: Bool) {
        self.uid = uid
        self.name = name
        self.input = input
        self.output = output
    }
}

public protocol AudioDeviceHardware: Sendable {
    func availableDevices() -> [SystemAudioDevice]
    func defaultDevice(_ direction: SystemAudioDirection) -> String?
    func setDefaultDevice(_ uid: String, direction: SystemAudioDirection) -> Bool
}

public struct SystemAudioDevices: AudioDeviceHardware {
    private static let system = AudioObjectID(kAudioObjectSystemObject)

    public init() {}

    public func availableDevices() -> [SystemAudioDevice] {
        deviceIDs().compactMap { id in
            guard isAlive(id), let uid = stringProperty(kAudioDevicePropertyDeviceUID, on: id),
                  let name = stringProperty(kAudioObjectPropertyName, on: id) else { return nil }
            let input = hasStreams(id, direction: .input)
            let output = hasStreams(id, direction: .output)
            guard input || output else { return nil }
            return SystemAudioDevice(uid: uid, name: name, input: input, output: output)
        }.sorted {
            let comparison = $0.name.localizedStandardCompare($1.name)
            return comparison == .orderedSame ? $0.uid < $1.uid : comparison == .orderedAscending
        }
    }

    public func defaultDevice(_ direction: SystemAudioDirection) -> String? {
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = property(direction.selector)
        guard AudioObjectGetPropertyData(Self.system, &address, 0, nil, &size, &id) == noErr,
              id != kAudioObjectUnknown else { return nil }
        return stringProperty(kAudioDevicePropertyDeviceUID, on: id)
    }

    public func setDefaultDevice(_ uid: String, direction: SystemAudioDirection) -> Bool {
        guard var id = deviceIDs().first(where: { candidate in
            isAlive(candidate) && hasStreams(candidate, direction: direction)
                && stringProperty(kAudioDevicePropertyDeviceUID, on: candidate) == uid
        }) else { return false }
        var address = property(direction.selector)
        return AudioObjectSetPropertyData(Self.system, &address, 0, nil,
                                          UInt32(MemoryLayout<AudioObjectID>.size), &id) == noErr
    }

    private func deviceIDs() -> [AudioObjectID] {
        var address = property(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(Self.system, &address, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioObjectID>.stride else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.stride)
        let status = ids.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { return kAudioHardwareBadPropertySizeError }
            return AudioObjectGetPropertyData(Self.system, &address, 0, nil, &size, base)
        }
        guard status == noErr else { return [] }
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.stride))
    }

    private func isAlive(_ id: AudioObjectID) -> Bool {
        var address = property(kAudioDevicePropertyDeviceIsAlive)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr && value != 0
    }

    private func hasStreams(_ id: AudioObjectID, direction: SystemAudioDirection) -> Bool {
        var address = property(kAudioDevicePropertyStreams, scope: direction.scope)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private func stringProperty(_ selector: AudioObjectPropertySelector, on id: AudioObjectID) -> String? {
        var address = property(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout.size(ofValue: value))
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr,
              let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private func property(_ selector: AudioObjectPropertySelector,
                          scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
}

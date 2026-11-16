import LumakeyFoundation; import LumakeySearch; import LumakeyMedia; import LumakeySystem
import AudioToolbox
import CoreAudio
import Foundation

public struct LumaLinkAudioStatus: Codable, Sendable, Hashable {
    public var virtualMicDeviceName: String?
    public var virtualMicActive: Bool
    public var speakerTapActive: Bool
    public var availableVirtualMics: [String]
    public var note: String?

    public init(
        virtualMicDeviceName: String? = nil,
        virtualMicActive: Bool = false,
        speakerTapActive: Bool = false,
        availableVirtualMics: [String] = [],
        note: String? = nil
    ) {
        self.virtualMicDeviceName = virtualMicDeviceName
        self.virtualMicActive = virtualMicActive
        self.speakerTapActive = speakerTapActive
        self.availableVirtualMics = availableVirtualMics
        self.note = note
    }
}

public struct LumaLinkAudioDeviceOption: Sendable, Hashable {
    public let deviceID: AudioDeviceID
    public let name: String
    public let isLoopbackVirtual: Bool
}

public final class LumaLinkAudioBridgeService: @unchecked Sendable {
    public static let shared = LumaLinkAudioBridgeService()

    private static let micMagic: [UInt8] = [0x4C, 0x41, 0x4D, 0x31] // "LAM1"
    private let lock = NSLock()
    private var outputUnit: AudioUnit?
    private var activeDeviceID: AudioDeviceID = kAudioObjectUnknown
    private var activeDeviceName: String?
    private var currentSampleRate: Double = 24_000
    private var currentChannels: UInt32 = 1
    private var ringBuffer = Data()
    private var maxRingBytes: Int = 24_000 * 2 // ~1s max, trim to ~160ms on overflow

    private init() {}

    public func status(preferredName: String) -> LumaLinkAudioStatus {
        let devices = Self.enumerateVirtualLoopbackDevices()
        let selected = Self.resolveTargetDevice(preferredName: preferredName, devices: devices)
        let running = lock.withLock { outputUnit != nil }
        let names = devices.map(\.name)
        let note: String? = selected == nil
            ? "未检测到虚拟声卡驱动（如 BlackHole 2ch），仅支持通过“安装 BlackHole 2ch”或开启 RDP 音频接收"
            : nil
        return LumaLinkAudioStatus(
            virtualMicDeviceName: selected?.name,
            virtualMicActive: running,
            speakerTapActive: LumaLinkSpeakerTapService.shared.isRunning,
            availableVirtualMics: names,
            note: note
        )
    }

    public func startVirtualMic(preferredName: String) -> LumaLinkAudioStatus {
        let devices = Self.enumerateVirtualLoopbackDevices()
        guard let target = Self.resolveTargetDevice(preferredName: preferredName, devices: devices) else {
            return status(preferredName: preferredName)
        }
        lock.withLock {
            if outputUnit != nil, activeDeviceID == target.deviceID {
                return
            }
            stopLocked()
            if setupOutputUnitLocked(deviceID: target.deviceID, sampleRate: currentSampleRate, channels: currentChannels) {
                activeDeviceID = target.deviceID
                activeDeviceName = target.name
            }
        }
        return status(preferredName: preferredName)
    }

    public func stopVirtualMic() {
        lock.withLock { stopLocked() }
    }

    public func handleIncomingPacket(_ frame: Data, preferredName: String) -> Bool {
        guard frame.count > 8 else { return false }
        let magic = [frame[frame.startIndex], frame[frame.startIndex + 1], frame[frame.startIndex + 2], frame[frame.startIndex + 3]]
        guard magic == Self.micMagic else { return false }

        let rate = Double(UInt16(frame[frame.startIndex + 4]) | (UInt16(frame[frame.startIndex + 5]) << 8))
        let ch = max(UInt32(1), min(UInt32(2), UInt32(frame[frame.startIndex + 6])))
        let safeRate = (rate >= 8_000 && rate <= 48_000) ? rate : 24_000
        let pcm = frame.subdata(in: (frame.startIndex + 8)..<frame.endIndex)
        guard !pcm.isEmpty else { return true }

        lock.withLock {
            if outputUnit == nil || safeRate != currentSampleRate || ch != currentChannels {
                let devices = Self.enumerateVirtualLoopbackDevices()
                guard let target = Self.resolveTargetDevice(preferredName: preferredName, devices: devices) else { return }
                stopLocked()
                currentSampleRate = safeRate
                currentChannels = ch
                maxRingBytes = Int(safeRate) * Int(ch) * 2 / 4 // cap jitter to 250ms
                if setupOutputUnitLocked(deviceID: target.deviceID, sampleRate: safeRate, channels: ch) {
                    activeDeviceID = target.deviceID
                    activeDeviceName = target.name
                }
            }
            ringBuffer.append(pcm)
            let hardCap = max(9_600, maxRingBytes)
            let trimTarget = hardCap / 2
            if ringBuffer.count > hardCap {
                ringBuffer.removeFirst(ringBuffer.count - trimTarget)
            }
        }
        return true
    }

    private func setupOutputUnitLocked(deviceID: AudioDeviceID, sampleRate: Double, channels: UInt32) -> Bool {
        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let comp = AudioComponentFindNext(nil, &desc) else { return false }
        var unitOpt: AudioUnit?
        guard AudioComponentInstanceNew(comp, &unitOpt) == noErr, let unit = unitOpt else { return false }

        var enableOutput: UInt32 = 1
        var disableInput: UInt32 = 0
        AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &enableOutput, 4)
        AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &disableInput, 4)

        var devID = deviceID
        guard AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &devID, UInt32(MemoryLayout<AudioDeviceID>.size)) == noErr else {
            AudioComponentInstanceDispose(unit)
            return false
        }

        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2 * channels,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2 * channels,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        guard AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &asbd, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)) == noErr else {
            AudioComponentInstanceDispose(unit)
            return false
        }

        var cb = AURenderCallbackStruct(
            inputProc: Self.renderCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        guard AudioUnitSetProperty(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &cb, UInt32(MemoryLayout<AURenderCallbackStruct>.size)) == noErr else {
            AudioComponentInstanceDispose(unit)
            return false
        }

        guard AudioUnitInitialize(unit) == noErr, AudioOutputUnitStart(unit) == noErr else {
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
            return false
        }
        ringBuffer.removeAll(keepingCapacity: true)
        outputUnit = unit
        return true
    }

    private func stopLocked() {
        if let unit = outputUnit {
            AudioOutputUnitStop(unit)
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
            outputUnit = nil
        }
        activeDeviceID = kAudioObjectUnknown
        activeDeviceName = nil
        ringBuffer.removeAll(keepingCapacity: false)
    }

    private static let renderCallback: AURenderCallback = { inRefCon, _, _, _, _, ioData -> OSStatus in
        let service = Unmanaged<LumaLinkAudioBridgeService>.fromOpaque(inRefCon).takeUnretainedValue()
        guard let ioData, ioData.pointee.mNumberBuffers > 0 else { return noErr }
        let buf = ioData.pointee.mBuffers
        guard let dst = buf.mData else { return noErr }
        let needed = Int(buf.mDataByteSize)

        service.lock.lock()
        let available = service.ringBuffer.count
        let copyCount = min(needed, available)
        if copyCount > 0 {
            service.ringBuffer.withUnsafeBytes { raw in
                if let base = raw.baseAddress {
                    memcpy(dst, base, copyCount)
                }
            }
            service.ringBuffer.removeFirst(copyCount)
        }
        service.lock.unlock()

        if copyCount < needed {
            memset(dst.advanced(by: copyCount), 0, needed - copyCount)
        }
        return noErr
    }

    public static func enumerateVirtualLoopbackDevices() -> [LumaLinkAudioDeviceOption] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }

        let keywords = ["blackhole", "vb-cable", "vbcable", "loopback", "soundflower", "background music", "virtual"]
        return ids.compactMap { id in
            guard channelCount(deviceID: id, scope: kAudioObjectPropertyScopeOutput) > 0,
                  channelCount(deviceID: id, scope: kAudioObjectPropertyScopeInput) > 0,
                  let name = deviceName(deviceID: id) else { return nil }
            let lower = name.lowercased()
            let isVirtual = keywords.contains { lower.contains($0) }
            guard isVirtual else { return nil }
            return LumaLinkAudioDeviceOption(deviceID: id, name: name, isLoopbackVirtual: true)
        }
    }

    private static func resolveTargetDevice(preferredName: String, devices: [LumaLinkAudioDeviceOption]) -> LumaLinkAudioDeviceOption? {
        let trimmed = preferredName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, let match = devices.first(where: { $0.name.localizedCaseInsensitiveContains(trimmed) }) {
            return match
        }
        return devices.first(where: { $0.name.localizedCaseInsensitiveContains("BlackHole 2ch") }) ?? devices.first
    }

    private static func deviceName(deviceID: AudioDeviceID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfName: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &cfName) == noErr,
              let resolved = cfName?.takeUnretainedValue() as String? else { return nil }
        return resolved
    }

    private static func channelCount(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let rawPtr = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { rawPtr.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, rawPtr) == noErr else { return 0 }
        let abl = rawPtr.assumingMemoryBound(to: AudioBufferList.self)
        let listPtr = UnsafeMutableAudioBufferListPointer(abl)
        return listPtr.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}

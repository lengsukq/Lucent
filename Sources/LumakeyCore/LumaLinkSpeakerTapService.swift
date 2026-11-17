import LumakeyFoundation; import LumakeySearch; import LumakeyMedia; import LumakeySystem
import AudioToolbox
import CoreAudio
import Foundation

public final class LumaLinkSpeakerTapService: @unchecked Sendable {
    public static let shared = LumaLinkSpeakerTapService()
    private static let speakerMagic: [UInt8] = [0x4C, 0x41, 0x53, 0x31] // "LAS1"

    private let lock = NSLock()
    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private var srcRate: Double = 48_000
    private var srcChannels: Int = 2
    private var subscribers: [String: @Sendable (Data) -> Void] = [:]

    private init() {}

    public var isRunning: Bool {
        lock.withLock { ioProcID != nil }
    }

    public func subscribe(sessionID: String, handler: @escaping @Sendable (Data) -> Void) -> String? {
        var startError: String?
        lock.withLock {
            subscribers[sessionID] = handler
            if ioProcID == nil {
                startError = startTapLocked()
                if startError != nil {
                    subscribers.removeValue(forKey: sessionID)
                }
            }
        }
        return startError
    }

    public func unsubscribe(sessionID: String) {
        lock.withLock {
            subscribers.removeValue(forKey: sessionID)
            if subscribers.isEmpty {
                stopTapLocked()
            }
        }
    }

    public func stopAll() {
        lock.withLock {
            subscribers.removeAll()
            stopTapLocked()
        }
    }

    private func startTapLocked() -> String? {
        guard #available(macOS 14.4, *) else {
            return "系统音频转发需要 macOS 14.4 及以上版本"
        }
        // Exclude Lumakey itself so bridged mobile mic audio written to BlackHole 2ch
        // is never looped back into the speaker tap stream.
        let excludedProcesses: [AudioObjectID] = Self.currentProcessAudioObjectID().map { [$0] } ?? []
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: excludedProcesses)
        desc.name = "LumaLink Speaker Tap"
        desc.isPrivate = true
        desc.muteBehavior = .unmuted

        var tap: AudioObjectID = kAudioObjectUnknown
        let tapStatus = AudioHardwareCreateProcessTap(desc, &tap)
        guard tapStatus == noErr, tap != kAudioObjectUnknown else {
            return "系统音频录制未授权或创建失败 (\(tapStatus))"
        }
        tapID = tap

        var uidAddr = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var tapUID: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(tap, &uidAddr, 0, nil, &uidSize, &tapUID) == noErr,
              let tapUIDStr = tapUID?.takeUnretainedValue() as String? else {
            stopTapLocked()
            return "读取系统音频 Tap UID 失败"
        }

        let aggDict: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "LumaLink Tap Aggregate",
            kAudioAggregateDeviceUIDKey as String: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey as String: true,
            kAudioAggregateDeviceTapAutoStartKey as String: true,
            kAudioAggregateDeviceTapListKey as String: [
                [
                    kAudioSubTapUIDKey as String: tapUIDStr,
                    kAudioSubTapDriftCompensationKey as String: true
                ]
            ]
        ]
        var agg: AudioObjectID = kAudioObjectUnknown
        let aggStatus = AudioHardwareCreateAggregateDevice(aggDict as CFDictionary, &agg)
        guard aggStatus == noErr, agg != kAudioObjectUnknown else {
            stopTapLocked()
            return "创建音频聚合设备失败 (\(aggStatus))"
        }
        aggregateID = agg

        var fmtAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var asbd = AudioStreamBasicDescription()
        var asbdSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(agg, &fmtAddr, 0, nil, &asbdSize, &asbd) == noErr,
              asbd.mSampleRate > 0, asbd.mChannelsPerFrame > 0 else {
            stopTapLocked()
            return "读取系统音频格式失败"
        }
        srcRate = asbd.mSampleRate
        srcChannels = max(1, Int(asbd.mChannelsPerFrame))

        var procID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcID(agg, Self.ioProc, Unmanaged.passUnretained(self).toOpaque(), &procID)
        guard status == noErr, let procID else {
            stopTapLocked()
            return "注册系统音频采集回调失败 (\(status))"
        }
        ioProcID = procID

        let startStatus = AudioDeviceStart(agg, procID)
        guard startStatus == noErr else {
            stopTapLocked()
            return "启动系统音频采集失败 (\(startStatus))"
        }
        return nil
    }

    private func stopTapLocked() {
        if aggregateID != kAudioObjectUnknown, let proc = ioProcID {
            AudioDeviceStop(aggregateID, proc)
            AudioDeviceDestroyIOProcID(aggregateID, proc)
        }
        ioProcID = nil
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            if #available(macOS 14.4, *) {
                AudioHardwareDestroyProcessTap(tapID)
            }
            tapID = kAudioObjectUnknown
        }
    }

    private static func currentProcessAudioObjectID() -> AudioObjectID? {
        var pid = ProcessInfo.processInfo.processIdentifier
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var objID: AudioObjectID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            UInt32(MemoryLayout<pid_t>.size),
            &pid,
            &size,
            &objID
        )
        guard status == noErr, objID != kAudioObjectUnknown else { return nil }
        return objID
    }

    private static let ioProc: AudioDeviceIOProc = { _, _, inInputData, _, _, _, clientData in
        guard let clientData else { return noErr }
        let service = Unmanaged<LumaLinkSpeakerTapService>.fromOpaque(clientData).takeUnretainedValue()
        service.handleInputBufferList(inInputData)
        return noErr
    }

    private func handleInputBufferList(_ inputListPtr: UnsafePointer<AudioBufferList>) {
        let listeners = lock.withLock { Array(subscribers.values) }
        guard !listeners.isEmpty else { return }

        let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputListPtr))
        guard let firstBuf = abl.first, let rawData = firstBuf.mData else { return }
        let isPlanarStereo = abl.count >= 2 && firstBuf.mNumberChannels == 1 && abl[1].mData != nil
        let ch = max(1, Int(firstBuf.mNumberChannels))
        let totalFloats = Int(firstBuf.mDataByteSize) / MemoryLayout<Float>.size
        let frameCount = totalFloats / ch
        guard frameCount > 0 else { return }

        let floats = rawData.assumingMemoryBound(to: Float.self)
        let floatsR = isPlanarStereo ? abl[1].mData!.assumingMemoryBound(to: Float.self) : nil
        let downsampleStep = srcRate >= 44_000 ? 2 : 1
        let outRate = UInt16((srcRate / Double(downsampleStep)).rounded())
        let outFrames = frameCount / downsampleStep
        guard outFrames > 0 else { return }

        var packet = Data(capacity: 8 + outFrames * 2 * 2)
        packet.append(contentsOf: Self.speakerMagic)
        packet.append(UInt8(outRate & 0xFF))
        packet.append(UInt8((outRate >> 8) & 0xFF))
        let outCh: UInt8 = 2
        packet.append(outCh)
        packet.append(0)

        for i in 0..<outFrames {
            let sampleIdx = i * downsampleStep
            let l: Float
            let r: Float
            if let floatsR {
                l = floats[sampleIdx]
                r = floatsR[sampleIdx]
            } else {
                let idx = sampleIdx * ch
                l = floats[idx]
                r = ch > 1 ? floats[idx + 1] : l
            }
            let li = Int16(max(-32767, min(32767, Int((l * 32767.0).rounded()))))
            let ri = Int16(max(-32767, min(32767, Int((r * 32767.0).rounded()))))
            packet.append(UInt8(bitPattern: Int8(truncatingIfNeeded: li & 0xFF)))
            packet.append(UInt8(bitPattern: Int8(truncatingIfNeeded: (li >> 8) & 0xFF)))
            packet.append(UInt8(bitPattern: Int8(truncatingIfNeeded: ri & 0xFF)))
            packet.append(UInt8(bitPattern: Int8(truncatingIfNeeded: (ri >> 8) & 0xFF)))
        }
        for cb in listeners { cb(packet) }
    }
}

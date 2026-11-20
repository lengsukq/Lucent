import Foundation
import LucentSystem

public struct AudioDevicePair: Equatable, Sendable {
    public let input: String?
    public let output: String?

    public init(input: String?, output: String?) {
        self.input = input
        self.output = output
    }
}

public enum AudioDeviceSwitchStatus: String, Sendable {
    case applied, unavailable, restored, partial
}

public struct AudioDeviceSwitchResult: Sendable {
    public let status: AudioDeviceSwitchStatus
    public let actual: AudioDevicePair
    public let missing: [SystemAudioDirection]
}

public final class PluginAudioDeviceRouter: Sendable {
    static let shared = PluginAudioDeviceRouter(hardware: SystemAudioDevices())
    private let hardware: any AudioDeviceHardware
    private let lock = NSLock()

    public init(hardware: any AudioDeviceHardware) {
        self.hardware = hardware
    }

    public func status() -> (devices: [SystemAudioDevice], actual: AudioDevicePair) {
        lock.withLock { (hardware.availableDevices(), current()) }
    }

    public func apply(input: String, output: String) -> AudioDeviceSwitchResult {
        lock.withLock {
            let before = current()
            let devices = hardware.availableDevices()
            var missing: [SystemAudioDirection] = []
            if !devices.contains(where: { $0.uid == input && $0.input }) { missing.append(.input) }
            if !devices.contains(where: { $0.uid == output && $0.output }) { missing.append(.output) }
            guard missing.isEmpty else {
                return AudioDeviceSwitchResult(status: .unavailable, actual: current(), missing: missing)
            }

            let target = AudioDevicePair(input: input, output: output)
            let outputSet = setIfNeeded(output, direction: .output)
            // Bluetooth can change the default microphone while changing the output.
            let afterOutput = outputSet ? waitFor(.output, uid: output) : current()
            let inputSet = afterOutput.output == output && setIfNeeded(input, direction: .input)
            let after = inputSet ? waitForPair(target) : current()
            if inputSet, after == target {
                return AudioDeviceSwitchResult(status: .applied, actual: after, missing: [])
            }

            if let previous = before.output, after.output != previous, after.output == output {
                if setIfNeeded(previous, direction: .output) { _ = waitFor(.output, uid: previous) }
            }
            let afterRestoreOutput = current()
            if let previous = before.input, afterRestoreOutput.input != previous,
               afterRestoreOutput.input == input || afterRestoreOutput.input == afterOutput.input {
                _ = setIfNeeded(previous, direction: .input)
            }
            let actual = waitForPair(before)
            return AudioDeviceSwitchResult(status: actual == before ? .restored : .partial, actual: actual, missing: [])
        }
    }

    public func setSingle(uid: String, direction: SystemAudioDirection) -> AudioDeviceSwitchResult {
        lock.withLock {
            let devices = hardware.availableDevices()
            let available = devices.contains {
                $0.uid == uid && (direction == .input ? $0.input : $0.output)
            }
            guard available else {
                return AudioDeviceSwitchResult(status: .unavailable, actual: current(), missing: [direction])
            }
            let before = current()
            let didSet = setIfNeeded(uid, direction: direction)
            let after = didSet ? waitFor(direction, uid: uid) : current()
            let matched = (direction == .input ? after.input : after.output) == uid
            if didSet && matched {
                return AudioDeviceSwitchResult(status: .applied, actual: after, missing: [])
            }
            if let prev = (direction == .input ? before.input : before.output),
               (direction == .input ? after.input : after.output) != prev {
                _ = setIfNeeded(prev, direction: direction)
            }
            let finalPair = waitForPair(before)
            return AudioDeviceSwitchResult(status: finalPair == before ? .restored : .partial, actual: finalPair, missing: [])
        }
    }

    private func current() -> AudioDevicePair {
        AudioDevicePair(input: hardware.defaultDevice(.input), output: hardware.defaultDevice(.output))
    }

    private func setIfNeeded(_ uid: String, direction: SystemAudioDirection) -> Bool {
        hardware.defaultDevice(direction) == uid || hardware.setDefaultDevice(uid, direction: direction)
    }

    private func waitFor(_ direction: SystemAudioDirection, uid: String) -> AudioDevicePair {
        readUntil { (direction == .input ? $0.input : $0.output) == uid }
    }

    private func waitForPair(_ expected: AudioDevicePair) -> AudioDevicePair {
        readUntil { $0 == expected }
    }

    private func readUntil(_ matches: (AudioDevicePair) -> Bool) -> AudioDevicePair {
        let deadline = ProcessInfo.processInfo.systemUptime + 0.35
        var actual = current()
        while !matches(actual), ProcessInfo.processInfo.systemUptime < deadline {
            Thread.sleep(forTimeInterval: 0.02)
            actual = current()
        }
        return actual
    }
}

extension PluginAudioDeviceRouter {
    func dispatch(_ action: String, params: [String: Any],
                  feedback: (@Sendable (String, String) -> Void)?) -> [String: Any] {
        let capability = PluginCapability.audioDevices
        let data: [String: Any]
        switch action {
        case "list", "status":
            let snapshot = status()
            data = ["actual": Self.payload(snapshot.actual), "devices": snapshot.devices.map {
                ["uid": $0.uid, "name": $0.name, "input": $0.input, "output": $0.output] as [String: Any]
            }]
        case "apply":
            guard let input = params["inputUID"] as? String, !input.isEmpty, input.utf8.count <= 2048,
                  let output = params["outputUID"] as? String, !output.isEmpty, output.utf8.count <= 2048 else {
                return PluginHostBridgeHandlers.errorJSON("invalid_params", "Expected inputUID and outputUID", capability: capability)
            }
            let result = apply(input: input, output: output)
            if result.status == .applied, params["showFeedback"] as? Bool == true, let feedback {
                let devices = status().devices
                let inputName = devices.first(where: { $0.uid == result.actual.input })?.name ?? input
                let outputName = devices.first(where: { $0.uid == result.actual.output })?.name ?? output
                feedback(inputName, outputName)
            }
            data = ["status": result.status.rawValue, "actual": Self.payload(result.actual),
                    "missing": result.missing.map(\.rawValue)]
        case "setDevice":
            guard let dirRaw = params["direction"] as? String,
                  let direction = SystemAudioDirection(rawValue: dirRaw),
                  let uid = params["uid"] as? String, !uid.isEmpty, uid.utf8.count <= 2048 else {
                return PluginHostBridgeHandlers.errorJSON("invalid_params", "Expected direction (input|output) and uid", capability: capability)
            }
            let result = setSingle(uid: uid, direction: direction)
            data = ["status": result.status.rawValue, "actual": Self.payload(result.actual),
                    "missing": result.missing.map(\.rawValue)]
        default:
            return PluginHostBridgeHandlers.errorJSON("invalid_action", "Expected list, status, apply or setDevice", capability: capability)
        }
        return PluginHostBridgeHandlers.okJSON(capability, action, data)
    }

    private static func payload(_ pair: AudioDevicePair) -> [String: String] {
        ["inputUID": pair.input, "outputUID": pair.output].compactMapValues { $0 }
    }
}

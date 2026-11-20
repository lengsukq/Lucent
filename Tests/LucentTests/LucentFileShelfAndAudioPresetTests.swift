import Foundation
import LucentCore
import LucentSystem
import Testing

private func temporaryFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("LucentShelfTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

@Test func shelfSurvivesReopenAndFollowsVerifiedMovedFile() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let original = folder.appendingPathComponent("报价单 final.txt")
    let moved = folder.appendingPathComponent("renamed.txt")
    let payload = Data("original".utf8)
    try payload.write(to: original)
    let item = try FileShelfStore.makeItem(original)
    let store = FileShelfStore(location: folder.appendingPathComponent("state/shelf.json"))
    try store.save([item])
    try FileManager.default.moveItem(at: original, to: moved)
    try Data("replacement".utf8).write(to: original)

    let saved = try #require(store.load().first)
    let availability = FileShelfStore.resolve(saved, mountedVolumes: FileShelfStore.mountedVolumeIDs())
    #expect(availability.url?.resolvingSymlinksInPath() == moved.resolvingSymlinksInPath())
    let updated = try #require(availability.url.flatMap { FileShelfStore.updatedReference(saved, to: $0) })
    #expect(updated.id == item.id)
    #expect(updated.name == "renamed.txt")

    try store.save([])
    #expect(try store.load().isEmpty)
    #expect(try Data(contentsOf: moved) == payload)
    #expect(FileManager.default.fileExists(atPath: original.path))
}

@Test func shelfKeepsMissingEntryAndRejectsSamePathReplacement() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let original = folder.appendingPathComponent("document.txt")
    try Data("original".utf8).write(to: original)
    let item = try FileShelfStore.makeItem(original)
    let store = FileShelfStore(location: folder.appendingPathComponent("shelf.json"))
    try store.save([item])
    try FileManager.default.removeItem(at: original)
    try Data("replacement".utf8).write(to: original)

    let saved = try #require(store.load().first)
    #expect(FileShelfStore.resolve(saved, mountedVolumes: FileShelfStore.mountedVolumeIDs()).url == nil)
    #expect(try store.load() == [item])
}

@Test func shelfDistinguishesCorruptionFromEmptyStore() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = FileShelfStore(location: folder.appendingPathComponent("shelf.json"))
    #expect(try store.load().isEmpty)
    let damaged = Data("{".utf8)
    try damaged.write(to: store.location)
    #expect(throws: DecodingError.self) { try store.load() }
    #expect(try Data(contentsOf: store.location) == damaged)
}

@Test func shelfBridgeRejectsPluginSuppliedPaths() {
    let context = PluginBridgeHostContext(pluginID: "file-shelf", fileShelfAction: { _, _ in true })
    let blocked = PluginHostBridgeHandlers.dispatch(
        capability: .fileShelf, action: "addContextItems", params: ["path": "/tmp/chosen-by-plugin"], hostContext: context
    )
    #expect(blocked["ok"] as? Bool == false)
    let accepted = PluginHostBridgeHandlers.dispatch(
        capability: .fileShelf, action: "addContextItems", params: [:], hostContext: context
    )
    #expect(accepted["ok"] as? Bool == true)
}

private final class MockAudioHardware: AudioDeviceHardware, @unchecked Sendable {
    private let lock = NSLock()
    private var pairs = AudioDevicePair(input: "old-mic", output: "old-speakers")
    private var operations: [String] = []
    private let failing: Set<String>

    init(failing: Set<String> = []) { self.failing = failing }

    func availableDevices() -> [SystemAudioDevice] {
        ["old-mic", "new-mic", "old-speakers", "new-speakers"].map {
            SystemAudioDevice(uid: $0, name: $0, input: $0.hasSuffix("mic"), output: $0.hasSuffix("speakers"))
        }
    }

    func defaultDevice(_ direction: SystemAudioDirection) -> String? {
        lock.withLock { direction == .input ? pairs.input : pairs.output }
    }

    func setDefaultDevice(_ uid: String, direction: SystemAudioDirection) -> Bool {
        lock.withLock {
            operations.append("\(direction.rawValue):\(uid)")
            guard !failing.contains(uid) else { return false }
            if direction == .output {
                pairs = AudioDevicePair(input: "old-mic", output: uid)
            } else {
                pairs = AudioDevicePair(input: uid, output: pairs.output)
            }
            return true
        }
    }

    var history: [String] { lock.withLock { operations } }
}

@Test func audioPresetReadsActualPairAndUsesOutputBeforeInput() {
    let hardware = MockAudioHardware()
    let router = PluginAudioDeviceRouter(hardware: hardware)
    let result = router.apply(input: "new-mic", output: "new-speakers")
    #expect(result.status == .applied)
    #expect(result.actual == AudioDevicePair(input: "new-mic", output: "new-speakers"))
    #expect(hardware.history == ["output:new-speakers", "input:new-mic"])
}

@Test func audioPresetRejectsMissingDeviceBeforeMutation() {
    let hardware = MockAudioHardware()
    let router = PluginAudioDeviceRouter(hardware: hardware)
    let result = router.apply(input: "missing", output: "new-speakers")
    #expect(result.status == .unavailable)
    #expect(result.missing == [.input])
    #expect(hardware.history.isEmpty)
}

@Test func audioPresetReportsRestoredAndPartialRoutes() {
    let initial = AudioDevicePair(input: "old-mic", output: "old-speakers")
    let recoverable = MockAudioHardware(failing: ["new-mic"])
    let restored = PluginAudioDeviceRouter(hardware: recoverable).apply(input: "new-mic", output: "new-speakers")
    #expect(restored.status == .restored)
    #expect(restored.actual == initial)
    #expect(recoverable.history == ["output:new-speakers", "input:new-mic", "output:old-speakers"])

    let unrecoverable = MockAudioHardware(failing: ["new-mic", "old-speakers"])
    let partial = PluginAudioDeviceRouter(hardware: unrecoverable).apply(input: "new-mic", output: "new-speakers")
    #expect(partial.status == .partial)
    #expect(partial.actual == AudioDevicePair(input: "old-mic", output: "new-speakers"))
}

import Foundation
import LucentCore
import LucentFoundation
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

@Test func audioPresetSingleDeviceSwitchAndBridgeDispatch() {
    let hardware = MockAudioHardware()
    let router = PluginAudioDeviceRouter(hardware: hardware)
    let switched = router.setSingle(uid: "new-mic", direction: .input)
    #expect(switched.status == .applied)
    #expect(switched.actual == AudioDevicePair(input: "new-mic", output: "old-speakers"))

    let missing = router.setSingle(uid: "ghost-mic", direction: .input)
    #expect(missing.status == .unavailable)
    #expect(missing.missing == [.input])

    let failHardware = MockAudioHardware(failing: ["new-speakers"])
    let failRouter = PluginAudioDeviceRouter(hardware: failHardware)
    let restored = failRouter.setSingle(uid: "new-speakers", direction: .output)
    #expect(restored.status == .restored)
    #expect(restored.actual == AudioDevicePair(input: "old-mic", output: "old-speakers"))
}

@Test func fileShelfEdgeDockingGeometryAndModeResolution() {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let nearLeft = CGRect(x: 8, y: 300, width: 320, height: 420)
    let nearRight = CGRect(x: 1110, y: 300, width: 320, height: 420)
    let nearTop = CGRect(x: 560, y: 472, width: 320, height: 420)
    let pushedPastLeft = CGRect(x: -160, y: 300, width: 320, height: 420)
    let pushedPastRight = CGRect(x: 1280, y: 300, width: 320, height: 420)
    let pushedPastTop = CGRect(x: 560, y: 550, width: 320, height: 420)
    let middle = CGRect(x: 520, y: 260, width: 320, height: 420)

    #expect(FileShelfEdgeGeometry.detectSnapEdge(frame: nearLeft, visibleFrame: screen) == .left)
    #expect(FileShelfEdgeGeometry.detectSnapEdge(frame: nearRight, visibleFrame: screen) == .right)
    #expect(FileShelfEdgeGeometry.detectSnapEdge(frame: nearTop, visibleFrame: screen) == .top)
    #expect(FileShelfEdgeGeometry.detectSnapEdge(frame: pushedPastLeft, visibleFrame: screen) == .left)
    #expect(FileShelfEdgeGeometry.detectSnapEdge(frame: pushedPastRight, visibleFrame: screen) == .right)
    #expect(FileShelfEdgeGeometry.detectSnapEdge(frame: pushedPastTop, visibleFrame: screen) == .top)
    #expect(FileShelfEdgeGeometry.detectSnapEdge(frame: middle, visibleFrame: screen) == .none)

    let dockedAutoHide = FileShelfWindowSettings(dockEdge: .right, edgeAutoHide: true, pinnedExpanded: false)
    #expect(FileShelfEdgeGeometry.resolveMode(
        settings: dockedAutoHide, isHovered: false, isDraggingIntoShelf: false, isModalOrInputActive: false
    ) == .edgeTucked(.right))
    let dockedTop = FileShelfWindowSettings(dockEdge: .top, edgeAutoHide: true, pinnedExpanded: false)
    #expect(FileShelfEdgeGeometry.resolveMode(
        settings: dockedTop, isHovered: false, isDraggingIntoShelf: false, isModalOrInputActive: false
    ) == .edgeTucked(.top))
    #expect(FileShelfEdgeGeometry.resolveMode(
        settings: dockedAutoHide, isHovered: true, isDraggingIntoShelf: false, isModalOrInputActive: false
    ) == .expanded)
    #expect(FileShelfEdgeGeometry.resolveMode(
        settings: dockedAutoHide, isHovered: false, isDraggingIntoShelf: true, isModalOrInputActive: false
    ) == .expanded)
    #expect(FileShelfEdgeGeometry.resolveMode(
        settings: dockedAutoHide, isHovered: false, isDraggingIntoShelf: false, isModalOrInputActive: false, isManuallyRevealed: true
    ) == .expanded)

    let tuckedRect = FileShelfEdgeGeometry.frame(
        for: .edgeTucked(.right), dockEdge: .right, size: FileShelfEdgeGeometry.tuckedTabSize,
        currentFrame: nearRight, anchorMidY: 450, visibleFrame: screen
    )
    #expect(tuckedRect.maxX == screen.maxX)
    #expect(tuckedRect.width == FileShelfEdgeGeometry.tuckedTabSize.width)

    let tuckedTopRect = FileShelfEdgeGeometry.frame(
        for: .edgeTucked(.top), dockEdge: .top, size: FileShelfEdgeGeometry.tuckedTopTabSize,
        currentFrame: nearTop, anchorMidX: 720, anchorMidY: 682, visibleFrame: screen
    )
    #expect(tuckedTopRect.maxY == screen.maxY)
    #expect(tuckedTopRect.size == FileShelfEdgeGeometry.tuckedTopTabSize)
    #expect(tuckedTopRect.midX == 720)

    let expandedTop = FileShelfEdgeGeometry.frame(
        for: .expanded, dockEdge: .top, size: FileShelfEdgeGeometry.expandedSize,
        currentFrame: tuckedTopRect, anchorMidX: 720, anchorMidY: 682, visibleFrame: screen
    )
    #expect(expandedTop.maxY == screen.maxY - FileShelfEdgeGeometry.dockEdgeInset)
    #expect(expandedTop.midX == 720)

    let expandedLeft = FileShelfEdgeGeometry.frame(
        for: .expanded, dockEdge: .left, size: FileShelfEdgeGeometry.expandedSize,
        currentFrame: nearLeft, anchorMidY: 450, visibleFrame: screen
    )
    #expect(expandedLeft.minX == screen.minX + FileShelfEdgeGeometry.dockEdgeInset)

    let expandedRight = FileShelfEdgeGeometry.frame(
        for: .expanded, dockEdge: .right, size: FileShelfEdgeGeometry.expandedSize,
        currentFrame: nearRight, anchorMidY: 450, visibleFrame: screen
    )
    #expect(expandedRight.maxX == screen.maxX - FileShelfEdgeGeometry.dockEdgeInset)
}

@Test func codeSigningKeychainStabilityRequiresAppleTeamIdentifier() {
    let selfSigned = CodeSigningStatus(
        mode: .customCertificate(commonName: "Lucent Local Signer"),
        bundleIdentifier: "app.lucent.macos", teamIdentifier: nil, isStableForTCC: true,
        badgeTitle: "Local", explanation: ""
    )
    #expect(selfSigned.isStableForTCC == true)
    #expect(selfSigned.isStableForKeychain == false)

    let devID = CodeSigningStatus(
        mode: .developerID(commonName: "Developer ID Application: Test", teamID: "TEAM123456", hardenedRuntime: true),
        bundleIdentifier: "app.lucent.macos", teamIdentifier: "TEAM123456", isStableForTCC: true,
        badgeTitle: "DevID", explanation: ""
    )
    #expect(devID.isStableForKeychain == true)

    let appleDev = CodeSigningStatus(
        mode: .appleDevelopment(commonName: "Apple Development: Test", teamID: "9339HT279W"),
        bundleIdentifier: "app.lucent.macos", teamIdentifier: "9339HT279W", isStableForTCC: true,
        badgeTitle: "AppleDev", explanation: ""
    )
    #expect(appleDev.isStableForKeychain == true)

    let adHoc = CodeSigningStatus(
        mode: .adHoc(hardenedRuntime: false),
        bundleIdentifier: "app.lucent.macos", teamIdentifier: nil, isStableForTCC: false,
        badgeTitle: "AdHoc", explanation: ""
    )
    #expect(adHoc.isStableForKeychain == false)
}

import Darwin
import Foundation
import PluginKit

struct AudioPreset: Codable, Identifiable {
    let id: UUID
    let name: String
    let inputUID: String
    let outputUID: String
    let inputName: String
    let outputName: String

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 60
            && (1...2048).contains(inputUID.utf8.count) && (1...2048).contains(outputUID.utf8.count)
            && inputName.count <= 256 && outputName.count <= 256
    }
}

struct AudioPresetDocument: Codable {
    var presets: [AudioPreset] = []
    var favorite: UUID?
}

struct AudioPresetStore {
    let directory: URL

    init(dataDirectory: String) throws {
        guard !dataDirectory.isEmpty else { throw CocoaError(.fileNoSuchFile) }
        directory = URL(fileURLWithPath: dataDirectory, isDirectory: true)
    }

    func update(_ transform: (inout AudioPresetDocument) throws -> Void = { _ in }) throws -> AudioPresetDocument {
        let lockPath = directory.appendingPathComponent("presets.lock").path
        let fd = open(lockPath, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw CocoaError(.fileWriteUnknown) }
        let location = directory.appendingPathComponent("presets.json")
        var document: AudioPresetDocument
        if FileManager.default.fileExists(atPath: location.path) {
            document = try JSONDecoder().decode(AudioPresetDocument.self, from: Data(contentsOf: location))
        } else {
            document = AudioPresetDocument()
        }
        let before = try PluginOutput.encodeJSON(document)
        try transform(&document)
        let after = try PluginOutput.encodeJSON(document)
        if before != after { try after.write(to: location, options: .atomic) }

        let items = document.presets.map { preset in
            SearchIndexItem(id: preset.id.uuidString, title: preset.name,
                            subtitle: "\(preset.outputName) · \(preset.inputName)", icon: "waveform",
                            tags: ["音频组合", "audio preset"],
                            commandArgs: ["--apply", preset.id.uuidString], includeInGlobalSearch: true)
        }
        let index = directory.appendingPathComponent("search-index.json")
        let data = try PluginOutput.encodeJSON(SearchIndexEnvelope(items: items))
        if (try? Data(contentsOf: index)) != data { try data.write(to: index, options: .atomic) }
        return document
    }
}

import Darwin
import Foundation
import PluginKit

struct WorkspaceSlotItem: Codable, Equatable {
    let bundleID: String
    let appName: String
    let windowTitle: String?
    let windowIndex: Int
    let displayIndex: Int
    let displayID: UInt32?
    let displayName: String?
    let rx: Double
    let ry: Double
    let rw: Double
    let rh: Double

    var isValid: Bool {
        !bundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && bundleID.count <= 256
            && appName.count <= 128
            && rx.isFinite && ry.isFinite && rw.isFinite && rh.isFinite
            && rx >= -0.05 && rx <= 1.0 && ry >= -0.05 && ry <= 1.0
            && rw > 0.05 && rw <= 1.05 && rh > 0.05 && rh <= 1.05
    }

    func toBridgeDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "bundleID": bundleID,
            "appName": appName,
            "windowIndex": windowIndex,
            "displayIndex": displayIndex,
            "rx": rx,
            "ry": ry,
            "rw": rw,
            "rh": rh
        ]
        if let windowTitle, !windowTitle.isEmpty { dict["windowTitle"] = windowTitle }
        if let displayID { dict["displayID"] = displayID }
        return dict
    }
}

struct WindowWorkspacePreset: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let displayCount: Int
    let slots: [WorkspaceSlotItem]
    let updatedAt: String?

    var isValid: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 60
            && !slots.isEmpty && slots.count <= 24
            && slots.allSatisfy(\.isValid)
    }

    var uniqueAppSummary: String {
        var seen = Set<String>()
        let names = slots.compactMap { slot -> String? in
            let clean = slot.appName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, seen.insert(clean).inserted else { return nil }
            return clean
        }
        return names.prefix(4).joined(separator: " · ") + (names.count > 4 ? " +\(names.count - 4)" : "")
    }
}

struct WindowSnapPreferences: Codable, Equatable {
    var gap: Int?
    var launchMissingApps: Bool?
}

struct WindowSnapDocument: Codable {
    var workspaces: [WindowWorkspacePreset] = []
    var favorite: UUID?
    var preferences: WindowSnapPreferences = WindowSnapPreferences()
}

struct WindowWorkspaceStore {
    let directory: URL

    init(dataDirectory: String) throws {
        guard !dataDirectory.isEmpty else { throw CocoaError(.fileNoSuchFile) }
        directory = URL(fileURLWithPath: dataDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func update(
        isEnglish: Bool,
        _ transform: (inout WindowSnapDocument) throws -> Void = { _ in }
    ) throws -> WindowSnapDocument {
        let lockPath = directory.appendingPathComponent("workspaces.lock").path
        let fd = open(lockPath, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw CocoaError(.fileWriteUnknown) }

        let location = directory.appendingPathComponent("workspaces.json")
        var document: WindowSnapDocument
        if FileManager.default.fileExists(atPath: location.path) {
            document = try JSONDecoder().decode(WindowSnapDocument.self, from: Data(contentsOf: location))
        } else {
            document = WindowSnapDocument()
        }

        let before = try PluginOutput.encodeJSON(document)
        try transform(&document)
        let after = try PluginOutput.encodeJSON(document)
        if before != after {
            try after.write(to: location, options: .atomic)
        }

        try syncSearchIndex(for: document, isEnglish: isEnglish)
        try syncStatusFile(for: document, isEnglish: isEnglish)
        return document
    }

    private func syncSearchIndex(for document: WindowSnapDocument, isEnglish: Bool) throws {
        let items = document.workspaces.map { preset -> SearchIndexItem in
            let dispTag = preset.displayCount > 1
                ? (isEnglish ? "\(preset.displayCount) displays" : "\(preset.displayCount) 屏")
                : (isEnglish ? "1 display" : "单屏")
            let countTag = isEnglish ? "\(preset.slots.count) win" : "\(preset.slots.count) 窗口"
            let summary = preset.uniqueAppSummary
            let subtitle = summary.isEmpty ? "\(dispTag) · \(countTag)" : "\(dispTag) · \(summary)"
            return SearchIndexItem(
                id: preset.id.uuidString,
                title: preset.name,
                subtitle: subtitle,
                icon: document.favorite == preset.id ? "star.fill" : "rectangle.3.group.fill",
                badge: dispTag,
                tags: ["工作区", "窗口布局", "分屏", "workspace", "layout"],
                pinned: document.favorite == preset.id,
                commandArgs: ["--apply-workspace", preset.id.uuidString],
                includeInGlobalSearch: true
            )
        }
        let indexURL = directory.appendingPathComponent("search-index.json")
        let data = try PluginOutput.encodeJSON(SearchIndexEnvelope(items: items))
        if (try? Data(contentsOf: indexURL)) != data {
            try data.write(to: indexURL, options: .atomic)
        }
    }

    private func syncStatusFile(for document: WindowSnapDocument, isEnglish: Bool) throws {
        let count = document.workspaces.count
        let summary = count == 0
            ? (isEnglish ? "Ready · Snap presets active" : "就绪 · 支持分屏与多屏工作区")
            : (isEnglish ? "\(count) saved workspace(s)" : "已保存 \(count) 套多屏工作区")
        let status = RuntimeStatusFile(summary: summary, badge: count > 0 ? "\(count)" : nil)
        let statusURL = directory.appendingPathComponent("status.json")
        let data = try PluginOutput.encodeJSON(status)
        if (try? Data(contentsOf: statusURL)) != data {
            try data.write(to: statusURL, options: .atomic)
        }
    }
}

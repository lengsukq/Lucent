import AppKit
import LucentCore
import SwiftUI

struct FileShelfRowState: Identifiable, Equatable {
    let item: FileShelfItem
    let availability: FileShelfAvailability?

    var id: UUID { item.id }
    var url: URL? { availability?.url }
    var name: String { url?.lastPathComponent ?? item.name }
    var parent: String { url?.deletingLastPathComponent().lastPathComponent ?? item.parent }

    var detail: String {
        switch availability {
        case .available: parent
        case .volumeOffline: L10n.pick("磁盘未连接", "Drive disconnected")
        case .missing: L10n.pick("找不到源文件", "Original missing")
        case .noAccess: L10n.pick("无法读取源文件", "Access unavailable")
        case .needsRelink: L10n.pick("需要重新定位", "Locate the original")
        case nil: L10n.pick("正在检查", "Checking")
        }
    }
}

@MainActor
final class FileShelfModel: ObservableObject {
    @Published private(set) var rows: [FileShelfRowState] = []
    @Published var selection: Set<UUID> = []
    @Published var filter = ""
    @Published private(set) var message: String?
    @Published private(set) var loadFailed = false

    private let store: FileShelfStore
    private var refreshTask: Task<Void, Never>?
    private var addTask: Task<Void, Never>?
    private var items: [FileShelfItem] = []
    private var active = true

    init(store: FileShelfStore) {
        self.store = store
        reload()
    }

    var filteredRows: [FileShelfRowState] {
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? rows : rows.filter {
            $0.name.localizedStandardContains(query) || $0.parent.localizedStandardContains(query)
        }
    }

    var selectedRows: [FileShelfRowState] { filteredRows.filter { selection.contains($0.id) } }

    func reload() {
        do {
            items = try store.load()
            loadFailed = false
            message = nil
            publishItems()
            refresh()
        } catch {
            loadFailed = true
            refreshLabels()
        }
    }

    func refreshLabels() {
        message = loadFailed
            ? L10n.pick("记录读取失败，原数据已保留。修复后可重试。",
                        "The shelf couldn’t load. Its saved data is intact. Retry after checking access.")
            : nil
    }

    func refresh() {
        guard active, !loadFailed else { return }
        refreshTask?.cancel()
        let snapshot = items
        refreshTask = Task { [weak self] in
            let work = Task.detached(priority: .utility) {
                let volumes = FileShelfStore.mountedVolumeIDs()
                var result: [FileShelfRowState] = []
                for item in snapshot where !Task.isCancelled {
                    let availability = FileShelfStore.resolve(item, mountedVolumes: volumes)
                    let moved = availability.url.flatMap { FileShelfStore.updatedReference(item, to: $0) }
                    result.append(FileShelfRowState(item: moved ?? item, availability: availability))
                }
                return result
            }
            let next = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
            guard !Task.isCancelled, let self, self.items == snapshot else { return }
            let updated = next.map(\.item)
            if updated != snapshot {
                do {
                    try self.store.save(updated)
                    self.items = updated
                } catch {
                    self.message = L10n.pick("无法保存文件的新位置。", "Couldn’t save the file’s new location.")
                    return
                }
            }
            if self.rows != next { self.rows = next }
        }
    }

    func cancelRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func stop() {
        active = false
        cancelRefresh()
        addTask?.cancel()
        addTask = nil
    }

    func add(_ urls: [URL]) {
        guard active, !loadFailed, !urls.isEmpty else { return }
        message = L10n.pick("正在加入文件…", "Adding files…")
        let previous = addTask
        addTask = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled else { return }
            let work = Task.detached(priority: .userInitiated) {
                urls.compactMap { Task.isCancelled ? nil : try? FileShelfStore.makeItem($0) }
            }
            let candidates = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
            guard !Task.isCancelled, let self, self.active else { return }
            self.addResolved(candidates, rejected: urls.count - candidates.count)
        }
    }

    private func addResolved(_ candidates: [FileShelfItem], rejected: Int) {
        var new: [FileShelfItem] = []
        var chosen: Set<UUID> = []
        for candidate in candidates {
            if let existing = (new + items).first(where: {
                $0.identity.matches(candidate.identity) || ($0.path == candidate.path && $0.bookmark == candidate.bookmark)
            }) {
                chosen.insert(existing.id)
            } else {
                chosen.insert(candidate.id)
                new.append(candidate)
            }
        }
        guard new.isEmpty || persist(new + items) else { return }
        filter = ""
        selection = chosen
        if rejected > 0 {
            let saved = new.count
            message = L10n.pick("已保存 \(saved) 项，\(rejected) 项无法读取。",
                                "\(saved) saved. \(rejected) couldn’t be read.")
        } else if !new.isEmpty {
            message = L10n.pick("已保存 \(new.count) 项", "\(new.count) saved")
        } else if !chosen.isEmpty {
            message = L10n.pick("已在中转站", "Already on your shelf")
        }
    }

    func removeSelected() {
        guard !selection.isEmpty else { return }
        if persist(items.filter { !selection.contains($0.id) }) { selection = [] }
    }

    func clear() {
        if persist([]) { selection = [] }
    }

    func relink(_ item: FileShelfItem, to url: URL) {
        do {
            let replacement = try FileShelfStore.makeItem(url, id: item.id)
            if items.contains(where: { $0.id != item.id && ($0.path == replacement.path || $0.identity.matches(replacement.identity)) }) {
                message = L10n.pick("这个文件已在中转站。", "This file is already on the shelf.")
                return
            }
            _ = persist(items.map { $0.id == item.id ? replacement : $0 })
        } catch {
            message = L10n.pick("无法读取选定的文件。", "The selected file couldn’t be read.")
        }
    }

    func validatedURLs(for rows: [FileShelfRowState]) -> [URL] {
        let volumes = FileShelfStore.mountedVolumeIDs()
        let urls = rows.compactMap { FileShelfStore.resolve($0.item, mountedVolumes: volumes).url }
        if urls.count != rows.count {
            message = L10n.pick("部分文件已不可用，请检查对应条目。", "Some files are unavailable. Check their entries.")
            refresh()
        }
        return urls
    }

    func copySelected() {
        let urls = validatedURLs(for: selectedRows)
        guard !urls.isEmpty else { return }
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.writeObjects(urls as [NSURL]) {
            message = L10n.pick("已复制 \(urls.count) 项", "\(urls.count) copied")
        } else {
            message = L10n.pick("无法写入剪贴板。", "Couldn’t write to the clipboard.")
        }
    }

    private func persist(_ next: [FileShelfItem]) -> Bool {
        guard active, !loadFailed else { return false }
        do {
            try store.save(next)
            items = next
            message = nil
            publishItems()
            refresh()
            return true
        } catch {
            message = L10n.pick("未能保存更改，请检查磁盘和权限后重试。",
                                "Couldn’t save the change. Check storage and permissions and try again.")
            return false
        }
    }

    private func publishItems() {
        let previous = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        rows = items.map { item in
            if let existing = previous[item.id], existing.item == item { return existing }
            return FileShelfRowState(item: item, availability: nil)
        }
    }
}

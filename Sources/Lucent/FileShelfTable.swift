import AppKit
import LucentCore
import QuickLookThumbnailing
import SwiftUI

@MainActor
final class ShelfTableView: NSTableView {
    var copyFiles: (() -> Void)?
    var clearSelectionItems: (() -> Void)?
    var searchFiles: (() -> Void)?
    var previewSelection: (() -> Void)?

    @objc func copy(_ sender: Any?) { copyFiles?() }

    override func keyDown(with event: NSEvent) {
        switch (event.keyCode, event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)) {
        case (8, true): copyFiles?()
        case (3, true): searchFiles?()
        case (49, false): previewSelection?()
        case (51, false), (117, false): clearSelectionItems?()
        default: super.keyDown(with: event)
        }
    }
}

struct FileShelfTable: NSViewRepresentable {
    @ObservedObject var model: FileShelfModel
    let focusSearch: () -> Void
    let preview: (FileShelfRowState) -> Void
    let locate: (FileShelfRowState) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(table: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        scroll.hasVerticalScroller = true
        let table = ShelfTableView()
        table.headerView = nil
        table.backgroundColor = .clear
        table.allowsMultipleSelection = true
        table.rowHeight = 51
        table.intercellSpacing = NSSize(width: 0, height: 3)
        table.style = .inset
        table.usesAlternatingRowBackgroundColors = false
        table.setDraggingSourceOperationMask(.copy, forLocal: true)
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        let column = NSTableColumn(identifier: .init("file"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.setAccessibilityLabel(L10n.pick("暂放文件", "Shelved files"))
        table.copyFiles = { [weak coordinator = context.coordinator] in coordinator?.table.model.copySelected() }
        table.clearSelectionItems = { [weak coordinator = context.coordinator] in coordinator?.table.model.removeSelected() }
        table.searchFiles = { [weak coordinator = context.coordinator] in coordinator?.table.focusSearch() }
        table.previewSelection = { [weak coordinator = context.coordinator] in
            guard let coordinator, let row = coordinator.table.model.selectedRows.first else { return }
            if row.url != nil { coordinator.table.preview(row) } else { coordinator.table.locate(row) }
        }
        scroll.documentView = table
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.table = self
        guard let table = scroll.documentView as? NSTableView else { return }
        context.coordinator.update(table)
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var table: FileShelfTable
        private var rows: [FileShelfRowState] = []
        private var updating = false
        private var lastSelection: Set<UUID> = []

        init(table: FileShelfTable) { self.table = table }

        func update(_ view: NSTableView) {
            updating = true
            defer { updating = false }
            let next = table.model.filteredRows
            if next != rows {
                rows = next
                view.reloadData()
            }
            let selected = IndexSet(rows.indices.filter { table.model.selection.contains(rows[$0].id) })
            if view.selectedRowIndexes != selected { view.selectRowIndexes(selected, byExtendingSelection: false) }
            if lastSelection != table.model.selection, let first = selected.first { view.scrollRowToVisible(first) }
            lastSelection = table.model.selection
        }

        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let view = notification.object as? NSTableView else { return }
            let selection = Set(view.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0].id : nil })
            if table.model.selection != selection { table.model.selection = selection }
        }

        func tableView(_ view: NSTableView, viewFor tableColumn: NSTableColumn?, row index: Int) -> NSView? {
            guard rows.indices.contains(index) else { return nil }
            let row = rows[index]
            let root = ShelfRowContent(row: row) { [weak self] in
                if row.url != nil { self?.table.preview(row) } else { self?.table.locate(row) }
            }
            return NSHostingView(rootView: root)
        }

        func tableView(_ view: NSTableView, pasteboardWriterForRow index: Int) -> (any NSPasteboardWriting)? {
            guard rows.indices.contains(index),
                  let url = table.model.validatedURLs(for: [rows[index]]).first else { return nil }
            return url as NSURL
        }
    }
}

private struct ShelfRowContent: View {
    let row: FileShelfRowState
    let activate: () -> Void
    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 9) {
            Group {
                if let thumbnail { Image(nsImage: thumbnail).resizable().scaledToFit() }
                else { Image(systemName: row.url == nil ? "doc.badge.ellipsis" : "doc.fill")
                    .font(.system(size: 17)).foregroundStyle(row.url == nil ? Color.secondary : Color.teal) }
            }
            .frame(width: 35, height: 34)
            .background(LiquidColors.solidCardSurface, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.name).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                Text(row.detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if row.availability != nil {
                let label = row.url == nil ? L10n.pick("重新定位", "Locate") : L10n.pick("快速查看", "Quick Look")
                Button(action: activate) {
                    Image(systemName: row.url == nil ? "link" : "eye").frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless).help(label).accessibilityLabel(label)
            }
        }
        .padding(.horizontal, 7)
        .help("\(row.name) · \(row.detail)")
        .task(id: row.url) {
            thumbnail = nil
            guard let url = row.url else { return }
            let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
            if values?.isUbiquitousItem == true && values?.ubiquitousItemDownloadingStatus != .current { return }
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 72, height: 64),
                                                       scale: 2, representationTypes: [.icon, .thumbnail])
            defer { QLThumbnailGenerator.shared.cancel(request) }
            if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request),
               !Task.isCancelled { thumbnail = representation.nsImage }
        }
    }
}

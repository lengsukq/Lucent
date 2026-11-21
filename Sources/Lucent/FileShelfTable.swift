import AppKit
import LucentCore
import SwiftUI

@MainActor
final class ShelfTableRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        let inset = bounds.insetBy(dx: 4, dy: 1.5)
        let path = NSBezierPath(roundedRect: inset, xRadius: 11, yRadius: 11)
        NSColor.systemTeal.withAlphaComponent(0.18).setFill()
        path.fill()
        NSColor.systemTeal.withAlphaComponent(0.36).setStroke()
        path.lineWidth = 0.85
        path.stroke()
    }

    override var isEmphasized: Bool {
        get { false }
        set {}
    }
}

@MainActor
final class ShelfTableView: NSTableView {
    var copyFiles: (() -> Void)?
    var clearSelectionItems: (() -> Void)?
    var searchFiles: (() -> Void)?
    var previewSelection: (() -> Void)?
    var contextMenuBuilder: ((Int) -> NSMenu?)?

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

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)
        guard row >= 0 else { return nil }
        if !selectedRowIndexes.contains(row) {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        return contextMenuBuilder?(row)
    }
}

struct FileShelfTable: NSViewRepresentable {
    @ObservedObject var model: FileShelfModel
    let focusSearch: () -> Void
    let preview: (FileShelfRowState) -> Void
    let locate: (FileShelfRowState) -> Void
    let onDraggedOut: (Set<UUID>) -> Void
    let matchingPlugins: ([FileShelfRowState]) -> [(PluginDescriptor, PluginContextPayload)]
    let sendToPlugin: (PluginDescriptor, PluginContextPayload) -> Void

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
        table.rowHeight = 52
        table.intercellSpacing = NSSize(width: 0, height: 4)
        table.style = .plain
        table.usesAlternatingRowBackgroundColors = false
        table.setDraggingSourceOperationMask(.copy, forLocal: true)
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        let column = NSTableColumn(identifier: .init("file"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.handleDoubleClick(_:))
        table.setAccessibilityLabel(L10n.pick("暂放文件", "Shelved files"))
        table.copyFiles = { [weak coordinator = context.coordinator] in coordinator?.table.model.copySelected() }
        table.clearSelectionItems = { [weak coordinator = context.coordinator] in coordinator?.table.model.removeSelected() }
        table.searchFiles = { [weak coordinator = context.coordinator] in coordinator?.table.focusSearch() }
        table.previewSelection = { [weak coordinator = context.coordinator] in
            guard let coordinator, let row = coordinator.table.model.selectedRows.first else { return }
            if row.url != nil { coordinator.table.preview(row) } else { coordinator.table.locate(row) }
        }
        table.contextMenuBuilder = { [weak coordinator = context.coordinator] index in
            coordinator?.buildContextMenu(for: index)
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
        private var activeDraggedIDs: Set<UUID> = []

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

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            ShelfTableRowView()
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let view = notification.object as? NSTableView else { return }
            let selection = Set(view.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0].id : nil })
            if table.model.selection != selection { table.model.selection = selection }
        }

        func tableView(_ view: NSTableView, viewFor tableColumn: NSTableColumn?, row index: Int) -> NSView? {
            guard rows.indices.contains(index) else { return nil }
            let row = rows[index]
            let root = FileShelfRowContent(row: row) { [weak self] in
                if row.url != nil { self?.table.preview(row) } else { self?.table.locate(row) }
            }
            let hosting = NSHostingView(rootView: root)
            hosting.wantsLayer = true
            hosting.layer?.backgroundColor = NSColor.clear.cgColor
            return hosting
        }

        func tableView(_ view: NSTableView, pasteboardWriterForRow index: Int) -> (any NSPasteboardWriting)? {
            guard rows.indices.contains(index),
                  let url = table.model.validatedURLs(for: [rows[index]]).first else { return nil }
            return url as NSURL
        }

        func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession,
                       willBeginAt screenPoint: NSPoint, forRowIndexes rowIndexes: IndexSet) {
            activeDraggedIDs = Set(rowIndexes.compactMap { rows.indices.contains($0) ? rows[$0].id : nil })
        }

        func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession,
                       endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            let dragged = activeDraggedIDs
            activeDraggedIDs = []
            guard !dragged.isEmpty, operation != [] else { return }
            table.onDraggedOut(dragged)
        }

        @objc func handleDoubleClick(_ sender: NSTableView) {
            let idx = sender.clickedRow
            guard rows.indices.contains(idx) else { return }
            let row = rows[idx]
            if row.url != nil { table.model.open([row]) } else { table.locate(row) }
        }

        func buildContextMenu(for index: Int) -> NSMenu? {
            guard rows.indices.contains(index) else { return nil }
            let targets = table.model.selectedRows.isEmpty ? [rows[index]] : table.model.selectedRows
            let primary = rows[index]
            let menu = NSMenu()
            if primary.url != nil {
                menu.addItem(makeItem(L10n.pick("打开", "Open")) { [weak self] in self?.table.model.open(targets) })
                menu.addItem(makeItem(L10n.pick("快速查看", "Quick Look")) { [weak self] in self?.table.preview(primary) })
                menu.addItem(makeItem(L10n.pick("在访达中显示", "Reveal in Finder")) { [weak self] in self?.table.model.revealInFinder(targets) })
                menu.addItem(.separator())
                menu.addItem(makeItem(L10n.pick("复制文件", "Copy Files")) { [weak self] in self?.table.model.copyFiles(for: targets) })
                menu.addItem(makeItem(L10n.pick("复制路径", "Copy Paths")) { [weak self] in self?.table.model.copyPaths(for: targets) })
                let pluginMatches = table.matchingPlugins(targets)
                if !pluginMatches.isEmpty {
                    let sub = NSMenu()
                    for (plugin, ctx) in pluginMatches {
                        sub.addItem(makeItem(plugin.displayName) { [weak self] in self?.table.sendToPlugin(plugin, ctx) })
                    }
                    let parent = NSMenuItem(title: L10n.pick("发送到扩展插件", "Send to Plugin"), action: nil, keyEquivalent: "")
                    parent.submenu = sub
                    menu.addItem(.separator())
                    menu.addItem(parent)
                }
            } else {
                menu.addItem(makeItem(L10n.pick("重新定位源文件…", "Locate Original…")) { [weak self] in self?.table.locate(primary) })
            }
            menu.addItem(.separator())
            menu.addItem(makeItem(L10n.pick("从中转站移出", "Remove from Shelf")) { [weak self] in
                self?.table.model.remove(ids: Set(targets.map(\.id)))
            })
            return menu
        }

        private func makeItem(_ title: String, action: @escaping () -> Void) -> NSMenuItem {
            ShelfContextMenuItem(title: title, callback: action)
        }
    }
}

@MainActor
private final class ShelfContextMenuItem: NSMenuItem {
    private let callback: () -> Void
    init(title: String, callback: @escaping () -> Void) {
        self.callback = callback
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        self.target = self
    }
    @available(*, unavailable) required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func run() { callback() }
}

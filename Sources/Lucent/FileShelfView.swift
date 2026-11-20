import AppKit
import LucentCore
import SwiftUI
import UniformTypeIdentifiers

struct FileShelfView: View {
    @ObservedObject var model: FileShelfModel
    @ObservedObject private var theme = ThemeManager.shared
    @State private var isDropTarget = false
    @FocusState private var searchFocused: Bool

    let compact: Bool
    let toggle: () -> Void
    let close: () -> Void
    let preview: (FileShelfRowState) -> Void
    let locate: (FileShelfRowState) -> Void
    let clear: () -> Void

    private let accent = Color(nsColor: .systemTeal)

    var body: some View {
        Group {
            if compact { capsule } else { expanded }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { LiquidFluidBackdrop() }
        .clipShape(RoundedRectangle(cornerRadius: compact ? 22 : LiquidRadii.windowPanel))
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 22 : LiquidRadii.windowPanel)
                .strokeBorder(isDropTarget ? accent : LiquidColors.inputFieldBorder, lineWidth: isDropTarget ? 2 : 1)
                .allowsHitTesting(false)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget, perform: accept)
        .onExitCommand { if compact { close() } else { toggle() } }
        .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .easeOut(duration: 0.16),
                   value: isDropTarget)
        .id(theme.current)
    }

    private var capsule: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                Image(systemName: "tray.full.fill").foregroundStyle(accent)
                Text(model.rows.count, format: .number).monospacedDigit()
            }
            .font(.system(size: 15, weight: .semibold))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isDropTarget ? accent.opacity(0.20) : .clear)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.pick("展开文件中转站", "Expand File Shelf"))
        .accessibilityValue(Text(model.rows.count, format: .number))
        .contextMenu { Button(L10n.pick("关闭", "Close"), action: close) }
    }

    private var expanded: some View {
        VStack(spacing: 0) {
            header
            if model.loadFailed {
                empty(symbol: "exclamationmark.folder", title: L10n.pick("中转站暂不可读", "Shelf unavailable"),
                      detail: model.message ?? "")
                Button(L10n.pick("重新读取", "Retry"), action: model.reload).padding(.bottom, 16)
            } else {
                if !model.rows.isEmpty { filter }
                content
                if !model.rows.isEmpty || model.message != nil { footer }
            }
        }
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: LiquidRadii.windowPanel)
                    .fill(accent.opacity(0.17))
                    .overlay {
                        Label(L10n.pick("松手放入", "Drop to add"), systemImage: "arrow.down.to.line")
                            .font(.system(size: 14, weight: .semibold)).padding(12)
                            .background(LiquidColors.solidCardSurface, in: Capsule())
                    }
                    .allowsHitTesting(false)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray.full.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 34, height: 34)
                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.pick("文件中转站", "File Shelf")).font(.system(size: 16, weight: .semibold))
                Text(L10n.pick("\(model.rows.count) 项", "\(model.rows.count) items"))
                    .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            control("rectangle.compress.vertical", L10n.pick("收起", "Collapse"), action: toggle)
            control("xmark", L10n.pick("关闭", "Close"), action: close)
        }
        .padding(.horizontal, 15).padding(.vertical, 13)
        .accessibilityElement(children: .contain)
    }

    private var filter: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField(L10n.pick("查找暂放文件", "Find on shelf"), text: $model.filter)
                .textFieldStyle(.plain).focused($searchFocused)
                .onChange(of: model.filter) { _, _ in
                    model.selection.formIntersection(model.filteredRows.map(\.id))
                }
            if !model.filter.isEmpty {
                control("xmark.circle.fill", L10n.pick("清除搜索", "Clear search")) { model.filter = "" }
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10).frame(height: 34)
        .background(LiquidColors.inputFieldSurface, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 14).padding(.bottom, 10)
    }

    @ViewBuilder
    private var content: some View {
        if model.rows.isEmpty {
            empty(symbol: "tray", title: L10n.pick("拖入文件", "Drop files here"),
                  detail: L10n.pick("下次打开还在这里。", "They’ll be here when you return."))
        } else if model.filteredRows.isEmpty {
            empty(symbol: "magnifyingglass", title: L10n.pick("没有匹配的文件", "No matching files"), detail: "")
        } else {
            FileShelfTable(model: model, focusSearch: { searchFocused = true }, preview: preview, locate: locate)
                .padding(.horizontal, 8)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text(model.message ?? (model.selection.isEmpty
                ? L10n.pick("拖入或拖出文件", "Drag files in or out")
                : L10n.pick("已选 \(model.selection.count) 项", "\(model.selection.count) selected")))
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .lineLimit(2)
                .accessibilityAddTraits(.updatesFrequently)
            Spacer(minLength: 4)
            if !model.selectedRows.isEmpty {
                control("minus.circle", L10n.pick("移除所选", "Remove selected"), action: model.removeSelected)
            }
            if !model.rows.isEmpty {
                control("tray.and.arrow.up", L10n.pick("清空中转站", "Clear the shelf"), action: clear)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .overlay(alignment: .top) { Divider().opacity(0.55) }
        .background {
            Button("", action: { searchFocused = true }).keyboardShortcut("f", modifiers: .command)
                .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
        }
    }

    private func empty(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 29, weight: .light))
                .foregroundStyle(accent).padding(.bottom, 3).accessibilityHidden(true)
            Text(title).font(.system(size: 14, weight: .semibold))
            if !detail.isEmpty {
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func control(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium)).frame(width: 28, height: 28)
        }
        .buttonStyle(.borderless).help(label).accessibilityLabel(label)
    }

    private func accept(_ providers: [NSItemProvider]) -> Bool {
        guard !model.loadFailed, !providers.isEmpty else { return false }
        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                if let url = await readURL(from: provider) { urls.append(url) }
            }
            model.add(urls)
        }
        return true
    }

    private func readURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                continuation.resume(returning: data.flatMap { URL(dataRepresentation: $0, relativeTo: nil) })
            }
        }
    }
}

import Combine
import Foundation
import LucentCore
import SwiftUI

@MainActor
final class OverlayActionMenuState: ObservableObject {
    @Published var isPresented: Bool = false
    @Published var selectedIndex: Int = 0
    @Published var candidateTitle: String = ""
    @Published var actions: [OverlayContextAction] = []

    var selectedAction: OverlayContextAction? {
        guard isPresented, selectedIndex >= 0, selectedIndex < actions.count else { return nil }
        return actions[selectedIndex]
    }

    func open(candidateTitle: String, actions: [OverlayContextAction]) {
        guard !actions.isEmpty else { close(); return }
        self.candidateTitle = candidateTitle
        self.actions = actions
        self.selectedIndex = 0
        self.isPresented = true
    }

    func close() {
        guard isPresented || !actions.isEmpty else { return }
        isPresented = false
        selectedIndex = 0
        candidateTitle = ""
        actions = []
    }

    func moveUp() {
        guard isPresented, !actions.isEmpty else { return }
        selectedIndex = selectedIndex > 0 ? selectedIndex - 1 : actions.count - 1
    }

    func moveDown() {
        guard isPresented, !actions.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % actions.count
    }
}

/// Liquid Glass `⌘K` context action drawer anchored above the bottom-right footer bar.
struct OverlayActionDrawerView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var menu: OverlayActionMenuState

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        self._menu = ObservedObject(wrappedValue: viewModel.actionMenu)
    }

    var body: some View {
        if menu.isPresented {
            ZStack(alignment: .bottomTrailing) {
                Color.black.opacity(0.08)
                    .contentShape(Rectangle())
                    .onTapGesture { viewModel.closeOverlayActionMenu() }

                drawerCard
                    .padding(.trailing, 16)
                    .padding(.bottom, 42)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottomTrailing)))
            }
            .animation(LiquidMotion.snappySpring, value: menu.isPresented)
        }
    }

    private var drawerCard: some View {
        let shape = RoundedRectangle(cornerRadius: LiquidRadii.card, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "command")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LiquidColors.accentPrimary)
                Text(menu.candidateTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LiquidColors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 6)
                Text("↑↓ · ↩ · ⎋")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(LiquidColors.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            Divider().opacity(0.24)

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(menu.actions.enumerated()), id: \.element.id) { idx, action in
                            if idx == 0 || menu.actions[idx - 1].section != action.section {
                                sectionHeader(action.section.title, isFirst: idx == 0)
                            }
                            actionRow(action, index: idx, isSelected: idx == menu.selectedIndex)
                                .id(action.id)
                        }
                    }
                    .padding(6)
                }
                .onChange(of: menu.selectedIndex) { _, nextIdx in
                    guard nextIdx >= 0, nextIdx < menu.actions.count else { return }
                    withAnimation(LiquidMotion.snappySpring) {
                        proxy.scrollTo(menu.actions[nextIdx].id, anchor: .center)
                    }
                }
            }
            .frame(maxHeight: 288)
        }
        .frame(width: 320)
        .background {
            ZStack {
                shape.fill(.ultraThickMaterial)
                shape.fill(LiquidColors.cardSurface.opacity(0.65))
            }
        }
        .clipShape(shape)
        .overlay { DoubleSpecularBorder(cornerRadius: LiquidRadii.card) }
        .shadow(color: Color.black.opacity(0.24), radius: 18, x: 0, y: 10)
    }

    private func sectionHeader(_ title: String, isFirst: Bool) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(LiquidColors.textSecondary)
            .padding(.horizontal, 8)
            .padding(.top, isFirst ? 2 : 7)
            .padding(.bottom, 2)
    }

    private func actionRow(_ action: OverlayContextAction, index: Int, isSelected: Bool) -> some View {
        let rowShape = RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous)
        return Button {
            viewModel.executeOverlayAction(action)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: action.symbol)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(action.isDestructive ? Color.red : (isSelected ? LiquidColors.accentPrimary : LiquidColors.textSecondary))
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(action.title)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(action.isDestructive ? Color.red : LiquidColors.textPrimary)
                        .lineLimit(1)
                    if let sub = action.subtitle, !sub.isEmpty {
                        Text(sub)
                            .font(.system(size: 10))
                            .foregroundStyle(LiquidColors.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                if let hint = action.shortcutHint {
                    Text(hint)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(LiquidColors.textSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(LiquidColors.pillSurface, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(isSelected ? LiquidColors.highlightGlow : Color.clear, in: rowShape)
            .contentShape(rowShape)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { menu.selectedIndex = index }
        }
    }
}

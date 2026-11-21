import LucentCore
import LucentFoundation
import SwiftUI

struct CaptureToolbarCustomizationCard: View {
    @ObservedObject var viewModel: AppViewModel

    private var hiddenSet: Set<String> {
        viewModel.generalPreferences.hiddenToolbarItemSet
    }

    private let toolItems: [ScreenshotToolbarItemID] = [
        .toolMove, .toolRect, .toolEllipse, .toolArrow, .toolLine, .toolPen,
        .toolHighlighter, .toolMosaic, .toolBlur, .toolSpotlight, .toolCounter, .toolText
    ]

    private let actionItems: [ScreenshotToolbarItemID] = [
        .actionUndoRedo, .actionClear, .actionLongShot, .actionOCR, .actionCutout, .actionPin, .actionSave
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(
                    L10n.pick("截图工具栏元素按需显隐", "Screenshot Toolbar Visibility"),
                    systemImage: "slider.horizontal.below.rectangle"
                )
                .font(.callout.weight(.semibold))
                Spacer()
                Button(L10n.pick("精简常用", "Compact Preset")) {
                    let compactHidden: [ScreenshotToolbarItemID] = [
                        .toolEllipse, .toolLine, .toolSpotlight, .actionClear, .actionCutout
                    ]
                    viewModel.updateGeneralPreferences {
                        $0.hiddenScreenshotToolbarItems = compactHidden.map(\.rawValue)
                    }
                }
                .buttonStyle(GlassPillButtonStyle(compact: true))

                if !hiddenSet.isEmpty {
                    Button(L10n.pick("全部显示", "Show All")) {
                        viewModel.updateGeneralPreferences { $0.hiddenScreenshotToolbarItems = [] }
                    }
                    .buttonStyle(GlassPillButtonStyle(compact: true))
                }
            }

            Text(L10n.pick(
                "隐藏按钮仅精简底部工具栏视觉宽度，不影响对应快捷键（1–0 / B 切换工具、S 长图、O 识字、P 钉图、⌘S 保存始终有效）。",
                "Hiding buttons only declutters the floating toolbar; keyboard shortcuts (1–0 / B, S, O, P, ⌘S) always remain active."
            ))
            .font(.caption2)
            .foregroundStyle(LiquidColors.textSecondary)

            sectionRow(title: L10n.pick("标注工具：", "Annotation Tools:"), items: toolItems)
            sectionRow(title: L10n.pick("动作按钮：", "Action Buttons:"), items: actionItems)
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
    }

    private func sectionRow(title: String, items: [ScreenshotToolbarItemID]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(LiquidColors.textSecondary)
            FlowWrapLayout(horizontalSpacing: 7, verticalSpacing: 6) {
                ForEach(items) { item in
                    let visible = !hiddenSet.contains(item.rawValue)
                    Button {
                        viewModel.updateGeneralPreferences { prefs in
                            var set = Set(prefs.hiddenScreenshotToolbarItems)
                            if visible { set.insert(item.rawValue) } else { set.remove(item.rawValue) }
                            prefs.hiddenScreenshotToolbarItems = Array(set).sorted()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: visible ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(visible ? Color.accentColor : .secondary)
                            Text(item.label)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(visible ? Color.accentColor.opacity(0.14) : LiquidColors.pillSurface, in: Capsule())
                        .overlay(Capsule().strokeBorder(visible ? Color.accentColor.opacity(0.45) : LiquidColors.pillBorder, lineWidth: 0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

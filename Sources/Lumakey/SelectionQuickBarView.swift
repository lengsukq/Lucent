import AppKit
import LumakeyCore
import SwiftUI

enum SelectionQuickBarPhase: Equatable {
    case actions
    case loading
    case result(title: String, subtitle: String, detail: String, saveArgs: [String]?)
    case error(String)
}

@MainActor
final class SelectionQuickBarState: ObservableObject {
    @Published var selectedText: String = ""
    @Published var pluginName: String = ""
    @Published var phase: SelectionQuickBarPhase = .actions
    @Published var toast: String?
    @Published var savedToVocab = false
}

struct SelectionQuickBarView: View {
    static let horizontalShadowInset: CGFloat = 18
    static let topShadowInset: CGFloat = 14
    static let bottomShadowInset: CGFloat = 22

    @ObservedObject var state: SelectionQuickBarState
    let onTranslate: () -> Void
    let onSpeak: () -> Void
    let onCopySource: () -> Void
    let onCopyResult: (String) -> Void
    let onSaveVocab: ([String]) -> Void
    let onClose: () -> Void

    var body: some View {
        Group {
            switch state.phase {
            case .actions:
                compactBubbleBar
            case .loading:
                loadingCard
            case .result(let title, let subtitle, let detail, let saveArgs):
                resultCard(title: title, subtitle: subtitle, detail: detail, saveArgs: saveArgs)
            case .error(let msg):
                errorCard(msg)
            }
        }
        .padding(.horizontal, Self.horizontalShadowInset)
        .padding(.top, Self.topShadowInset)
        .padding(.bottom, Self.bottomShadowInset)
        .animation(LiquidMotion.snappySpring, value: state.phase)
    }

    private var compactBubbleBar: some View {
        HStack(spacing: 4) {
            Button(action: onTranslate) {
                HStack(spacing: 4) {
                    Image(systemName: "character.book.closed.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text(L10n.pick("翻译", "Translate"))
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(LiquidColors.accentGradient, in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)

            Button(action: onSpeak) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LiquidColors.textPrimary)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(LiquidColors.pillSurface, in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .help(L10n.pick("朗读选中内容", "Speak selection"))

            Button(action: onCopySource) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LiquidColors.textPrimary)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(LiquidColors.pillSurface, in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .help(L10n.pick("复制选中文本", "Copy selection"))

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(LiquidColors.textSecondary)
                    .padding(5)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6).padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous).strokeBorder(LiquidColors.pillBorder, lineWidth: 0.9)
        }
        .background {
            RoundedShapeOuterShadow(
                shape: Capsule(style: .continuous),
                color: .black.opacity(0.20),
                radius: 9,
                yOffset: 4
            )
        }
    }

    private var loadingCard: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(L10n.pick("正在翻译…", "Translating…"))
                .font(.caption.weight(.medium))
                .foregroundStyle(LiquidColors.textPrimary)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 260)
        .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
        .background {
            RoundedShapeOuterShadow(
                shape: RoundedRectangle(cornerRadius: LiquidRadii.card, style: .continuous),
                color: .black.opacity(0.20),
                radius: 9,
                yOffset: 4
            )
        }
    }

    private func resultCard(title: String, subtitle: String, detail: String, saveArgs: [String]?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "character.book.closed.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LiquidColors.accentPrimary)
                Text(state.pluginName.isEmpty ? L10n.pick("划词翻译", "Translation") : state.pluginName)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(LiquidColors.textSecondary)
                    .lineLimit(1)
                Spacer()
                if let toast = state.toast {
                    Text(toast)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.mint)
                }
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(LiquidColors.textSecondary)
                }
                .buttonStyle(.plain)
            }

            Text(state.selectedText)
                .font(.caption2)
                .foregroundStyle(LiquidColors.textSecondary)
                .lineLimit(2)

            Divider().opacity(0.25)

            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(LiquidColors.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(LiquidColors.textSecondary)
                    .lineLimit(2)
            }

            if !detail.isEmpty {
                ScrollView {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(LiquidColors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 92)
            }

            FlowWrapLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                Button {
                    onCopyResult(title)
                } label: {
                    Label(L10n.pick("复制译文", "Copy"), systemImage: "doc.on.doc")
                }
                .buttonStyle(GlassPillButtonStyle(prominent: true, compact: true))

                Button {
                    _ = PluginAudioBridgePlayer.shared.speak(text: state.selectedText)
                } label: {
                    Label(L10n.pick("读原文", "Source"), systemImage: "speaker.wave.2")
                }
                .buttonStyle(GlassPillButtonStyle(compact: true))
                .help(L10n.pick("朗读选中的原文", "Speak source text"))

                Button {
                    _ = PluginAudioBridgePlayer.shared.speak(text: title)
                } label: {
                    Label(L10n.pick("读译文", "Target"), systemImage: "speaker.wave.2.fill")
                }
                .buttonStyle(GlassPillButtonStyle(compact: true))
                .help(L10n.pick("朗读翻译结果", "Speak translation"))

                if let saveArgs, !saveArgs.isEmpty {
                    Button(state.savedToVocab ? L10n.pick("已收藏", "Saved") : L10n.pick("存生词本", "Save")) {
                        onSaveVocab(saveArgs)
                    }
                    .buttonStyle(GlassPillButtonStyle(compact: true))
                    .disabled(state.savedToVocab)
                }
            }
        }
        .padding(12)
        .frame(width: 368)
        .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
        .background {
            RoundedShapeOuterShadow(
                shape: RoundedRectangle(cornerRadius: LiquidRadii.card, style: .continuous),
                color: .black.opacity(0.20),
                radius: 9,
                yOffset: 4
            )
        }
    }

    private func errorCard(_ msg: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(L10n.pick("翻译失败", "Translation Error"), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark") }.buttonStyle(.plain)
            }
            Text(msg).font(.caption2).foregroundStyle(LiquidColors.textSecondary)
        }
        .padding(12).frame(width: 280)
        .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
        .background {
            RoundedShapeOuterShadow(
                shape: RoundedRectangle(cornerRadius: LiquidRadii.card, style: .continuous),
                color: .black.opacity(0.20),
                radius: 9,
                yOffset: 4
            )
        }
    }
}

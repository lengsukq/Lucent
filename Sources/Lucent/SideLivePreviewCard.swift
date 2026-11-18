import AppKit
import LucentCore
import PDFKit
import SwiftUI

struct SideLivePreviewCard: View {
    let previewState: PreviewContentState

    var body: some View {
        Group {
            switch previewState {
            case .empty:
                ContentUnavailableView("选择文件即可实时预览", systemImage: "sidebar.right")
            case .loading(let entry):
                VStack(spacing: 8) {
                    ProgressView()
                    Text("正在加载 \(entry.name)...").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .image(_, let cgImage, let dimensions):
                ZStack(alignment: .bottomTrailing) {
                    Image(nsImage: NSImage(cgImage: cgImage, size: .zero))
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.75)
                        }
                        .shadow(color: .black.opacity(0.11), radius: 6, y: 2)
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                    if let dimensions {
                        Text("\(Int(dimensions.width)) × \(Int(dimensions.height)) px")
                            .font(.caption2.monospacedDigit().weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.58), in: Capsule(style: .continuous))
                            .padding(10)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            case .videoOrAudio(let entry):
                InlinePreviewMediaPlayerBox(url: entry.url)
                    .id(entry.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            case .pdf(let entry):
                InlinePDFRepresentable(url: entry.url)
                    .id(entry.id)
                    .clipShape(RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
            case .markdown(_, let blocks, let truncated):
                VStack(alignment: .leading, spacing: 6) {
                    ScrollView {
                        MarkdownBlocksStackView(blocks: Array(blocks.prefix(24)), baseFontSize: 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if truncated || blocks.count > 24 {
                        Text("点击「独立窗口打开」查看完整排版与大纲")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
            case .text(_, let content, let truncated):
                VStack(alignment: .leading, spacing: 4) {
                    ScrollView {
                        Text(content)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    if truncated {
                        Text("仅显示前 16 KB（安全有界预览）").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(8)
            case .folderOrGeneric(let entry):
                VStack(spacing: 10) {
                    Image(nsImage: IconCache.shared.icon(for: entry))
                        .resizable().frame(width: 56, height: 56)
                    Text(entry.name).font(.caption.weight(.medium)).lineLimit(2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(8)
        .liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)
    }
}

struct InlinePDFRepresentable: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.document = PDFDocument(url: url)
        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document?.documentURL != url {
            nsView.document = PDFDocument(url: url)
        }
    }
}

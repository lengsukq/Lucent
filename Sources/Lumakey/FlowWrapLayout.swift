import SwiftUI

/// 自适应流式水平换行布局：保持每个胶囊/标签的单行固有宽度，超出容器宽度时自动折行，彻底避免窄列竖排挤压。
struct FlowWrapLayout: Layout {
    var horizontalSpacing: CGFloat = 6
    var verticalSpacing: CGFloat = 6

    struct RowElement {
        let index: Int
        let size: CGSize
    }

    struct RowLine {
        var elements: [RowElement] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let lines = computeLines(maxWidth: maxWidth, subviews: subviews)
        guard !lines.isEmpty else { return .zero }
        let totalHeight = lines.reduce(CGFloat(0)) { $0 + $1.height }
            + CGFloat(max(0, lines.count - 1)) * verticalSpacing
        let widest = lines.map(\.width).max() ?? 0
        let resolvedWidth = proposal.width ?? widest
        return CGSize(width: resolvedWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let lines = computeLines(maxWidth: bounds.width, subviews: subviews)
        var cursorY = bounds.minY
        for line in lines {
            var cursorX = bounds.minX
            for element in line.elements {
                let yOffset = cursorY + (line.height - element.size.height) * 0.5
                subviews[element.index].place(
                    at: CGPoint(x: cursorX, y: yOffset),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: element.size.width, height: element.size.height)
                )
                cursorX += element.size.width + horizontalSpacing
            }
            cursorY += line.height + verticalSpacing
        }
    }

    private func computeLines(maxWidth: CGFloat, subviews: Subviews) -> [RowLine] {
        guard !subviews.isEmpty else { return [] }
        let finiteLimit = maxWidth.isFinite && maxWidth > 0 ? maxWidth : .infinity
        var lines: [RowLine] = []
        var current = RowLine()

        for (index, subview) in subviews.enumerated() {
            let natural = subview.sizeThatFits(.unspecified)
            let clampedWidth = finiteLimit.isFinite ? min(natural.width, finiteLimit) : natural.width
            let itemSize = CGSize(width: clampedWidth, height: natural.height)

            if current.elements.isEmpty {
                current.elements.append(RowElement(index: index, size: itemSize))
                current.width = itemSize.width
                current.height = itemSize.height
            } else if current.width + horizontalSpacing + itemSize.width <= finiteLimit {
                current.elements.append(RowElement(index: index, size: itemSize))
                current.width += horizontalSpacing + itemSize.width
                current.height = max(current.height, itemSize.height)
            } else {
                lines.append(current)
                current = RowLine(
                    elements: [RowElement(index: index, size: itemSize)],
                    width: itemSize.width,
                    height: itemSize.height
                )
            }
        }
        if !current.elements.isEmpty {
            lines.append(current)
        }
        return lines
    }
}

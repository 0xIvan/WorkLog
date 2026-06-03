import SwiftUI

struct WrappingHStack: Layout {
    var horizontalSpacing: CGFloat = 12
    var verticalSpacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        let rows = rows(maxWidth: proposal.width, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height }
            + verticalSpacing * CGFloat(max(0, rows.count - 1))

        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        let rows = rows(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX

            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + horizontalSpacing
            }

            y += row.height + verticalSpacing
        }
    }

    private func rows(maxWidth proposedWidth: CGFloat?, subviews: Subviews) -> [WrappingRow] {
        let maxWidth = proposedWidth ?? .infinity
        var rows: [WrappingRow] = []
        var currentItems: [WrappingItem] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let itemWidth = currentItems.isEmpty ? size.width : currentWidth + horizontalSpacing + size.width

            if itemWidth > maxWidth, !currentItems.isEmpty {
                rows.append(WrappingRow(items: currentItems, width: currentWidth, height: currentHeight))
                currentItems = []
                currentWidth = 0
                currentHeight = 0
            }

            currentItems.append(WrappingItem(index: index, size: size))
            currentWidth = currentItems.count == 1 ? size.width : currentWidth + horizontalSpacing + size.width
            currentHeight = max(currentHeight, size.height)
        }

        if !currentItems.isEmpty {
            rows.append(WrappingRow(items: currentItems, width: currentWidth, height: currentHeight))
        }

        return rows
    }
}

private struct WrappingRow {
    var items: [WrappingItem]
    var width: CGFloat
    var height: CGFloat
}

private struct WrappingItem {
    var index: Int
    var size: CGSize
}

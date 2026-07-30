import SwiftUI
import DnotesCore

/// Lays tag chips out left to right, wrapping onto a new row when the width runs out.
///
/// An `HStack` cannot do this — it would either clip or squeeze — and a `VStack` of one
/// chip per line is what made the capture panel outgrow its window. Where the rows break
/// is `ChipFlow`'s decision, in the core where it is tested; this type only places what
/// it is told and reports the height that follows.
struct ChipWrapLayout: Layout {
    var spacing: CGFloat = 6
    var rowSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let maxWidth = proposal.width ?? .infinity
        let rows = ChipFlow.rows(widths: sizes.map(\.width), maxWidth: maxWidth, spacing: spacing)
        let height = rows.enumerated().reduce(CGFloat.zero) { total, row in
            total + (row.offset == 0 ? 0 : rowSpacing)
                + (row.element.map { sizes[$0].height }.max() ?? 0)
        }
        // Full offered width: the panel has a fixed width, and reporting less would let
        // the chips drift into the middle of it.
        return CGSize(width: maxWidth == .infinity ? 0 : maxWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect,
                       proposal: ProposedViewSize,
                       subviews: Subviews,
                       cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let rows = ChipFlow.rows(widths: sizes.map(\.width), maxWidth: bounds.width, spacing: spacing)
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX
            for index in row {
                subviews[index].place(at: CGPoint(x: x, y: y),
                                      anchor: .topLeading,
                                      proposal: ProposedViewSize(sizes[index]))
                x += sizes[index].width + spacing
            }
            y += (row.map { sizes[$0].height }.max() ?? 0) + rowSpacing
        }
    }
}

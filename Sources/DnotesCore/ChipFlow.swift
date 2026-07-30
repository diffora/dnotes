import CoreGraphics

/// Where a row of tag chips breaks.
///
/// Here rather than in the view for the reason `ListKeyCommand` is here: this is the
/// part of the capture panel's chip flow with edge cases worth testing — an off-by-one
/// on the spacing, a tag wider than the panel — and none of them need SwiftUI to
/// reproduce. The `Layout` in `CaptureView` does the placing; this decides the breaks.
public enum ChipFlow {
    /// Groups chip widths into rows that fit `maxWidth`, returning the indices in each
    /// row in order. Every index is placed exactly once.
    ///
    /// A chip wider than `maxWidth` is given a row of its own rather than dropped: a
    /// suggestion that cannot be seen cannot be chosen, and a tag long enough to
    /// overflow the panel is still a tag somebody typed.
    public static func rows(widths: [CGFloat], maxWidth: CGFloat, spacing: CGFloat) -> [[Int]] {
        var rows: [[Int]] = []
        var row: [Int] = []
        var used: CGFloat = 0

        for (index, width) in widths.enumerated() {
            // Spacing is charged between chips only, so an empty row starts at zero.
            let needed = row.isEmpty ? width : used + spacing + width
            if !row.isEmpty, needed > maxWidth {
                rows.append(row)
                row = [index]
                used = width
            } else {
                row.append(index)
                used = needed
            }
        }

        if !row.isEmpty { rows.append(row) }
        return rows
    }
}

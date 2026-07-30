import CoreGraphics
import Testing
@testable import DnotesCore

@Test func nothingToLayOutIsNoRows() {
    #expect(ChipFlow.rows(widths: [], maxWidth: 100, spacing: 6).isEmpty)
}

@Test func chipsThatFitStayOnOneRow() {
    let rows = ChipFlow.rows(widths: [30, 30, 30], maxWidth: 102, spacing: 6)
    #expect(rows == [[0, 1, 2]])
}

/// Spacing sits *between* chips, so three 30pt chips need 102pt, not 108.
@Test func spacingIsNotChargedBeforeTheFirstChip() {
    #expect(ChipFlow.rows(widths: [30, 30, 30], maxWidth: 101, spacing: 6) == [[0, 1], [2]])
    #expect(ChipFlow.rows(widths: [30, 30, 30], maxWidth: 102, spacing: 6) == [[0, 1, 2]])
}

@Test func chipsWrapOntoTheNextRowWhenTheRowIsFull() {
    let rows = ChipFlow.rows(widths: [40, 40, 40, 40], maxWidth: 86, spacing: 6)
    #expect(rows == [[0, 1], [2, 3]])
}

/// A tag long enough to be wider than the panel must still be laid out — dropping it
/// would hide a real suggestion, and looping forever would hang the capture field.
@Test func aChipWiderThanTheRowGetsARowOfItsOwn() {
    let rows = ChipFlow.rows(widths: [30, 500, 30], maxWidth: 100, spacing: 6)
    #expect(rows == [[0], [1], [2]])
}

@Test func everyChipIsPlacedExactlyOnce() {
    let widths: [CGFloat] = [20, 45, 33, 90, 12, 61, 28]
    let placed = ChipFlow.rows(widths: widths, maxWidth: 120, spacing: 6).flatMap { $0 }
    #expect(placed == Array(widths.indices))
}

import Foundation

/// Where an entry sits in the markdown files. This is the backend's private
/// vocabulary: §4.1 identity ("file + line", recomputed on every read) plus the two
/// facts §4.4 needs to find the line again after the file changed underneath us.
/// It never crosses the storage seam.
struct EntryLocation: Hashable, Sendable {
    let month: MonthID
    let lineIndex: Int
    let rawLine: String
    /// N-th identical raw line within its day, 0-based.
    let duplicateOrdinal: Int
}

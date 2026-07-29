import Foundation

public struct MonthFile: Hashable, Sendable {
    public let month: MonthID
    public let url: URL
}

public enum FileDiscovery {
    /// Notes files in `folder`, ascending by month. Subdirectories are not traversed
    /// and only the exact `YYYY-MM.md` pattern counts (§4) — that pattern is what
    /// keeps cloud conflict copies from showing the same month twice.
    public static func monthFiles(in folder: URL) throws -> [MonthFile] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles]
        )

        return contents
            .compactMap { url -> MonthFile? in
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
                guard values?.isDirectory != true else { return nil }
                guard let month = MonthID(fileName: url.lastPathComponent) else { return nil }
                return MonthFile(month: month, url: url)
            }
            .sorted { $0.month < $1.month }
    }
}

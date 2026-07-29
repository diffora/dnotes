import Foundation

public enum AtomicWriter {
    /// Writes through a temporary file next to the target and then replaces it, so a
    /// crash mid-write cannot leave a half-written notes file (§4.4). The temporary
    /// name is dot-prefixed, so it is hidden and cannot match `YYYY-MM.md`.
    @discardableResult
    public static func write(_ text: String, to url: URL) throws -> Date {
        let manager = FileManager.default
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")

        try Data(text.utf8).write(to: temporary)

        do {
            if manager.fileExists(atPath: url.path) {
                _ = try manager.replaceItemAt(url, withItemAt: temporary)
            } else {
                try manager.moveItem(at: temporary, to: url)
            }
        } catch {
            try? manager.removeItem(at: temporary)
            throw error
        }

        let attributes = try manager.attributesOfItem(atPath: url.path)
        return attributes[.modificationDate] as? Date ?? Date()
    }
}

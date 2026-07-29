import Foundation

/// A throwaway directory. Every backend test gets its own, so tests never see each
/// other's files and never see the owner's notes.
final class TempFolder: @unchecked Sendable {
    let url: URL

    init() {
        url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("dnotes-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        try? FileManager.default.removeItem(at: url)
    }

    func path(_ name: String) -> URL { url.appendingPathComponent(name) }

    @discardableResult
    func write(_ name: String, _ contents: String, modified: Date? = nil) -> URL {
        let file = path(name)
        try! Data(contents.utf8).write(to: file)
        if let modified {
            try! FileManager.default.setAttributes([.modificationDate: modified],
                                                   ofItemAtPath: file.path)
        }
        return file
    }

    func read(_ name: String) -> String {
        String(decoding: try! Data(contentsOf: path(name)), as: UTF8.self)
    }

    func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: path(name).path)
    }

    func makeDirectory(_ name: String) {
        try! FileManager.default.createDirectory(at: path(name), withIntermediateDirectories: true)
    }

    func modificationDate(_ name: String) -> Date {
        let attributes = try! FileManager.default.attributesOfItem(atPath: path(name).path)
        return attributes[.modificationDate] as! Date
    }

    func setReadOnly(_ readOnly: Bool) {
        try! FileManager.default.setAttributes([.posixPermissions: readOnly ? 0o500 : 0o755],
                                               ofItemAtPath: url.path)
    }
}

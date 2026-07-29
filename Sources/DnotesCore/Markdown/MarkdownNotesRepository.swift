import Foundation

/// The §4 backend: one flat folder, one markdown file per month.
///
/// `@MainActor` with synchronous IO behind an async protocol. At the volumes §5.2
/// assumes, parsing a folder is microseconds, and staying on one actor keeps the
/// concurrency story trivial. A backend that genuinely needs to suspend already has
/// the `async` it needs.
@MainActor
public final class MarkdownNotesRepository: NotesRepository {
    public private(set) var folder: URL
    public private(set) var entries: [NoteEntry] = []
    public var onExternalChange: (@MainActor () -> Void)?

    let calendar: Calendar
    let now: () -> Date

    /// The seam's opaque ids resolved back to file positions. Rebuilt on every load,
    /// exactly as §4.1 prescribes.
    private var locations: [EntryID: EntryLocation] = [:]

    /// The mtime each month file had when we last read it. This doubles as the
    /// self-write filter for watching: our own writes update it, so they never look
    /// like an external change.
    private var readMTimes: [MonthID: Date] = [:]

    private var isObserving = false
    private var watcher: FolderWatcher?

    public init(folder: URL, calendar: Calendar = .current, now: @escaping () -> Date = { Date() }) {
        self.folder = folder
        self.calendar = calendar
        self.now = now
    }

    public var isAvailable: Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    /// Folder-specific, deliberately not on the protocol.
    public func setFolder(_ url: URL) async throws {
        let wasObserving = isObserving
        stopObserving()
        folder = url
        readMTimes.removeAll()
        locations.removeAll()
        entries = []
        try await load()
        if wasObserving { startObserving() }
    }

    // MARK: - reading

    public func load() async throws {
        try loadNow()
    }

    /// The synchronous core, so the write path can reload without awaiting itself.
    func loadNow() throws {
        guard isAvailable else { throw NotesError.storeUnavailable(folder.path) }
        try importLegacyNotesIfNeeded()

        var loaded: [NoteEntry] = []
        var found: [EntryID: EntryLocation] = [:]
        var mtimes: [MonthID: Date] = [:]

        for file in try FileDiscovery.monthFiles(in: folder) {
            let (text, mtime) = try read(file.url)
            mtimes[file.month] = mtime
            for scanned in Self.scan(Document.parse(text), month: file.month) {
                found[scanned.entry.id] = scanned.location
                loaded.append(scanned.entry)
            }
        }

        readMTimes = mtimes
        locations = found
        entries = loaded
    }

    static func scan(_ document: Document, month: MonthID)
        -> [(entry: NoteEntry, location: EntryLocation)] {
        var result: [(entry: NoteEntry, location: EntryLocation)] = []
        var day: CalendarDay?
        var seenInDay: [String: Int] = [:]

        for (index, line) in document.lines.enumerated() {
            switch line.kind {
            case .dayHeading(let heading):
                day = heading
                seenInDay.removeAll()          // ordinals are scoped to one day (§4.4)
            case .entry(let parsed):
                guard let day else { continue }  // no heading above it, so no date
                let ordinal = seenInDay[line.raw, default: 0]
                seenInDay[line.raw] = ordinal + 1
                let id = EntryID("\(month)/\(index)")
                result.append((
                    entry: NoteEntry(id: id, day: day, text: parsed.text,
                                     isDone: parsed.isDone, tags: parsed.tags),
                    location: EntryLocation(month: month, lineIndex: index,
                                            rawLine: line.raw, duplicateOrdinal: ordinal)
                ))
            case .other:
                break
            }
        }

        return result
    }

    /// Visible to the backend's own tests only — nothing above the seam may call it.
    func location(of id: EntryID) -> EntryLocation? { locations[id] }

    /// Notes are UTF-8. Invalid bytes are replaced rather than throwing: refusing to
    /// open the file would hide more text than a replacement character does.
    func read(_ url: URL) throws -> (text: String, mtime: Date) {
        let data = try Data(contentsOf: url)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (String(decoding: data, as: UTF8.self),
                attributes[.modificationDate] as? Date ?? .distantPast)
    }

    func modificationDate(of url: URL) throws -> Date {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.modificationDate] as? Date ?? .distantPast
    }

    /// Runs at most once per folder: after it, month files exist and the guard below
    /// is false forever. `notes.md` is left exactly where it is — an app that
    /// promises never to lose text does not open by deleting someone's file (§4).
    func importLegacyNotesIfNeeded() throws {
        guard try FileDiscovery.monthFiles(in: folder).isEmpty else { return }
        let legacy = folder.appendingPathComponent(NotesImporter.legacyFileName)
        guard FileManager.default.fileExists(atPath: legacy.path) else { return }

        let text = try read(legacy).text
        for (month, contents) in NotesImporter.split(text) {
            do {
                try AtomicWriter.write(contents, to: folder.appendingPathComponent(month.fileName))
            } catch {
                throw NotesError.writeFailed(error.localizedDescription)
            }
        }
    }

    // MARK: - writing

    /// Appends to the given day, creating the day and the month file as needed.
    /// The file is re-read immediately before the write, so a change made elsewhere
    /// since the last load is picked up rather than overwritten.
    @discardableResult
    public func append(text: String, on day: CalendarDay) async throws -> NoteEntry {
        guard isAvailable else { throw NotesError.storeUnavailable(folder.path) }

        let url = folder.appendingPathComponent(day.monthID.fileName)
        var document = Document(lines: [])
        if FileManager.default.fileExists(atPath: url.path) {
            document = Document.parse(try read(url).text)
        }

        let index = document.appendEntry(text: text, to: day)
        readMTimes[day.monthID] = try writeAtomically(document, to: url)
        try loadNow()

        let id = EntryID("\(day.monthID)/\(index)")
        guard let created = entries.first(where: { $0.id == id }) else {
            throw NotesError.entryVanished
        }
        return created
    }

    public func setDone(_ done: Bool, for entry: NoteEntry) async throws {
        try mutate(entry) { document, index in document.setDone(done, atLine: index) }
    }

    public func edit(_ entry: NoteEntry, to newText: String) async throws {
        try mutate(entry) { document, index in document.replaceText(atLine: index, with: newText) }
    }

    public func delete(_ entry: NoteEntry) async throws {
        try mutate(entry) { document, index in document.removeLine(at: index) }
    }

    private func mutate(_ entry: NoteEntry, _ apply: (inout Document, Int) -> Void) throws {
        guard isAvailable else { throw NotesError.storeUnavailable(folder.path) }
        guard let location = location(of: entry.id) else { throw NotesError.entryVanished }

        let url = folder.appendingPathComponent(location.month.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw NotesError.entryVanished
        }

        let (text, mtime) = try read(url)
        var document = Document.parse(text)

        // The file changed since we read it: find the line by its text, not its number.
        let index = mtime == readMTimes[location.month]
            ? location.lineIndex
            : try locate(location, on: entry.day, in: document)

        guard index < document.lines.count, document.lines[index].raw == location.rawLine else {
            throw NotesError.entryVanished
        }

        apply(&document, index)
        readMTimes[location.month] = try writeAtomically(document, to: url)
        try loadNow()
    }

    /// §4.4: search only within the entry's own day, pick the `duplicateOrdinal`-th
    /// identical line, and cancel rather than guess if it is not there any more.
    private func locate(_ location: EntryLocation,
                        on day: CalendarDay,
                        in document: Document) throws -> Int {
        guard let headingIndex = document.dayHeadingIndex(for: day) else {
            throw NotesError.entryVanished
        }
        let matches = document.dayLineRange(headingIndex: headingIndex)
            .filter { document.lines[$0].raw == location.rawLine }

        if matches.isEmpty { throw NotesError.entryVanished }
        guard location.duplicateOrdinal < matches.count else { throw NotesError.ambiguousMatch }
        return matches[location.duplicateOrdinal]
    }

    private func writeAtomically(_ document: Document, to url: URL) throws -> Date {
        do {
            return try AtomicWriter.write(document.serialize(), to: url)
        } catch {
            throw NotesError.writeFailed(error.localizedDescription)
        }
    }

    // MARK: - watching

    public func startObserving() {
        guard watcher == nil else { return }
        isObserving = true
        let created = FolderWatcher(folder: folder, queue: .main) { [weak self] in
            MainActor.assumeIsolated { self?.folderChanged() }
        }
        created.start()
        watcher = created
    }

    public func stopObserving() {
        isObserving = false
        watcher?.stop()
        watcher = nil
    }

    private func folderChanged() {
        guard isAvailable, hasExternalChange() else { return }
        try? loadNow()
        onExternalChange?()
    }

    /// Our own writes have already updated `readMTimes`, so they look like no change
    /// at all — which is exactly the "do not let our write come back at us" rule of
    /// §5.1, with no extra state to get out of sync.
    private func hasExternalChange() -> Bool {
        guard let files = try? FileDiscovery.monthFiles(in: folder) else { return true }
        if files.count != readMTimes.count { return true }
        for file in files {
            guard let known = readMTimes[file.month],
                  let current = try? modificationDate(of: file.url),
                  current == known
            else { return true }
        }
        return false
    }
}

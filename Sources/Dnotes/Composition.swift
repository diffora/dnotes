import AppKit
import DnotesCore

/// The only place in the app that names a concrete backend. Everything else takes
/// `any NotesRepository`, so replacing markdown files with something else is an edit
/// to this file.
@MainActor
final class Composition {
    let settings: SettingsStore
    let pending: PendingQueue
    let repository: MarkdownNotesRepository
    let model: NotesModel

    init(defaults: UserDefaults = .standard) {
        settings = SettingsStore(defaults: defaults)
        pending = PendingQueue(defaults: defaults)
        repository = MarkdownNotesRepository(folder: settings.folderURL)
        model = NotesModel(repository: repository, pending: pending)
        model.completionFilter = settings.completionFilter
    }

    func start() async {
        await model.load()
        // NotesModel installs its own handler in init; replacing it with one that
        // reloads covers both refreshing and draining the queue when the store
        // comes back, since load() does the drain.
        repository.onExternalChange = { [weak self] in
            Task { await self?.model.load() }
        }
        repository.startObserving()
    }

    func changeFolder(to url: URL) async {
        settings.folderURL = url
        try? await repository.setFolder(url)
        await model.load()
    }
}

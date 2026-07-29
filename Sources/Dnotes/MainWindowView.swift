import AppKit
import SwiftUI
import DnotesCore

struct MainWindowView: View {
    let model: NotesModel
    let list: NotesListModel
    let settings: SettingsStore
    let onChooseFolder: () -> Void

    private enum Focus: Hashable { case search }

    @FocusState private var focus: Focus?

    var body: some View {
        VStack(spacing: 0) {
            FolderBannerView(
                model: model,
                onChooseFolder: onChooseFolder,
                onRetry: { Task { await model.drainPending() } }
            )
            header
            Divider()
            TagChipsView(model: model)
            Divider()
            listBody
            shortcuts
        }
        .frame(minWidth: 520, minHeight: 380)
        .background(VisualEffectBackground())
        .task { await model.load() }
    }

    // MARK: - pieces

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search", text: Binding(get: { model.searchText },
                                              set: { model.searchText = $0 }))
                .textFieldStyle(.plain)
                .focused($focus, equals: .search)
                .onSubmit { focus = nil }
                .onExitCommand { clearFilters() }

            // A menu rather than a segmented control: three states need words to be
            // unambiguous, and words do not fit across a narrow window.
            Picker("", selection: Binding(get: { model.completionFilter },
                                          set: { filter in
                                              model.completionFilter = filter
                                              // Remembered across launches, like the
                                              // folder and the hotkeys.
                                              settings.completionFilter = filter
                                          })) {
                ForEach(CompletionFilter.allCases, id: \.self) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .help("Which completed entries the list shows")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// The keys are handled by `ListKeyMonitor`, not here: an event monitor sees them
    /// before the scroll view can treat the arrows as scrolling.
    private var listBody: some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1, pinnedViews: [.sectionHeaders]) {
                    ForEach(days, id: \.self) { day in
                        Section {
                            ForEach(entries(on: day)) { entry in
                                row(for: entry)
                            }
                        } header: {
                            Text(dayTitle(day))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.thinMaterial)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .scrollContentBackground(.hidden)
            .overlay { if model.visibleEntries.isEmpty { emptyState } }
            .onExitCommand { clearFilters() }
            .onChange(of: list.selection) { _, new in
                if let new { withAnimation { scroller.scrollTo(new, anchor: .center) } }
            }
        }
    }

    private func row(for entry: NoteEntry) -> some View {
        EntryRowView(
            entry: entry,
            issueURLTemplate: settings.issueURLTemplate,
            isSelected: list.selection == entry.id,
            isEditing: list.editing == entry.id,
            editingText: Binding(get: { list.editingText },
                                 set: { list.editingText = $0 }),
            onSelect: {
                list.selection = entry.id
                focus = nil
            },
            onToggle: {
                list.selection = entry.id
                Task { await list.toggleSelected() }
            },
            onBeginEdit: {
                list.selection = entry.id
                list.beginEditing()
            },
            onCommitEdit: { text in
                focus = nil
                Task { await list.commitEdit(text) }
            },
            onCancelEdit: {
                focus = nil
                list.cancelEditing()
            },
            onDelete: {
                list.selection = entry.id
                Task { await list.deleteSelected() }
            }
        )
        .id(entry.id)
    }

    /// An empty list has to say why it is empty and what to do about it. Without this,
    /// a first launch on an empty folder shows nothing at all and gives no hint that
    /// ⌥Space is the way in.
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: isFiltered ? "line.3.horizontal.decrease.circle" : "square.and.pencil")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(isFiltered ? "Nothing matches" : "No notes yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(isFiltered
                 ? "Clear the search and the filter with esc."
                 : "Press \(settings.captureHotKey.displayString) anywhere to capture a line.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }

    /// Empty because of a filter is a different problem from empty because there is
    /// nothing — and the completion filter counts, since "open only" can empty a list
    /// that is full of finished work.
    private var isFiltered: Bool {
        !model.searchText.isEmpty
            || model.selectedTag != nil
            || (!model.entries.isEmpty && model.completionFilter == .openOnly)
    }

    /// `⌘F` has no menu item to live in, so it lives here as a zero-sized button.
    private var shortcuts: some View {
        Button("") { focus = .search }
            .keyboardShortcut("f", modifiers: .command)
            .frame(width: 0, height: 0)
            .opacity(0)
    }

    // MARK: - grouping

    private var days: [CalendarDay] {
        var seen: Set<CalendarDay> = []
        return model.visibleEntries.compactMap { seen.insert($0.day).inserted ? $0.day : nil }
    }

    private func entries(on day: CalendarDay) -> [NoteEntry] {
        model.visibleEntries.filter { $0.day == day }
    }

    private func dayTitle(_ day: CalendarDay) -> String {
        day == model.today ? "Today — \(day)" : day.description
    }

    private func clearFilters() {
        // esc clears search and filter, in that order of usefulness (§7).
        model.searchText = ""
        model.selectedTag = nil
        focus = nil
    }
}

/// `NSVisualEffectView` as the background (§7); SwiftUI has no direct equivalent
/// that also picks up the window's active state.
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

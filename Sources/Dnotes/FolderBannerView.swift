import SwiftUI
import DnotesCore

/// Shown when the store cannot be reached, or when confirmed entries are still
/// waiting to be written. The app stays usable — capture still works and queues —
/// so this is a banner, not a modal (§8).
struct FolderBannerView: View {
    let model: NotesModel
    let onChooseFolder: () -> Void
    let onRetry: () -> Void

    var body: some View {
        if !model.storeAvailable {
            banner(icon: "exclamationmark.triangle.fill",
                   tint: .orange,
                   message: model.lastError ?? "The notes folder is not available.",
                   actionTitle: "Choose Folder…",
                   action: onChooseFolder)
        } else if model.pendingCount > 0 {
            banner(icon: "clock.arrow.circlepath",
                   tint: .yellow,
                   message: "\(model.pendingCount) unsaved "
                       + (model.pendingCount == 1 ? "entry" : "entries"),
                   actionTitle: "Retry",
                   action: onRetry)
        } else if let error = model.lastError {
            banner(icon: "info.circle", tint: .secondary, message: error,
                   actionTitle: nil, action: {})
        }
    }

    private func banner(icon: String, tint: Color, message: String,
                        actionTitle: String?, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(message).font(.callout).lineLimit(2)
            Spacer(minLength: 8)
            if let actionTitle {
                Button(actionTitle, action: action).controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.quaternary)
    }
}

import AppKit
import ServiceManagement

/// Starting dnotes when the Mac starts.
///
/// **There is no stored preference behind this.** macOS already keeps the answer, in
/// System Settings → General → Login Items, and the user can change it there without
/// telling us. A copy in `UserDefaults` would be a second answer free to disagree with
/// the first, and the checkbox would end up lying about the state of the machine. So
/// `status` is read every time it is shown.
///
/// Ad-hoc signing is enough for this: measured on this machine with a bundle signed
/// `-` and no Team ID, registration goes `notFound` → `enabled` and back. No
/// `LaunchAgent` fallback is needed (§11 still applies to *distribution* signing).
@MainActor
enum LoginItem {
    enum State: Equatable {
        case on
        case off
        /// Registered, but switched off by hand in System Settings. The app cannot
        /// override that — only the user can, and only there.
        case needsApproval
    }

    static var state: State {
        switch SMAppService.mainApp.status {
        case .enabled: return .on
        case .requiresApproval: return .needsApproval
        // `.notFound` is the state of a bundle the system has no record of, which for
        // the main app means the same thing as never registered.
        case .notRegistered, .notFound: return .off
        @unknown default: return .off
        }
    }

    /// Registration follows the running bundle, so turning this on from a copy in the
    /// repository is what will start at login — not the one in `/Applications`. The
    /// caption in Settings says so, because nothing about the state of the checkbox can.
    static func set(_ on: Bool) throws {
        if on {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// The one place the user can undo `.needsApproval`.
    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
        else { return }
        NSWorkspace.shared.open(url)
    }
}

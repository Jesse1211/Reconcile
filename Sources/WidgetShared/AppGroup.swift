import Foundation

/// The App Group shared between the `Reconcile` app and its WidgetKit extension
/// (ADR-042). Both targets carry this App Group entitlement so the read-only
/// widget snapshot round-trips through a single shared container.
///
/// The app is the SINGLE WRITER of the snapshot; the widget extension only READS
/// it (ADR-042). This identifier is the one place the group name is spelled, so
/// the writer (app-side) and the loader (extension-side) cannot diverge.
public enum AppGroup {
    /// The App Group container identifier (matches the entitlement in `project.yml`).
    public static let identifier = "group.com.reconcile.shared"

    /// The shared `UserDefaults` suite backing the widget snapshot, or `nil` if the
    /// App Group is unavailable (e.g. entitlement missing in a bare test host).
    ///
    /// Both the app-side ``WidgetSnapshotWriter`` and the extension-side
    /// ``WidgetSnapshotLoader`` resolve their store through this single accessor so
    /// there is exactly one container in play (ADR-042).
    public static func sharedDefaults() -> UserDefaults? {
        UserDefaults(suiteName: identifier)
    }
}

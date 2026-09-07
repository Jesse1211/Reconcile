import SwiftUI

/// SwiftUI `Environment` plumbing for the app-side ``WidgetSnapshotWriter``
/// (T12/ADR-042).
///
/// The app injects the real writer at the root (``ReconcileApp``); later UI tasks
/// (T7 quote area, T9 timer) read it from the environment to construct their `T5` /
/// `T6` services with widget writes enabled. Defaults to `nil` so previews and any
/// non-widget context simply perform no widget write (additive/backward-compatible).
///
/// This lives in the APP target only — the widget extension never sees or sets it,
/// preserving the read-only widget contract (ADR-042).
private struct WidgetSnapshotWriterKey: EnvironmentKey {
    static let defaultValue: WidgetSnapshotWriter? = nil
}

public extension EnvironmentValues {
    /// The app-side widget snapshot writer (T12/ADR-042), or `nil` when widget
    /// writes are disabled (previews / tests).
    var widgetSnapshotWriter: WidgetSnapshotWriter? {
        get { self[WidgetSnapshotWriterKey.self] }
        set { self[WidgetSnapshotWriterKey.self] = newValue }
    }
}

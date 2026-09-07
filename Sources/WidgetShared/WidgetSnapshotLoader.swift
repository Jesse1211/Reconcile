import Foundation

/// The extension-side READ-ONLY accessor for the widget snapshot (ADR-042 / ADR-043).
///
/// The `TimelineProvider` reads through this. It performs NO business logic and NO
/// network (ADR-043) — it only loads the last snapshot the app wrote and hands back
/// a placeholder when none exists yet (ADR-045). It exposes NO write path: the
/// widget is read-only (ADR-042) — controlling the timer from the widget is deferred
/// (OQ-08).
public struct WidgetSnapshotLoader {
    private let store: WidgetSnapshotStore

    /// Create a loader over the shared container (defaults to the real App Group
    /// store, ADR-042). Tests can inject an ``InMemorySnapshotStore``.
    public init(store: WidgetSnapshotStore = AppGroupSnapshotStore()) {
        self.store = store
    }

    /// The last snapshot the app wrote, or `nil` when none has been written yet.
    ///
    /// A `nil` result maps to the ADR-045 empty placeholder in the widget view — it
    /// is NEVER a blank view.
    public func load() -> WidgetSnapshot? {
        store.read()
    }
}

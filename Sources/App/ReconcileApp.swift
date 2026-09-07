import SwiftUI
import SwiftData
import WidgetKit

/// The app entry point (T1).
///
/// Wires the SwiftData `ModelContainer` (ADR-001) into the environment, provides the
/// persisted settings layer (ADR-040), and shows the 4-tab shell. A single `LiveClock`
/// (ADR-038) is provided for later tasks to read.
///
/// T12/ADR-042: constructs the app-side ``WidgetSnapshotWriter`` (the SINGLE writer)
/// backed by the real App Group store and a `WidgetCenter` timeline reload (ADR-043),
/// and injects it into the settings layer (T1 theme change) and — for later UI tasks —
/// makes it available to the quote (T5) and focus (T6) services via the environment.
@main
struct ReconcileApp: App {
    private let container: ModelContainer
    private let widgetWriter: WidgetSnapshotWriter
    @StateObject private var settings: AppSettings

    init() {
        self.container = PersistenceController.makeContainer()

        // T12/ADR-042: the app-side single writer over the REAL App Group container,
        // reloading the widget timeline after each write (ADR-043).
        let writer = WidgetSnapshotWriter(
            store: AppGroupSnapshotStore(),
            today: { LiveClock().today() },
            reload: { WidgetCenter.shared.reloadAllTimelines() }
        )
        self.widgetWriter = writer

        // T1 settings layer gets the writer so a theme change mirrors to the widget
        // (ADR-044). T5/T6 services (constructed by later UI tasks) receive it via the
        // `widgetWriter` environment value below.
        _settings = StateObject(wrappedValue: AppSettings(widgetWriter: writer))
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(settings)
                .environment(\.clock, LiveClock())
                .environment(\.widgetSnapshotWriter, widgetWriter)
        }
        .modelContainer(container)
    }
}

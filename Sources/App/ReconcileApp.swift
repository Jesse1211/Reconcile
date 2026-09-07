import SwiftUI
import SwiftData

/// The app entry point (T1).
///
/// Wires the SwiftData `ModelContainer` (ADR-001) into the environment, provides the
/// persisted settings layer (ADR-040), and shows the 4-tab shell. A single `LiveClock`
/// (ADR-038) is provided for later tasks to read.
@main
struct ReconcileApp: App {
    private let container: ModelContainer
    @StateObject private var settings: AppSettings

    init() {
        self.container = PersistenceController.makeContainer()
        _settings = StateObject(wrappedValue: AppSettings())
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(settings)
                .environment(\.clock, LiveClock())
        }
        .modelContainer(container)
    }
}

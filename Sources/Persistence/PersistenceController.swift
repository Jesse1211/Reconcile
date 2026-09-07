import Foundation
import SwiftData

/// Builds the app's SwiftData `ModelContainer` (ADR-001: pure-local persistence).
public enum PersistenceController {
    /// The registered domain model types (ADR-002).
    ///
    /// T2 replaced T1's `ScaffoldMarker` placeholder with the real domain models.
    public static var models: [any PersistentModel.Type] {
        [
            MIT.self,
            Quote.self,
            FocusSession.self,
            DailyFeeling.self,
            DailySelectedQuote.self,
        ]
    }

    public static var schema: Schema {
        Schema(models)
    }

    /// The on-disk container used by the running app (ADR-001).
    public static func makeContainer() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    /// An in-memory container for tests and previews.
    public static func makeInMemoryContainer() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create in-memory ModelContainer: \(error)")
        }
    }
}

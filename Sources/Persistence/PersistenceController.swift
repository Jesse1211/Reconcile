import Foundation
import SwiftData

/// A minimal scaffold model so the `ModelContainer` has a non-empty schema in T1.
///
/// SwiftData requires at least one `@Model` to build a container. The real domain
/// models (MIT, Quote, FocusSession, DailyFeeling, DailySelectedQuote) are defined by
/// T2, which will register them in `PersistenceController.schema`. This placeholder
/// carries no feature logic and exists only to make the container real and wired.
@Model
public final class ScaffoldMarker {
    public var createdAt: Date
    public init(createdAt: Date = Date()) {
        self.createdAt = createdAt
    }
}

/// Builds the app's SwiftData `ModelContainer` (ADR-001: pure-local persistence).
public enum PersistenceController {
    /// The registered model types. T2 extends this with the real domain models.
    public static var models: [any PersistentModel.Type] {
        [ScaffoldMarker.self]
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

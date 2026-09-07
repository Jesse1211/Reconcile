import XCTest
import SwiftData
@testable import Reconcile

/// The SwiftData `ModelContainer` (ADR-001) builds. T2 adds the real domain models.
final class PersistenceTests: XCTestCase {
    func testInMemoryContainerBuilds() throws {
        let container = PersistenceController.makeInMemoryContainer()
        XCTAssertFalse(container.schema.entities.isEmpty)
    }
}

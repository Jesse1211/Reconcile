import XCTest
import SwiftUI
import SwiftData
@testable import Reconcile

/// T8 UI gate — the Library screen RENDERS its purposeful empty state AND its populated
/// state in BOTH themes (ADR-033/ADR-022).
///
/// These are render smoke tests: each case forces the SwiftUI `body` to evaluate through
/// a `UIHostingController` laid out at a real size, under each `Theme`, in each data state.
/// A crash or an out-of-contract token read (ADR-036) would fail the build/layout here.
@MainActor
final class LibraryScreenRenderTests: XCTestCase {

    final class FakeClient: ZenQuotesClient {
        func today() async throws -> FetchedQuote { FetchedQuote(text: "t", author: "a") }
        func random() async throws -> FetchedQuote { FetchedQuote(text: "r", author: "a") }
    }
    final class ScopeBox { var scope: TodayScope; init(_ s: TodayScope) { scope = s } }

    private var storeURL: URL!
    private var container: ModelContainer!
    private var context: ModelContext!
    private var clock: TestClock!

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibraryScreenRenderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storeURL = dir.appendingPathComponent("store.sqlite")
        let config = ModelConfiguration(schema: PersistenceController.schema, url: storeURL)
        container = try ModelContainer(for: PersistenceController.schema, configurations: [config])
        context = ModelContext(container)
        clock = TestClock(now: Date(timeIntervalSince1970: 1_700_000_000))
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
        if let dir = storeURL?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: dir)
        }
        storeURL = nil
    }

    private func makeModel(populated: Bool) -> LibraryViewModel {
        let box = ScopeBox(.mine)
        let service = QuoteService(context: context, clock: clock, client: FakeClient(), scope: { box.scope })
        let model = LibraryViewModel(service: service, scope: { box.scope }, setScope: { box.scope = $0 })
        if populated {
            _ = model.addUserQuote(text: "A rendered quote", author: "Author")
            _ = model.addUserQuote(text: "Another one", author: nil)
        }
        model.reload()
        return model
    }

    /// Force `body` evaluation by hosting the view and laying it out at a device size.
    private func render(_ theme: Theme, populated: Bool) {
        let model = makeModel(populated: populated)
        let view = LibraryScreen(model: model)
            .screenRole(.library)
            .themed(theme)
            .modelContainer(container)
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        XCTAssertNotNil(host.view, "Library screen renders (\(theme), populated=\(populated))")
    }

    func testRendersEmptyStateLedger() { render(.ledger, populated: false) }
    func testRendersEmptyStateDayArc() { render(.dayArc, populated: false) }
    func testRendersPopulatedLedger() { render(.ledger, populated: true) }
    func testRendersPopulatedDayArc() { render(.dayArc, populated: true) }
}

import XCTest
@testable import Reconcile

/// ADR-047 gate — the live online client parses the quotable mirror's
/// `{ "content", "author", "tags" }` object shape (NOT ZenQuotes' `[{ "q", "a" }]`).
///
/// These tests exercise the PURE parse boundary only — they NEVER hit the network
/// (ADR-013 gate: no real network in tests).
final class LiveQuoteClientTests: XCTestCase {

    func testParsesContentAndAuthorObject() throws {
        let json = #"{ "content": "Be here now", "author": "Ram Dass", "tags": ["Wisdom"] }"#
        let fetched = try LiveZenQuotesClient.parse(Data(json.utf8))
        XCTAssertEqual(fetched.text, "Be here now")
        XCTAssertEqual(fetched.author, "Ram Dass")
    }

    func testParsesArrayFormDefensively() throws {
        let json = #"[{ "content": "First", "author": "A" }]"#
        let fetched = try LiveZenQuotesClient.parse(Data(json.utf8))
        XCTAssertEqual(fetched.text, "First")
        XCTAssertEqual(fetched.author, "A")
    }

    func testEmptyContentThrowsBadResponse() {
        let json = #"{ "content": "", "author": "X" }"#
        XCTAssertThrowsError(try LiveZenQuotesClient.parse(Data(json.utf8))) { error in
            XCTAssertEqual(error as? ZenQuotesError, .badResponse)
        }
    }

    func testMalformedJSONThrowsBadResponse() {
        XCTAssertThrowsError(try LiveZenQuotesClient.parse(Data("not json".utf8))) { error in
            XCTAssertEqual(error as? ZenQuotesError, .badResponse)
        }
    }
}

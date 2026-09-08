import Foundation
import SwiftData

/// The quote selected for a given day + scope (ADR-002, ADR-040).
///
/// `day` is the canonical LOCAL start-of-day `Date` (ADR-038). A selection either
/// references a persisted `Quote` (via `quoteRef`, a `PersistentIdentifier`) OR
/// carries an inline snapshot (`inlineText`/`inlineAuthor`/`inlineDedupKey`) for a
/// quote that is not (yet) in the library — e.g. an online pick. `isManualOverride`
/// records that the user pinned this selection rather than it being auto-chosen.
@Model
public final class DailySelectedQuote {
    /// Stable identity (independent of SwiftData's `PersistentIdentifier`).
    public var id: UUID
    /// The canonical LOCAL start-of-day key (ADR-038).
    public var day: Date
    /// Which pool this selection belongs to (ADR-040).
    public var scope: TodayScope
    /// The online CATEGORY this selection belongs to (ADR-047). The (day, scope)
    /// override key is extended to (day, scope, category) so an `online` refresh
    /// under one category does not apply after the user switches category. `mine`
    /// selections are category-agnostic and always store `.any` (category does not
    /// affect the local pool, ADR-047). Defaults to `.any` for older records.
    public var category: QuoteCategory = QuoteCategory.any

    /// The Codable-encoded backing store for ``quoteRef``.
    ///
    /// SwiftData cannot persist a bare `PersistentIdentifier` property — it wraps
    /// an `NSManagedObjectID`, which the schema builder rejects as a class member
    /// of a persisted value ("Class property within Persisted Struct/Enum is not
    /// supported: NSManagedObjectID"). `PersistentIdentifier` IS `Codable`, so we
    /// persist its encoded bytes here and expose the spec's `PersistentIdentifier?`
    /// contract through the ``quoteRef`` computed accessor below — callers use
    /// ``quoteRef``, not this backing store.
    public var quoteRefData: Data?

    /// Inline snapshot text when there is no backing `Quote`.
    public var inlineText: String?
    /// Inline snapshot author when there is no backing `Quote`.
    public var inlineAuthor: String?
    /// Inline snapshot dedup key (INV-4) when there is no backing `Quote`.
    public var inlineDedupKey: String?
    /// Whether the user manually pinned this selection.
    public var isManualOverride: Bool

    public init(
        id: UUID = UUID(),
        day: Date,
        scope: TodayScope,
        category: QuoteCategory = .any,
        quoteRef: PersistentIdentifier? = nil,
        inlineText: String? = nil,
        inlineAuthor: String? = nil,
        inlineDedupKey: String? = nil,
        isManualOverride: Bool = false
    ) {
        self.id = id
        self.day = day
        self.scope = scope
        self.category = category
        self.quoteRefData = DailySelectedQuote.encode(quoteRef)
        self.inlineText = inlineText
        self.inlineAuthor = inlineAuthor
        self.inlineDedupKey = inlineDedupKey
        self.isManualOverride = isManualOverride
    }
}

public extension DailySelectedQuote {
    /// Reference to a persisted `Quote`, or `nil` when the selection is inline.
    ///
    /// Preserves the spec's `PersistentIdentifier?` contract while persisting via
    /// the Codable-encoded ``quoteRefData`` (SwiftData cannot store a bare
    /// `PersistentIdentifier`). Reading decodes; writing re-encodes.
    var quoteRef: PersistentIdentifier? {
        get { DailySelectedQuote.decode(quoteRefData) }
        set { quoteRefData = DailySelectedQuote.encode(newValue) }
    }

    /// Whether this selection carries an inline snapshot (no backing `Quote`).
    var isInline: Bool {
        quoteRefData == nil
    }

    /// Encode a `PersistentIdentifier` to its Codable byte representation.
    static func encode(_ ref: PersistentIdentifier?) -> Data? {
        guard let ref else { return nil }
        return try? JSONEncoder().encode(ref)
    }

    /// Decode a `PersistentIdentifier` from its Codable byte representation.
    static func decode(_ data: Data?) -> PersistentIdentifier? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(PersistentIdentifier.self, from: data)
    }

    /// Build an inline selection, deriving `inlineDedupKey` from text/author (INV-4).
    static func inline(
        day: Date,
        scope: TodayScope,
        category: QuoteCategory = .any,
        text: String,
        author: String?,
        isManualOverride: Bool = false
    ) -> DailySelectedQuote {
        DailySelectedQuote(
            day: day,
            scope: scope,
            category: category,
            quoteRef: nil,
            inlineText: text,
            inlineAuthor: author,
            inlineDedupKey: QuoteNormalization.dedupKey(text: text, author: author),
            isManualOverride: isManualOverride
        )
    }
}

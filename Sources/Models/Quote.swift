import Foundation
import SwiftData

/// A quote in the personal library or fetched from the online source (ADR-002).
///
/// Invariants enforced here:
///   * INV-9: `likedAt` is the SINGLE stored like field. There is NO separate
///     stored `liked` column; ``liked`` is a DERIVED computed property equal to
///     `likedAt != nil`. Liking sets a timestamp; unliking clears it.
///   * INV-4: ``dedupKey`` is `normalize(text) + "|" + normalizeAuthor(author)`
///     and is the ONLY duplicate-detection identity. It is stored (so it can be
///     queried/indexed) and MUST be kept in sync with `text`/`author` via
///     ``recomputeDedupKey()`` / ``update(text:author:)``.
@Model
public final class Quote {
    /// Stable identity (independent of SwiftData's `PersistentIdentifier`).
    public var id: UUID
    /// The quote text.
    public var text: String
    /// Optional author; `nil`/`""`/`"Anonymous"` are equivalent for dedup (INV-4).
    public var author: String?
    /// The origin of the quote (ADR-002).
    public var source: QuoteSource
    /// The instant the quote was liked, or `nil` if not liked (INV-9).
    ///
    /// This is the SINGLE stored like field; ``liked`` derives from it.
    public var likedAt: Date?
    /// Stored canonical dedup key (INV-4). Kept in sync with `text`/`author`.
    public var dedupKey: String

    public init(
        id: UUID = UUID(),
        text: String,
        author: String? = nil,
        source: QuoteSource,
        likedAt: Date? = nil
    ) {
        self.id = id
        self.text = text
        self.author = author
        self.source = source
        self.likedAt = likedAt
        self.dedupKey = QuoteNormalization.dedupKey(text: text, author: author)
    }
}

// MARK: - Derived like state (INV-9)

public extension Quote {
    /// DERIVED like state (INV-9): `true` iff `likedAt != nil`. There is NO
    /// separate stored `liked` field — this is the single source of truth.
    var liked: Bool {
        likedAt != nil
    }

    /// Like the quote by stamping `likedAt` (INV-9). No-op if already liked, so a
    /// re-like never overwrites the original like time.
    func like(at date: Date) {
        if likedAt == nil {
            likedAt = date
        }
    }

    /// Unlike the quote by clearing `likedAt` (INV-9).
    func unlike() {
        likedAt = nil
    }

    /// Set like state to `desired`, stamping `at` when transitioning to liked (INV-9).
    func setLiked(_ desired: Bool, at date: Date) {
        if desired {
            like(at: date)
        } else {
            unlike()
        }
    }
}

// MARK: - Dedup (INV-4)

public extension Quote {
    /// Recompute and store `dedupKey` from the current `text`/`author` (INV-4).
    ///
    /// Call after any mutation of `text` or `author`; ``update(text:author:)``
    /// does this for you.
    func recomputeDedupKey() {
        dedupKey = QuoteNormalization.dedupKey(text: text, author: author)
    }

    /// Update `text`/`author` and keep `dedupKey` in sync (INV-4).
    func update(text: String, author: String?) {
        self.text = text
        self.author = author
        recomputeDedupKey()
    }

    /// The dedup key an arbitrary text/author pair WOULD produce (INV-4).
    ///
    /// Use for pre-insert duplicate checks without constructing a `Quote`.
    static func dedupKey(text: String, author: String?) -> String {
        QuoteNormalization.dedupKey(text: text, author: author)
    }
}

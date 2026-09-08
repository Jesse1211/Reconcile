import Foundation

/// Canonical text/author normalization and dedup-key derivation for quotes (INV-4).
///
/// A `Quote`'s `dedupKey` is the ONLY identity used to detect duplicates across
/// the personal library and the online source, so the rules here are the single
/// source of truth and must stay deterministic. The key is:
///
///     dedupKey = normalize(text) + "|" + normalizeAuthor(author)
///
/// where (INV-4):
///   * `normalize(text)`  lowercases, trims, collapses internal runs of
///     whitespace to a single ASCII space, folds curly quotes/apostrophes to
///     their straight ASCII equivalents, and strips a SINGLE trailing period.
///   * `normalizeAuthor(_:)` folds `nil`, the empty string, and `"Anonymous"`
///     (case-insensitively) to the SAME empty value, then applies the same text
///     normalization to any other author.
public enum QuoteNormalization {
    /// Normalize quote text per INV-4.
    ///
    /// Steps, in order:
    ///  1. Fold curly quotes/apostrophes to straight ASCII.
    ///  2. Lowercase.
    ///  3. Collapse every run of Unicode whitespace to a single ASCII space.
    ///  4. Trim leading/trailing whitespace.
    ///  5. Strip a single trailing period (`.`), if present.
    ///  6. Trim again (a space before the stripped period must not linger, e.g. "word .").
    public static func normalize(_ text: String) -> String {
        var s = foldQuotes(text)
        s = s.lowercased()
        // Collapse internal whitespace (spaces, tabs, newlines, unicode spaces)
        // to a single ASCII space.
        let collapsed = s
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        s = collapsed
        // Strip a single trailing period, then re-trim so a space that preceded it (e.g.
        // "word .") does not leave a stray trailing space that breaks dedup (INV-4).
        if s.hasSuffix(".") {
            s.removeLast()
            s = s.trimmingCharacters(in: .whitespaces)
        }
        return s
    }

    /// Normalize an author per INV-4: `nil`, `""`, and `"Anonymous"` all fold to
    /// the same empty value; any other author is text-normalized.
    public static func normalizeAuthor(_ author: String?) -> String {
        guard let author else { return "" }
        let normalized = normalize(author)
        if normalized.isEmpty || normalized == "anonymous" {
            return ""
        }
        return normalized
    }

    /// The canonical dedup key `normalize(text) + "|" + normalizeAuthor(author)` (INV-4).
    public static func dedupKey(text: String, author: String?) -> String {
        normalize(text) + "|" + normalizeAuthor(author)
    }

    /// Fold curly quotes/apostrophes and common typographic dashes-adjacent glyphs
    /// to straight ASCII. Kept narrow to the marks named by INV-4.
    private static func foldQuotes(_ text: String) -> String {
        var result = text
        // Curly single quotes / apostrophes → straight apostrophe.
        for ch in ["\u{2018}", "\u{2019}", "\u{201B}", "\u{2032}"] {
            result = result.replacingOccurrences(of: ch, with: "'")
        }
        // Curly double quotes → straight double quote.
        for ch in ["\u{201C}", "\u{201D}", "\u{201F}", "\u{2033}"] {
            result = result.replacingOccurrences(of: ch, with: "\"")
        }
        return result
    }
}

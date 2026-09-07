import Foundation

/// The deterministic LOCAL daily pick for the `mine` scope (ADR-011).
///
/// Contract (ADR-011):
///   * The pick is derived ENTIRELY LOCALLY by seeding an index into the local
///     `mine` pool, **stably sorted by `dedupKey`**, with seed = **(day, scope)**.
///   * `pick(...)` returns `Quote?`: **`nil` on an EMPTY pool** (caller renders the
///     guiding empty state, ADR-033/-034 — NEVER a modulo-by-zero), and the **sole
///     element on a singleton** pool.
///   * The pick is **stable under pool growth**: adding quotes that sort AFTER the
///     picked one (larger `dedupKey`) does NOT change today's derived pick for that
///     (day, scope).
///
/// The stability-under-growth property is met with rendezvous (HRW) selection: each
/// candidate gets a deterministic score `hash(seed ‖ dedupKey)` and the pool's
/// winner is the SMALLEST score. A newly-added quote can only change the winner if
/// its own score is smaller — a later-sorting quote added to the tail leaves the
/// existing winner in place. The hash is a stable FNV-1a (NOT Swift's per-process
/// randomized `Hasher`), so the pick is reproducible across launches and processes.
public enum DailyQuotePicker {
    /// Deterministically pick a `Quote` from a local pool for (day, scope) (ADR-011).
    ///
    /// - Returns: `nil` when `pool` is empty; the sole element when it has one; else
    ///   the rendezvous-hash winner. Ties on score break by `dedupKey` (stable).
    public static func pick(from pool: [Quote], day: Date, scope: TodayScope) -> Quote? {
        guard !pool.isEmpty else { return nil }              // ADR-011: empty → nil, no modulo-by-zero
        if pool.count == 1 { return pool[0] }                 // ADR-011: singleton → that quote
        let seed = seedString(day: day, scope: scope)
        return pool.min { lhs, rhs in
            let ls = score(seed: seed, dedupKey: lhs.dedupKey)
            let rs = score(seed: seed, dedupKey: rhs.dedupKey)
            if ls != rs { return ls < rs }
            return lhs.dedupKey < rhs.dedupKey                // stable tiebreak by sort key
        }
    }

    /// A DIFFERENT local pick than `current`, for manual refresh in `mine` (ADR-025).
    ///
    /// Excludes `current` (by `dedupKey`), then rendezvous-picks among the rest with a
    /// refresh-salted seed so the result is deterministic yet distinct. Returns `nil`
    /// when there is no OTHER selectable quote (degenerate pool ≤1 selectable, ADR-027).
    public static func pickDifferent(
        from pool: [Quote],
        excluding current: Quote?,
        day: Date,
        scope: TodayScope
    ) -> Quote? {
        let remaining = pool.filter { $0.dedupKey != current?.dedupKey }
        guard !remaining.isEmpty else { return nil }
        if remaining.count == 1 { return remaining[0] }
        let seed = seedString(day: day, scope: scope) + "|refresh"
        return remaining.min { lhs, rhs in
            let ls = score(seed: seed, dedupKey: lhs.dedupKey)
            let rs = score(seed: seed, dedupKey: rhs.dedupKey)
            if ls != rs { return ls < rs }
            return lhs.dedupKey < rhs.dedupKey
        }
    }

    // MARK: - Seed / hash

    /// The canonical (day, scope) seed string (ADR-011). Uses the day's `timeIntervalSince1970`
    /// (a canonical local start-of-day per ADR-038) so it is stable across launches.
    static func seedString(day: Date, scope: TodayScope) -> String {
        "\(Int(day.timeIntervalSince1970.rounded()))|\(scope.rawValue)"
    }

    /// The rendezvous score `FNV1a(seed ‖ "#" ‖ dedupKey)` — a STABLE 64-bit hash.
    static func score(seed: String, dedupKey: String) -> UInt64 {
        fnv1a("\(seed)#\(dedupKey)")
    }

    /// FNV-1a 64-bit over the string's UTF-8 bytes. Deterministic across processes
    /// (unlike `Hasher`, which is seeded per-process and must NOT be used here).
    static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return hash
    }
}

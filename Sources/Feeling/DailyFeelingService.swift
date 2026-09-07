import Foundation
import SwiftData

/// Capture/persistence service for the daily mood/stress diary entry (T11).
///
/// This service OWNS capture and persistence of ``DailyFeeling``:
///   * **Fetch-or-create today's entry** — there is at most ONE entry per local
///     calendar day (INV-7 / ADR-020); the canonical day key is the injectable
///     ``Clock``'s local `startOfDay` (ADR-038).
///   * **Save = UPSERT** — saving today's feeling updates the existing row in
///     place if present, otherwise inserts one; it never creates a second row
///     for the same day (INV-7 / ADR-020). Both `mood` and `stress` are REQUIRED
///     and must lie in `0...5`; `whyText` is optional (ADR-019 / ADR-020).
///   * **Same-day editable, cross-day locked** — an entry for a day that has
///     already rolled is READ-ONLY: attempting to save/edit it is REJECTED
///     (INV-8, mirrors ADR-004's cross-day lock for MITs).
///
/// The DISPLAY of mood/stress on the Summary screen is NOT this service's
/// responsibility — that is T10 (ADR-023, which superseded ADR-021's store-only
/// clause for the display aspect only; the capture rules INV-7/-8 are unchanged).
///
/// The service is a thin value type over an injected ``Clock`` so "today" is
/// deterministic in tests. It reads/writes through a `ModelContext` the caller
/// supplies; it does not own the context or call `save()` — persistence flush is
/// the caller's choice (mirrors the model-layer `upsert` contract).
public struct DailyFeelingService {
    /// The injected time source. "Today" and every day-key comparison flow
    /// through this clock's calendar (ADR-038) so tests can pin the day.
    public let clock: Clock

    public init(clock: Clock) {
        self.clock = clock
    }

    /// Errors raised by the capture path when a save would violate an invariant.
    ///
    /// Scale-range violations surface as ``DailyFeeling/InvariantError`` (thrown by
    /// the model layer); this enum adds the SERVICE-level cross-day lock (INV-8).
    public enum ServiceError: Error, Equatable {
        /// INV-8: an attempt to save/edit a feeling for a day that is not today.
        ///
        /// A cross-day historical entry is read-only (mirrors ADR-004). Carries
        /// the offending `day` key and the current `today` for diagnostics.
        case crossDayLocked(day: Date, today: Date)
    }

    // MARK: - Read

    /// The canonical day key for "now" (local `startOfDay`, ADR-038).
    public func today() -> Date {
        clock.today()
    }

    /// Fetch today's ``DailyFeeling`` if one exists, else `nil` (INV-7).
    ///
    /// Read-only: never inserts. Use ``fetchOrCreateToday(in:)`` when the caller
    /// needs a live, same-day-editable entry to bind an editor to.
    public func todaysFeeling(in context: ModelContext) throws -> DailyFeeling? {
        try DailyFeeling.fetch(day: today(), in: context)
    }

    /// Whether the feeling for `day` is editable RIGHT NOW (INV-8).
    ///
    /// Only TODAY's entry is editable; any entry whose `day` has already rolled is
    /// locked (read-only). This is the predicate the UI uses to disable an editor.
    public func isEditable(day: Date) -> Bool {
        clock.startOfDay(for: day) == today()
    }

    // MARK: - Capture (upsert)

    /// Fetch-or-create today's ``DailyFeeling`` for editing (INV-7 / ADR-020).
    ///
    /// If today already has an entry it is returned (same-day editable); otherwise
    /// a fresh one is inserted with the given seed scales (defaulting to the
    /// scale midpoint-ish `0`) so the editor always has a live row to bind to.
    /// Because the day key is today's, the result is always editable (INV-8).
    ///
    /// Prefer ``saveToday(mood:stress:whyText:in:)`` for the actual save; this
    /// helper exists for editors that want a materialized row up front.
    ///
    /// - Throws: ``DailyFeeling/InvariantError`` if the seed scales are out of range.
    @discardableResult
    public func fetchOrCreateToday(
        mood: Int = 0,
        stress: Int = 0,
        whyText: String? = nil,
        in context: ModelContext
    ) throws -> DailyFeeling {
        let day = today()
        if let existing = try DailyFeeling.fetch(day: day, in: context) {
            return existing
        }
        let created = try DailyFeeling(day: day, mood: mood, stress: stress, whyText: whyText)
        context.insert(created)
        return created
    }

    /// Save (UPSERT) TODAY's feeling — the primary capture entry point.
    ///
    /// One-per-day: updates today's row in place if present, else inserts it
    /// (INV-7 / ADR-020). `mood` and `stress` are required and validated to
    /// `0...5` (rejected out of range, never clamped); `whyText` is optional.
    ///
    /// Because it always targets today's day key, this path can never be blocked
    /// by the cross-day lock — today is, by definition, editable.
    ///
    /// - Returns: the upserted feeling (today's single row).
    /// - Throws: ``DailyFeeling/InvariantError`` if `mood`/`stress` are out of range.
    @discardableResult
    public func saveToday(
        mood: Int,
        stress: Int,
        whyText: String?,
        in context: ModelContext
    ) throws -> DailyFeeling {
        try DailyFeeling.upsert(
            day: today(),
            mood: mood,
            stress: stress,
            whyText: whyText,
            in: context
        )
    }

    /// Save (UPSERT) the feeling for an EXPLICIT `day`, enforcing the cross-day
    /// lock (INV-8).
    ///
    /// This is the guarded variant of ``saveToday(mood:stress:whyText:in:)``: if
    /// `day` is not today's canonical key it is a historical entry and the save is
    /// REJECTED with ``ServiceError/crossDayLocked(day:today:)`` — the store is
    /// left untouched (mirrors ADR-004's cross-day read-only lock for MITs). The
    /// `day` is normalized to its `startOfDay` before comparison so a time-of-day
    /// component never defeats the lock (ADR-038).
    ///
    /// Scale validation (INV-7) runs the same as the today path when the day IS
    /// editable; the lock is checked FIRST so a cross-day edit is rejected even if
    /// its scales would have been valid.
    ///
    /// - Returns: the upserted feeling.
    /// - Throws: ``ServiceError/crossDayLocked(day:today:)`` if `day` has rolled;
    ///   ``DailyFeeling/InvariantError`` if `mood`/`stress` are out of range.
    @discardableResult
    public func save(
        day: Date,
        mood: Int,
        stress: Int,
        whyText: String?,
        in context: ModelContext
    ) throws -> DailyFeeling {
        let key = clock.startOfDay(for: day)
        let todayKey = today()
        guard key == todayKey else {
            throw ServiceError.crossDayLocked(day: key, today: todayKey)
        }
        return try DailyFeeling.upsert(
            day: key,
            mood: mood,
            stress: stress,
            whyText: whyText,
            in: context
        )
    }

    /// Edit an EXISTING feeling in place, enforcing the cross-day lock (INV-8).
    ///
    /// Convenience over ``save(day:mood:stress:whyText:in:)`` for callers that
    /// already hold a fetched ``DailyFeeling``: rejects the edit if the entry's
    /// `day` has rolled (read-only historical entry), otherwise applies the new
    /// validated scales/why to the row.
    ///
    /// - Throws: ``ServiceError/crossDayLocked(day:today:)`` if the entry is
    ///   historical; ``DailyFeeling/InvariantError`` if scales are out of range.
    public func edit(
        _ feeling: DailyFeeling,
        mood: Int,
        stress: Int,
        whyText: String?
    ) throws {
        let key = clock.startOfDay(for: feeling.day)
        let todayKey = today()
        guard key == todayKey else {
            throw ServiceError.crossDayLocked(day: key, today: todayKey)
        }
        try feeling.setMood(mood)
        try feeling.setStress(stress)
        feeling.whyText = whyText
    }
}

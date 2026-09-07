import Foundation
import SwiftData

/// The service that owns every MIT operation (T4).
///
/// All day logic flows through the injectable ``Clock`` (ADR-038); no wall-clock
/// reads happen here, so tests pin "today" deterministically.
///
/// ## Responsibilities
///   * Create — multiple MITs per local day, **no upper cap** (ADR-003).
///   * Edit — content is mutable on the current local day only; a cross-day
///     historical MIT is read-only (INV-3 / ADR-004).
///   * Complete / flip — completing stamps `completedOn = today`; flipping
///     `completed → open` the SAME day clears `completedOn` (ADR-004 / D1).
///   * Lazy rollover (ADR-005 / D2) — on app open, advance `appearsOn = today`
///     for every open, non-deleted, past-due MIT (**rollover FIRST**), THEN the
///     cross-day read-only lock applies only to records still terminal/historical.
///   * Soft delete + undo (ADR-008) — retained, excluded from stats AND from the
///     rollover query (ADR-029); cross-midnight undo restores into TODAY (ADR-030).
///   * Daily stat (ADR-006) — count of MITs whose `completedOn` is that day; the
///     open/rolling count is `status == open AND isDeleted == false` (ADR-017).
///
/// The service is intentionally a thin, `Clock`-parameterised layer over the
/// model-layer invariants already enforced on ``MIT`` (INV-1, INV-6). It adds the
/// day-boundary rules (rollover, cross-day lock) that only make sense with a clock.
public struct MITService {
    /// The injectable time source (ADR-038). Every day key derives from this.
    public let clock: Clock

    public init(clock: Clock) {
        self.clock = clock
    }

    // MARK: - Errors

    /// Errors raised by MIT operations that a caller may recover from.
    public enum ServiceError: Error, Equatable {
        /// INV-3 / ADR-004: a mutation targeted a cross-day historical (locked)
        /// MIT — its local day has already rolled, so it is read-only.
        case historicalRecordIsReadOnly(id: UUID, appearsOn: Date, today: Date)
        /// The referenced MIT could not be found in the context.
        case notFound(id: UUID)
    }

    // MARK: - Create (ADR-003: no cap)

    /// Create a new MIT appearing on TODAY. Multiple per day are allowed with NO
    /// upper limit (ADR-003).
    ///
    /// - Parameters:
    ///   - text: the task text.
    ///   - reason: optional reason/context.
    ///   - context: the SwiftData context to insert into.
    /// - Returns: the newly-created, inserted MIT.
    @discardableResult
    public func create(
        text: String,
        reason: String? = nil,
        in context: ModelContext
    ) -> MIT {
        let today = clock.today()
        let mit = MIT(
            text: text,
            reason: reason,
            status: .open,
            createdOn: today,
            completedOn: nil,
            appearsOn: today
        )
        context.insert(mit)
        return mit
    }

    // MARK: - Cross-day read-only lock (INV-3 / ADR-004)

    /// Whether `mit` is mutable on the current local day (INV-3 / ADR-004).
    ///
    /// A live MIT is same-day mutable exactly when it appears on TODAY. After the
    /// lazy rollover has run (``rollover(in:)``), every open, non-deleted, past-due
    /// MIT has already been advanced to today, so only genuinely terminal
    /// (completed) or still-historical records have `appearsOn < today`. A
    /// soft-deleted MIT is never content-mutable (it has left every list).
    ///
    /// - Important: call ``rollover(in:)`` on app open BEFORE relying on this, so an
    ///   open past-due MIT is advanced (editable), not frozen (ADR-005 / D2).
    public func isMutable(_ mit: MIT) -> Bool {
        guard !mit.isDeleted else { return false }
        return mit.appearsOn >= clock.today()
    }

    /// Throw if `mit` is a cross-day historical (locked) record (INV-3 / ADR-004).
    private func requireMutable(_ mit: MIT) throws {
        guard isMutable(mit) else {
            throw ServiceError.historicalRecordIsReadOnly(
                id: mit.id,
                appearsOn: mit.appearsOn,
                today: clock.today()
            )
        }
    }

    // MARK: - Edit (same-day only; INV-3 / ADR-004)

    /// Edit an MIT's content (text/reason) on the current local day (ADR-004).
    ///
    /// - Throws: ``ServiceError/historicalRecordIsReadOnly(id:appearsOn:today:)``
    ///   if the MIT's day has already rolled (INV-3). A rejected edit never mutates.
    public func edit(
        _ mit: MIT,
        text: String? = nil,
        reason: String?? = nil
    ) throws {
        try requireMutable(mit)
        if let text {
            mit.text = text
        }
        if let reason {
            mit.reason = reason
        }
    }

    // MARK: - Complete / flip (ADR-004 / D1)

    /// Mark an MIT completed on TODAY (ADR-004 / D1): `status = completed`,
    /// `completedOn = today`.
    ///
    /// - Throws: ``ServiceError/historicalRecordIsReadOnly(id:appearsOn:today:)``
    ///   for a locked historical MIT (INV-3), or ``MIT/InvariantError`` if the
    ///   completion day precedes creation (INV-1 — never expected for a same-day op).
    public func complete(_ mit: MIT) throws {
        try requireMutable(mit)
        try mit.markCompleted(on: clock.today())
    }

    /// Flip a completed MIT back to open on the SAME day (ADR-004 / D1):
    /// `status = open` AND `completedOn = nil` — so the daily completed-count
    /// (which counts by `completedOn`, ADR-006) is decremented and never over-counts
    /// a re-opened MIT.
    ///
    /// - Throws: ``ServiceError/historicalRecordIsReadOnly(id:appearsOn:today:)``
    ///   if the MIT's day has already rolled (a completed cross-day MIT is terminal).
    public func reopen(_ mit: MIT) throws {
        try requireMutable(mit)
        mit.reopen()
    }

    /// Toggle an MIT between completed and open on the current local day (ADR-004 / D1).
    ///
    /// Convenience over ``complete(_:)`` / ``reopen(_:)`` for a same-day checkbox flip.
    public func toggleCompletion(_ mit: MIT) throws {
        switch mit.status {
        case .open:
            try complete(mit)
        case .completed:
            try reopen(mit)
        }
    }

    // MARK: - Lazy rollover (ADR-005 / D2)

    /// The lazy rollover, run on app open (ADR-005 / D2).
    ///
    /// **Step 1 — rollover FIRST:** advance `appearsOn = today` for EVERY MIT with
    /// `status == open AND !isDeleted AND appearsOn < today`. This is the SAME
    /// record advancing (not a per-day copy) and has no cap on days rolled.
    /// Soft-deleted MITs are gated out of this query (ADR-029) so a deleted MIT
    /// never advances `appearsOn` again.
    ///
    /// **Step 2 — THEN the cross-day read-only lock** (INV-3 / ADR-004) is a pure
    /// read predicate (``isMutable(_:)``): because step 1 already advanced every
    /// open, non-deleted, past-due MIT, only records that remain terminal
    /// (completed) or still historical after step 1 are locked. Order matters — an
    /// open past-due MIT is ADVANCED to today (editable), never frozen.
    ///
    /// - Returns: the MITs whose `appearsOn` was advanced this call.
    @discardableResult
    public func rollover(in context: ModelContext) throws -> [MIT] {
        let today = clock.today()
        // Step 1: rollover query — open AND !isDeleted AND appearsOn < today.
        // `isSoftDeleted` gates the query (ADR-029); a #Predicate cannot compare an
        // enum, so match the raw status string.
        let openRaw = MITStatus.open.rawValue
        let descriptor = FetchDescriptor<MIT>(
            predicate: #Predicate<MIT> { mit in
                mit.statusRaw == openRaw && !mit.isSoftDeleted && mit.appearsOn < today
            }
        )
        let dueForRoll = try context.fetch(descriptor)
        for mit in dueForRoll {
            mit.appearsOn = today
        }
        return dueForRoll
        // Step 2 (the cross-day lock) needs no write — it is enforced lazily by
        // `isMutable(_:)` / `requireMutable(_:)` on every subsequent edit/complete.
    }

    // MARK: - Soft delete + undo (ADR-008 / ADR-029 / ADR-030)

    /// Soft-delete an MIT (ADR-008): `isDeleted = true`, `deletedAt = now`. The row
    /// is RETAINED (history/undo) but excluded from every stat (INV-6) AND from the
    /// rollover query (ADR-029) — a deleted MIT never advances `appearsOn` again.
    public func softDelete(_ mit: MIT) {
        mit.softDelete(at: clock.now())
    }

    /// Undo a soft-delete (ADR-008 / ADR-030).
    ///
    /// Cross-midnight-safe: the restored (still-open) MIT re-enters TODAY —
    /// `appearsOn = today`, `isDeleted` cleared, `deletedAt` cleared — never the
    /// now-locked previous day (upholds ADR-004 / INV-3). `createdOn` is PRESERVED
    /// (unchanged) so the lifecycle timeline (ADR-007) stays honest about the MIT's
    /// true origin and its delete-gap. A restored completed MIT keeps its
    /// `completedOn`; only an OPEN MIT re-enters rollover as today's.
    public func undoDelete(_ mit: MIT) {
        let today = clock.today()
        mit.restore() // clears isDeleted + deletedAt; createdOn untouched.
        // Only an open MIT re-enters today's rollover; a restored completed MIT is
        // terminal and keeps its historical appearsOn/completedOn.
        if mit.status == .open {
            mit.appearsOn = today
        }
    }

    // MARK: - Read model: today's list (ADR-005 / ADR-017)

    /// The MITs that appear on TODAY: open, non-deleted, `appearsOn == today`.
    ///
    /// Call ``rollover(in:)`` first (app open) so past-due open MITs have been
    /// advanced into this list.
    public func todaysOpenMITs(in context: ModelContext) throws -> [MIT] {
        let today = clock.today()
        let openRaw = MITStatus.open.rawValue
        let descriptor = FetchDescriptor<MIT>(
            predicate: #Predicate<MIT> { mit in
                mit.statusRaw == openRaw && !mit.isSoftDeleted && mit.appearsOn == today
            },
            sortBy: [SortDescriptor(\.createdOn), SortDescriptor(\.id)]
        )
        return try context.fetch(descriptor)
    }

    // MARK: - Stats (ADR-006 / ADR-017)

    /// The daily completed-MIT stat (ADR-006): count of live MITs whose
    /// `completedOn` is `day`. Soft-deleted MITs are excluded (INV-6).
    public func completedCount(on day: Date, in context: ModelContext) throws -> Int {
        let dayKey = clock.startOfDay(for: day)
        let descriptor = FetchDescriptor<MIT>(
            predicate: #Predicate<MIT> { mit in
                !mit.isSoftDeleted && mit.completedOn == dayKey
            }
        )
        return try context.fetchCount(descriptor)
    }

    /// The MITs completed on `day` (ADR-006), excluding soft-deleted (INV-6).
    public func completedMITs(on day: Date, in context: ModelContext) throws -> [MIT] {
        let dayKey = clock.startOfDay(for: day)
        let descriptor = FetchDescriptor<MIT>(
            predicate: #Predicate<MIT> { mit in
                !mit.isSoftDeleted && mit.completedOn == dayKey
            },
            sortBy: [SortDescriptor(\.createdOn), SortDescriptor(\.id)]
        )
        return try context.fetch(descriptor)
    }

    /// The current open/rolling count (ADR-017): MITs where
    /// `status == open AND isDeleted == false`, regardless of `appearsOn`.
    ///
    /// This is the single shared predicate behind Today's rolled-in list length and
    /// the Summary "current open/rolling" KPI (read-model consistency, T10).
    public func openRollingCount(in context: ModelContext) throws -> Int {
        let openRaw = MITStatus.open.rawValue
        let descriptor = FetchDescriptor<MIT>(
            predicate: #Predicate<MIT> { mit in
                mit.statusRaw == openRaw && !mit.isSoftDeleted
            }
        )
        return try context.fetchCount(descriptor)
    }
}

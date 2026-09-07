import Foundation
import SwiftData

/// The read-model that powers the Summary screen (T10 / ADR-007 / ADR-017 / ADR-023).
///
/// `SummaryService` is a pure, `Clock`-parameterised aggregation layer: it owns NO
/// mutable state and performs NO writes. It derives every Summary block — the two
/// per-day charts, the mood/stress trend, the per-MIT lifecycle timeline, and the KPI
/// cards — from the SAME service queries the rest of the app already uses, so the
/// Summary numbers are read-model-consistent with Today's numbers (ADR-006/-007/-017):
///
///   * completed-MIT counts route through ``MITService/completedCount(on:in:)`` /
///     ``MITService/completedMITs(on:in:)`` — the identical `completedOn` query Today
///     uses (ADR-006). The KPI "total completed" is the SUM of those per-day counts.
///   * the open/rolling KPI routes through ``MITService/openRollingCount(in:)`` — the
///     SAME predicate (`status == open AND !isDeleted`) that gives Today's rolled-in
///     list length, so `today_list_length == open_rolling_kpi` (ADR-017/F8).
///   * per-day focus totals route through ``FocusSessionService/perDayPortions`` — the
///     query-time midnight split (ADR-032). The range filter is applied PER SPLIT
///     PORTION, and the "total focus" KPI is the SUM of the SAME in-range portions the
///     chart draws, so `KPI == Σ chart bars` and a boundary-spanning session counts
///     only its in-range portion (ADR-017/-032).
///   * mood/stress come from `DailyFeeling`; the average-mood KPI is the mean over ONLY
///     days that HAVE an entry (missing days excluded, NOT counted as 0, ADR-031), and
///     the trend series marks missing days as gaps.
///
/// The service takes an injected ``Clock`` so "today" and every day boundary are
/// deterministic in tests (ADR-038). It reuses the peer services rather than
/// re-implementing their predicates, which is what keeps the read model honest.
public struct SummaryService {
    /// The injectable time source (ADR-038); every day key and range window derives
    /// from this.
    public let clock: Clock

    private let mitService: MITService

    public init(clock: Clock) {
        self.clock = clock
        self.mitService = MITService(clock: clock)
    }

    // MARK: - Range window (ADR-017: Week / Month / All)

    /// The switchable Summary time range (ADR-017). `.week`/`.month` are trailing
    /// windows ending on (and including) today; `.all` covers all stored data.
    public enum Range: String, CaseIterable, Sendable {
        case week
        case month
        case all

        /// A short label for the range switcher UI.
        public var displayName: String {
            switch self {
            case .week: return "Week"
            case .month: return "Month"
            case .all: return "All"
            }
        }
    }

    /// A `[startDay, endDay]` inclusive window of canonical day keys (ADR-038).
    ///
    /// For `.week`/`.month` the window is a fixed trailing span ending on today. For
    /// `.all`, `start` is `nil` — every stored day qualifies (the earliest data day
    /// becomes the effective start when a concrete axis is needed).
    public struct DayWindow: Sendable, Equatable {
        /// The inclusive first day, or `nil` for an open-ended `.all` range.
        public let start: Date?
        /// The inclusive last day (always today for the trailing ranges).
        public let end: Date

        public init(start: Date?, end: Date) {
            self.start = start
            self.end = end
        }

        /// Whether `day` falls within `[start, end]` (a `nil` start means unbounded below).
        public func contains(_ day: Date) -> Bool {
            if let start, day < start { return false }
            return day <= end
        }
    }

    /// The inclusive day window for `range`, relative to today (ADR-017).
    ///
    /// `.week` = the 7 days ending today (today and the prior 6). `.month` = the 30
    /// days ending today. `.all` = open-ended below, capped at today above.
    public func window(for range: Range) -> DayWindow {
        let today = clock.today()
        switch range {
        case .week:
            return DayWindow(start: dayOffset(today, by: -6), end: today)
        case .month:
            return DayWindow(start: dayOffset(today, by: -29), end: today)
        case .all:
            return DayWindow(start: nil, end: today)
        }
    }

    /// Advance a day key by whole calendar days via the clock's calendar (ADR-038).
    private func dayOffset(_ day: Date, by days: Int) -> Date {
        clock.calendar.date(byAdding: .day, value: days, to: day) ?? day
    }

    /// The ordered list of day keys spanning `window` inclusively. For an `.all`
    /// window with no data, `fallbackStart` (normally today) anchors a single-day axis.
    private func days(in window: DayWindow, fallbackStart: Date) -> [Date] {
        let start = window.start ?? fallbackStart
        guard start <= window.end else { return [window.end] }
        var result: [Date] = []
        var cursor = start
        while cursor <= window.end {
            result.append(cursor)
            cursor = dayOffset(cursor, by: 1)
        }
        return result
    }

    /// The concrete ordered axis days for `range` (ADR-017).
    ///
    /// For `.week`/`.month` this is the fixed trailing window. For `.all` (open-ended
    /// below) the axis starts at the EARLIEST stored data day so the whole history is
    /// drawn — falling back to today's single (zero) bar when there is no data at all,
    /// so the chart still renders an axis (ADR-033).
    private func axisDays(for range: Range, in context: ModelContext) throws -> [Date] {
        let win = window(for: range)
        let today = clock.today()
        let fallback: Date
        if win.start == nil {
            // `.all`: anchor at the earliest data day (or today when empty).
            fallback = try earliestDataDay(in: context) ?? today
        } else {
            fallback = today
        }
        return days(in: win, fallbackStart: fallback)
    }

    /// The earliest calendar day that ANY stored data touches — the min over MIT
    /// `createdOn`, focus-session `startedAt`'s day, and `DailyFeeling.day` — or `nil`
    /// when the store is empty. Used to anchor the `.all` axis (ADR-017).
    private func earliestDataDay(in context: ModelContext) throws -> Date? {
        var earliest: Date?
        func consider(_ day: Date) {
            if earliest == nil || day < earliest! { earliest = day }
        }

        var mitDesc = FetchDescriptor<MIT>(sortBy: [SortDescriptor(\.createdOn, order: .forward)])
        mitDesc.fetchLimit = 1
        if let m = try context.fetch(mitDesc).first { consider(m.createdOn) }

        var focusDesc = FetchDescriptor<FocusSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .forward)]
        )
        focusDesc.fetchLimit = 1
        if let f = try context.fetch(focusDesc).first {
            consider(clock.startOfDay(for: f.startedAt))
        }

        var feelingDesc = FetchDescriptor<DailyFeeling>(sortBy: [SortDescriptor(\.day, order: .forward)])
        feelingDesc.fetchLimit = 1
        if let feeling = try context.fetch(feelingDesc).first { consider(feeling.day) }

        return earliest
    }

    // MARK: - Block 1: daily completed-MIT count chart (ADR-006/-017)

    /// A single per-day chart point: a canonical day key and its value.
    public struct DayValue: Sendable, Equatable, Identifiable {
        public let day: Date
        public let value: Int
        public var id: Date { day }
        public init(day: Date, value: Int) {
            self.day = day
            self.value = value
        }
    }

    /// Per-day completed-MIT counts over `range` (ADR-006/-017).
    ///
    /// Each day's count is the EXACT value ``MITService/completedCount(on:in:)`` returns
    /// for that day — the same `completedOn` query Today uses — so the chart bar, the
    /// service count and the KPI component all agree (read-model consistency, ADR-006/
    /// -007). Every day in the range is present (zeros included) so the chart draws a
    /// continuous axis; the empty-range case still yields today's single (zero) bar.
    public func completedByDay(range: Range, in context: ModelContext) throws -> [DayValue] {
        let axis = try axisDays(for: range, in: context)
        var out: [DayValue] = []
        out.reserveCapacity(axis.count)
        for day in axis {
            let count = try mitService.completedCount(on: day, in: context)
            out.append(DayValue(day: day, value: count))
        }
        return out
    }

    // MARK: - Block 2: daily focus-duration chart (ADR-017/-032)

    /// Per-day focus totals (whole seconds) over `range`, split at each midnight and
    /// filtered PER PORTION by the range window (ADR-017/-032).
    ///
    /// Built from ``FocusSessionService/perDayPortions`` so the split matches the T6
    /// aggregation exactly. A session that straddles the range boundary contributes
    /// ONLY its in-range day portions — the out-of-range portions are dropped — which
    /// is precisely why the "total focus" KPI (the sum of these bars) counts only the
    /// in-range portion of a boundary-spanning session (ADR-017/-032). Every day in the
    /// range appears (zeros included) for a continuous axis.
    public func focusSecondsByDay(range: Range, in context: ModelContext) throws -> [DayValue] {
        let win = window(for: range)
        let perDay = try focusPortionsInRange(win, in: context)
        let axis = try axisDays(for: range, in: context)
        return axis.map { DayValue(day: $0, value: perDay[$0] ?? 0) }
    }

    /// The in-range per-day focus portions map (ADR-032): every stored STOPPED
    /// session split per calendar day, keeping only day-portions inside `window`.
    ///
    /// This is the single source both the focus chart and the "total focus" KPI read,
    /// so `KPI == Σ chart bars` by construction (ADR-017). Running (un-stopped)
    /// sessions are excluded by the `endedAt != nil` predicate.
    private func focusPortionsInRange(
        _ window: DayWindow,
        in context: ModelContext
    ) throws -> [Date: Int] {
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.endedAt != nil }
        )
        let stopped = try context.fetch(descriptor)
        var perDay: [Date: Int] = [:]
        for session in stopped {
            guard let endedAt = session.endedAt else { continue }
            let portions = FocusSessionService.perDayPortions(
                startedAt: session.startedAt,
                endedAt: endedAt,
                calendar: clock.calendar
            )
            for (day, seconds) in portions where window.contains(day) {
                perDay[day, default: 0] += seconds
            }
        }
        return perDay
    }

    // MARK: - Block 3: mood/stress trend (ADR-023/-031)

    /// A single day's mood/stress trend point. `mood`/`stress` are `nil` on a day with
    /// no `DailyFeeling` entry — the chart renders those as a GAP, and the average-mood
    /// KPI excludes them (ADR-031).
    public struct MoodPoint: Sendable, Equatable, Identifiable {
        public let day: Date
        public let mood: Int?
        public let stress: Int?
        public var id: Date { day }
        public init(day: Date, mood: Int?, stress: Int?) {
            self.day = day
            self.mood = mood
            self.stress = stress
        }
    }

    /// The mood/stress trend series over `range` (ADR-023/-031).
    ///
    /// One point per axis day; days without a `DailyFeeling` have `mood == nil` and
    /// `stress == nil` so the chart shows a break/gap (ADR-031) rather than plotting a
    /// misleading zero.
    public func moodTrend(range: Range, in context: ModelContext) throws -> [MoodPoint] {
        let win = window(for: range)
        let byDay = try feelingsByDay(win, in: context)
        let axis = try axisDays(for: range, in: context)
        return axis.map { day in
            let feeling = byDay[day]
            return MoodPoint(day: day, mood: feeling?.mood, stress: feeling?.stress)
        }
    }

    /// The average mood over `range`, taken over ONLY days that HAVE a `DailyFeeling`
    /// (missing days EXCLUDED, not counted as 0, ADR-031). `nil` when no day in range
    /// has an entry.
    public func averageMood(range: Range, in context: ModelContext) throws -> Double? {
        let win = window(for: range)
        let byDay = try feelingsByDay(win, in: context)
        let moods = byDay.values.map { $0.mood }
        guard !moods.isEmpty else { return nil }
        return Double(moods.reduce(0, +)) / Double(moods.count)
    }

    /// The `DailyFeeling` rows whose `day` falls in `window`, keyed by day.
    private func feelingsByDay(
        _ window: DayWindow,
        in context: ModelContext
    ) throws -> [Date: DailyFeeling] {
        // `.all` (start == nil) fetches every feeling; a bounded range filters by day.
        let descriptor: FetchDescriptor<DailyFeeling>
        if let start = window.start {
            let end = window.end
            descriptor = FetchDescriptor<DailyFeeling>(
                predicate: #Predicate { $0.day >= start && $0.day <= end }
            )
        } else {
            let end = window.end
            descriptor = FetchDescriptor<DailyFeeling>(
                predicate: #Predicate { $0.day <= end }
            )
        }
        let feelings = try context.fetch(descriptor)
        var byDay: [Date: DailyFeeling] = [:]
        for feeling in feelings { byDay[feeling.day] = feeling }
        return byDay
    }

    // MARK: - Block 4: per-MIT lifecycle timeline (ADR-007/-030)

    /// A contiguous portion of an MIT's lifecycle span. `isGap == true` marks a stretch
    /// during which the MIT was soft-deleted (between `deletedAt` and a later restore,
    /// ADR-030) — rendered as a muted/broken segment so the timeline is honest that the
    /// MIT did NOT roll uninterrupted (ADR-007). A non-gap segment is live rolling.
    public struct TimelineSegment: Sendable, Equatable {
        public let start: Date
        public let end: Date
        public let isGap: Bool
        public init(start: Date, end: Date, isGap: Bool) {
            self.start = start
            self.end = end
            self.isGap = isGap
        }
    }

    /// One MIT's lifecycle row on the timeline (ADR-007).
    public struct TimelineRow: Sendable, Equatable, Identifiable {
        public let id: UUID
        public let text: String
        /// The origin day (`createdOn`) — PRESERVED across a restore (ADR-030).
        public let createdOn: Date
        /// The terminal day: `completedOn` if completed, else today (still open/rolling).
        public let endOn: Date
        /// How many calendar days the MIT spanned created→end (0 = same-day).
        public let daysRolled: Int
        /// Whether the MIT is currently soft-deleted (its span ends at the delete day).
        public let isDeleted: Bool
        /// The contiguous segments (live vs delete-gap) making up the span.
        public let segments: [TimelineSegment]

        public init(
            id: UUID,
            text: String,
            createdOn: Date,
            endOn: Date,
            daysRolled: Int,
            isDeleted: Bool,
            segments: [TimelineSegment]
        ) {
            self.id = id
            self.text = text
            self.createdOn = createdOn
            self.endOn = endOn
            self.daysRolled = daysRolled
            self.isDeleted = isDeleted
            self.segments = segments
        }
    }

    /// The per-MIT lifecycle timeline over `range` (ADR-007/-030).
    ///
    /// Each row spans `createdOn → completedOn` (or `→ today` while still open),
    /// preserving the true origin even across a cross-midnight restore (ADR-030). A
    /// soft-deleted stretch renders as a GAP segment (ADR-007): the span is split into a
    /// live portion up to the delete day and a muted gap from there on, rather than a
    /// single continuous "rolled" bar. Soft-deleted MITs ARE shown (their history is the
    /// point of the timeline) but their span ends at the delete day. Rows are included
    /// when their span overlaps the range window.
    public func timeline(range: Range, in context: ModelContext) throws -> [TimelineRow] {
        let win = window(for: range)
        let today = clock.today()
        // All MITs (including soft-deleted — the timeline is a history view, ADR-007).
        let descriptor = FetchDescriptor<MIT>(
            sortBy: [SortDescriptor(\.createdOn), SortDescriptor(\.id)]
        )
        let all = try context.fetch(descriptor)

        var rows: [TimelineRow] = []
        for mit in all {
            let created = mit.createdOn
            let deletedDay = mit.deletedAt.map { clock.startOfDay(for: $0) }

            // Terminal day (ADR-007): the span runs createdOn → completedOn if completed,
            // else → today. A soft-deleted-but-not-completed MIT still spans to TODAY so
            // the deleted stretch (deletedDay → today) renders as a visible GAP rather
            // than the span silently ending at the delete day (ADR-007/-030).
            let endOn = mit.completedOn ?? today

            // Range overlap: include if the span [created, endOn] intersects the window.
            guard spanOverlaps(created: created, end: endOn, window: win) else { continue }

            let daysRolled = wholeDays(from: created, to: endOn)
            let segments = timelineSegments(
                created: created,
                endOn: endOn,
                deletedDay: (mit.isDeleted ? deletedDay : nil)
            )
            rows.append(TimelineRow(
                id: mit.id,
                text: mit.text,
                createdOn: created,
                endOn: endOn,
                daysRolled: daysRolled,
                isDeleted: mit.isDeleted,
                segments: segments
            ))
        }
        return rows
    }

    /// Build the live/gap segments for one MIT's span (ADR-007/-030).
    ///
    /// With no active soft-delete, the whole span is one live segment. When the MIT is
    /// currently soft-deleted, the span is a live segment `[created, deleteDay]` followed
    /// by a GAP segment `[deleteDay, endOn]` — so the deleted stretch is visibly broken
    /// rather than implying uninterrupted rolling. (A restored MIT is not soft-deleted,
    /// so its gap is not re-derived here; its preserved `createdOn` keeps the origin
    /// honest per ADR-030, and the delete-gap is represented while the delete is active.)
    private func timelineSegments(
        created: Date,
        endOn: Date,
        deletedDay: Date?
    ) -> [TimelineSegment] {
        guard let deletedDay, deletedDay > created, deletedDay < endOn else {
            // Single continuous live segment (no visible gap within the span).
            if let deletedDay, deletedDay <= created {
                // Deleted at/before creation day — whole span is a gap.
                return [TimelineSegment(start: created, end: endOn, isGap: true)]
            }
            return [TimelineSegment(start: created, end: endOn, isGap: false)]
        }
        return [
            TimelineSegment(start: created, end: deletedDay, isGap: false),
            TimelineSegment(start: deletedDay, end: endOn, isGap: true),
        ]
    }

    /// Whole calendar days between two day keys (`to - from`), floored at 0.
    private func wholeDays(from: Date, to: Date) -> Int {
        let comps = clock.calendar.dateComponents([.day], from: from, to: to)
        return max(0, comps.day ?? 0)
    }

    /// Whether the span `[created, end]` intersects the (possibly open-ended) window.
    private func spanOverlaps(created: Date, end: Date, window: DayWindow) -> Bool {
        if end < (window.start ?? .distantPast) { return false }
        if created > window.end { return false }
        return true
    }

    // MARK: - Block 5: KPI cards (ADR-006/-017/-031/-032)

    /// The four Summary KPI cards over a range (ADR-017).
    public struct KPIs: Sendable, Equatable {
        /// Total completed MITs over the range = Σ of the per-day completed counts
        /// (the SAME `completedOn` query as Today, ADR-006).
        public let totalCompleted: Int
        /// Total focus seconds over the range = Σ of the SAME split day-portions the
        /// focus chart draws (KPI == Σ chart bars, ADR-017/-032).
        public let totalFocusSeconds: Int
        /// Current open/rolling count = MITs where `status == open AND !isDeleted`
        /// (regardless of `appearsOn`) — the SAME query as Today's list length
        /// (ADR-017/F8). This is a point-in-time count, independent of the range.
        public let openRollingCount: Int
        /// Mean mood over ONLY days with an entry in range (missing excluded, ADR-031);
        /// `nil` when no day in range has a feeling.
        public let averageMood: Double?

        public init(
            totalCompleted: Int,
            totalFocusSeconds: Int,
            openRollingCount: Int,
            averageMood: Double?
        ) {
            self.totalCompleted = totalCompleted
            self.totalFocusSeconds = totalFocusSeconds
            self.openRollingCount = openRollingCount
            self.averageMood = averageMood
        }
    }

    /// Compute the four KPI cards for `range` (ADR-017).
    ///
    /// - `totalCompleted` sums the same per-day completed counts the chart draws, each
    ///   from ``MITService/completedCount(on:in:)`` (ADR-006).
    /// - `totalFocusSeconds` sums the same in-range split portions the focus chart draws,
    ///   so `KPI == Σ chart bars` and a boundary session counts only its in-range portion
    ///   (ADR-017/-032).
    /// - `openRollingCount` is ``MITService/openRollingCount(in:)`` — the SAME predicate
    ///   behind Today's rolled-in list length (ADR-017/F8).
    /// - `averageMood` excludes missing days (ADR-031).
    public func kpis(range: Range, in context: ModelContext) throws -> KPIs {
        let completed = try completedByDay(range: range, in: context)
        let totalCompleted = completed.reduce(0) { $0 + $1.value }

        let win = window(for: range)
        let focusPortions = try focusPortionsInRange(win, in: context)
        let totalFocus = focusPortions.values.reduce(0, +)

        let openRolling = try mitService.openRollingCount(in: context)
        let avgMood = try averageMood(range: range, in: context)

        return KPIs(
            totalCompleted: totalCompleted,
            totalFocusSeconds: totalFocus,
            openRollingCount: openRolling,
            averageMood: avgMood
        )
    }

    // MARK: - Emptiness (ADR-033)

    /// Whether a brand-new user has NO stored data at all (no MITs, no focus sessions,
    /// no feelings). Drives the Summary "nothing to show yet" empty state (ADR-033) —
    /// the charts still render their axes/frame either way.
    public func hasNoData(in context: ModelContext) throws -> Bool {
        let mitCount = try context.fetchCount(FetchDescriptor<MIT>())
        if mitCount > 0 { return false }
        let focusCount = try context.fetchCount(FetchDescriptor<FocusSession>())
        if focusCount > 0 { return false }
        let feelingCount = try context.fetchCount(FetchDescriptor<DailyFeeling>())
        return feelingCount == 0
    }
}

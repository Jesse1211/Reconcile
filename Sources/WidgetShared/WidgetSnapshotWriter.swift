import Foundation

/// The app-side SINGLE WRITER of the widget snapshot (ADR-042). **T12 owns this
/// writer**; T5 (quote), T6 (focus), and T1 (settings) only INVOKE it at the named
/// transition points — they do NOT compute snapshot logic themselves (DESIGN T12 §2).
///
/// Each method writes exactly ONE slice of the read-only projection and MERGES it
/// into the current snapshot, so writing today's quote never clobbers the running
/// figure and vice-versa. After every write it fires the injected `reload` hook so
/// the app can ask WidgetKit to reload the timeline (ADR-043) — the hook is injected
/// (rather than importing WidgetKit here) so this stays platform-clean and unit-
/// testable, and so the shared-code surface carries NO widget-host dependency.
///
/// The widget extension NEVER constructs or calls this writer (ADR-042: read-only) —
/// it is wired only into the app's flows.
public final class WidgetSnapshotWriter {
    private let store: WidgetSnapshotStore
    /// Supplies the canonical LOCAL `startOfDay` for `day` stamping (ADR-038).
    private let today: () -> Date
    /// Fired after each successful write so the app can reload the widget timeline
    /// (ADR-043). No-op by default (and in tests / shared code).
    private let reload: () -> Void

    /// Create the writer.
    ///
    /// - Parameters:
    ///   - store: the shared container store (defaults to the real App Group store).
    ///   - today: the canonical day-key provider (typically `clock.today`, ADR-038).
    ///   - reload: called after each write to request a widget timeline reload
    ///     (ADR-043). Defaults to a no-op; the app injects `WidgetCenter` reload.
    public init(
        store: WidgetSnapshotStore = AppGroupSnapshotStore(),
        today: @escaping () -> Date = { Calendar.current.startOfDay(for: Date()) },
        reload: @escaping () -> Void = {}
    ) {
        self.store = store
        self.today = today
        self.reload = reload
    }

    /// The current snapshot, or a fresh one stamped for today (ADR-038). Used as the
    /// merge base so each slice write preserves the others.
    private func base() -> WidgetSnapshot {
        store.read() ?? WidgetSnapshot(day: today())
    }

    private func commit(_ snapshot: WidgetSnapshot) {
        var next = snapshot
        next.day = today()
        store.write(next)
        reload()
    }

    // MARK: - Focus transitions (T6 → ADR-042 (a))

    /// A focus session STARTED (T6 start). Records the running `startedAt` so the
    /// widget shows the live self-advancing timer text (ADR-041 running layout /
    /// ADR-043). Preserves the quote + theme slices.
    ///
    /// - Parameter startedAt: the running session's `startedAt`.
    public func focusSessionStarted(startedAt: Date) {
        var snap = base()
        snap.runningStartedAt = startedAt
        commit(snap)
    }

    /// A focus session STOPPED or was DISCARDED (T6 stop/discard). Clears the running
    /// figure and records today's accumulated STOPPED focus seconds — the same
    /// aggregation T6 already computes (ADR-042 (a)). The widget flips to the idle
    /// quote-fills layout (ADR-041), which shows NO time figure.
    ///
    /// - Parameter accumulatedSecondsToday: today's total stopped focus seconds.
    public func focusSessionEnded(accumulatedSecondsToday: Int) {
        var snap = base()
        snap.runningStartedAt = nil
        snap.accumulatedSeconds = accumulatedSecondsToday
        commit(snap)
    }

    // MARK: - Quote transitions (T5 → ADR-042 (b))

    /// Today's resolved quote changed (T5 pick / refresh / scope change). Writes the
    /// resolved `text` + `author` mirroring the app's `TodayScope` + override
    /// resolution (ADR-011/-025/-026). Preserves the focus + theme slices.
    ///
    /// - Parameters:
    ///   - text: today's resolved quote text.
    ///   - author: today's resolved quote author (may be `nil`).
    public func todaysQuoteResolved(text: String, author: String?) {
        var snap = base()
        snap.quoteText = text
        snap.quoteAuthor = author
        commit(snap)
    }

    /// There is NO quote for today (T5 resolved `.empty` — e.g. scope=`mine` with an
    /// empty library, ADR-034). Clears the quote slice so the widget shows the
    /// gentle placeholder (ADR-045), never a blank view. Preserves focus + theme.
    public func todaysQuoteCleared() {
        var snap = base()
        snap.quoteText = nil
        snap.quoteAuthor = nil
        commit(snap)
    }

    // MARK: - Theme transition (T1 → ADR-042 (c) / ADR-044)

    /// The persisted `Theme` changed (T1 settings). Writes its raw value so the Home
    /// widget can render in the selected theme (ADR-044). Preserves quote + focus.
    ///
    /// - Parameter theme: the newly-persisted theme.
    public func themeChanged(_ theme: Theme) {
        var snap = base()
        snap.themeRawValue = theme.rawValue
        commit(snap)
    }
}

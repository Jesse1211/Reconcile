import WidgetKit
import SwiftUI

/// The timeline entry the widget views render (ADR-043). Wraps the read-only
/// ``WidgetSnapshot`` the app wrote; the widget adds NO business logic of its own.
struct ReconcileWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

/// The `TimelineProvider` for both Reconcile widget families (ADR-043).
///
/// It reads the ADR-042 shared snapshot via ``WidgetSnapshotLoader`` — NO business
/// logic, NO network (ADR-043). The RUNNING stopwatch figure is rendered by the
/// views as a self-advancing `Text(startedAt, style: .timer)` so it advances without
/// a per-second tick. The provider still schedules PERIODIC reloads so WidgetKit
/// picks up the coarse transitions the timer text cannot express (ADR-043):
///   * the running → accumulated flip when a session ends (and vice-versa), and
///   * a new day's quote / the accumulated reset at local midnight.
/// It performs NO network fetch — a stale snapshot is refreshed by the app's next
/// write, not by the widget calling ZenQuotes (ADR-043).
struct ReconcileWidgetProvider: TimelineProvider {
    private let loader: WidgetSnapshotLoader

    init(loader: WidgetSnapshotLoader = WidgetSnapshotLoader()) {
        self.loader = loader
    }

    /// The gallery/placeholder entry (ADR-045): a purposeful placeholder, never blank.
    func placeholder(in context: Context) -> ReconcileWidgetEntry {
        ReconcileWidgetEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (ReconcileWidgetEntry) -> Void) {
        completion(ReconcileWidgetEntry(date: Date(), snapshot: loader.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ReconcileWidgetEntry>) -> Void) {
        let now = Date()
        let snapshot = loader.load()
        let entry = ReconcileWidgetEntry(date: now, snapshot: snapshot)

        // ADR-043: schedule the next reload for the coarse state/day transitions the
        // self-advancing timer text cannot express. Reload at the NEXT local midnight
        // (new day's quote + accumulated reset); and, while a session is running,
        // also nudge a periodic reload so a stop that happened while the widget was
        // offscreen flips running → accumulated in bounded time.
        let nextMidnight = Self.nextLocalMidnight(after: now)
        var reloadDate = nextMidnight
        if snapshot?.isRunning == true {
            let periodic = now.addingTimeInterval(15 * 60)   // coarse running nudge
            reloadDate = min(nextMidnight, periodic)
        }

        completion(Timeline(entries: [entry], policy: .after(reloadDate)))
    }

    /// The next local midnight strictly after `date` (ADR-043 day-flip reload).
    private static func nextLocalMidnight(after date: Date) -> Date {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: date)
        return cal.date(byAdding: .day, value: 1, to: startOfToday)
            ?? date.addingTimeInterval(86_400)
    }
}

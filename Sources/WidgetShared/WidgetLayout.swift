import Foundation

/// The two widget layouts (ADR-041), derived PURELY from the snapshot so the choice
/// is unit-testable without a running widget host.
///
///   * `.running` — a `FocusSession` is running: `time │ quote — author` (a divider,
///     the live timer on the left, quote+author on the right).
///   * `.idle` — no running session: the quote FILLS the widget (larger, author
///     beneath), with NO time figure and NO divider.
///   * `.emptyQuote` — no quote yet (ADR-045): the gentle placeholder, never blank.
///
/// Note there is NO "no-focus" empty layout: idleness is simply the quote-only
/// layout (ADR-041/-045) — there is no "0 / no focus" figure to show.
enum WidgetLayout: Equatable {
    case running
    case idle
    case emptyQuote

    /// The layout for a snapshot (or `nil` when the app has written nothing yet).
    ///
    /// Precedence: no quote → `.emptyQuote` (ADR-045) regardless of the focus figure,
    /// because both layouts center the quote and there is nothing to show without it.
    /// Otherwise a running session → `.running`; else `.idle` (ADR-041).
    static func resolve(_ snapshot: WidgetSnapshot?) -> WidgetLayout {
        guard let snapshot, snapshot.hasQuote else { return .emptyQuote }
        return snapshot.isRunning ? .running : .idle
    }
}

/// The empty-state placeholder copy (ADR-045). Kept short for the Lock family.
enum WidgetPlaceholder {
    /// Home Screen copy — the gentle full placeholder (ADR-045).
    static let home = "Open Reconcile to set today's quote"
    /// Lock Screen copy — the same intent, clamped shorter for the tiny surface.
    static let lock = "Open Reconcile to set today's quote"
}

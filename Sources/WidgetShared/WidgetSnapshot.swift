import Foundation

/// The read-only projection the app writes into the App Group container and the
/// widget reads back (ADR-042 / DESIGN §2).
///
/// This is a **read-only projection** of the app's authoritative SwiftData store —
/// NOT an aggregate root and NOT a source of truth. It carries only the three
/// widget-relevant slices of app state:
///
///   * today's resolved quote (`quoteText` + `quoteAuthor`), mirroring the app's
///     `TodayScope` + override resolution (ADR-011/-025/-026) — the widget never
///     re-derives or re-picks;
///   * the focus figure: EITHER a running session's `runningStartedAt` (drives the
///     self-advancing `Text(startedAt, style: .timer)`, ADR-043) OR — when no
///     session is running — today's `accumulatedSeconds` of stopped focus;
///   * the persisted `Theme` raw value (ADR-044), for the Home widget's theming.
///
/// The app is the SINGLE WRITER (ADR-042). The widget NEVER writes this — it has no
/// mutation path (widget-driven start/stop is deferred, OQ-08).
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    /// Today's resolved quote text, or `nil` when there is no quote yet
    /// (e.g. scope=`mine` with an empty library, ADR-034/-045).
    public var quoteText: String?
    /// Today's resolved quote author, or `nil` (anonymous / no quote).
    public var quoteAuthor: String?

    /// The running session's `startedAt` when a `FocusSession` is currently running
    /// (drives the live timer text, ADR-043), or `nil` when idle.
    public var runningStartedAt: Date?
    /// Today's accumulated STOPPED focus seconds. Only meaningful when
    /// `runningStartedAt == nil` (the idle layout does NOT display it — ADR-041 —
    /// but it is carried so the read-model stays complete).
    public var accumulatedSeconds: Int

    /// The persisted `Theme` raw value (ADR-044) for the Home widget's theming.
    /// Defaults to `ledger` when absent.
    public var themeRawValue: String

    /// The canonical LOCAL `startOfDay` this snapshot was written for (ADR-038).
    /// Lets the provider detect a day flip so a stale snapshot from yesterday is not
    /// treated as today's (ADR-043).
    public var day: Date

    public init(
        quoteText: String? = nil,
        quoteAuthor: String? = nil,
        runningStartedAt: Date? = nil,
        accumulatedSeconds: Int = 0,
        themeRawValue: String = Theme.ledger.rawValue,
        day: Date = Date()
    ) {
        self.quoteText = quoteText
        self.quoteAuthor = quoteAuthor
        self.runningStartedAt = runningStartedAt
        self.accumulatedSeconds = accumulatedSeconds
        self.themeRawValue = themeRawValue
        self.day = day
    }

    // MARK: Derived read-model helpers (pure, no business logic)

    /// Whether a focus session is currently running — i.e. the RUNNING layout applies
    /// (time present); otherwise the IDLE quote-fills layout applies (ADR-041).
    public var isRunning: Bool { runningStartedAt != nil }

    /// Whether there is a quote to show. `false` → the empty placeholder (ADR-045).
    public var hasQuote: Bool {
        guard let text = quoteText else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The persisted theme this snapshot was written under (ADR-044), defaulting to
    /// `ledger` if the stored raw value is unrecognized.
    public var theme: Theme { Theme(rawValue: themeRawValue) ?? .ledger }
}

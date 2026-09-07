import SwiftUI
import SwiftData

/// The Timer screen (T9): a standalone count-up stopwatch plus today's saved sessions.
///
/// ## What it shows (ADR-014 / ADR-032 / ADR-033)
/// - A **live stopwatch** whose elapsed is ALWAYS `now − startedAt`, recomputed from
///   the persisted `startedAt` so it survives backgrounding and an app kill (INV-5 /
///   ADR-014). Across midnight it stays a single undivided number — never day-split
///   (ADR-032: the split is an aggregation concern that lives on Summary only).
/// - **start / stop / discard** controls (ADR-014). *There is no true pause*: elapsed
///   is defined as `now − startedAt`, and INV-5 makes the timestamps the sole source
///   of truth, so a running session cannot be "paused" without breaking that invariant.
///   The lifecycle is start → (stop saves | discard drops), matching the T6 service.
/// - The list of **today's saved sessions** as WHOLE records, attributed to a single
///   day by `startedAt`'s calendar day (ADR-032 whole-record divergence).
/// - A purposeful **empty state** ("No sessions yet today") when the list is empty
///   (ADR-033), rendered in both themes.
///
/// ## What it deliberately does NOT show (ADR-032 / E3)
/// The Timer screen presents **NO summed "today total"** — no per-day focus sum. That
/// figure lives on Summary (ADR-017). Because the Timer never displays a day sum, the
/// whole-record-vs-split divergence never surfaces here as a contradiction.
///
/// ## Theming (ADR-022 / ADR-036 / ADR-037)
/// The screen is theme-agnostic: it declares `screenRole = .timer` (the shell applies
/// it via `RootTabView`) and reads every color/font BY ROLE from the `\.theme` token
/// set — no hard-coded color or font. Day Arc paints its midday gradient; Ledger paints
/// flat paper. Both light and dark are supported through the token set.
struct TimerScreen: View {
    @Environment(\.theme) private var tokens
    @Environment(\.clock) private var clock
    @Environment(\.modelContext) private var modelContext

    /// The single currently-running session, if any (drives the live stopwatch).
    @State private var running: FocusSession?
    /// Today's SAVED sessions, whole records, newest-first (ADR-032).
    @State private var todaysSessions: [FocusSession] = []

    private var service: FocusSessionService {
        FocusSessionService(context: modelContext, clock: clock)
    }

    var body: some View {
        ZStack {
            ThemeBackground()

            VStack(spacing: 24) {
                header
                stopwatch
                controls
                sessionList
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onAppear(perform: reload)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 4) {
            Text("TIMER")
                .font(tokens.typography.eyebrow)
                .foregroundStyle(tokens.colors.textMuted)
            Text("Focus")
                .font(tokens.typography.display)
                .foregroundStyle(tokens.colors.textPrimary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Live stopwatch (ADR-014 / ADR-032)

    @ViewBuilder
    private var stopwatch: some View {
        if let running {
            // Live, self-advancing elapsed recomputed from `startedAt` each tick so it
            // survives an app kill/resume and stays a single undivided number across
            // midnight (INV-5 / ADR-032). Driven by the injected clock for testability.
            TimelineView(.periodic(from: clock.now(), by: 1)) { _ in
                Text(TimerScreen.formatElapsed(running.duration(now: clock.now())))
                    .font(tokens.typography.mono)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(tokens.colors.textPrimary)
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("timer.live.elapsed")
            }
        } else {
            Text(TimerScreen.formatElapsed(0))
                .font(tokens.typography.mono)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(tokens.colors.textMuted)
                .accessibilityIdentifier("timer.live.idle")
        }
    }

    // MARK: - Controls (ADR-014): start / stop / discard

    @ViewBuilder
    private var controls: some View {
        if running == nil {
            Button(action: startSession) {
                controlLabel("Start", systemImage: "play.fill", color: tokens.colors.accent)
            }
            .accessibilityIdentifier("timer.control.start")
        } else {
            HStack(spacing: 16) {
                Button(action: stopSession) {
                    controlLabel("Stop", systemImage: "stop.fill", color: tokens.colors.accent)
                }
                .accessibilityIdentifier("timer.control.stop")

                Button(action: discardSession) {
                    controlLabel("Discard", systemImage: "trash", color: tokens.colors.accentCarried)
                }
                .accessibilityIdentifier("timer.control.discard")
            }
        }
    }

    private func controlLabel(_ title: String, systemImage: String, color: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(tokens.typography.title)
            .foregroundStyle(color)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(tokens.colors.surfaceRaised, in: Capsule())
    }

    // MARK: - Today's saved sessions (ADR-032 / ADR-033)
    //
    // WHOLE records attributed by `startedAt`'s day. NO summed "today total" is shown
    // (ADR-032/E3) — this list is the ONLY per-session content; the per-day focus sum
    // lives on Summary (ADR-017).

    @ViewBuilder
    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's sessions")
                .font(tokens.typography.title)
                .foregroundStyle(tokens.colors.textPrimary)

            if todaysSessions.isEmpty {
                // Purposeful empty state (ADR-033), rendered in both themes.
                Text("No sessions yet today")
                    .font(tokens.typography.body)
                    .foregroundStyle(tokens.colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("timer.sessions.empty")
            } else {
                VStack(spacing: 8) {
                    ForEach(todaysSessions) { session in
                        sessionRow(session)
                    }
                }
                .accessibilityIdentifier("timer.sessions.list")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sessionRow(_ session: FocusSession) -> some View {
        HStack {
            // Whole-record duration (never day-split, ADR-032). A stopped session's
            // duration is timestamp-derived (`endedAt − startedAt`, INV-5).
            Text(TimerScreen.formatElapsed(session.duration(now: clock.now())))
                .font(tokens.typography.mono)
                .monospacedDigit()
                .foregroundStyle(tokens.colors.textPrimary)
            Spacer()
            Text(session.startedAt, style: .time)
                .font(tokens.typography.body)
                .foregroundStyle(tokens.colors.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(tokens.colors.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Actions

    private func startSession() {
        running = try? service.start()
        reload()
    }

    private func stopSession() {
        if let running { try? service.stop(running) }
        running = nil
        reload()
    }

    private func discardSession() {
        if let running { try? service.discard(running) }
        running = nil
        reload()
    }

    /// Re-read the running session and today's saved list from the store. Called on
    /// appear and after every lifecycle action so the view reflects the persisted
    /// state (which is what survives a kill/resume, INV-5).
    private func reload() {
        running = try? service.runningSession()
        todaysSessions = (try? service.todaysSessions()) ?? []
    }

    // MARK: - Formatting

    /// Format whole seconds as `H:MM:SS` (hours shown only when non-zero) — a single
    /// undivided elapsed figure. This is a per-session / live-stopwatch figure ONLY;
    /// the screen never sums these into a "today total" (ADR-032/E3).
    static func formatElapsed(_ totalSeconds: Int) -> String {
        let seconds = max(0, totalSeconds)
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

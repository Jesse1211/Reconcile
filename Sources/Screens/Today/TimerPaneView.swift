import SwiftUI
import SwiftData

/// The Timer PANE — the stopwatch + today's-session content, WITHOUT its own background,
/// header eyebrow, or page chrome. It is the second page of the Today screen's lower
/// horizontal pager (the first page is Feeling + the MIT list). The daily quote card lives
/// ABOVE the pager and is shared/unchanged across the swipe, so switching tasks ↔ timer
/// never re-renders the quote.
///
/// Behaviour is unchanged from the former standalone `TimerScreen` (T9 / ADR-014 / ADR-032):
/// a live count-up stopwatch (`now − startedAt`, INV-5), start/stop/discard, and today's
/// saved-session list as WHOLE records — NO summed "today total" (ADR-032/E3). It reads the
/// injected `widgetWriter` so focus start/stop mirrors the running/accumulated figure to the
/// widget (ADR-042). Theme-agnostic: reads every color/font by role from `\.theme`.
struct TimerPaneView: View {
    @Environment(\.theme) private var tokens
    @Environment(\.clock) private var clock
    @Environment(\.modelContext) private var modelContext
    @Environment(\.widgetSnapshotWriter) private var widgetWriter

    /// The single currently-running session, if any (drives the live stopwatch).
    @State private var running: FocusSession?
    /// Today's SAVED sessions, whole records, newest-first (ADR-032).
    @State private var todaysSessions: [FocusSession] = []

    private var service: FocusSessionService {
        FocusSessionService(context: modelContext, clock: clock, widgetWriter: widgetWriter)
    }

    var body: some View {
        VStack(spacing: 24) {
            stopwatch
            controls
            sessionList
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .onAppear(perform: reload)
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
                controlLabel("Start", systemImage: "play.fill", color: tokens.colors.accentOnBackground)
            }
            .accessibilityIdentifier("timer.control.start")
        } else {
            HStack(spacing: 16) {
                Button(action: stopSession) {
                    controlLabel("Stop", systemImage: "stop.fill", color: tokens.colors.accentOnBackground)
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
        // No "Today's sessions" header and no empty-state line (owner tweak): when there
        // are no saved sessions, show nothing; otherwise just the record list.
        if !todaysSessions.isEmpty {
            VStack(spacing: 8) {
                ForEach(todaysSessions) { session in
                    sessionRow(session)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("timer.sessions.list")
        }
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
}

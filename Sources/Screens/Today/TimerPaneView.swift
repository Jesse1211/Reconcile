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
    /// Today's total finished (stopped) focus seconds. The "Today · <total>" line adds
    /// the live running-session seconds on top of this (ADR-048b).
    @State private var savedSecondsToday: Int = 0
    /// Drives the ring's continuous rotation while a session runs. Toggled to `true`
    /// under a repeating linear animation when running; reset when idle.
    @State private var spinning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var service: FocusSessionService {
        FocusSessionService(context: modelContext, clock: clock, widgetWriter: widgetWriter)
    }

    var body: some View {
        VStack(spacing: 24) {
            tapTimer
            sessionList
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .onAppear {
            reload()
            syncSpin()
        }
    }

    /// Start or stop the ring's continuous rotation to match the running state.
    private func syncSpin() {
        if running != nil && !reduceMotion {
            spinning = false
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                spinning = true
            }
        } else {
            withAnimation(.linear(duration: 0.2)) { spinning = false }
        }
    }

    // MARK: - Ring dial + today's total (ADR-048b — revises ADR-032/E3)
    //
    // Design: the elapsed figure sits inside a circular ring that IS the control — tap
    // inside the ring to start a session, tap again to stop (which saves it). The ring
    // SPINS while running (a live "focusing" cue) and is static/quiet when idle. No cue
    // text, no discard. Above it, a quiet "Today · <total>" line shows today's total
    // focus = finished sessions + the running session, ticking live (ADR-048b).

    /// Dimensions of the ring dial.
    private let ringSize: CGFloat = 200
    private let ringWidth: CGFloat = 3

    @ViewBuilder
    private var tapTimer: some View {
        // PERF: the per-second tick runs ONLY while a session is running. When idle the
        // figure is a static 0:00, so there is no every-second view rebuild competing
        // with the pager swipe (that constant idle tick was the swipe-lag cause).
        if running != nil {
            TimelineView(.periodic(from: clock.now(), by: 1)) { _ in
                dialContent(sessionSeconds: running?.duration(now: clock.now()) ?? 0)
            }
            .frame(maxWidth: .infinity)
        } else {
            dialContent(sessionSeconds: 0)
                .frame(maxWidth: .infinity)
        }
    }

    /// The total line + ring dial. `sessionSeconds` is the live figure while running, or 0.
    private func dialContent(sessionSeconds: Int) -> some View {
        let totalSeconds = savedSecondsToday + sessionSeconds
        return VStack(spacing: 28) {
            // Today's total — quiet mono header (finished + running, ADR-048b).
            Text("Today · \(TimerScreen.formatElapsed(totalSeconds))")
                .font(tokens.typography.mono)
                .monospacedDigit()
                .foregroundStyle(tokens.colors.textMuted)
                .accessibilityIdentifier("timer.today.total")

            // The ring dial — tap inside to start/stop; spins while running.
            Button(action: toggleSession) {
                ZStack {
                    // Faint full track.
                    Circle()
                        .stroke(tokens.colors.divider, lineWidth: ringWidth)

                    // Spinning accent arc — only present/animated while running.
                    if running != nil {
                        Circle()
                            .trim(from: 0, to: 0.28)
                            .stroke(
                                tokens.colors.accentOnBackground,
                                style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                            )
                            .rotationEffect(.degrees(spinning ? 360 : 0))
                    }

                    Text(TimerScreen.formatElapsed(sessionSeconds))
                        .font(tokens.typography.display)
                        .monospacedDigit()
                        .foregroundStyle(running == nil ? tokens.colors.textMuted : tokens.colors.textPrimary)
                        .contentTransition(.numericText())
                }
                .frame(width: ringSize, height: ringSize)
                .contentShape(Circle())
            }
            .buttonStyle(RingPressStyle())
            .accessibilityIdentifier(running == nil ? "timer.control.start" : "timer.control.stop")
            .accessibilityLabel(running == nil ? "Start focus" : "Stop focus")
        }
    }

    /// Tap the time: start a session if idle, stop (save) if running.
    private func toggleSession() {
        if running == nil { startSession() } else { stopSession() }
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
        syncSpin()
    }

    private func stopSession() {
        // Tapping the ring while running stops AND saves the session (no discard path
        // in this UI, owner tweak — the ring is start/stop only).
        if let running { try? service.stop(running) }
        running = nil
        reload()
        syncSpin()
    }

    /// Re-read the running session and today's saved list from the store. Called on
    /// appear and after every lifecycle action so the view reflects the persisted
    /// state (which is what survives a kill/resume, INV-5).
    private func reload() {
        running = try? service.runningSession()
        todaysSessions = (try? service.todaysSessions()) ?? []
        // Today's finished total (running session excluded here; the live view adds it).
        savedSecondsToday = service.todaysAccumulatedSeconds()
    }
}

/// Press feedback for the ring dial: a clear dip in scale + opacity on touch-down so a
/// tap reads unmistakably (the previous plain-button feedback was too subtle, owner
/// tweak). Suppressed under Reduce Motion via the shorter/again-still transition.
private struct RingPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

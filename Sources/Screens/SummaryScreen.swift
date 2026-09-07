import SwiftUI
import SwiftData
import Charts

/// The single Summary screen (T10 / ADR-007 / ADR-017 / ADR-023).
///
/// Aggregates all stored data by calendar day into five blocks, all driven by the pure
/// ``SummaryService`` read-model so the numbers stay consistent with Today (ADR-006/
/// -007/-017):
///   1. daily completed-MIT count chart (ADR-006/-017);
///   2. daily total focus-duration chart, split at midnight per portion (ADR-017/-032);
///   3. mood/stress trend chart, with gaps for days without a feeling (ADR-023/-031);
///   4. per-MIT lifecycle timeline, with a muted GAP for a soft-deleted stretch
///      (ADR-007/-030);
///   5. KPI cards (total completed, total focus, open/rolling, average mood, ADR-017/-031).
///
/// A Week / Month / All range switcher (ADR-017) re-aggregates every block. The screen
/// is theme-agnostic: it declares `screenRole == .summary` (ADR-037, set by the shell)
/// and reads ALL colors/fonts by role from the `\.theme` token set (ADR-036) — never a
/// hard-coded color or font — so it renders correctly under both themes (ADR-022). Even
/// for a brand-new user the charts render their axes/frame with a "nothing to show yet"
/// state rather than disappearing (ADR-033).
public struct SummaryScreen: View {
    @Environment(\.theme) private var tokens
    @Environment(\.modelContext) private var modelContext
    /// The injectable clock (ADR-038), read from the environment so day math and the
    /// range window are deterministic; tests inject a `TestClock`.
    @Environment(\.clock) private var clock

    @State private var range: SummaryService.Range = .week
    @State private var model: SummaryViewModel = .empty

    public init() {}

    public var body: some View {
        ZStack {
            ThemeBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    rangeSwitcher

                    if model.hasNoData {
                        emptyBanner
                    }

                    kpiCards
                    completedChart
                    focusChart
                    moodChart
                    timelineBlock
                }
                .padding(20)
            }
        }
        .onAppear(perform: reload)
        .onChange(of: range) { _, _ in reload() }
    }

    // MARK: - Header & range switcher

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SUMMARY")
                .font(tokens.typography.eyebrow)
                .foregroundStyle(tokens.colors.textMuted)
            Text("Summary")
                .font(tokens.typography.display)
                .foregroundStyle(tokens.colors.textPrimary)
        }
    }

    private var rangeSwitcher: some View {
        HStack(spacing: 8) {
            ForEach(SummaryService.Range.allCases, id: \.self) { option in
                Button {
                    range = option
                } label: {
                    Text(option.displayName)
                        .font(tokens.typography.body)
                        .foregroundStyle(
                            option == range ? tokens.colors.background : tokens.colors.textSecondary
                        )
                        .padding(.vertical, 6)
                        .padding(.horizontal, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(option == range ? tokens.colors.accent : tokens.colors.surface)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(option == range ? [.isSelected] : [])
            }
        }
        .accessibilityIdentifier("summary.rangeSwitcher")
    }

    private var emptyBanner: some View {
        Text("Nothing to show yet — complete an MIT, run the timer, or log how you feel.")
            .font(tokens.typography.body)
            .foregroundStyle(tokens.colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tokens.colors.surface)
            )
            .accessibilityIdentifier("summary.emptyState")
    }

    // MARK: - Block 5: KPI cards

    private var kpiCards: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            kpiCard(title: "Completed MITs", value: "\(model.kpis.totalCompleted)")
            kpiCard(title: "Focus time", value: Self.formatDuration(model.kpis.totalFocusSeconds))
            kpiCard(title: "Open / rolling", value: "\(model.kpis.openRollingCount)")
            kpiCard(title: "Average mood", value: Self.formatMood(model.kpis.averageMood))
        }
        .accessibilityIdentifier("summary.kpis")
    }

    private func kpiCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(tokens.typography.eyebrow)
                .foregroundStyle(tokens.colors.textMuted)
            Text(value)
                .font(tokens.typography.title)
                .foregroundStyle(tokens.colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tokens.colors.surfaceRaised)
        )
    }

    // MARK: - Block 1: completed-MIT chart

    private var completedChart: some View {
        chartCard(title: "Completed MITs per day") {
            Chart(model.completedByDay) { point in
                BarMark(
                    x: .value("Day", point.day, unit: .day),
                    y: .value("Completed", point.value)
                )
                .foregroundStyle(tokens.colors.accent)
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 160)
            .accessibilityIdentifier("summary.completedChart")
        }
    }

    // MARK: - Block 2: focus-duration chart

    private var focusChart: some View {
        chartCard(title: "Focus time per day") {
            Chart(model.focusByDay) { point in
                BarMark(
                    x: .value("Day", point.day, unit: .day),
                    y: .value("Minutes", Double(point.value) / 60.0)
                )
                .foregroundStyle(tokens.colors.accent)
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 160)
            .accessibilityIdentifier("summary.focusChart")
        }
    }

    // MARK: - Block 3: mood/stress trend

    private var moodChart: some View {
        chartCard(title: "Mood & stress trend") {
            Chart {
                // Only plot days that HAVE a value, so the line breaks over gap days
                // (missing feelings, ADR-031) instead of dropping to zero.
                ForEach(model.moodTrend) { point in
                    if let mood = point.mood {
                        LineMark(
                            x: .value("Day", point.day, unit: .day),
                            y: .value("Mood", mood),
                            series: .value("Series", "Mood")
                        )
                        .foregroundStyle(tokens.colors.accent)
                        PointMark(
                            x: .value("Day", point.day, unit: .day),
                            y: .value("Mood", mood)
                        )
                        .foregroundStyle(tokens.colors.accent)
                    }
                    if let stress = point.stress {
                        LineMark(
                            x: .value("Day", point.day, unit: .day),
                            y: .value("Stress", stress),
                            series: .value("Series", "Stress")
                        )
                        .foregroundStyle(tokens.colors.accentCarried)
                    }
                }
            }
            .chartYScale(domain: 0...5)
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 160)
            .accessibilityIdentifier("summary.moodChart")
        }
    }

    // MARK: - Block 4: per-MIT lifecycle timeline

    private var timelineBlock: some View {
        chartCard(title: "MIT lifecycle") {
            if model.timeline.isEmpty {
                Text("No MITs in this range yet.")
                    .font(tokens.typography.body)
                    .foregroundStyle(tokens.colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("summary.timeline")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(model.timeline, id: \.id) { row in
                        timelineRow(row)
                    }
                }
                .accessibilityIdentifier("summary.timeline")
            }
        }
    }

    private func timelineRow(_ row: SummaryService.TimelineRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.text)
                .font(tokens.typography.body)
                .foregroundStyle(tokens.colors.textPrimary)
                .lineLimit(1)
            GeometryReader { geo in
                timelineBar(row, width: geo.size.width)
            }
            .frame(height: 10)
            Text("\(row.daysRolled) day\(row.daysRolled == 1 ? "" : "s") rolled")
                .font(tokens.typography.eyebrow)
                .foregroundStyle(tokens.colors.textMuted)
        }
    }

    /// Render a lifecycle span as a horizontal bar; a soft-deleted stretch is drawn as
    /// a muted GAP segment (ADR-007/-030), not continuous rolling.
    private func timelineBar(_ row: SummaryService.TimelineRow, width: CGFloat) -> some View {
        let total = max(1.0, row.endOn.timeIntervalSince(row.createdOn))
        return HStack(spacing: 0) {
            ForEach(Array(row.segments.enumerated()), id: \.offset) { _, seg in
                let frac = max(0, seg.end.timeIntervalSince(seg.start)) / total
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(seg.isGap ? tokens.colors.divider : tokens.colors.accent)
                    .opacity(seg.isGap ? 0.4 : 1.0)
                    .frame(width: max(2, width * CGFloat(frac)))
            }
        }
    }

    // MARK: - Chart card chrome

    @ViewBuilder
    private func chartCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(tokens.typography.title)
                .foregroundStyle(tokens.colors.textPrimary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tokens.colors.surface)
        )
    }

    // MARK: - Data load

    private func reload() {
        let service = SummaryService(clock: clock)
        do {
            model = try SummaryViewModel(
                completedByDay: service.completedByDay(range: range, in: modelContext),
                focusByDay: service.focusSecondsByDay(range: range, in: modelContext),
                moodTrend: service.moodTrend(range: range, in: modelContext),
                timeline: service.timeline(range: range, in: modelContext),
                kpis: service.kpis(range: range, in: modelContext),
                hasNoData: service.hasNoData(in: modelContext)
            )
        } catch {
            model = .empty
        }
    }

    // MARK: - Formatting

    static func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    static func formatMood(_ mood: Double?) -> String {
        guard let mood else { return "—" }
        return String(format: "%.1f", mood)
    }
}

/// A snapshot of every Summary block, computed off the SwiftData context and rendered by
/// ``SummaryScreen``. Keeping the view's state in one value keeps the render path free of
/// per-frame fetches.
struct SummaryViewModel: Equatable {
    let completedByDay: [SummaryService.DayValue]
    let focusByDay: [SummaryService.DayValue]
    let moodTrend: [SummaryService.MoodPoint]
    let timeline: [SummaryService.TimelineRow]
    let kpis: SummaryService.KPIs
    let hasNoData: Bool

    static let empty = SummaryViewModel(
        completedByDay: [],
        focusByDay: [],
        moodTrend: [],
        timeline: [],
        kpis: SummaryService.KPIs(
            totalCompleted: 0,
            totalFocusSeconds: 0,
            openRollingCount: 0,
            averageMood: nil
        ),
        hasNoData: true
    )
}

import SwiftUI
import WidgetKit

/// The `.accessoryRectangular` Lock Screen widget view (ADR-041/-044).
///
/// Mirrors the two Home layouts (ADR-041) but for the tiny lock surface: the quote
/// is CLAMPED/truncated to fit, and the treatment is THEME-NEUTRAL and legible under
/// the OS tint/monochrome rendering mode (ADR-044) — it does NOT read the persisted
/// theme; legibility under system tint wins.
///
///   * RUNNING — `time │ quote` (a divider; live timer left; short quote right).
///   * IDLE — quote-only (no time, no divider).
///   * EMPTY-QUOTE — short placeholder (ADR-045).
///
/// NO field labels, NO status word/dot, NO brand mark (ADR-041).
struct LockWidgetView: View {
    let snapshot: WidgetSnapshot?

    private var layout: WidgetLayout { WidgetLayout.resolve(snapshot) }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            // Theme-neutral: no explicit colors — inherit the system tint (ADR-044).
            .containerBackground(.clear, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        switch layout {
        case .running:
            runningLayout
        case .idle:
            idleLayout
        case .emptyQuote:
            emptyLayout
        }
    }

    // RUNNING (ADR-041): time │ quote. Fills the whole rectangle — the quote column
    // stretches to the full height, and its text scales up to use the space.
    @ViewBuilder
    private var runningLayout: some View {
        HStack(alignment: .center, spacing: 6) {
            if let startedAt = snapshot?.runningStartedAt {
                Text(startedAt, style: .timer)
                    .font(.system(.body, design: .monospaced))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .frame(minWidth: 40, alignment: .leading)
            }
            Rectangle()
                .fill(.secondary)
                .frame(width: 1)
            Text(snapshot?.quoteText ?? "")
                .font(.body)                // larger base; scales down only if needed
                .lineLimit(4)
                .minimumScaleFactor(0.4)    // shrink-to-fit; long quotes still fit
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // IDLE (ADR-041): quote-only, no time, no divider. Fills the whole rectangle —
    // a short quote goes large, a long one shrinks; vertically centred, no wasted space.
    @ViewBuilder
    private var idleLayout: some View {
        Text(snapshot?.quoteText ?? "")
            .font(.body)                     // larger base font (was .footnote)
            .lineLimit(5)                    // more lines allowed before clamping
            .minimumScaleFactor(0.35)        // shrink hard before clipping
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // EMPTY (ADR-045): short placeholder, never blank.
    @ViewBuilder
    private var emptyLayout: some View {
        Text(WidgetPlaceholder.lock)
            .font(.body)
            .lineLimit(2)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

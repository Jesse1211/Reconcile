import SwiftUI
import WidgetKit

/// The `.accessoryRectangular` Lock Screen widget view (ADR-041/-044).
///
/// Mirrors the two Home layouts (ADR-041) but for the tiny lock surface: the quote
/// is CLAMPED/truncated to fit, and the treatment is THEME-NEUTRAL and legible under
/// the OS tint/monochrome rendering mode (ADR-044) — it does NOT read the persisted
/// theme and paints NO Day-Arc gradient; legibility under system tint wins.
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

    // RUNNING (ADR-041): time │ quote (quote clamped).
    @ViewBuilder
    private var runningLayout: some View {
        HStack(alignment: .center, spacing: 6) {
            if let startedAt = snapshot?.runningStartedAt {
                Text(startedAt, style: .timer)
                    .font(.system(.footnote, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(minWidth: 40, alignment: .leading)
            }
            Rectangle()
                .fill(.secondary)
                .frame(width: 1)
            Text(snapshot?.quoteText ?? "")
                .font(.footnote)
                .lineLimit(2)               // clamped for the lock surface (ADR-041)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // IDLE (ADR-041): quote-only, no time, no divider.
    @ViewBuilder
    private var idleLayout: some View {
        Text(snapshot?.quoteText ?? "")
            .font(.footnote)
            .lineLimit(3)                    // clamped for the lock surface (ADR-041)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // EMPTY (ADR-045): short placeholder, never blank.
    @ViewBuilder
    private var emptyLayout: some View {
        Text(WidgetPlaceholder.lock)
            .font(.footnote)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

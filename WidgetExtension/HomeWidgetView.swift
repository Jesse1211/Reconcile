import SwiftUI
import WidgetKit

/// The `.systemMedium` Home Screen widget view (ADR-041/-044).
///
/// Two layouts (ADR-041), driven by ``WidgetLayout``:
///   * RUNNING — `time │ quote — author`: the live self-advancing
///     `Text(startedAt, style: .timer)` on the LEFT, a divider, the quote + author
///     on the RIGHT.
///   * IDLE — the quote FILLS the widget (larger), author beneath, NO time, NO
///     divider.
///   * EMPTY-QUOTE — the gentle placeholder (ADR-045), never blank.
///
/// Themed per the persisted `Theme` (ADR-044). NO field labels, NO status word/dot,
/// NO brand mark in any layout (ADR-041).
struct HomeWidgetView: View {
    let snapshot: WidgetSnapshot?

    private var theme: Theme { snapshot?.theme ?? .ledger }
    private var palette: WidgetTheme { WidgetTheme.home(for: theme) }
    private var layout: WidgetLayout { WidgetLayout.resolve(snapshot) }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(palette.background, for: .widget)
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

    // RUNNING (ADR-041): time │ quote — author.
    @ViewBuilder
    private var runningLayout: some View {
        HStack(alignment: .center, spacing: 12) {
            if let startedAt = snapshot?.runningStartedAt {
                // Live, self-advancing figure (ADR-043) — no per-second reload.
                Text(startedAt, style: .timer)
                    .font(.system(.title2, design: .monospaced))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(minWidth: 64, alignment: .leading)
            }

            Rectangle()
                .fill(palette.divider)
                .frame(width: 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot?.quoteText ?? "")
                    .font(.system(.callout, design: .serif))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(4)
                    .minimumScaleFactor(0.7)
                if let author = snapshot?.quoteAuthor, !author.isEmpty {
                    Text("— \(author)")
                        .font(.system(.caption, design: .serif))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // IDLE (ADR-041): quote fills the widget, larger; author beneath; NO time/divider.
    @ViewBuilder
    private var idleLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer(minLength: 0)
            Text(snapshot?.quoteText ?? "")
                .font(.system(.title3, design: .serif))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(5)
                .minimumScaleFactor(0.6)
            if let author = snapshot?.quoteAuthor, !author.isEmpty {
                Text("— \(author)")
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // EMPTY (ADR-045): gentle placeholder, never blank.
    @ViewBuilder
    private var emptyLayout: some View {
        VStack(alignment: .leading, spacing: 4) {
            Spacer(minLength: 0)
            Text(WidgetPlaceholder.home)
                .font(.system(.body, design: .serif))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

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
            // Inner margin so text never crowds the widget edge (owner tweak). The
            // adaptive quote sizing (below) measures against this padded area, so it
            // fills the surface WITHOUT touching the rim.
            .padding(16)
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
                // Adaptive: picks the largest font size that fits the (narrower)
                // running-layout column without truncating; long quotes shrink.
                AdaptiveQuoteText(
                    text: snapshot?.quoteText ?? "",
                    sizes: [21, 18, 16, 14, 12, 10],
                    color: palette.textPrimary
                )
                if let author = snapshot?.quoteAuthor, !author.isEmpty {
                    Text("— \(author)")
                        // Author kept deliberately SMALL so the quote is the hero (owner tweak).
                        .font(.system(size: 10, design: .serif))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        // Author right-aligned (quote stays left) per owner tweak.
                        .frame(maxWidth: .infinity, alignment: .trailing)
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
            // Adaptive: the quote owns the whole surface when idle, so it can go
            // large for a short quote and shrink for a long one — never truncated.
            AdaptiveQuoteText(
                text: snapshot?.quoteText ?? "",
                sizes: [32, 28, 24, 21, 18, 15],
                color: palette.textPrimary
            )
            if let author = snapshot?.quoteAuthor, !author.isEmpty {
                Text("— \(author)")
                    // Author kept deliberately SMALL so the quote is the hero (owner tweak).
                    .font(.system(size: 12, design: .serif))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                    // Author right-aligned (quote stays left) per owner tweak.
                    .frame(maxWidth: .infinity, alignment: .trailing)
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

/// A serif quote label that auto-sizes to FILL the available space without being
/// truncated (owner tweak): short quotes render large, long quotes shrink.
///
/// `ViewThatFits` tries each size in `sizes` (largest → smallest) and renders the
/// FIRST one whose fully-wrapped text fits the offered area; because each candidate
/// has NO `lineLimit`, it wraps freely and "fits" means "no vertical overflow". The
/// smallest candidate carries a `minimumScaleFactor` as a final safety net so an
/// extreme-length quote still shrinks-to-fit rather than clipping.
private struct AdaptiveQuoteText: View {
    let text: String
    /// Candidate point sizes, LARGEST first.
    let sizes: [CGFloat]
    let color: Color

    var body: some View {
        ViewThatFits(in: .vertical) {
            ForEach(Array(sizes.enumerated()), id: \.offset) { index, size in
                Text(text)
                    .font(.system(size: size, design: .serif))
                    .foregroundStyle(color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Only the smallest candidate scales further, so nothing ever clips.
                    .minimumScaleFactor(index == sizes.count - 1 ? 0.5 : 1.0)
            }
        }
    }
}

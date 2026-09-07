import SwiftUI

/// Today's quote area (ADR-011/-013/-025/-027/-033/-034).
///
/// Renders one of four states — loading, quote, guiding-empty (`mine`), error+retry
/// (`online`) — with a source indicator, a ♡ save control (ADR-010) and a ↻ refresh
/// control (ADR-025) that is disabled for a degenerate `mine` pool (ADR-027). All
/// styling is read by role from the `\.theme` tokens (ADR-036); no hard-coded styling.
struct TodayQuoteCard: View {
    @Environment(\.theme) private var tokens
    @ObservedObject var model: TodayViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
        }
        .padding(20)
        .background(tokens.colors.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Header — source indicator + controls (ADR-010/-025/-027)

    private var header: some View {
        HStack {
            Text(TodayCopy.sourceIndicator(for: model.scope).uppercased())
                .font(tokens.typography.eyebrow)
                .foregroundStyle(tokens.colors.textMuted)
                .accessibilityIdentifier("quote.source")
            Spacer()
            controls
        }
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 16) {
            // ♡ save — only meaningful for a transient online quote (ADR-010).
            if model.canLikeCurrentQuote || model.currentQuoteIsSaved {
                Button {
                    Task { await model.likeCurrentQuote() }
                } label: {
                    Image(systemName: model.currentQuoteIsSaved ? "heart.fill" : "heart")
                        .foregroundStyle(tokens.colors.accent)
                }
                .disabled(!model.canLikeCurrentQuote)
                .accessibilityIdentifier("quote.like")
            }

            // ↻ refresh — disabled on a degenerate mine pool (ADR-027).
            Button {
                Task { await model.refreshQuote() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(model.refreshDisabled ? tokens.colors.textMuted : tokens.colors.accent)
            }
            .disabled(model.refreshDisabled)
            .accessibilityIdentifier("quote.refresh")
        }
    }

    // MARK: Content — the four states (ADR-013/-033/-034)

    @ViewBuilder
    private var content: some View {
        switch model.quoteState {
        case .loading:
            ProgressView()
                .tint(tokens.colors.accent)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
                .accessibilityIdentifier("quote.loading")

        case .quote(let resolved):
            VStack(alignment: .leading, spacing: 8) {
                Text(resolved.text)
                    .font(tokens.typography.title)
                    .foregroundStyle(tokens.colors.textPrimary)
                if let author = resolved.author, !author.isEmpty {
                    Text("— \(author)")
                        .font(tokens.typography.body)
                        .foregroundStyle(tokens.colors.textSecondary)
                }
            }
            .accessibilityIdentifier("quote.text")

        case .empty:
            // Guiding empty state — mine + empty pool (ADR-033/-034). Not an error.
            Text(TodayCopy.mineEmptyGuidance)
                .font(tokens.typography.body)
                .foregroundStyle(tokens.colors.textSecondary)
                .accessibilityIdentifier("quote.empty")

        case .error(let err):
            // online failure → error + retry (ADR-013). No local fallback.
            VStack(alignment: .leading, spacing: 12) {
                Text(TodayCopy.onlineError(err))
                    .font(tokens.typography.body)
                    .foregroundStyle(tokens.colors.textSecondary)
                Button {
                    Task { await model.retryQuote() }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(tokens.typography.body)
                        .foregroundStyle(tokens.colors.accent)
                }
                .accessibilityIdentifier("quote.retry")
            }
            .accessibilityIdentifier("quote.error")
        }
    }
}

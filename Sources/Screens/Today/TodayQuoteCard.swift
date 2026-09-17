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

    /// Confirm dialog before UN-SAVING (removing) the current quote — required for ANY
    /// un-save, in either source (owner decision).
    @State private var showRemoveConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
        }
        .padding(20)
        .background(tokens.colors.surface, in: RoundedRectangle(cornerRadius: 16))
        .alert("Remove from saved?", isPresented: $showRemoveConfirm) {
            Button("Remove", role: .destructive) {
                Task { await model.removeCurrentSavedQuote() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This quote will be removed from your library.")
        }
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
            // ♥ heart. If the current quote is SAVED (either source), tapping UN-SAVES it
            // — but that ALWAYS goes through a confirm dialog (owner decision). If it's an
            // unsaved transient online quote, tapping SAVES it directly (no confirm needed —
            // adding is not destructive, ADR-010).
            if model.currentQuoteIsSaved {
                Button {
                    showRemoveConfirm = true
                } label: {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(tokens.colors.likedAccent)
                }
                .accessibilityLabel("Remove from saved")
                .accessibilityIdentifier("quote.unsave")
            } else if model.canLikeCurrentQuote {
                Button {
                    Task { await model.likeCurrentQuote() }
                } label: {
                    Image(systemName: "heart")
                        .foregroundStyle(tokens.colors.accentOnBackground)
                }
                .accessibilityLabel("Save quote")
                .accessibilityIdentifier("quote.like")
            }

            // ↻ refresh — disabled on a degenerate mine pool (ADR-027).
            Button {
                Task { await model.refreshQuote() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(model.refreshDisabled ? tokens.colors.textMuted : tokens.colors.accentOnBackground)
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
                .tint(tokens.colors.accentOnBackground)
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
                        .foregroundStyle(tokens.colors.accentOnBackground)
                }
                .accessibilityIdentifier("quote.retry")
            }
            .accessibilityIdentifier("quote.error")
        }
    }
}

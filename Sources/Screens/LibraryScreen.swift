import SwiftUI
import SwiftData

/// The Library screen (T8): the personal quote library.
///
/// Cited ADRs: ADR-009/-010 (two sources; like = persist; user entry goes straight in),
/// ADR-011 (`mine` pool = `source == user OR liked == true`), ADR-012 (browse-online-and-
/// like uses ZenQuotes `/random`), ADR-033 (purposeful empty state, both themes), ADR-035/
/// ADR-039 (source-dependent delete / un-like), ADR-040 (the source picker WRITES the
/// persisted current `TodayScope`).
///
/// Theme-agnostic (ADR-036/-037): declares `screenRole == .library` and reads every color/
/// font BY ROLE from the `\.theme` token set — no hard-coded color or font. Day Arc paints
/// its `.library` gradient; Ledger paints flat paper. All logic lives in ``LibraryViewModel``
/// so persistence goes through the T5 service (verified via the service, not just UI).
public struct LibraryScreen: View {
    @Environment(\.theme) private var tokens
    @StateObject private var model: LibraryViewModel

    @State private var showingAdd = false
    @State private var showingBrowse = false

    /// Construct the screen with a ready-made view model (used by tests/previews).
    public init(model: LibraryViewModel) {
        _model = StateObject(wrappedValue: model)
    }

    public var body: some View {
        ZStack {
            ThemeBackground()

            VStack(spacing: 0) {
                header
                Divider().background(tokens.colors.divider)
                content
            }
        }
        .onAppear { model.reload() }
        .sheet(isPresented: $showingAdd) {
            AddQuoteSheet { text, author in
                model.addUserQuote(text: text, author: author)
            }
            .themed(tokens.theme, role: .library)
        }
        .sheet(isPresented: $showingBrowse) {
            BrowseQuoteSheet(model: model)
                .themed(tokens.theme, role: .library)
        }
    }

    // MARK: Header + actions

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("LIBRARY")
                    .font(tokens.typography.eyebrow)
                    .foregroundStyle(tokens.colors.textMuted)
                Text("Your quotes")
                    .font(tokens.typography.title)
                    .foregroundStyle(tokens.colors.textPrimary)
            }
            Spacer()
            Button {
                showingBrowse = true
            } label: {
                Image(systemName: "sparkles")
                    .foregroundStyle(tokens.colors.accent)
            }
            .accessibilityLabel("Browse online quotes")
            Button {
                showingAdd = true
            } label: {
                Image(systemName: "plus")
                    .foregroundStyle(tokens.colors.accent)
            }
            .accessibilityLabel("Add a quote")
        }
        .padding(.horizontal)
        .padding(.top)
        .padding(.bottom, 8)
    }

    // Note: the "today's quote source" (`TodayScope`) picker moved to the Settings screen
    // (ADR-040) — it is the single place the user changes theme + quote source. The Library
    // no longer hosts a source picker.

    // MARK: Content — empty state (ADR-033) or list

    @ViewBuilder
    private var content: some View {
        if model.isEmpty {
            emptyState
        } else {
            list
        }
    }

    /// The purposeful, themed empty/first-run state (ADR-033): an invitation to save a
    /// quote, NOT a blank view. Renders in BOTH themes (reads tokens by role).
    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "quote.opening")
                .font(.system(size: 40))
                .foregroundStyle(tokens.colors.textMuted)
            Text("Your library is empty")
                .font(tokens.typography.title)
                .foregroundStyle(tokens.colors.textPrimary)
            Text("Save a quote you like — write your own, or discover one online.")
                .font(tokens.typography.body)
                .foregroundStyle(tokens.colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            HStack(spacing: 12) {
                Button("Write one") { showingAdd = true }
                    .foregroundStyle(tokens.colors.accent)
                Button("Discover online") { showingBrowse = true }
                    .foregroundStyle(tokens.colors.accent)
            }
            .font(tokens.typography.body)
            .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("library-empty-state")
    }

    /// The library list (the `mine` pool, ADR-011). Each row supports un-like and explicit
    /// delete (source-dependent, ADR-035/-039) via swipe actions.
    private var list: some View {
        List {
            ForEach(model.quotes, id: \.id) { quote in
                LibraryRow(quote: quote, tokens: tokens)
                    .listRowBackground(tokens.colors.surface)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        // Explicit delete — HARD delete for either source (ADR-035).
                        Button(role: .destructive) {
                            model.delete(quote)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        // Un-like — source-dependent (ADR-035/-039). Offered when liked.
                        if quote.liked {
                            Button {
                                model.unlike(quote)
                            } label: {
                                Label("Un-like", systemImage: "heart.slash")
                            }
                            .tint(tokens.colors.textSecondary)
                        }
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

/// A single library row: text, author, and a like indicator (ADR-011/-010).
private struct LibraryRow: View {
    let quote: Quote
    let tokens: ThemeTokens

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(quote.text)
                    .font(tokens.typography.body)
                    .foregroundStyle(tokens.colors.textPrimary)
                HStack(spacing: 6) {
                    if let author = quote.author, !author.isEmpty {
                        Text(author)
                            .font(tokens.typography.eyebrow)
                            .foregroundStyle(tokens.colors.textSecondary)
                    }
                    Text(quote.source == .user ? "MINE" : "SAVED")
                        .font(tokens.typography.eyebrow)
                        .foregroundStyle(tokens.colors.textMuted)
                }
            }
            Spacer()
            Image(systemName: quote.liked ? "heart.fill" : "heart")
                .foregroundStyle(quote.liked ? tokens.colors.accent : tokens.colors.textMuted)
                .accessibilityLabel(quote.liked ? "Liked" : "Not liked")
        }
        .padding(.vertical, 4)
    }
}

/// The manual-add sheet (ADR-009/-010): a large text field + optional author. Save routes
/// through ``LibraryViewModel/addUserQuote(text:author:)`` → the T5 service (`source==user`).
private struct AddQuoteSheet: View {
    @Environment(\.theme) private var tokens
    @Environment(\.dismiss) private var dismiss

    @State private var text: String = ""
    @State private var author: String = ""

    /// Called with the entered text + author on save (blank author folds to nil upstream).
    let onSave: (String, String?) -> Void

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            ThemeBackground()
            VStack(alignment: .leading, spacing: 16) {
                Text("WRITE A QUOTE")
                    .font(tokens.typography.eyebrow)
                    .foregroundStyle(tokens.colors.textMuted)
                TextField("The quote", text: $text, axis: .vertical)
                    .font(tokens.typography.body)
                    .foregroundStyle(tokens.colors.textPrimary)
                    .lineLimit(3...8)
                TextField("Author (optional)", text: $author)
                    .font(tokens.typography.body)
                    .foregroundStyle(tokens.colors.textSecondary)
                Spacer()
                HStack {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(tokens.colors.textSecondary)
                    Spacer()
                    Button("Save") {
                        onSave(text, author)
                        dismiss()
                    }
                    .foregroundStyle(canSave ? tokens.colors.accent : tokens.colors.textMuted)
                    .disabled(!canSave)
                }
                .font(tokens.typography.body)
            }
            .padding()
        }
    }
}

/// The browse-online-and-like sheet (ADR-012/-010/-013): fetches a transient quote via
/// `/random`, shows it, and ♡ persists it into the library (dedup by INV-4). Discover /
/// error+retry states per ADR-013.
private struct BrowseQuoteSheet: View {
    @Environment(\.theme) private var tokens
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: LibraryViewModel

    var body: some View {
        ZStack {
            ThemeBackground()
            VStack(spacing: 20) {
                Text("DISCOVER ONLINE")
                    .font(tokens.typography.eyebrow)
                    .foregroundStyle(tokens.colors.textMuted)

                Spacer()

                if model.isBrowsing {
                    ProgressView()
                        .tint(tokens.colors.accent)
                } else if let error = model.browseError {
                    errorState(error)
                } else if let quote = model.browsing {
                    quoteCard(quote)
                } else {
                    Text("Tap discover to find a quote you like.")
                        .font(tokens.typography.body)
                        .foregroundStyle(tokens.colors.textSecondary)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                actions
            }
            .padding()
        }
        .task {
            if model.browsing == nil && model.browseError == nil {
                await model.browseNext()
            }
        }
    }

    private func quoteCard(_ quote: FetchedQuote) -> some View {
        VStack(spacing: 10) {
            Text(quote.text)
                .font(tokens.typography.title)
                .foregroundStyle(tokens.colors.textPrimary)
                .multilineTextAlignment(.center)
            if let author = quote.author, !author.isEmpty {
                Text(author)
                    .font(tokens.typography.eyebrow)
                    .foregroundStyle(tokens.colors.textSecondary)
            }
        }
        .padding()
    }

    /// Error + retry (ADR-013): online has no local fallback, so a failure surfaces retry.
    private func errorState(_ error: ZenQuotesError) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .foregroundStyle(tokens.colors.textMuted)
            Text("Couldn't reach the quote source.")
                .font(tokens.typography.body)
                .foregroundStyle(tokens.colors.textSecondary)
            Button("Retry") { Task { await model.browseNext() } }
                .foregroundStyle(tokens.colors.accent)
        }
    }

    private var actions: some View {
        HStack {
            Button("Close") {
                model.dismissBrowsed()
                dismiss()
            }
            .foregroundStyle(tokens.colors.textSecondary)
            Spacer()
            Button {
                Task { await model.browseNext() }
            } label: {
                Label("Next", systemImage: "arrow.clockwise")
            }
            .foregroundStyle(tokens.colors.accent)
            .disabled(model.isBrowsing)
            Spacer()
            // ♡ like → persist the transient quote (ADR-010). Enabled only when browsing one.
            Button {
                model.likeBrowsed()
                dismiss()
            } label: {
                Label("Like", systemImage: "heart")
            }
            .foregroundStyle(model.browsing == nil ? tokens.colors.textMuted : tokens.colors.accent)
            .disabled(model.browsing == nil)
        }
        .font(tokens.typography.body)
    }
}

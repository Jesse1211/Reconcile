import SwiftUI
import SwiftData

/// The Today screen (T7): quote area + MIT list (with intention ritual) + evening feeling.
///
/// Theme-agnostic (ADR-022/-036): it declares `screenRole == .today` so Day Arc paints
/// the dawn gradient (ADR-037) and reads every color/font by role from `\.theme`. It
/// wires the T4/T5/T11 services out of the environment into a ``TodayViewModel`` and
/// renders its state. All feature logic lives in the view model; this view is the thin
/// composition + presentation of the full-screen intention ritual (ADR-024) and the
/// soft-delete undo snackbar (ADR-008).
public struct TodayScreen: View {
    @Environment(\.theme) private var tokens
    @Environment(\.modelContext) private var modelContext
    @Environment(\.clock) private var clock
    @EnvironmentObject private var settings: AppSettings

    @StateObject private var model: TodayViewModel

    @State private var showRitual = false
    @State private var showFeeling = false
    @State private var editingMIT: MIT?

    /// Build the screen, constructing the view model from the environment's context,
    /// clock and settings. `client` is injectable so previews/tests supply a fake
    /// ZenQuotes boundary (ADR-013); the app passes the live client.
    public init(
        context: ModelContext,
        clock: Clock,
        settings: AppSettings,
        client: ZenQuotesClient
    ) {
        let quoteService = QuoteService(
            context: context, clock: clock, client: client,
            scope: { settings.todayScope }, category: { settings.quoteCategory }   // ADR-047
        )
        let vm = TodayViewModel(
            context: context,
            clock: clock,
            quoteService: quoteService,
            mitService: MITService(clock: clock),
            feelingService: DailyFeelingService(clock: clock),
            scope: { settings.todayScope }
        )
        _model = StateObject(wrappedValue: vm)
    }

    public var body: some View {
        ZStack {
            ThemeBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    TodayQuoteCard(model: model)
                    MITListSection(
                        model: model,
                        onOpenRitual: { showRitual = true },
                        onEdit: { editingMIT = $0 }
                    )
                    EveningFeelingSection(model: model, onOpen: { showFeeling = true })
                }
                .padding(20)
            }

            if let undo = model.pendingUndo {
                undoSnackbar(undo)
            }
        }
        .task { await model.onAppear() }
        // ADR-024: the intention ritual is a PINNED full-screen experience (entered from
        // the dashed placeholder row). It must cover the whole screen — not a partial-height
        // `.sheet` card — so it reads as a deliberate ritual rather than a generic sheet.
        .fullScreenCover(isPresented: $showRitual) {
            NavigationStack {
                IntentionRitualView(date: clock.today()) { text, reason in
                    _ = model.saveIntention(text: text, reason: reason)
                }
            }
            .themed(settings.theme, role: .today)
        }
        .sheet(item: $editingMIT) { mit in
            NavigationStack {
                MITEditSheet(mit: mit) { newText, newReason in
                    model.editMIT(mit, text: newText, reason: .some(newReason))
                }
            }
            .themed(settings.theme, role: .today)
        }
        // ADR-046b: the evening feeling is a full-screen entry (like the intention ritual),
        // opened from the small feeling card. Seed from today's saved entry, or the 3/3
        // midpoint for a fresh one.
        .fullScreenCover(isPresented: $showFeeling) {
            NavigationStack {
                FeelingSheetView(
                    date: clock.today(),
                    editable: model.feelingEditable,
                    initialMood: model.feeling?.mood ?? 3,
                    initialStress: model.feeling?.stress ?? 3,
                    initialWhy: model.feeling?.whyText ?? ""
                ) { mood, stress, why in
                    model.saveFeeling(mood: mood, stress: stress, why: why)
                }
            }
            .themed(settings.theme, role: .today)
        }
    }

    // MARK: Undo snackbar (ADR-008/-030)

    private func undoSnackbar(_ undo: TodayViewModel.PendingUndo) -> some View {
        VStack {
            Spacer()
            HStack {
                Text("Deleted “\(undo.mit.text)”")
                    .font(tokens.typography.body)
                    .foregroundStyle(tokens.colors.textPrimary)
                    .lineLimit(1)
                Spacer()
                Button("Undo") { model.undoDelete() }
                    .font(tokens.typography.body)
                    .foregroundStyle(tokens.colors.accentOnBackground)
                    .accessibilityIdentifier("mit.undo")
            }
            .padding(16)
            .background(tokens.colors.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .transition(.move(edge: .bottom))
    }
}

/// A minimal same-day editor for an existing MIT (ADR-004): edit text + reason. Reuses
/// the theme tokens (ADR-036). Presented as a sheet from the Today MIT list.
struct MITEditSheet: View {
    @Environment(\.theme) private var tokens
    @Environment(\.dismiss) private var dismiss

    let mit: MIT
    let onSave: (_ text: String, _ reason: String?) -> Void

    @State private var text: String
    @State private var reason: String

    init(mit: MIT, onSave: @escaping (_ text: String, _ reason: String?) -> Void) {
        self.mit = mit
        self.onSave = onSave
        _text = State(initialValue: mit.text)
        _reason = State(initialValue: mit.reason ?? "")
    }

    var body: some View {
        ZStack {
            ThemeBackground()
            VStack(alignment: .leading, spacing: 20) {
                Text("EDIT")
                    .font(tokens.typography.eyebrow)
                    .foregroundStyle(tokens.colors.textMuted)
                TextField("The one thing…", text: $text, axis: .vertical)
                    .font(tokens.typography.title)
                    .foregroundStyle(tokens.colors.textPrimary)
                    .lineLimit(1...4)
                TextField("Why does it matter today?", text: $reason, axis: .vertical)
                    .font(tokens.typography.body)
                    .foregroundStyle(tokens.colors.textPrimary)
                    .lineLimit(1...4)
                    .padding(12)
                    .background(tokens.colors.surface, in: RoundedRectangle(cornerRadius: 10))
                Spacer()
                Button {
                    let r = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSave(text, r.isEmpty ? nil : r)
                    dismiss()
                } label: {
                    Text("Save")
                        .font(tokens.typography.title)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(tokens.colors.background)
                        .background(tokens.colors.accentFill, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(24)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
                    .foregroundStyle(tokens.colors.textSecondary)
            }
        }
    }
}

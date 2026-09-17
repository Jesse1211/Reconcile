import SwiftUI

/// The Settings screen: the single place the user changes the **today's quote source**
/// (`TodayScope` mine / online, ADR-040) and the online quote **category** (ADR-047).
///
/// There is no theme picker: Ledger is the only theme (Day Arc removed, ADR-022).
///
/// Theme-agnostic (ADR-036): it declares `screenRole == .settings` and reads every
/// color/font by role from `\.theme`. Its controls write straight to `AppSettings` — the
/// single persisted source of truth (ADR-040): writing `todayScope` re-points the next
/// daily quote pick (T5 reads it). No view model needed.
public struct SettingsScreen: View {
    @Environment(\.theme) private var tokens
    @EnvironmentObject private var settings: AppSettings

    public init() {}

    public var body: some View {
        ZStack {
            ThemeBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header

                    settingBlock(
                        eyebrow: "TODAY'S QUOTE",
                        title: "Source",
                        caption: "Saved shows your saved & liked quotes; Online pulls a fresh one from the web."
                    ) {
                        Picker("Today's quote source", selection: $settings.todayScope) {
                            ForEach(TodayScope.allCases, id: \.self) { scope in
                                Text(scope.displayName).tag(scope)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("settings.scope")
                    }

                    // ADR-047: the online quote CATEGORY. Applies to the Online source only
                    // (Mine ignores it) — disabled unless the source is Online.
                    settingBlock(
                        eyebrow: "TODAY'S QUOTE",
                        title: "Category",
                        caption: "Filters the Online quote by theme. Applies to Online only."
                    ) {
                        Picker("Today's quote category", selection: $settings.quoteCategory) {
                            ForEach(QuoteCategory.allCases, id: \.self) { category in
                                Text(category.displayName).tag(category)
                            }
                        }
                        .pickerStyle(.menu)
                        .disabled(settings.todayScope != .online)
                        .accessibilityIdentifier("settings.category")
                    }

                    Spacer(minLength: 0)
                }
                .padding(24)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("SETTINGS")
                .font(tokens.typography.eyebrow)
                .foregroundStyle(tokens.colors.textMuted)
            Text("Settings")
                .font(tokens.typography.display)
                .foregroundStyle(tokens.colors.textPrimary)
        }
    }

    // MARK: A titled setting block — eyebrow + title + caption + control

    @ViewBuilder
    private func settingBlock<Control: View>(
        eyebrow: String,
        title: String,
        caption: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(eyebrow)
                .font(tokens.typography.eyebrow)
                .foregroundStyle(tokens.colors.textMuted)
            Text(title)
                .font(tokens.typography.title)
                .foregroundStyle(tokens.colors.textPrimary)
            // Controls fill the block's width so a menu picker (intrinsic-width) and a
            // segmented picker (full-width) both produce the SAME card size. The menu's
            // button aligns to the trailing edge for a tidy row.
            control()
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(caption)
                .font(tokens.typography.body)
                .foregroundStyle(tokens.colors.textSecondary)
        }
        .padding(16)
        // Every setting card fills the available width → all cards are the same size,
        // regardless of the control inside (owner tweak).
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tokens.colors.surface, in: RoundedRectangle(cornerRadius: 14))
    }
}

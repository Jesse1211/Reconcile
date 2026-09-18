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
        ScreenScaffold("Settings") {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    settingBlock(eyebrow: "QUOTE SOURCE") {
                        Picker("Quote source", selection: $settings.todayScope) {
                            ForEach(TodayScope.allCases, id: \.self) { scope in
                                Text(scope.displayName).tag(scope)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("settings.scope")
                    }

                    // ADR-047: the online quote CATEGORY. Applies to the Online source only
                    // (Mine ignores it) — disabled unless the source is Online.
                    settingBlock(eyebrow: "ONLINE QUOTE CATEGORY") {
                        categoryDropdown
                    }

                    Spacer(minLength: 0)
                }
                .padding(24)
            }
        }
    }

    // MARK: Ledger-styled category dropdown (ADR-047)
    //
    // Replaces the system `.menu` picker (which rendered a jarring system-blue "Any"
    // control) with a theme-native dropdown: a paper/ink trigger button showing the current
    // category + a ledger-red chevron, over a native `Menu` whose items tick the selection.
    // Disabled (dimmed) unless the source is Online.

    private var categoryDropdown: some View {
        let isOnline = settings.todayScope == .online
        return Menu {
            ForEach(QuoteCategory.allCases, id: \.self) { category in
                Button {
                    settings.quoteCategory = category
                } label: {
                    // A tick appears next to the current selection in the menu list.
                    if settings.quoteCategory == category {
                        Label(category.displayName, systemImage: "checkmark")
                    } else {
                        Text(category.displayName)
                    }
                }
            }
        } label: {
            HStack {
                Text(settings.quoteCategory.displayName)
                    .font(tokens.typography.body)
                    .foregroundStyle(tokens.colors.textPrimary)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tokens.colors.accentOnBackground)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(tokens.colors.surfaceRaised, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(tokens.colors.divider, lineWidth: 1)
            )
        }
        .disabled(!isOnline)
        .accessibilityIdentifier("settings.category")
    }

    // MARK: A titled setting block — eyebrow + title + caption + control
    // (the "Settings" page title is the pinned ScreenScaffold header)

    @ViewBuilder
    private func settingBlock<Control: View>(
        eyebrow: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        // One consistent design language for every setting: a single small-caps eyebrow
        // label above its control — no large title, no description caption (owner tweak).
        VStack(alignment: .leading, spacing: 10) {
            Text(eyebrow)
                .font(tokens.typography.eyebrow)
                .foregroundStyle(tokens.colors.textMuted)
            // Controls fill the block's width so a menu picker (intrinsic-width) and a
            // segmented picker (full-width) both produce the SAME card size. The menu's
            // button aligns to the trailing edge for a tidy row.
            control()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        // Every setting card fills the available width → all cards are the same size,
        // regardless of the control inside.
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tokens.colors.surface, in: RoundedRectangle(cornerRadius: 14))
    }
}

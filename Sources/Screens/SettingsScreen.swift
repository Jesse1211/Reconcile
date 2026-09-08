import SwiftUI

/// The Settings screen: the single place the user changes the **visual theme**
/// (Ledger / Day Arc, ADR-022) and the **today's quote source** (`TodayScope` mine /
/// online, ADR-040).
///
/// Theme-agnostic (ADR-022/-036): it declares `screenRole == .settings` so Day Arc paints
/// its night gradient (ADR-037) and reads every color/font by role from `\.theme`. Both
/// controls write straight to `AppSettings` — the single persisted source of truth
/// (ADR-040): writing `theme` also mirrors to the widget (ADR-044) and writing
/// `todayScope` re-points the next daily quote pick (T5 reads it). No view model needed.
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
                        eyebrow: "APPEARANCE",
                        title: "Theme",
                        caption: "Ledger is paper & ink; Day Arc shifts with the light of day."
                    ) {
                        Picker("Theme", selection: $settings.theme) {
                            ForEach(Theme.allCases, id: \.self) { theme in
                                Text(theme.displayName).tag(theme)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("settings.theme")
                    }

                    settingBlock(
                        eyebrow: "TODAY'S QUOTE",
                        title: "Source",
                        caption: "Mine shows your saved & liked quotes; Online pulls a fresh one from ZenQuotes."
                    ) {
                        Picker("Today's quote source", selection: $settings.todayScope) {
                            ForEach(TodayScope.allCases, id: \.self) { scope in
                                Text(scope.displayName).tag(scope)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("settings.scope")
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
            control()
            Text(caption)
                .font(tokens.typography.body)
                .foregroundStyle(tokens.colors.textSecondary)
        }
        .padding(16)
        .background(tokens.colors.surface, in: RoundedRectangle(cornerRadius: 14))
    }
}

import WidgetKit
import SwiftUI

/// The `.systemMedium` Home Screen widget (ADR-041): one wide widget showing the
/// stopwatch figure AND the quote side by side (running) or the quote filling the
/// widget (idle). Themed per the persisted `Theme` (ADR-044). READ-ONLY — tapping it
/// opens the app (a plain app-open; ADR-042) and it exposes no mutation path (OQ-08).
struct HomeWidget: Widget {
    let kind = "ReconcileHomeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ReconcileWidgetProvider()) { entry in
            HomeWidgetView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Reconcile")
        .description("Today's quote and your focus stopwatch.")
        .supportedFamilies([.systemMedium])   // ADR-041: systemMedium ONLY
    }
}

/// The combined `.accessoryRectangular` Lock Screen widget (ADR-041): BOTH the
/// stopwatch figure and the quote (quote truncated to fit). Theme-neutral under the
/// system tint (ADR-044). READ-ONLY — plain app-open on tap (ADR-042).
struct LockWidget: Widget {
    let kind = "ReconcileLockWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ReconcileWidgetProvider()) { entry in
            LockWidgetView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Reconcile")
        .description("Today's quote and your focus stopwatch.")
        .supportedFamilies([.accessoryRectangular])   // ADR-041: one combined lock widget
    }
}

/// The widget bundle exposing both families (ADR-041). This is the extension's
/// `@main` entry point — the extension runs NO business logic and NO network of its
/// own (ADR-042/-043); it only reads the shared snapshot.
@main
struct ReconcileWidgetBundle: WidgetBundle {
    var body: some Widget {
        HomeWidget()
        LockWidget()
    }
}

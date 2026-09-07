# T12 — NAMED human delivery / smoke step (WidgetKit blindSpot)

WidgetKit **timeline scheduling** and **on-device widget RENDERING** (the real
Home/Lock widget host, system tint, `Text(startedAt, style: .timer)` advancing on a
real Home/Lock Screen, and the running→accumulated / local-midnight flips) are **NOT
fully drivable by the in-loop tester** (declared blindSpot, DESIGN §6/§7 T12). The
in-loop asset that IS covered is the **shared-snapshot round-trip through a real App
Group container** (see `WidgetSnapshotTests.testSnapshotRoundTripsThroughRealAppGroupContainer`).

Everything below MUST be verified by a human on a device/simulator before shipping.

## Smoke checklist

1. **Gallery** — long-press the Home Screen → add widget → confirm the **Reconcile**
   widget appears with a `.systemMedium` (Home) option, and the Lock Screen editor
   offers the `.accessoryRectangular` (Lock) option.
2. **Home — running layout (ADR-041)**: start a focus session in the app. On the
   Home widget confirm `time │ quote — author` — a **self-advancing** timer on the
   left (it ticks up without opening the app), a divider, the quote + author on the
   right. NO field label, NO status word/dot, NO brand mark.
3. **Home — idle layout (ADR-041)**: stop the session. Confirm the widget flips to
   the **quote filling the widget** (larger), author beneath, **NO time figure and NO
   divider**.
4. **Home — both themes (ADR-044)**: switch the app Theme (Ledger ↔ Day Arc) and
   confirm the Home widget re-renders in the selected theme after its next reload.
5. **Lock — both layouts (ADR-041/-044)**: add the Lock widget. Running → `time │
   quote` (quote clamped); idle → quote-only (no time, no divider). Confirm it is
   **legible under the system tint** (theme-neutral, no Day-Arc gradient).
6. **Empty state (ADR-045)**: with scope=`mine` and an empty library (no quote yet),
   confirm BOTH families show **"Open Reconcile to set today's quote"**, never a blank
   view.
7. **Flips (ADR-043)**: observe the **running→accumulated** flip when a session ends
   while the widget is on-screen, and the **local-midnight** quote/accumulated reset
   (advance the device clock past midnight and confirm the new day's snapshot shows).
8. **Read-only (ADR-042)**: confirm tapping either widget just **opens the app**
   (plain app-open) — there is no start/stop/like/refresh control on the widget.

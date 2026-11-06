# WTB-007 — Settings window wiring

- **Priority:** P2
- **Estimate:** S
- **Depends on:** 006
- **Suggested owner:** one agent; good small parallel task

## Problem

The Settings default-window picker is not connected to the Results screen.

- `SettingsView` writes `@AppStorage("defaultWindow")`.
- `ResultsView` reads `@AppStorage("defaultResultsWindow")`.
- Settings tags All Time as `"all"`.
- `ResultsWindow.allTime.rawValue` is `"All"`.

So changing the setting does nothing today. Even if the key were fixed, the All Time value would not round-trip.

Relevant code:

- `WODCounter/Views/SettingsView.swift:5-7`, `:25-32`.
- `WODCounter/Views/ResultsView.swift:7-13`, `:40-44`.

## Goal

One source of truth for the default results window, shared by Settings and Results.

## Scope

1. Make `ResultsWindow` the shared model (move it to `Support/` or a suitable non-view file if needed).
2. Use one `@AppStorage` key in both views. Suggested: `"defaultResultsWindow"`.
3. Bind Settings directly to `ResultsWindow` values, not ad-hoc strings.
4. Ensure the default is `30d` and invalid stored values fall back safely.
5. Add a reset-to-default path only if it fits the existing Settings UX; otherwise leave it out.
6. Remove or update the old `"defaultWindow"` key handling. Do not migrate unless existing users need it.

## Acceptance criteria

- [x] Changing the window in Settings changes the initial window in Results.
- [x] All four windows round-trip: 7d, 30d, 90d, all.
- [x] Default is 30 days.
- [x] An invalid stored value falls back to 30 days without crashing.
- [x] No duplicated string constants for window values remain in the two views.

## Tests

- Round-trip each `ResultsWindow` raw value through the shared key.
- Invalid value falls back.
- Settings picker selection and Results initial selection use the same key.
- Existing results window tests keep passing.

## Out of scope

- iCloud sync (ticket 008).
- Results delta calculations (ticket 006).

## Result

**Status:** implemented (uncommitted, 2026-11-06).

- `ResultsWindow` now lives in `WODCounter/Support/ResultsWindow.swift` and owns the shared key, default, and safe stored-value resolution.
- Both `SettingsView` and `ResultsView` use `ResultsWindow.storageKey` (`"defaultResultsWindow"`).
- Settings binds its picker to `ResultsWindow` cases; labels are unchanged.
- Raw values remain `7d`, `30d`, `90d`, `All`; the old `"defaultWindow"` key is no longer used.
- Invalid or missing stored values resolve to `.thirtyDays`.
- Tests cover shared-key round-trips for all four windows and invalid-value fallback.

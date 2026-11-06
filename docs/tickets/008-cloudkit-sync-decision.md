# WTB-008 — iCloud sync decision

- **Priority:** P2
- **Estimate:** Decision + S (defer/remove) or L (implement)
- **Depends on:** 001, 004
- **Suggested owner:** human decision first; implementation can be delegated afterward

## Problem

The Settings screen exposes an iCloud sync toggle, but sync does not exist.

- `SettingsView` stores `cloudKitEnabled` in `@AppStorage`.
- Nothing reads it.
- `Container.local()` always creates a plain local `ModelConfiguration`.
- There is no CloudKit entitlement, container identifier, or configuration path.
- The footer claims changes take effect next launch, but no code applies them.

The current model is also not CloudKit-ready:

- `.unique` on `Movement.name` and `WorkoutRecord.id` is problematic for CloudKit.
- Non-optional fields need defaults for CloudKit schema compatibility.
- The spec says “public database, no account,” which is a poor fit for private workout history and is not accurate for writes in practice.

Relevant code:

- `WODCounter/Views/SettingsView.swift:5`, `:10-23`.
- `WODCounter/Support/Container.swift:13-16`.
- `WODCounter/Models/Movement.swift:5`.
- `WODCounter/Models/WorkoutRecord.swift:5`.

## Decision

**Chosen: Option A — defer sync (2026-11-06).**

The app is local-only in v1. The non-functional toggle and misleading copy have been removed from Settings. iCloud sync is deferred to v1.1 and remains tracked here.

### Option A — Defer sync (chosen for v1)

- Remove the iCloud toggle and “next launch” copy from Settings.
- Update README/spec to say sync is deferred to v1.1.
- Keep `Container.local()` local-only.
- No data-model changes.

This is honest and avoids shipping a non-functional control.

### Option B — Implement private CloudKit sync

- Use a private CloudKit database with an iCloud account; do not use a public database for workout history.
- Add the CloudKit entitlement and container identifier to the project.
- Remove `.unique` constraints or replace them with application-level deduplication.
- Ensure every synced model has CloudKit-compatible defaults/optionality.
- Build a container factory that selects local vs CloudKit based on the preference.
- Define restart/reload semantics when toggling.
- Handle “iCloud unavailable / not signed in” gracefully.
- Add a migration/backfill plan for existing local data.
- Test with an in-memory/local fallback; CloudKit integration needs a manual device test.

## Acceptance criteria

### If Option A

- [x] The toggle and misleading copy are removed.
- [x] Docs state sync is deferred.
- [x] No `cloudKitEnabled` preference remains unless documented as unused.
- [x] Settings still builds and the results window preference still works.

### If Option B

- [ ] Toggle actually selects a CloudKit-backed container.
- [ ] Local-only mode still works offline.
- [ ] No `.unique` CloudKit violations remain.
- [ ] Signed-out/unavailable state is handled without data loss.
- [ ] Toggling has explicit, documented restart behavior.
- [ ] Existing local records survive the transition.
- [ ] Manual cross-device smoke test is documented.

## Tests

- Option A: settings UI no longer exposes a no-op control.
- Option B: container factory unit tests for local/cloud selection; model schema validation; migration test. CloudKit itself requires a device/manual test.

## Out of scope

- Public leaderboards, accounts, or server infrastructure.
- Cross-platform sync.

## Result

**Status:** implemented (Option A, uncommitted, 2026-11-06).

- Removed the `cloudKitEnabled` `@AppStorage` value and the non-functional iCloud toggle from `SettingsView`.
- Replaced the misleading sync copy with a local-storage note: “iCloud sync is not available in this version.”
- Settings still exposes the shared results-window preference from ticket 007.
- README, spec, and handoff now describe sync as deferred to v1.1, not as a pending working feature.
- No data-model or CloudKit changes were made; `Container.local()` remains local-only.
- Option B (private CloudKit) remains an explicit future path in this ticket.

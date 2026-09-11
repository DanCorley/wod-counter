# WOD Round Counter — Design Spec

- **Status:** Approved (user sign-off pending)
- **Platform:** iOS (Apple-native)
- **Stack:** SwiftUI + SwiftData + Swift Concurrency
- **Version:** 1.0 spec

---

## 1. Purpose & Problem

Athletes doing "benchmark" workouts (Cindy, Murph, Fran, etc.) want to know **how many rounds they completed** in a given effort, and — over time — whether they're getting faster.

The app provides a **focused timer** that counts completed *rounds* for a predefined or custom workout, in one of two execution modes, and later surfaces a **historical results view** showing personal records (PRs), progress over time, and a shareable result card.

---

## 2. Scope

### In scope (v1.0)
- Predefined workout library: **Cindy** and **Murph** (seed values, editable).
- Custom workout creation from a shipped exercise palette; custom WODs are editable and savable.
- Two execution modes: **For-time** and **Top-time**.
- Per-round counting with a single tap action.
- **Pause/Resume**; paused time tracked and subtracted from active time (for-time).
- SwiftData local storage + **optional iCloud sync**.
- Historical results view: time-window summary, per-WOD bests, PRs, "Δ vs last attempt", a progress chart.
- Share card (Share Sheet / screenshot).

### Explicitly out of scope (deferred)
- Streaks, daily/weekly goals, gamified nudges, community leaderboards.
- Apple Watch app (v2, behind a shared timer model).
- Apple Health integration (v1.5).
- Apple Sign-In / accounts (v1.5).
- Scheduling / EMOM / interval (structured timer) WOD styles.
- Android / web.

---

## 3. Domain Model (SwiftData)

### `Exercise`
A movement the user can put into a WOD.
| Field | Type | Notes |
|---|---|---|
| id | UUID | PK |
| name | String | e.g. "Pull-ups", "Air Squat" |
| iconName | String? | SF Symbol name (optional; fallback to text) |
| standard | Bool | `true` = shipped standard move |
| createdAt | Date | |

### `Workout`
A named set of exercises with a mode (predefined benchmark OR user-created).
| Field | Type | Notes |
|---|---|---|
| id | UUID | PK |
| name | String | "Cindy", "My HIIT", etc. |
| description | String? | e.g. "5/10/15 scheme" |
| mode | `ExecutionMode` | `.forTime` or `.topTime` |
| exercises | [Exercise] | ordered list |
| isBuiltin | Bool | benchmark presets vs. user WODs |
| createdAt / updatedAt | Date | |
| **For-time specifics** | Int? `totalRounds` | minutes the clock runs (Cindy = 20; Murph = 0/unlimited effectively) |
| **Top-time specifics** | [Int: Int] `roundRepCounts` | map round → per-exercise rep quota, e.g. round 3 = {exercise: 100, ...} |

**Mode semantics**

- **For-time:** The clock is fixed at `totalRounds` minutes. Contestable (active) time = elapsed − pausedTime. The app counts how many full rounds finished *within active time*; it never stops on its own — the user ends the session by tapping Stop/Finish (round count at that moment is the result). Default Cindy `totalRounds = 20`. Murph is for-time; spec its minutes (default 0 = "as long as it takes" → clock only stops on Finish, active time tracked).
- **Top-time:** Target is reached by completing the last rep of the final round. When the final rep is hit the timer **auto-stops** and records elapsed active time as the result. (For v1, top-time pause handling: pauses stop the active clock since reps are the driver, not time — paused time is still logged in history but does not reset the rep target.)

> **Round definition:** A *round* = one complete pass of every exercise in `exercises` at its quota. Round count increments by 1 each time all quotas in the current round are met.

### `WorkoutAttempt` (a completed workout session)
| Field | Type | Notes |
|---|---|---|
| id | UUID | PK |
| workout | relationship → `Workout` | FK |
| resultType | String | `"rounds"` (for-time) or `"time"` (top-time) |
| roundCount | Int | completed rounds (for-time) |
| totalReps | Int | sum of reps completed (informative) |
| elapsedTime | TimeInterval | total wall-clock from start to finish |
| pausedTime | TimeInterval | accumulated paused duration |
| activeTime | TimeInterval | elapsedTime − pausedTime |
| finishedAt | Date | when session ended |
| isPR | Bool | better than user's previous best for that workout |
| notes | String? | |

`activeTime = elapsedTime − pausedTime`, computed at save time (seeded via `#Predicate`/computed property in the model or a value computed in the view model).

### `WorkoutRecord` (optional higher-level for history views / sync)
> *Decision: consider whether to store completed attempts directly on `Workout` (denormalized best stats) vs. a separate `WorkoutRecord` table. A separate `WorkoutRecord` keeps `Workout` clean and makes "best rounds" an easy aggregate query. Recommend separate table.*

| Field | Type | Notes |
|---|---|---|
| id | UUID | PK |
| workout | relationship → `Workout` | FK |
| attemptId | UUID | FK to the `WorkoutAttempt` this record summarizes |
| date | Date | session date (for windowed stats) |
| kind | String | `"rounds"` / `"time"` |
| value | Double | rounded for display (roundCount or activeTime) |
| isPR | Bool | |

**History aggregation** is derived from `WorkoutRecord` by date window (7/30/90 days/all) → counts, PRs, deltas. This keeps queries simple and cheap.

---

## 4. User Flows

### Flow A — Start a for-time WOD (Cindy)
1. Home lists WODs (builtins first, then custom). Tap **Cindy**.
2. Detail shows scheme (5/10/15), mode **For-time 20:00**, round definition, a **Start** button.
3. Tap Start → timer screen appears, clock at 20:00, **Round** counter at 0.
4. User taps **Round +1** (or **Next Round**) each time they finish a full round. Round counter increments.
5. **Pause/Resume** button: freezing the clock; paused seconds accumulate and are subtracted from active time.
6. Tap **Finish** → attempt saved (resultType = rounds, roundCount, elapsedTime, pausedTime, activeTime).

### Flow B — Start a top-time WOD
1. Pick a custom or top-time workout.
2. Timer screen shows progress toward final round; **Start**.
3. User completes reps; app detects final rep and **auto-stops**, recording elapsed active time.
4. Results overlay shows the time; **Share** and **Finish**.

### Flow C — History / stats
1. Results tab shows: window summary ("Past 30 days: X workouts, Y PRs"), a per-WOD bests list with Δ vs. last, a progress chart of best-over-time, and a "View attempts" drill-down.
2. Window default = **1 month**; user can switch between 7 / 30 / 90 days / all-time (saved as default preference).

### Flow D — Create a custom WOD
1. "Create WOD" → add exercises from the palette → set per-exercise rep quota → choose mode (for-time w/ minutes, or top-time) → name it → Save (synced).

---

## 5. UI Screens (proposed)
1. **Home** — workods grid/list, Start buttons, quick entry to results.
2. **WOD Detail** — scheme/mode description, Start, edit/delete.
3. **Timer** — the core screen: big clock, round counter / progress, Pause/Resume, Finish, Round +1.
4. **Results / History** — window summary, PRs, chart, attempts drill-down.
5. **Create WOD** — form for building custom workouts.
6. **Settings** — iCloud sync toggle, time-window default, preferences.

*No full mockups yet — approved later via visual companion if desired.*

---

## 6. Architecture

```
┌───────────────────────────────────────────────┐
│  SwiftUI Views (presentational)                │
│   HomeView · WODDetailView · TimerView ·       │
│   ResultsView · CreateWODView · SettingsView   │
└───────────────────────────────────────────────┘
                       │  @Query / bindings
┌───────────────────────────────────────────────┐
│  Model layer (SwiftData @Model classes)         │
│   Exercise · Workout · WorkoutRecord ·          │
│   WorkoutAttempt (optional)                     │
└───────────────────────────────────────────────┘
                       │  ModelContainer
┌───────────────────────────────────────────────┐
│  Services                                       │
│   WorkoutTimerService (clock, pause, active)   │
│   ResultsService (windowed aggregation/PRs)     │
│   SyncService (optional iCloud CloudKit)        │
└───────────────────────────────────────────────┘
```

- **Timer logic** lives in a `WorkoutTimerService` (actor/class) so the view stays declarative; it owns start/pause/resume/finish and computes active time.
- On **finish**, the service writes the `WorkoutAttempt` + `WorkoutRecord` via the `ModelContext`.
- **ResultsService** provides pure functions/queries for windowed stats, bests, and PR detection ("is this attempt better than the user's prior best for that workout").
- **SyncService**: CloudKit-backed SwiftData container. Sync **opt-in** (Settings toggle); defaults to on per plan but must be graceful if unavailable/disabled.

---

## 7. Data & Sync

- **Persistence:** SwiftData `ModelContainer` (in-memory + persistent, main-ctx usable).
- **CloudKit sync:** Opt-in via Settings. Requires container configured with a CloudKit description (public database, no server). Custom `Workout`/`WorkoutRecord` get default values so sync works without a user account.
- **Offline-first:** all reads/writes local first; CloudKit mirrors in background. No backend, no server, no account.
- **Privacy:** workout data never leaves the device (unless the user enables iCloud).

---

## 8. Seeded Content (v1)
| Workout | Mode | Scheme | totalRounds (min) |
|---|---|---|---|
| Cindy | For-time | 5/10/15 × Pull-ups, Push-ups, Air Squats | 20 |
| Murph | For-time | 100 Pull-ups, 200 Push-ups, 300 Air Squats | 0 (finish-driven; clock stops on Finish) |

> Design the builtin list as **data in a `BuiltinWorkouts` seed source** that can be extended (Fran, Helen, David, Diane, Thrasher, 21-95) without schema changes.

---

## 9. Non-Functional Requirements
- **Offline-first**, instant launch, no network calls in the timer path.
- Works reliably in background for short sessions; foreground timer is primary.
- Accessibility: Dynamic Type, VoiceOver-labeled clock and round counter, large hit targets.
- Clear timer during rest/pause so miscounting is minimized.

## 10. Acceptance Criteria
- [ ] Can start Cindy, tap to count rounds, pause/resume (paused time subtracted), and Finish → a `WorkoutRecord` is created.
- [ ] Can start a top-time WOD and the timer auto-stops at the final rep, recording elapsed active time.
- [ ] Can create, edit, and delete a custom WOD; it appears on Home and syncs (if iCloud on).
- [ ] Results screen shows 7/30/90-day/all-time windows, per-WOD bests, PRs, Δ vs. last, a progress chart, and a share card.
- [ ] iCloud sync is toggleable and, when enabled, propagates records across devices.

## 11. Deferred Roadmap
1. **v1.5:** Apple Health (write workout result), Apple Sign-In (optional).
2. **v2:** Apple Watch app reusing the shared `WorkoutTimerService` and model.

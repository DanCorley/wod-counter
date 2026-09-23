# WOD Round Counter — Design Spec

- **Status:** Approved (user sign-off pending)
- **Platform:** iOS (Apple-native)
- **Stack:** SwiftUI + SwiftData + Swift Concurrency
- **Version:** 1.1 spec (free-form task tracker supersedes the per-rep cycling counter)

---

## 1. Purpose & Problem

Athletes doing "benchmark" workouts (Cindy, Murph, Fran, etc.) want to know **how many rounds they completed** in a given effort, and — over time — whether they're getting faster.

The app provides a **focused timer** that counts completed *rounds* for a predefined (Girl / Hero) or custom workout, in one of two execution modes, and later surfaces a **historical results view** showing personal records (PRs), progress over time, and a shareable result card.

The predefined library follows the real **Girl** and **Hero** WOD catalog, supporting the full range of movements those WODs require: bodyweight, barbell, kettlebell, rope, rowing/bike, box jumps, sprints, runs, and muscle-ups.

---

## 2. Scope

### In scope (v1.0)
- **Predefined benchmark library** seeded from the Girl / Hero catalog (see § 8), including Cindy and Murph, extending to Fran, Angie, Grace, Diane, Helen, DT, and similar well-known benchmarks.
- **Custom workout creation** from a shipped movement catalog; custom WODs are editable and savable.
- **Two execution modes:** **For-time** and **Top-time**.
- **Free-form task tracker** that drives both modes: every exercise set (exercise × round) is a *task* with a remaining-rep count; the athlete logs reps against **any task in any order** via quick counters; rounds are tracked internally.
- **Pause/Resume**; paused time tracked and subtracted from active time (for-time).
- **Optional per-workout rest between rounds** (e.g. Barbara 5 rounds, 3 min rest); continuous WODs leave it off.
- SwiftData local storage + **optional iCloud sync**.
- **Historical results view:** time-window summary, per-WOD bests, PRs, "Δ vs last attempt", a progress chart.
- Share card (Share Sheet / screenshot).

### Explicitly out of scope (deferred)
- Streaks, daily/weekly goals, gamified nudges, community leaderboards.
- Apple Watch app (v2, behind a shared timer model).
- Apple Health integration (v1.5).
- Apple Sign-In / accounts (v1.5).
- Scheduling / EMOM / interval (structured timer) WOD styles. (Chelsea-style EMOM is deferred.)
- Android / web.

---

## 3. Domain Model (SwiftData)

### `Movement` (a movement *type*)
A catalogued movement category. Shared across WODs so weights/distance/equipment are modeled once.
| Field | Type | Notes |
|---|---|---|
| id | UUID | PK |
| name | String | e.g. "Thrusters", "Run", "Deadlift" |
| equipment | String? | `Barbell`/`Kettlebell`/`Rope`/`Rowing Machine`/`Bike`/`Box`/`Track`/`Power Rack`/`Ring`/`Sandbag`/`Bodyweight` (nullable) |
| category | String? | `Strength`/`Gymnastics`/`Power`/`Cardio`/`Sprint`/`Skill` (for grouping/filters) |
| iconName | String? | SF Symbol (optional; fallback to text) |

### `Exercise` (a *dose* of a movement inside a WOD)
A concrete prescription that fills in the variable fields for one movement in one WOD. This is what the timer actually counts.
| Field | Type | Notes |
|---|---|---|
| id | UUID | PK |
| movement | relationship → `Movement` | FK (name lookup) |
| reps | Int? | e.g. 21 (nullable for distanced work) |
| weight | String? | e.g. "95 lb", "225 lb", "53/35 lb" (nullable) |
| distance | String? | e.g. "1 mi", "400 m", "800 m" (nullable; runs/sprints/row/bike) |
| distanceUnit | String? | derived from distance (mi/m) — optional explicit field |
| restSeconds | Int? | inter-round / inter-set rest built into the WOD (nullable) |
| displayLabel | String? | pre-rendered "21 Thrusters (95 lb)" so the UI never has to reformat — robust for sync |

**Seeding note:** `Movement`s are the stable catalog; `Exercise`s are the per-WOD prescriptions. Adding a new WOD = add a few `Exercise` rows referencing existing `Movement`s. `displayLabel` is pre-rendered so synced data renders identically on every device without re-formatting logic.

### `Workout`
A named set of `RoundBlock`s with a mode (predefined benchmark OR user-created).
| Field | Type | Notes |
|---|---|---|
| id | UUID | PK |
| name | String | "Cindy", "Murph", "My HIIT", etc. |
| description | String? | e.g. "AMRAP 20 min" / "For time" |
| category | String? | `Girl` / `Hero` / `Custom` — drives grouping and the seed library |
| mode | `ExecutionMode` | `.forTime` or `.topTime` |
| blocks | [RoundBlock] | ordered; for-time blocks loop until clock, top-time play once |
| isBuiltin | Bool | benchmark presets vs. user WODs |
| createdAt / updatedAt | Date | |
| category | String? | `Girl` / `Hero` / `Custom` — drives grouping and the seed library |
| mode | `ExecutionMode` | `.forTime` or `.topTime` |
| blocks | [RoundBlock] | ordered; for-time blocks loop until clock, top-time play once |
| isBuiltin | Bool | benchmark presets vs. user WODs |
| createdAt / updatedAt | Date | |

**Rest between rounds** is an *optional per-workout* feature: set on each `Exercise.restSeconds` (or a `Workout.restBetweenRoundsSeconds`). Continuous WODs (Cindy, Fran, DT) leave it `nil`; spaced WODs (Barbara) set it. The field is present in v1; it only does something when populated.

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

`activeTime = elapsedTime − pausedTime`, computed at save time (in the timer service / view model).

### `WorkoutRecord` (higher-level row for history views / sync)
> Prefer a separate `WorkoutRecord` table over denormalizing stats onto `Workout`: keeps `Workout` clean and makes "best rounds" an easy aggregate query.

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
1. Home lists WODs (builtins first, grouped Girl / Hero, then custom). Tap **Cindy**.
2. Detail shows scheme (5/10/15), mode **For-time 20:00**, movement labels, a **Start** button.
3. Tap Start → timer screen: an initial **Start Workout** gate showing the scheme, then the count-up clock at 00:00 with the remaining-set list at round 0.
4. Every set is listed as a task with its remaining rep count ("21 Thrusters (95 lb) — 21 left"). Tap a set to select it, then log reps with the **+1/+5/+10/+25** quick counters — in any order. Depleting every set in a block advances the round counter internally (one play of the current `RoundBlock`); AMRAP blocks regenerate a fresh wave and the clock keeps running.
5. **Pause/Resume**: freezing the clock; paused seconds accumulate and are subtracted from active time. Rest-between-rounds (if any) is handled automatically when a round completes.
6. Tap **Finish** → attempt saved (resultType = rounds, roundCount, elapsedTime, pausedTime, activeTime).

### Flow B — Start a top-time WOD
1. Pick a top-time workout.
2. Timer screen shows progress toward the final block; **Start**.
3. Reps are logged against any remaining set (same free-form tracker); the app detects the session end when **every task is depleted** and **auto-stops**, recording elapsed active time.
4. Results overlay shows the time; **Share** and **Finish** (early end, if any).

### Flow C — History / stats
1. Results tab: window summary ("Past 30 days: X workouts, Y PRs"), per-WOD bests with Δ vs. last, a progress chart of best-over-time, and a "View attempts" drill-down.
2. Window default = **1 month**; user can switch between 7 / 30 / 90 days / all-time (saved as default preference).

### Flow D — Create a custom WOD
1. "Create WOD" → pick movements from the catalog → set reps / weight / distance as needed → choose mode (for-time w/ minutes, or top-time) → optional rest between rounds → name it → Save (synced).

---

## 5. UI Screens (proposed)
1. **Home** — WODs grouped by category (Girl / Hero), then Custom; Start buttons; quick entry to results.
2. **WOD Detail** — scheme, movement labels (with weight/distance/equipment), mode, Start, edit/delete.
3. **Timer** — core screen: big count-up clock with time-cap label, free-form remaining-set tracker with quick counters, Pause/Resume, Finish; rest indicator when applicable.
4. **Results / History** — window summary, PRs, chart, attempts drill-down.
5. **Create WOD** — form for building custom workouts.
6. **Settings** — iCloud sync toggle, time-window default, preferences.

*No full mockups yet — review via visual companion if desired.*

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
│   Movement · Exercise · Workout ·               │
│   WorkoutRecord · WorkoutAttempt                │
│   + BenchmarkSeed (data source for built-ins)  │
└───────────────────────────────────────────────┘
                       │  ModelContainer
┌───────────────────────────────────────────────┐
│  Services                                       │
│   WorkoutTimerService (clock, pause, rest,     │
│   task tracker, auto-stop, active time)        │
│   ResultsService (windowed aggregation/PRs)    │
│   SyncService (optional iCloud CloudKit)        │
└───────────────────────────────────────────────┘
```

- **Timer logic** lives in a `WorkoutTimerService` (actor/class) so the view stays declarative; it owns start/pause/resume/finish, the free-form task tracker, optional per-round rest, and active-time computation.
- On **finish / auto-stop**, the service writes the `WorkoutAttempt` + `WorkoutRecord` via the `ModelContext`.
- **ResultsService** provides pure functions/queries for windowed stats, bests, and PR detection ("is this attempt better than the user's prior best for that workout").
- **SyncService**: CloudKit-backed SwiftData container. Sync **opt-in** (Settings toggle); defaults to on per plan but graceful when unavailable/disabled.

---

## 7. Data & Sync
- **Persistence:** SwiftData `ModelContainer` (in-memory + persistent).
- **CloudKit sync:** Opt-in via Settings. Public database, no server, no account. Pre-rendered `Exercise.displayLabel` ensures identical rendering across devices.
- **Offline-first:** all reads/writes local first; CloudKit mirrors in background. Workout data never leaves the device unless iCloud is enabled.
- **Privacy:** default private; iCloud optional.

---

## 8. Seeded Library (Girl / Hero WODs)

Movement taxonomy supported from the start: bodyweight, barbell (squat/clean&jerk/snatch/deadlift/bench press), kettlebell (thrusters/swings), rope (double-unders/triple-unders/climb), rowing machine, bike, box jumps, sprints, runs, muscle-ups, etc.

### Canonical seed set (accurate prescriptions)
| Workout | Category | Mode | Scheme (working block, ordered) | Rest |
|---|---|---|---|---|
| **Cindy** | Girl | For-time | 5 Pull-ups, 10 Push-ups, 15 Air Squats (×N) | none |
| **Murph** | Hero | Top-time | 100 Pull-ups, 200 Push-ups, 300 Air Squats (single pass) | none |
| **Fran** | Girl | Top-time | Block A = 21 Thrusters (95 lb) + 21 Pull-ups; Block B = 15 of each; Block C = 9 of each | none |
| **Angie** | Hero | Top-time | 100 Pull-ups, 100 Push-ups, 100 Sit-ups, 100 Air Squats (single pass) | none |
| **Grace** | Girl | Top-time | 30 Clean & Jerk (135/95 lb) | none |
| **Diane** | Girl | Top-time | Block = 21 Deadlifts (225 lb) + 21 HSPU; ×3 (21-15-9) | none |
| **Helen** | Girl | Top-time | 400 m Run, 21 Kettlebell Swings (53/35 lb), 12 Pull-ups (×3) | none |
| **DT** | Hero | Top-time | 12 Deadlifts (225 lb), 9 Hang Power Cleans (155 lb), 6 Push Jerks (155 lb) (×5 rounds) | none |

### Notes on the catalog
- The library is a **seed source** (`BenchmarkSeed`). The full Girl catalog (~27) and Hero catalog (200+) exist as reference; seeding proceeds in phases (v1 ≈ table above), then Fran-family / additional Girls, then more Heroes.
- **Murph variant:** canonical Hero Murph includes two 1 mi runs (1 mi run → 100/200/300 → 1 mi run, traditionally with a 20 lb vest). The v1 seed is the **bodyweight-only** 100/200/300 version; the run-based variant is supported (via the `Run` movement + distance) and can be seeded later.
- **Rest between rounds:** seed set above is all continuous. Spaced WODs like **Barbara** (5 rounds, 3 min rest: 20 pull-ups / 30 push-ups / 40 sit-ups / 50 air squats) demonstrate the optional `restSeconds` feature and can be added in a later phase.
- Equipment & weight are core, not an afterthought — the movement catalog is intentionally wide so any Girl/Hero WOD can be added by filling `Exercise` rows.

---

## 9. Non-Functional Requirements
- **Offline-first**, instant launch, no network calls in the timer path.
- Reliable for short sessions; foreground timer is primary.
- Accessibility: Dynamic Type, VoiceOver-labeled clock and counter, large hit targets.
- Clear timer and rest indicators so counting/miscounting is minimized.

## 10. Acceptance Criteria
- [ ] Can run Cindy (for-time 20 min) using the free-form tracker; pausing subtracts from active time; Finish saves a `WorkoutRecord`.
- [ ] Can run Murph (top-time, bodyweight) and the timer auto-stops when every set is depleted, recording elapsed active time.
- [ ] Can complete sets **out of program order** (e.g. finish squats before pull-ups in Murph) and the session still auto-stops correctly.
- [ ] Can run a descending/multi-block WOD (Fran-style) where each block is a round and the session auto-stops.
- [ ] Can build a custom WOD with reps + weight/distance + equipment + optional rest between rounds; it syncs (if iCloud on).
- [ ] Results screen shows 7/30/90-day/all-time windows, per-WOD bests, PRs, Δ vs. last, a progress chart, and a share card.
- [ ] iCloud sync is toggleable and, when enabled, propagates records across devices.

## 11. Deferred Roadmap
1. **v1.5:** Apple Health (write workout result), Apple Sign-In (optional).
2. **v2:** Apple Watch app reusing the shared `WorkoutTimerService` and model.
3. **Later:** broader Hero/Girl seed set; Barbara-style spaced WODs; EMOM/scheduling WOD styles.

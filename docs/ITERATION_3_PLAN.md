# Jimm's Bro+ — v1.2 plan (iteration 3)

Two inputs drove this release.

1. **The code-health review** (2026-09-07): four confirmed defects, one broken build route,
   repository hygiene, and three structural concerns. Recorded in `docs/CODE_HEALTH_REVIEW.md`.
2. **The owner's notes after using v1.1 on the phone**: the workout does not say clearly
   enough where you are in it, there is no warm-up, the gap between exercises is neither
   timed nor settable, the set suggestions are weak and can suggest a weight you cannot
   load, the timer should reach the Lock Screen and the Dynamic Island, the calendar and
   the next-day choice feel clunky and compound after a missed day, and a past workout
   should be openable with real metrics attached.

Milestones **V0–V8, in order**. Each ends with the full suite green
(`xcodebuild test -scheme JimmsBro -destination 'platform=iOS Simulator,name=iPhone 16'`)
and one commit. SPEC amendments land **before** the code that depends on them, as in v1.1.

---

## V0 — Repository hygiene (no app code)

- Delete the leftover history-rewrite refs (`refs/original/*`, `refs/backup/pre-rewrite`,
  `refs/codex/turn-diffs/*`), expire the reflog, `git gc --prune=now`. **Done.**
- Work on the `v1.2-refinement` branch; commit per milestone; never Claude as co-author.
- Move the two real sources out of the git-ignored `build/` folder into `tools/`
  (`tools/icon/main.swift`, `tools/seed/main.swift`) so a clean clone keeps them.
- Delete the ten stale `.gitkeep` files in Feature folders that now hold real files.
- Keep `HANDOFF_BUNDLE.md` and the zip, but add `tools/check_bundle.py`, which fails when
  either has drifted from the sources it is built from, and regenerate both at V8.

## V1 — The four confirmed defects, and the broken build route

| # | Defect | Fix |
|---|---|---|
| 1 | Editing a plan silently changes a superset's between-round rest | `PlanJSON.render` emits the group's round rest as an exercise-level `restSeconds`, so re-import reconstructs `groupRestSeconds`. Round-trip test over every grouped fixture. |
| 2 | Retry on the save-failure alert is a no-op | Capture the failure synchronously in the button action; `retrySaveFailure(_:)` takes it as a parameter. |
| 3 | Hold-to-repeat on − / + cancels itself | `minimumDuration: .infinity`, so `pressing(false)` only ever means "finger lifted". |
| 4 | Every weight keystroke writes `active-session.json` | `setWorkWeight` no longer emits `.persist`; the view pushes the weight when editing ends, not per keystroke. |
| 5 | `swift test` does not compile | `Package.swift` → `.macOS(.v14)` (`@Observable`), and the one bundle-resource test reads the source tree under SwiftPM. |

Smaller, same milestone: bound the DEBUG polling loop in `HistoryView`; make
`Store.restore` truthful about `.replaceAll` (it deletes before writing); give
`exportData`/`readBackup`/`restore` a read path that does not silently set corrupt files
aside; `Phase.init(from:)` throws on an unrecognised payload instead of decoding it as
`.completed`; replace the two `\.first!` key paths.

## V2 — Schema durability (prerequisite for V3's new fields)

Adding one field to `Settings` today makes every existing `settings.json` "corrupt" and
moves it aside, because synthesized `Codable` treats a defaulted property as a required key.
V3 adds three. So this comes first.

- Hand-written, lenient `init(from:)` for `Settings`, `SetTarget` and `Plan`: every field
  optional, missing keys take the default.
- Freeze a v1 file of each type under `examples/store/` and decode each in a test, so a
  future field cannot break an old file without a red test (this is G59's missing test).
- `IssueCode` and `AlertIdentifier` as enums, used everywhere (ten raw literals today).
- One definition each for: block grouping (Overview + Session detail), `ExerciseText.result`,
  and the date/stat maths Summary, ExerciseHistory and Home each re-derive.
- Pin `Prompts.planTemplate` to `docs/PROMPT.md` with a test, and stop carrying the example
  JSON twice.
- Test hygiene: `makeRoot()`/`discard()` once in `CoreTestSupport`; `RecordingAlerts` moves
  out of the app target; the three wall-clock assertions get tolerances.

## V3 — Warm-up, the gap between exercises, and where you are (owner notes 1–3)

SPEC §4.5, §4.7, §6.3 and §6.6 amended first.

- **Warm-up (D32).** A session starts in a warm-up stage rather than on set 1: a settable
  duration (`Settings.warmUpSeconds`, default 5 min, 0 = off), the first exercise already
  named, **Start warm-up** / **Skip warm-up**, and the same status strip everything else uses.
- **Between-exercise rest (D33).** A finished block no longer advances with no rest at all.
  `Advance.blockDone` carries a rest, from the plan's optional `transitionRestSeconds` or
  `Settings.transitionRestSeconds` (default 120 s). It does not gate the next set — the next
  exercise's card is already up, exactly as in v1.1 — it runs a visible countdown in the strip.
- **Stage (D34).** The screen says which stage it is in, in words and as one progress bar:
  `Warm-up → Exercise 2 of 6 · Set 2 of 4 → Between exercises → Done`. `WorkoutStage` is
  resolved in Core, so the wording is a unit test.

## V4 — Sets and suggestions (owner notes 4–5)

- **`WeightRounding` (D35).** No suggestion is ever a weight you cannot load. A new
  `Settings.weightIncrementKg` / `weightIncrementLb` (the smallest change the equipment
  actually allows; default 2.5 kg / 5 lb) snaps every suggested and stepped weight.
  "134 lb next time" becomes "135 lb".
- **`SetSuggestion` (D36).** Per set, not per exercise: the target, what you did last time
  for *that* set, and the suggestion with its reason in one line — "last time 8 × 60, try
  8 × 62.5". Shown on the current set row and behind the suggestion chip.

## V5 — The calendar and the next day (owner note 7)

- **Anchored rotation (D37).** A rotation projects from an anchor date, so one missed day no
  longer slides the whole calendar forward for ever. A day you missed is surfaced on Home as
  a choice — **Do it next** or **Skip it** — rather than resolved silently.
- **Legible spacing.** Cells name the day, rest days are drawn as gaps rather than as dots
  the same size as everything else, and the month grid paints the whole horizon for a
  rest-free cycle instead of only tomorrow.

## V6 — Past workouts and metrics (owner note 8)

- Open any past workout from Home, the calendar, or History, and read what it actually was:
  duration, working time, rest time, volume, sets, PRs, per-exercise comparison.
- A **Metrics** section over time: sessions a week, volume a week, and per-exercise best.
  All computed in Core (`SessionMetrics`, `TrendMetrics`), all unit-tested.

## V7 — Live Activity: Lock Screen and Dynamic Island (owner note 6)

- A widget extension target (`JimmsBroActivity`) with an ActivityKit rest/warm-up/timed-set
  activity: time remaining, exercise, set, and the same −30 / +30 / Skip controls.
- Core stays free of ActivityKit: the engine emits `Effect.activity(...)`, and an
  `ActivityPresenting` protocol is injected exactly as `NotificationScheduling` is, so the
  behavior is unit-tested and the extension is a thin renderer.

## V8 — Docs, bundle, checklist

- Reconcile README, `BUILD_STATUS.md`, `DECISIONS_LOG.md`, SPEC §8, `TEST_CASES.md` and the
  simulator name with what the machine actually does.
- New test cases added to `TEST_CASES.md` as they land, per milestone, not in a batch at the end.
- `DEVICE_CHECKLIST.md` gains a v1.2 section (warm-up, transition rest, Live Activity,
  calendar, metrics), still marked not-run until the owner runs it.
- Regenerate `HANDOFF_BUNDLE.md` and the zip; `tools/check_bundle.py` must pass.

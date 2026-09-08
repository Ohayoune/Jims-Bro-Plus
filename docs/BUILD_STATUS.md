# Build status

Updated 2026-09-08. **v1.3 (X0–X6) is built and green; the device checklist needs the phone.**
v1.2, v1.1 and v1 are below, unchanged except where a later milestone corrected them.

## v1.3 (X0–X6): built and green

`docs/ITERATION_4_PLAN.md` is the v1.3 plan — the owner's list after running v1.2, with
"implement them seamlessly" attached to all of it. Every milestone ended with the whole suite
green on all three routes and one commit, on the `v1.3-refinement` branch (off
`v1.2-refinement`, which is not yet merged to main).

| Route | Result |
|---|---|
| `xcodebuild test -scheme JimmsBro -destination 'platform=iOS Simulator,name=iPhone 16'` | **246 tests, 3 skipped, 0 failures** |
| `swift test` | **245 tests, 0 failures** |
| `python3 tools/check_core.py` | **245 bodies, 4,055 assertions, 0 failures** |
| `python3 tools/reference_import.py` | **111/111 fixtures match** |
| `python3 tools/check_bundle.py` | **current** |

The three skipped cases are the prompt pins (M9 and W37), which read `docs/PROMPT.md` from the
checkout — outside the simulator's sandbox. They run on the other two routes.

| Milestone | What it did | State |
|---|---|---|
| X0 | The plan, the branch | Done |
| X1 | The Dynamic Island the width of its timer: `timerRange` in Core, never inverted, never an hour (D41) | Done |
| X2 | Change exercise mid-workout: pending steps to a new name that keeps its own history; a split when something was logged (D42) | Done |
| X3 | JSON edits at every size, spliced into the plan's own tree and re-imported; Edit JSON, Add day / Add exercise from JSON (D43). Fixed on the way: a plan edit and Replace both dropped `cycleAnchor` | Done |
| X4 | History as CSV in Strong's column order, and a reader for its own, Strong's and Hevy's exports by header name; read-then-describe-then-Import (D45) | Done |
| X5 | Progression: the prompt out, the reply in, the week applied to the day's snapshot, the chip's reason, Home's line (D44) | Done |
| X6 | Docs, checklist rows, bundle | Done |
| — | The v1.3 device rows (W3, W12, W21, W30, W40) | **Written, not run** — needs the owner's iPhone |

### Checked on the simulator (v1.3)

Every screenshot is from a real build on a booted simulator, seeded through the app's own `Store`.

| File | Shows |
|---|---|
| `build/x2-change.png` | The Change exercise sheet over a running workout: the name field, the exercises done before, the optional weight, **Change** |
| `build/x3-plan.png` | Plan detail with the Progression row and, in the menus, Edit JSON, Add day from JSON, Add exercise and Edit day as JSON |
| `build/x5-home.png` | Home with a progression on the plan: the subtitle ends "week 1 of 4", and nothing else moved |
| `build/x5-progression.png` | The Progression screen reading a saved progression back: the week, this week's targets first, every week in one line, **Plan the next one** |

### Not run in v1.3

The Island's width (W3) needs a phone with one. What the compact view is given is unit-tested
(`timerRange`, W1–W2), but nothing here has measured it on a Dynamic Island.


## v1.2 (V0–V7): built and green

`docs/ITERATION_3_PLAN.md` is the v1.2 plan, and `docs/CODE_HEALTH_REVIEW.md` is the review that
prompted half of it; the other half is the owner's notes after running v1.1 on the phone. Every
milestone ended with the whole suite green and one commit, on the `v1.2-refinement` branch.

| Route | Result |
|---|---|
| `xcodebuild test -scheme JimmsBro -destination 'platform=iOS Simulator,name=iPhone 16'` | **210 tests, 2 skipped, 0 failures** |
| `swift test` | **209 tests, 0 failures** — this route had not compiled since `AppModel` became `@Observable`; V1 fixed it |
| `python3 tools/check_core.py` | **209 bodies, 3,289 assertions, 0 failures** |
| `python3 tools/reference_import.py` | **111/111 fixtures match** |
| `python3 tools/check_bundle.py` | **current** |

The two skipped cases are the prompt pins (M9), which read `docs/PROMPT.md` from the checkout —
outside the simulator's sandbox. They run on the other two routes, both of which are on the host.

| Milestone | What it did | State |
|---|---|---|
| V0 | Repository hygiene: leftover rewrite refs deleted, `tools/icon` and `tools/seed` rescued from the ignored `build/`, `tools/check_bundle.py` | Done |
| V1 | The five confirmed defects of the code-health review, and `swift test` unbroken | Done |
| V2 | Schema durability (`Core/Persistence.swift`, `examples/store/v1/`), `AlertIdentifier` and `SessionBlocks` as one definition each, the prompt pinned to its doc | Done |
| V3 | Warm-up (D32), the timed walk between exercises (D33), the stage in the header (D34) | Done |
| V4 | Loadable weights (D35) and a per-set suggestion with its reason (D36) | Done |
| V5 | The anchored rotation (D37) and a calendar you can read (D38) | Done |
| V6 | Session and trend metrics (D39) | Done |
| V7 | Lock Screen and Dynamic Island (D40), and the `JimmsBroActivity` extension target | Done |
| — | The v1.2 device checklist | **Written, not run** — needs the owner's iPhone |

### Checked on the simulator (v1.2)

Every screenshot is from a real build on a booted simulator, seeded through the app's own `Store`.

| File | Shows |
|---|---|
| `build/v3-warmup.png` | A session opening in a warm-up: the stage named, the countdown, the first exercise already up, **Log set** live |
| `build/v3-resting.png` | The same screen resting between sets |
| `build/v3-between.png` | The walk between exercises: its own countdown, the next exercise already showing, the finished block's sentence on the strip |
| `build/v5-home.png` | Home and the week strip agreeing: "Rest day · Push is next, Tue" over a grid that names each day and draws the rest day as a gap |
| `build/v6-metrics.png` | A past workout's metrics: duration, working and resting share, sets, volume, reps, heaviest set, PRs |

### Not run in v1.2

The Live Activity itself (Q71–Q73) needs a phone: the extension builds, embeds and installs, and
what it would draw is unit-tested through `ActivityPresenting`, but nothing here has watched it
appear on a Lock Screen.

## v1.1 (refinement release): R0–R5 done, R6 open

`docs/ITERATION_2_PLAN.md` is the v1.1 plan. R0 through R5 are implemented and green:
`xcodebuild test` reports **148 tests, 0 failures** on the iPhone 16 simulator, and the portable
Core runner reports **147 test bodies, 2,939 assertions, 0 failures**. SPEC.md, TEST_CASES.md and
DECISIONS_LOG.md were amended alongside the code, per milestone, before it was written.

| Milestone | What it did | State |
|---|---|---|
| R0 | Truthfulness: skipped-set recovery (D27), every delete confirms (D25), Replace, the activation toggle, calendar taps that open the session, and a surfaced save failure with Retry (D24) | Done |
| R1 | Core for the new loop: `.transition` removed (D14), `blockDone`, undo (D23), the prefill rule for varied exercises (D11) | Done |
| R2 | The workout screen rebuilt as five fixed zones (D22) | Done |
| R3 | Home leading with the workout (D18) and **Add plan** replacing the JSON editor (D26) | Done |
| R4 | One visual language, and the Summary said in words | Done |
| R5 | Do later (D28), plan editing (D29), the exercise chart, search and PR marker (D30), backup restore (D31) | Done |
| R6 | Device checklist v2 | **Written, not run** — needs the owner's iPhone |

### What changed, by milestone

- **R0** — `SessionEngine.editSet` recovers a skipped step (D27) instead of silently doing
  nothing; every plan/session delete confirms (D25); Plan detail gained **Replace**; the import
  preview gained a **Set as current plan** toggle; the Home calendar's second tap on a completed
  day opens it; a failed write is surfaced as `AppModel.saveFailure` with **Retry**. A real bug
  was caught by the new failure-injection test, not by inspection: `SessionRunner.run(_:)` was
  clearing `active-session.json` on a batch's trailing `.persist` even when the session's own
  save had just failed.
- **R1** — the `.transition` phase is gone (D14); a v1 file holding it still decodes.
  `Event.undoLog` (D23). Prefill no longer carries a weight forward across a **varied**
  exercise's sets (D11), and the dynamic "changing weight re-prefills reps" rule is removed.
- **R2** — the workout is one screen with five fixed zones (SPEC §4.5, D22), resolved as data by
  `WorkoutScreen.model` so "the zones never move" is a unit test (O50) rather than a convention.
  Rest, the block-done line and the timed-set state are contents of one status strip; the primary
  button never moves; Exercises, minimize and "···" are reachable in every state. Undo moved onto
  the strip. Three defects were found on the simulator: notes repeating on every set row, two
  superset rows reading identically (`StepCard.rowLabel` now lives in Core and is shared with the
  Overview and Session detail), and the header wrapping to four lines at accessibility XL.
- **R3** — Home names the day, the plan and its exercises and says what its button will do (D18);
  a 7-day strip discloses to the month; one activity line replaced the sparkline, which was
  removed along with `HomeMetric` and its Settings row. **Add plan** (D26) offers Paste plan,
  the three-step chatbot round-trip and Import file, with the JSON editor behind "Show text";
  errors lead with a sentence (`IssueText.friendly`, one per `E_` code); **Review plan** shows the
  exercises with per-set targets and separates material warnings from tidying.
- **R4** — one grouped-list language on every screen, a green reserved for "this happened",
  pressed states, and a Summary that says "2 more reps at the same weight" instead of printing
  both sessions' raw sets. Volume totals are grouped ("12,400 kg").
- **R5** — **Do later** (D28) moves an exercise's remaining sets to the end of the day; **plan
  editing** (D29) renders a plan back to JSON and re-imports it, so an edit is validated by the
  import pipeline itself (C40 asserts that round trip over every valid fixture, and caught a real
  bug: an "off" warning beep has to be written as an explicit `false`); the **exercise chart**,
  History **search** and the **PR** marker (D30); and **backup restore** with Merge / Replace all
  (D31).
- **R6** — `docs/DEVICE_CHECKLIST.md` gained a v1.1 section (H24, H33, O53–O60, O76–O82, K27–K28
  and the T2–T6 acceptance tasks) and `-uiReadOnlyStore`, a DEBUG-only argument that makes every
  write fail so D24's Retry path can be exercised on a real phone. Building it found a genuine
  bug: the save-failure alert was attached only to `RootView`, which the workout is presented
  *over*, so a failed write mid-workout showed nothing at all. Fixed, and visible in
  `build/r6-savefail.png`.

### Checked on the simulator (v1.1)

Every screenshot is from a real build on a booted simulator, seeded through the app's own `Store`.

| File | Shows |
|---|---|
| `build/r2-working.png` | The five zones, working: header, exercise + set rows, labelled inputs, empty strip, Log set |
| `build/r2-resting.png` | Resting: countdown, −30/+30/Skip, "Next: …", "set 0:06" and Undo, with the set rows still on screen |
| `build/r2-blockdone.png` | A finished block: the next exercise already showing, the block's line and "moving on · 0:03" in the strip, no Continue gate |
| `build/r2-superset.png` | A superset round, its rows named by exercise rather than all reading "A · Set 3 of 3" |
| `build/r2-timed.png` | A timed set: TIME label, 0:45, **Start timer** in the same primary slot, no weight row |
| `build/r2-xl.png` | Accessibility XL: the header reflowed to two rows, rest controls on their own row, nothing clipped |
| `build/r4-workout.png`, `build/r4-dark.png` | The R4 visual pass, light and dark |
| `build/r4-summary.png` | "Workout saved", one sentence per exercise, the set table only where the weights varied |
| `build/r3-home.png` | Home leading with the workout, the week strip and the activity line |
| `build/r3-addplan.png`, `build/r3-review.png`, `build/r3-errors.png` | Add plan's three ways in; Review plan with per-set targets; an error said in a sentence |
| `build/r5-plandetail.png` | Plan detail with Edit, per-day menus and per-set variation |
| `build/r5-exercise.png` | The exercise chart, top weight over time with reps annotated |
| `build/r6-savefail.png` | The save-failure alert over the workout screen, with Retry |

### Not done

- **R6's rows have not been run.** They need the owner's iPhone. Signing is already configured
  (`DEVELOPMENT_TEAM = 3CDZYD6W6G` on both targets), so nothing blocks a device build but the
  phone being plugged in — see `docs/DEVICE_CHECKLIST.md`.
- ITERATION_2_PLAN §7 step 4 asks for the owner's phone walkthrough of T2–T6 after R2, before R3.
  That checkpoint was **not** taken: R3–R5 were built straight through on the instruction to
  complete the remaining refinements. If the walkthrough turns up something about the workout
  screen, R3–R5 sit on top of it.
- The six owner decisions in ITERATION_2_PLAN §9 were never answered in writing. Everything above
  was built on the plan's own recommendation for each, which is now recorded in SPEC §1 (D18,
  D22–D31) as the contract.

## v1 (M0–M7)

M0 through M7 are implemented and **certified on iOS XCTest and the Simulator**: `xcodebuild test`
runs the whole suite green on the iPhone 16 simulator. (The M7-era licence blocker and the beta
Xcode in `~/Downloads` are gone: there is one Xcode, at `/Applications/Xcode.app`, and a plain
`xcodebuild` works.)

M4's and M5's screens are built and were checked on the simulator (see **Screens checked** below).
Start and Resume now run a real workout end to end: step card, rest, the between-exercises done screen,
timed sets, overview, summary and resume after a relaunch. History lists finished workouts by month,
with an editable, deletable session detail and a per-exercise history showing the best set. Settings is
complete, including export and delete-all, and the polish pass is done: dark mode, Dynamic Type to
accessibility XL, VoiceOver labels, and an app icon.

What remained after M7 was M8: the `manual` cases in `TEST_CASES.md`, which need the owner's iPhone. They are still outstanding, now as part of v1.2's device checklist.

## Results actually run

| Check | Result |
|---|---|
| **iOS XCTest + Simulator (beta Xcode, iPhone 16)** | **97 tests, 0 failures — `** TEST SUCCEEDED **`** |
| M0 hosted resource test (`ProjectSkeletonTests`) | Passed on the simulator; no longer pending |
| M3 store tests (`StoreTests`, K1–K15) | 15 tests, 0 failures |
| M4 settings/home tests (`SettingsAndHomeTests`, N1–N2, N8–N10) | 14 tests, 0 failures |
| M5 workout tests (`WorkoutTests`, N3–N7, H1, H2, H17) | 15 tests, 0 failures |
| M6 history tests (`HistoryTests`, O14–O16) | 8 tests, 0 failures |
| M7 settings/polish tests (`SettingsPolishTests`) | 7 tests, 0 failures |
| Portable Core checks (Command Line Tools) | 96 test bodies, 2,022 assertions, 0 failures |
| Python reference importer | 111/111 fixtures match the manifest |
| Original fixture integrity | 112/112 files under `examples/` match the design-package zip byte-for-byte |
| Core isolation | No SwiftUI/UIKit imports in `Core/` or `Store/` |
| M0 simulator visual check | App installs and launches on a booted simulator, showing its name (`build/m3-home.png`); no longer pending |

Logs and result bundles: `build/M7-beta.xcresult`, `build/m7-beta-tests.log` (generated, ignored by git).

## Screens checked on the simulator

Each was captured from a real build on a booted simulator, with the store seeded through the app's own
`Store` code (`tools/seed/`). Screenshots are in `build/`.

| Case | Screen | Result |
|---|---|---|
| O1 | Empty Home | Two buttons, four tabs; "Try the sample plan" imports and activates |
| O2 | Import, text on the clipboard | Paste enabled, editor fills |
| O3 | Import, no text on the clipboard | PasteButton disabled; nothing happens |
| O4 | Import error list | Each row shows path, message and code; Copy fix-it prompt present |
| O5 | Preview sheet | Warnings in yellow with paths, day table counts, cycle chips |
| O6 | Name conflict | Replace / Keep both / Cancel all present |
| O29 | Home with data | Start card, calendar, sparkline, four tabs; nothing else |
| O30 | Calendar dots | Filled accent for completed, hollow accent for projected, grey for scheduled rest days, none for days the plan says nothing about, today outlined |
| O31 | Sparkline | 44 pt, no axes, one caption; metric cycles and persists |
| O35 | Plan detail repeat block | Chips with the current position highlighted, "repeats every 7 days" |
| O38 | Preview cycle chips | Present |
| O9 | Step card order and fit | Name, set line, target, bold last-time entry, reps row, weight row + Last line, Log set directly beneath |
| O9c | Rest overlay | Countdown largest, −30/+30, "Next: …", set time on top, Skip rest |
| O10 / O43 | Overview | Grouped by block with durations; logged rows read "8 @ 80 · 0:00"; pending rows show the target; drops and superset members named |
| O13 | Summary | Duration, sets, volume; per exercise duration, this-vs-last, advice |
| O32 | Done screen | Block name, duration largest, advice, running stopwatch, one Continue button |
| O34 | Drop rows | "· drop 1 of 2" with the weight prefilled from the previous step |
| O39 | Bodyweight card | No weight row; Log set directly under the reps row |
| O41 | Fixed-duration card | Countdown with Done; the number turns accent at the warning |
| O14 | History list | Grouped by month, newest month and newest session first, with duration · sets · volume |
| O15 | Session detail | Every set editable; exercises grouped with block durations; delete behind "···" |
| O16 | Exercise history | Best set on top, sessions newest first; reachable from the step card, session detail and summary |
| O17 | Dark mode | Every screen legible; the countdown stays primary while resting and turns accent on overrun, so the two states are distinct |
| O18 | Dynamic Type at accessibility XL | Nothing clipped; the target line wraps; Log set fully on screen |
| O19 | VoiceOver | The card's description is one element reading "Bench Press, set 2 of 4, target 8 to 12 reps, at 60 kilograms"; "Rest over" is announced once at zero |

Three rendering defects were found and fixed this way: the calendar's weekday header collapsed to five
columns, the primary buttons were not full width, and the sparkline rendered empty whenever no two
workout days were adjacent.

M6's pass found one more: the History month headings were a month early whenever a session sat near a
month boundary, because the section key is the month's first instant in the injected calendar while the
formatter was still reading it in the system zone.

M5's pass found and fixed three more: the workout dismissed straight past the Summary (the engine is
cleared the instant a session completes, so the finished session needed its own hold), Log set was
pinned to the screen bottom leaving a dead gap instead of sitting under the weight row, and every row
of a superset in the overview read "A · Set 1 of 3" with no way to tell the two exercises apart.

After M4 the owner asked for scheduled rest days to be visible. `DayEntry` gained a `.rest` case, rest
days now draw a grey dot and tapping one reads "Sun 14 · Rest day", while days the plan says nothing
about still draw nothing. SPEC §4.1 and §6.12, TEST_CASES O30, `HANDOFF_BUNDLE.md` and the docs inside
`JimmsBro-design-package.zip` were all updated to match (`build/o30-rest-dots.png`).

The portable runner executes the real test methods in `JimmsBroTests` through the assertion adapters
in `tools/CoreCheckSupport.swift`. It discovers no-argument `test*` methods (sync and async), refuses
an empty filtered run, and exits nonzero on any failure. It excludes `ProjectSkeletonTests`, which
needs the app and test resource bundles. It is a Core behavior check; the xcodebuild run above is the
authoritative one.

## Implemented and tested areas

| Source/test area | Behaviors |
|---|---|
| Models, RawJSON, PlanImport / ImportTests | Codable models; extraction, strict decoding, normalization and validation; manifest codes/paths/warning multisets; expected normalized fields; limits and malformed input; identity and round trips |
| Steps, RestResolution / StepsAndEngineTests | All valid fixture step/rest expectations; groups, mismatched rounds, drops, block transitions, same-block wraps; 2,500-step flattening well inside budget |
| SessionEngine / StepsAndEngineTests | Logging/editing/skipping/jumping/finishing; Date-based rest; transitions; fixed/open work timers; notifications as effects; missed-beep reconciliation; persisted timer state and edited weight |
| Prefill / PrefillAndStatsTests | History filtering by name, unit and completion; current-session precedence; missing sets/weights; dynamic reps; drops; bodyweight; last-time formatting and suggestions |
| Stats, ProgressionAdvice / PrefillAndStatsTests | Volume, best set, block/set durations, advice thresholds and messages, editing advice, history series |
| PlanLibrary, PlanSchedule / LibraryCalendarPromptTests | Conflicts, activation, replacement, deletion, cycles, weekday lookup, switch-day coordination, completion/discard, history edits |
| CalendarProjection, Sparkline / LibraryCalendarPromptTests | Local calendar boundaries, projection horizon, rest cycles, completed days, seven-day metrics, unit filtering, captions, metric cycling |
| Prompts / LibraryCalendarPromptTests | 3,510-character prompt, unchanged JSON example data, fix-it errors, marker rejection, large valid input, truncated input, exact/over byte-limit handling |
| **Settings, delete-all, export, spoken card / SettingsPolishTests** | **Every remaining setting persisting independently; a silenced app playing nothing while still scheduling notifications; delete-all cancelling alerts, emptying the store and leaving it usable; the backup document; the notification-state row; the spoken step card for every target kind and unit** |
| HistoryGrouping, ExerciseText / HistoryTests | **Month grouping newest first with running sessions excluded and local-calendar boundaries; editing a past session persisting and feeding the next prefill; deleting one file and leaving the rest; best-set text with its weightless and timed fallbacks; per-exercise series by normalized name and unit |
| InputRules, StepCard, Alerts, SessionRunner / WorkoutTests | **Weight separators and rounding, rejected input, reps/seconds limits, steppers never below zero; step-card lines for every target kind; Date-based rest with rescheduled notifications; fixed and open timers with warning/end/minimum alerts and no replayed beeps; finish, discard, day switching, resume, and the finished session held for the Summary |
| AppModel, HomeCard / SettingsAndHomeTests | Locale unit defaults, weight steps, zero default rest, units changes leaving plans untouched, first-launch settings write, sample-plan import, start-card wording per schedule, repeat-block chips, import error rows and fix-it prompt, preview warnings and counts, conflict choices, plan list actions, corrupt-file alert, metric cycling |
| Store, StoreFiles / StoreTests | Atomic writes; corrupt and unknown-version files set aside and reported; per-event active-session persistence; complete/discard; ISO-8601 fractional dates; sorted-key stability; 1,000-session load; export document; delete-all; serialized concurrent writes |

Decisions and conflicting older test text are recorded in `DECISIONS_LOG.md`. Copy/paste research and
the limits of what was tested are in `COPY_PASTE_NOTES.md`.

## Reproduce

Authoritative iOS run:

```sh
xcodebuild test -scheme JimmsBro -destination 'platform=iOS Simulator,name=iPhone 16'
```

Portable Core checks, which need only the Command Line Tools:

```sh
python3 tools/check_core.py
python3 tools/reference_import.py
```

The manual cases are collected as a ready-to-run checklist in `DEVICE_CHECKLIST.md`.

## Remaining manual checks

K16 (kill the app mid-workout and relaunch) and K17 (reinstall from Xcode over the existing app) are
marked `manual` in `TEST_CASES.md` and need the resume banner from M5/M6 before they can be exercised.

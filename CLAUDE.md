# Jimm's Bro+ — implementation handoff

This file is the entry point for whichever coding agent builds the app: ChatGPT / Codex reads `AGENTS.md`, Claude Code reads `CLAUDE.md`. Both files are identical; if you edit one, copy it over the other.

You are implementing a native iOS workout-tracking app from a finished design.
The owner has already made the product decisions. Your job is to build exactly
what the docs describe, with tests, in the milestone order given.

## Read these first, in this order

1. `docs/SPEC.md` — what the app is, decisions already made, screens, behaviors, data model, persistence
2. `docs/PLAN_FORMAT.md` — the JSON plan format: fields, leniency rules, validation, error/warning codes
3. `docs/PROMPT.md` — the exact chatbot prompt text the app copies to the clipboard
4. `docs/TEST_CASES.md` — the test list. Every case marked `unit` must have a passing automated test
5. `docs/BUILD_PLAN.md` — milestones. Do them in order; each ends with green tests
6. `examples/` — fixture files and `manifest.json` (expected outcomes). Drive the import tests from these files
7. `tools/reference_import.py` — a Python reference implementation of the import pipeline, step flattening, and rest resolution. It passes the whole manifest (`python3 tools/reference_import.py`). Port its behavior to Swift; when a Swift test disagrees with the manifest, run the Python on the same file to see the intended result
8. `tools/generate_fixtures.py` — regenerates every file in `examples/` from scratch. If `examples/` is missing (for example you received only the bundle file), run it first

## v1.1 and v1.2 — the refinement releases

`docs/ITERATION_2_PLAN.md` is the v1.1 plan (milestones **R0–R6**) and
`docs/ITERATION_3_PLAN.md` is the v1.2 plan (milestones **V0–V8**), in order, with the SPEC
amendments landing before the code that depends on them. Everything through V7 is built and
green (and v1.3 on top of it, below); what remains is the device checklist, which needs the owner's iPhone
(`docs/DEVICE_CHECKLIST.md`). `docs/BUILD_STATUS.md` says what is done and what was actually run,
and `docs/CODE_HEALTH_REVIEW.md` records the review that prompted half of v1.2.

Read `docs/SPEC.md` as the contract, not the plan: where they disagree, SPEC wins, and the plans'
proposed test-case ids were renumbered on landing (TEST_CASES notes the mapping).

`docs/ITERATION_4_PLAN.md` is the v1.3 plan (milestones **X0–X6**): a narrower Dynamic Island
(D41), changing an exercise mid-workout (D42), JSON edits at every size (D43), history as CSV in
and out (D45), and **Progression** — the chatbot round-trip run the other way (D44,
`docs/PROGRESSION_FORMAT.md`, `docs/PROMPT.md` §3). Everything through X6 is built and green;
the v1.3 device rows (W3, W12, W21, W30, W40) join the checklist that still needs the phone.

`docs/ITERATION_5_PLAN.md` is the v1.4 plan (milestones **Y0–Y5**), the owner's notes after
running v1.3 on the phone: a tap's result before its side effects (D48 — the workout cover no
longer waits for the notification, the Live Activity and the disk write), four **built-in
plans** through the ordinary import pipeline with no weights in them (D46,
`Core/BuiltInPlans.swift`, `JimmsBro/Resources/*.json`), an **introduction** whose pages are
Core data pinned to real control names (D47, `Core/Introduction.swift`, `Settings.introSeen`),
and store readiness (D49: an opaque icon, version 1.4 on every target, the export-compliance
answer, `docs/PRIVACY.md`, `docs/APP_STORE.md`, `tools/check_release.py`, and a Release build
as part of every milestone's green). Everything through Y5 is built and green. What remains is
the owner's: the device checklist, the Developer Program, a release Xcode, the LICENSE and the
submission (`docs/APP_STORE.md` §1 and §6).

`docs/ITERATION_6_PLAN.md` is the v1.5 plan (milestones **Z0–Z6**), the owner's notes after
living with the app, with four readings put to the owner and chosen: a clearer Progression row
and Copy prompt with the mechanism explained once (D50, `PromptText`), an **effort target** in
the plan format — `inReserve`, reps or seconds short of failure (D51, `SetTarget.inReserve`,
four fixtures) — **a plan in several pastes** for free chatbot tiers: the outline first, then one
day per paste, through the ordinary importer (D52, `Core/PlanDraft.swift`, `draft.json`,
PROMPT.md §4–5), **progression as steps you earn** by performance with the calendar kept as a
mode (D53, `ProgressionSteps`, `Progression.mode`), and **a goal per exercise** (D54,
`Core/Goals.swift`, `goals.json`). Everything through Z6 is built and green; the v1.5 device
rows (Z4, Z10, Z17, Z25, Z31) join the checklist. The reading of "a history for each exercise"
as typed current numbers is parked by the owner's decision (the plan's last section).

`docs/ITERATION_7_PLAN.md` is the v1.6 plan (milestones **U0–U7**), built from the 2026-09-09
usability audit (`docs/UX_REVIEW_2026-09-09.md`) and judged for three users — a coach, a
great-grandparent and a five-year-old: **nothing untrue** (D55 — a missed workout only when the
plan expected one, "Nothing logged" before "First time", calendar labels unique within the plan,
a chip that never contradicts the fields, the right sentence for a plan pasted in words),
**nothing unreachable** (D56 — every menu confirmation an alert with a way out, Done in the strip
instead of over Log set, no phantom bar, a placeholder in the empty weight, large text that keeps
the inputs on screen), **the first five minutes** (D57 — no warm-up on a fresh install, **Start
first set** during a warm-up, the notification permission at the first Log set,
`InputDefaults.weightHint`, the unit asked on the review when the plan named none, a **Start
here** badge, Home that headlines the workout on a rest day, "Next: …" on the Summary) and
**hierarchy** (D59 — Start in the bottom slot, headers in ink, `WrapLayout`, Undo on the row, an
idle strip that says what follows, labelled History rows, Settings presets). U4 — **plain words**
(D58) — was written as two readings and the owner chose **Reading B**: the app speaks in words
("Aim 4–6 reps · 100 kg", "Last time 10 × 100 kg", "paired with …", "lighter set 1 of 2") and
**Settings → Compact notation** restores v1.5's forms; `Wording` is chosen once from
`Settings.compactNotation` and threaded from `WorkoutScreen.model(settings:)`, and the chatbot
prompt and the progression ladder keep the compact forms whatever the switch says. U7 — **an
activity that outlived the app** (D60) — is the one defect the owner hit on the phone rather than
in the audit: a Live Activity survives the process that started it, so `SystemActivityPresenter`
keeps no handle and asks `Activity.activities` instead, and every launch reconciles the Lock
Screen (`refreshActivity(force:)`). U0–U7 are built and green on `v1.6-refinement` (pull request
#2). The v1.6 device rows join the checklist.

`docs/ITERATION_8_PLAN.md` is the v1.7 plan (milestones **T0–T6**), written 2026-09-13 from the
owner's note after living with v1.6 — *"sensory overload… less choices… more forcing… feels like a
settings menu"*. Home becomes **Today**, one card with the same five zones every day and its
alternatives in one ··· (D61); the tab bar shrinks (D62 — the owner chose **Reading A: Today · History**
on 2026-09-13); the calendar and the week's line move to History (D63); controls
are **earned** by a table in SPEC (D64, `Core/Gates.swift`); and a **colour per day** in four
places (D65, `Core/DayColour.swift`, chosen go the same day). Nothing in it touches
`Core/Persistence.swift`, the pipeline, the format, the prompts or the Workout screen. The Today
mock is the "Jimm's Bro+ Today" artifact linked from the plan. T0–T3 are built and green on
`v1.7-today` off `main` now that pull request #2 has merged: Today is one card (`HomeStart.message`
and `.alternatives` are Core data, `TodayTests` T1–T4), and the empty card offers **Choose a
plan**. The tab bar is **Today · History** (`AppTab`, `Core/Tabs.swift`, pinned to SPEC §4.0 by
T7): Plans is pushed from Today's ··· → Change plan, and Settings from a gear at the top-left of
both tabs (`settingsGear`). The calendar and the week's line open History
(`Features/History/CalendarView.swift`); the tapped-day line is Core's (`CalendarText.line`) and
has no Start this, because a workout starts on Today. T4 is next.

Three v1.2 rules are worth knowing before touching anything:

- **`Core/Persistence.swift` is the on-disk contract.** Identity is required; anything with a
  default is optional. Adding a field to `Settings`, `Plan` or `Session` means adding it to that
  file's decoder too, or every file already on the phone becomes "corrupt" and is moved aside.
  `examples/store/v1/` freezes a real file of each type; never regenerate one to make a test pass.
- **The app has one rest with three kinds** (`RestKind`): the warm-up, the rest between sets, and
  the walk between exercises. They share the countdown, the controls and the notification.
- **Every weight the app *offers* is snapped to a loadable increment** (`WeightRounding`);
  weights the user types are never touched.

## Hard rules

- Platform: SwiftUI, iOS 17.0+, Swift 5.9+, iPhone only, portrait only. No third-party dependencies. No backend. No accounts. Two targets since v1.2: the app, and `JimmsBroActivity`, the widget extension that draws the Lock Screen / Dynamic Island activity (`tools/add_activity_target.py` is how it got into the project).
- Xcode product name: `JimmsBro` (bundle id like `com.<owner>.jimmsbro`). Create the project inside this folder.
- Persistence: Codable JSON files in Application Support (SPEC §8). Not SwiftData. Not Core Data. Not UserDefaults for anything except trivial flags.
- All logic (import pipeline, step flattening, rest resolution, session state machine, prefill, stats, export) lives in plain Swift types under a `Core/` group with no `import SwiftUI`/`UIKit`, and is covered by unit tests.
- The rest timer is Date-based (`endsAt: Date`), never a decrementing counter (SPEC §6.4).
- Never crash on bad input. Bad paste → error with a path and a code. Corrupt file on disk → moved aside, app continues (SPEC §8.3).
- Do not build anything in SPEC §10 "Later" unless the owner asks.
- Where the docs are silent, pick the simplest behavior and record it in `docs/DECISIONS_LOG.md` (create it) with one line per decision.

## Working style

- Finish each milestone with its tests green before starting the next. Run the tests; do not declare a milestone done without running them. There are three routes and they check different things: `xcodebuild test` (the app, on a simulator), `swift test` (Core on the host — where the doc-pinning tests actually run), and `python3 tools/check_core.py` (Core with no Xcode at all). From v1.4 a milestone is also a Release build (`xcodebuild build -scheme JimmsBro -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17'`) and `python3 tools/check_release.py` (SPEC §6.25). CI runs the three routes and `tools/check_bundle.py` on every push, so a milestone that edits a bundled document regenerates the bundle in the same commit (`python3 tools/build_bundle.py`); v1.6's U1–U3 were red on that job until U5 did.
- Work on a branch, commit per milestone with the tests green, and write commit messages that say *why*. Never add an AI as a co-author — no `Co-Authored-By` trailer of any kind, whatever a harness suggests; the history was rewritten once (2026-09-08) to remove them.
- The repository is public under the MIT license (`LICENSE`), with a landing page at the top of `README.md` and CI in `.github/workflows/ci.yml` running the three routes on every push. Keep the README's landing section for people and its lower half for you; keep `docs/screenshots/` to what the README shows.
- Keep views thin. Views call into an `AppModel`/store; they do not parse, validate, or compute.
- Use the fixtures in `examples/` verbatim in tests. Do not edit fixtures to make tests pass; if a fixture looks wrong, say so.
- Use the iOS Simulator for visual checks. The owner installs on the physical iPhone (BUILD_PLAN §Device).
- If you cannot run Xcode where you are (for example a chat session without a Mac), still write the complete project files, and give the owner exact commands to run the tests locally (`xcodebuild test -scheme JimmsBro -destination 'platform=iOS Simulator,name=iPhone 17'` — any installed iPhone works). Never claim tests passed that you did not run.

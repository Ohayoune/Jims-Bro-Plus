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
mode (D53, `ProgressionSteps`, `Progression.mode`), and **a goal per exercise** (D54 —
removed in v1.7's review, D68). Everything through Z6 is built and green; the v1.5 device
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
settings menu"*. Home became **Today**, one card with the same five zones every day and its
alternatives in one ··· (D61); the tab bar shrank (D62 — the owner chose **Reading A: Today · History**
on 2026-09-13); the calendar and the week's line moved to History (D63); controls
became **earned** by a table in SPEC (D64, `Core/Gates.swift`); and each day took a **colour** in
four places (D65, `Core/DayColour.swift`, chosen go the same day). Nothing in it touched
`Core/Persistence.swift`, the pipeline, the format, the prompts or the Workout screen. The Today
mock is the "Jimm's Bro+ Today" artifact linked from the plan. T0–T6 are built and green on
`v1.7-today`, off `main`, which holds v1.6 since pull request #2 merged: Today is one card (`HomeStart.message`
and `.alternatives` are Core data, `TodayTests` T1–T4), and the empty card offers **Choose a
plan**. The tab bar is **Today · History** (`AppTab`, `Core/Tabs.swift`, pinned to SPEC §4.0 by
T7): Plans is pushed from Today's ··· → Change plan, and Settings from a gear at the top-left of
both tabs (`settingsGear`). The calendar and the week's line open History
(`Features/History/CalendarView.swift`); the tapped-day line is Core's (`CalendarText.line`) and
has no Start this, because a workout starts on Today. Controls are earned (T4): `Core/Gates.swift`
has one function per row of SPEC §6.40's table, pinned by T21, and the views ask it — Month waits
for a workout older than this week, and Metrics and Find an exercise
for the first workout. Each day has a colour (T5): `Core/DayColour.swift` gives a day its colour by
its place in the plan's day list, derived and never stored, and `DaySquare.swift` draws it in
SPEC §6.41's four places — Today, the calendar, History's rows, and the workout header with the
Lock Screen — and nowhere else. T6 made the documents say so: version 1.7 on every target,
Today and History's month as the README's screenshots, SPEC's remaining Homes made Today, and the
v1.7 device rows (T5, T9, T13, T24) in the checklist that still needs the phone. Before the push the
owner reviewed T0–T6 (SPEC §6.42; T7 in TEST_CASES): History lost its search field — **Find an
exercise** is the way (D66); the **Progression** row moved from Plan detail into History's block
with Metrics and Find an exercise, for the active plan, and Today's **Plan the next one** opens it
(D67); and **goals are removed** (D68) — `goals.json` is no longer read or written, a file left on
the phone stays unread, and a backup that carries goals still restores. Its device row is T29.

`docs/ITERATION_9_PLAN.md` is the v1.8 plan (milestones **S0–S4**), written 2026-09-13 from the
owner's note after looking at v1.7's Today — *"too much text, and too little use of visual
cues… I want the visual cues to be a sort of guide for the user"*. The rule is **no words without
a cue** (D69, S1): every line of words on Today sits beside a mark that says the same thing
without words, or it leaves the card. The week becomes a seven-square strip that replaces
**Another day** (D70, S2), and a rest day says rest instead of naming the next workout (D71, S3).
Nothing in it touches `Core/Persistence.swift`, the pipeline, the format, the prompts, the
Workout screen, the rest, the Live Activity, History, or the empty card. The mock is the "Today,
Simpler" artifact linked from the plan. S0–S4 are built and green, on `v1.8-cues` off `main`: a day's
card has no sentence (`HomeStart` has no `subtitle`, TS1) — a clock and the minutes, the
exercises with their sets as blocks (`HomeStart.rows`, `PreviewRow`), the step as the ···'s last
line (`stepLine`), **▶ Start Today's Push** (`HomeStart.startTitle`, D70's words), and a lighter
gear and ··· (`QuietGlyph`); and the week is a strip (S2, D70, SPEC §6.44): seven squares at the
left of the meta row from the calendar's own projection (`Core/WeekStrip.swift`,
`CalendarProjection.next(days:from:)`), a tap shows that day (`HomeStart.current(showing:)`, the
view's `shownOffset`, never stored) with a button that says when, a tapped grey square shows
D71's rest card early, and **Another day** left the ··· with its chooser and `Gates.anotherDay`
(§6.40's table records the strip as the one ungated control). S3 is built too: a rest day says
rest (D71, SPEC §6.45) — **Rest** after a grey square, the moon where the clock was, the
system's z's in the accent where the rows were, and a disabled **No exercise Today** — which
reverses D57 on Today, because the next workout is one tap away on the strip; after the day's
workout, on every plan, the same card says **✓ Done Today** (the owner's reading), and a missed workout still
speaks. S4 made the documents say so: version **1.8** on the app, the extension and the tests,
`docs/DEVICE_CHECKLIST.md`'s **v1.8 rows** (TS5, TS11, TS12, TS16), `today.png` retaken for the
README with the strip and the set blocks, and the bundle regenerated. Everything through S4 is
built and green. What remains is the owner's: the device checklist (the v1.7 and v1.8 rows both
need the phone), the Developer Program, a release Xcode and the submission
(`docs/APP_STORE.md` §1 and §6).

`docs/ITERATION_10_PLAN.md` is the v1.9 plan (milestones **Q0–Q7**), written 2026-09-14 from the
owner's notes after living with v1.8's strip: **a day swapped, not a plan changed** (D72 — an
off-day workout writes two dates to `swaps.json`, a new file beside `plans.json`, and leaves the
plan's cycle, position and anchor alone; the day whose workout was taken carries a question on the
strip: Rest, today's day, keep, or **Slide**, which is D37's re-anchor chosen on purpose and offered
on rotations only, D73), **the marks on Today** (D74 — a dot in the pattern's colour under a
swapped square, a yellow ring for a question, a long press for "was Push", the question block with
words beneath its squares and a button that follows the choice), **a ··· of two items** with squares
for symbols and no progression in it (D75 — History's Progression row is the way), **Change a day's
exercises** from this plan, another plan (outlined in its colour) or a day written just for that
date (D76), **the JSON sheet redone** at every fragment point — named, pre-filled, the error at the
line, a Save that says its effect (D77) — and **Plans that speak in squares** (D78 — a circle to
mark and a button to confirm, the page with the cycle as squares and every day closed until
tapped). The requirements were settled in two rounds on the "Swapping Days" artifact linked from
the plan. Q0–Q7 are built and green on `v1.9-swaps` — Q1 the swap in Core, Q2 its marks on
Today, Q3 the ··· in squares with progression left to History, Q4 a day's exercises changed for one
date — a day of this plan, a day borrowed from another plan (outlined in its colour) or a day
written just for the date (outlined in ink), `Core/ChangeDay.swift` and `ChangeDayView` — Q5
the JSON sheet redone at its five points: named, pre-filled with an example that saves as it
stands, the error marked at its line or nowhere (`Core/JSONPoint.swift`, `Core/JSONLocator.swift`),
and a Save that says its effect — and Q6 Plans in squares: on the list a chevron at the left, the
cycle's symbol, how often, and a circle that marks while **Use *name*** confirms (now the one way
to change plan), and on the plan's page the cycle as squares, then as rows each closed until
tapped (`Core/PlanPage.swift`). v1.9 touches the on-disk contract once: `swaps.json` beside
`plans.json` (absent means no swaps) and an optional `swaps` in a backup, frozen in
`examples/store/v1/` with a backup that carries swaps and one that does not. Q7 made the documents
say so: version **1.9** on the app, the extension and the tests, `docs/DEVICE_CHECKLIST.md`'s
**v1.9 rows** (TQ18–TQ20, TQ24, TQ29, TQ33, TQ38, TQ39), D72–D78 in `docs/DECISIONS_LOG.md` with
the D37 amendment and the D50 reversal on Today named, and the bundle regenerated; no screenshot
changed. Everything through Q7 is built and green. What remains is the owner's: the device
checklist (the v1.7, v1.8 and v1.9 rows all need the phone), the Developer Program, a release Xcode
and the submission (`docs/APP_STORE.md` §1 and §6).

`docs/ITERATION_11_PLAN.md` is the v1.10 plan (milestones **P0–P7**), written 2026-09-16 from the
owner's notes after living with v1.9: the Workout screen in **symbols**, and colour that means
**state** — done in the day's colour, now in blue (reserved on that screen for the current set),
not yet in grey (D79); the header without words, its bar one segment per exercise with a tick per
set, tapped to open the Overview (D80); the exercise as a name with a **?** for its notes, a row of
**dots** for its sets, and one **card of cells** for the set you are on — solid to the minimum,
translucent to the top of the range, a caret under the reps, a line where last time reached — with
a logged set changed in place by **Save** (D81); the walk between exercises as a **count-up and a
ring** that fills red → amber → green over the plan's minimum, `restBetweenExercises`, the one
field this release adds to the plan format and the on-disk contract, optional, the setting as the
fallback (D82); **pages** — swipe to the next or previous exercise while the bar's fill stays put
and its caret moves (D83); a bar whose segments take **your median time** per exercise once it has
been done three times, held between ½× and 2× (D84); **Change *day*** as joined squares with a
button that confirms and names its effect, and today's exercises editable through the JSON sheet
pre-filled with the day (D85); and cycles drawn **seven to a row, the squares touching** (D86).
The requirements were settled on two artifacts linked from the plan: round 1, "Workout in Symbols",
and round 2, "Symbols, Round Two", redrawn four times on the owner's corrections. P0 is written;
nothing else is built.

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

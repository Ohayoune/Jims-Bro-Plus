# Jimm's Bro+ — complete handoff bundle

This single file contains the entire design package for a native iOS workout app, so it can be uploaded or pasted into a chat with a coding assistant. The folder version of this package (with 111 fixture files under `examples/`) is the same content; the fixtures are not inlined here because `tools/generate_fixtures.py` (included below) recreates all of them.

The app itself is built: v1 (M0–M7), v1.1 (R0–R6), v1.2 (V0–V7) and v1.3 (X0–X5) are implemented and green. `docs/BUILD_STATUS.md` says what was actually run, and `docs/DECISIONS_LOG.md` records every decision taken where the docs were silent. The Swift sources are not in this bundle — they are in the folder, under `JimmsBro/`, `JimmsBroActivity/` and `JimmsBroTests/`.

How to use this bundle:
1. Read `AGENTS.md` first (immediately below). It says what to read next and the hard rules.
2. Recreate the folder: save each `### FILE:` section below to its path, then run `python3 tools/generate_fixtures.py` and `python3 tools/reference_import.py` (expect "111/111 fixtures match the manifest").
3. Read `docs/BUILD_STATUS.md` to see where the build has got to, then `docs/ITERATION_2_PLAN.md`, `docs/ITERATION_3_PLAN.md` and `docs/ITERATION_4_PLAN.md` for what v1.1, v1.2 and v1.3 were.

Each file below starts with a line `### FILE: <path>` followed by its full content inside a five-backtick fence, so the three- and four-backtick fences inside the documents nest correctly.

---

### FILE: AGENTS.md

`````markdown
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

- Finish each milestone with its tests green before starting the next. Run the tests; do not declare a milestone done without running them. There are three routes and they check different things: `xcodebuild test` (the app, on a simulator), `swift test` (Core on the host — where the two doc-pinning tests actually run), and `python3 tools/check_core.py` (Core with no Xcode at all).
- Work on a branch, commit per milestone with the tests green, and write commit messages that say *why*. Never add an AI as a co-author.
- Keep views thin. Views call into an `AppModel`/store; they do not parse, validate, or compute.
- Use the fixtures in `examples/` verbatim in tests. Do not edit fixtures to make tests pass; if a fixture looks wrong, say so.
- Use the iOS Simulator for visual checks. The owner installs on the physical iPhone (BUILD_PLAN §Device).
- If you cannot run Xcode where you are (for example a chat session without a Mac), still write the complete project files, and give the owner exact commands to run the tests locally (`xcodebuild test -scheme JimmsBro -destination 'platform=iOS Simulator,name=iPhone 16'`). Never claim tests passed that you did not run.
`````

---

### FILE: README.md

`````markdown
# Jimm's Bro+

A personal iPhone app that runs your workout for you: import a plan a chatbot wrote from your own description, then log each set while the app times your rest and remembers what you lifted last time.

This folder contains the design package and the app, built through **v1 (M0–M7)**, **v1.1 (R0–R6)**, **v1.2 (V0–V7)** and **v1.3 (X0–X5)**: the Core import pipeline and session engine, the JSON store, every screen, the workout's five fixed zones, plan editing, backup and restore, v1.2's warm-up, timed walk between exercises, loadable weight suggestions, anchored calendar, metrics and Lock Screen / Dynamic Island activity, and v1.3's narrower Island, changing an exercise mid-workout, JSON edits at every size, history as CSV in and out, and Progression — the chatbot round-trip run the other way. Open `JimmsBro.xcodeproj` and select the shared `JimmsBro` scheme. What remains is the device checklist, which needs the owner's iPhone. ChatGPT / Codex reads `AGENTS.md`; Claude Code reads the identical `CLAUDE.md`.

Run the iOS tests from this folder:

```sh
xcodebuild test -scheme JimmsBro -destination 'platform=iOS Simulator,name=iPhone 16'
```

That is **246 tests** (3 of them skipped on this route — see below). The suite covers imports, steps, rest, the session engine, prefill, stats, progression, plan coordination, scheduling, calendar projection, prompts, the persistence store and its migration from v1.1's files, the app model behind the screens, the workout's input rules, timers, notifications and session lifecycle, history and metrics, plan editing, backup and restore, v1.2's warm-up, transition rest, weight rounding, suggestions, anchored schedule and Live Activity, and v1.3's Island timer range, exercise substitution, JSON splices, history CSV and Progression. Imports use the original 111 fixtures and manifest verbatim. There are no third-party dependencies, and the signing team is already set for both targets.

Core can also be checked with the independently installed Command Line Tools:

```sh
python3 tools/check_core.py --filter ImportTests
python3 tools/check_core.py
```

This portable runner compiles the actual Core sources in Swift 5 language mode and executes the same test bodies using assertion adapters. It reports a nonzero exit code on any failure; it does not run XCTest or certify app bundle/simulator behavior.

```sh
swift test
```

runs Core as an ordinary Swift Package. This route had not compiled since `AppModel` became `@Observable` — `Package.swift` declared macOS 13 and Observation needs 14 — and v1.2's V1 fixed it. It is also where the three cases the simulator skips actually run: they pin `Prompts.swift` to `docs/PROMPT.md`, which is outside the simulator's sandbox. See `docs/BUILD_STATUS.md` for results and remaining verification.

An iOS simulator runtime must be installed in Xcode; the commands above name the iPhone 16 simulator, and any installed iPhone works.

```sh
python3 tools/check_bundle.py
```

fails when `HANDOFF_BUNDLE.md` or the zip has drifted from the files it is built from. Both are derived but committed, because the owner hands them to a chatbot that cannot read a folder — which is only safe with a check that says when they have gone stale.

| File | What it is | Who reads it |
|---|---|---|
| `AGENTS.md` / `CLAUDE.md` | Handoff instructions and hard rules (identical; one per agent convention) | the agent |
| `docs/SPEC.md` | Product spec: decisions, platform, screens, exact behaviors, data model, persistence | you first, then the agent |
| `docs/PLAN_FORMAT.md` | The JSON plan format, what's accepted leniently, every error/warning code | the agent |
| `docs/PROMPT.md` | The exact prompt the app copies for ChatGPT/Claude, and the fix-it prompt | you, the agent |
| `docs/TEST_CASES.md` | About 475 test cases, unit / ui / manual | the agent; you for the manual checklist |
| `docs/BUILD_PLAN.md` | Milestones M0–M8 and how to install on your iPhone | both |
| `docs/ITERATION_2_PLAN.md` | The v1.1 plan: milestones R0–R6 | both |
| `docs/ITERATION_3_PLAN.md` | The v1.2 plan: milestones V0–V8 | both |
| `docs/ITERATION_4_PLAN.md` | The v1.3 plan: milestones X0–X6 | both |
| `docs/PROGRESSION_FORMAT.md` | The progression reply format (D44): fields, leniency, codes | both |
| `docs/CODE_HEALTH_REVIEW.md` | The 2026-09-07 review that prompted half of v1.2, and what became of each finding | you |
| `docs/DEVICE_CHECKLIST.md` | The 32 manual cases to run on your iPhone, with a place to record results | you |
| `docs/BUILD_STATUS.md` | What is built, what was verified and how to reproduce it | you |
| `schema/plan.schema.json` | JSON Schema of the strict plan shape | the agent |
| `examples/` | 111 fixture files + `manifest.json` with expected results | the agent's tests |
| `tools/reference_import.py` | Python reference implementation; `python3 tools/reference_import.py` checks every fixture | the agent, as an oracle |
| `tools/generate_fixtures.py` | Regenerates all of `examples/` from scratch | the agent, if it only has the bundle |
| `HANDOFF_BUNDLE.md` | Everything above except the fixtures, in one file for pasting or uploading into a chat | ChatGPT (web) |
| `JimmsBro-design-package.zip` | The whole folder, for uploading into a chat | ChatGPT (web) |

Before handing off, read `docs/SPEC.md` §1 (decisions made for you) and §2 (why a native iOS app, and what the free vs $99 Apple routes mean). Change anything you disagree with in the docs first; the agent builds what the docs say.
`````

---

### FILE: docs/SPEC.md

`````markdown
# Jimm's Bro+ — Product Spec (v1)

## 0. One paragraph

A personal iPhone app that runs your workout for you. You import a plan (one workout or a whole week) as JSON that a chatbot wrote from your own description. The app then walks you through the day's exercises in order, set by set: it shows the target, you enter what you actually did, it logs the set and starts a rest timer that alerts you even when the phone is locked. It remembers everything: your plans, every set you've ever logged, the weight you used last time, and where you are in your weekly rotation. Local only, no account, no server.

## 1. Decisions already made (change these if wrong)

The original description left a few things open. These are the choices this spec is built on. Change the doc before building if any are wrong.

| # | Decision | Why |
|---|----------|-----|
| D1 | The unit of logging is the **set**, not the exercise. Rest runs after every set. | "Bench press 3×10" is three separate efforts with rest between them. An exercise with one set behaves exactly like "log after each exercise". |
| D2 | Each set logs **reps and weight** (weight optional). | Reps alone can't show progression. Weight is prefilled from last time so it costs zero taps when unchanged. |
| D3 | **Supersets/circuits are supported** in v1 via a `group` tag. | Chatbot-written plans contain them constantly. Refusing them would break most imports. |
| D4 | **Timed sets** (plank 45s, bike 10 min) are supported via `durationSeconds`. The work countdown reuses the rest timer. | Same reason as D3. |
| D5 | Plans are **JSON**, produced by a chatbot from a prompt the app gives you. | Chatbots produce JSON reliably; Swift decodes it natively. A friendlier text format is listed under Later. |
| D6 | A plan is always a list of **days**. A "daily" plan is a plan with one day. Weekly plans are either a **rotation** (do days in order, repeat) or **weekday-anchored** (Mon/Wed/Fri). | Covers both kinds of real plans without two code paths. |
| D7 | Sessions store a **snapshot** of the day as performed, not a reference to the plan. | Plans get re-imported, edited, and deleted. History must survive that. |
| D8 | Exercise identity across history is the **normalized name** (trim, case-insensitive, collapse whitespace). | No exercise database to maintain. The prompt tells the chatbot to keep names consistent. |
| D9 | Native **SwiftUI iOS app**, files on disk, no cloud. | See §2. |
| D10 | Logged weights keep the **unit of the plan** they were logged under. No unit conversion anywhere. | Conversion is where rounding bugs live. Display always shows the unit. |
| D11 | Reps and weight are **prefilled with what you achieved last time** for that set, so a normal set is one tap and a better set is "+" then tap. Targets are used only when there is no history. **Revised in v1.1**: carry-forward across sets within the same session applies only to a **straight** exercise, where every main-set target weight is equal (or all absent). A **varied** exercise (targets differ across sets, e.g. a 50→60→70 kg pyramid) always prefills each set from last session's same set index, else that set's own target — never from a weight logged earlier in the same session. Reps for a step are computed once when its card appears and are never rewritten by a later weight edit; the user's own edits are never touched either way. | Owner request. Prefilling the target instead would hide progress and cost taps. Revision: a deliberately varied plan was fighting the user (v1.1 UX review, 2026-09-05); predictable beats clever. |
| D12 | Every exercise carries a **rep range** (`repRange`, e.g. 8–12). Hit the top of the range on every set → the app suggests adding one weight step next time. Fall below the bottom of the range → it suggests holding or dropping a step. Never applied automatically; the suggestion is a chip you can tap. | Standard double progression. Note the owner first asked for "below the range → increase", which is inverted; below the range means the weight is too heavy. |
| D14 | Between **sets** of the same exercise: countdown rest timer with alert. Between **exercises**: a count-up stopwatch on a "done" screen with one **Continue** button, no alert. **Revised in v1.1**: the full-screen "done" screen and its Continue gate are removed. When a block ends, the next step's card appears immediately (phase → `working`, no `.transition` phase); the finished block's name, duration and any advice appear as a status line on the new step's card, alongside a small count-up "moving on" time, until the next set is logged. No alert, no countdown — the owner still decides when to move on; only the mandatory tap is gone. | Owner request. You decide when you've walked to the next station; the app just shows how long it took. Revision: the mandatory Continue tap between every pair of exercises added no value and made the finished set's duration the largest thing on screen (v1.1 UX review, 2026-09-05). |
| D15 | **Drop sets** are supported: a set can carry `drops`, each logged as its own sub-step with no rest before it. | Owner request. |
| D16 | Every plan has a **cycle**: the ordered block of day names and rest days that repeats (`cycle`). Rotation plans default to the days in order; weekday plans derive a 7-day cycle. The cycle drives "Next up" and the calendar's projected workouts. | Owner asked for "a block where the plan repeats". This is the interpretation; it also gives the calendar a schedule to project. |
| D17 | Starting a different day while a workout is in progress is **allowed but discouraged**: a popup defaults to "Keep going". | Owner request. |
| D18 | Home is **quiet**: one Start card, a compact month calendar, one tiny sparkline. Everything else lives in the Plans, History and Settings tabs. A screen has one primary action; secondary actions go in a "···" menu. **Revised in v1.1**: quiet, but leading with the workout. The start card names the day, the plan and the day's exercises, and its button says what it will do ("Start Push", "Resume Push · 23 min", "Start Lower early"); the month grid becomes a 7-day strip that discloses to the month; and the tap-to-cycle sparkline is replaced by one activity line. | Owner asked twice for less clutter. §4.0 has the rules. Revision: v1.1 UX review, 2026-09-05 — Start was blind (nothing on Home said what was behind it) and the sparkline's hidden tap was undiscoverable rather than quiet. |
| D19 | **Every set is timed.** A rep set's duration runs from the moment its card appears (rest ended, the block-done strip appeared, or the previous log when rest is 0) to Log set. Timed sets run from the Start tap. Stored per step and shown after the fact, not on the card. **Revised in v1.1**: storage is unchanged, but the number is demoted everywhere it is shown. A set's duration appears only as small text — in the Overview rows, Session detail, the status strip's "set 0:34", and behind Details on the Summary — and is never the largest thing on a screen. Removing the Continue gate (D14) makes a rep set's recorded duration include walking and fiddling, so it must never outrank a deliberately timed plank. | Owner request. No extra tap per set. Revision: v1.1 UX review, 2026-09-05. |
| D20 | Three kinds of work: **reps**, **fixed duration** (countdown with a short **warning beep at 10 % remaining** and a **final beep** at the end), and **open duration** (`"durationSeconds": "max"`, a stopwatch you stop yourself, logging the seconds held). The warning beep is optional per exercise or set via `warningBeep`: `true` (10 %, the default), `false`, or a number of seconds before the end. | Owner asked for timed sets that show how long they take, and a warning beep before the final beep. |
| D21 | `"bodyweight": true` on an exercise means no weight applies: the weight row is hidden, the JSON never needs a weight, and advice says "add load" instead of a number. A missing weight without the flag still shows an empty weight field. | Owner asked the JSON to accommodate sets with no weight. Distinguishes "no weight applies" from "the plan didn't say". |
| D13 | History is stored **per set with a timestamp, reps, weight and unit**, so a time-vs-weight-and-reps chart per exercise is a pure read of existing data. v1 ships the Core query (`ExerciseHistory.series`) without the chart UI. | Owner wants the chart later; storage must not need a migration to add it. |
| D22 (v1.1) | The workout is **one screen with five fixed zones** — header, exercise block, inputs, status strip, primary action — top to bottom, in that order, in every state. Working, resting, a running timed set and a block having just finished change what the zones *contain*; none of them ever appears, disappears, or changes position. In particular the primary button is always the same full-width control in the same place, and the header's Exercises, minimize and "···" controls are reachable in every state, rest included. | v1.1 UX review, 2026-09-05: the workout was three different full-screen layouts in sequence (card → rest → done screen). Controls moved under the thumb between them, and rest and the done screen carried no "···" at all, so the overview, skip, finish and any correction were unreachable exactly while the user had time to make one. |
| D23 (v1.1) | **Undo** is available for the most recently logged or skipped step, until another step is logged or skipped after it: it restores the step to pending, clears its result, cancels any rest notification that started because of it, recomputes the exercise's progression advice, and re-enters that step as the current one. Not available once the session is completed (history editing, §4.10, covers that case instead). | v1.1 UX review: correcting the immediately previous set required Skip rest → ··· → Overview → edit → Save; a typo should be one tap to fix while rest keeps running. |
| D24 (v1.1) | A **failed write is never reported as a success.** `AppModel` surfaces a `saveFailure` describing what failed; the data that couldn't be written is kept (the active session file, or the in-memory session pending its file) rather than discarded, and the app offers **Retry**. A session is only added to the "already persisted" set after its file write succeeds; `active-session.json` is only cleared once every completed session from it is confirmed on disk. On launch, an active-session file whose phase is already `completed` (a write that succeeded partially last time) is turned into a normal session file and cleared. | v1.1 UX review found `persistCompletedSessions` marking a session persisted before confirming its write succeeded, and every store write silently swallowed with `try?`. |
| D25 (v1.1) | **Every delete of a plan or a session confirms**, with one concise dialog ("Delete Push Pull Legs?" / "Delete this workout?"). This applies to swipe-to-delete in the Plans and History lists and to Plan detail's "···" menu, matching the confirmation session detail already had. Delete all data keeps its existing, more serious confirmation. | v1.1 UX review found three of four delete paths deleting immediately with no confirmation and no undo, while session detail alone confirmed. |
| D26 (v1.1) | Plans arrive through **Add plan**, not through a JSON text box: Paste plan, Create with a chatbot (three numbered steps), Import file, with the editor behind "Show text". The review step shows the exercises and their per-set targets, states errors in plain sentences before any path or code, separates warnings that changed the workout from tidying that did not, and offers "Set as current plan". Onboarding offers a short practice workout beside the full sample. | v1.1 UX review, 2026-09-05: the import screen read as a data-file editor for an app whose premise is a chatbot round-trip it never described, and its preview could not show whether the chatbot had produced the right exercises. |
| D27 (v1.1) | A **skipped set can be recovered**, in both the live overview and history: the edit sheet becomes valid for a skipped step, not only a logged one. Saving sets its result, marks it logged, and sets `loggedAt` to the time of the save (replacing the earlier skip time, since the set is being addressed now). In the live workout only, a skipped step's row also offers **jump to it** as a way to do it properly instead of backfilling a result. | v1.1 UX review found the edit sheet already offered for skipped sets, but `SessionEngine.editSet` silently did nothing unless the step was already logged — an apparently successful Save that changed nothing. |

| D28 (v1.1) | **Do later** moves an exercise's remaining sets — its whole block, so a superset moves together — to after the day's last pending step, and carries on with whatever is next. It is offered only when it would move something. The step order changes; `blockIndex` does not, so the block keeps its identity for rest resolution, durations and the block-done strip, and views order blocks by where their steps now sit. | The machine is taken. Skipping an exercise says you are not doing it; this says you are doing it later, which is what actually happens in a gym. |
| D29 (v1.1) | A plan can be **edited in the app**: an exercise's name, set count, reps, rep range, weight and rest; reordering and deleting exercises; renaming and duplicating a day. Every edit is rendered back to plan JSON and re-imported, so it is validated and normalized by exactly the code an import is, and `sourceText` always matches the plan. The plan keeps its id, its import date and its cycle position. | A one-word change should not mean a round trip to a chatbot. Routing edits through the importer means an edit can never produce a plan the app would have refused to import. |
| D30 (v1.1) | A logged set that beats every earlier logged set of that exercise — heaviest first, ties broken by reps; reps alone when there is no weight; seconds held for timed work; same units only (D10) — is a **personal record**, marked on the Summary and in session detail. The first session of an exercise sets none, since there is nothing to beat. History gains a search box that finds an exercise by name, and the exercise screen gains the top-weight chart of D13. | The data was already stored (§8.4); D13 always intended the chart. A PR is the one number worth interrupting for. |
| D31 (v1.1) | A backup can be **restored**: Settings reads the file, says what is in it and what each choice would do, then offers **Merge** (adds only ids not already present; leaves current settings, the active plan, and anything edited since the backup alone) or **Replace all** (empties the store and takes the backup's plans, workouts, active plan and settings). A file that isn't a backup, or is from a newer app, is refused before anything is written. | SPEC §8.5 always said the export format is the on-disk format so this would be trivial. Export without restore is only half a backup. |

## 2. Platform

**Build a native iOS app in SwiftUI.** You have the two things it needs: a Mac (Xcode is free) and an iPhone.

Why native and not a web app: the core feature is a rest timer that goes off while your phone is locked in your pocket. iOS Safari suspends a web page when the screen locks, and a web page cannot schedule "notify me in 90 seconds" without a push server. A web app's timer would only work with the screen on. iOS can also evict a website's stored data. Native gets local notifications, haptics, reliable storage, and keeps-screen-awake for free.

Why not React Native / Flutter: you don't need Android, it still needs Xcode to install, and it adds a toolchain for an AI-built app to get tangled in.

What it costs:

| Route | Install lifetime | Price | Notes |
|-------|------------------|-------|-------|
| Free Apple ID in Xcode | 7 days, then re-run from Xcode (data survives) | $0 | Max 3 sideloaded apps at once. Fine for personal use. |
| Apple Developer Program | 1 year, plus TestFlight | $99/yr | Only needed if the 7-day re-install annoys you or you want friends on it. |

What you do vs. what the implementing agent does: the agent writes all code and tests and can run the app in the iOS Simulator. Installing on your physical iPhone is a one-time 5-minute manual step (plug in, trust, enable Developer Mode, choose your Team in Xcode). Steps are in `docs/BUILD_PLAN.md`.

Targets: iOS 17.0+, iPhone only, portrait only, English only, light and dark mode, Dynamic Type.

## 3. Vocabulary

Use these words in code and UI. Don't invent synonyms.

- **Plan** — an imported document. Has a name, units (kg/lb), a schedule type, and one or more Days.
- **Day** — one workout: a named, ordered list of Exercises. ("Push", "Day 2", "Wednesday").
- **Exercise** — one movement with an ordered list of Set Targets, optional notes, optional group tag.
- **Set Target** — what you're supposed to do for one set: a rep target, a fixed duration, or an open duration; an optional weight (never, for bodyweight exercises); a resolved warning-beep offset for fixed durations; and a resolved rest time.
- **Group** — exercises with the same `group` tag, listed consecutively, are done as a superset/circuit: one set of each in turn, then rest, then the next round.
- **Drop** — a sub-set done immediately after a set with lower weight and no rest. A set with 2 drops is logged as 3 steps.
- **Step** — one set (or one drop) of one exercise, in execution order. A Day flattens into a list of Steps (§6.2).
- **Block** — one exercise, or one superset group, as an execution unit. Between blocks the app shows the "done" screen (D14).
- **Cycle** — the ordered list of Days and rest days a Plan repeats (D16). "Cycle position" is where you are in it.
- **Session** — one run-through of a Day on a date. Contains a snapshot of the exercises plus a result per step.
- **Set Result** — what you actually did: reps (or seconds) and weight, or skipped.
- **Cycle position** — per plan, the index in the cycle of the last completed entry. Drives "Next up" and the calendar projection.

## 4. Screens

### 4.0 Quiet UI rules (apply everywhere)
Rewritten in v1.1's R2 milestone. The v1 text is kept underneath each rule that changed, so the change is deliberate rather than drift.

- **One primary action per screen**, full width, accent colour, bottom-anchored above the keyboard. Secondary actions that the primary task itself needs while it is running may be visible buttons — Exercises, Undo, rest −30 / +30, Skip rest — and everything else goes behind "···" or a swipe. *(v1: "Never more than two visible buttons besides the primary." That rule put Overview, undo and Skip behind a menu that did not exist during rest, which made them unreachable exactly when they were needed — P2.)*
- **Label what the value does not explain.** A bare `10` and `80` get small-caps **REPS** and **KG** labels; a volume figure is labelled Volume. A unit suffix is not a label. Do not label what is already self-evident (no "Notes:" before notes). *(v1: "No labels for things the value already says." Two unlabelled stepper rows were the most-reported confusion in both reviews — P5.)*
- No decorative dividers, cards inside cards, or badges. Group with whitespace, or with one grouped/inset list style used consistently on every screen (R4).
- **Large numbers are for values you act on right now**: the input values, a running countdown, a running timer. A number you are only being told about — a set's duration, a block's duration, a volume total — is body text. *(v1: "The most important number on a screen is the largest thing on it", which made the between-exercise block duration the hero of its own screen — D19, P1.)*
- Show a line only when it has content (no "Notes: none", no empty "Last time").
- Tab bar with four tabs: **Home · Plans · History · Settings**. No other navigation chrome on Home.
- **Zones do not move.** Within one task, a control keeps its position across every state of that task: nothing appears, disappears or shifts under the thumb between working, resting and timed work (§4.5, D22, P1).

### 4.1 Home (D18, rewritten in v1.1's R3)
Three things, top to bottom, nothing else:
1. **Start card**, which leads with the workout rather than with the calendar: the day's name as the headline ("Push"), a subtitle of the fragments that have data ("Push Pull Legs · 5 exercises · 48 min last time"), the day's first five exercise names and "and N more", then one button that says what it does — **Start Push**, **Resume Push · 23 min**, or, on a rest day, a "Rest day" headline with "Lower is next, Thu" and **Start Lower early**. **Preview** opens the day in Plan detail; **Another day** offers the plan's other days. **v1.3 (D44)**: when the plan carries a progression, the subtitle also says where it is — "· week 3 of 8"; the day after its last week, one line says "Your progression has run its course" with **Plan the next one**, which opens the plan. Nothing else on Home moves. No plans yet → "No plan yet" with **Add plan**, plus "Try the sample plan" and "Try a short practice workout". *(v1: "Next up · Pull" and a bare Start, which never said what you were about to do.)*
2. **Calendar**: a **7-day strip of the current week** by default, with **Month** disclosing the full grid (7 columns, weeks as rows, ‹ › to change month, today outlined) and **Week** collapsing it again. Cells are at least 44 pt in both (P6). A day with a completed session shows a filled accent dot; a future day with a projected workout (§6.12) shows a hollow accent dot; a scheduled rest day shows a filled grey dot; a day the plan says nothing about shows no dot at all. Tapping a day shows one line under the grid: "Wed 10 · Legs · 52 min" (tap again → session detail), "Sat 13 · Push · projected" with a small **Start this** if it's today, or "Sun 14 · Rest day". Days with no dot show no line.
3. **One activity line**: "2 workouts this week · 1 h 32 min", or "No workouts yet this week". "This week" is the calendar week containing today, the same seven days the strip above shows. *(v1 had a 44 pt sparkline whose metric changed on an undocumented tap. Both v1.1 reviews called it undiscoverable rather than quiet; `Sparkline`, `HomeMetric` and the Settings row that picked the metric were removed with it. `ExerciseHistory.series` — the per-exercise data behind the chart of D13/§10 — is untouched.)*

### 4.2 Plans
List of plans (active one marked). Tap → Plan detail. Primary action: **Add plan** (§4.4). Swipe to delete, with a confirmation dialog (D25 v1.1) — swiping no longer deletes immediately.

### 4.3 Plan detail
- Name, units, schedule, and the **repeat block**: the cycle as a row of chips, `Push · Pull · Legs · Push · Pull · Legs · Rest`, with "repeats every 7 days" beneath and the current position highlighted. Weekday plans show Mon…Sun with the day name or "rest" under each.
- **Progression** (D44, v1.3, §6.21): one row under the repeat block — "Plan it", "Week 3 of 8" or "Finished" — opening the Progression screen: the period (4 / 6 / 8 / 12 weeks), **Use my history** when there is any, the three chatbot steps, **Paste progression**, a review of every exercise's weeks with the material warnings in yellow, **Save progression**. With one saved, the same screen reads it back, week by week with this week's targets first, and offers **Plan the next one** and Remove.
- Days: each expands to its exercises (sets, target, rest, drops, rep range).
- **Editing** (D29, v1.1): tapping an exercise opens a sheet for its name, set count, reps, rep range, weight and rest. Edit mode reorders and deletes exercises within a day; the day header's menu renames the day and duplicates it. Every change goes back through the import pipeline, and one it would refuse says why rather than appearing to work.
- **JSON edits** (D43, v1.3, §6.19): the exercise sheet's **Edit as JSON** opens the exercise's own JSON — for what the fields cannot say: one set unlike the others, drop sets, a warning beep. The day's menu has **Add exercise** (a template to fill in, or a pasted list) and **Edit day as JSON**. One sheet does all of them: monospace text, a Paste button, the friendly error sentence with the real path behind Details, Save. Every Save is a `PlanEdit.Operation` through the import pipeline.
- "···": Set as active, Rename, Copy JSON, **Edit JSON**, **Add day from JSON**, Delete. Edit JSON (v1.3, D43; v1.1 called it Replace) opens Import targeting this plan's id with the plan's text already open: saving it keeps the id, the cycle position and its anchor (D37) and, if this plan was active, keeps it active. Add day from JSON appends a pasted day — or every day of a pasted plan, which is how a week the chatbot cut short gets finished — and puts it into a rotation's repeat block. Delete confirms (D25 v1.1).
- Any day has **Start** (override). If a session is in progress this triggers the switch popup (D17): "You're in the middle of Pull (5 of 16 sets). Switching workouts mid-session isn't recommended." Buttons: **Keep going** (default), Finish Pull and start Legs, Discard Pull and start Legs.

### 4.4 Add plan (D26, rewritten in v1.1's R3)
The chatbot round-trip is this app's premise, and the v1 screen — a JSON text box — never explained it. **Add plan** offers three ways in, and the editor is a detail behind "Show text":

- **Paste plan**, the one you use when the chatbot's reply is already on the clipboard. It imports immediately; the button does nothing when the clipboard holds no text (O3).
- **Create with a chatbot**, three numbered steps: 1 **Copy prompt** (the button reads "Copied" and goes back on its own after about two seconds), 2 paste it into your chatbot and describe your training, 3 copy its reply and come back. The draft in the editor survives leaving the app.
- **Import file**, for a `.json` on disk.

**Errors** lead with a plain sentence naming where the problem is — "Day 1, exercise 2, set 2 needs either a rep target or a duration." — with the path, the code and the importer's own message behind **Details (n)**, and **Copy fix-it prompt** unchanged. `IssueText.friendly` has a sentence for every `E_` code in PLAN_FORMAT §4 and falls back to the importer's message for one it doesn't know.

**Review plan** replaces the v1 preview: name, units, schedule and cycle chips; the days as rows that expand to their exercises with **per-set** targets ("3 × 8–12 · 24 / 26 / 28 kg"), the first day already open; **material** warnings shown in yellow (a dropped unit, a removed load, a changed grouping, an inferred schedule) with **cleanup** warnings folded behind "Details (n)" (curly quotes, unknown fields, rounded weights — tidying that did not change the workout); a **"Set as current plan"** toggle, default on; then **Save plan**. Same-name conflict → Replace / Keep both / Cancel. The toggle's value is passed through as `makeActive`; the very first plan ever saved always becomes active regardless of it, since there is nothing to compare it to.

### 4.5 Workout screen (v1.1, D22)
One screen, five fixed zones, top to bottom, identical across every state below. Only the zones' contents change; none of them appears, disappears, or moves position between working, resting, a timed set, or a block having just finished.

> **Build status**: built in R2. `WorkoutScreen.model(active:history:now:)` resolves the whole screen — zones, set rows, prefilled inputs, strip and primary action — as a `WorkoutScreenModel`, and the view only renders it, which is what makes "the zones never move" a unit test (O50) rather than a convention.

1. **Header** (v1.2, D34): the **stage** the workout is in, said in words, above a progress bar of the whole day — **Warm-up**, **Exercise 2 of 5 · Set 2 of 3**, **Resting**, **Between exercises**. Then elapsed time · progress ("Exercise 2 of 5 · Set 2 of 3", or "· drop 1 of 2", or "A · round 2 of 3" for a superset member) · **Exercises** (opens the Overview sheet, §4.8, reachable in every state including rest) · minimize (returns to the tabs; the session and its timers keep running; Home shows "<Day> in progress · <elapsed>" with **Resume**) · "···" (Skip set, Skip exercise, Do later, **Change exercise** — v1.3, D42 — Finish workout — Rename exercise moved to Session detail, a history-editing task, not a mid-workout one).
2. **Exercise block**: the exercise's name (opens its history) and target line (with notes, truncated to one line), then the current exercise's set rows: finished rows show what was logged ("✓ 10 @ 80") and never how long it took (D19), the current row is highlighted with its target and last-time value, upcoming rows show their targets. A row carries the set's own target only — the exercise's notes appear once, on the target line above, rather than repeating on every row. In a block holding more than one exercise (a superset round) each row names its exercise instead of repeating the shared group tag, which would otherwise make two rows read identically. A superset shows the current round's members. Tapping a finished row opens the edit sheet; tapping an upcoming row jumps to it (§6.6 `jumpTo`).
3. **Inputs**: small-caps labels **REPS** and the unit (**KG**/**LB**) above the − value + rows; the weight row is omitted for bodyweight exercises (D21); a "72.5 suggested" chip appears under the weight when §6.11 produced one. Timed sets replace the reps row with the timer block described below; the weight row stays unless bodyweight.
4. **Status strip** (always present; its content depends on phase, per §4.6/§4.7 below).
5. **Primary action**, bottom-anchored above the keyboard, full width: **Log set** while working or resting (logging during rest ends the rest early); **Start timer** / **Done** / **Stop** for a timed set, per D20. When the step waiting on the far side of a rest is a timed one, **Start timer** ends that rest and starts the work in the same tap, exactly as logging out of a rest does — the one button in the one slot is never inert.

After logging, a step's seconds (D19) remain editable in the Overview like any other value.

### 4.6 Rest, within the status strip (v1.2: one rest, three kinds)
There is one rest in the app, and it says which of three kinds it is, because "a break" that does not say what it is for is the thing the owner said was unclear:

| Kind | When | Length |
|---|---|---|
| **Warm-up** (D32) | Before the first set of the session | `Settings.warmUpSeconds`, 0 = off |
| **Rest** | Between sets of an exercise, and after a superset round | The set's resolved `restSeconds` (§6.3) |
| **Between exercises** (D33) | After a block's last step, before the next exercise | `Settings.transitionRestSeconds`, 0 = straight through, as v1.1 |

The strip shows: the kind, named; the countdown m:ss; −30 s / +30 s; **Skip** (whose label names the kind — "Skip rest", "Skip warm-up"); and "Set logged · **Undo**" (D23) for as long as the rest runs. Alert at zero (§6.4); at zero the strip reads "Rest over · +0:12" (or "Warm-up over") until the next log. "set 0:34" (how long the set just logged took, D19) appears in the strip in small text, never as the largest element on the screen.

None of the three gates anything. The next set's card is already on screen and the primary button works throughout — logging (or starting a timed set) during any of them ends it early, exactly as v1.1's rest did.

### 4.7 Between exercises: the status strip's block-done state (D14, revised in v1.1; timed in v1.2's D33)
There is no separate screen and no Continue gate. The moment a block's last step is logged or skipped, the next step's card appears immediately and the exercise block (zone 2) already shows the next exercise. The status strip reads the finished block's line — "Barbell Row done · 9:40 · try 72.5 kg next time".

**v1.2 (D33)**: walking to the next machine takes as long as a rest does, and v1.1 gave it no time at all — so it now runs a real countdown of `Settings.transitionRestSeconds` (default 120 s), with the same −30 / +30 / Skip controls as any other rest, and the same alert at zero. Set that setting to 0 and v1.1's behavior comes back exactly: no countdown, and the count-up "moving on · 0:42" beneath the block's line instead. The strip clears on the next log or skip, or can be dismissed directly (`dismissBlockDone`, §6.6). Timed-set logic behaves as normal throughout — there is no state in which it is suspended.

### 4.8 Overview (from "···", or the header's Exercises button)
Every step grouped by exercise with status and set time ("10 @ 60 · 0:34"); finished blocks show duration and advice. Tap logged → edit; tap pending → jump (cancels rest, and clears any block-done strip). A **skipped** step (v1.1, D27) can also be edited: the sheet's Save now sets its result, marks it logged, and updates `loggedAt` — recovering it rather than silently doing nothing. Reachable in every workout state, including rest and a block-done strip (v1.1) — previously it was attached only to the step card and unreachable during rest.

### 4.9 Summary (rewritten in v1.1's R4)
Leads with "**Workout saved**", then one line of what happened — "Push · 48 min · 16 of 18 sets · Volume 12,400 kg", with the volume fragment omitted entirely when it is zero (a bodyweight day has no volume, and "Volume 0 kg" reads like a failure). Then one section per exercise: a **sentence** comparing it to last time — "2 more reps at the same weight", "+2.5 kg", "+2.5 kg, 1 fewer rep", "5 s longer held", "First time" — plus the progression advice when there is any. When the weights varied within the exercise no single sentence is true of it, so a compact "10 @ 60 → 10 @ 62.5" table appears under a volume headline instead. Set and block durations sit behind **Details** (D19). **Done**.

*(v1 printed both sessions' raw sets — "10, 8@60 · last 10, 9@60 · kg" — and left the reader to do the subtraction, with the block duration beside it as if it mattered as much.)*

### 4.10 History
Sessions newest first by month, with a **search box** that finds an exercise by name (D30, v1.1) — most recently trained first — and opens its history directly. Session detail (editable, deletable, with a confirmation on delete, and **Rename exercise**, which moved here from the workout menu in v1.1); exercise history with best set, every session that included it, and a **chart of top weight over time with the reps annotated** (D13, built in v1.1's R5). A set that beat everything before it carries a **PR** badge here and on the Summary (D30). Tapping an exercise name anywhere opens it. A skipped step in session detail can be recovered the same way as in the live Overview (D27 v1.1).

### 4.11 Settings
Units, default rest, **warm-up length** (D32, v1.2), **between exercises** (D33, v1.2), sound, vibration, notifications state, keep awake, weight step, **smallest weight change** (D35, v1.2), Export backup, **Import backup** (D31, v1.1), **Export history (CSV)** and **Import history (CSV)** (D45, v1.3), Delete all data, About. (The home-chart metric row went with the sparkline in v1.1's R3.)

The three v1.2 rows, in the owner's words:

- **Warm-up length** — "there should be a warm-up phase before you actually start the first exercise." A duration, 0 to 30 min, 0 meaning off.
- **Between exercises** — "type how long it takes between switching different exercises." A duration, 0 to 10 min; 0 restores v1.1's behavior of moving straight on.
- **Smallest weight change** — the smallest increment the equipment actually allows, per unit. It is what every suggestion is rounded to (§6.11), so the app never says "try 134 lb" when the plates only make 135.

## 5. Flows

### 5.1 First run
Home's empty state offers two ways to have something to run today:
- **Try the sample plan** imports the bundled `SamplePlan.json` (same as `examples/valid/weekly-rotation.json`) and makes it active → Home shows "Push", its five exercises and **Start Push**.
- **Try a short practice workout** (v1.1) imports the bundled `PracticePlan.json`: one day, three straight-set exercises (one of them bodyweight), 60 s rest, no supersets, drops or timed work — small enough to run through in a few minutes to learn the app. It goes through the same import pipeline as any other plan; nothing in `examples/` is involved.

### 5.2 Getting a plan in (the loop that makes this app different)
1. Settings has units and default rest. **Add plan** → **Copy prompt** (step 1 of the three the screen lists).
2. User opens ChatGPT/Claude, pastes the prompt, adds their plan text below it ("Mon: bench 3×8 … " or "design me a 4-day upper/lower split").
3. Chatbot replies with a ```json block. User copies it.
4. Back in the app: **Paste plan** → **Review plan** (the exercises, the per-set targets, the warnings worth reading) → **Save plan**.
5. If it fails validation: the sentence on screen says what and where; **Copy fix-it prompt** → paste into the same chat → chatbot outputs corrected JSON → repeat step 4.

### 5.3 Running a workout
Home → Start → step card → Log set → rest → … → last set of the exercise → done screen (count-up) → Continue → next exercise … → last step → Summary → Done. Notification permission is requested the first time a session starts (not at app launch). If denied, a one-time in-app banner explains that alerts only work with the app open.

### 5.4 Interrupted workout
The active session is written to disk after every event. If the app is killed (or the phone dies), the Home start card offers Resume on next launch. Resume restores the exact step and, if a rest was running, shows it with the correct remaining or overrun time computed from `endsAt`; if the done screen was showing, its stopwatch continues from its `startedAt`.

## 6. Behaviors (precise rules)

### 6.1 Import pipeline
Four stages, each a pure function, each unit-tested:

1. **Extract** (`String → String`): strip BOM and zero-width characters; if the text contains a fenced code block, take the content of the first fence (any language tag); else take from the first `{` or `[` to the matching last `}` or `]`. Order of checks: over 1 MB → `E_TOO_LARGE`; blank → `E_EMPTY`; contains the prompt marker (PROMPT.md) and no fenced code block → `E_PROMPT_PASTED`; more than one fence, or a second top-level value after the first → `E_MULTIPLE_OBJECTS`; no `{`/`[` at all → `E_NOT_JSON`. The brace scan must be string-aware (braces inside string values don't count). Prose removed around the JSON → `W_SURROUNDING_TEXT` (a bare fence with nothing outside it is not prose).
2. **Decode** (`String → RawPlan`): strict `JSONDecoder` into lenient DTOs (every field optional, numbers-or-strings accepted where PLAN_FORMAT says so). If strict decode fails and the text contains curly quotes, replace them with straight quotes and retry; success → `W_CURLY_QUOTES_FIXED`. Still failing → `E_NOT_JSON` with the decoder's position/message.
3. **Normalize** (`RawPlan → Plan + [Issue]`): apply every leniency rule in PLAN_FORMAT §3 (wrap a bare day/array, expand `sets: 3` shorthand, parse rep strings, resolve rest via the fallback chain, infer schedule, normalize weekday and group strings, assign UUIDs, default missing names).
4. **Validate** (`Plan → [Issue]`): every rule in PLAN_FORMAT §4. Any `E_*` issue blocks import. `W_*` issues are shown in Preview and stored on the plan.

The original pasted text is kept on the Plan as `sourceText` for Copy JSON.

### 6.2 Flattening a Day into Steps
Input: `[Exercise]` in order. Output: `[Step]` where `Step = (exerciseIndex, setIndex, dropIndex, blockIndex, isLastInRound, isLastInBlock)`.

- Walk exercises in order. An exercise with no group, or whose group differs from its neighbors, is a block of one. Consecutive exercises with the same normalized group form one block. Blocks are numbered 0.. in order.
- A block of one exercise with sets S yields, for each set k, the step (e,k,0) followed by (e,k,1)…(e,k,D) for its D drops. `isLastInRound` is true on the last of those (the last drop, or the set itself if no drops).
- A block of exercises E1..En with set counts S1..Sn yields `max(S)` rounds. Round r yields, for each Ei with r < Si in listed order, the set step and its drop steps. `isLastInRound` is true only for the last step of each round.
- `isLastInBlock` is true for the final step of a block.
- Steps are numbered 0..N−1 in output order. Nothing else in the app reasons about groups or drops; it only sees Steps.

### 6.3 Rest resolution
Resolved at import into every Set Target as `restSeconds: Int`. Fallback chain, first non-nil wins:
`set.restSeconds → exercise.restSeconds → day.defaultRestSeconds → plan.defaultRestSeconds → user default rest setting (at import time)`.

At execution, after logging step i, with n = nextStep(after: i):
- n == nil → the session completes.
- `steps[i].isLastInBlock` and n is in a different block → **between exercises** (D14, timed in v1.2's D33): a rest of `Settings.transitionRestSeconds`, with the block's line in the strip. The Set Target's own `restSeconds` is not used here — the gap between two exercises is about the room, not about the set. `transitionRestSeconds = 0` means no countdown, which is v1.1's behavior.
- `!steps[i].isLastInRound` (the next step is a drop of this set, or the next superset member) → 0: the next step card appears immediately.
- otherwise → countdown of `restSeconds` of step i's Set Target, except for grouped exercises where the rest after a round is the first explicit `restSeconds` found among the group's members in listed order, else the fallback chain. A value of 0 means no timer.

If n is in the same block but earlier (the user jumped ahead and comes back), the rule for "otherwise" applies. If n is in an earlier block, between exercises.

**Before the first step (v1.2, D32)**: a session starts in a warm-up rest of `Settings.warmUpSeconds` whose `nextStep` is the first step, unless that setting is 0, in which case the session starts on the first step exactly as v1.1 did.

### 6.4 Rest timer
- State is `RestState(endsAt: Date, nextStep: Int, startedAt: Date)`. Remaining = `endsAt − now`, recomputed on every tick (TimelineView, 1 s) and on every foreground event. Never store a countdown integer.
- On rest start: schedule one local notification, identifier `"rest-timer"`, fire date `endsAt`, title "Rest over", body "Next: <exercise> · set k of n · <target>". Always `removePendingNotificationRequests(withIdentifiers: ["rest-timer"])` before scheduling and on skip/jump/finish/discard/app-quit-of-session.
- +30 s / −30 s: `endsAt += 30` (or −30); if `endsAt <= now` the rest ends immediately. Reschedule the notification after each adjustment.
- At `endsAt` while foregrounded: haptic (`.success`) and the sound (if enabled), overlay dismisses, phase → working(nextStep). Overrun label shows `now − endsAt` until the next log.
- If the app is foregrounded after `endsAt` already passed: no sound (the notification did that), phase → working(nextStep), overrun label shown.
- Audio: `AVAudioSession` category `.playback`, options `[.mixWithOthers, .duckOthers]`, activated only for the duration of the beep, so music keeps playing and the beep is audible on silent. Sound setting off → no audio session activity at all.
- The done screen's stopwatch is `now − transition.startedAt`, rendered by the same TimelineView. It schedules nothing and plays nothing.
- Work countdown for fixed-duration sets uses the same component with `endsAt = now + duration`, notification body "Time! <exercise> set k of n". "Done" early logs the elapsed seconds (rounded down); at zero it logs the full duration and moves to rest.
- Warning beep (fixed durations, `warningBeepSeconds = w`, resolved at import per PLAN_FORMAT §3.12): at `endsAt − w` play a short, quieter tick plus a light haptic (respecting the sound and vibration settings). It is scheduled as a second local notification, identifier `"set-warning"`, body "{w} s left", with the bundled short `warning.caf`, so it also fires when the phone is locked. The final beep at `endsAt` is the normal alert plus the `"set-end"` notification. Both notifications are cancelled together on Done, Stop, skip, jump, finish, discard. Beep moments are computed from `startedAt`, never counted; a moment that passed while backgrounded is not replayed (the notification covered it).
- Open-duration sets run a stopwatch from `startedAt`; **Stop** logs `floor(now − startedAt)`. If the target has a minimum, one beep (tick + haptic, and a `"set-minimum"` notification "30 s reached") plays at `startedAt + min`. Nothing else fires; there is no end.

### 6.5 Memory: prefill and "last time"
Same-name lookup uses the normalized name (D8) and only considers **completed** sessions, newest first. "Last session" below means the most recent completed session containing this exercise **with the same units as the current plan** and at least one logged set of it.

Weight prefill for step (exercise E, set index k), first hit wins:
0. **v1.3 (D44)**: the exercise carries a progression week and the set's target has a weight → that weight. You asked a chatbot to plan it; the plan is what the card shows. ("Last" still says last time's weight underneath.)
1. Most recent logged weight for E **in the current session** (any earlier set index).
2. Last session: weight logged at set index k if present, else the last logged weight for E in that session.
3. The Set Target's weight.
4. Empty.

Reps prefill (D11), first hit wins:
0. **v1.3 (D44)**: a progression week → the target's reps (fixed n → n; range → min), else last time's.
1. Last session: reps logged at set index k, **if the prefilled weight equals that set's weight** (same number, same unit; both nil counts as equal). This is the normal case: you did 10 @ 60 last week, the card shows 10 @ 60, and one "+" makes it 11.
2. Last session has no set k (fewer sets last time) → the last logged reps for E in that session, same weight condition.
3. Otherwise the target: fixed n → n; range (min, max) → min; amrap → empty.

Dynamic rule: while the step card is showing, if the user changes the **weight** field to a value different from the last session's weight for that set, and has not yet edited the reps field, the reps field re-prefills from rule 3 (the target). Changing the weight back restores rule 1. Once the user edits reps, the app stops touching it.

Seconds prefill for fixed-duration sets: last session's seconds at index k, else the target duration. Open-duration sets have no prefill (the stopwatch decides); the "Last time" line shows last session's seconds ("0:52, **0:48**, 0:40").

Drops: lookups use (set index, drop index). Weight prefill for a drop, first hit: same drop last session (same conditions as above); the drop's target weight; the previous step's logged weight (so the user only taps −). Reps prefill for a drop: last session's reps at that drop if the weight matches, else the drop's target (AMRAP → empty).

"Last time" line: from the last session: reps per set joined by ", ", drops joined to their set with "↓" ("10↓8↓6"), and weight(s). The entry whose set index equals the current step's set index is rendered **bold**. If all weights equal show "@ 60 kg" once; if they differ show per set "10@60, 8@65"; if none show reps only. Skipped sets show "–". If the last session had fewer sets than the current index, nothing is bold.

Under the weight field: "Last: <last session's weight at index k, or last logged weight> kg". Absent if none. When §6.11 produced a suggestion for E in the last session, a chip "Suggested: 62.5 kg" appears next to it; tapping sets the weight field (and triggers the dynamic rule above).

### 6.6 Session state machine
Pure struct `SessionEngine` with `apply(_ event: Event, now: Date) -> [Effect]`. Effects: `scheduleNotification(at:body:)`, `cancelNotification`, `playAlert`, `persist`, `sessionCompleted`.

```
// v1.1 removed `.transition`; v1.2 folds the warm-up and the between-exercises gap into
// `resting`, which is where the countdown, the controls and the notification already lived.
enum Phase { case working(step: Int), resting(RestState), completed }
enum RestKind { case warmUp, betweenSets, betweenExercises }
struct RestState { var startedAt: Date; var endsAt: Date; var nextStep: Int; var kind: RestKind }

enum Event {
  case logSet(step: Int, result: SetResult)
  case editSet(step: Int, result: SetResult)      // no phase change, no timer
  case skipSet(step: Int)
  case skipExercise(exerciseIndex: Int)           // all pending steps of that exercise → skipped
  case jumpTo(step: Int)                          // cancels rest, phase → working(step)
  case adjustRest(seconds: Int)
  case skipRest
  case restElapsed                                // from tick or foreground check
  case startTimer(step: Int)                      // timed sets: begins the countdown/stopwatch
  case stopTimer(step: Int)                       // open duration: logs elapsed seconds
  case timerDone(step: Int)                       // fixed duration, early: logs elapsed seconds
  case timerElapsed(step: Int)                    // fixed duration reached zero: logs the target
  case dismissBlockDone                           // v1.1: clears the strip's block-done line
  case renameExercise(exerciseIndex: Int, name: String)
  case substituteExercise(exerciseIndex: Int, name: String, weight: Double?)  // v1.3 (D42): the remaining sets go to another exercise
  case finish                                     // remaining pending → skipped, → completed
}
```

Rules:
- Whenever the phase becomes `working(step)` (from any event), set `steps[step].startedAt = now` unless the step is a timed set, whose `startedAt` is set by `.startTimer` instead. Re-entering a step (jump back) resets it.
- `startTimer(step)`: timed sets only; sets `startedAt = now`, phase stays working. Effects: fixed duration → `scheduleNotification("set-end", endsAt)` and, if `warningBeepSeconds` is set, `scheduleNotification("set-warning", endsAt − w)`; open duration with a minimum → `scheduleNotification("set-minimum", startedAt + min)`. `stopTimer`/`timerDone`/`timerElapsed`/skip/jump emit `cancelNotification` for all three ids. `stopTimer` (open) / `timerDone` (fixed, early) log `floor(now − startedAt)` seconds via the normal logSet path; `timerElapsed` (fixed, at zero) logs the full duration.
- `nextStep(after i)`: first pending step with index > i; else first pending step with any index; else nil.
- `logSet(i)`: set result, status = logged, `loggedAt = now`. Let n = nextStep(after: i). If n == nil → completed. Else per §6.3: a block ended → `blockDone` is recorded for the strip and, when `transitionRestSeconds > 0`, phase → `resting(kind: .betweenExercises)`; rest 0 → working(n); else `resting(kind: .betweenSets, endsAt: now + rest, nextStep: n)` + scheduleNotification.
- `skipSet(i)`: status = skipped, `loggedAt = now`, then the same advance logic but **never starts a between-sets countdown** — you skipped the set, you do not need the rest after it. A skipped set that ends a block still gets the between-exercises rest (v1.2): the walk to the next machine happens either way.
- `skipExercise`: mark that exercise's pending steps skipped (loggedAt = now), then the block-done strip if a block ended and another remains, else working(nextStep(after: current)) or completed.
- `dismissBlockDone`: clears the strip's block-done line; it does not end a between-exercises rest, which has its own Skip.
- `substituteExercise(e, name, weight)` (v1.3, D42, §6.18): the exercise's **pending** steps become steps of `name`; logged and skipped ones keep their exercise. No phase change, no reorder, no change to `blockIndex` — a running rest keeps running. Refused when the session is completed, the name is blank, the exercise has nothing pending, or the name is unchanged and no weight was given.
- A session starts in `resting(kind: .warmUp, nextStep: firstStep)` when `Settings.warmUpSeconds > 0` (D32, §6.14), and on the first step otherwise.
- Any event that changes phase away from resting emits `cancelNotification`.
- `finish` with pending steps: the UI must confirm ("3 sets not done. Finish anyway?"); the engine just does it.
- `finish` or completing with **zero logged steps**: UI asks "Nothing was logged. Discard this workout?" → discard (no session saved, no rotation advance). "Save anyway" is not offered.
- Completed session: `endedAt = now`, moved from `active-session.json` to `sessions/<id>.json`, rotation pointer updated (§6.8), summary shown.
- Every event ends with `persist`.

### 6.11 Progression advice (D12)
Evaluated for an exercise E the moment its last step in the session is logged or skipped, and again on the Summary and in history. Pure function `ProgressionAdvice.evaluate(exercise: SessionExercise, steps: [SessionStep], weightStep: Double) -> Advice?`.

Inputs: `range = E.repRange` (min, max). The logged rep-based **main** sets of E this session (dropIndex 0; drops are ignored): `n` sets with reps `r_1..r_n` and weights `w_1..w_n`.

Preconditions (return nil if any fails): E has a rep range; n ≥ 1; every logged set is rep-based; all `w_i` are equal (one working weight; nil when E is bodyweight or no weight was logged). Skipped sets are ignored; if every set was skipped, nil.

Let `achieved = Σ r_i`, `ceiling = n × max`, `floor = n × min`, `tolerance = 1`.
- `achieved ≥ ceiling − tolerance` → `.increase(to: w + weightStep)`. Message: "All sets hit the top of {min}–{max}. Try {w + step} {unit} next time." Bodyweight (w nil) → `.increaseLoad`: "You've completed the range. Add load or a harder variation." `tolerance = 1` means missing a single rep across the whole exercise still counts as done; that is the owner's "close to completing" rule.
- `achieved < floor` → `.decrease(to: max(0, w − weightStep))`. Message: "Below {min}–{max} across {n} sets. Try {w − step} {unit} next time, or keep {w} and build up." Bodyweight → `.decreaseLoad`: "Below the range. Try an easier variation or fewer sets."
- otherwise → nil (inside the range; keep the weight). The UI shows nothing.

The advice is stored on the completed session's exercise (`advice`) so the next session can show the "Suggested" chip without recomputing across history. Advice is never applied to the weight field automatically.

**v1.3 (D44)**: in a progression week the set's target *is* the suggestion — the chip reads "Try 8 × 62.5 kg" with the reason "Week 3 of 8 of your progression" and outranks advice from last time, which the chatbot has already read. Advice is still evaluated and stored, so it is there the week after the progression ends.

**v1.2 (D35): every suggested weight is snapped to a weight you can actually load.** `w ± weightStep` is arithmetic, and arithmetic will happily produce 134 lb on a rack whose smallest plate pair makes 135. So the result is rounded to the nearest multiple of `Settings.weightIncrement(for: units)` — 2.5 kg or 5 lb by default — and never rounded down to a number that is not an increase when the advice was to increase (or up, when it was to decrease). A weight already on an increment is unchanged. The same rounding applies to the − / + steppers and the suggestion chip, so every number the app offers is loadable.

### 6.14 Warm-up (D32, v1.2)
"There should be a warm-up phase before you actually start the first exercise."

A session with `Settings.warmUpSeconds > 0` starts in `resting(kind: .warmUp, nextStep: <first step>)`. It is a rest in every mechanical sense — the same countdown, the same −30 / +30, the same notification, the same alert at zero, the same right to log straight out of it — and it differs only in what the strip says and in the fact that it comes before anything has been logged. At zero it becomes `working(firstStep)`; its Skip reads **Skip warm-up**.

It is not a set, it is not logged, and it does not appear in history. A session whose warm-up is the only thing that happened is still a session with nothing logged, and is discarded on finish exactly as before (§6.6).

`warmUpSeconds = 0` starts the session on its first step, which is what v1.1 did.

### 6.15 The stage (D34, v1.2)
"It should be a bit more clear what stage of the workout you're on."

`WorkoutStage` resolves, in Core, to one of: **Warm-up**, **Exercise k of n · Set j of m**, **Resting**, **Between exercises**, **Done** — plus a `progress` fraction of the whole day, which is logged-or-skipped steps over total steps. The header renders both; nothing about the stage is computed in a view, so the wording per state is a unit test.

### 6.16 Metrics (D39, v1.2)
"Should be able to select a past workout and see … metrics for the past — I don't know exactly what metrics would be, but they should be included."

Everything is a `Metric`: a label, an already-formatted value, and a one-line note where the number needs one. Views render the list; they compute nothing.

**One workout** (`SessionMetrics.of(_:history:)`, shown in Session detail): duration; **working** and **resting** time with the share of the session each took; sets done of sets planned, with the skipped count; volume; reps; time under tension for timed work; the heaviest set; personal records with the exercises that set them; the average set. A metric with nothing to say is absent rather than zero — a bodyweight day has no volume, and "Volume 0 kg" reads like a failure.

**A run of workouts** (`TrendMetrics.summary(_:days:)`, on the **Metrics** screen under History, over 7 / 30 / 90 days): how many workouts and how many a week; time trained and the average length; volume; sets; consecutive weeks with at least one workout; the most-trained exercise; and the all-time count with the month it started. Volume only adds up within one unit, because the app never converts (D10). Under the numbers, the workouts of that window, so any figure can be traced back to the days that made it.

**Getting to a past workout** is one tap from three places: the History list, the **Metrics** screen, and Home's calendar — where the line under the grid is now the way in ("Sat 6 · Legs · 28 min ›"). v1.1 wanted a second tap on the cell, which nothing on the screen said you could do.

### 6.17 Lock Screen and Dynamic Island (D40, v1.2)
"Could also have the time appear at the lock screen at the top — that would also be useful — and in the Dynamic Island."

A **Live Activity** runs for as long as a workout does. It shows the stage (Warm-up, Rest, Between exercises, or the exercise's name), the line under it ("Bench Press · set 2 of 4 · 8–12 · 60 kg"), the timer, and a bar of the day's progress. In the Dynamic Island it is the same three states compact, expanded and minimal.

- **The countdown is drawn by the system**, from a `Date`, exactly as §6.4's rest timer is. The app does not push an update per second and does not have to be awake for the number to be right.
- **`WorkoutActivityState` is resolved in Core** from the same `ActiveSession` the workout screen reads, so the Island and the app cannot disagree. `WorkoutActivityState.swift` is the one file compiled into both the app and the widget extension — it is the contract between them, and depends on nothing but Foundation.
- **ActivityKit lives behind `ActivityPresenting`**, injected exactly as `NotificationScheduling` is, so what the Lock Screen would show is a unit test rather than something only a phone can answer.
- A state that has not changed is not pushed. A per-second tick that woke the system sixty times a minute would cost battery for no new information.
- The activity ends when the workout does — finished **or discarded**. A countdown for a workout that no longer exists is worse than none.
- Failure is silent: a Lock Screen widget that will not start is a missing convenience, not a lost set, and the workout screen is unaffected. The user can turn Live Activities off for the app in iOS Settings, and the app simply shows nothing.

The extension target is `JimmsBroActivity` (`com.ohayoune.jimmsbro.activity`), embedded in the app. It renders and nothing else.

**D41 (v1.3): the compact Island is the timer, boxed.** "The Dynamic Island is too big — it shouldn't be so wide." It was wide for two reasons, neither of them content: `Text(timerInterval:)` reserves the width of the widest string it might ever draw, and a count-up whose range ran to `.distantFuture` was allowed to grow to `h:mm:ss`. So:

- `WorkoutActivityState.timerRange(now:)` is the one range the system timer is given, resolved in Core: a countdown is `now…max(endsAt, now + 1 s)` (never inverted, which would crash the text), and a count-up is cut at 59:59 (`longestTimer`). Nothing here runs an hour — a rest is at most 3600 s, a warm-up 30 min, and an open hold that long is not a set.
- The timer is told not to show hours, and in the compact and minimal Island it sits in a fixed box the width of "59:59" in its font, with monospaced digits. Compact leading is one symbol. Nothing else is in the compact Island; the set line and the progress bar belong to the expanded view.
- The Lock Screen banner keeps its title, timer, one line of detail and the bar, with 4 pt less padding.

### 6.18 Changing an exercise mid-workout (D42, v1.3)
"Being able to change exercise mid workout." The machine is taken and **Do later** (D28) is not the answer, because you want to do *something* now, on the equipment that is free.

`Event.substituteExercise(exerciseIndex:name:weight:)`, in the engine, with these rules:

- **Only what is left changes.** The exercise's pending steps become steps of the new exercise; logged and skipped steps keep the name they were done under. Step order and `blockIndex` do not change, so the position in the day, the rest that is running and the block durations are all exactly what they were.
- **Nothing done yet → renamed in place.** The `SessionExercise` takes the new name and `substitutedFor` remembers the old one.
- **Something done → split.** A second `SessionExercise` is appended, a copy of the original with the new name, `substitutedFor` the original's name and `replaces` the original's index, and the pending steps are re-pointed to it. History then says "Bench Press 1 set, Dumbbell Press 2 sets", which is what happened. `SessionBlocks.canonical` folds the two into one position, so the header still reads "Exercise 2 of 5"; the set rows show the logged sets under their own name next to the pending ones, named the way a superset's rows are.
- **The substitute keeps its own identity (D8).** Prefill, "last time", the suggestion chip, advice and PRs all read the new name's history. Whether it is bodyweight follows its own history when it has one. The original earns **no advice** for an exercise it did not finish; the substitute earns its own.
- **A weight, if given, replaces every pending target's weight**; empty keeps the plan's. The same name with a weight is just a weight change for the remaining sets; the same name with nothing is nothing.
- **A superset member is substituted alone**; the round stays a round.
- Said once: "Dumbbell Press · was Bench Press" on the exercise's target line, "Instead of Bench Press" on the Summary — never on every row.

UI: "···" → **Change exercise**, offered whenever the exercise still has a set to do, in every state including rest. One sheet: the name (exercises done before, most recent first, narrow as you type), an optional weight, **Change**.

### 6.19 JSON edits, at every size (D43, v1.3)
"Single plan JSON edits, and specific JSON edits in general." D29's structured sheet covers the everyday change; sometimes the fastest edit is the text — one set unlike the others, a day the chatbot wrote wrong, a week it cut short. Every JSON edit goes through the same pipeline a paste does, so the app can never hold a plan it would have refused to import.

- **Fragments.** `PlanJSON.render(day:)` and `render(exercise:)` write one part as text, in the plan format, at the left margin. `PlanEdit.fragment(_:as:)` reads one back with the pipeline's own leniency — fences, prose around it, curly quotes — and is generous about shape, because a chatbot asked for "the missing day" may answer with a day, a whole plan holding it, or a bare list of exercises: read **as exercises**, a plan gives all its exercises, a day its exercises, an exercise itself; read **as days**, a plan gives its days, a day itself, loose exercises become one day, and an object that says nothing an exercise says is a day with nothing in it — refused with the importer's own "has no exercises".
- **The splice** (`PlanEdit.spliced`) works on the plan's own JSON *tree*, not its text, so a fragment lands at a real path and the pipeline's errors name it: `days[1].exercises[2].sets[0].reps` becomes "Day 2, exercise 3, set 1". Four operations: `replaceExerciseJSON`, `replaceDayJSON`, `insertExercisesJSON(day:at:)` and `insertDaysJSON`. After the re-import the plan keeps its id, import date, cycle position and anchor, and its text becomes the canonical rendering.
- **A replaced day keeps its identity.** An unnamed fragment keeps the old name; a renamed one takes the old name's place in the repeat block, which refers to days by name.
- **An added day is a day you mean to train.** It is named here if the fragment did not name it, and a rotation's repeat block gains it at the end. A weekday plan insists on a weekday, with the importer's own sentence.
- **Refusals stay in the sheet, with the text**, so a typo is fixed rather than retyped. A fragment that is not JSON, not a plan shape, or two exercises where one goes is refused before the pipeline runs.
- **The whole plan** is Plan detail's **Edit JSON** — the Add plan sheet targeting this plan's id (v1.1's Replace, renamed for what you came to do). It keeps the id, the position and the anchor.

A v1.2 defect fixed here, because the splice goes through the same `apply`: a plan edit and Replace both dropped `cycleAnchor`, so the next launch re-anchored the rotation to that day and the calendar moved — the compounding D37 had just fixed. Both now keep it (W20).

### 6.20 History as a file (D45, v1.3)
"An importable CSV history file, and an importable history file in general that you can add to another app." The JSON backup (D31) is for this app; it carries ids, plans, settings and the active session, and nothing else reads it. History for *another* app is a CSV: one row per logged set, columns named in the first line.

- **Export** (`HistoryCSV.render`): `Date, Workout Name, Duration, Exercise Name, Set Order, Weight, Reps, Distance, Seconds, Notes, Workout Notes, RPE` — the column order Strong writes and Hevy reads — with `Weight Unit` last, because this app never converts (D10) and a file that does not say its unit is a guess. Dates are local `yyyy-MM-dd HH:mm:ss`; the duration is Strong's "48m" / "1h 5m". Drops are rows of their own; skipped sets are not rows; a value holding a comma or a quote is quoted. Oldest first.
- **Import** (`HistoryCSV.parse`) finds its columns **by header name, not position**, so its own export, a Strong export (either delimiter, with or without a unit column) and a Hevy export (`weight_kg`, `start_time` in words, an `end_time`) all read. A row's unit comes from a unit column, then from the weight header (`weight_kg`, `Weight (lbs)`), then from the setting — and when the setting had to be used, the summary says so ("weights read as kg"). A weight of 0 is no weight, which is what Strong writes for a bodyweight set; an exercise none of whose sets has a weight is marked bodyweight. A row whose date cannot be read, that names no exercise, or that has neither reps nor seconds is skipped and named by line; a file with no usable columns, or no usable rows, is refused with a sentence.
- **Grouping**: a run of rows with the same start and workout name is one workout; its exercises come in order of first appearance; each row is a logged set. The duration is the file's, else the end time's, else a minute a set. Sets are spread evenly over it — the file says when the workout started and how long it took, not when each set was logged — so the metrics that need set times (D19) stay absent rather than invented.
- **Imported sessions are ordinary sessions**: `planId` nil, `planName` "Imported", the workout name as the day name, steps logged with their timestamps. Prefill, "last time", PRs, the chart and Metrics read them as if they had been logged here. They never advance a plan's rotation.
- **Nothing is written before it is described.** Settings → Import history reads the file and says "42 workouts (610 sets) from 12 Jan to 3 Sep · 5 already here · weights read as kg", then offers **Import**. A workout already in History — the same name at the same minute — is skipped, so a file imported twice adds nothing, and the dialog says "Nothing new in this file". A failed write is surfaced as any other save is (D24).
- The same flow is offered from an empty History tab ("Import from another app"), the one place an empty History can say what fills it.

### 6.21 Progression (D44, v1.3)
"A feature called progression: based on the current workout plan, give the chatbot a JSON and have it calculate your progression over a certain period. When there is history, use it as context." The app's premise is the chatbot round-trip, and until now it ran one way. Progression runs it the other way: the app writes out what the plan is and what you have actually done, the chatbot plans the next N weeks, and the plan carries the answer week by week.

- **The model.** `Plan.progression: Progression?` — a start date, a number of weeks (1–52), and per (day, exercise) one `ProgressionWeek` per week: a weight and/or a work target for every set, or per-set overrides. Optional in `Persistence.swift`; a plan without one is exactly a v1.2 plan. `Session.progressionWeek` / `progressionWeeks` and `SessionExercise.progressionWeek` record which week a workout was.
- **The prompt** (`Prompts.progression`, marker `JIMMSBRO-PROGRESSION-PROMPT-V1`, PROMPT.md §3): the period, the plan as a compact listing (one line per exercise, not its JSON), the loadable increment (D35), and — when **Use my history** is on and there is any — the last six sessions of every exercise in the plan within 90 days, with the advice the most recent one earned. Kept under 9,000 characters by shortening the history first, never the plan.
- **The reply** (`ProgressionImport`, PROGRESSION_FORMAT.md): a small JSON — `weeks` and one entry per exercise with an array of week objects. Read with the plan importer's leniency, matched to the plan by day and exercise name (§6.9), every weight snapped to the loadable increment, weights on bodyweight exercises dropped, and everything dropped or short **said**: material warnings on the review, tidying behind Details. Nothing about the plan's structure changes.
- **The week** is calendar weeks from `startDate`, which is the day the progression is saved. `Session.start` applies the current week to the day's snapshot (D7 holds: the session records what it was asked to do) and stamps the week on the exercises it touched. An exercise, week or set the progression says nothing about keeps the plan's own target; a range of reps also becomes the rep range advice judges by. The day after the last week, the plan's own targets and advice are back — nothing lingers.
- **On the workout**, prefill shows the week's weight and reps (§6.5, rule 0) and the chip says which week (§6.11). The Summary's line and Session detail's first line carry "week 3 of 8". Home's subtitle carries it too, and when it has run out Home offers **Plan the next one**.
- **Edits keep it, Replace drops it.** A structured or JSON edit (D29, D43) carries the progression through — entries match by name, so a renamed exercise simply stops matching. Edit JSON / Replace of the whole plan, or a name-conflict Replace on import, starts a new plan without one.

### 6.12 Calendar projection
`Calendar.entries(month, plans, sessions, today) -> [DayEntry]`, `DayEntry = .completed([Session]) | .projected(planId, dayIndex) | .rest | .none`, for the active plan only. `.rest` is a day the plan schedules as rest; `.none` is a day the plan says nothing about (the past, beyond the horizon, or no active plan). The two are drawn differently: `.rest` gets a grey dot, `.none` gets nothing.
- Past and today: `.completed` for days with ≥ 1 completed session (any plan). Past days without a session are `.none`, never `.rest` — a day you didn't train is not a scheduled rest day.
- Future days (and today if no session yet):
  - weekday plan → `.projected` for days whose weekday has a Day, `.rest` for every other weekday (a weekday plan names all its training days, so the remainder are rest).
  - rotation plan (v1.2, D37) → the cycle entry for a date is `cycle[(cyclePosition + daysFrom(cycleAnchor)) mod count]`. Every rotation is painted this way, rest entries or not: `.day` → projected, `.rest` → rest, and a `.day` entry whose index no longer exists is `.none`, not `.rest`.
- Projection never shows more than 62 days ahead (two months); past that every day is `.none`.

**D37 (v1.2): the anchor, and why.** v1.1 walked the cycle forward from *today* — `cyclePosition + daysFromToday` — and `cyclePosition` moved only when a session completed. Miss a workout and every later day slid by one, and by one more for each further day missed. The owner: *"if one day of the week is messed up then it compounds."*

`Plan.cycleAnchor` is the day `cyclePosition` describes, so the pattern is nailed to the calendar:

- Missing a workout changes **nothing** about what any other day says.
- The pattern moves only when a workout **finishes**, which re-anchors it, once, to the day it was actually done.
- A rest-free cycle is painted for the whole horizon, because it is now a real repeating pattern rather than a guess about tomorrow. v1.1 projected only tomorrow and left the month blank.
- A plan that predates the anchor is anchored to today at launch, once, and written down. Nothing it says today changes; from tomorrow it stops sliding.
- The day the schedule expected and did not get is **said**, on Home — "Push was due Monday", with **Do it now** and **Dismiss** — rather than resolved behind your back. Only the most recent one, and only within a week: a plan you came back to after a fortnight is a fresh start, not a missed Tuesday.

Home's **Next up** and the ring on the grid read the same function (`PlanSchedule.next(_:today:)`), so they cannot disagree. In v1.1 they were computed two different ways, which is the other half of why the calendar felt clunky.

**D38 (v1.2): what a cell says.** v1.1 drew every day as the same 5 pt dot — filled for done, outlined for planned, grey for rest — so a month of training looked like a month of anything else, and the shape of a week could not be read off the grid ("the spacing … is not perfectly clear"). A cell now carries the day's short name under its number, a finished day is filled in the reserved green, a planned day is outlined in the accent, and a rest day is a dash: a visible gap rather than another kind of dot. Each cell reads as one VoiceOver sentence ("Monday 7 September. Planned: Push").

### 6.7 Stats
- Session duration = `endedAt − startedAt` wall clock. No pause feature. Elapsed time is shown in the workout header and on the rest overlay.
- Set duration (D19) = `loggedAt − startedAt` for a logged step, in whole seconds; nil if `startedAt` is missing (pre-D19 data) or the step was skipped. Shown as "0:34". Average set time per session appears on the Summary.
- Exercise duration (for an ungrouped exercise, or for a whole superset block): `end − start` where `end` = `loggedAt` of the block's last logged-or-skipped step, and `start` = `loggedAt` of the last step logged before the block began (the previous block's last step), or `session.startedAt` for the first block. Transition time between blocks therefore counts toward the exercise that follows it, so block durations sum to the session duration. The done screen shows the block that just finished (its duration excludes the stopwatch now running). Not shown until the block is finished (all its steps logged or skipped); never shown for a block with zero logged steps. Skipped steps get `loggedAt` set to the skip time so this works.
- `ExerciseHistory.series(name, units) -> [ExercisePoint]`: one point per completed session containing the exercise, oldest first: `date`, `sets: [SetResult]`, `setSeconds: [Int?]`, `topWeight`, `topSetReps` (reps at topWeight), `topSeconds` (longest duration set), `volume`, `units`. This is the data source for the time-vs-weight-and-reps chart, which v1.1's R5 built on top of it with no schema change (D13, D30); it must run under 50 ms for 1000 sessions.
- Sets logged/total counts steps; skipped steps count in total only.
- Volume = Σ (reps × weight) over logged rep-based steps (drops included) that have a weight. Timed steps and weightless steps contribute 0. Displayed in the session's units. Never summed across sessions with different units (History list shows per-session volume only).
- Exercise best = the logged set with the highest weight; tie → more reps. Rep-based sets only. Shown as "Best: 100 kg × 5". If no weighted sets: most reps.
- "This time vs last time" on Summary compares per exercise to the most recent earlier completed session containing that exercise.

### 6.8 Plans, active plan, cycle, weekday (D16)
- Many plans may exist; exactly one is active (or none). Importing a plan makes it active if none is active; otherwise it asks.
- Every plan has `cycle: [CycleEntry]`, `CycleEntry = .day(dayIndex) | .rest`, length 1–31, resolved at import (PLAN_FORMAT §3.10): explicit `cycle` for rotation plans, else the days in order with no rest; weekday plans always derive `[Mon…Sun]` with `.rest` for unlisted weekdays and ignore an explicit cycle.
- Rotation: `cyclePosition: Int?` = index in the cycle of the last completed entry. **Next up** = the first `.day` entry after `cyclePosition` (wrapping; from index 0 if nil). Rest entries are skipped by Next up but used by the calendar.
- On session completion for plan P, day D (matched by normalized name in P's current days): `cyclePosition` = the first index after the current position (wrapping) whose entry is D; if D isn't in the cycle, unchanged. Discarded sessions never move it. Deleted plan / unknown day: nothing happens.
- Replacing a plan: keep the position by matching the day name at the old position to the new cycle (first occurrence); if it doesn't exist, nil.
- Weekday plans: Home shows the day whose weekday equals today (local calendar); else "Rest day" and the next weekday that has one. `cyclePosition` is unused.
- Starting any Day from Plan detail or the calendar is always allowed regardless of the cycle. If a session is in progress it triggers the D17 popup; "Finish X and start Y" finishes X exactly like Finish (pending → skipped, advice, cycle advance) then starts Y; "Discard X and start Y" discards X.
- Two sessions on the same calendar day are allowed. A session's `date` for grouping = local calendar date of `startedAt`.

### 6.9 Exercise name matching
`normalized(name) = name.trimmingCharacters(whitespacesAndNewlines).lowercased()` then collapse runs of whitespace to one space. No diacritic folding. Used for history lookup, plan-name conflicts, day lookup for the pointer, and group tags (uppercased instead of lowercased).

### 6.10 Input rules
- Reps field: digits only, max 3 characters, 0 allowed (a failed set logs as 0, no confirmation), empty disables Log set.
- Weight field: digits plus one decimal separator; accept both `.` and `,`; one decimal place kept; 0 allowed; empty allowed (logs no weight); max 10000.
- Seconds field (timed sets): digits, max 5 characters, 0 allowed.
- − / + buttons never go below 0. Long-press repeats.

## 7. Data model (Core, Codable, no UI imports)

```swift
struct Plan: Codable, Identifiable {
    var id: UUID
    var name: String
    var units: WeightUnit                 // kg | lb
    var schedule: Schedule                // rotation | weekday
    var days: [Day]
    var importedAt: Date
    var sourceText: String                // original paste
    var warnings: [Issue]                 // W_* from import
    var cycle: [CycleEntry]               // resolved at import (§6.8)
    var cyclePosition: Int?
}
struct Day: Codable, Identifiable { var id: UUID; var name: String; var weekday: Weekday?; var exercises: [Exercise] }
struct Exercise: Codable, Identifiable { var id: UUID; var name: String; var group: String?; var notes: String?; var repRange: RepRange?; var bodyweight: Bool; var sets: [SetTarget] }
struct RepRange: Codable, Equatable { var min: Int; var max: Int }   // 1 ≤ min ≤ max ≤ 1000
struct SetTarget: Codable { var work: WorkTarget; var weight: Double?; var restSeconds: Int; var warningBeepSeconds: Int?; var drops: [DropTarget] }   // rest and warning offset already resolved; warning only on fixed durations
struct DropTarget: Codable, Equatable { var work: WorkTarget; var weight: Double? }   // work defaults to .reps(.amrap(min: nil))
enum WorkTarget: Codable { case reps(RepTarget); case duration(seconds: Int); case openDuration(minSeconds: Int?) }
enum RepTarget: Codable { case fixed(Int); case range(min: Int, max: Int); case amrap(min: Int?) }
enum Weekday: String, Codable, CaseIterable { case monday, tuesday, wednesday, thursday, friday, saturday, sunday }

struct Step: Equatable { let exerciseIndex: Int; let setIndex: Int; let dropIndex: Int; let blockIndex: Int; let isLastInRound: Bool; let isLastInBlock: Bool }
enum CycleEntry: Codable, Equatable { case day(Int), rest }

struct Session: Codable, Identifiable {
    var id: UUID
    var planId: UUID?; var planName: String; var dayName: String
    var units: WeightUnit
    var startedAt: Date; var endedAt: Date?
    var exercises: [SessionExercise]      // snapshot; names editable for this session
    var steps: [SessionStep]              // flattened, in order
}
struct SessionExercise: Codable, Identifiable { var id: UUID; var name: String; var group: String?; var notes: String?; var repRange: RepRange?; var bodyweight: Bool; var targets: [SetTarget]; var advice: Advice? }
enum Advice: Codable, Equatable { case increase(to: Double), increaseLoad, decrease(to: Double), decreaseLoad }
struct ExercisePoint: Equatable { var date: Date; var sets: [SetResult]; var setSeconds: [Int?]; var topWeight: Double?; var topSetReps: Int?; var topSeconds: Int?; var volume: Double; var units: WeightUnit }
struct SessionStep: Codable { var exerciseIndex: Int; var setIndex: Int; var dropIndex: Int; var blockIndex: Int; var isLastInRound: Bool; var isLastInBlock: Bool; var status: StepStatus; var result: SetResult?; var startedAt: Date?; var loggedAt: Date? }   // setSeconds = loggedAt − startedAt
enum StepStatus: String, Codable { case pending, logged, skipped }
enum SetResult: Codable { case reps(count: Int, weight: Double?); case duration(seconds: Int, weight: Double?) }

// v1.1 added the last five fields; `blockDone` replaced the removed `.transition` phase, and
// `lastCompletedStep` is what D23's Undo acts on.
struct ActiveSession: Codable { var session: Session; var phase: Phase; var lastRestEndedAt: Date?; var workWeight: Double?; var timerRunning: Bool; var deliveredBeeps: Set<TimerBeep>; var blockDone: BlockDone?; var lastCompletedStep: Int? }
struct BlockDone: Codable { var finishedBlock: Int; var startedAt: Date }
struct RestState: Codable { var startedAt: Date; var endsAt: Date; var nextStep: Int; var kind: RestKind }
enum RestKind: String, Codable { case warmUp, betweenSets, betweenExercises }   // v1.2, §4.6

// `homeMetric` went with the sparkline in v1.1's R3. The last three are v1.2's (D32, D33, D35).
struct Settings: Codable { var units: WeightUnit; var defaultRestSeconds: Int; var sound: Bool; var vibration: Bool; var keepAwake: Bool; var weightStepKg: Double; var weightStepLb: Double; var warmUpSeconds: Int; var transitionRestSeconds: Int; var weightIncrementKg: Double; var weightIncrementLb: Double }

// Every one of these may be absent from a file written by an older version; `Core/Persistence.swift`
// says which keys are required (identity) and which take a default (everything else).

struct Issue: Codable, Equatable { var severity: Severity; var code: String; var path: String; var message: String }   // e.g. ("error","E_REPS_INVALID","days[0].exercises[2].reps","…")
```

## 8. Persistence

### 8.1 Layout
```
<Application Support>/JimmsBro/
  settings.json            Settings
  plans.json               { "fileVersion": 1, "activePlanId": UUID?, "plans": [Plan] }
  active-session.json      { "fileVersion": 1, ...ActiveSession }   present only during a workout
  sessions/<uuid>.json     { "fileVersion": 1, ...Session }          one file per completed session
```
Application Support is included in iCloud/iTunes device backups by default. Set file protection to `.completeUntilFirstUserAuthentication` so background writes never fail on a locked phone.

### 8.2 Writes
All I/O goes through one `Store` actor. Every write is atomic: encode to `Data`, write to a temp file in the same directory, then `FileManager.replaceItemAt`. The active session is written after every engine event. Encoder uses ISO-8601 dates and sorted keys (stable diffs, testable).

### 8.3 Reads and corruption
On launch, load settings, plans, active session, and all session files into memory. Any file that fails to decode is renamed to `<name>.corrupt-<unixtime>` and treated as absent; the app shows one alert "A data file couldn't be read and was set aside" listing the file names. Never crash. Never delete.

### 8.4 Why this is enough for charts
Every logged set carries `loggedAt`, reps or seconds, weight and the session's unit, and sessions are immutable snapshots. A per-exercise chart over time (D13) is `ExerciseHistory.series` over the in-memory session list. No index, no migration, no extra file.

### 8.5 Export and restore
`{ "exportedAt", "appVersion", "fileVersion": 1, "settings", "plans", "sessions": [...], "activePlanId" }` written to a temp file and offered via ShareLink. `activePlanId` was added in v1.1 and is optional, so a v1 backup still restores — it just leaves the first plan active.

**Restoring** (D31, v1.1): Settings → Import backup reads the file and reports its date, its app version, how many plans and workouts it holds, and how many of each a Merge would actually add. Nothing is written until **Merge** or **Replace all** is chosen. Merge adds only ids not already on disk and leaves the current settings, the active plan and anything edited since the backup untouched; Replace all empties the store first and takes the backup's settings and active plan. A running workout is discarded before either. A file that isn't a backup, or whose `fileVersion` is newer than this app's, is refused with a message before anything is written.

**History as CSV** (D45, v1.3, §6.20): the backup is the app-to-app format; CSV is the app-to-*other*-app one. `HistoryCSV.render` writes one row per logged set in the column order Strong writes and Hevy reads, plus the unit last; `HistoryCSV.parse` reads that, a Strong export and a Hevy export by header name. Import is read-then-describe-then-Import, like a backup, and a workout already in History is never added twice.

### 8.6 Data survival on the free-account 7-day reinstall
Re-running from Xcode over the existing install keeps the container. Deleting the app deletes everything. Settings shows this sentence next to Export.

## 9. Non-functional
- Launch to Home under 1 s with 1000 sessions on disk.
- No network permission needed. No analytics.
- VoiceOver: every control labeled; timer end announced; step card reads as one element ("Bench press, set 2 of 4, target 8 to 12 reps at 60 kilograms").
- Dynamic Type up to accessibility XL without clipping the Log button off screen.
- 44 pt minimum tap targets; the Log set button spans the width above the keyboard.

## 10. Later (explicitly out of v1)
- Live Activity / Dynamic Island rest timer (the Date-based design makes this a drop-in).
- Sync across devices. Apple Watch. Apple Health. (~~Import a backup file~~ — built in v1.1's R5, D31.)
- Estimated 1RM; PR *celebrations* (the marker itself shipped in v1.1's R5, D30). ~~The time-vs-weight-and-reps chart per exercise~~ — built in v1.1's R5 (D13, D30).
- Add an exercise mid-session; per-session notes. (~~Reorder~~ within a workout is D28's Do later; reordering a *plan's* exercises is D29.)
- ~~Editing plans inside the app~~ — built in v1.1's R5 (D29). ~~Still out: adding an exercise to a day, and editing an individual set independently of the others.~~ Both built in v1.3's X3 (D43), as JSON edits.
- ~~Add a pasted single Day to an existing plan (helps when the chatbot truncates a long week).~~ Built in v1.3's X3 (D43): **Add day from JSON** takes a day or a whole plan's days.
- An optional nudge on the done screen after N minutes; `transitionSeconds` between superset members.
- A warning beep before the **rest** timer ends ("get ready"); a "Start set" tap for exact rep-set timing.
- An agenda view for the calendar; tapping a projected day to reschedule. (~~Week view~~ — built in v1.1's R3, D18.)
- Manual rest start (auto-start off), pause, custom sounds.
- Applying progression advice to the weight field automatically; per-exercise `tolerance`.
- A compact text plan format (`Bench 3x10 @60 r90`).
- Localization, iPad, landscape.

## 11. Open questions for the owner
None block v1. Confirm D1, D2 and D10 in §1, and pick the free vs paid Apple route in §2.
`````

---

### FILE: docs/PLAN_FORMAT.md

`````markdown
# Plan format (schemaVersion 1)

This is the JSON the app imports. A chatbot writes it from the prompt in `docs/PROMPT.md`; humans may hand-edit it. The strict shape is in `schema/plan.schema.json`. This document adds the leniency rules (what the app accepts beyond the strict shape) and the validation rules with their codes. Test fixtures for every rule are in `examples/` with expected outcomes in `examples/manifest.json`.

## 1. Canonical example

```json
{
  "schemaVersion": 1,
  "name": "Push Pull Legs",
  "units": "kg",
  "defaultRestSeconds": 90,
  "schedule": "rotation",
  "cycle": ["Push", "rest"],
  "days": [
    {
      "name": "Push",
      "defaultRestSeconds": 120,
      "exercises": [
        { "name": "Barbell Bench Press", "sets": 4, "reps": "6-8", "weight": 80, "restSeconds": 150, "notes": "Pause on chest" },
        { "name": "Incline Dumbbell Press", "sets": [ { "reps": 12, "weight": 24 }, { "reps": 10, "weight": 26 }, { "reps": 8, "weight": 28 } ], "repRange": "8-12", "restSeconds": 90 },
        { "name": "Lateral Raise", "group": "A", "sets": 3, "reps": 15, "repRange": "12-15", "weight": 10, "restSeconds": 60 },
        { "name": "Tricep Pushdown", "group": "A", "sets": 3, "reps": 12, "repRange": "10-12", "weight": 25, "restSeconds": 60, "drops": [ { "weight": 20 }, { "weight": 15 } ] },
        { "name": "Plank", "sets": 3, "durationSeconds": 45, "warningBeep": true, "bodyweight": true, "restSeconds": 45 },
        { "name": "Dead Hang", "sets": 2, "durationSeconds": "max", "bodyweight": true, "restSeconds": 60 }
      ]
    }
  ]
}
```

## 2. Fields

### Plan (top level)
| Field | Type | Required | Notes |
|---|---|---|---|
| `schemaVersion` | int | no | Missing → 1. Greater than the app supports → `E_SCHEMA_VERSION`. |
| `name` | string | no | Missing/blank → "Imported plan <yyyy-MM-dd>" + `W_DEFAULT_NAME`. Max 100 chars (truncate + `W_NAME_TRUNCATED`). |
| `units` | "kg" \| "lb" | no | Case-insensitive; "kgs", "lbs", "pounds", "kilograms" accepted. Missing → user's setting. Other → `E_UNITS_INVALID`. |
| `defaultRestSeconds` | int ≥ 0 | no | Fallback for all days. |
| `schedule` | "rotation" \| "weekday" | no | Missing → inferred: every day has a weekday → weekday; none has → rotation; mixed → `E_SCHEDULE_MIXED`. Present but conflicting with the days → the days win with `W_SCHEDULE_INFERRED`. |
| `days` | array of Day | yes | 1–31 entries. Empty/missing → `E_NO_DAYS`. Over 31 → `E_LIMIT_EXCEEDED`. |
| `cycle` | array of string | no | The repeating block: day names in order with `"rest"` for rest days, e.g. `["Push","Pull","Legs","rest"]`. See §3.10. |

### Day
| Field | Type | Required | Notes |
|---|---|---|---|
| `name` | string | no | Missing/blank → "Day N" + `W_DEFAULT_NAME`. Duplicates within a plan → auto-suffix " (2)", " (3)" + `W_DAY_RENAMED`. Max 100 chars. |
| `weekday` | string | weekday schedule only | Case-insensitive full names or 3-letter abbreviations ("Mon", "monday", "MONDAY"). Other → `E_WEEKDAY_INVALID`. Same weekday twice → `E_WEEKDAY_DUPLICATE`. Present in a rotation plan → ignored + `W_WEEKDAY_IGNORED`. |
| `defaultRestSeconds` | int ≥ 0 | no | Fallback for this day's exercises. |
| `exercises` | array of Exercise | yes | 1–50 entries. Empty/missing → `E_NO_EXERCISES`. Over 50 → `E_LIMIT_EXCEEDED`. |

### Exercise
| Field | Type | Required | Notes |
|---|---|---|---|
| `name` | string | yes | Blank after trim → `E_MISSING_NAME`. Max 100 chars. |
| `group` | string | no | Trimmed, uppercased. Blank → treated as absent. See §3.5. |
| `sets` | int **or** array of Set | no | Missing → 1 set built from the exercise-level fields. Int: 1–50, all sets identical, built from exercise-level `reps`/`durationSeconds`/`weight`/`restSeconds`. Array: 1–50 Set objects; exercise-level `reps`/`durationSeconds`/`weight`/`restSeconds` act as defaults for any set that omits them. 0, negative, non-integer (2.5), or over 50 → `E_SETS_INVALID` / `E_LIMIT_EXCEEDED`. `3.0` is accepted as 3. |
| `reps` | int or string | see Set | Exercise-level default for sets. |
| `durationSeconds` | int or string | see Set | Exercise-level default for sets. `"max"` = open duration (§3.12). |
| `warningBeep` | bool or int | no | Warning beep before a fixed-duration set ends (§3.12). Exercise-level default for sets. |
| `bodyweight` | bool | no | `true` = no weight applies to this exercise (§3.13). |
| `weight` | number or string | no | Exercise-level default for sets. |
| `restSeconds` | int ≥ 0 | no | Rest after each set of this exercise. |
| `repRange` | string or int | no | The rep range the working weight should stay in, e.g. `"8-12"`; drives progression advice (SPEC §6.11). See §3.9 for defaults and leniency. |
| `drops` | array of Drop | no | Drop sets applied to every set of this exercise that doesn't define its own. See §3.11. |
| `notes` | string | no | Max 500 chars (truncate + `W_NOTES_TRUNCATED`). Shown on the step card. |

### Set
| Field | Type | Required | Notes |
|---|---|---|---|
| `reps` | int or string | exactly one of `reps`/`durationSeconds` | See §3.2. |
| `durationSeconds` | int 1–86400 or string | exactly one of `reps`/`durationSeconds` | 0 or negative → `E_DURATION_INVALID`. `"max"`, `"30+"` → open duration (§3.12). |
| `warningBeep` | bool or int | no | Overrides the exercise. Only meaningful on fixed-duration sets (§3.12). |
| `weight` | number ≥ 0 or string | no | See §3.3. Over 10000 → `E_WEIGHT_INVALID`. |
| `restSeconds` | int 0–3600 | no | Overrides the exercise. Negative or over 3600 → `E_REST_INVALID`. Non-integer (90.5) → `E_REST_INVALID`; `90.0` accepted. |
| `drops` | array of Drop | no | Overrides the exercise-level drops for this set. See §3.11. |

### Drop
| Field | Type | Required | Notes |
|---|---|---|---|
| `weight` | number or string | no | Same forms as Set weight. Omit to let the app prefill from the previous step. |
| `reps` | int or string | no | Same forms as Set reps. Missing → AMRAP. |

Any field not listed above, at any level, is ignored with `W_UNKNOWN_FIELD` (path + field name). This keeps old app versions tolerant of newer plans and tolerates chatbot inventions like `tempo` or `rpe`.

`null` for any optional field is the same as absent.

## 3. Leniency rules (Normalize stage)

### 3.1 Top-level shape
- Object with `days` → a plan.
- Object with `exercises` but no `days` → wrapped as a plan with one day. Plan name and day name both come from `name` (or defaults). `W_WRAPPED_SINGLE_DAY`.
- Array whose elements look like days (have `exercises`) → plan with those days. `W_WRAPPED_SINGLE_DAY`.
- Array whose elements look like exercises (have `name` and no `exercises`) → plan with one day. `W_WRAPPED_SINGLE_DAY`.
- Anything else (string, number, object with neither) → `E_NOT_A_PLAN` with a message naming what was found.

### 3.2 `reps` values
Accepted forms (whitespace trimmed; strings case-insensitive):

| Input | Result |
|---|---|
| `10` (int), `10.0`, `"10"` | fixed(10) |
| `"8-12"`, `"8 - 12"`, `"8–12"` (en dash), `"8—12"` (em dash), `"8 to 12"`, `"8/12"` | range(8, 12) |
| `"12-8"` | range(8, 12) + `W_RANGE_SWAPPED` |
| `"8-8"` | fixed(8) |
| `"AMRAP"`, `"amrap"`, `"max"`, `"failure"`, `"to failure"`, `"as many as possible"` | amrap(min: nil) |
| `"10+"`, `"10 +"` | amrap(min: 10) |
| `"8-12 reps"`, `"10 reps"` | trailing word "reps"/"rep" stripped, then as above |
| `0`, negative, `10.5`, `"ten"`, `""`, `"8-"`, `"-12"`, `"8-12-15"`, `true`, `{}` | `E_REPS_INVALID` |
| any number over 1000 (either bound) | `E_REPS_INVALID` |

### 3.3 `weight` values
| Input | Result |
|---|---|
| `60`, `62.5`, `"60"`, `"62,5"` | 60 / 62.5 |
| `"60kg"`, `"60 kg"`, `"135lb"`, `"135 lbs"` | number part; if the unit word disagrees with the plan's units → `W_WEIGHT_UNIT_IGNORED` |
| `"bw"`, `"bodyweight"`, `"body weight"`, `"BW"` | no weight, and the exercise becomes bodyweight (§3.13) |
| `"none"`, `""`, `null` | no weight |
| `"+10kg"`, `"+10"` | 10 (added load) |
| negative, `"heavy"`, `true`, `{}` | `E_WEIGHT_INVALID` |
| over 10000 | `E_WEIGHT_INVALID` |
Weights keep one decimal place (62.5 stays; 62.55 → 62.6 with `W_WEIGHT_ROUNDED`).

### 3.4 Sets shorthand expansion
`"sets": 3` + exercise-level `reps: "8-12"`, `weight: 60`, `restSeconds: 90` → three identical Set Targets. If neither `reps` nor `durationSeconds` is given at the exercise level → `E_TARGET_MISSING` at path `…exercises[i]`. If both → `E_TARGET_CONFLICT`.

`"sets": [ {...}, {...} ]`: each set object takes its own fields; missing `reps`/`durationSeconds`/`weight`/`restSeconds` are filled from the exercise level. A set that ends up with neither target → `E_TARGET_MISSING` at `…sets[k]`; both → `E_TARGET_CONFLICT`. A set with `reps` while the exercise-level has `durationSeconds` (or vice versa): the set's own field wins and the exercise-level one is not applied to that set (no error).

### 3.5 Groups
- Normalize: trim, uppercase. Blank → absent.
- Consecutive exercises with the same group → one block (SPEC §6.2).
- A group tag that appears on only one exercise → treated as ungrouped + `W_GROUP_SINGLE`.
- A group tag that re-appears after a different exercise (A, B, A) → the later run is a separate block, renamed "A2" + `W_GROUP_SPLIT`.
- Members with different set counts → rounds = max, shorter members drop out of later rounds + `W_GROUP_SET_MISMATCH`.

### 3.6 Rest fallback chain
Per set: `set.restSeconds → exercise.restSeconds → day.defaultRestSeconds → plan.defaultRestSeconds → user default (at import)`. Resolved values are stored on every Set Target. Missing everywhere → user default and no warning.

### 3.7 Numbers given as strings
Any integer field accepts a string of digits (`"3"`, `"90"`). Any number field accepts a numeric string with `.` or `,` as the decimal separator. Anything else → the field's `E_*_INVALID`.

### 3.8 Names
Trimmed. Internal whitespace collapsed for matching only (display keeps the original). Unicode allowed. Over 100 chars → truncated + `W_NAME_TRUNCATED`.

### 3.9 `repRange`
- Accepts the range forms of §3.2 (`"8-12"`, `"8 to 12"`, `"8–12"`, `"12-8"` swapped with `W_RANGE_SWAPPED`) and a single whole number `n` (or `"n"`), meaning `n-n`.
- `"AMRAP"`, `"10+"`, words, 0, negatives, fractions, anything over 1000 → `E_REPRANGE_INVALID` at `…exercises[i].repRange`.
- Missing: if the exercise-level `reps` is a range, `repRange` = that range. Otherwise no range (no progression advice for this exercise). Per-set rep ranges are not used for the default.
- Given on an exercise whose exercise-level target is `durationSeconds` → ignored + `W_REPRANGE_IGNORED`.
- Given with an exercise-level fixed `reps` n outside the range → kept + `W_REPRANGE_OUTSIDE` (the range wins for advice; the target stays n).

### 3.10 `cycle` (the repeat block)
- Rotation plans: if present, a non-empty list of 1–31 strings. Each entry is a day name (matched by normalized name, §3.8) or `"rest"` (case-insensitive; `"off"` also accepted). Unknown name → `E_CYCLE_UNKNOWN_DAY` at `cycle[i]`. Not a list, empty, over 31, or a non-string entry → `E_CYCLE_INVALID` at `cycle`. A day that never appears in the cycle → `W_CYCLE_MISSING_DAY` at `cycle` (once). Missing `cycle` → the days in listed order, no rest days.
- Weekday plans: the cycle is always derived as Monday…Sunday from the days' weekdays, with rest for unlisted weekdays. An explicit `cycle` → `W_CYCLE_IGNORED`.

### 3.11 `drops`
- A list of 1–5 Drop objects; each Drop is an object with optional `weight` and `reps`. Empty list, over 5, non-list, or non-object entry → `E_DROPS_INVALID` at the field's path. Weight/reps values follow §3.2 / §3.3 and report `E_WEIGHT_INVALID` / `E_REPS_INVALID` at `…drops[j].weight` / `…drops[j].reps`.
- Exercise-level `drops` apply to every set; a set's own `drops` replace them for that set (`"drops": []` at set level is `E_DROPS_INVALID`, not "no drops").
- Drops on a timed set → dropped with `W_DROPS_IGNORED`.
- Unknown fields inside a Drop → `W_UNKNOWN_FIELD`.

### 3.12 Timed sets: fixed, open, and beeps
- `durationSeconds` integer (or numeric string) 1–86400 → **fixed duration**: countdown, alert at the end.
- `durationSeconds` `"max"`, `"open"`, `"AMSAP"`, `"as long as possible"`, `"to failure"` (case-insensitive) → **open duration**: a stopwatch the user stops; the seconds held are logged. `"30+"` → open duration with a 30 s minimum shown as the target.
- Any other string, 0, negatives, fractions, over 86400 → `E_DURATION_INVALID`.
- Every fixed-duration set ends with a **final beep**. Before it, an optional **warning beep**, controlled by `warningBeep`:
  - missing or `true` → 10 % of the duration before the end, rounded half up to whole seconds, minimum 1 s; no warning at all for durations under 10 s.
  - `false` → no warning beep.
  - a whole number `n` (1–86399) → `n` seconds before the end. `n ≥ duration` → dropped with `W_WARNING_BEEP_IGNORED`.
  - anything else (`0`, negatives, fractions, strings) → `E_WARNING_BEEP_INVALID`.
  - given explicitly on a rep-based or open-duration set (or exercise) → dropped with `W_WARNING_BEEP_IGNORED`. A missing field on those never warns.
  The resolved offset is stored per set as `warningBeepSeconds` (nil = off).
- Open-duration sets with a minimum (`"30+"`) beep once when the minimum is reached. Open sets without a minimum never beep.

### 3.13 Bodyweight exercises
- `"bodyweight": true` on an exercise → the app never asks for a weight on it. Non-boolean → `E_BODYWEIGHT_INVALID`.
- A `weight` string of `"bw"`, `"bodyweight"`, `"body weight"` at exercise or set level also sets the flag (so chatbots that write `"weight": "bodyweight"` still work).
- A numeric `weight` (exercise, set, or drop level) on a bodyweight exercise → dropped with `W_BODYWEIGHT_WEIGHT_IGNORED`. For weighted calisthenics (dips +10 kg) don't set the flag; give the added load as the weight.
- An exercise with neither a weight nor the flag simply shows an empty weight field.

## 4. Validation rules (Validate stage) — full code list

Errors block import. Warnings are shown in Preview and saved on the plan. `path` uses JSON-pointer-like notation: `days[1].exercises[3].sets[0].reps`.

| Code | Severity | When |
|---|---|---|
| `E_EMPTY` | error | Nothing to parse after extraction |
| `E_TOO_LARGE` | error | Input over 1,048,576 bytes |
| `E_PROMPT_PASTED` | error | Input contains the prompt marker and no fenced code block (checked before anything else except size/empty) |
| `E_MULTIPLE_OBJECTS` | error | More than one top-level JSON value |
| `E_NOT_JSON` | error | No `{` or `[` found in the text, or strict decode failed (message includes the decoder error and, when available, line/column). A bare `null`, number, or string at top level lands here too |
| `E_NOT_A_PLAN` | error | JSON parsed but no recognizable shape (§3.1) |
| `E_SCHEMA_VERSION` | error | `schemaVersion` > supported |
| `E_UNITS_INVALID` | error | `units` not kg/lb |
| `E_SCHEDULE_MIXED` | error | Some days have weekdays, some don't, and no explicit schedule |
| `E_NO_DAYS` | error | `days` missing or empty |
| `E_NO_EXERCISES` | error | A day has no exercises |
| `E_MISSING_NAME` | error | Exercise name missing or blank |
| `E_SETS_INVALID` | error | `sets` is 0, negative, non-integer, or not int/array |
| `E_REPS_INVALID` | error | §3.2 rejected forms |
| `E_REPRANGE_INVALID` | error | §3.9 rejected forms |
| `E_DROPS_INVALID` | error | §3.11 rejected forms |
| `E_CYCLE_INVALID` | error | §3.10: not a list, empty, over 31, non-string entry |
| `E_CYCLE_UNKNOWN_DAY` | error | §3.10: cycle entry names no day |
| `E_DURATION_INVALID` | error | `durationSeconds` ≤ 0, > 86400, non-integer, or an unrecognized string (§3.12) |
| `E_WARNING_BEEP_INVALID` | error | `warningBeep` not a boolean or a whole number 1–86399 |
| `E_BODYWEIGHT_INVALID` | error | `bodyweight` not a boolean |
| `E_TARGET_MISSING` | error | A set has neither reps nor duration |
| `E_TARGET_CONFLICT` | error | A set has both reps and duration |
| `E_WEIGHT_INVALID` | error | §3.3 rejected forms |
| `E_REST_INVALID` | error | Rest negative, > 3600, or non-integer (any level) |
| `E_WEEKDAY_INVALID` | error | Unrecognized weekday string |
| `E_WEEKDAY_DUPLICATE` | error | Two days share a weekday |
| `E_WEEKDAY_MISSING` | error | Explicit `schedule: "weekday"` and a day lacks `weekday` |
| `E_LIMIT_EXCEEDED` | error | > 31 days, > 50 exercises in a day, > 50 sets in an exercise |
| `W_SURROUNDING_TEXT` | warning | Prose/fences were stripped |
| `W_CURLY_QUOTES_FIXED` | warning | Decode succeeded only after replacing curly quotes |
| `W_WRAPPED_SINGLE_DAY` | warning | Top level was a day or array and was wrapped |
| `W_DEFAULT_NAME` | warning | Plan or day name defaulted |
| `W_NAME_TRUNCATED` | warning | Name over 100 chars |
| `W_NOTES_TRUNCATED` | warning | Notes over 500 chars |
| `W_DAY_RENAMED` | warning | Duplicate day name suffixed |
| `W_UNKNOWN_FIELD` | warning | Field ignored |
| `W_RANGE_SWAPPED` | warning | `"12-8"` read as 8–12 (reps or repRange) |
| `W_REPRANGE_IGNORED` | warning | `repRange` on a timed exercise |
| `W_REPRANGE_OUTSIDE` | warning | Fixed `reps` target outside `repRange` |
| `W_DROPS_IGNORED` | warning | `drops` on a timed set |
| `W_WARNING_BEEP_IGNORED` | warning | `warningBeep` on a rep-based or open-duration set, or not before the end |
| `W_BODYWEIGHT_WEIGHT_IGNORED` | warning | A weight given on a bodyweight exercise |
| `W_CYCLE_MISSING_DAY` | warning | A day never appears in the cycle |
| `W_CYCLE_IGNORED` | warning | `cycle` given on a weekday plan |
| `W_WEIGHT_UNIT_IGNORED` | warning | Weight string carried a unit that differs from the plan's |
| `W_WEIGHT_ROUNDED` | warning | Weight rounded to one decimal |
| `W_GROUP_SINGLE` | warning | Group with a single member |
| `W_GROUP_SPLIT` | warning | Non-consecutive reuse of a group tag |
| `W_GROUP_SET_MISMATCH` | warning | Group members have different set counts |
| `W_WEEKDAY_IGNORED` | warning | Weekday given on a rotation plan |
| `W_SCHEDULE_INFERRED` | warning | Explicit schedule contradicted the days |

Every error message is a full sentence a non-programmer can act on, and names the accepted forms. Example: `days[0].exercises[2].reps: "ten" is not a valid reps value. Use a whole number, a range like "8-12", "AMRAP", or "10+".`

## 5. Things the format deliberately does not have
- Rest days as Day entries (rest days live in `cycle` for rotation plans, and are the unlisted weekdays for weekday plans).
- Tempo, RPE, RIR, equipment fields (put them in `notes`).
- Warm-up flags (list warm-ups as their own exercises if wanted).
- Per-set notes.
`````

---

### FILE: docs/PROMPT.md

`````markdown
# Chatbot prompts

The app copies these texts to the clipboard. Placeholders in `{{ }}` are filled from Settings at copy time. The line `JIMMSBRO-PLAN-PROMPT-V1` is the **prompt marker**. Rule: if the pasted text contains the marker and **no fenced code block** (three backticks), the app reports `E_PROMPT_PASTED` ("That's the prompt. Paste the chatbot's JSON reply instead."). A chatbot reply always has a fence, and the prompt itself must never contain three backticks, which is why the prompts below say "code block tagged json" instead of writing the fence. The prompt does contain an example JSON object, so a plain "marker and no JSON" check would import the example by mistake.

## 1. Plan prompt (Import → Copy prompt)

```
JIMMSBRO-PLAN-PROMPT-V1
Convert my workout plan to JSON for a workout-tracking app. Reply with ONE complete JSON object in a single code block tagged json, with no other text.

FORMAT (schemaVersion 1):
{
  "schemaVersion": 1,
  "name": "Push Pull Legs",
  "units": "{{units}}",
  "defaultRestSeconds": {{defaultRest}},
  "schedule": "rotation",
  "cycle": ["Push", "rest"],
  "days": [
    {
      "name": "Push",
      "exercises": [
        { "name": "Barbell Bench Press", "sets": 4, "reps": "6-8", "weight": 80, "restSeconds": 150, "notes": "Pause on chest" },
        { "name": "Incline Dumbbell Press", "sets": [ { "reps": 12, "weight": 24 }, { "reps": 10, "weight": 26 }, { "reps": 8, "weight": 28 } ], "repRange": "8-12", "restSeconds": 90 },
        { "name": "Lateral Raise", "group": "A", "sets": 3, "reps": 15, "repRange": "12-15", "weight": 10, "restSeconds": 60 },
        { "name": "Tricep Pushdown", "group": "A", "sets": 3, "reps": 12, "repRange": "10-12", "weight": 25, "restSeconds": 60, "drops": [ { "weight": 20 }, { "weight": 15 } ] },
        { "name": "Plank", "sets": 3, "durationSeconds": 45, "warningBeep": true, "bodyweight": true, "restSeconds": 45 },
        { "name": "Dead Hang", "sets": 2, "durationSeconds": "max", "bodyweight": true, "restSeconds": 60 }
      ]
    }
  ]
}

RULES
- days: training days in order; one workout = one day. Do not list rest days as days.
- schedule: rotation = repeat days in order. Use weekday only for a fixed weekly schedule; give every day a weekday (monday…sunday) and omit cycle.
- cycle: rotation's full repeating block, using day names and "rest", including rest days. Example: ["Push","Pull","Legs","Push","Pull","Legs","rest"]. This drives the calendar.
- sets: a count for identical sets; otherwise an array of set objects. Exercise-level fields default each set. Prefer the count form.
- Each set needs exactly one of reps or durationSeconds. Duration is seconds for holds/cardio; "max" = stopwatch until stopped, "30+" = at least 30 seconds.
- Fixed durations beep at the end. warningBeep: true or omitted = warning at 10% remaining, false = off, or a number of seconds before the end (e.g. 5). Fixed durations only.
- bodyweight: true when no weight applies (push-ups, planks, hangs); omit weight. For weighted calisthenics use added load as weight and omit the flag.
- reps: whole number, "8-12", "AMRAP" (as many as possible), or "10+" (at least 10). Nothing else.
- repRange: give every rep exercise a working range for weight progression, e.g. "8-12". Omit if reps already is a range. For fixed targets choose a range containing it (10 → "8-12", 5 → "4-6"). No repRange for timed exercises.
- weight: number in {{units}}, without unit text. Omit for bodyweight or unspecified weight.
- restSeconds: always include whole seconds. If unspecified: 120-180 for heavy compounds, 60-90 for isolation, 30-60 for circuits/core.
- drops: list on exercise or individual set, e.g. [{"weight":20},{"weight":15}], done immediately after the main set with no rest. Reps default to AMRAP.
- Supersets/circuits: same group letter, consecutive exercises, equal set counts. Rest after each round.
- Names: specific and consistent ("Barbell Back Squat", not "Squats"); reuse spelling across days for history matching.
- Keep execution order. If I supply exercises, use exactly those: no additions, removals, or reordering. If I request a plan, design a sensible one.
- Put tempo, RPE, cues and "each side" in notes.
- Return ALL JSON, never abbreviate with "...".

My plan:
```

The user types or pastes their description after "My plan:".

Rendered length: 3,510 characters with kg and rest 90. Keep it under 4,000. Chat apps may handle longer pastes differently; see `COPY_PASTE_NOTES.md`. 

## 2. Fix-it prompt (Import error → Copy fix-it prompt)

```
JIMMSBRO-PLAN-PROMPT-V1
The workout app rejected the JSON with these errors:
{{errorLines}}

Fix them and reply with the complete corrected JSON only, in one code block tagged json, keeping the same format and rules as before. Do not change anything else.
```

`{{errorLines}}` is one line per error: `- <path>: <message>`. Include at most 20 errors; if more, add `- …and N more`. Include the original decoder message for `E_NOT_JSON` (e.g. "Unexpected end of file" tells the chatbot its output was cut off).

## 3. Progression prompt (Plan → Progression → Copy prompt)

The line `JIMMSBRO-PROGRESSION-PROMPT-V1` is this prompt's marker, with the same rule as §1: the marker and no fenced code block means the prompt itself was pasted (`E_PROMPT_PASTED`). `{{weeks}}` is the period the owner picked (4, 6, 8 or 12), `{{units}}` and `{{increment}}` come from the plan and Settings, `{{plan}}` is the plan as a compact listing — one line per exercise, not its JSON — and `{{history}}` is empty or a block headed `MY HISTORY (most recent last)` with one line per exercise: its last sessions (up to six, within 90 days) and the advice the most recent one earned. The history is shortened first, never the plan, to stay under 9,000 characters (`COPY_PASTE_NOTES.md`).

```
JIMMSBRO-PROGRESSION-PROMPT-V1
Plan my progression for the next {{weeks}} weeks for the workout plan below. Reply with ONE complete JSON object in a single code block tagged json, with no other text.

FORMAT:
{
  "weeks": {{weeks}},
  "exercises": [
    { "day": "Push", "name": "Barbell Bench Press", "weeks": [ { "weight": 80, "reps": "6-8" }, { "weight": 82.5, "reps": "6-8" }, {} ] }
  ]
}

RULES
- One entry per exercise in the plan, with its day and its exact name as written below. Leave an exercise out only if nothing about it should change.
- weeks: exactly {{weeks}} objects per exercise, week 1 first. An object gives the weight (in {{units}}, no unit text) and/or the reps for every set that week; {} means no change from the plan that week.
- reps: a whole number, a range like "8-12", "AMRAP", or "10+". For timed exercises give durationSeconds instead of reps. For bodyweight exercises give reps only.
- To vary the sets within a week, give "sets": [ { "weight": 60, "reps": 10 }, { "weight": 65, "reps": 8 } ] instead of weight and reps.
- Every weight must be loadable: a multiple of {{increment}} {{units}}.
- Progress conservatively from the plan and from my history below. If the period is 6 weeks or more, make one week a deload.
- Return ALL JSON, never abbreviate with "...".

MY PLAN
{{plan}}{{history}}
```

The reply format is `docs/PROGRESSION_FORMAT.md`.

## 4. Behavior notes for the app
- All three prompts are plain strings in `Core/Prompts.swift` with a `render(settings:)` / `render(errors:)` function, unit-tested (placeholders substituted, marker present, length bound).
- After **Copy prompt**, show a toast for 3 s. Don't navigate away.
- The prompt marker line must never appear in the JSON example, or a chatbot might echo it inside the plan.
- The example JSON inside the plan prompt is also exposed as `Prompts.exampleJSON` so a test can import it (TEST_CASES M4). `examples/valid/prompt-example.txt` is that same text; `examples/invalid/prompt-pasted-full.txt` preserves the original full prompt as an unchanged regression fixture; the shortened prompt has its own automated marker test.
- Never put three backticks anywhere in either prompt (see the marker rule above).
`````

---

### FILE: docs/PROGRESSION_FORMAT.md

`````markdown
# Jimm's Bro+ — the progression reply (D44, v1.3)

What the chatbot sends back to the prompt in `PROMPT.md` §3, and how the app reads it. It is
deliberately small: the plan's structure never changes, a progression is *attached* to the
plan you have, and only the week-by-week targets travel.

## 1. Canonical example

```json
{
  "weeks": 4,
  "exercises": [
    { "day": "Push", "name": "Barbell Bench Press",
      "weeks": [ { "weight": 80, "reps": "6-8" }, { "weight": 82.5 }, {}, { "weight": 85, "reps": "5-7" } ] },
    { "day": "Push", "name": "Plank",
      "weeks": [ { "durationSeconds": 45 }, { "durationSeconds": 50 }, {}, { "durationSeconds": 60 } ] },
    { "day": "Pull", "name": "Barbell Row",
      "weeks": [ { "sets": [ { "weight": 60, "reps": 10 }, { "weight": 65, "reps": 8 } ] }, {}, {}, {} ] }
  ]
}
```

## 2. Fields

| Field | Type | Required | Notes |
|---|---|---|---|
| `weeks` | int 1–52 | no | The period. Missing → the longest entry's length. Anything else → `E_PROGRESSION_WEEKS_INVALID`. |
| `exercises` | array of Entry | yes | Empty or missing → `E_PROGRESSION_INVALID`. A bare top-level array is read as this list. The whole object may also sit under a `progression` key. |

### Entry
| Field | Type | Required | Notes |
|---|---|---|---|
| `day` | string | no | Matched to a plan day by name (SPEC §6.9). Missing → every day that has the exercise gets the same weeks (`W_PROGRESSION_DAY_ASSUMED` when that is more than one). |
| `name` | string | yes | Matched to a plan exercise by name. Blank or missing → `E_PROGRESSION_EXERCISE_INVALID`. Not in the plan (on that day) → `W_PROGRESSION_UNMATCHED`, the entry is left out. |
| `weeks` | array of Week | yes | Week 1 first. Missing → `E_PROGRESSION_WEEKS_INVALID`. Longer than `weeks` → truncated (`W_PROGRESSION_LONG`); shorter → `W_PROGRESSION_SHORT`, and the plan's own targets apply after the last one. |

### Week
`null` or `{}` is "no change from the plan that week".

| Field | Type | Notes |
|---|---|---|
| `weight` | number or string | For every set that week, in the plan's units. `"62.5 kg"` is accepted; `"bw"` / `"bodyweight"` / `"none"` mean no weight. Snapped to the smallest loadable change (D35, `W_PROGRESSION_ROUNDED`). Ignored on a bodyweight exercise (`W_PROGRESSION_WEIGHT_IGNORED`). Over 10000 or negative → `E_WEIGHT_INVALID`. |
| `reps` | int or string | For every set that week: `8`, `"8-12"`, `"8 to 12"`, `"AMRAP"`, `"10+"`, `"max"`. A range also becomes the rep range advice judges by. Else `E_REPS_INVALID`. |
| `durationSeconds` | int or string | For timed exercises: seconds, `"max"`, `"30+"`. With `reps` as well → `E_TARGET_CONFLICT`. |
| `sets` | array of { `weight`, `reps` / `durationSeconds` } | Per-set values instead of `weight`/`reps`; set *n* of the plan's exercise takes entry *n*; extra entries are ignored. 1–50 objects, else `E_SETS_INVALID`. |

Any other field, at any level, is ignored with `W_UNKNOWN_FIELD`. Anything that is not an object where a Week is expected → `E_PROGRESSION_WEEK_INVALID`; where an Entry is expected → `E_PROGRESSION_EXERCISE_INVALID`. A reply in which no entry matched the plan → `E_PROGRESSION_EMPTY`.

## 3. Leniency

The reply goes through the same extract and decode stages as a plan (PLAN_FORMAT §3): a fenced block with prose around it, curly quotes, numbers as strings. The marker rule applies to *this* prompt's marker.

## 4. How the app uses it

- **Week 1 starts the day the progression is saved** (`Progression.startDate`, midnight local), and weeks are calendar weeks from there. On the day after the last week the plan's own targets and advice are back, and Home offers to plan the next one.
- **Starting a day** in one of its weeks writes that week's targets into the session's snapshot (D7): every set's weight and/or work from the entry, per set when `sets` was given. An exercise, week or set the progression says nothing about keeps the plan's own target. The exercise and the session record the week.
- **Prefill** shows the week's weight and reps even when last time was different (SPEC §6.5, rule 0); the suggestion chip's reason reads "Week 3 of 8 of your progression".
- **Plan edits** (D29, D43) keep the progression; entries match by name, so a renamed exercise simply stops matching. **Edit JSON** / Replace of the whole plan drops it — that is a new plan.

## 5. Codes

Errors: `E_PROMPT_PASTED`, `E_NOT_JSON`, `E_MULTIPLE_OBJECTS`, `E_EMPTY`, `E_TOO_LARGE` (as for a plan); `E_PROGRESSION_INVALID`, `E_PROGRESSION_WEEKS_INVALID`, `E_PROGRESSION_EXERCISE_INVALID`, `E_PROGRESSION_WEEK_INVALID`, `E_PROGRESSION_EMPTY`, `E_REPS_INVALID`, `E_DURATION_INVALID`, `E_TARGET_CONFLICT`, `E_WEIGHT_INVALID`, `E_SETS_INVALID`.

Warnings, **material** (shown on the review): `W_PROGRESSION_UNMATCHED`, `W_PROGRESSION_SHORT`, `W_PROGRESSION_WEIGHT_IGNORED`. **Cleanup** (behind Details): `W_PROGRESSION_ROUNDED`, `W_PROGRESSION_LONG`, `W_PROGRESSION_DAY_ASSUMED`, `W_UNKNOWN_FIELD`, `W_SURROUNDING_TEXT`, `W_CURLY_QUOTES_FIXED`.
`````

---

### FILE: docs/TEST_CASES.md

`````markdown
# Test cases

Type: **unit** = automated test on Core types (required, must pass). **ui** = SwiftUI/XCUITest or simulator check. **manual** = physical-device checklist in BUILD_PLAN.
Fixtures referenced as `valid/x.json` / `invalid/x.txt` live in `examples/`; `examples/manifest.json` lists the expected codes for each. Tests for A–D should iterate the manifest, plus the specific assertions below. `tools/reference_import.py` passes the whole manifest and is the oracle for any disputed case.

## A. Import — Extract stage
| ID | Type | Case | Expected |
|---|---|---|---|
| A1 | unit | Bare JSON object | Passed through unchanged, no warnings |
| A2 | unit | ```` ```json { … } ``` ```` fence | Inner JSON; `W_SURROUNDING_TEXT` not raised (fence only) |
| A3 | unit | Prose before and after a fence ("Here's your plan: … Let me know!") | Inner JSON; `W_SURROUNDING_TEXT` |
| A4 | unit | Fence tagged ```` ```javascript ```` or untagged ```` ``` ```` | Inner JSON |
| A5 | unit | No fence, prose then `{…}` then prose | From first `{` to its matching `}` (string-aware scan); `W_SURROUNDING_TEXT` |
| A6 | unit | Two fences, each a plan | `E_MULTIPLE_OBJECTS` |
| A7 | unit | Two top-level objects with no fence `{…} {…}` | `E_MULTIPLE_OBJECTS` |
| A8 | unit | Empty string / whitespace only / only newlines | `E_EMPTY` |
| A9 | unit | Leading BOM `\u{FEFF}` and zero-width spaces `\u{200B}` | Stripped; parses |
| A10 | unit | Input of 1,048,577 bytes | `E_TOO_LARGE` before any parsing |
| A11 | unit | The plan prompt itself pasted (`invalid/prompt-pasted-full.txt`: marker, an example JSON object, no fence) | `E_PROMPT_PASTED`, not an import of the example |
| A11b | unit | Marker with plain text and no braces (`invalid/prompt-pasted.txt`) | `E_PROMPT_PASTED` |
| A12 | unit | Marker present AND a valid JSON block | Imports normally (marker in prose ignored) |
| A13 | unit | Top-level array `[ … ]` | Extracted the same way as an object |
| A14 | unit | Braces inside string values (`"notes": "hold {tight}"`) | Matching uses a JSON-aware scan, not naive first/last brace; parses |

## B. Import — Decode stage
| ID | Type | Case | Expected |
|---|---|---|---|
| B1 | unit | Trailing comma `{"days": [],}` | `E_NOT_JSON`; message contains the decoder's description |
| B2 | unit | Comments `// …` in JSON | `E_NOT_JSON` |
| B3 | unit | Curly quotes `“name”: “Push”` | Retry succeeds; `W_CURLY_QUOTES_FIXED` |
| B4 | unit | Curly quotes inside a string value only (`"notes": "“slow”"`) | Strict decode succeeds first try; no warning; value preserved |
| B5 | unit | Truncated JSON (cut mid-array) | `E_NOT_JSON`; message mentions unexpected end so the fix-it prompt is useful |
| B6 | unit | Single-quoted strings `{'days': []}` | `E_NOT_JSON` |
| B7 | unit | `NaN` / `Infinity` literals | `E_NOT_JSON` |
| B8 | unit | Deeply nested unrelated JSON (e.g. a package.json) | Decodes as raw, then `E_NOT_A_PLAN` in Normalize |
| B9 | unit | `null`, a number, or a string at top level (no `{`/`[`) | `E_NOT_JSON` ("No JSON found") |

## C. Import — Normalize stage
### C.1 Top-level shape
| ID | Type | Case | Expected |
|---|---|---|---|
| C1 | unit | Object with `days` | Plan |
| C2 | unit | Object with `exercises`, no `days` (`valid/single-day-bare.json`) | One-day plan; day name = plan name; `W_WRAPPED_SINGLE_DAY` |
| C3 | unit | Array of day objects (`valid/array-of-days.json`) | Plan with those days; `W_WRAPPED_SINGLE_DAY` |
| C4 | unit | Array of exercise objects | One-day plan; `W_WRAPPED_SINGLE_DAY` |
| C5 | unit | Object with neither `days` nor `exercises` | `E_NOT_A_PLAN` |
| C6 | unit | `"days": {}` (object not array) | `E_NO_DAYS` |
| C7 | unit | Missing plan name / `""` / `"   "` | "Imported plan <date>"; `W_DEFAULT_NAME` |
| C8 | unit | `schemaVersion` missing | Treated as 1 |
| C9 | unit | `schemaVersion: 2` | `E_SCHEMA_VERSION` |
| C10 | unit | `schemaVersion: "1"` | Accepted as 1 |
| C11 | unit | `units` "KG", "kgs", "lbs", "Pounds", "kilograms" | kg / kg / lb / lb / kg |
| C12 | unit | `units: "stone"` | `E_UNITS_INVALID` |
| C13 | unit | `units` missing, settings = lb | Plan units lb |

### C.2 Schedule and weekdays
| ID | Type | Case | Expected |
|---|---|---|---|
| C14 | unit | No `schedule`, all days have weekdays | schedule = weekday, no warning |
| C15 | unit | No `schedule`, no weekdays | rotation |
| C16 | unit | No `schedule`, some weekdays | `E_SCHEDULE_MIXED` |
| C17 | unit | `schedule: "weekday"`, one day lacks weekday | `E_WEEKDAY_MISSING` at that day's path |
| C18 | unit | `schedule: "rotation"`, days have weekdays | rotation; `W_WEEKDAY_IGNORED` per day |
| C19 | unit | `schedule: "Weekly"` (unknown value) | Inferred from days + `W_SCHEDULE_INFERRED` |
| C20 | unit | Weekday "Mon", "monday", "MONDAY", "  tue " | monday, monday, monday, tuesday |
| C21 | unit | Weekday "Funday", "M", "Mondays" | `E_WEEKDAY_INVALID` |
| C22 | unit | Two days both "friday" | `E_WEEKDAY_DUPLICATE` on the second |

### C.3 Days and names
| ID | Type | Case | Expected |
|---|---|---|---|
| C23 | unit | Day without name | "Day 1", "Day 2"… by position; `W_DEFAULT_NAME` |
| C24 | unit | Two days named "Push" and "push " (matched after trim + case-fold) | Second becomes "push (2)" (trimmed original + suffix); `W_DAY_RENAMED` |
| C25 | unit | Three days "A", "A", "A" | "A", "A (2)", "A (3)" |
| C26 | unit | Name 150 chars | Truncated to 100; `W_NAME_TRUNCATED` |
| C27 | unit | Name with emoji and CJK "🏋️ 胸" | Preserved |
| C28 | unit | Exercise name missing / `""` / `"  "` / `null` | `E_MISSING_NAME` at `days[i].exercises[j].name` |
| C29 | unit | Exercise name `"  Bench   Press "` | Display "Bench   Press" trimmed; normalized "bench press" |
| C30 | unit | Notes 600 chars | Truncated to 500; `W_NOTES_TRUNCATED` |

### C.4 Sets, reps, duration
| ID | Type | Case | Expected |
|---|---|---|---|
| C31 | unit | `sets: 3, reps: 10` | 3 SetTargets fixed(10) |
| C32 | unit | `sets: 3.0` | 3 sets |
| C33 | unit | `sets: "4"` | 4 sets |
| C34 | unit | `sets: 0` / `-1` / `2.5` / `true` / `"three"` | `E_SETS_INVALID` |
| C35 | unit | `sets: 51` | `E_LIMIT_EXCEEDED` |
| C36 | unit | `sets` missing, `reps: 10` | 1 set |
| C37 | unit | `sets` missing, no `reps`, no `durationSeconds` | `E_TARGET_MISSING` at exercise path |
| C38 | unit | `sets: 3` with both `reps` and `durationSeconds` at exercise level | `E_TARGET_CONFLICT` |
| C39 | unit | `sets: []` | `E_SETS_INVALID` |
| C40 | unit | `sets: [{reps:12},{reps:10},{reps:8}]`, exercise-level `weight: 60` | All three sets weight 60 |
| C41 | unit | `sets: [{reps:12, weight: 50},{reps:10}]`, exercise-level `weight: 60` | 50 then 60 |
| C42 | unit | `sets: [{weight: 60}]`, exercise-level `reps: 10` | fixed(10) @ 60 |
| C43 | unit | `sets: [{}]`, no exercise-level target | `E_TARGET_MISSING` at `…sets[0]` |
| C44 | unit | `sets: [{reps: 10, durationSeconds: 30}]` | `E_TARGET_CONFLICT` at `…sets[0]` |
| C45 | unit | `sets: [{durationSeconds: 30}]`, exercise-level `reps: 10` | Set is duration(30); exercise reps not applied; no error |
| C46 | unit | `sets: [{reps: 10}, {restSeconds: 120}]`, exercise-level `reps: 8`, `restSeconds: 60` | set0 fixed(10) rest 60; set1 fixed(8) rest 120 |
| C47 | unit | reps `10`, `10.0`, `"10"`, `" 10 "` | fixed(10) |
| C48 | unit | reps `"8-12"`, `"8 - 12"`, `"8–12"`, `"8—12"`, `"8 to 12"`, `"8/12"` | range(8,12) |
| C49 | unit | reps `"12-8"` | range(8,12) + `W_RANGE_SWAPPED` |
| C50 | unit | reps `"8-8"` | fixed(8) |
| C51 | unit | reps `"AMRAP"`, `"amrap"`, `"Max"`, `"failure"`, `"to failure"`, `"as many as possible"` | amrap(nil) |
| C52 | unit | reps `"10+"`, `"10 +"` | amrap(min 10) |
| C53 | unit | reps `"8-12 reps"`, `"10 reps"`, `"1 rep"` | range(8,12), fixed(10), fixed(1) |
| C54 | unit | reps `0`, `-5`, `10.5`, `"ten"`, `""`, `"8-"`, `"-12"`, `"8-12-15"`, `true`, `{}`, `[]` | `E_REPS_INVALID` each, message lists accepted forms |
| C55 | unit | reps `1001`, `"5-2000"` | `E_REPS_INVALID` |
| C56 | unit | reps `1000` | fixed(1000) (boundary accepted) |
| C57 | unit | `durationSeconds: 45`, `"45"`, `45.0` | duration(45) |
| C58 | unit | `durationSeconds: 0`, `-1`, `30.5`, `"30s"`, `86401` | `E_DURATION_INVALID` |
| C59 | unit | `durationSeconds: 86400` | Accepted |

### C.5 Weight
| ID | Type | Case | Expected |
|---|---|---|---|
| C60 | unit | `60`, `62.5`, `"60"`, `"62,5"`, `"62.5"` | 60, 62.5, 60, 62.5, 62.5 |
| C61 | unit | `"60kg"`, `"60 kg"`, `"60 KG"` on a kg plan | 60, no warning |
| C62 | unit | `"135lb"`, `"135 lbs"` on a kg plan | 135 + `W_WEIGHT_UNIT_IGNORED` |
| C63 | unit | `"bw"`, `"BW"`, `"bodyweight"`, `"body weight"` | no weight, exercise `bodyweight = true`, no warning |
| C63b | unit | `"none"`, `""`, `null` | no weight, flag unchanged, no warning |
| C64 | unit | `"+10kg"`, `"+10"` | 10 |
| C65 | unit | `-5`, `"heavy"`, `true`, `{}` | `E_WEIGHT_INVALID` |
| C66 | unit | `10001` | `E_WEIGHT_INVALID`; `10000` accepted |
| C67 | unit | `62.55` | 62.6 + `W_WEIGHT_ROUNDED`; `62.5` unchanged, no warning |
| C68 | unit | `0` | weight 0 (kept, not treated as absent) |

### C.6 Rest
| ID | Type | Case | Expected |
|---|---|---|---|
| C69 | unit | Only plan `defaultRestSeconds: 100` | Every set rest 100 |
| C70 | unit | Plan 100, day 80 | 80 for that day's sets; other days 100 |
| C71 | unit | Plan 100, day 80, exercise 70 | 70 |
| C72 | unit | Plan 100, day 80, exercise 70, set 60 | 60 for that set, 70 for the others |
| C73 | unit | Nothing anywhere, settings default 90 | 90 |
| C74 | unit | `restSeconds: 0` | 0 (no rest), not treated as missing |
| C75 | unit | `restSeconds: -1`, `3601`, `90.5`, `"1m30"` | `E_REST_INVALID` at the right path |
| C76 | unit | `restSeconds: "90"`, `90.0`, `3600` | 90, 90, 3600 |

### C.7 Groups
| ID | Type | Case | Expected |
|---|---|---|---|
| C77 | unit | `group: "a"` and `"A"` on consecutive exercises | Same group "A" |
| C78 | unit | `group: " "` | Absent |
| C79 | unit | One exercise with group "A", neighbors ungrouped | Ungrouped + `W_GROUP_SINGLE` |
| C80 | unit | A, A, B, A | Blocks: [A,A], [B], [A2]; `W_GROUP_SPLIT`; the lone A2 also gets `W_GROUP_SINGLE` |
| C81 | unit | A (3 sets), A (2 sets) | `W_GROUP_SET_MISMATCH`; block rounds = 3 |
| C82 | unit | `group: 1` (number) | Accepted as "1" |

### C.8 Unknown fields and nulls
| ID | Type | Case | Expected |
|---|---|---|---|
| C83 | unit | `"tempo": "3010"`, `"rpe": 8` on an exercise | Ignored; `W_UNKNOWN_FIELD` ×2 with path and field name |
| C84 | unit | Unknown top-level field `"author"` | `W_UNKNOWN_FIELD` |
| C85 | unit | `"weight": null`, `"notes": null`, `"group": null` | As absent, no warning |
| C86 | unit | `"days": null` | `E_NO_DAYS` |

### C.9 repRange (`valid/reprange-cases.json`)
| ID | Type | Case | Expected |
|---|---|---|---|
| C87 | unit | `reps: 10, repRange: "8-12"` | RepRange(8,12) |
| C88 | unit | `reps: "8-12"`, no repRange | RepRange(8,12) inherited from reps |
| C89 | unit | `reps: 10`, no repRange | nil (no advice for this exercise) |
| C90 | unit | `reps: 15, repRange: "8-12"` | RepRange(8,12) + `W_REPRANGE_OUTSIDE`; target stays 15 |
| C91 | unit | `durationSeconds: 30, repRange: "8-12"` | nil + `W_REPRANGE_IGNORED` |
| C92 | unit | `repRange: 10` (int) or `"10"` | RepRange(10,10) |
| C93 | unit | `repRange: "12-8"` | RepRange(8,12) + `W_RANGE_SWAPPED` at the repRange path |
| C94 | unit | Per-set reps `[{reps:"8-12"},…]` and no exercise-level reps or repRange | nil (per-set ranges don't set the default) |
| C95 | unit | `repRange: "lots"`, `"AMRAP"`, `"0-5"`, `"10+"`, `2.5`, `true` | `E_REPRANGE_INVALID` at `…exercises[i].repRange` |

### C.10 drops (`valid/drop-sets.json`)
| ID | Type | Case | Expected |
|---|---|---|---|
| C96 | unit | Exercise-level `drops: [{weight:15},{weight:10,reps:"8-10"}]`, 3 sets | Every set has 2 drops: (amrap, 15), (range 8–10, 10) |
| C97 | unit | Set-level `drops` on set 2 only, none at exercise level | Sets 0–1 have 0 drops, set 2 has 1 |
| C98 | unit | Set-level drops when exercise-level drops exist | Set's own list replaces the exercise's |
| C99 | unit | Drop without `reps` | AMRAP |
| C100 | unit | Drop without `weight` | weight nil (prefilled at run time from the previous step) |
| C101 | unit | Drops on a timed set / timed exercise | Removed + `W_DROPS_IGNORED` |
| C102 | unit | `drops: []`, 6 drops, `drops: {…}`, `drops: [5]` | `E_DROPS_INVALID` at the drops path |
| C103 | unit | `drops: [{weight:"heavy"}]`, `[{reps:"ten"}]` | `E_WEIGHT_INVALID` / `E_REPS_INVALID` at `…drops[0].weight` / `.reps` |
| C104 | unit | Unknown field inside a drop | `W_UNKNOWN_FIELD` |

### C.11 cycle (`valid/cycle-cases.json`, `valid/cycle-weekday-ignored.json`)
| ID | Type | Case | Expected |
|---|---|---|---|
| C105 | unit | `cycle: ["upper","REST","Lower","off"]` with days Upper, Lower, Arms | [Upper, rest, Lower, rest]; `W_CYCLE_MISSING_DAY` (Arms) |
| C106 | unit | No cycle, rotation, 3 days | [day 0, day 1, day 2] |
| C107 | unit | Weekday plan with Tue and Sat | [rest, A, rest, rest, rest, B, rest]; an explicit cycle → `W_CYCLE_IGNORED` |
| C108 | unit | `cycle: ["A","Legs"]` where Legs isn't a day | `E_CYCLE_UNKNOWN_DAY` at `cycle[1]` |
| C109 | unit | `cycle: []`, `"A, rest"`, 32 entries, `[1,2]` | `E_CYCLE_INVALID` at `cycle` |
| C110 | unit | Cycle names matched case-insensitively with collapsed whitespace | True |

### C.12 Timed sets, beeps, bodyweight (`valid/timed-sets.json`, `valid/bodyweight.json`)
| ID | Type | Case | Expected |
|---|---|---|---|
| C111 | unit | `durationSeconds: "max"`, `"open"`, `"AMSAP"`, `"as long as possible"`, `"to failure"` | openDuration(min nil) |
| C112 | unit | `durationSeconds: "30+"` | openDuration(min 30) |
| C113 | unit | `durationSeconds: "forever"`, `"0+"`, `"30s"` | `E_DURATION_INVALID` |
| C114 | unit | Set-level `durationSeconds: "AMSAP"` under an exercise-level fixed 60 | That set is open; the others fixed 60 |
| C115 | unit | Fixed 45 s set, `warningBeep` missing or `true` | warningBeepSeconds 5 (10 %, rounded half up) |
| C115b | unit | Fixed 25 s → 3; 30 s → 3; 600 s → 60; 8 s → nil (under 10 s never warns) | As listed |
| C116 | unit | Exercise-level `warningBeep: 15`, set-level `5` on one set | 15 for the others, 5 for that set |
| C116b | unit | `warningBeep: false` | nil |
| C117 | unit | `warningBeep` given on a rep-based or open-duration set/exercise | nil + `W_WARNING_BEEP_IGNORED`; missing on those → nil, no warning |
| C117b | unit | `warningBeep: 45` on a 30 s set | nil + `W_WARNING_BEEP_IGNORED` |
| C118 | unit | `warningBeep: 0`, `-1`, `2.5`, `"soon"`, `86400` | `E_WARNING_BEEP_INVALID` |
| C119 | unit | `bodyweight: true` with no weight | flag true, weights nil |
| C120 | unit | `bodyweight: true` with `weight: 5` (exercise or set level) | weight nil + `W_BODYWEIGHT_WEIGHT_IGNORED` |
| C121 | unit | `bodyweight: true` with weighted drops | drop weights nil + `W_BODYWEIGHT_WEIGHT_IGNORED` |
| C122 | unit | `bodyweight: "yes"`, `1` | `E_BODYWEIGHT_INVALID` |
| C123 | unit | `bodyweight: false` with `weight: 10` | normal weighted exercise |
| C124 | unit | Drops on an open-duration set | `W_DROPS_IGNORED` |

### C.13 Rendering a plan back to JSON (D29, v1.1)
| ID | Type | Case | Expected |
|---|---|---|---|
| C40 | unit | Render every valid fixture with `PlanJSON.render` and import the result | No errors; the re-imported plan renders byte-identically, and its days, exercises, set counts, cycle and schedule all match. This fixpoint is what lets an edit go out through the real import pipeline instead of around it. A `warningBeep` of "off" must be written as an explicit `false`, since an absent field means the 10 % default |

## D. Import — Validate stage (limits, plan-wide)
| ID | Type | Case | Expected |
|---|---|---|---|
| D1 | unit | 32 days | `E_LIMIT_EXCEEDED` at `days` |
| D2 | unit | 31 days | Accepted |
| D3 | unit | 51 exercises in one day | `E_LIMIT_EXCEEDED` at `days[i].exercises` |
| D4 | unit | `days: []` | `E_NO_DAYS` |
| D5 | unit | A day with `exercises: []` | `E_NO_EXERCISES` at `days[i].exercises` |
| D6 | unit | Multiple errors in one plan | All reported, ordered by path; import blocked |
| D7 | unit | Errors and warnings together | Errors returned; warnings also present in the issue list |
| D8 | unit | Every fixture in `valid/` | Zero errors; warnings exactly as manifest says |
| D9 | unit | Every fixture in `invalid/` | The manifest's error code present, at the manifest's path when given |
| D10 | unit | Resulting `Plan` re-encodes and re-decodes to an equal value (round trip) | Equal |
| D11 | unit | Import is deterministic except UUIDs and `importedAt` | Two imports of the same text produce equal plans after zeroing those |

## E. Flattening a Day into Steps
| ID | Type | Case | Expected order (exercise.set) |
|---|---|---|---|
| E1 | unit | One exercise, 3 sets | 0.0, 0.1, 0.2; all isLastInRound |
| E2 | unit | Two ungrouped exercises, 2 sets each | 0.0, 0.1, 1.0, 1.1 |
| E3 | unit | Superset A: ex0 (3 sets), ex1 (3 sets) | 0.0, 1.0, 0.1, 1.1, 0.2, 1.2; isLastInRound only on ex1 steps |
| E4 | unit | Circuit of 3 exercises × 2 rounds | 0.0,1.0,2.0, 0.1,1.1,2.1 |
| E5 | unit | Group with 3/2 sets | 0.0,1.0, 0.1,1.1, 0.2; step 0.2 isLastInRound |
| E6 | unit | Ungrouped, group A ×2, ungrouped | 0.0…, then interleaved 1/2, then 3.x |
| E7 | unit | Empty day (shouldn't happen post-validation) | Returns [] without crashing |
| E8 | unit | Step indices are 0..N−1 contiguous; count = total sets | True for all fixtures |
| E9 | unit | 50 exercises × 50 sets | Completes in < 10 ms |
| E10 | unit | One exercise, 2 sets, 2 drops each | 0.0, 0.0.1, 0.0.2, 0.1, 0.1.1, 0.1.2; isLastInRound only on the .2 drops |
| E11 | unit | Superset A: ex0 (2 sets, 1 drop), ex1 (2 sets) | 0.0, 0.0.1, 1.0, 0.1, 0.1.1, 1.1; isLastInRound on 1.0 and 1.1 |
| E12 | unit | Three blocks | blockIndex 0,1,2 assigned; isLastInBlock true on exactly three steps, the last of each block |
| E13 | unit | Single exercise, single set, no drops | one step: isLastInRound, isLastInBlock both true |
| E14 | unit | Drop steps of a set are contiguous and follow their set | True for all fixtures |

## F. Rest at execution (SPEC §6.3)
| ID | Type | Case | Expected |
|---|---|---|---|
| F1 | unit | Log the last set of the last exercise | No rest; session completes |
| F2 | unit | Log a set not last in round (superset member 1 of 2) | Rest 0 → working(next) immediately |
| F3 | unit | Log last in round of group where member 1 has rest 60, member 2 has none | 60 |
| F4 | unit | Group where only member 2 has explicit rest 45 | 45 |
| F5 | unit | Group with no explicit rests, day default 80 | 80 |
| F6 | unit | Ungrouped set with rest 0 | working(next) immediately, no notification effect |
| F7 | unit | Log last set of exercise 0 while exercise 1 remains | `RestResolution.after` returns `.blockDone` (was called "transition" before v1.1) — see F9 |
| F8 | unit | Log the final pending step while an earlier pending step exists (user jumped ahead) | Rest starts; nextStep = the earlier pending step |
| F9 | unit | Log the last set of exercise 0 while exercise 1 remains | `.blockDone` (v1.1; was `.transition`); **behavior revised in v1.1**: the engine advances straight to `working(next)` instead of a separate phase — see G29/G49; the set's restSeconds unused |
| F10 | unit | Log the last step of a superset block (last round, last member) with another block after | `.blockDone` |
| F11 | unit | Log a main set that has drops | 0 (next step is the drop) |
| F12 | unit | Log the last drop of a set, more sets remain in the exercise | countdown of the set's rest |
| F13 | unit | Log the last step of the last block | session completes (no blockDone) |
| F14 | unit | Jumped ahead: log last step of block 2 while a pending step in block 0 remains | `.blockDone` (next step is in another block) |
| F15 | unit | (v1.1, D14) A block-ending log's effects | No `.transition` phase exists; phase → `working(next)` in the same event; `ActiveSession.blockDone` records `(finishedBlock, startedAt: now)`; no scheduleNotification effect |

## G. Session engine
| ID | Type | Case | Expected |
|---|---|---|---|
| G1 | unit | New session from a Day | steps all pending; phase working(0); effects [persist] |
| G2 | unit | logSet(0, 10 @ 60) | step0 logged with loggedAt=now; phase resting(endsAt=now+rest, next=1); effects contain scheduleNotification(endsAt, body mentions next exercise and "set 2 of") and persist |
| G3 | unit | logSet on an already-logged step | Overwrites result; behaves like a log (starts rest) |
| G4 | unit | editSet on a logged step during rest | Result updated; phase unchanged; no timer effects |
| G5 | unit | skipSet(0) | step0 skipped; phase working(1); no notification effect |
| G6 | unit | skipSet on the last pending step | completed; sessionCompleted effect |
| G7 | unit | skipExercise(e) with 2 pending and 1 logged step in e | The 2 pending → skipped; logged untouched; phase → next pending outside e |
| G8 | unit | jumpTo(5) during rest | cancelNotification; phase working(5); rest state cleared; lastRestEndedAt set |
| G9 | unit | jumpTo a logged step | phase working(that step) (edit mode in UI) |
| G10 | unit | adjustRest(+30) | endsAt += 30; effects cancelNotification then scheduleNotification(new endsAt) |
| G11 | unit | adjustRest(−30) when 20 s remain | endsAt ≤ now → rest ends: phase working(next); cancelNotification; no playAlert |
| G12 | unit | skipRest | cancelNotification; working(next); no playAlert |
| G13 | unit | restElapsed at exactly endsAt while foreground | playAlert; working(next); lastRestEndedAt = endsAt |
| G14 | unit | restElapsed observed 5 min late (foreground after background) | working(next); **no** playAlert; overrun computable as now − endsAt |
| G15 | unit | restElapsed while not resting | No-op, no effects except nothing (idempotent) |
| G16 | unit | logSet on step i where nextStep(after i) wraps to an earlier pending | resting with nextStep = earlier index |
| G17 | unit | nextStep when all pending are after i | First pending > i |
| G18 | unit | nextStep when none pending | nil |
| G19 | unit | finish with 3 pending | They become skipped; completed; endedAt=now; sessionCompleted |
| G20 | unit | finish with 0 logged | Engine reports `loggedCount == 0` so the UI can offer discard; no rotation advance if discarded |
| G21 | unit | renameExercise(1, "DB Bench") | session.exercises[1].name updated; targets and steps untouched; persist |
| G22 | unit | renameExercise to blank | Rejected (no change) |
| G23 | unit | Log timed set with duration result 40 of target 45 | result duration(40); rest starts normally |
| G24 | unit | Any event → last effect is persist | True for every event type |
| G25 | unit | Event sequence for a full 18-step workout | Ends completed, 18 logged, one notification scheduled per rest, one cancel per rest end |
| G26 | unit | Engine is a value type; applying events to a copy doesn't affect the original | True |
| G27 | unit | `elapsed(now)` = now − startedAt regardless of phase | True |
| G28 | unit | Session completed exactly when logging the last pending | endedAt == that loggedAt |
| G29 | unit | logSet on the last step of block 0 | **Revised in v1.1** (was a separate `transition(startedAt, nextStep, finishedBlock)` phase): phase → `working(first step of block 1)` in the same event; `active.blockDone == BlockDone(finishedBlock: 0, startedAt: now)`; `session.steps[nextStep].startedAt == now`; no scheduleNotification; persist |
| G30 | unit | dismissBlockDone (was continueTransition) | Clears `active.blockDone`; phase already `working(nextStep)`, so it is unchanged; no effects but persist |
| G31 | unit | dismissBlockDone when `blockDone` is nil | no-op |
| G32 | unit | jumpTo while `blockDone` is set | working(step); `blockDone` cleared |
| G33 | unit | skipExercise that ends a block with another block remaining | `blockDone` set for the finished block; phase already `working(next)` |
| G34 | unit | skipSet on the last step of a block | `blockDone` set, never a countdown |
| G35 | unit | ActiveSession with `blockDone` persisted and restored | `blockDone.startedAt` preserved; the "moving on" stopwatch continues from it |
| G36 | unit | `adviceForBlockJustFinished` while `blockDone` is set | equals ProgressionAdvice.evaluate for that block's exercise(s); `[]` once `blockDone` is nil |
| G37 | unit | Switch-day: `finishAndStart(day)` | old session completed (pending → skipped), cycle advanced, new session working(0) |
| G38 | unit | Switch-day: `discardAndStart(day)` | old session removed, cycle unchanged, new session working(0) |
| G39 | unit | Phase becomes working(i) for a rep step | `steps[i].startedAt = now` |
| G40 | unit | Phase becomes working(i) for a timed step | `startedAt` stays nil until `startTimer(i)` |
| G41 | unit | `startTimer` on a fixed 45 s set with warning 5 | startedAt = now; effects scheduleNotification("set-end", now+45) and scheduleNotification("set-warning", now+40) |
| G41b | unit | `startTimer` on a fixed set with warning nil | only "set-end" scheduled |
| G41c | unit | `startTimer` on an open set with minimum 30 | only scheduleNotification("set-minimum", now+30) |
| G42 | unit | `timerElapsed` after `startTimer` | logged duration 45, loggedAt = now, then the normal rest/transition rule; cancels "set-end", "set-warning", "set-minimum" |
| G43 | unit | `timerDone` at 30 s | logged duration 30 |
| G44 | unit | `startTimer` on an open set, `stopTimer` at 52.8 s | logged duration 52; no notification was scheduled |
| G45 | unit | `startTimer` on a rep step / `stopTimer` while not running | no-op |
| G46 | unit | Jump back to a logged rep step and re-log | startedAt reset on re-entry; new duration measured from re-entry |
| G47 | unit | Skipped step | startedAt kept, setSeconds nil |
| G48 | unit | Warning moment = endsAt − warningBeepSeconds; `beepDue(now)` reports warning / end / minimum exactly once each | True; nothing reported for moments that passed while backgrounded |
| G49 | unit | (D27, v1.1) editSet on a **skipped** step with a valid result | Result set; status → logged; `loggedAt` set to the edit's `now` (replacing the skip time); no phase change, no timer effects; advice recomputed |
| G50 | unit | editSet on a **pending** step | No-op (unchanged from v1: only logged or skipped steps can be edited) |
| G51 | unit | (D23, v1.1) undoLog on the step named by `active.lastCompletedStep` | Step → pending; result and `loggedAt` cleared; `startedAt` reset to `now`; phase → `working(step)`; `blockDone` cleared; the exercise's `advice` cleared if it now has a pending step |
| G52 | unit | undoLog on any step other than `lastCompletedStep` | No-op |
| G53 | unit | undoLog after the rest that followed the log it undoes has started | Cancels the pending `"rest-timer"` notification; phase → `working` |
| G54 | unit | undoLog on a step logged via `skipSet` | Same as G51 (skip and log are both undoable) |
| G55 | unit | undoLog on a drop step | Same as G51, for a `dropIndex > 0` step |
| G56 | unit | undoLog when the session is `.completed` | No-op (history editing, §4.10, covers correcting a finished session instead) |
| G57 | unit | `canUndo` | True only when `lastCompletedStep` names a non-pending step and the session isn't completed |
| G58 | unit | Log step A, then log step B, then undoLog(A) | No-op — A is no longer `lastCompletedStep` |
| G59 | unit | A v1 `ActiveSession` file whose `phase` is the old `.transition(startedAt, nextStep, finishedBlock)` | Decodes without throwing: `phase == .working(step: nextStep)`; `blockDone == BlockDone(finishedBlock: finishedBlock, startedAt: startedAt)` |

| G61 | unit | (D28, v1.1) Do later on an exercise with sets left | Its whole block's steps move after the day's last pending step; `blockIndex` is unchanged, and the Overview orders blocks by position so the new order shows |
| G62 | unit | (D28, v1.1) Do later on a partly-done exercise | The logged sets move with it and keep their results; the undo target follows its step through the move |
| G63 | unit | (D28, v1.1) Do later during a rest, or with a block-done strip showing | The rest is cancelled (no stale notification) and the strip is cleared; work resumes on the next pending step |
| G64 | unit | (D28, v1.1) Do later when it would change nothing | A no-op: nothing pending in that block, nothing pending outside it, a one-block superset day, or a completed session |

## H. Rest timer, notifications, audio (UI + manual)
| ID | Type | Case | Expected |
|---|---|---|---|
| H1 | ui | Start rest 90 s | Display 1:30 counting down each second |
| H2 | ui | +30 twice, −30 once | Display reflects +30 net; notification rescheduled (assert via a mock notification center in engine tests G10) |
| H3 | manual | Lock phone during 90 s rest | Notification arrives at the right second, with the next exercise in the body |
| H4 | manual | Skip rest while locked-notification pending, then unlock | No stale notification fires later |
| H5 | manual | Background for 3 min mid-rest, return | Step card shows next step with overrun "+1:30" |
| H6 | manual | Kill the app during rest, relaunch, Resume | Rest resumes with correct remaining (or overrun) from `endsAt` |
| H7 | manual | Notification permission denied | Foreground alerts still work; one-time banner shown; Settings row shows "Off · Open Settings" |
| H8 | manual | Phone on silent, sound on, no headphones | Beep is audible (playback category) |
| H9 | manual | Music playing in headphones | Music keeps playing; beep ducks it briefly; music resumes at full volume |
| H10 | manual | Sound off | No audio session activation (music never ducks) |
| H11 | manual | Vibration on, phone face down on bench | Haptic felt at zero |
| H12 | manual | Two rests in a row quickly (log, skip rest, log) | Only one pending notification at any time |
| H13 | manual | Rest of 10 minutes | Notification fires at 10:00, display shows m:ss throughout |
| H14 | manual | Incoming phone call during rest | Notification still delivered as banner |
| H15 | manual | Timed set countdown 45 s, tap Done at 30 s | Logs 30; rest begins |
| H16 | manual | Timed set countdown reaches zero while locked | Notification "Time!"; on return the logged duration is 45 and rest is running/overrun |
| H17 | ui | Low Power Mode | Countdown still accurate (Date-based) |
| H18 | manual | Change device clock forward during rest | Rest ends immediately on next tick; no crash (accepted behavior) |
| H19 | manual | Fixed 45 s plank, default warning | Short quieter beep at 40 s, final beep at 45 s, nothing else |
| H20 | manual | Open-duration dead hang with "30+" | One beep at 30 s; Stop logs the seconds; no beep without a minimum |
| H21 | manual | Lock the phone at 12 s of a 45 s set | "5 s left" notification at 40 s, "Time!" at 45 s; on unlock nothing replays |
| H22 | manual | Sound off, vibration on, timed set | Light haptic at the warning and a stronger one at the end; no audio session activation |
| H23 | manual | Tap Done at 30 s of a 45 s set | Neither the warning nor the end notification fires later |
| H33 | manual | (D24, v1.1) Launch with `-uiReadOnlyStore`, start a workout and log a set | "Couldn't save the workout…" appears **over the workout screen** with Retry — an alert attached only to the view behind the cover would show nothing; the set stays on screen; relaunching without the argument and tapping Retry saves it |
| H24 | manual | (D22, v1.1) Minimize mid-rest, lock the phone, wait past the rest notification, reopen and Resume | The notification fires at the right second; Resume returns to the same step with the strip already reading the overrun, and no stale rest notification fires afterwards |

## I. Prefill and "last time" (SPEC §6.5)
"Last" below = most recent completed session containing the exercise in the same units.
| ID | Type | Case | Expected |
|---|---|---|---|
| I1 | unit | No history, target 8–12 @ 60 | reps 8, weight 60 |
| I2 | unit | No history, fixed 10, no weight | reps 10, weight empty |
| I3 | unit | Last: set k = 10 @ 62.5; target 8–12 @ 60 | weight 62.5, reps 10 (last achieved, weight matches) |
| I4 | unit | Last: set k = 14 @ 60; target 8–12 @ 60 | reps 14 (last achieved wins even above the range) |
| I5 | unit | Last had only 2 sets, current set index 3 | weight = last logged weight of that exercise; reps = last logged reps of it |
| I6 | unit | Current session set 0 logged @ 65; last session set 1 was 10 @ 60; set 1 prefill | weight 65 (current session); reps = target min (weight differs from last's set 1 weight) |
| I7 | unit | Last in lb, current plan kg | history ignored; target values used |
| I8 | unit | A session that is in progress (not completed) | Ignored |
| I9 | unit | Newest session has the exercise fully skipped | Falls through to the older session |
| I10 | unit | "bench press" vs history "Bench  Press" | Matches |
| I11 | unit | AMRAP target, last = 12 @ 0 (bodyweight), prefilled weight empty | reps 12 (nil weights count as equal) |
| I12 | unit | AMRAP target, no history | reps empty; Log set disabled until typed |
| I13 | unit | Timed target 45, last = 40 s | seconds field 40; no history → 45 |
| I14 | removed (v1.1) | **D11 revised**: the v1 dynamic rule ("changing weight before touching reps re-prefills reps from the target; the RepsDraft API this needed is gone") was removed in v1.1 — see I38. Was: "User changes weight 60 → 62.5 before touching reps (last was 10 @ 60, target 8–12)" → "reps re-prefills to 8". |
| I15 | removed (v1.1) | Same removal as I14. Was: "Then changes weight back to 60" → "reps back to 10". |
| I16 | removed (v1.1) | Same removal as I14. Was: "User edits reps to 11, then changes weight" → "reps stays 11". |
| I17 | unit | Tapping "Suggested: 62.5" chip | weight 62.5; reps → target min via I14 |
| I18 | unit | "Last time" line, all weights equal, current set index 1 | "10, **10**, 8 @ 60 kg" (bold marks index 1) |
| I19 | unit | "Last time" line, weights differ | "10@60, **10@60**, 8@65 kg" |
| I20 | unit | "Last time" line, no weights | "10, 10, 8" |
| I21 | unit | "Last time" line, skipped set in the middle, current index 1 | "10, **–**, 8 @ 60 kg" |
| I22 | unit | Current set index 3, last had 3 sets | nothing bold |
| I23 | unit | "Last:" weight line under the weight field | "Last: 60 kg"; absent with no history |
| I24 | unit | Suggested chip appears only when the last session stored advice for this exercise | True; `.increase(to:)` shows the number, `.increaseLoad` shows "Add load" with no chip |
| I25 | unit | Rename exercise mid-session ("Bench" → "DB Bench") | Later sets prefill from "DB Bench" history |
| I26 | unit | Deleted session | No longer used for prefill |
| I27 | unit | Edited past session value | New value used for prefill |
| I28 | unit | Bodyweight exercise, last = 12 reps, no weight | reps 12, weight empty, "Last: –" line hidden |
| I29 | unit | Drop prefill: last session drop (k,1) = 8 @ 15 | weight 15, reps 8 |
| I30 | unit | Drop prefill, no history, drop target weight nil, previous step logged @ 20 | weight 20 (user taps −), reps empty (AMRAP) |
| I31 | unit | "Last time" line with drops: sets 10 (drops 8, 6), 10, 9 | "10↓8↓6, 10, 9 · 60 kg" (per-set weights shown when the drops' weights differ) |
| I32 | unit | Bold in "Last time" for a drop step (k=0, drop 1) | The "8" inside "10↓**8**↓6" is bold |
| I33 | unit | Open-duration set, last session 52, 48 s | No prefill; "Last time: 0:52, **0:48**" |
| I34 | unit | Bodyweight exercise | Weight prefill nil and the weight row is not rendered (view model exposes `showsWeight = false`) |
| I35 | unit | (D11 v1.1) 50 → 60 → 70 kg pyramid (`hasVariedTargets == true`); log set 1 at 50 kg | Set 2 prefills 60 kg, set 3 prefills 70 kg — never 50 |
| I36 | unit | A straight exercise (uniform target weight) | `hasVariedTargets == false`; carry-forward within the session is unchanged from v1 (I2's behavior) |
| I37 | unit | Varied pyramid with last-session history logged at 52.5 / 62.5 / 72.5; log this session's set 1 at 50 kg | Set 2 prefills 62.5 kg (last session's own set 2), set 3 prefills 72.5 kg — not carried from set 1 |
| I38 | unit | (D11 v1.1) Reps are computed once when a step's card loads | No API exists to re-prefill reps from a later weight edit (`RepsDraft`/`Prefill.draft` removed); the suggestion chip (§6.11) is unaffected — see the retained assertion in I39 |
| I39 | unit | Suggestion chip still works after the I14–I16 removal | Last session's `advice` still produces `suggestedWeight` and an unaffected `weight` prefill |
| I40 | unit | (v1.1, D22) `StepCard.progress` | "Exercise 2 of 5 · Set 2 of 3" for a plain exercise; "· drop 1 of 2" appended for a drop; "A · round 2 of 3 · Incline Press" for a superset member |
| I41 | unit | (v1.1, D22) `StepCard.setRows` for a straight exercise | One row per set of that exercise, in order, with `isCurrent` true only on the given step; logged rows show the result, pending rows the target, skipped rows "skipped" |
| I42 | unit | `StepCard.setRows` for a superset member | Only the current round's members (one row per exercise sharing that block and set index), not every round |
| I43 | unit | (v1.1, D14) `StepCard.blockDoneLine` for a finished block with advice | "<exercise> done · <duration>" plus the progression message; `nil` when the block has no identifiable exercise |

## J. Stats (SPEC §6.7)
| ID | Type | Case | Expected |
|---|---|---|---|
| J1 | unit | 3 sets 10@60, 10@60, 8@65 | volume 1720 |
| J2 | unit | Sets without weight | contribute 0 |
| J3 | unit | Timed sets with weight | contribute 0 |
| J4 | unit | Skipped sets | excluded from volume and logged count; included in total |
| J5 | unit | Best set among 100×5, 100×3, 95×8 | 100 × 5 |
| J6 | unit | Best set with no weights | most reps |
| J7 | unit | Best set with only timed sets | none (nil) |
| J8 | unit | Duration | endedAt − startedAt; a session crossing midnight still grouped under start date |
| J9 | unit | Summary comparison when exercise has no prior session | `ExerciseComparison(headline: "First time", rows: [])`. **Rewritten in v1.1's R4**: it used to return one raw string, "10, 8@60 · last 10, 9@60 · kg", which printed both sessions and left the reader to subtract |
| J10 | unit | History list per-session volume in lb and kg sessions | Each shows its own unit; no cross-unit totals anywhere |
| J11 | unit | Exercise duration, first block: session started 10:00:00, its last step logged 10:09:40 | 9:40 |
| J12 | unit | Exercise duration, second block: previous block's last log 10:09:40, this block's last step 10:17:00 | 7:20 (rest before the block counts toward it) |
| J13 | unit | Block durations across a completed session | Sum to session duration (±1 s rounding) |
| J14 | unit | Block with pending steps | Duration nil (not finished) |
| J15 | unit | Block whose steps were all skipped | Duration nil; skipped steps still carry `loggedAt` |
| J16 | unit | Superset block A/B, 3 rounds | One duration for the block, not per exercise |
| J17 | unit | `ExerciseHistory.series("Bench Press")` over 3 sessions (one lb, two kg), units kg | 2 points, oldest first, each with sets, topWeight, topSetReps, volume |
| J18 | unit | series point for session with sets 10@60, 8@65, 6@65 | topWeight 65, topSetReps 8, volume 1510 |
| J19 | unit | series on 1000 sessions | < 50 ms |
| J20 | unit | series for an exercise with only timed sets | Points exist; topWeight nil; volume 0; topSeconds = longest set |
| J21 | unit | Set seconds: startedAt 10:00:00, loggedAt 10:00:34.9 | 34 |
| J22 | unit | Set seconds for a step with no startedAt (old data) | nil, rendered as "–" |
| J23 | unit | Average set time on Summary | Mean of non-nil set seconds over logged steps |
| J24 | unit | series point `setSeconds` | One entry per set in order, nil for skipped |

| J25 | unit | (v1.1) `SessionStats.comparison` for the comparable, non-comparable, varied-weight and first-time cases | Same weight → "2 more reps at the same weight"; a moved weight → "+2.5 kg", plus ", 1 fewer rep" when the reps moved too; identical → "Same as last time"; bodyweight → reps alone; timed → "5 s longer held"; weights that varied within the session → a volume headline and one "10 @ 60 → 10 @ 62.5" row per set; no prior session → "First time" |

| J26 | unit | (D30, v1.1) `SessionStats.personalRecords` | A set that beats every earlier logged set of that exercise is a record; equalling it is not; a session that sets two records marks both; the first session ever sets none |
| J27 | unit | (D30, v1.1) Records across units and statuses | A session in other units is not history for the comparison (D10); a skipped set is never a record; bodyweight compares reps and timed work compares seconds held |
| J28 | unit | (D30, v1.1) History's exercise search, and the chart's data | Search matches on normalized name, most recently trained first, de-duplicated; the chart plots only points that have a weight, so a bodyweight exercise gets no chart rather than a flat line at zero |

## P. Progression advice (SPEC §6.11)
weightStep = 2.5 unless stated. Range 8–12, 3 sets, all @ 60 unless stated.
| ID | Type | Case | Expected |
|---|---|---|---|
| P1 | unit | 12, 12, 12 | `.increase(to: 62.5)` |
| P2 | unit | 12, 12, 11 (one rep short overall) | `.increase(to: 62.5)` (tolerance 1) |
| P3 | unit | 12, 11, 11 (two short) | nil |
| P4 | unit | 8, 8, 8 (floor exactly) | nil |
| P5 | unit | 8, 8, 7 (below floor by one) | `.decrease(to: 57.5)` |
| P6 | unit | 5, 5, 5 | `.decrease(to: 57.5)` |
| P7 | unit | 12, 12, 5 (total 29 ≥ floor 24) | nil |
| P8 | unit | Weights differ: 12@60, 12@60, 12@65 | nil (no single working weight) |
| P9 | unit | Bodyweight, 12, 12, 12 | `.increaseLoad` |
| P10 | unit | Bodyweight, 6, 6, 6 | `.decreaseLoad` |
| P11 | unit | No repRange | nil |
| P12 | unit | Timed sets | nil |
| P13 | unit | 12, 12, skipped | Evaluates on 2 sets: achieved 24 ≥ 24−1 → `.increase(to: 62.5)` |
| P14 | unit | All sets skipped | nil |
| P15 | unit | One set, 12 | `.increase` |
| P16 | unit | One set, 7 | `.decrease` |
| P17 | unit | Weight 2 with step 2.5, below floor | `.decrease(to: 0)` (clamped) |
| P18 | unit | Weight step 5 (lb plan) | `.increase(to: 65)` from 60 |
| P19 | unit | Advice is stored on the completed session's exercise | Present after completion; nil when none |
| P20 | unit | Editing a past session's reps re-evaluates advice | Updated |
| P21 | unit | Advice evaluated when the exercise's last step is logged mid-session | Rest overlay text includes it; engine exposes `adviceForBlockJustFinished` |
| P22 | unit | Message text for increase, kg | "All sets hit the top of 8–12. Try 62.5 kg next time." |
| P23 | unit | Message text for decrease | "Below 8–12 across 3 sets. Try 57.5 kg next time, or keep 60 kg and build up." |
| P24 | unit | Range 10–10 (single number), 10, 10, 10 | `.increase` |
| P25 | unit | Main sets 12, 12, 12 with drops 8, 6 each | `.increase` (drops ignored) |

## S. Home sparkline — **removed in v1.1's R3**

The sparkline, `HomeMetric` and SPEC §6.13 went together: a chart whose metric changed on an
undocumented tap was undiscoverable rather than quiet, and `HomeActivity.line` (O66) replaced it.
These rows are kept as the record of what was tested and then deleted; **none of them is a `unit`
case any more**, and nothing implements them.

| ID | Type | Case | Expected |
|---|---|---|---|
| S1 | removed | duration, sessions on 3 of the last 7 days | 7 values; 4 nil; minutes for the rest |
| S2 | removed | Two sessions on one day, duration | summed |
| S3 | removed | volume with a lb session in a kg window | lb session excluded |
| S4 | removed | avgWeight | mean over weighted rep-based steps of that day's sessions |
| S5 | removed | avgReps over rep-based steps including drops | mean |
| S6 | removed | exercises = blocks with ≥ 1 logged step | count |
| S7 | removed | Caption for duration, avg 52 | "Workout length · last 7 days · avg 52 min" |
| S8 | removed | Caption for volume | "Volume · last 7 days · total 12,400 kg" |
| S9 | removed | No sessions in the window | all nil; caption "No workouts in the last 7 days" |
| S10 | removed | Window is the last 7 calendar days ending today (injected), local time zone | Sessions 8 days ago excluded; today included |
| S11 | removed | Tap cycles metrics in enum order and wraps; persisted in Settings | True |
| S12 | removed | A session crossing midnight counts on its start day | True |

## Q. v1.2 — the code-health defects (V1)

Each row is a defect the 2026-09-07 review found, with the test that would have caught it.
`JimmsBroTests/DefectFixesTests.swift`.

| ID | Kind | Case | Expected |
|---|---|---|---|
| Q1 | unit | (v1.2) A no-op rename of a superset member, applied through `PlanEdit` | The between-round rest is unchanged; `groupRestSeconds` survives the render/re-import that every edit is |
| Q2 | unit | (v1.2) Every `PlanEdit.Operation` applied to a plan with a superset | None of them changes the round rest |
| Q3 | unit | (v1.2) `setRest` on a superset member | Changes the round rest the whole group shares — the value rest resolution actually reads — not only the per-set value nothing in a group reads |
| Q4 | unit | (v1.2) `PlanJSON.render` for an ungrouped exercise | No exercise-level `restSeconds`; only a group member carries the round rest there |
| Q5 | unit | (v1.2) `setWorkWeight` | Takes effect but emits no `.persist`; the next log carries it to disk. Typing "62.5" is no longer four writes of `active-session.json` |
| Q6 | unit | (v1.2) Decoding a `Phase` payload this version does not know | Throws, so the file is set aside as corrupt rather than silently read as a completed workout; `working` and v1's `transition` still decode |
| Q7 | unit | (v1.2) `exportData` / `readBackup` / `restore` over a store holding an undecodable file | The file is reported but **not** renamed aside; a real `load` still sets it aside and names it |
| Q8 | unit | (D24, v1.2) Retry after the alert's dismissal has cleared `saveFailure` | The captured failure is retried and the value actually reaches disk |
| Q9 | unit | (D31, v1.2) The restore failure message | **Replace all** says what it had already cleared; only **Merge** may say nothing you had was changed |
| Q10 | ui | (v1.2) Hold − or + on the reps or weight stepper | The value keeps changing while the finger is down, and stops when it lifts |
| Q11 | manual | (v1.2) `swift test` from a clean checkout | Compiles and runs the Core suite |

### V2 — schema durability and one definition per rule

`JimmsBroTests/StoreMigrationTests.swift`. The frozen files live in `examples/store/v1/` and are
what v1.1 actually wrote; they are never regenerated to make a test pass.

| ID | Kind | Case | Expected |
|---|---|---|---|
| Q12 | unit | (v1.2) Decode `examples/store/v1/settings.json` | Every setting v1.1 held comes back |
| Q13 | unit | (v1.2) Decode `examples/store/v1/plans.json` | The plan, its active id, its superset's `groupRestSeconds`, and it still flattens into a runnable session |
| Q14 | unit | (v1.2) Decode `examples/store/v1/session.json` | Logged and skipped sets, results and set durations |
| Q15 | unit | (G59, v1.2) Decode `examples/store/v1/active-session.json` | Resumes mid-rest with its next step, work weight and undoable step |
| Q16 | unit | (v1.2) A file missing every defaulted key, and one missing an identity key | The first decodes to defaults (a plan with no cycle repeats its days in order); the second throws, so §8.3 still sets it aside |
| Q17 | unit | (v1.2) `fileVersion` 0, 1 and 2 | A reader reads its own version and older; only a newer file is refused |
| Q18 | unit | (v1.2) A whole store of v1.1 files through `Store.load` | Loads with `corruptFiles` empty |
| Q19 | unit | (v1.2) `AlertIdentifier` | Each id carries its own title and sound; only the warning uses the bundled sound; the engine can no longer spell one wrong |
| Q20 | unit | (v1.2) `SessionBlocks` | One grouping rule for the Overview and Session detail: blocks ordered by where their steps sit, names de-duplicated by §6.9's matching, rows named only in a superset |
| M9 | unit | (v1.2) `Prompts.planTemplate` and `fixTemplate` | Equal, character for character, to the fenced blocks of `docs/PROMPT.md`; the example JSON appears once in the source and still imports cleanly |

### V3 — warm-up, the walk between exercises, and the stage

`JimmsBroTests/WarmUpAndTransitionTests.swift`. Every row came from the owner using v1.1 on the
phone: the workout did not say where in it you were, there was no warm-up, and the gap between
two exercises was given no time at all.

| ID | Kind | Case | Expected |
|---|---|---|---|
| Q21 | unit | (D32, v1.2) Start a session with `warmUpSeconds = 300` | Phase is `resting(kind: .warmUp, nextStep: 0)`, ending 5 min out, with its own scheduled alert |
| Q22 | unit | (D32, v1.2) −30 / Skip / log during a warm-up | Adjusting keeps the kind; Skip goes to the first set; logging out of it logs the set, exactly as any other rest |
| Q23 | unit | (D32, v1.2) A warm-up that runs out | Becomes the first set, alerts at zero, and logs nothing — a warm-up is not a set |
| Q24 | unit | (D32, v1.2) `warmUpSeconds = 0` | Starts on the first set with nothing to schedule: v1.1 exactly |
| Q25 | unit | (D33, v1.2) Log a block's last set | A `betweenExercises` rest of `transitionRestSeconds`, with the next exercise already on screen, −30 / +30 / Skip, and the finished block's line on the strip |
| Q26 | unit | (D33, v1.2) **Skip** a block's last set | Still gets the walk; a skipped set mid-block still gets no rest |
| Q27 | unit | (D33, v1.2) `transitionRestSeconds = 0` | The v1.1 block-done strip with its count-up, and no countdown |
| Q28 | unit | (D33, v1.2) A rest between sets | Still resolved from the set (§6.3), not from the new setting |
| Q29 | unit | (D34, v1.2) `WorkoutStage` through a whole session | Warm-up → Exercise 1 of 2 · Set 1 of 3 → Resting → Between exercises, each named, and each break flagged as one |
| Q30 | unit | (D34, v1.2) `WorkoutStage.progress` | Counts logged **and** skipped sets over the day's sets, so the bar moves within a long exercise |
| Q31 | unit | (v1.2) A v1.1 `RestState` with no `kind` | Decodes as `betweenSets`, which is the only thing it could have been |
| Q32 | ui | (v1.2) The workout header | Names the stage above a progress bar; the stage is accented while you are in a break and reads in the reserved green while you are working |
| Q33 | ui | (v1.2) Settings | **Warm-up** and **Between exercises** rows read in minutes and say "Off" at 0; **Smallest change** says what suggestions are rounded to |

### V4 — a weight you can actually load, and a suggestion per set

`JimmsBroTests/SuggestionTests.swift`.

| ID | Kind | Case | Expected |
|---|---|---|---|
| Q34 | unit | (D35, v1.2) `WeightRounding.snap` | 134 → 135 on a 5 lb grid, 61 → 60 on 2.5 kg, never below zero, and unchanged when the increment is 0 ("the equipment can make anything") |
| Q35 | unit | (D35, v1.2) `heavier`/`lighter` | Always move: 132 + 2.5 rounds *down* to 130 on a 5 lb grid, so it goes to 135 instead. Never past zero |
| Q36 | unit | (D35, v1.2) Three sets of 8 at 132 lb, top of 6–8, 5 lb grid | `.increase(to: 135)` — never 134. And 61 kg below the range gives `.decrease(to: 57.5)` |
| Q37 | unit | (D35, v1.2) − and + | From a loadable weight, one step, rounded onto the grid; from an off-grid weight (134 lb), the first tap lands on the grid — 135, not 140 |
| Q38 | unit | (D36, v1.2) A set with no history | "Try 8 × 60 kg", reason "The plan's target" |
| Q39 | unit | (D36, v1.2) A set done before, no advice | Repeats last time's weight and says "Last time 10 × 70 kg" |
| Q40 | unit | (D36, v1.2) A set whose exercise earned advice | Advice wins, and the reason names the rule: "You hit the top of 8–12 last time" |
| Q41 | unit | (D35/D36, v1.2) Stored advice of 61 kg on a 2.5 kg grid | Snapped to 60 on the way out — a suggestion stored by another version or another setting is still made loadable |
| Q42 | unit | (D36, v1.2) A timed set | Suggested in seconds, with no reps and no weight |
| Q43 | ui | (D36, v1.2) The suggestion chip | Reads "Try 8 × 62.5 kg" with its reason beneath; one tap fills in **both** numbers |

### V5 — an anchored rotation, and a calendar you can read

`JimmsBroTests/ScheduleAnchorTests.swift`.

| ID | Kind | Case | Expected |
|---|---|---|---|
| Q44 | unit | (D37, v1.2) `PlanSchedule.entry` around its anchor | The anchor day is the one that was done; the cycle runs forward and backward from it |
| Q45 | unit | (D37, v1.2) **Miss three days in a row** | Every other day says exactly what it said before — the compounding is gone |
| Q46 | unit | (D37, v1.2) Finish a workout | Re-anchors, once, to the day it was actually done; the following days follow from there |
| Q47 | unit | (D37, v1.2) `PlanSchedule.next` | The next training day at or after today, never the one just done, and it says which date |
| Q48 | unit | (D37, v1.2) Home's card and the month grid | Both read `PlanSchedule.next`, so the day named on the card is the day ringed on the grid |
| Q49 | unit | (D37, v1.2) A training day with no session on it | Reported as "Pull was due Monday"; nothing is reported when you trained that day |
| Q50 | unit | (D37, v1.2) A plan that predates anchors | Anchored to the day of its most recent completed session — or today when it has none — once, and never again |
| Q51 | unit | (D38, v1.2) `CalendarText.label` | Names the day, cut to fit a cell; a rest day has no label, which is what makes the gap visible |
| Q52 | unit | (D38, v1.2) `CalendarText.spoken` | One sentence per cell: "Monday 7 September. Planned: Pull" |
| Q53 | ui | (D38, v1.2) The week strip | Finished days filled in the reserved green with what was done, planned days outlined with what is coming, rest days a dash |
| Q54 | ui | (D37, v1.2) A rotation whose next day is not today | The card reads "Rest day", "Push is next, Tue" and **Start Push early**, matching the grid |

### V6 — what a workout was, and what a run of them adds up to

`JimmsBroTests/MetricsTests.swift`.

| ID | Kind | Case | Expected |
|---|---|---|---|
| Q55 | unit | (D39, v1.2) `SessionMetrics.of` a 30-minute session | Duration, working and resting time with their share, sets, volume, reps, heaviest set, average set |
| Q56 | unit | (D39, v1.2) A session with a skipped set | "2 of 3" with "1 skipped", and the volume counts only what was logged |
| Q57 | unit | (D39, v1.2) A bodyweight, timed session | No volume and no reps at all — not "0 kg" — and time under tension instead |
| Q58 | unit | (D39, v1.2) A session that beat its history | A personal-record count, naming the exercises that set them |
| Q59 | unit | (D39, v1.2) `TrendMetrics.summary` over 30 days | Workouts and workouts-a-week, time trained and average length, volume, sets, most trained, all-time count; nothing at all reports nothing |
| Q60 | unit | (D39, v1.2) `TrendMetrics.streakWeeks` | Consecutive calendar weeks with at least one workout; a gap ends it; a week with none is zero |
| Q61 | ui | (D39, v1.2) Session detail | Leads with the Metrics section; every value has a label and, where it needs one, a note |
| Q62 | ui | (D39, v1.2) History → **Metrics** | 7 / 30 / 90 day windows, the numbers, and the workouts that produced them |
| Q63 | ui | (D39, v1.2) Home's calendar | Tapping a finished day shows its line; the line itself opens the workout |

### V7 — the Lock Screen and the Dynamic Island

`JimmsBroTests/ActivityTests.swift`. ActivityKit is behind `ActivityPresenting`, so all of this
is testable without a phone; Q71–Q73 need the device and live in `DEVICE_CHECKLIST.md`.

| ID | Kind | Case | Expected |
|---|---|---|---|
| Q64 | unit | (D40, v1.2) A warm-up | The activity is a countdown titled "Warm-up", with the first exercise named under it |
| Q65 | unit | (D40, v1.2) Working, then resting | Working shows the exercise and no timer; logging turns it into a countdown and moves the progress |
| Q66 | unit | (D40, v1.2) A running timed set | Counts up from `startedAt`; a fixed duration also carries its end, an open hold does not |
| Q67 | unit | (D40, v1.2) A finished session | No activity at all |
| Q68 | unit | (D40, v1.2) Start a workout, then finish it | One activity started; ended exactly once when the workout ends |
| Q69 | unit | (D40, v1.2) Five seconds of ticks with nothing changing | Nothing pushed — the system draws the countdown itself |
| Q70 | unit | (D40, v1.2) Discard a workout | The activity ends; a countdown for a workout that no longer exists is worse than none |
| Q71 | manual | (D40, v1.2) Lock the phone mid-rest | The countdown is on the Lock Screen and stays right without opening the app |
| Q72 | manual | (D40, v1.2) The Dynamic Island | Compact, expanded and minimal all show the timer; the expanded view shows the set line and progress |
| Q73 | manual | (D40, v1.2) Live Activities turned off in iOS Settings | The app is unaffected and shows nothing on the Lock Screen |






## W. v1.3 — the Island, changing an exercise, JSON edits, history as CSV, Progression

`docs/ITERATION_4_PLAN.md` is the plan; one subsection per milestone, added as it lands.

### X1 — a narrower Dynamic Island (D41)

`JimmsBroTests/ActivityTests.swift`.

| ID | Kind | Case | Expected |
|---|---|---|---|
| W1 | unit | (D41, v1.3) `timerRange` for a rest, now and two minutes after it ended | Counts down from now to the end; once the end has passed it is a one-second range, never an inverted one |
| W2 | unit | (D41, v1.3) `timerRange` for a running open hold, and for a working state | Counts up from `startedAt` and is cut at 59:59 rather than running to the end of time; a working state has no range at all |
| W3 | manual | (D41, v1.3) The compact Dynamic Island during a rest and during a timed set | One symbol on the left, the timer on the right, no wider than a phone's own Timer; the expanded view is unchanged |

### X2 — changing an exercise mid-workout (D42)

`JimmsBroTests/ChangeExerciseTests.swift`.

| ID | Kind | Case | Expected |
|---|---|---|---|
| W4 | unit | (D42, v1.3) Change an exercise before any of its sets, with a weight | Renamed in place: same exercise count, same step order and blocks, `substitutedFor` set, every target at the new weight, the card's prefill re-read |
| W5 | unit | (D42, v1.3) Change it after one set was logged, mid-rest | A second `SessionExercise` with `replaces` pointing back; the logged step keeps the old name, the pending steps take the new one; the rest is untouched; the rows show both, named |
| W6 | unit | (D42, v1.3) The substitute has its own history | Prefill, the card's weight, "last time" and the suggestion all read the substitute's last session, not the original's and not the plan's target |
| W7 | unit | (D42, v1.3) The header after a split | Still "Exercise 1 of 3 · Set 2 of 2"; the exercise's line ends "· was Bench Press"; no row repeats it |
| W8 | unit | (D42, v1.3) Finishing the substitute at the top of the range | The substitute earns the increase; the original, with one set, earns nothing; the block-done line names the substitute |
| W9 | unit | (D42, v1.3) A superset member | Substituted alone; the group and the round are unchanged; the round's rows name all three |
| W10 | unit | (D42, v1.3) A blank name, an unknown index, a bad weight, the same name with no weight, nothing pending, a finished session | Each refused with no effects; the same name *with* a weight changes the remaining targets' weight and nothing else |
| W11 | unit | (D42, v1.3) The active session through the store's coder; a session exercise written before v1.3 | Round-trips with both new fields; the old one decodes with both nil |
| W12 | manual | (D42, v1.3) "···" → Change exercise during a rest | The sheet opens over the running rest; after Change, the card shows the new exercise with its own last time, and the rest is still counting |

### X3 — JSON edits at every size (D43)

`JimmsBroTests/JSONEditTests.swift`.

| ID | Kind | Case | Expected |
|---|---|---|---|
| W13 | unit | (D43, v1.3) Every day and every exercise of every valid fixture, rendered as a fragment and spliced back over itself | The plan renders identically — the fragment renderer and the splice are exact inverses |
| W14 | unit | (D43, v1.3) One exercise replaced from compact JSON (`"sets": 5, "reps": 5`) | Five identical sets; neighbours, days, id, import date, cycle position and anchor unchanged; the plan's text is the canonical rendering |
| W15 | unit | (D43, v1.3) An exercise whose second set differs (`sets` as a list) | The sets keep their own weight and rest, and survive the structured editor's round trip |
| W16 | unit | (D43, v1.3) A fragment with `"reps": "eight"`; not JSON; `[1, 2]`; two exercises where one goes; a day with no exercises; an index off the end | Refused with `E_REPS_INVALID` at `days[0].exercises[1].sets[0].reps` ("Day 1, exercise 2, set 1"); `E_NOT_JSON`; `E_NOT_A_PLAN`; `E_EDIT_INVALID`; `E_NO_EXERCISES`; `E_EDIT_INVALID` — and the plan untouched |
| W17 | unit | (D43, v1.3) Add exercises: one at the end, two at the start from a fenced list with prose, a day pasted as exercises, an empty list, the blank template | Added where asked; a day adds its exercises and no day; `[]` refused; the template's blank name refused with "Every exercise needs a name" |
| W18 | unit | (D43, v1.3) Add days: a bare day; a whole plan holding two days, one unnamed; to a weekday plan without a weekday, then with a free one | Appended and added to the rotation's repeat block, named "Day N" if unnamed, the pasted plan's name ignored; `E_WEEKDAY_MISSING` at `days[n].weekday`; placed on its weekday in the derived cycle |
| W19 | unit | (D43, v1.3) Replace a day renamed, and unnamed | The renamed day keeps its place in the repeat block; the unnamed one keeps its old name, with no default-name warning |
| W20 | unit | (D37, v1.3) `cycleAnchor` through a plan edit and through Replace | Kept — v1.2 dropped it in both, and the next launch re-anchored the rotation to that day |
| W21 | manual | (D43, v1.3) Plan → exercise → **Edit as JSON**, make the second set heavier, Save; then day menu → **Add exercise**, Save with the blank name | The sets show "24 / 26 / 24 kg"; the blank name is refused with a sentence and the text stays in the sheet |

### X4 — history as a file another app can read (D45)

`JimmsBroTests/HistoryCSVTests.swift`.

| ID | Kind | Case | Expected |
|---|---|---|---|
| W22 | unit | (D45, v1.3) `render` over three sessions: straight sets, one skipped set and a comma in the name, timed work | The exact header; one row per logged set, oldest first; the skipped set absent and the set order closed up; the name quoted; seconds and no reps for timed work; the unit last; "1h 5m" |
| W23 | unit | (D45, v1.3) `parse(render(history))` | The same workouts: names, starts to the second, units, every result, exercise order, duration to the minute, bodyweight where no set had a weight; and `ExerciseHistory.last` finds them |
| W24 | unit | (D45, v1.3) A Strong export, newer (comma, no unit) and older (semicolon, `Weight Unit`, `Workout Duration`) | Both read; the newer one's unit is the setting and is reported; 0 kg is no weight; "52m" and "1h 5m" become the duration |
| W25 | unit | (D45, v1.3) A Hevy export (`weight_kg`, "12 Jan 2024, 07:30", `end_time`, `set_type`, `superset_id`) | Reads in kg from the header; the duration from the end time; warm-up sets kept; columns this app has no use for ignored |
| W26 | unit | (D45, v1.3) No usable columns; an empty file; a file whose rows have a bad date, no exercise, no reps | `E_CSV_COLUMNS`; `E_EMPTY`; the good rows read and each bad one named by line (`W_CSV_ROW_SKIPPED`); a file with only bad rows is `E_CSV_NO_ROWS` |
| W27 | unit | (D45, v1.3) `new(_:against:)` and the summary | The same file twice adds nothing; the same minute with another name is new; the summary counts only what would be added |
| W28 | unit | (D45, v1.3) `Summary.text` | "2 workouts (6 sets) from Nov 12 to Nov 14 · 1 already here · weights read as kg"; one workout on one day says "on" |
| W29 | unit | (D45, v1.3) `AppModel.read(csv:)` then `importHistory` | Reading writes nothing; importing writes one file per session and no `saveFailure`; a second import adds nothing; the workout screen's prefill reads an imported session as last time; a non-history file fails with a sentence; `exportHistoryCSV` yields a file |
| W30 | manual | (D45, v1.3) Settings → **Export history (CSV)**, AirDrop it to the Mac and open it; then delete a workout in History and **Import history (CSV)** with that file | A spreadsheet shows one row per set with the columns named; the dialog says "1 workout … · N already here"; Import brings only the deleted one back |

### X5 — Progression (D44)

`JimmsBroTests/ProgressionTests.swift`; the prompt pin is in `PromptPinningTests.swift`.

| ID | Kind | Case | Expected |
|---|---|---|---|
| W31 | unit | (D44, v1.3) `weekIndex` on the start day, day 6, day 7, day 27, day 28 and the day before the start | 0, 0, 1, 3, nil, nil; `isFinished` flips on day 28; the status reads "Week 2 of 4" then "Finished" |
| W32 | unit | (D44, v1.3) `apply` for a weight-and-range week, a weight-only week, `{}`, a per-set week, and a day with no entry | Only what the week says changes; a range also sets the rep range; a bodyweight exercise takes reps and no weight; `{}` touches nothing; the per-set week leaves the third set as the plan had it |
| W33 | unit | (D44, v1.3) `Session.start` in week 2, after the last week, and for a plan without one | Week 2's targets in the snapshot and the week stamped on the exercises it touched; the plan's own targets after the last week; nothing stamped without one |
| W34 | unit | (D44, v1.3) Prefill in week 2 when last time was heavier; after the last week; a bodyweight exercise in its week | The week's weight and reps, with "Last 70 kg" still said, and the chip "Try 8 × 62.5 kg — Week 2 of 4 of your progression"; last time wins again afterwards; nothing invented for a bodyweight AMRAP |
| W35 | unit | (D44, v1.3) A fenced reply with prose, a name the plan does not have, a lower-cased match, a weight on a bodyweight exercise, an unloadable 52 kg, a short list, `null`, an unknown field and per-set values | Three entries under the plan's own names; 52 → 52.5; the material warnings are exactly unmatched, weight-ignored and short; rounding, surrounding text and the unknown field are cleanup |
| W36 | unit | (D44, v1.3) Words; the prompt itself; `weeks: 0`; nothing matching; an entry with no name; `"reps": "eight"`; reps and a duration; a bare list of numbers; a number where a week goes | `E_NOT_JSON`, `E_PROMPT_PASTED`, `E_PROGRESSION_WEEKS_INVALID`, `E_PROGRESSION_EMPTY`, `E_PROGRESSION_EXERCISE_INVALID`, `E_REPS_INVALID` at `exercises[0].weeks[0].reps` ("exercise 1, week 1"), `E_TARGET_CONFLICT`, `E_PROGRESSION_EXERCISE_INVALID`, `E_PROGRESSION_WEEK_INVALID`; and the wrapper key, an inferred period, "55 kg" and "bw" are all read |
| W37 | unit | (D44, v1.3) The prompt for a plan with one session of history, with and without history | The marker, the period three ways, the increment, every exercise of every day as one line, the history block with the sets and the advice; no fence anywhere; under the bound; no history block when off; pinned to PROMPT.md §3 |
| W38 | unit | (D44, v1.3) A plan with a progression through the store's coder; the frozen v1.2 plans file; a session with a week; a structured edit; a JSON edit; Replace | Round-trips; the old file has none; the week survives; both edits keep it; Replace drops it |
| W39 | unit | (D44, v1.3) Home in week 2, after the last week, and with no progression | "· week 2 of 4" in the subtitle; `progressionFinished` and no week afterwards; neither without one |
| W40 | manual | (D44, v1.3) Plans → a plan → **Progression**, pick 4 weeks, Copy prompt, paste it into a chatbot, paste its reply, Save; then start today's workout | The review shows every exercise's four weeks; Plan detail reads "Week 1 of 4"; Home's subtitle ends "week 1 of 4"; the first set's card shows the week's weight with the chip's reason naming the week |

## K. Persistence and recovery (SPEC §8)
| ID | Type | Case | Expected |
|---|---|---|---|
| K1 | unit | Save then load plans | Equal |
| K2 | unit | Save is atomic: temp file replaced; no partial file on simulated failure mid-write | Old file intact |
| K3 | unit | Corrupt `plans.json` (garbage bytes) | Renamed to `plans.json.corrupt-<t>`; store loads empty; `corruptFiles` reports it |
| K4 | unit | Corrupt one of 5 session files | 4 load; 1 set aside |
| K5 | unit | `fileVersion: 99` | Treated as corrupt (set aside), not crash |
| K6 | unit | Missing directory on first launch | Created |
| K7 | unit | Active session written after each event | File on disk decodes to the engine's current state |
| K8 | unit | Complete session | `active-session.json` removed; `sessions/<id>.json` exists |
| K9 | unit | Discard session | `active-session.json` removed; no session file; notification cancelled |
| K10 | unit | Dates round-trip through ISO-8601 with fractional seconds | Equal to the millisecond |
| K11 | unit | Encoder uses sorted keys | Same value → byte-identical output |
| K12 | unit | 1000 session files | Load under 1 s on simulator |
| K13 | unit | Export JSON | Contains settings, all plans, all sessions; decodes back into the same types |
| K14 | unit | Delete all data | Directory empty except nothing; in-memory state reset; active plan nil |
| K15 | unit | Two rapid writes | Serialized by the actor; last write wins; no interleaving |
| K16 | manual | Kill app mid-workout, relaunch | Resume banner with correct elapsed; Resume restores exact step and inputs' prefill |
| K17 | manual | Reinstall from Xcode over the existing app | Plans and history still present |
| K18 | unit | (D24, v1.1) `store.save(session:)` when its directory can't be created | Throws (a genuine error, not a silent no-op); succeeds once unblocked |
| K19 | unit | (D24, v1.1) A session's completion write fails (its directory blocked) | `AppModel.saveFailure == .session(that session)`; the session's id is **not** added to `persistedSessionIds`; `active-session.json` **survives**; `retrySaveFailure()` after unblocking clears the failure, persists the session and then clears `active-session.json` |
| K20 | unit | (D24, v1.1) Launch with an `active-session.json` whose `phase` is already `.completed` (a prior run's file-clear didn't finish) | The session ends up in `sessions/` (added if missing); `active-session.json` is removed; `hasActiveSession == false` — recovered, not resumed, not lost |

| K22 | unit | (D31, v1.1) Read a backup | Reports its date, app version, plan and workout counts, and how many of each a Merge would add; the store is unchanged until a mode is chosen |
| K23 | unit | (D31, v1.1) Restore with **Replace all** | The store ends holding exactly the backup: its plans, its workouts, its active plan and its settings, and nothing that was there before |
| K24 | unit | (D31, v1.1) Restore with **Merge** | Only ids not already present are added; a workout edited here since the backup was taken is left alone; the active plan and the current settings are untouched |
| K25 | unit | (D31, v1.1) A file that isn't a backup, or is from a newer app | Refused with a message before anything is written; `.notABackup` / `.unsupportedFileVersion` |
| K26 | unit | (D31, v1.1) Restore through `AppModel` | A running workout is discarded first, the store is reloaded, and the app shows what was written; an unreadable file comes back as a message and changes nothing |

## L. Plans, active plan, rotation, weekday (SPEC §6.8)
| ID | Type | Case | Expected |
|---|---|---|---|
| L1 | unit | Import into empty library | Becomes active |
| L2 | unit | Import when another plan is active | Not active until chosen (UI asks) |
| L3 | unit | Import with the same normalized name ("push pull legs" vs "Push Pull Legs") | Conflict detected; Replace keeps id and pointer-by-name; Keep both → "Push Pull Legs (2)" |
| L4 | unit | Rotation, pointer nil | Next up = days[0] |
| L5 | unit | Rotation 3 days, pointer 2 | Next up = days[0] (wrap) |
| L6 | unit | Complete days[1] when pointer was nil | Pointer = 1; next up days[2] |
| L7 | unit | Complete a day picked out of order (days[2] while next was days[0]) | Pointer = 2 |
| L8 | unit | Complete a session with skips | Pointer advances |
| L9 | unit | Discard a session | Pointer unchanged |
| L10 | unit | Complete a session whose plan was deleted | No crash; nothing updated |
| L11 | unit | Complete a session whose day name no longer exists in the plan (plan replaced) | Pointer unchanged |
| L12 | unit | Replace plan; old pointer pointed at "Pull" which is now index 3 | Pointer = 3 |
| L13 | unit | Replace plan; "Pull" gone | Pointer nil |
| L14 | unit | Weekday plan, today Wednesday, has a Wednesday day | Today = that day |
| L15 | unit | Weekday plan, today Tuesday, days Mon/Wed/Fri | "Rest day", next = Wed |
| L16 | unit | Weekday plan, today Saturday, days Mon/Wed/Fri | Next = Mon (wraps the week) |
| L17 | unit | Weekday lookup uses the device's local time zone and calendar | Test with a fixed calendar/time zone injected |
| L18 | unit | Delete plan with sessions | Sessions remain; their planName still displays |
| L19 | unit | Delete the active plan | Active becomes nil (or the only remaining plan if exactly one remains) |
| L20 | unit | Two sessions same day | Both saved and listed |
| L21 | unit | Start a day while an active session exists | Allowed only through the D17 popup; `startDay` without the flag throws `sessionInProgress` |
| L22 | unit | Cycle [P, Pu, L, P, Pu, L, rest], position nil | Next up = P (index 0) |
| L23 | unit | Position 2 (L) | Next up = P at index 3 |
| L24 | unit | Position 5 (L) | Next up = P at index 0 (rest at 6 skipped, wraps) |
| L25 | unit | Complete "Pull" from position 0 | position = 1 (first Pull after 0) |
| L26 | unit | Complete "Pull" from position 3 | position = 4 |
| L27 | unit | Complete "Legs" from position 5 | position = 2 (wraps) |
| L28 | unit | Complete a day not in the cycle | position unchanged |
| L29 | unit | Replace plan; old position pointed at "Pull", new cycle has Pull at index 4 first | position 4; Pull gone → nil |
| L30 | unit | Calendar, weekday plan Mon/Wed/Fri, month view | projected on every future Mon/Wed/Fri, ≤ 62 days ahead |
| L31 | unit | Calendar, rotation cycle with rest, position 2, today Tue | Wed = entry 3, Thu = 4, Fri = 5, Sat = rest (none), Sun = entry 0 … |
| L32 | unit | Calendar, rotation cycle without rest | only tomorrow projected |
| L33 | unit | Calendar, day with 2 completed sessions | `.completed([2 sessions])` |
| L34 | unit | Calendar, today with a completed session | `.completed`, not projected |
| L35 | unit | Calendar uses the injected today/time zone | Deterministic in tests |
| L36 | unit | (D26, v1.1) Import a second plan with the preview's activation choice off, then a third with it on | The second does not change `activePlanId`; the third does; both persist and survive reload |
| L37 | unit | (D25, v1.1) Plan detail's Replace, given a plan whose new JSON renamed it entirely | Keeps the same id (no second plan created); keeps active status if it was active; persists; a missing id is a no-op |
| L38 | unit | (D18, v1.1) Start a weekday plan's next day early from a rest day | `HomeStart` targets that day, and starting it runs that day's session |
| L39 | unit | (D29, v1.1) Edit an exercise's name, sets, reps, rep range, weight and rest | Each goes through the import pipeline; the plan keeps its id, importedAt and cycle position, and `sourceText` is regenerated so Copy JSON and the export file match |
| L40 | unit | (D29, v1.1) Reorder and delete exercises within a day | The order changes as asked; deleting leaves the rest untouched |
| L41 | unit | (D29, v1.1) Duplicate a day | A copy named "<day> copy" is inserted after it with its own ids; the cycle is deliberately unchanged |
| L42 | unit | (D29, v1.1) An edit the import pipeline would refuse | Refused with errors, and the plan is left exactly as it was — a blank name, 0 or 51 sets, unparseable reps, rest outside 0–3600, a backwards rep range, an out-of-range index, or deleting a day's last exercise |
| L43 | unit | (D29, v1.1) The reps field's vocabulary | Accepts a number, "8-12", "8–12", AMRAP, "5+", "45s", "30s+" and "open"; refuses everything else |
| L44 | unit | (D29, v1.1) An edited plan still flattens and runs | Changing the set count changes the step count by the same amount, and the session logs normally |
| L45 | unit | (D29, v1.1) `PlanEdit.text(for:)` and `parseWork` are inverses | Every `WorkTarget` prints as text that parses back to the same value, so opening the edit sheet on a timed set and saving cannot turn it into a rep set |

## M. Prompt rendering (docs/PROMPT.md)
| ID | Type | Case | Expected |
|---|---|---|---|
| M1 | unit | Render with units lb, rest 120 | `"units": "lb"`, `"defaultRestSeconds": 120`, "a number in lb" |
| M2 | unit | Rendered prompt contains marker line first | True |
| M3 | unit | Rendered prompt under 4,000 characters | True |
| M4 | unit | The JSON example inside the prompt imports cleanly through the pipeline | Zero errors, zero warnings |
| M5 | unit | Fix-it prompt with 3 errors | Three "- path: message" lines; marker present |
| M6 | unit | Fix-it prompt with 25 errors | 20 lines + "…and 5 more" |
| M7 | unit | Fix-it prompt for `E_NOT_JSON` | Includes the decoder message |
| M8 | unit | (D26, v1.1) Every error code in PLAN_FORMAT §4 has a friendly sentence | `IssueText.friendly` returns a non-empty sentence for each, distinct from the raw code, and an unknown code falls back to the importer's own message rather than to nothing |

## N. Settings, units, input parsing
| ID | Type | Case | Expected |
|---|---|---|---|
| N1 | unit | Default units by locale: en_US → lb; en_GB, de_DE, fr_CA → kg | As listed |
| N2 | unit | Weight step default: kg → 2.5, lb → 5 | As listed |
| N3 | unit | Weight text "62,5" and "62.5" | 62.5 |
| N4 | unit | Weight text "62.55" | 62.6 on commit |
| N5 | unit | Weight text "abc", "1.2.3", "-5" | Rejected (field keeps last valid) |
| N6 | unit | Reps text "1000" (4 digits) | Truncated to 3 digits by the field |
| N7 | unit | Weight − from 2.5 with step 2.5 | 0; − again stays 0 |
| N8 | unit | Default rest setting 0 | Allowed; plans without rest get 0 |
| N9 | unit | Changing units setting after plans exist | Existing plans unchanged; only the prompt and unit-less future imports change |
| N10 | unit | Settings file missing | Defaults used and written |
| N11 | ui | (D26, v1.1) Import preview's "Set as current plan" toggle | Present and on by default when another plan is already active; hidden during Plan detail's Replace (which already preserves active status) |

## O. UI, accessibility, device (mostly manual)
| ID | Type | Case | Expected |
|---|---|---|---|
| O1 | ui | Empty Home | Two buttons; "Try the sample plan" imports and activates the sample |
| O2 | ui | Import screen Paste with text on clipboard | Editor filled |
| O3 | ui | Paste with an image on clipboard | Nothing happens; PasteButton disabled or no-op |
| O4 | ui | Import error list | Each row shows path, message, code; Copy fix-it button present |
| O5 | ui | Preview shows warnings in yellow and day table | Correct counts |
| O6 | ui | Name conflict dialog | Replace / Keep both / Cancel work |
| O7 | ui | Step card renders every target kind | "8–12 reps @ 60 kg", "10 reps (range 8–12) @ 60 kg", "AMRAP", "10+ reps", "45 s" |
| O8 | ui | Log set with empty reps | Button disabled |
| O9 | ui | Step card order and fit: name, target, last-time (bold entry), reps row, weight row + Last/Suggested line, Log set; all visible above the keyboard on an iPhone 15/16 at default text size | True; Log set never hidden by the keyboard |
| O9b | ui | Tapping the reps number opens the number pad; tapping the weight number opens the decimal pad; ± buttons don't open a keyboard | True |
| O9c | ui | Rest overlay shows workout elapsed; after an exercise's last set it also shows "Bench Press done · 9:40" and the advice line | True |
| O9d | ui | Overview list shows duration and advice on finished exercises | True |
| O9e | ui | Summary per exercise shows duration, this vs last, advice | True |
| O29 | ui | Home shows exactly three things: start card, calendar, sparkline; tab bar has four tabs | True; no other controls |
| O30 | ui | Calendar dots: filled accent for completed, hollow accent for projected, grey for a scheduled rest day, none for a day the plan says nothing about; today outlined | True; tapping a dotted day shows one line beneath |
| O31 | ui | Sparkline is ≤ 44 pt tall, no axes, one caption line; tapping it changes the metric and caption | True |
| O32 | ui | Done screen after an exercise: block name, duration (largest), advice, running stopwatch, one Continue button | True; no countdown, no sound, no notification |
| O33 | manual | Lock the phone on the done screen for 5 minutes | Nothing fires; on unlock the stopwatch reads ~5:00 |
| O34 | ui | Drop step card shows "Set 2 of 3 · drop 1 of 2" and weight prefilled from the previous step | True |
| O35 | ui | Plan detail shows the repeat block chips with the current position highlighted and "repeats every N days" | True |
| O36 | ui | Start another day mid-session | Popup with Keep going (default), Finish X and start Y, Discard X and start Y |
| O37 | ui | Step card has no visible label text other than exercise name, set line, target, last-time, and the "kg" suffix; secondary actions only in "···" | True |
| O38 | ui | Preview sheet shows cycle chips | True |
| O39 | ui | Bodyweight exercise step card | No weight row; card is shorter; Log set still under the reps row |
| O40 | ui | Open-duration card: 0:00 large, Start; running: counting up, Stop | Stop logs; the "30+" minimum turns the number accent at 30 |
| O41 | ui | Fixed-duration card: 0:45 large, Start; running: countdown, Done | Number turns accent at the warning; at zero: final beep, auto-log, rest |
| O42 | ui | Rest overlay top line shows "set 0:34" after a rep set | True |
| O43 | ui | Overview and session detail show set time per logged step | "10 @ 60 · 0:34" |
| O44 | ui | (v1.1) Tap a completed calendar day, then tap it again | First tap shows the summary line; second tap opens that session's detail |
| O45 | ui | (v1.1) Tap-then-tap-again a day with two completed sessions | A chooser lists both by day name and time; picking one opens it |
| O46 | ui | (D27, v1.1) Overview: tap a skipped row | Offers **Do this set** (jumps to it, cancelling rest/blockDone) and **Add result** (opens the edit sheet); saving through Add result survives reopening the session |
| O47 | ui | (D25, v1.1) Swipe-to-delete in Plans and History, and Plan detail's Delete | Every path confirms with one dialog before deleting; cancelling leaves the row untouched |
| O48 | ui | (D14, v1.1) After a block finishes, no full-screen "done" gate appears | The next step's card shows immediately, with a dismissible banner naming the finished block, its duration and any advice — a temporary placeholder for R2's status strip |
| O49 | ui | (D23, v1.1) The workout's "···" menu after logging a set | Offers **Undo last set**, which restores it to pending with its inputs re-prefilled; the item is absent once another set is logged or the session is completed — a temporary placeholder for R2's "Set logged · Undo" strip |
| O10 | ui | Overview list statuses and tap-to-edit / tap-to-jump | Work as SPEC 4.4 |
| O11 | ui | Finish with pending sets | Confirmation names the count |
| O12 | ui | Finish with nothing logged | "Nothing was logged. Discard?" |
| O13 | ui | Summary comparison lines | Match J25's sentences; the set-by-set table appears only when the weights varied |
| O14 | ui | History grouping by month, newest first | Correct |
| O15 | ui | Edit a value in a past session | Saved; volume updates; prefill next time uses it |
| O16 | ui | Exercise history reachable from step card, session detail, and summary | All three |
| O17 | ui | Dark mode | All screens legible; timer colors distinct |
| O18 | ui | Dynamic Type at accessibility XL | Log button still on screen; no text clipped |
| O19 | ui | VoiceOver reads step card as one element and announces "Rest over" | True |
| O20 | manual | Screen stays awake during workout; turns off normally after Done | True |
| O21 | manual | Keep-awake setting off | Screen locks per system setting |
| O22 | manual | Rotate the phone | Stays portrait |
| O23 | manual | Sweaty-thumb test: all workout controls ≥ 44 pt and reachable one-handed | True |
| O24 | manual | Free-account 7-day expiry: app refuses to open after a week | Re-run from Xcode restores it with data intact |
| O25 | manual | Full end-to-end: copy prompt → ChatGPT → paste → import → 3-exercise workout with a superset and a plank → summary → history | Works without touching a keyboard except reps/weight |
| O26 | manual | Chatbot output truncated (long weekly plan) | `E_NOT_JSON` with "end of file" message; fix-it prompt gets a complete plan back |
| O27 | manual | Chatbot added `rpe` and `tempo` fields | Imports with warnings, no errors |
| O28 | manual | Chatbot wrote weights as "60kg" strings | Imports; no warning if unit matches |
| O50 | unit | (D22, v1.1) `WorkoutScreen.model` in the working, resting, timed-running and block-done states | The five zones — header, exercise, inputs, strip, primary — are present in that order in every one of them; only their contents differ |
| O51 | unit | (D22, v1.1) Log a set while the previous set's rest is still running | The set logs, the rest ends, its notification is cancelled, and the following step becomes current |
| O52 | unit | (D23, v1.1) Undo from the status strip | The row goes back to pending, `canUndo` becomes false, and the values that had been logged are handed back so the inputs come back filled |
| O53 | ui | (D22, P2, v1.1) Open **Exercises** while resting, and again while a block-done strip is showing | The overview opens in both; the header's Exercises, minimize and "···" are present in every state |
| O54 | unit | (v1.1) Minimize mid-rest, then Resume | Same step, same prefilled inputs, and rest remaining derived from `endsAt` rather than from a counter that stopped |
| O55 | ui | (P6, v1.1) Keyboard raised over the reps or weight field | A **Done** toolbar item dismisses it, and the primary button sits above the keyboard, not behind it |
| O56 | ui | (P5, v1.1) The input rows | Small-caps **REPS** and **KG**/**LB** labels are visible, and VoiceOver reads each field with that label |
| O57 | unit | (D22, v1.1) `StepCard.setRows` for the current exercise | Finished rows carry what was logged, the current row is flagged with its target and last-time value, upcoming rows carry targets; a superset lists only the current round's members |
| O58 | unit | (D14, v1.1) Run a whole multi-exercise day through, logging every set | The session completes without `dismissBlockDone` ever being applied and without entering any phase but working and resting — zero Continue taps |
| O59 | unit | (v1.1) `.logged` feedback on Log set | Played exactly once per logged set, and not for an edit, a skip, or an input the engine rejected |
| O60 | ui | (P6, v1.1) The workout screen at accessibility XL | No zone clipped or pushed off screen; the input numbers keep their size; the layout reflows around them |
| O61 | unit | (D14, v1.1) The status strip once a block ends | Names the finished block with its duration, carries that exercise's advice, and reports the count-up "moving on" time |
| O62 | unit | (D20, D22, v1.1) A timed set's primary action | **Start timer**, then **Done** (fixed) or **Stop** (open), in the same bottom slot the reps sets use; the timer replaces the reps row and the weight row stays |

| O63 | unit | (D18, v1.1) `HomeStart.current` for every schedule state | Rotation and weekday name the day and the plan and read "Start &lt;day&gt;"; a rest day reads "Rest day", says which day is next, and offers "Start &lt;day&gt; early"; a running session reads "Resume &lt;day&gt; · N min"; no plan reads "No plan yet" with **Add plan** |
| O64 | unit | (D18, v1.1) The start card's exercise preview | Names the day's first five exercises and counts the rest as "and N more"; the subtitle carries the plan name, the exercise count and "N min last time", each only when it has data |
| O65 | unit | (D18, v1.1) `CalendarProjection.week(containing:)` | Seven days of the calendar week containing today, with the same entries the month grid gives, including across a month boundary |
| O66 | unit | (D18, v1.1) `HomeActivity.line` | "2 workouts this week · 1 h 32 min"; a week with none reads "No workouts yet this week"; only completed sessions count |
| O67 | ui | (D26, v1.1) Add plan's three rows | Paste plan, Create with a chatbot (three numbered steps), Import file; the JSON editor is behind "Show text" and starts collapsed |
| O68 | unit | (D26, v1.1) The review sheet's day rows | Each day expands to its exercises with per-set targets — "3 × 8–12 · 24 / 26 / 28 kg" rather than the first set repeated |
| O69 | unit | (D26, v1.1) Warning classification | A dropped unit, a removed load, a changed grouping and an inferred schedule are material; curly quotes, unknown fields, truncated names and rounded weights are cleanup, and go behind "Details (n)" |
| O70 | unit | (D26, v1.1) An import error | `IssueText.friendly` leads with a sentence naming where it is ("Day 1, exercise 2, set 2 needs either a rep target or a duration."); path, code and the importer's own message stay behind Details |
| O71 | unit | (D26, v1.1) The practice plan | `PracticePlan.json` imports through the normal pipeline with no errors, three exercises, one bodyweight, 60 s rest, and becomes active |
| O72 | ui | (N12, v1.1) Copy prompt | The button reads "Copied" and goes back to "Copy prompt" about two seconds later, without needing another tap |
| O73 | ui | (P6, v1.1) Calendar cells | Every cell is at least 44 pt in the week strip and the month grid alike |
| O74 | unit | (v1.1) The Summary's headline line | "Push · 48 min · 16 of 18 sets · Volume 12,400 kg"; the volume fragment is omitted entirely when it is zero (a bodyweight day) |
| O75 | ui | (v1.1) The Summary | Leads with "Workout saved"; one sentence per exercise; set durations only under **Details** |
| O76 | unit | (v1.1) Plan detail's exercise rows | Show per-set variation via `TargetText.summary` rather than the first set repeated |
| O77 | ui | (v1.1) One list style per screen | Home, the workout screen, Add plan, the review sheet, Plans, Plan detail, History, Session detail and Settings all use the same grouped/inset list idiom and the same 20 pt horizontal margin |
| O78 | ui | (v1.1) The stepper buttons and set rows | Show a pressed state; done rows use the reserved green, not the accent blue |
| O79 | ui | (D28, v1.1) "Do later" in the workout menu | Present only when it would move something; the deferred exercise appears at the end of the Overview and comes round again later in the workout |
| O80 | ui | (D29, v1.1) Plan detail's edit affordances | Tapping an exercise opens the edit sheet; Edit reorders and deletes; the day header's menu renames and duplicates; a refused edit says why |
| O81 | ui | (D30, v1.1) The exercise chart and PR badges | The chart draws top weight over time with reps annotated when there are two or more weighted sessions; a PR badge shows on the Summary and in session detail, in the reserved green |
| O82 | ui | (D31, v1.1) Settings → Import backup | Names the backup's date and counts, says what Merge would add, and offers Merge / Replace all / Cancel; a file that isn't a backup says so and changes nothing |

`ITERATION_2_PLAN.md` §R2 proposed these as O48–O60. O48 and O49 were already taken by R1's
placeholder rows above, so the R2 block runs O50–O62 instead; the order is otherwise the plan's.
§R3 proposed O61–O70 and they follow at O63–O73 for the same reason. L38, M8 and N12 kept their
proposed ids; N12 is covered by O72 above, and M8 and L38 sit in their own sections.
`````

---

### FILE: docs/BUILD_PLAN.md

`````markdown
# Build plan

Milestones in order. Each ends with its tests green. Don't start UI before the Core logic for it is tested.

## M0 — Project skeleton (½ day)
- Xcode project `JimmsBro` in this folder: iOS App, SwiftUI, Swift, iOS 17.0 deployment target, iPhone only, portrait only.
- Groups: `Core/` (no UI imports), `Store/`, `Features/` (one folder per screen), `Resources/` (SamplePlan.json = `examples/valid/weekly-rotation.json`, beep sound).
- Unit test target `JimmsBroTests` with a helper that loads `examples/` fixtures and `manifest.json` (add the `examples` folder to the test bundle as a folder reference).
- `xcodebuild test -scheme JimmsBro -destination 'platform=iOS Simulator,name=iPhone 16'` runs green with one placeholder test.
- Capabilities: none needed. Add `NSUserNotificationsUsageDescription`? Not required for local notifications; no Info.plist keys needed except none. Background modes: none.

## M1 — Core: plan model + import pipeline (1–2 days)
- Types from SPEC §7. Import pipeline SPEC §6.1 as four functions. Issue codes from PLAN_FORMAT §4.
- Tests: A, B, C, D, plus D8/D9 driven by the manifest.
- Done when every fixture matches the manifest and all A–D unit tests pass.

## M2 — Core: steps, rest, engine, prefill, stats, prompts (1–2 days)
- `flatten(day) -> [Step]` (SPEC §6.2). `SessionEngine` (SPEC §6.6) with effects, injected `now`. Prefill and last-time (SPEC §6.5). Stats, exercise duration and `ExerciseHistory.series` (SPEC §6.7). Progression advice (SPEC §6.11). Cycle/weekday helpers (SPEC §6.8), calendar projection (§6.12), sparkline points (§6.13). Prompt rendering (PROMPT.md).
- Tests: E, F, G, I, J, L, M, P, S.

## M3 — Store (½–1 day)
- `Store` actor, file layout SPEC §8, atomic writes, corrupt-file handling, export document.
- Tests: K1–K15 using a temp directory injected into the store.

## M4 — Plan library + Import UI (1 day)
- Tab bar. Home (start card, calendar, sparkline; no workout yet), Plans list, Import screen with Paste / Copy prompt / Import, error list with Copy fix-it, Preview sheet, conflict dialog, Plan detail with the repeat block, Settings (units, default rest only for now), sample plan. Follow SPEC §4.0 quiet rules.
- Tests: O1–O6 (UI), N1–N2, N8–N10.

## M5 — Workout UI + rest timer + notifications (1–2 days)
- Workout screen, step card in the exact order of SPEC §4.4 (Log set directly under the weight row, above the keyboard), inputs (SPEC §6.10), bold last-time entry, Last/Suggested line and chip, rest overlay, the between-exercises done screen with count-up stopwatch and Continue, the switch-day popup, overview list, fixed and open timed sets with the warning and final beeps (two notification ids, `warning.caf` bundled), set timing, summary, resume banner and discard, keep-awake, notification scheduling via a `NotificationScheduler` protocol (mockable), audio via `AlertPlayer`.
- Tests: H1, H2, H17, N3–N7, O7–O13. Then the manual H checklist on a physical phone.

## M6 — History (½–1 day)
- History list, session detail with editing and delete, exercise history with best set.
- Tests: O14–O16, I19–I20 covered by Core already.

## M7 — Polish (½ day)
- Remaining Settings rows (sound, vibration, notifications state, keep awake, weight step, export, delete all, about). Dark mode pass, Dynamic Type pass, VoiceOver labels, app icon, launch screen.
- Tests: O17–O19; manual O20–O28.

## M8 — Device checklist (owner + agent together)
Run every `manual` case in TEST_CASES.md on the owner's iPhone. Log results in `docs/DEVICE_CHECKLIST.md`.

## Device: installing on the owner's iPhone (owner does this once)
1. Xcode → Settings → Accounts → add your Apple ID.
2. Project → Signing & Capabilities → Team = your personal team; "Automatically manage signing" on. Bundle identifier must be unique, e.g. `com.<yourname>.jimmsbro`.
3. iPhone: Settings → Privacy & Security → Developer Mode → on (restarts the phone).
4. Plug in the iPhone, tap "Trust this computer", pick the phone in Xcode's run destination, press Run.
5. First launch on the phone: Settings → General → VPN & Device Management → trust your developer certificate.
6. Free account: the build expires after 7 days; just press Run again with the phone plugged in. Data survives. Paid account ($99/yr): builds last a year and TestFlight becomes available.

## Simulator note for the agent
The simulator can't do notifications-while-locked, real haptics, or the silent switch. Everything in the manual column must be verified on the phone; everything else should be verified on the simulator before handing over.
`````

---

### FILE: docs/ITERATION_2_PLAN.md

`````markdown
# Iteration 2 — the refinement release (v1.1)

Written 2026-09-05 from SPEC v1, the current code (M0–M7, 97 tests green), `docs/UX_REVIEW.md`, and a second
independent review that drove the app in the simulator. This is a proposal. Nothing in it is accepted until
SPEC §1 and the relevant sections are amended; the docs stay the contract for whichever agent builds it.

## 0. One paragraph

v1.1 adds almost no capability. It makes the five things you do every session effortless: start the
intended workout, log a normal set in one tap, fix the last set while the rest runs, see what is left,
and minimize and come back without losing your place. It also stops the app from ever looking like it
did something it did not. Visual polish comes last and is applied to a layout that has stopped moving.

## 1. Principles for this release

Each principle is a rule the implementing agent can check, not a mood.

| # | Principle | Rule for this app | Source |
|---|---|---|---|
| P1 | One layout per task | Logging, resting and timed work share one screen with fixed zones. The primary button never changes position. | HIG consistency; NN/g heuristic 4 |
| P2 | Never hide what the task needs | Exercises (overview), undo, skip and finish are reachable in every workout state, including rest. | NN/g on minimalism: remove decoration, not task content |
| P3 | Undo beats confirmation for frequent reversible actions; concise confirmation for irreversible ones | Log set gets Undo. Deletes confirm, consistently, everywhere. No dialog on the happy path. | NN/g heuristic 3 (user control and freedom); HIG |
| P4 | Never report success that did not happen | A Save that changes nothing is a bug. A failed write shows Retry and keeps the data. | NN/g heuristics 1 and 9 |
| P5 | Label what the value does not explain | `10` and `80` get "Reps" and "kg" labels. A volume number is labelled Volume. Units alone are not labels. | Recognition over recall |
| P6 | Reachable and accessible by default | Primary action bottom-anchored above the keyboard; keyboard has Done; every target ≥ 44 pt; Dynamic Type reflows rather than shrinking numbers. | Apple design tips; HIG Dynamic Type |
| P7 | Docs first, Core first, green per milestone | Amend SPEC and TEST_CASES before code. Core logic tested before any view. No milestone is done without running the tests. | CLAUDE.md, unchanged |
| P8 | Judge by tasks, not taste | §6 lists the acceptance tasks. A milestone passes when the tasks pass on the phone. | Usability testing practice |

Where SPEC v1 §4.0 conflicts with P2 or P5 (the "no labels" and "one primary action, everything else in ···"
rules), §4.0 is rewritten in R2. Both reviews independently reached that conclusion.

## 2. What the two reviews agree on, and the one fork

Consensus (both reviews, confirmed against the code on 2026-09-05):

- Rest and the between-exercise "done" screen replace the workout instead of sitting inside it. During rest the
  `···` menu is gone (it belongs to `StepCardView`), so overview, skip, finish and corrections are unreachable.
- The "done" screen is a mandatory tap between every pair of exercises and makes the block duration the
  largest thing on screen.
- No undo exists anywhere. Correcting a typo is Skip rest → ··· → Overview → row → sheet → Save.
- The two input rows are unlabelled.
- Log set floats mid-screen with over half the screen empty below it; no keyboard dismissal; no haptic on log.
- Editing a skipped set through the overview or session detail silently does nothing (`SessionEngine.editSet`
  returns early unless the step is logged; both views open the sheet anyway).
- Save failures are swallowed (`try?`), and `persistCompletedSessions` marks a session persisted before its
  write is known to succeed.
- Carry-forward prefill overrides explicitly varied targets (50 → 60 → 70 kg prefills 50 for set 2).
- Home spends its space on a month of projected dots and a hidden tap-to-cycle sparkline while saying nothing
  about the workout behind Start; calendar taps do not open the session.
- Import reads as a data-file editor; the preview cannot show whether the chatbot produced the right exercises;
  a second import never offers to become active; Plan detail's specified Replace action is missing.
- Deletion asks for confirmation in one place and deletes directly in three others.
- The app speaks two visual languages (bare stacks on Home and Workout; grouped lists elsewhere).
- New features should be few: the per-exercise chart, "Do later", basic plan editing, backup restore.

The fork: **what the workout screen is.**

| Option | Shape | Pros | Cons |
|---|---|---|---|
| A. Stable step card (review 1) | Current exercise expanded with its set rows, inputs and action in fixed slots; rest as a strip inside the same screen; an Exercises button opens the full overview as a sheet | Keeps the guided one-tap model that is this app's reason to exist (D1, D11, D19); presentation-only refactor, engine phases largely intact; less scrolling with a bar in one hand | You still open a sheet to see the whole day |
| B. Full scrolling list (review 2) | The overview becomes the main screen: every exercise, every set row, logging in place; rest as a bottom bar | Industry pattern (Strong, Hevy); the whole workout is always visible | Changes the product model from "runs your workout" to "a list you fill in"; more to rebuild; the one-tap prefilled log is easier to lose in a long list |

**Recommendation: A**, with the full overview one visible tap away at all times. A is what the owner asked
for in spirit (quiet, guided) with the context and controls that were missing. If A still feels cramped after
the R2 walkthrough on the phone, B is a presentation change on the same Core and can be revisited.

Second, smaller fork: **what happens between exercises.** Review 1 keeps D14's "no alert, you decide when
you've walked over" and only removes the tap. Review 2 runs a real rest countdown with an alert between
blocks. Recommendation: review 1's version, because D14's rationale was the owner's and still holds; the
alerting variant is listed under Later.

## 3. Decisions to re-open (SPEC §1)

Amend the table in SPEC §1 before any R1/R2 code. Proposed text:

| # | Now | Proposed | Why |
|---|---|---|---|
| D11 | Prefill carries the current session's last weight forward; changing the weight re-prefills reps | Carry-forward applies only to **straight** exercises (all main-set target weights equal or absent). For **varied** exercises (targets differ across sets) prefill is: last session at the same set index → the set's target → empty. Reps initialize once per step and are never rewritten by a weight change. | A pyramid should look like a pyramid after set 1. Predictable beats clever. |
| D14 | Between exercises: full-screen done screen, count-up stopwatch, Continue | Between exercises the next set's card appears **immediately**. A status strip shows "Bench Press done · 9:40 · try 82.5 kg next time" and a small "moving on 0:42" until the next log. No alert, no countdown, no Continue. | Removes one tap per exercise and keeps context; keeps D14's "you decide when to move" rationale. |
| D18 | Home is one Start card, a month calendar, a tappable sparkline | Home leads with the workout: day name, plan, exercise preview, and a button that names the action ("Start Push", "Start Pull early", "Resume Push · 23 min"). A week strip expands to the month. One activity line ("2 workouts this week") replaces the sparkline. | Start is currently blind. Hidden tap-to-cycle is not quiet, it is undiscoverable. |
| D19 | Every set is timed; shown after the fact | Unchanged in storage. Set durations are shown only in the overview rows, session detail and Summary details, never as a hero number and not on the rest strip. | Rep-set timing includes walking and fiddling; it must not outrank a deliberately timed plank. |
| D22 (new) | — | The workout is **one screen with fixed zones**: header, exercise block with the current exercise's set rows, labelled inputs, status strip, bottom-anchored primary action. Working, resting, timed and between-exercise states change the strip's contents, never the zones. | P1, P2. |
| D23 (new) | — | **Undo** after Log set and Skip set, available until the next log/skip, while the rest keeps running. | P3. |
| D24 (new) | — | A failed write is **shown** with Retry and never marks the data as saved. A completed session that could not be written stays in `active-session.json` and is recovered on the next launch. | P4. |
| D25 (new) | — | Every delete of a plan or session **confirms** with one concise dialog; Delete all data keeps its explicit confirmation. No silent swipe-deletes. | Consistency; file deletion has no undo stack. |
| D26 (new) | — | Plans arrive through **Add plan**: Paste plan, Create with a chatbot (three numbered steps), Import file. The JSON editor is a detail, not the front door. The review step shows the actual exercises and targets, plain-language errors first, and a "Set as current plan" choice. | The chatbot round-trip is the product's premise and the screen never explained it. |
| D27 (new) | — | Skipped sets can be **recovered**: "Do this set" (jump back) or "Add result" (log after the fact). Both work in the live overview and in history. | The current sheet's Save is a no-op. |

§4.0 is rewritten in R2 to: one primary action per screen, bottom-anchored; secondary actions may be visible
buttons when a task needs them during the primary task (Exercises, Undo, rest ±30); labels are allowed where a
value does not explain itself; no decorative dividers, badges or cards-in-cards; large numbers only for values
you act on right now (the input values, a running countdown).

## 4. Scope

**In**, in this order: R0 truthfulness, R1 Core for the new loop, R2 workout screen, R3 Home and Add plan,
R4 visual system and Summary, R5 narrow additions, R6 device checklist v2.

**Out** of v1.1 (stays in SPEC §10): Live Activity, Apple Watch/Health, sync, in-app chatbot, social,
badges/streaks, nutrition, recovery scores, themes, an analytics dashboard, plate math, warm-ups, session
notes, automatic progression, the compact text plan format, localization, iPad, landscape. Also out: the
"real rest with alert between exercises" variant, and a "Start set" tap for exact rep timing.

**Preserved untouched**: local files, no accounts, Date-based timers, per-event persistence of the active
session, the import pipeline and every fixture in `examples/`, supersets, drops, timed sets with warning
beeps, bodyweight, progression advice, export, the four tabs.

## 5. Milestones

Sizes are relative to BUILD_PLAN's, for one agent. Each milestone: amend docs → Core → tests green → UI →
simulator screenshots into `build/` → DECISIONS_LOG entries. New test IDs continue TEST_CASES numbering
(G49+, I35+, K18+, L36+, M8+, N11+, O44+, J25+, F15+, H24+).

### R0 — Truthful behavior and finished workflows (½–1 day)

No layout changes. Everything here is "the app already claims to do this."

Docs first: SPEC §8.3 gains a "Writes that fail" paragraph (D24); §4.4 gains the activation choice; §4.8 and
§4.10 gain "Add result" for skipped sets (D27); D25 added. §4.1's "tap again → session detail" and §4.3's
Replace are already specified; those are bugs.

Core / Store:
- `SessionEngine.editSet` accepts a **skipped** step: result set, status → logged, `loggedAt` set if nil,
  advice recomputed, no phase change, no timer. `PlanLibrary.editSession` does the same for history.
- `jumpTo` on a skipped step resets it to pending before entering working (so "Do this set" is a plain jump).
- `AppModel` gets `saveFailure: SaveFailure?` (what failed, the error, a retry). Every `try?` around
  `store.save`/`deleteSession`/`clearActiveSession` becomes a caught error that sets it.
- `persistCompletedSessions` inserts an id into `persistedSessionIds` only after the write succeeds, and
  clears `active-session.json` only when every completed session is on disk. On launch, an active session
  whose phase is `.completed` is written to `sessions/` and cleared (recovery).
- `AppModel.save(plan, makeActive:)` is driven by the user's choice from the preview.

UI:
- Import preview: a "Set as current plan" toggle, default on. Plan detail `···` gains **Replace**
  (opens Add plan targeting this plan's id; saving replaces it and keeps it active if it was).
- Home calendar: tapping a completed day opens the session (a short chooser when a day has two); a projected
  today keeps "Start this"; rest days keep the line.
- Overview and Session detail: skipped rows show **Do this set** (live only) and **Add result**.
- Deletes: swipe-to-delete in Plans and History and the Plan detail menu confirm ("Delete Push Pull Legs?").
- A save-failure alert: "Couldn't save the workout. It's still here; try again." **Retry** / **Later**.
  Retry is also attempted automatically on the next successful write and on launch.

Tests: G49 editSet on skipped → logged, loggedAt set, advice recomputed, no timer effects; G50 jumpTo skipped
→ pending then working; K18 `save(session:)` throws → id not in persisted set, active file kept, Retry
succeeds and clears it; K19 launch with a completed active session → moved to `sessions/`; K20 plans write
failure surfaces `saveFailure`; L36 import with makeActive on/off; L37 Replace from Plan detail keeps id and
active state; N11 activation toggle default; O44 calendar tap opens the session; O45 two sessions on one day
→ chooser; O46 Add result on a skipped row survives reopening; O47 every delete path confirms.

Exit: the three silent no-ops (skipped edit, failed save, second import not active) are gone; the suite is
green on the iPhone 16 simulator.

### R1 — Core for the new workout loop (1–2 days)

Same branch as R2, but its tests go green first and the app must still build at the end (TransitionView
deleted, a temporary banner in its place).

Docs first: D11, D14, D19, D22, D23 in §1; §4.5–§4.8 replaced by one "Workout screen" section (written
now, built in R2); §6.3 block-end rule; §6.5 prefill precedence and removal of the dynamic reps rule;
§6.6 events; §7 `ActiveSession`. TEST_CASES F7/F9, G-section rows that assert `.transition`, and I-section
rows that assert carry-forward on varied targets are rewritten deliberately, with the old expectation noted.

Core:
- **Block end**: `.transition` phase removed. After the last step of a block, phase → `working(next)`
  immediately and `ActiveSession.blockDone: BlockDone?` records `(finishedBlock, at, nextStep, advice)`.
  Cleared by the next log, skip, jump or an explicit `dismissBlockDone` event (replaces
  `continueTransition`). Persisted, so Resume shows the strip with the right "moving on" time. A v1
  `active-session.json` holding `.transition` decodes into `working(nextStep)` + `blockDone`.
- **Undo**: `undoLog(step)` is valid only for the most recently logged or skipped step and only if nothing
  was logged after it. It restores pending, clears result and `loggedAt`, sets `startedAt = now`, clears
  `blockDone`, cancels the rest notification, recomputes the exercise's advice, and enters `working(step)`.
  Not available once the session is completed (history editing covers that). The UI captures the logged
  values before applying so the inputs come back filled.
- **Prefill** (§6.5 revised): `SessionExercise.hasVariedTargets` (main-set target weights not all equal).
  Varied → last session at the same set index → target → empty. Straight → unchanged. `RepsDraft.changeWeight`
  removed; reps initialize once per step.
- **Progress text**: `StepCard.progress` → "Exercise 2 of 5 · Set 2 of 3", "· drop 1 of 2",
  "A · round 2 of 3 · Incline Press" for superset members. The header's "Set 5 of 22" (which counts drops)
  is replaced by this.
- **Set rows**: `StepCard.setRows(session, step, history) -> [SetRow]` — for the current exercise (or the
  current superset round's members): set number, status, logged text ("10 @ 80"), target text, last-time
  text, `isCurrent`. Pure and tested; the view only renders it.
- **Strip text**: `StepCard.blockDoneLine` → "Barbell Bench Press done · 9:40 · try 82.5 kg next time".
- `AlertPlaying` gains a `.logged` feedback kind so the haptic on Log set is testable through the protocol.

Tests: F15 block end → working(next) + blockDone, no notification; G51 blockDone cleared on the next log;
G52 dismissBlockDone; G53 old `.transition` file decodes; G54–G58 undo: valid on the latest step, no-op after
a later log, cancels the rest notification, restores pending and clears advice, works after skipSet and for a
drop step; G59 undo is a no-op when completed; I35 50/60/70 kg → set 2 prefills 60 after logging 50;
I36 straight sets still carry forward; I37 varied with last-session history at index k; I38 reps not rewritten
on weight change; I39 setRows for straight, superset and drop cases; I40 progress text; K21 `blockDone`
round-trips.

Exit: both runners green (`xcodebuild test` and `python3 tools/check_core.py`).

### R2 — Workout screen rebuild (2–3 days)

Docs first: the new §4.5 "Workout screen" (written in R1) is the contract; §4.0 rewritten as in §3 above.

Zones, top to bottom, identical in every state:

1. **Header**: elapsed · progress ("Exercise 2 of 5") · **Exercises** (opens the overview sheet) ·
   **minimize** (chevron) · `···` (Skip set, Skip exercise, Finish workout). Rename exercise leaves the
   mid-workout menu; it stays in Session detail.
2. **Exercise block**: name (link to history), target line with notes, then the current exercise's set rows
   from `setRows`: done rows "✓ 10 @ 80", the current row highlighted with its target and last-time value,
   upcoming rows with targets. Tap a done row → edit sheet; tap an upcoming row → jump. Supersets list the
   round's members. "Last time" appears once, in the rows, not as a separate line and a "Last 80 kg" line.
3. **Inputs**: small-caps labels **REPS** and **KG/LB** above the values; − value +; weight row hidden for
   bodyweight; "82.5 suggested" chip under the weight. Timed sets show the timer in the reps slot; the weight
   row stays. Numbers keep one size across Dynamic Type; the layout reflows instead.
4. **Status strip** (always present, may be empty): during rest a progress line, `2:26`, −30 / +30, Skip,
   and "Set logged · **Undo**" for the rest duration; at zero "Rest over · +0:12" until the next log;
   between blocks the blockDone line and "moving on 0:42"; for timed sets the running/warning state.
5. **Primary action**: bottom-anchored with `safeAreaInset`, above the keyboard, full width. Reads
   **Log set** in working and resting states (logging during rest ends the rest), **Start timer** /
   **Done** / **Stop** for timed sets. A keyboard toolbar with **Done**; `.success` haptic on log.

Minimize dismisses the cover; Home shows "Push in progress · 23 min" with Resume; timers and notifications
keep running (already Date-based); Resume returns to the identical state. The overview sheet keeps its
current content and is reachable from every state.

Tests: O48 zones present and in the same order in working, resting, timed and between-block states;
O49 Log set during rest logs and ends rest; O50 Undo restores the inputs and the row; O51 Exercises opens
during rest; O52 minimize then Resume restores step, inputs and rest remaining; O53 keyboard Done dismisses;
O54 labels present and read by VoiceOver; O55 set rows: done/current/upcoming; O56 six-exercise day needs
zero Continue taps; O57 `.logged` feedback recorded once per log; O58 accessibility XL: no clipped zone,
numbers unchanged in size; O59 the strip between blocks shows advice and moving-on time; O60 timed set uses
the same primary slot. Manual H24: minimize, lock, rest notification fires, Resume.

Screenshots `build/o9-*`, `o9c-*`, `o32-*` replaced. Exit: the owner runs the sample Push day on the iPhone
and tasks T2–T6 in §6 pass without coaching.

### R3 — Home and Add plan (1–2 days)

Docs first: §4.1 (D18 revised), §4.2, §4.4 (D26), §5.1, §5.2, §6.13 removed or moved to History.

Home:
- Start card: "**Push**", "Push Pull Legs · 5 exercises · 48 min last time" (each fragment only when it has
  data), the first five exercise names, then **Start Push** / **Resume Push · 23 min** / on a rest day
  "Rest day · Pull is next" with **Start Pull early**. "Preview" opens the day in Plan detail; "Another day"
  opens a compact chooser.
- A 7-day strip with today's dots and a disclosure to the month grid; cells ≥ 44 pt; taps behave as in R0.
- One line, "2 workouts this week · 1 h 32 min". The sparkline and the home-metric setting are removed
  (`Sparkline` and `HomeMetric` code deleted; `ExerciseHistory.series` stays for R5).

Add plan:
- Entry point renamed **Add plan** on Plans and the empty Home. Three rows: **Paste plan** (primary when the
  clipboard has text), **Create with a chatbot** (steps: 1 Copy prompt, 2 paste it into your chatbot with your
  workout, 3 come back and paste the reply; "Copied" resets after two seconds; the draft survives app
  switches), **Import file**. The text editor is behind "Show text".
- **Review plan** replaces the modal-over-modal: days as compact rows that expand to exercises with per-set
  targets ("50 / 60 / 70 kg"); material warnings (unit mismatch, load removed, grouping changed) in yellow;
  cleanup warnings behind "Details (3)"; the "Set as current plan" toggle; **Save plan**.
- Errors lead with a sentence: "Bench Press, set 2 needs a rep target." Path and code under Details; the
  fix-it prompt unchanged. Core gains `IssueText.friendly(issue, plan context)` with a sentence for every
  E_ code in PLAN_FORMAT §4 and a generic fallback.
- Onboarding: "Try a short practice workout" next to "Try the full sample". `PracticePlan.json` (three
  straight-set exercises, one bodyweight, 60 s rest) is a new Resource, imported through the normal pipeline.
  `examples/` and the manifest are not touched.

Tests: L38 start-early target on a rest day; M8 every E_ code has a non-empty friendly sentence; N12 Copied
resets; O61 Home card wording per schedule state; O62 exercise preview; O63 week strip expands; O64 activity
line; O65 Add plan rows and default primary; O66 review shows per-set targets; O67 material vs cleanup
warnings; O68 friendly error first, details behind; O69 practice plan imports and activates; O70 draft
survives backgrounding.

### R4 — Visual system, Summary, Plan detail, accessibility (1–2 days)

- One design language: grouped/inset lists on every screen (content is list-shaped); one horizontal margin;
  a 4/8/12/20 spacing scale; three type tiers (input numbers, body, small-caps labels and secondary).
- Accent: keep the blue or pick one committed colour; add a green reserved for done rows and PRs.
  `StepButton` becomes a `Button` with a pressed state.
- Summary (§4.9): "**Workout saved**" · Push · 48 min · 16 of 18 sets · "Volume 12,400 kg" (omitted when 0);
  per exercise one readable comparison ("2 more reps at the same weight", "+2.5 kg", "first time") and a
  compact table when weights vary; set durations behind Details; Done.
- Plan detail: compact day rows with disclosure; exercise summaries show per-set variation
  ("3 × 8–12 · 24 / 26 / 28 kg") instead of the first target repeated.
- Accessibility: 44 pt calendar cells; Dynamic Type reflow; VoiceOver pass on the new workout screen, with
  the exercise-name link verified operable.

Tests: J25 comparison text for the comparable, non-comparable, varied-weight and first-time cases;
O71 volume omitted when zero; O72 Plan detail per-set variation; O73 calendar cell ≥ 44 pt; O74 pressed state;
O75 one list style per screen (snapshot); re-run O17–O19.

### R5 — Narrow additions (after R0–R4; each optional, in this order)

1. **Do later** (1 day): `deferExercise(exerciseIndex)` moves the block's pending steps after the last
   pending step of the day; overview shows the new order; `···` and the exercise block get "Do later".
   G61–G64.
2. **Basic plan editing** (2 days): edit exercise name, sets, targets, weight, rest, rep range; reorder
   exercises; duplicate a day. `PlanEdit` operations produce a new `Plan` that is re-normalized and
   re-validated by the existing pipeline; `sourceText` is regenerated so Copy JSON and export reflect the
   edit. L39+, C-section additions.
3. **Exercise chart and PR marker** (1 day): Swift Charts line of `topWeight` over date with reps annotated,
   in `ExerciseHistoryView`; exercise search in History; "PR" on a set that beats the previous best, on the
   Summary and in history. J26–J28. (Moves the chart out of SPEC §10.)
4. **Backup restore** (1 day): Settings → Import backup → validate → counts → Replace all / Merge. K22+.

Live Activity stays out until device use shows rest checks while locked are frequent.

### R6 — Device checklist v2 (owner + agent)

Re-run H3–H23, K16–K17 and O20–O28 on the new screen. Add H24 (minimize, lock, notification, Resume),
O76 (workout at accessibility XL, one-handed), O77 (VoiceOver through one full exercise), K23 (write
failure simulated with a debug launch argument that makes the store directory read-only; the app keeps the
data and Retry succeeds after the flag is removed). Record results in `DEVICE_CHECKLIST.md`.

## 6. Acceptance tasks

A milestone is done when its tasks pass on the iPhone with the sample plan, without coaching.

| Task | Passes when | Milestone |
|---|---|---|
| T1 Start the intended workout | Home names the day and the plan; one tap starts it; on a rest day the button says which day starts early | R3 (R0 for the calendar) |
| T2 Log a normal set | One tap, values prefilled, haptic, row fills in, rest starts in the strip | R2 |
| T3 Correct the last set while resting | Undo (one tap) or tap the done row (two taps); the rest keeps running | R2 |
| T4 Recover a skipped set | Add result saves; the value is there after reopening the session | R0 |
| T5 See what is left, then minimize and resume | Exercises opens in any state; minimize, switch tabs, Resume returns to the same step and remaining rest | R2 |
| T6 Run a pyramid | 50 → 60 → 70 kg prefills each set's own target after logging the first | R1 |
| T7 Import a second plan | Review shows the exercises; material warnings are readable; the plan is active if you said so | R0, R3 |
| T8 Tap a calendar day | A completed day opens the session; two sessions offer a choice | R0 |
| T9 Large text and VoiceOver | All of T2–T5 at accessibility XL and with VoiceOver | R2, R4 |
| T10 A failed write | Data stays, Retry works, nothing says "saved" until it is | R0, R6 |
| T11 Read the Summary | Name, duration, sets and one comparison per exercise are understood in a few seconds | R4 |

## 7. Order and process

Why this order: R0 is small, needs no design decisions, and removes every place the app lies, so trust is
restored before anything moves. R1/R2 is where the clunkiness lives and where the walkthrough happens; Home
and Import (R3) matter less per session and would otherwise be redesigned around a workout screen that was
about to change. Visual polish (R4) is applied once to layouts that have stopped moving. Features (R5) come
only after the everyday loop feels effortless.

Process for the implementing agent:

1. On approval, add one line to `CLAUDE.md`/`AGENTS.md` (both, identically) pointing to this file and
   stating "v1.1: milestones R0–R6 in order; SPEC amendments per ITERATION_2_PLAN §3 land before code."
2. Each milestone starts with the SPEC and TEST_CASES edits, committed on their own. Rewritten expectations
   note the previous behavior so the change is deliberate, not a test made to pass.
3. Core before views; both runners green; simulator screenshots into `build/` with the same `-ui*` debug
   arguments; every deviation in `DECISIONS_LOG.md`.
4. After R2, stop for the owner's phone walkthrough (T2–T6) before starting R3.
5. When the docs are final, regenerate `HANDOFF_BUNDLE.md` and the design-package zip so the bundle matches
   the folder.

Fixtures in `examples/` and `manifest.json` are never edited. `PracticePlan.json` lives in Resources only.

## 8. Risks

- **Removing the `.transition` phase** touches F/G tests, resume (K16) and the persisted `ActiveSession`.
  Mitigation: tolerant decoding of the v1 file (G53), and R1's tests green before any view changes.
- **Undo and notifications**: undo must cancel `rest-timer` and never leave a stale notification. G56 and the
  device check H24 cover it.
- **Prefill change** alters I-section expectations on purpose. Any fixture-driven test that disagrees is
  checked against the amended §6.5, not adjusted to pass.
- **Set timing (D19) gets longer** without the Continue gate. Accepted; the number is demoted everywhere.
- **Scope creep in R5**: each item is optional and stops on its own; none starts before R4 is green.

## 9. Owner decisions needed before R1

1. Workout screen: stable step card (recommended) or full scrolling list.
2. Between exercises: strip with no alert (recommended, keeps D14's rationale) or a real rest with an alert.
3. Reps rule: initialize once and never rewrite (recommended) or keep the dynamic re-prefill from D11.
4. Deletes: confirm everywhere (recommended) or an undo toast with deferred file deletion.
5. Sparkline: remove (recommended) or move to History with an explicit metric picker.
6. Tabs: keep four (recommended for this release).

Answer these in SPEC §1 and the agent builds what the docs say.
`````

---

### FILE: docs/ITERATION_3_PLAN.md

`````markdown
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
`````

---

### FILE: docs/ITERATION_4_PLAN.md

`````markdown
# Jimm's Bro+ — v1.3 plan (iteration 4)

One input drove this release: the owner's list after v1.2, with one instruction attached to
all of it — *"implement them seamlessly; the app should feel extremely intuitive and simple to
use."*

1. The Dynamic Island is too big; it should not be so wide.
2. A feature called **Progression**: based on the current plan, give the chatbot a JSON and
   have it calculate your progression over a period. When there is history, use it as context.
3. An importable CSV history file, and an importable history file in general — one you can
   add to another app.
4. Single-plan JSON edits, and specific JSON edits in general.
5. Changing an exercise mid-workout.

Milestones **X0–X6, in order**. Each ends with the full suite green
(`xcodebuild test -scheme JimmsBro -destination 'platform=iOS Simulator,name=iPhone 16'`,
`swift test`, `python3 tools/check_core.py`) and one commit on `v1.3-refinement`. SPEC
amendments land **before** the code that depends on them, as in v1.1 and v1.2. Each feature is
one decision, D41–D45, and one Core type that a view only renders.

"Seamless" is read the way the v1.1 reviews read it: nothing new on Home unless it has
something to say, every new action in the menu of the thing it acts on, every paste going
through the one import pipeline, and every number the app offers still loadable (D35).

---

## X0 — This plan, the branch, and the decisions

- Branch `v1.3-refinement` off `v1.2-refinement` (v1.2 is not yet merged to main; merging is
  the owner's call).
- D41–D45 are written into SPEC §6 and `DECISIONS_LOG.md` by the milestone that lands
  them, as v1.2 did with D32–D40; §1's table stops at v1.1.
- No app code.

## X1 — A narrower Dynamic Island (owner note 1, D41)

The compact Island was wide for two reasons, neither of them content: `Text(timerInterval:)`
reserves the width of the widest string it might ever show, and a count-up whose range runs to
`.distantFuture` is allowed to grow to `h:mm:ss`.

- `WorkoutActivityState.timerRange(now:)` in Core: the closed date range the system timer
  draws, bounded so it never shows hours — a countdown clamps at `now + 1 s`, a count-up is
  cut at 59:59. Unit-tested, since it is the one rule the Island's width depends on.
- The widget's compact trailing view is the timer alone at a fixed width with monospaced
  digits; compact leading is one symbol; minimal is the timer at a smaller fixed width. The
  expanded view keeps the set line and the progress bar. The Lock Screen banner loses 4 pt of
  padding and one line of detail.
- Checklist row Q74 for the phone.

## X2 — Change exercise mid-workout (owner note 5, D42)

The machine is taken and **Do later** is not the answer because you want to do *something*
now. `Event.substituteExercise(exerciseIndex:name:weight:)`:

- Pending steps of the exercise become steps of the new exercise; logged and skipped ones stay
  what they were. If nothing has been logged, the exercise is renamed in place; if something
  has, a second `SessionExercise` is appended and the pending steps re-pointed to it, so
  history says "Bench Press 1 set, Dumbbell Press 2 sets". `blockIndex` and step order do not
  change, so the rest that is running keeps running.
- The new exercise keeps its own identity: prefill, "last time", the suggestion chip, advice
  and PRs all read *its* history (D8). `substitutedFor` records the original's name, so the
  Overview, Session detail and the Summary can say "Dumbbell Press · was Bench Press".
- An optional weight replaces every pending target's weight; empty keeps the plan's. A
  superset member is substituted alone.
- UI: "···" → **Change exercise** opens one sheet: a name field with recent exercises from
  history as suggestions, an optional weight, **Change**. Reachable in every state, like
  Skip and Do later.

## X3 — JSON edits, at every size (owner note 4, D43)

Plan editing (D29) is structured — a sheet per exercise. Sometimes the fastest edit is the
text: the chatbot wrote one day wrong, or truncated the week, or you want a second set to
differ from the first. Every JSON edit goes through the same pipeline a paste does, so the
app cannot end up holding a plan it would refuse to import.

- `PlanJSON.render(day:)` and `render(exercise:)` render a fragment; `PlanEdit.Operation`
  gains `replaceDayJSON`, `replaceExerciseJSON`, `insertDaysJSON` and `insertExercisesJSON`.
  A splice decodes the fragment leniently (a bare object, an array of them, or a whole plan
  whose days or exercises are taken), puts it into the plan's own JSON tree, and re-imports.
  Errors carry the full path (`days[1].exercises[2].sets[0].reps`), so the sentence the
  editor shows names the real place.
- The plan itself: Plan detail's **Replace** becomes **Edit JSON** — the same sheet, titled
  for what it does, with the text already open. Replace's semantics (keep the id, keep it
  active, remap the cycle position) are unchanged.
- The parts: the exercise sheet gains **Edit as JSON**; the day's menu gains **Edit day as
  JSON** and **Add exercise from JSON**; the plan menu gains **Add day from JSON**. Adding
  opens the editor with a template, so an exercise can be typed in from nothing. One
  `JSONFragmentSheet` does all of them: monospace text, Paste, the friendly error sentence
  with Details, Save.
- This closes two things SPEC §10 still listed as out: adding an exercise to a day, and
  editing an individual set independently of the others.

## X4 — History as a file other apps can read (owner note 3, D45)

- **Export history (CSV)**, from Settings → Data: one row per logged set, in the column
  order Strong writes and Hevy reads — `Date, Workout Name, Duration, Exercise Name, Set
  Order, Weight, Reps, Distance, Seconds, Notes, Workout Notes, RPE` — plus `Weight Unit`
  last, because this app never converts (D10). Drops are their own rows; skipped sets are
  not rows. `HistoryCSV.render`.
- **Import history (CSV)**, from the same section: the file is read and *described* before
  anything is written — "42 workouts from 12 Jan to 3 Sep · 5 already here · weights read as
  kg" — then **Import**. `HistoryCSV.parse` reads its own export, a Strong export and a Hevy
  export by header name, not by position; it takes the unit from a unit column, a `_kg` /
  `_lbs` header, or the setting, and says which. A workout already in History (same start,
  same name) is skipped, so importing the same file twice adds nothing.
- Imported sessions are ordinary sessions: `planId` nil, the workout name as the day name,
  steps logged with their timestamps, so prefill, PRs, the chart and Metrics read them as
  if they had been logged here.
- The JSON backup (D31) stays the app-to-app format; CSV is the app-to-*other*-app one.

## X5 — Progression (owner note 2, D44)

The app's premise is the chatbot round-trip, and until now it ran one way. **Progression**
runs it the other way: the app writes out what the plan is and what you have actually done,
the chatbot plans the next N weeks, and the plan carries the answer week by week.

- `Progression` on a `Plan`: a start date, a number of weeks, and per (day, exercise) the
  week-by-week targets — weight, reps, or seconds, or per-set overrides. Optional in
  `Persistence.swift`; a plan without one is exactly a v1.2 plan.
- **The prompt** (`Prompts.progression`, marker `JIMMSBRO-PROGRESSION-PROMPT-V1`): the plan
  as a compact listing (not its JSON — a week of exercises fits a chat paste), the period,
  and, when the owner keeps the toggle on and history exists, the last six sessions of every
  exercise in the plan with the advice they earned. Under the paste bound.
- **The reply** (`docs/PROGRESSION_FORMAT.md`): a small JSON — `weeks`, and one entry per
  exercise with an array of week objects. `ProgressionImport` parses it with the import
  pipeline's leniency (numbers as strings, the reps vocabulary of PLAN_FORMAT §3.2, unknown
  fields ignored), matches entries to the plan by day and exercise name (§6.9), snaps every
  weight to the loadable increment (D35), and reports what it dropped. Nothing in the plan's
  structure changes: a progression is attached to the plan you have.
- **The week** is calendar weeks from the start date. `Session.start` applies the current
  week's targets to the day's snapshot (D7 holds: the session records what it was asked to
  do), and `SessionExercise.progressionWeek` says which week it was. Prefill reads the week's
  weight before last time's (§6.5, rule 0), and the suggestion chip's reason reads "Week 3 of
  8 of your progression". After the last week, the plan's own targets and advice are back.
- **UI**: Plan detail gets a **Progression** row — "Plan your progression" or "Week 3 of 8 ·
  started 8 Sep". It opens one screen: the period (4 / 6 / 8 / 12 weeks), **Use my history**
  when there is any, the three steps Add plan already taught (Copy prompt, paste it into
  your chatbot, paste its reply), the review (each exercise's weeks in one row, warnings in
  yellow), and **Save progression**. With one saved, the same screen reads it back, with
  **Plan the next one** and **Remove**. Home's subtitle says "week 3 of 8"; when it has run
  out, one line says so with **Plan the next one**. Nothing else moves.
- Plan edits (D29, X3) carry the progression through; Edit JSON / Replace of the whole plan
  drops it, because that is a new plan.

## X6 — Docs, checklist, bundle

- SPEC §4, §6, §8 and §10 reconciled; `PLAN_FORMAT.md` §5 unchanged (the plan format itself
  did not grow); `PROGRESSION_FORMAT.md` new and bundled; `PROMPT.md` gains the progression
  prompt and its marker rule.
- `TEST_CASES.md` gains section **W** (v1.3), per milestone as they land.
- `DEVICE_CHECKLIST.md` gains v1.3 rows; `BUILD_STATUS.md`, `DECISIONS_LOG.md`, README and
  `HANDOFF_BUNDLE.md` regenerated; `tools/check_bundle.py` passes.
`````

---

### FILE: docs/CODE_HEALTH_REVIEW.md

`````markdown
# Code-health review — 2026-09-07

A full read of the repository at `783c18f` (v1.1, R0–R5 landed, R6 written but not run):
every `Core/` and `Store/` file, the 13 view files, the 19 test files, the project
configuration, the docs and the tools. What was actually run at review time:

| Route | Result |
|---|---|
| `xcodebuild test`, iPhone 17 / iPhone 16 simulator | 148 tests, 0 failures, 0 compiler warnings |
| `python3 tools/check_core.py` | 147 bodies, 2,939 assertions, 0 failures |
| `python3 tools/reference_import.py` | 111/111 fixtures match |
| `swift test` via `Package.swift` | **does not compile** |

The verdict: the Core / Store / Views split is real, there are no force unwraps or `try!` in
Core, no `print`, no `UserDefaults`, and every on-disk write is atomic. Against that, four
confirmed defects, one broken build route, and a set of hygiene and structural issues.

**Every finding below is closed.** v1.2 (V0–V8) landed them all; `docs/ITERATION_3_PLAN.md` is
the plan, `docs/BUILD_STATUS.md` the result. The one thing left open is not a finding but a
limitation: the Live Activity of V7 has never been watched on a real Lock Screen (Q71–Q73 in
`DEVICE_CHECKLIST.md`).

## Confirmed defects

| # | Defect | Where | Status |
|---|---|---|---|
| 1 | Editing a plan silently changes a superset's between-round rest. The importer stores the round rest in `groupRestSeconds` from the first member's exercise-level `restSeconds`; `PlanEdit` only ever writes per-set `restSeconds`, so the re-import in `PlanEdit.apply` sees no exercise-level rest and sets `groupRestSeconds` to nil. A no-op rename turned a 120 s round rest into 90 s. | `Core/PlanEdit.swift` | Fixed in V1 |
| 2 | Retry on the save-failure alert is a no-op: the binding's setter clears `saveFailure` on dismissal, and by the time the button's `Task` runs, `retrySaveFailure`'s guard sees nil. | `RootView.swift` | Fixed in V1 |
| 3 | Hold-to-repeat on the − / + steppers cancels itself: `onLongPressGesture(minimumDuration: 0.4, pressing:)` calls `pressing(false)` when the gesture recognises, killing the repeater as its own 400 ms sleep ends. | `Features/Workout/WorkoutView.swift` | Fixed in V1 |
| 4 | Every weight keystroke writes `active-session.json`: the field's setter commits, which applies `setWorkWeight`, and the engine appends `.persist` to every accepted event. Typing "62.5" is four disk writes. | `Core/SessionEngine.swift`, `WorkoutView.swift` | Fixed in V1 |
| 5 | The SwiftPM route is broken: `Package.swift` declares macOS 13, but `AppModel` uses `@Observable`, which needs macOS 14. README claims `swift test` works. | `Package.swift` | Fixed in V1 |

Smaller, all fixed in V1: a DEBUG polling loop in `HistoryView` that busy-spins on the main
actor if cancelled before load finishes; `Store.restore(.replaceAll)` deletes before writing,
so the "nothing was changed" failure message is untrue for that mode; `exportData`,
`readBackup` and `restore` call `load()`, which renames corrupt files aside as a side effect
without surfacing the alert; `Phase.init(from:)` decodes any unrecognised payload as
`.completed` instead of throwing; two `\.first!` key paths in Overview and Session detail.

## Repository and GitHub hygiene

- **Nothing sensitive is published.** The repo is private and holds no keys or tokens. Two
  things to know before it ever goes public: `DEVELOPMENT_TEAM` is committed in the pbxproj,
  and every commit carries the owner's personal address as author.
- Leftover history-rewrite refs (`refs/original/*`, `refs/backup/pre-rewrite`, a stray
  `refs/codex/turn-diffs/…`) kept the pre-rewrite chain reachable. **Deleted in V0**, reflog
  expired, `git gc --prune=now` run.
- `HANDOFF_BUNDLE.md` and the zip are derived, committed, and were stale.
  **`tools/check_bundle.py` (V0)** now fails when either drifts.
- `build/icon/main.swift` and `build/seed/main.swift` were real sources inside the ignored
  `build/` folder. **Moved to `tools/` in V0**; the binaries are still built into `build/`.
- Docs disagreed with each other and with the machine. **Reconciled in V8**: README's "what
  remains is M8" and its `swift test` claim, `BUILD_STATUS.md`'s duplicated heading and its
  obsolete beta-Xcode note, `DECISIONS_LOG.md`'s claim that the signing team was unset (it is
  set, and v1.2's second target now carries it too), SPEC §7's three-field `ActiveSession` and
  `Settings.homeMetric`, and `TEST_CASES.md`'s twelve `unit` rows for the sparkline that v1.1
  deleted — now marked `removed`, with a note saying so rather than being quietly dropped.
- Ten stale `.gitkeep` files. **Deleted in V0.**

## Structural

- **The on-disk schema had no migration path.** `VersionedFile` refuses any `fileVersion`
  other than 1, and synthesized `Codable` makes a defaulted property a required key, so
  adding one field to `Settings` would move every existing file aside as corrupt.
  **V2** makes `Settings`, `SetTarget` and `Plan` decode leniently and freezes a v1 file of
  each type as a fixture that a test decodes.
- **Persisted shapes are the compiler's**: enums with associated values encode as
  `{"reps":{"_0":…}}`, and the legacy decoder already reaches for `_0` by name. Renaming a
  case silently breaks old files. V2's frozen fixtures are what makes that a red test.
- **String-typed codes and identifiers**: issue codes are bare strings with severity inferred
  from an `E_`/`W_` prefix, and `AlertIdentifier` exists but ten call sites still use raw
  literals. **Both become enums in V2.**
- Block grouping was implemented twice with different name matching, Overview re-implemented
  `ExerciseText.result`, and Summary, ExerciseHistory and Home each recomputed date or stat
  maths Core already knows. `Prompts.swift` carried the example JSON twice with nothing
  pinning it to `docs/PROMPT.md`. **All deduplicated in V2.**
- The test suite is broad and manifest-driven and caught real bugs during v1.1. Its
  weaknesses are hygiene: `makeRoot()`/`discard()` pasted into eight files, three assertions
  that depend on wall-clock timing under `-Onone`, and `RecordingAlerts` — a test double —
  shipping inside the app target. **V2.**
`````

---

### FILE: docs/BUILD_STATUS.md

`````markdown
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
`````

---

### FILE: docs/DECISIONS_LOG.md

`````markdown
# Decisions log

- M0: Use `com.ohayoune.jimmsbro` as the bundle identifier; leave the signing Team unset for the owner to choose in Xcode.
- M0: Display only the app name at launch until M4 implements Home after Core tests pass.
- M0: Bundle an original synthesized 0.3-second, 880 Hz PCM WAV beep; notification/audio behavior and the separate warning sound belong to M5.
- M0: Use Swift 5 language mode (Xcode's `SWIFT_VERSION = 5.0`) with the installed Swift 5.9+ toolchain; no package dependencies or project generator are required.
- M1: Preserve group-round rest provenance as optional `SetTarget.groupRestSeconds`, resolved from the first explicit exercise rest in the group; it survives Codable round trips without changing per-set fallback values.
- M1: Use a lenient typed JSON tree for DTOs and a strict grammar guard before JSONDecoder so trailing commas, comments and non-JSON numbers are rejected consistently across Foundation versions.
- M1: Limit JSON nesting to 256 levels to report malformed/deep input without unbounded recursion; the input byte cap is checked first.
- M1: Avoid duplicate suffixed names/group tags when an explicit name already occupies a generated suffix; a late bodyweight alias clears all numeric weights on that exercise.
- M2: Per the owner's request, shorten the chatbot prompt while preserving rules and example JSON data; keep all supplied fixture files unchanged and test the revised prompt separately.
- M2: Resolve stale F7 in favor of F9 and SPEC §6.3: crossing a completed block starts the done transition, not a rest countdown.
- M2: Resolve blanket G24 persistence wording in favor of G15/G31: invalid and inapplicable events are true no-ops; accepted mutations end in persist.
- M2: Add persisted work-timer running/beep-delivery state to ActiveSession; foreground reconciliation explicitly marks missed beep moments as delivered without replaying them.
- M2: ExercisePoint.sets contains actual logged results only; setSeconds retains one entry per historical step (nil for skipped/missing timestamps), as J24 requires; do not fabricate skipped results as zero reps.
- M2: A Core-only PlanLibrary implements library/session coordination for the L/G tests; disk I/O remains M3.
- Verification: The installed Command Line Tools compile Core independently of Xcode; their missing XCTest is handled by a portable runner that executes the same test bodies with real assertion checks. This does not certify XCTest discovery, app resource bundles, iOS builds or Simulator behavior.
- M2: Persist the current work weight and expose a Core `setWorkWeight` event so automatic timed-set logging uses the same historical prefill or edited value as the card, including an explicitly empty weight.
- M3: Give `settings.json` the same `fileVersion` key as the other three files; SPEC §8.1 names its type but not its shape, and one uniform version check makes K5 apply to every file.
- M3: Encode `fileVersion` beside the payload's own keys via a `VersionedFile` wrapper writing into the same keyed container, so files match SPEC §8.1's `{ "fileVersion": 1, ...Session }` literally rather than nesting the payload.
- M3: Sessions load sorted by `startedAt` then id, so history, charts and export have a stable order independent of directory enumeration.
- M3: Temp files are written as `.<name>.<uuid>.tmp` in the destination directory and removed on failure; only `*.json` is read back, so temp and `.corrupt-` files are never parsed as data.
- M3: `setAside` computes the reported relative path before moving the file — `resolvingSymlinksInPath()` strips `/private` only for paths that still exist, so reading it afterwards yields a different name.
- M3: Set file protection on both the temp file and the final file; the attribute is iOS-only and is compiled out elsewhere so Core checks run on macOS.
- M3: `deleteAll` removes the store directory and recreates it empty, leaving the store immediately usable rather than requiring a relaunch.
- M3: The portable Core runner gained an async test path and an `accuracy:` assertion, and now compiles `JimmsBro/Store` alongside `JimmsBro/Core`, so the K cases run on both routes.
- M4: `AppModel` (`@MainActor @Observable`) lives in `JimmsBro/Store/` beside the `Store` actor; it is the in-memory front end of the store, has no UI imports, and is therefore covered by both the iOS and the portable test routes.
- M4: Start/Resume on Home and Start on Plan detail show "The workout screen arrives in M5" instead of acting; starting a session before M5's workout screen exists would strand an active session with no way to finish it.
- M4: `StartCard` gains a `nothingScheduled` case for an active plan whose cycle resolves to no day (an empty cycle); it shows no button rather than a dead Start.
- M4: `StoreSnapshot.hasSettingsFile` distinguishes "no settings file" from "a file equal to the defaults", which is what N10 needs in order to write the defaults exactly once.
- M4: The sparkline draws a 3 pt dot for a day whose neighbours are both gaps. SPEC §6.13 says "nothing else", but with alternate-day training every point is isolated and single-point segments stroke to nothing, so the chart rendered empty in the common case. Flagged for the owner.
- M4: The name-conflict prompt is an `.alert`, not a `.confirmationDialog`: presented over the import sheet, the dialog style drops its cancel row, and O6 requires all three choices.
- M4: The preview sheet hands its plan back and the conflict alert is raised from the sheet's `onDismiss`; raising it in the same turn as the dismissal leaves the alert half-built.
- M4: Calendar weekday initials are keyed by position, not value — `id: \.self` silently collapses the repeated S, M, T, W, T, F, S to five columns.
- M4: DEBUG-only launch arguments (`-uiScreen`, `-uiPlanDetail`, `-uiImportText`, `-uiImportSave`) open a screen directly for screenshot runs. They are compiled out of release builds and inert without the arguments. They exist because the iOS Simulator tap tooling needs an Xcode whose licence is accepted; a UI test target would replace them if the owner wants XCUITest.
- M4 (owner change, 2026-09-04): Scheduled rest days now show a filled grey dot on the calendar, distinct from days the plan says nothing about, which show no dot. `DayEntry` gains a `.rest` case; SPEC §4.1 and §6.12 and TEST_CASES O30 were updated to match, and the same edits were applied to `HANDOFF_BUNDLE.md` and to the doc entries inside `JimmsBro-design-package.zip` (its `examples/` fixtures were copied through untouched, so the zip remains the byte-for-byte oracle for fixture integrity).
- M4: A weekday plan's unlisted weekdays are rest days; a rotation cycle's `.rest` entries are rest days. Past days without a session, days beyond the 62-day horizon, days with no active plan, and every day of a rest-free rotation cycle stay `.none` — a day you simply didn't train is not a scheduled rest day.
- M4: A cycle entry pointing at a day index that no longer exists is `.none`, not `.rest`; it is a broken entry rather than scheduled rest.
- M4: Tapping a rest day shows "Sun 14 · Rest day" beneath the grid. SPEC previously said rest days show nothing, which was consistent when they had no dot; a dot you can tap that then says nothing would not be.
- M5: The step card's set line reads "A · Set 2 of 4" for a superset member. SPEC §4.5 writes it as "A · 2 of 2", which drops the set number you need mid-superset; the group tag plus the normal set line keeps both and still adds no label text (O37).
- M5: O7's target strings ("8–12 reps @ 60 kg") conflict with SPEC §4.5's ("8–12 · 60 kg") and §4.0's no-labels rule. Resolved in favour of SPEC and the already-tested `TargetText.target`.
- M5: `NotificationScheduling` and `AlertPlaying` are protocols in Core; `RecordingAlerts` is the inert default used by tests and previews, and `JimmsBroApp` injects `SystemNotificationScheduler`/`SystemAlertPlayer` from Features. Core and Store therefore never import UserNotifications, AVFoundation or UIKit.
- M5: `AlertRouting` owns notification titles and the choice of `warning.caf` for the warning beep, so the engine keeps emitting only ids, dates and bodies.
- M5: `warning.caf` is an original synthesized 0.08 s, 1320 Hz tick with a fast decay at 60% volume — deliberately shorter, higher and quieter than the 880 Hz end beep.
- M5: Notification permission is requested without blocking: the first set appears immediately and the prompt sits over it, with the "alerts only work with the app open" banner shown afterwards if permission was refused. Blocking would have made the first card wait on a system dialog.
- M5: `AppModel.justCompleted` holds the finished session after `PlanLibrary` clears the engine, so the Summary (SPEC §4.9) has something to render. Without it the workout dismissed straight past the Summary. It is cleared by Done, by discarding, and by a day switch that finishes the previous session.
- M5: Log set sits directly under the weight row inside the card rather than pinned to the screen bottom; the keyboard pushes the card up, so the button is never hidden (O9) and the card reads as one block.
- M5: The overview groups by block, and when a block holds more than one exercise (a superset) each row names its exercise instead of repeating the shared group tag, which otherwise made every row read "A · Set 1 of 3".
- M5: Additional DEBUG-only screenshot arguments: `-uiNoAlerts` (inert alerts, so no system permission prompt), `-uiAdvance <n>`, `-uiSkipWaits`, `-uiSkipDone`, `-uiOverview`. Compiled out of release builds and inert without the arguments.
- M6: `HistoryGrouping.months` groups by the local calendar month of `startedAt`, newest month and newest session first, and excludes sessions with no `endedAt` — a workout still running is not history.
- M6: The month formatter takes its time zone from the injected calendar. Without that the section key (the month's first instant in that calendar) formats in the system zone and a month boundary lands one month early.
- M6: SPEC §6.7 defines the best set for rep-based sets only; an exercise with only timed sets shows its longest hold instead of nothing, and a weightless exercise shows most reps.
- M6: `EditResultSheet` is shared by the live overview and session detail; the overview routes its save through `SessionEngine.editSet` (no phase change, no timer) and history routes it through `PlanLibrary.editSession`, which rewrites just that session file.
- M6: Exercise names are accent-coloured links in session detail, on the step card and on the summary, which is O16's "reachable from all three".
- M6: The exercise-history screen lists `ExerciseHistory.series` newest first with the best set on top. The time-vs-weight chart itself is D13/§10 "Later"; this ships its data source, as SPEC §8.4 intends.
- M6: `tools/add_sources.py` was rewritten for Xcode's canonical `project.pbxproj` format. Xcode rewrote the project file from the quoted format the M0 skeleton used, which broke the old parser.
- M6: Additional DEBUG-only screenshot arguments: `-uiSessionDetail`, `-uiExercise <name>`.
- M7: `NotificationScheduling` gained `authorizationState()` so the Settings row reports what the system says rather than what the app last hoped; `NotificationState.explanation` is non-nil only for a refusal, since that is the only case worth a sentence.
- M7: The weight step is stored and edited per unit, so changing units never silently moves the other one. It is clamped to 0.1–100; zero would make − and + do nothing.
- M7: `deleteAllData` cancels every pending alert first, then empties the store and resets the model in place, so the app stays usable without a relaunch. It writes fresh defaults immediately, which is why a later launch sees those rather than re-deriving from the locale.
- M7: Export uses a `UIActivityViewController` wrapper rather than `ShareLink`: the file only exists after an await, and `ShareLink` needs its item up front.
- M7: `HomeMetric.title` is now the one definition of each metric's name; the sparkline caption used to spell them inline.
- M7: `StepCard.spoken` writes the card out as a sentence for VoiceOver rather than reusing the visual text, which is full of "·" and "–" that do not read aloud. The descriptive block is one accessibility element (O19); the reps and weight rows stay separately focusable because they are controls.
- M7: The rest overlay posts a "Rest over" announcement once when the countdown crosses zero. The haptic and sound alone are no use to a VoiceOver user.
- M7: Large numbers (the countdown, the timer, the reps and weight fields) get `minimumScaleFactor` and a smaller base size at accessibility sizes, so O18's "Log set still on screen" holds at accessibility XL.
- M7: The app icon is an original barbell on a blue gradient, drawn by `tools/icon/main.swift` with Core Graphics at 1024×1024 — no text, so it reads at home-screen size. The launch screen stays Xcode's generated one, which already adapts to light and dark.
- M7: `AccentColor` is defined in the asset catalog with a lighter blue in dark mode, so the accent stays legible on black (O17).
- v1.1 R0/R1: `SessionEngine.editSet` now accepts a **skipped** step (D27): it sets the result, marks it logged, and — only when the previous status was `.skipped` — overwrites `loggedAt` to the edit's `now`, since the old value was a skip timestamp, not a log time. An edit to an already-logged step still leaves `loggedAt` untouched, preserving its original set-duration measurement.
- v1.1 R1: The `.transition` phase is removed (D14). A block-ending log or skip now advances straight to `working(next)` in the same event; `ActiveSession.blockDone: BlockDone?` (`finishedBlock`, `startedAt`) records what the status strip shows and is cleared by the next log, skip, jump, `undoLog`, or an explicit `dismissBlockDone` (replaces `continueTransition`). `Phase` keeps a hand-written `Codable` conformance (SE-0295's synthesis was empirically verified via a standalone probe script before this landed) so a v1 file whose phase was `.transition` decodes as `.working(step: nextStep)`, and `ActiveSession`'s own hand-written decoder reconstructs `blockDone` from that same legacy payload when the modern key is absent, rather than throwing or silently losing the strip's context (G59).
- v1.1 R1: `Event.undoLog(step:)` (D23) is valid only when `step == active.lastCompletedStep` — the single most recently logged-or-skipped step — and the session isn't completed. It resets the step to pending, clears its result/`loggedAt`, clears the exercise's now-stale `advice`, clears any `blockDone`, and re-enters it via the existing `enterWorking` path (so a fresh `startedAt` and prefill are computed exactly as if the card were appearing for the first time). `lastCompletedStep` is set only by `logSet`/`skipSet` (and transitively by the timer events that funnel into `logSet`), not by `skipExercise`, `jumpTo`, or timer starts — undo targets one set at a time, not a batch skip.
- v1.1 R1: Discovered while testing D24 — `SessionRunner.run(_:)` processed a batch's `.persist` effect after `.sessionCompleted` and, since `completeSession()` had already niled the engine, `persistActiveSession()`'s "no engine → clear the file" fallback unconditionally deleted `active-session.json` regardless of whether the session's own write had just failed. Fixed by skipping the generic `.persist` handling whenever `.sessionCompleted` is in the same batch (it always is, together, or not at all) and letting `persistCompletedSessions` own the file's fate instead. Caught by `WorkoutTests.testSessionWriteFailureIsKeptAndRetried`, not by inspection.
- v1.1 R0: `SaveFailure` (D24) is a small enum (`.session`, `.activeSessionWrite`, `.activeSessionClear`, `.plans`, `.settings`, `.deleteSession`) carrying the failing value itself, so `AppModel.retrySaveFailure()` can retry without re-deriving anything. `trySaveSession`/`tryClearActiveSession` are shared, non-`private` helpers (SessionRunner.swift and AppModel.swift both extend `AppModel` from separate files, and `private` doesn't cross files) used by both the normal completion path and retry.
- v1.1 R0: `AppModel.load()` now special-cases an `active-session.json` whose phase is already `.completed` (D24): rather than resuming it as a live workout, its session is folded into `library.sessions` if not already there, saved, and the active file cleared — recovering a run whose prior file-clear write had failed instead of resuming a "completed" workout or silently losing it.
- v1.1 R0: Plan detail's **Replace** (D25) does not reuse `PlanLibrary.save`'s name-based conflict matching — the intent is already explicit, and the incoming JSON may have renamed the plan entirely. `PlanLibrary.replace(id:with:)` is a separate method that overwrites the plan at that id outright, remapping `cyclePosition` the same way `.replace` conflict resolution already did.
- v1.1 R0: The import preview's "Set as current plan" toggle is hidden (not merely disabled) when `ImportView.replacingPlanId` is set, since Replace already preserves whatever active status the plan had; showing a toggle that does nothing there would be worse than no toggle.
- v1.1 R0: Every list swipe-to-delete (Plans, History) now routes through a captured id and a `confirmationDialog` rather than deleting inside the `.onDelete` closure itself (D25) — SwiftUI's swipe action already requires a second tap on the red button, but the owner asked for a worded confirmation consistent with every other delete path, not just that affordance.
- v1.1 R1: `StepCard.setRows`/`progress`/`blockDoneLine` (D22) are pure Core functions with unit tests but no caller yet — R2 wires them into the rebuilt workout screen. R1's `WorkoutView` instead shows a temporary, unstyled banner (block-done line + Dismiss) and an "Undo last set" row in the existing "···" menu, so `blockDone` and `undoLog` are reachable behavior rather than dead Core code while the real fixed-zone layout is still ahead.
- v1.1 R2: The workout screen is resolved as data. `WorkoutScreen.model(active:history:now:)` returns a `WorkoutScreenModel` holding all five zones (SPEC §4.5, D22), the set rows, the prefilled input values, the status strip and the primary action; `WorkoutView` only renders it. That is what makes "the zones never move" a testable property (O50) instead of a promise the view layer has to keep, and it keeps prefill and text formatting out of SwiftUI, per CLAUDE.md's thin-views rule.
- v1.1 R2: The strip and the primary button live in a bottom `safeAreaInset`, not in the scrolling column. The middle two zones scroll and absorb Dynamic Type; the two the thumb uses keep their position across working, resting, timed and block-done states, and stay above the keyboard.
- v1.1 R2: The status strip keeps a `minHeight` when it is empty. An empty zone that collapsed would move the primary button between states, which is the thing D22 exists to prevent.
- v1.1 R2: `Feedback` is a new enum with one case (`.logged`) and a second `AlertPlaying.play(feedback:vibration:)` method, rather than a new `TimerBeep` case. `TimerBeep` is persisted inside `ActiveSession.deliveredBeeps` and means "a timer moment"; a log confirmation is neither persisted nor a clock. It is emitted as `Effect.playFeedback(.logged)` from `logSet` only, so O59 ("once per logged set, never for an edit, a skip or a rejected input") is assertable in Core, and it is vibration-only — a haptic that also beeped would compete with the rest alert.
- v1.1 R2: `startTimer` is now accepted while `.resting` when the rest's `nextStep` is the timed step: it ends the rest and starts the work in one event. SPEC §4.5 gives the one primary slot to "Log set" during rest, but a timed step waiting on the far side of a rest made that button read "Start timer" and do nothing, because the engine required `.working`. Logging out of a rest and starting a timed set out of a rest are now the same rule (O62).
- v1.1 R2: Set rows drop two things the R1 Core functions put in them. The set duration is gone (D19: seconds belong to the Overview, Session detail, the strip and the Summary's details, never to the screen you are working on), and the exercise's notes no longer repeat on every row — the exercise's own target line carries them once. Discovered on the simulator, where four rows each read "6–8 · 80 kg · Pause on chest".
- v1.1 R2: `StepCard.rowLabel(session:step:naming:)` and `blockNamesRows` moved the superset row-naming rule into Core. The Overview and Session detail had each written it out separately (M6), and the new set rows reproduced the original defect — two rows of a superset round both reading "A · Set 2 of 3". One rule, three callers.
- v1.1 R2: Rename exercise left the mid-workout "···" (SPEC §4.5) and landed in Session detail as `PlanLibrary.renameExercise`, which routes through the engine's own `renameExercise` event so the trimming and length cap cannot diverge between a live rename and a history one. Session detail asks which exercise when there is more than one.
- v1.1 R2: At accessibility sizes the header reflows onto two rows and the rest controls take a row of their own, rather than letting "Exercises" wrap to four lines and "Skip" break in half. Found by screenshotting at accessibility XL (O60), not by inspection.
- v1.1 R2: `ActiveSession.canUndo` replaced the copy of that rule in `SessionEngine`, so the strip's affordance and the event's guard read the same property and cannot disagree.
- v1.1 R2: New DEBUG-only screenshot argument `-uiNoAsk`, which marks notification permission as already requested so the system prompt does not sit over every screenshot. An unanswered prompt also survives `simctl install`, so `tools/shot.sh` uninstalls before a seeded run; `tools/pbxproj_edit.py` adds and removes source files in the (non-synchronized) Xcode project.
- v1.1 R3: `HomeStart.current(library:now:calendar:)` builds on the existing `StartCard` rather than replacing it: `StartCard` still decides *which* day and state Home is in, and `HomeStart` decides what is said about it. The wording per schedule state is therefore a unit test (O63) rather than a screenshot.
- v1.1 R3: The sparkline is gone, and so are `Sparkline`, `HomeMetric`, `AppModel.setHomeMetric`/`cycleHomeMetric`, the Settings "Home chart" row, SPEC §6.13 and the S-section test cases — replaced by `HomeActivity.line`. **This deleted working, tested code, and the folder is not under version control**, so it is recoverable only from a copy made before 2026-09-05. It was removed because both v1.1 reviews agreed a chart whose metric changes on an undocumented tap is undiscoverable rather than quiet (ITERATION_2_PLAN §5 R3). `ExerciseHistory.series` — the per-exercise data D13 stores for the chart in §10 — was deliberately kept; R5 uses it.
- v1.1 R3: "This week" means the calendar week containing today (honouring `firstWeekday`), not a rolling seven days, so the activity line and the week strip above it describe the same days. On a Monday the line therefore reads "No workouts yet this week", which is true; a rolling window would have said something friendlier and less accurate.
- v1.1 R3: `CalendarProjection.week(containing:)` composes two calls to the existing `entries(month:)` rather than duplicating the projection rules, because a week can straddle a month boundary. O65 asserts the week and the month grid agree day for day, which is what stops the two from drifting apart later.
- v1.1 R3: `IssueText.friendly` derives its "Day 1, exercise 2, set 2" from the issue's own path rather than from the plan, because when an import fails there is no plan to look an exercise's name up in. M8 asserts a sentence exists for every code the importer can emit — driven by running the invalid fixtures, so a code added later without a sentence fails the test rather than silently falling back.
- v1.1 R3: Warnings are split by whether they changed the workout. Material (unit dropped, load removed, grouping or schedule reinterpreted) is shown; cleanup (curly quotes, unknown fields, truncated names, rounded weights) goes behind "Details (n)". An unrecognized warning code counts as material: showing something unnecessary is the cheaper mistake.
- v1.1 R3: `TargetText.summary(_:units:)` shows what varies across an exercise's sets — "3 × 8–12 · 24 / 26 / 28 kg", or "12 · 24 / 10 · 26 / 8 · 28 kg" when the reps move too. Both the review sheet and Plan detail use it; Plan detail previously repeated the first set's target as if it described the exercise, which hid every pyramid.
- v1.1 R3: The review sheet opens with the first day already expanded. A review screen you have to tap before it reviews anything is not one.
- v1.1 R3: `View.bottomAction { }` is now the one definition of a bottom-anchored primary action (a bar background, the same padding), used by the workout screen, Add plan, the review sheet and Plans. Without the bar, list content showed through the button.
- v1.1 R3: `FixtureLoader.appResource` reads a file the app ships (`JimmsBro/Resources`) from the app bundle under XCTest and from the source tree under the portable runner, so O71 checks the `PracticePlan.json` that actually ships rather than a copy pasted into the test.
- v1.1 R4: `SessionStats.comparison` returns an `ExerciseComparison` (a headline sentence plus optional set rows) instead of one raw string. The sentence is chosen by what is actually true of the whole exercise: one weight both times → reps ("2 more reps at the same weight"); a moved weight → "+2.5 kg", with ", 1 fewer rep" appended only when the reps moved too; bodyweight both times → reps alone; timed work → seconds held; weights that varied within the session → a volume headline and a "10 @ 60 → 10 @ 62.5" row per set, because no sentence covers a pyramid. J9's old expectation is recorded in TEST_CASES as rewritten, not quietly replaced.
- v1.1 R4: A session's volume is grouped (`TargetText.grouped`, "12,400"); weights and reps are not. Weights are never four digits, and grouping them would only add noise. This changed History's row subtitle too, so `ExerciseText.summary` uses the same function — HistoryTests' "1680 kg" expectation was updated deliberately.
- v1.1 R4: `Color.done` (system green) is reserved for "this already happened" — a logged set row, and R5's PR marker. The accent blue now means only "you can act on this"; before, a finished row and a button were the same colour.
- v1.1 R4: `InsetGroup` gives the workout screen the grouped-list look every other screen gets from `.insetGrouped`, without making it a `List` — a List would take back the fixed zones D22 exists to guarantee. Same 12 pt radius, same secondary grouped background, so the app speaks one visual language without the workout screen giving up its layout.
- v1.1 R4: `PressableRow` and `StepButton`'s pressed state (O78). `.plain` keeps a row looking like a row but acknowledges nothing; in a gym, with one hand, "did that tap land?" is a real question.
- v1.1 R4: Set durations moved behind **Details** on the Summary rather than being deleted. D19 still stores them and the Overview and Session detail still show them; the Summary is where they were competing with the numbers that matter.
- v1.1 R5.1: `deferExercise` (D28) reorders the `steps` array and remaps every index that points into it — the phase and `lastCompletedStep` — through the permutation. `blockIndex` is deliberately **not** renumbered: it identifies the block for rest resolution, block durations and `blockDone`, and rewriting it would break all three. The Overview and Session detail now order blocks by where their steps sit rather than by `blockIndex`, which is what makes the new order visible.
- v1.1 R5.1: A superset defers as one block. Its members are one station, and moving half of one would produce rounds with nothing to alternate with. A day that is entirely one superset therefore has nothing to defer, and the menu item is not offered.
- v1.1 R5.2: `PlanJSON.render` writes a `Plan` back out as plan-format JSON, and `PlanEdit.apply` re-imports the result. An edit is therefore validated and normalized by exactly the code an import is, `sourceText` always matches the plan (so Copy JSON, the export file and a Replace round-trip all read the edit), and an edit that would produce an unimportable plan fails at the same place an unimportable paste does. C40 asserts the fixpoint over every valid fixture.
- v1.1 R5.2: The renderer always emits the explicit array-of-sets form. The compact forms exist for whoever is writing the plan by hand; a generator gains nothing from them and would have to guess which values happen to be shared. It also writes `"warningBeep": false` explicitly when a fixed-duration set has no warning: leaving the field out means "default", which the importer resolves to 10 % of the duration, not to "off". `valid/timed-sets.json` caught this — the round-trip test found it, not inspection.
- v1.1 R5.2: The edit sheet's reps field takes one string for what the plan format keeps in two JSON keys, so a trailing "s" means seconds: `10`, `8-12`, `AMRAP`, `5+` are reps; `45s`, `30s+`, `open` are time. `PlanEdit.text(for:)` is the inverse of `parseWork`, asserted over every `WorkTarget` (L45) — without that, opening the sheet on an open-duration set and pressing Save would have turned it into an AMRAP rep set, because "30+" reads as reps.
- v1.1 R5.2: Duplicating a day names the copy "<day> copy" rather than letting the importer's duplicate-name suffix produce "Push (2)", and does **not** add it to the cycle. Duplicating a day is a request for a day to edit, not a request to train more often.
- v1.1 R5.3: A personal record is decided by a running best walked in log order, so a session that sets a record twice marks both, and a set that merely equals the old best marks neither. The first session of an exercise sets none — otherwise every set of it would be a PR, which tells you nothing. Sessions in other units are not history for the comparison, because the app never converts (D10).
- v1.1 R5.3: The chart is drawn only when there are two or more sessions with a weight to plot. One point is a dot, not a trend, and a bodyweight or timed exercise would otherwise get a flat line at zero. It carries an accessibility summary in words ("5 sessions, 85 kg, up from 70"), since a chart VoiceOver cannot read is not a feature.
- v1.1 R5.4: Restore reads the file and reports what it holds before writing anything, and says what each choice would do in counts. **Merge** adds only ids not already on disk and leaves the current settings, the active plan and anything edited since the backup untouched — a merge that silently overwrote a workout you had corrected would be worse than no merge. **Replace all** takes the backup's settings and active plan, because it is restoring a device, not importing data.
- v1.1 R5.4: `ExportDocument` gained an optional `activePlanId`. Optional, so a backup written by v1 still decodes and restores; it just leaves the first plan active.
- v1.1 R5.4: A restore discards a running workout first. The active session describes steps in a session file the store is about to replace, and resuming it afterwards would be resuming a workout that no longer exists.
- v1.1 R6: A real bug, found while building the device checklist rather than by inspection. D24's save-failure alert lived only on `RootView`, which the workout is presented **over** as a `fullScreenCover` — so a failed write during a workout, which is when writes mostly happen, showed nothing at all. `View.saveFailureAlert(model:enabled:)` is now attached to both `RootView` (only while the cover is down) and `WorkoutView` (always), so whichever view is on top presents it. The disabled copy's binding also had to guard its setter: without that, switching the alert off would clear `saveFailure` instead of leaving it for the other copy.
- v1.1 R6: `-uiReadOnlyStore` makes `Store` refuse every write (DEBUG only), rather than making the store directory unwritable. Refusing cannot damage or lose real data, which matters because this argument is meant to be run on the owner's phone against real history; relaunching without it makes Retry succeed. POSIX permissions were tried first and did not reliably block the write on the simulator.
- v1.1 R6: The `-uiAdvance` screenshot loop drives engine events with no UI settling between them, so combining it with `-uiReadOnlyStore` loses the cover presentation to the repeated alert. That is a limitation of the screenshot harness, not of the app: without `-uiAdvance`, the same run shows the workout with the alert over it correctly (`build/r6-savefail.png`).
- v1.1 R6: The checklist rows were written but **not run** — they need the phone. Nothing in `DEVICE_CHECKLIST.md` is marked pass. *(Corrected in v1.2: the signing team **is** set in the pbxproj, and has been since 2026-09-05; v1.2's `JimmsBroActivity` target inherits it, since it uses automatic signing with no team of its own.)*
- v1.2 V0: The leftover history-rewrite refs are deleted rather than kept "just in case": they kept the pre-rewrite commits, with the trailers the rewrite existed to remove, reachable for ever. `tools/icon` and `tools/seed` hold the sources; the binaries are still built into the ignored `build/`, by `tools/shot.sh` when they are missing or stale. `HANDOFF_BUNDLE.md` and the zip stay committed — the owner hands them to a chatbot that cannot read a folder — but `tools/check_bundle.py` now fails when either drifts, which is the only thing that makes committing a derived file safe.
- v1.2 V1: `PlanJSON.render` writes a group's round rest back as an exercise-level `restSeconds`, which is the only field the importer resolves `groupRestSeconds` from. The explicit array-of-sets form does not otherwise need it; without it every edit (all of which re-import) silently replaced a superset's between-round rest with the last member's own. Found by the code-health review, reproduced with a probe, and now Q1/Q2.
- v1.2 V1: Rest resolution reads `groupRestSeconds` and never the per-set value for a grouped exercise, so `PlanEdit.setRest` on a superset member now sets the round rest for the whole group. Writing only the per-set value was an edit that looked like it worked and changed nothing.
- v1.2 V1: `setWorkWeight` no longer emits `.persist`. It is the weight the card is displaying while it is still being typed, and one keystroke is not a fact about the workout; the next log, skip or tick carries it to disk. The view now pushes it on focus loss, from the steppers and the suggestion chip, and once before a timed set is finished — not on every character.
- v1.2 V1: The save-failure alert captures the failure synchronously and passes it to `retrySaveFailure(_:)`. Presenting the alert clears `saveFailure` on dismissal, so the button's `Task` always found nil: Retry had never worked.
- v1.2 V1: The steppers' hold-to-repeat uses `minimumDuration: .infinity`. At 0.4 s the gesture recognised and SwiftUI called `pressing(false)`, cancelling the repeater exactly as its own 400 ms delay ended, so holding a stepper did nothing.
- v1.2 V1: `Store.load` gained `settingAsideCorruptFiles:`, false for export, backup inspection and restore. Renaming a file aside is a change the user is told about through the launch alert; doing it as a side effect of exporting moved a file with nothing on screen to say so.
- v1.2 V1: `Phase.init(from:)` throws on a payload it does not recognise instead of decoding it as `.completed`. A file that says something this version does not understand is corrupt, and SPEC §8.3 already knows what to do with corrupt files; guessing "completed" would silently end a workout.
- v1.2 V2: **Every file may leave out anything with a default; nothing may leave out its identity.** Synthesized `Codable` treats a defaulted property as a required key, so adding one field to `Settings` would have made every settings.json on the phone "corrupt" and moved it aside — and v1.2 adds three. `JimmsBro/Core/Persistence.swift` writes the rule out once, `examples/store/v1/` freezes a real file of each type from v1.1, and `StoreMigrationTests` decodes them. The fixtures are never regenerated to make a test pass: they are what is on the owner's phone.
- v1.2 V2: `VersionedFile` accepts `fileVersion <= storeFileVersion` rather than only `==`. A reader must read its own version and older, or the number can never be bumped.
- v1.2 V2: `AlertIdentifier` is an enum and `Effect` carries it, so a notification id cannot be spelled one way when it is scheduled and another when it is cancelled. Each id owns its title and sound, which is what `AlertRouting` used to switch on.
- v1.2 V2: `SessionBlocks` is the one grouping rule for the Overview and Session detail, which had each written their own — with different name matching, which is exactly where a superset made them disagree. The Overview also stopped re-implementing `ExerciseText.result`.
- v1.2 V2: The example JSON inside the plan prompt is written once, and `PromptPinningTests` asserts `Prompts.planTemplate` and `fixTemplate` are byte-identical to the fenced blocks of `docs/PROMPT.md`. The pin skips under XCTest on a simulator — the checkout is outside that sandbox — and runs under `swift test` and `tools/check_core.py`, both of which execute on the host.
- v1.2 V2: `RecordingAlerts` is a test double and moved into the test target; the app ships `SilentAlerts`, which does nothing, as `AppModel`'s default. `makeRoot`/`discard` live once in `CoreTestSupport`. The three timing assertions became generous ceilings with messages saying so: they exist to catch an accidental O(n²), not to measure a machine that may be busy or running at `-Onone`.
- v1.2 V3: The app has **one** rest with three kinds (`RestKind`: `warmUp`, `betweenSets`, `betweenExercises`). The warm-up before the first set and the walk to the next machine are mechanically rests — the same countdown, the same −30 / +30, the same notification, the same right to log straight out of them — so modelling them as anything else would have meant three copies of the timer. What changes is what the strip calls them, which is the thing the owner said was unclear.
- v1.2 V3: The warm-up and the between-exercises rest are **settings, not plan-format fields**. Adding an optional key to PLAN_FORMAT would have touched the importer, the schema, the 111 frozen fixtures and the manifest, for something the owner described in the language of a setting ("type how long it takes between switching different exercises"). If a plan ever needs its own, it can be added later without moving these.
- v1.2 V3: Both default to **on** (5 min warm-up, 2 min between exercises), because they are what the owner asked for. Every test written before v1.2 asserts the flow they change, so `CoreTestSupport.classic` turns both off and those tests say so explicitly — they still assert the app's real behavior, which is what it does when the settings are Off.
- v1.2 V3: A **skipped** set that ends a block still gets the walk between exercises, though a skipped set mid-block still gets no rest. Skipping a set does not move the next machine any closer.
- v1.2 V3: `WorkoutStage` counts exercises in the order the day is now running them (through `SessionBlocks`), not by `exerciseIndex`, so "Do later" (D28) moves an exercise's number with it instead of leaving a gap. Progress counts sets rather than exercises, so the bar moves inside a long exercise.
- v1.2 V3: Found on the simulator. The `-uiAdvance` screenshot loop could no longer log anything, because a session now opens in a break; `-uiSkipWaits` skips the waits *inside* an exercise (the warm-up and the rests between sets) and deliberately never the walk between them, so a run of N sets ends on that countdown, which is the state worth screenshotting. The finished block's sentence also wrapped and truncated its own advice beside the countdown, so it has the strip's second row to itself.
- v1.2 V4: `WeightRounding` snaps every weight the app *offers* to a multiple of `Settings.weightIncrement(for:)`; weights the user **types** are never touched. If they lifted 61 kg on a machine the app knows nothing about, that is what happened. `heavier(than:target:increment:)` and its mirror exist because rounding to nearest can land back on the weight you just lifted — 132 + 2.5 rounds down to 130 on a 5 lb grid — and a suggestion that is not a change is not advice.
- v1.2 V4: `weightIncrement` is separate from `weightStep`. A rack may be worth stepping through in 5 lb while the smallest plate pair makes 2.5; one is the size of a tap, the other is what the equipment can do.
- v1.2 V4: From a weight that is already loadable, − / + move by one step rounded onto the grid; from one that is not, the first tap simply brings it onto the grid in the direction asked for. 134 lb goes to 135, not to 140 — jumping a whole increment past the number you wanted is the behavior the owner complained about.
- v1.2 V4: `SetSuggestion` (D36) is per set and carries its reason: advice from last time if the exercise earned any, else what was done for that set index last time, else the plan's target. The chip reads "Try 8 × 62.5 kg" with the reason beneath it, and one tap fills in **both** numbers — half a suggested set is not much use.
- v1.2 V5: `Plan.cycleAnchor` (D37) is the day `cyclePosition` describes, so a rotation is projected from a **date**. v1.1 walked the cycle forward from *today* and moved the position only when a session completed, so a missed workout slid every later day by one — and by one more for each further day missed. The pattern now moves only when a workout finishes, which re-anchors it once, to the day it was actually done.
- v1.2 V5: The anchor day is the day that was *done*, so the calendar never paints it as planned and `next` never returns it. A plan that has completed nothing has no such day: its pattern starts today, and today is painted.
- v1.2 V5: A plan that predates anchors is anchored at launch to the day of its **most recent completed session** — the app has that date — and only to today when it has none. Anchoring blindly to today made the grid and the card disagree on the first launch, which was visible in the very first screenshot taken of it.
- v1.2 V5: A rest-free cycle is painted for the whole horizon. v1.1 projected only tomorrow and left the month blank, because without an anchor it was guessing; with one it is a real repeating pattern, and a blank month was part of what made the calendar feel like it did not know what it was doing.
- v1.2 V5: A missed training day is **said** on Home — "Pull was due Monday", with **Do it now** and **Dismiss** — rather than resolved behind your back. Only the most recent, only within a week, and the dismissal is not persisted: it costs one tap, and re-earning it means missing another day.
- v1.2 V5: Home's card now says *when*, not only *what*. For a rotation v1.1 read "Next up · Push" whether Push was today or three rest days away; it now reads "Rest day / Push is next, Tue / Start Push early" — the same wording the weekday branch already used — so the card and the grid say the same thing.
- v1.2 V5 (D38): A calendar cell carries its day's short name. v1.1 drew every day as the same 5 pt dot, so a month of training looked like a month of anything else and the shape of a week could not be read off the grid ("the spacing … is not perfectly clear"). A rest day is a dash rather than another dot, which is what makes the gaps visible, and each cell reads as one VoiceOver sentence.
- v1.2 V5: `tools/seed/main.swift` advances the plan on each session's own date. It was passing `Date()`, so every seeded plan ended up anchored to today and the screenshots showed a calendar no real phone would ever show.
- v1.2 V6 (D39): Every metric is a `Metric` — a label, an already-formatted value, and a note where the number needs one — so a view renders a list and computes nothing, and every figure the app shows is a unit test. The owner asked for "metrics for the past" without naming any, so the set is the questions a person actually asks after a workout: how long, how much of that was resting, how many sets, how much lifted, anything a record.
- v1.2 V6: A metric with nothing to say is **absent**, not zero. A bodyweight day has no volume, and "Volume 0 kg" reads like a failure rather than like a category that does not apply. Timed work reports time under tension instead.
- v1.2 V6: Trend volume only adds up within one unit, because the app never converts (D10); the window's own unit is used and sessions in another are left out of that figure alone.
- v1.2 V6: The streak counts **weeks**, not days. A day streak punishes a rest day, which is part of the plan; a week streak measures the thing the owner cares about, which is still training.
- v1.2 V6: The Metrics screen lists the workouts of its window under the numbers, so any figure can be traced back to the days that made it rather than being taken on faith.
- v1.2 V6: Home's calendar line under the grid is now the way into a finished workout. v1.1 wanted a second tap on the cell itself, which nothing on the screen said you could do — the affordance existed and was invisible.
- v1.2 V7 (D40): `WorkoutActivityState` is resolved in Core from the same `ActiveSession` the workout screen reads, so the Dynamic Island and the app cannot disagree about what is happening. It is the one file compiled into both the app and the widget extension — the contract between them — and depends on nothing but Foundation, which is why it is a separate file from the `of(_:)` factory that knows about sessions.
- v1.2 V7: ActivityKit lives behind `ActivityPresenting`, injected exactly as `NotificationScheduling` is. That is what makes "what the Lock Screen would show" a unit test rather than something only a phone can answer, and it keeps ActivityKit out of Core entirely.
- v1.2 V7: The countdown is drawn by the **system**, from a `Date`, using `Text(timerInterval:)` — the same rule as SPEC §6.4's Date-based rest timer, one layer out. The app pushes a state only when the state changes, so a per-second tick does not wake the system sixty times a minute for a number it is already drawing.
- v1.2 V7: The activity ends when the workout does, finished **or discarded**. A countdown on the Lock Screen for a workout that no longer exists is worse than no countdown.
- v1.2 V7: Every ActivityKit failure is silent. A Lock Screen widget that will not start is a missing convenience, not a lost set; the workout screen is unaffected, and the user may have turned Live Activities off, which only the system can change.
- v1.2 V7: The extension target was written into `project.pbxproj` by `tools/add_activity_target.py` rather than by hand, so it is reproducible and reviewable. Two things it had to get right, both found by the simulator refusing to install the app: the app target must **list** the Embed Foundation Extensions phase (creating the phase is not enough), and the extension needs a real `Info.plist` with an `NSExtension` dictionary — `INFOPLIST_KEY_NSExtensionPointIdentifier` did not produce one, and without it the bundle is not an extension at all.
- v1.3 X1 (D41): The compact Dynamic Island is the timer in a fixed box and one symbol, nothing else. Its width came from `Text(timerInterval:)` reserving room for the widest string it could ever draw — and a count-up running to `.distantFuture` could draw `999:59:59`. The range is now resolved in Core (`timerRange`), never inverted and never an hour, and the text is told not to show hours; the set line and progress bar are the expanded view's.
- v1.3 X2 (D42): Changing an exercise mid-workout changes only its **pending** steps. Nothing logged yet → the exercise is renamed in place; something logged → a second `SessionExercise` is appended and the pending steps re-pointed to it, so history credits each name with exactly the sets done under it. Step order and `blockIndex` never change, which is what keeps a running rest running and the position in the day where it was.
- v1.3 X2: The substitute keeps its own identity (D8): its own last time, prefill, advice and PRs. The original earns no advice for an exercise it did not finish — one set of Bench Press is not a verdict on the working weight.
- v1.3 X2: The same name with a weight is a weight change for the remaining sets, not a substitution; the same name with nothing is refused. A superset member is substituted alone.
- v1.3 X2: A substitution is said once — "· was Bench Press" on the exercise's line and "Instead of Bench Press" on the Summary — never on every row, for the same reason notes are not (§4.5).
- v1.3 X3 (D43): A JSON edit is a **splice into the plan's own JSON tree** followed by the ordinary import, never a parse of its own. That is what gives the errors real paths (`days[1].exercises[2].sets[0].reps`) and keeps the rule that the app holds nothing it would refuse to import.
- v1.3 X3: A fragment is read generously — a plan, a day, an exercise, or a list of any — because a chatbot asked for one day may answer with a plan holding it. Read as exercises, a plan gives all of them; read as days, loose exercises become one day.
- v1.3 X3: A day added by JSON joins a rotation's repeat block, and is named here if the fragment did not name it. Adding a day is a request to train it; leaving it out of the cycle with a warning nobody sees would have looked like nothing happened.
- v1.3 X3: A replaced day keeps its name when the fragment has none, and a renamed one takes the old name's place in the repeat block. Renaming a day is not a request to stop training it.
- v1.3 X3: Plan detail's Replace is now called **Edit JSON** — the same sheet, the same semantics, titled for what you came to do. Both it and every `PlanEdit` now keep `cycleAnchor` (D37); v1.2 dropped it in both, which re-anchored the calendar on the next launch.
- v1.3 X3: The exercise template opens with a **blank name**, so Save says "Every exercise needs a name" rather than quietly saving a placeholder.
- v1.3 X4 (D45): History leaves the app as **CSV in Strong's column order** with the unit as a thirteenth column, because that is the shape the most apps read and a file that does not say its unit is a guess. The JSON backup stays the app-to-app format.
- v1.3 X4: The CSV reader finds columns **by header name**, never by position, and takes a row's unit from a unit column, then the weight header, then the setting — saying so when the setting had to be used. A weight of 0 is no weight, which is what Strong writes for a bodyweight set.
- v1.3 X4: Imported sets are spread evenly over the workout's duration rather than given invented set times. The file says when the workout started and how long it took; the metrics that need set times (D19) stay absent for it, which is truthful.
- v1.3 X4: A workout is a duplicate of one already here when it has the same name at the same minute, so a file imported twice adds nothing. Imported sessions have no plan and never move a rotation.
- v1.3 X4: An empty History offers **Import from another app** — the one place an empty screen can say what would fill it — through the same flow Settings uses.
- v1.3 X5 (D44): A progression is **attached to the plan you have**, not a new plan. The reply carries only the week-by-week targets, matched to the plan by day and exercise name; the plan's structure never changes, so nothing the chatbot invents can reorder a day or drop an exercise.
- v1.3 X5: The prompt sends the plan as a **compact listing**, not its JSON, and the history as one line per exercise. A week of exercises fits a chat paste that way; the JSON of three days does not. The history is shortened first, never the plan.
- v1.3 X5: **Week 1 starts the day the progression is saved**, and weeks are calendar weeks. Counting from the first workout instead would make "week 3" depend on a date the user cannot see.
- v1.3 X5: In a progression week the week's target is the **prefill and the chip**, outranking last time and last time's advice. The chatbot has read the history; showing last time's weight in the field would be the app arguing with the plan the user asked for. "Last 70 kg" is still said underneath.
- v1.3 X5: A range of reps in a week also becomes the exercise's rep range for that session, so the advice at the end judges by the week's range and not the plan's.
- v1.3 X5: What the reply **left out or the app ignored** — an unmatched exercise, a weight on a bodyweight exercise, a short list — is a material warning; a rounded weight or an unknown field is tidying. Same rule as D26's review.
- v1.3 X5: Plan edits keep the progression; Edit JSON / Replace of the whole plan drops it. An edit is the same plan changed; a replacement is a new plan, and a progression planned for another plan's targets is not worth guessing about.
- v1.3 X5: When the progression has run out, Home says so in one line with **Plan the next one** — and the plan's own targets and advice are simply back. Nothing lingers, nothing nags.
`````

---

### FILE: docs/DEVICE_CHECKLIST.md

`````markdown
# Device checklist (M8, and v1.1's R6)

Every `manual` case from `TEST_CASES.md`, to run on the owner's iPhone. The simulator cannot do
notifications while locked, real haptics, the silent switch, or the free-account expiry, which is why
these are here rather than automated.

Everything else — 246 automated tests plus the simulator screen checks — is green; see
`BUILD_STATUS.md`. **v1.3** added the rows W3, W12, W21, W30 and W40 at the end; none has been run yet.

**v1.1 (R6)**: the workout screen was rebuilt (SPEC §4.5, D22), so every row below that touches it
is being run against a different layout than the one M8 described, and the **v1.1 rows** section at
the end is new. Nothing here has been run yet on this build — it needs the phone. Signing is already
configured (`DEVELOPMENT_TEAM = 3CDZYD6W6G` on both targets, all four configurations), so steps 1–2
of "Before starting" are done; start at step 3. H33's read-only-store case needs the
`-uiReadOnlyStore` launch argument, which is DEBUG-only.

## Before starting

1. ~~Xcode → Settings → Accounts → add your Apple ID.~~ Done.
2. ~~Project → Signing & Capabilities → Team.~~ Done — `DEVELOPMENT_TEAM = 3CDZYD6W6G`, automatic signing, on both `JimmsBro` and `JimmsBroTests`.
3. iPhone → Settings → Privacy & Security → Developer Mode → on (the phone restarts).
4. Plug in the phone, tap "Trust this computer", pick it as the run destination, press Run.
5. On the phone: Settings → General → VPN & Device Management → trust your developer certificate.
6. Import the sample plan from Home, or paste a real one, before starting the timer cases.

Mark each row **pass**, **fail** or **n/a**, and put anything surprising in Notes.

## Timers, notifications and audio

| Case | What to do | Expected | Result | Notes |
|---|---|---|---|---|
| H3 | Lock phone during 90 s rest | Notification arrives at the right second, with the next exercise in the body |  |  |
| H4 | Skip rest while locked-notification pending, then unlock | No stale notification fires later |  |  |
| H5 | Background for 3 min mid-rest, return | Step card shows next step with overrun "+1:30" |  |  |
| H6 | Kill the app during rest, relaunch, Resume | Rest resumes with correct remaining (or overrun) from `endsAt` |  |  |
| H7 | Notification permission denied | Foreground alerts still work; one-time banner shown; Settings row shows "Off · Open Settings" |  |  |
| H8 | Phone on silent, sound on, no headphones | Beep is audible (playback category) |  |  |
| H9 | Music playing in headphones | Music keeps playing; beep ducks it briefly; music resumes at full volume |  |  |
| H10 | Sound off | No audio session activation (music never ducks) |  |  |
| H11 | Vibration on, phone face down on bench | Haptic felt at zero |  |  |
| H12 | Two rests in a row quickly (log, skip rest, log) | Only one pending notification at any time |  |  |
| H13 | Rest of 10 minutes | Notification fires at 10:00, display shows m:ss throughout |  |  |
| H14 | Incoming phone call during rest | Notification still delivered as banner |  |  |
| H15 | Timed set countdown 45 s, tap Done at 30 s | Logs 30; rest begins |  |  |
| H16 | Timed set countdown reaches zero while locked | Notification "Time!"; on return the logged duration is 45 and rest is running/overrun |  |  |
| H18 | Change device clock forward during rest | Rest ends immediately on next tick; no crash (accepted behavior) |  |  |
| H19 | Fixed 45 s plank, default warning | Short quieter beep at 40 s, final beep at 45 s, nothing else |  |  |
| H20 | Open-duration dead hang with "30+" | One beep at 30 s; Stop logs the seconds; no beep without a minimum |  |  |
| H21 | Lock the phone at 12 s of a 45 s set | "5 s left" notification at 40 s, "Time!" at 45 s; on unlock nothing replays |  |  |
| H22 | Sound off, vibration on, timed set | Light haptic at the warning and a stronger one at the end; no audio session activation |  |  |
| H23 | Tap Done at 30 s of a 45 s set | Neither the warning nor the end notification fires later |  |  |

## Persistence

| Case | What to do | Expected | Result | Notes |
|---|---|---|---|---|
| K16 | Kill app mid-workout, relaunch | Resume banner with correct elapsed; Resume restores exact step and inputs' prefill |  |  |
| K17 | Reinstall from Xcode over the existing app | Plans and history still present |  |  |

## Screen, input and end to end

| Case | What to do | Expected | Result | Notes |
|---|---|---|---|---|
| O20 | Screen stays awake during workout; turns off normally after Done | True |  |  |
| O21 | Keep-awake setting off | Screen locks per system setting |  |  |
| O22 | Rotate the phone | Stays portrait |  |  |
| O23 | Sweaty-thumb test: all workout controls ≥ 44 pt and reachable one-handed | True |  |  |
| O24 | Free-account 7-day expiry: app refuses to open after a week | Re-run from Xcode restores it with data intact |  |  |
| O25 | Full end-to-end: copy prompt → ChatGPT → paste → import → 3-exercise workout with a superset and a plank → summary → history | Works without touching a keyboard except reps/weight |  |  |
| O26 | Chatbot output truncated (long weekly plan) | `E_NOT_JSON` with "end of file" message; fix-it prompt gets a complete plan back |  |  |
| O27 | Chatbot added `rpe` and `tempo` fields | Imports with warnings, no errors |  |  |
| O28 | Chatbot wrote weights as "60kg" strings | Imports; no warning if unit matches |  |  |
| O33 | Lock the phone on the done screen for 5 minutes | Nothing fires; on unlock the stopwatch reads ~5:00 |  |  |

## v1.1 rows (new or changed in R0–R5)

| Case | What to do | Expected | Result | Notes |
|---|---|---|---|---|
| H24 | Minimize mid-rest (the chevron), lock the phone, wait past the rest notification, reopen and Resume | The notification fires at the right second; Resume returns to the same step with the strip already reading the overrun; no stale rest notification fires afterwards |  |  |
| O53 | While resting, tap **Exercises**; then do it again while a block-done strip is showing | The overview opens in both states, and the header's Exercises, minimize and "···" are present in every state — this is the thing v1 made unreachable |  |  |
| O55 | Tap the reps field, then the weight field | A **Done** item appears above the keyboard and dismisses it; the primary button stays above the keyboard, never behind it |  |  |
| O56 | Look at the two input rows, then turn VoiceOver on and swipe to them | **REPS** and **KG** are visible; VoiceOver reads each field with that label and its value |  |  |
| O60 | Settings → Accessibility → Larger Text → accessibility XL, then run one exercise | No zone clipped or pushed off screen; the input numbers keep their size; the header reflows to two rows and the rest controls take a row of their own |  |  |
| O76 | One-handed, sweaty thumb, at accessibility XL: log a set, undo it, log it again | Every control is reachable and at least 44 pt; the primary button never moves between states |  |  |
| O77 | VoiceOver through one full exercise, including a rest | The exercise block reads as one element; "Rest over" is announced once; the exercise-name link is operable; the PR badge reads as "Personal record" |  |  |
| T2–T6 | The acceptance tasks of ITERATION_2_PLAN §6, on the sample plan, without coaching | Log a normal set in one tap; correct the last set while resting; see what is left and resume after minimizing; run the Incline pyramid and watch each set prefill its own weight |  |  |
| K27 | Settings → Export, then Settings → Import backup and pick that file; choose **Merge** | It names the backup's date and counts, says Merge would add nothing, and adding nothing is exactly what happens |  |  |
| K28 | Import a backup from another device (or an edited copy) with **Replace all** | The app ends holding exactly that backup, including which plan is active; a running workout is discarded first |  |  |
| H33 | Launch with `-uiReadOnlyStore` (Product → Scheme → Edit Scheme → Arguments), log a set, and let the write fail | "Couldn't save the workout. It's still here — try again." with **Retry**; the set stays on screen; removing the argument and tapping Retry saves it |  |  |
| O79 | Mid-workout, "···" → **Do later** on the exercise you are on | The next exercise appears immediately; the deferred one is at the end of the Overview and comes round again later |  |  |
| O80 | Plan detail: tap an exercise, change its weight, Save; then Edit → drag one exercise; then a day's "···" → Duplicate day | Each change sticks and survives leaving the screen; Copy JSON reflects it; a change the importer would refuse says why instead of appearing to work |  |  |

## v1.2 rows (new or changed in V1–V7)

| Case | What to do | Expected | Result | Notes |
|---|---|---|---|---|
| Q10 | Hold − and then + on the reps stepper, then on the weight stepper | The value keeps changing while your finger is down and stops when it lifts. Before v1.2 holding did nothing at all |  |  |
| Q32 | Start a workout and watch the top of the screen through a warm-up, a set, a rest and the walk to the next exercise | The stage is named in words above a progress bar, and the name changes at each of the four |  |  |
| Q33 | Settings → **Warm-up**, **Between exercises**, **Smallest change** | Read in minutes and say "Off" at 0; the smallest change is per unit and says what it is for |  |  |
| Q34 | Set **Smallest change** to 5 lb, log three sets at 132 lb at the top of the rep range, and read the advice | "Try 135 lb next time" — never 134 |  |  |
| Q35 | Type 134 into the weight field, then tap + once, then − twice | 135, then 130, then 125: every tap lands on a weight you can load |  |  |
| Q43 | Look at the suggestion chip under the weight, and tap it | It reads "Try 8 × 62.5 kg" with its reason underneath, and one tap fills in **both** the reps and the weight |  |  |
| Q53 | Home's week strip, then **Month** | Each day carries its workout's short name; finished days are green, planned days outlined, rest days a dash — the shape of the week is readable at arm's length |  |  |
| Q54 | On a rest day, read Home's card against the grid | The card names the same day the grid rings, and says when: "Rest day · Push is next, Tue" |  |  |
| Q45 | Skip a scheduled workout, open the app the next day, and compare the month grid with yesterday's | Nothing has moved. The missed day is reported on Home ("Push was due Monday") with **Do it now** and **Dismiss** |  |  |
| Q61 | History → a past workout | It opens with its metrics: duration, working and resting share, sets, volume, reps, heaviest set, records |  |  |
| Q62 | History → **Metrics**, and switch between 7 / 30 / 90 days | The numbers change with the window, and the workouts that produced them are listed underneath |  |  |
| Q63 | Home → tap a finished day in the calendar, then tap the line underneath it | The line opens that workout. (v1.1 needed a second tap on the cell, which nothing said you could do) |  |  |
| **Q71** | Start a workout, begin a rest, and **lock the phone** | The countdown is on the Lock Screen, counts down correctly without opening the app, and disappears when the workout ends |  |  |
| **Q72** | With a rest running, look at the Dynamic Island: glance at it, tap it, and long-press it | Compact, minimal and expanded all show the timer; expanded also shows the set line and the day's progress |  |  |
| **Q73** | iOS Settings → Jimm's Bro+ → turn **Live Activities** off, then run a workout | The app behaves exactly as before and shows nothing on the Lock Screen. Nothing about the workout is affected |  |  |
| K29 | Install v1.2 **over** a v1.1 install that already has plans and history | Everything is still there — no "a data file couldn't be read" alert — and Home's next day says what it said before the update |  |  |

## v1.3 rows (new or changed in X1–X5)

| Case | What to do | Expected | Result | Notes |
|---|---|---|---|---|
| **W3** | Start a workout, begin a rest, and look at the Dynamic Island; then start a timed set and look again | The compact Island is one symbol and the timer, no wider than the phone's own Timer app makes it; the count-up never grows to hours; long-press still opens the expanded view with the set line and bar |  |  |
| **W12** | Log one set, then during the rest tap "···" → **Change exercise**, type a name you have done before, and tap Change | The sheet suggested the name as you typed; the card now shows the new exercise with its own last time and suggestion; the rest is still counting; the logged set is still listed under the old name |  |  |
| **W21** | Plans → a plan → an exercise → **Edit as JSON**; change the second set's weight; Save. Then the day's menu → **Add exercise**; Save without a name | The exercise row now reads its sets as "24 / 26 / 24 kg"; the blank name is refused with "Every exercise needs a name" and the text stays in the sheet to fix |  |  |
| **W30** | Settings → **Export history (CSV)**, AirDrop it to the Mac and open it in Numbers; then delete one workout in History and Settings → **Import history (CSV)** with that file | The spreadsheet shows one row per set with named columns and the unit last; the dialog says "1 workout … · N already here"; Import brings only the deleted workout back, and its exercise chart is whole again |  |  |
| **W40** | Plans → a plan → **Progression**; pick 4 weeks; Copy prompt; paste it into ChatGPT or Claude; copy the reply; **Paste progression**; Save. Then Home → Start | The review lists every exercise's four weeks with any warnings in yellow; Plan detail's row reads "Week 1 of 4"; Home's subtitle ends "week 1 of 4"; the first set's card shows the week's weight and the chip says "Week 1 of 4 of your progression" |  |  |

## When you are done

Anything that fails is a bug to bring back here with the row and what actually happened. A `fail` on
H8, H9 or H10 points at the audio session; on H3, H16 or H21 at notification scheduling; on H5, H6 or
K16 at the Date-based timers or the resume path. A `fail` on O53, O55 or O60 points at the
fixed-zone layout of SPEC §4.5; on K27/K28 at `Store.restore`; on H33 at D24's save-failure path.

For the v1.2 rows: a `fail` on Q71–Q73 points at `SystemActivityPresenter` or the
`JimmsBroActivity` target's embedding; on Q45 or Q54 at `PlanSchedule`'s anchor (D37); on Q34 or
Q35 at `WeightRounding` (D35); and on **K29** at `Core/Persistence.swift` — which would mean a
field added in v1.2 is being required of a file written by v1.1, the exact failure the frozen
fixtures in `examples/store/v1/` exist to prevent.
`````

---

### FILE: docs/COPY_PASTE_NOTES.md

`````markdown
# Copy and paste findings

Checked 2026-09-04. The plan prompt was shortened from 4,399 to 3,510 characters (kg, rest 90) at the owner's request. The example JSON retains exactly the same data; the rules retain the schedule, cycle, rest, progression, timed-set, bodyweight, drop, group, naming, notes, ordering and complete-output requirements. The 4,000-character regression test now matches the prompt.

ChatGPT currently converts pastes over 10,000 characters into attachments. This is a composer behavior, not evidence that the text was truncated. The release notes describe an option to move the attachment back into the text field. The prompt itself is below that threshold, although the user's appended workout description could cross it. [OpenAI release notes, August 4 and June 22, 2026](https://help.openai.com/en/articles/6825453-chatgpt-release-notes).

The app's import limit is 1,048,576 UTF-8 bytes, not characters. Oversized input is rejected before parsing with `E_TOO_LARGE`; the import pipeline never silently clips the original paste. Multibyte text is counted by bytes. Fenced replies, surrounding prose, BOM/zero-width characters and curly quotes are covered by the fixture tests. The plan stores the original source text for copying back out.

A reply cut off mid-object reports `E_NOT_JSON` with an end-of-file/position message. The fix-it prompt retains that message and requests the entire corrected JSON. A syntactically complete plan that a chatbot silently omitted exercises from cannot be detected automatically: the user must compare the preview to the requested workout. The prompt explicitly forbids abbreviated output and exercise removal.

The regression tests include a large valid 31-day, 50-exercise-per-day plan, preservation of its complete source text, a truncated copy of that plan, exactly-at-limit and over-limit inputs, and multibyte input over the byte limit. These test Core string handling, not the system clipboard.

Actual iPhone copying/pasting, paste permissions, rich-text conversion, and the Import editor are pending M4/device validation. The original prompt-pasted and prompt-example fixtures remain unchanged; a separate test covers the new rendered prompt. There is no claim that every chatbot or clipboard implementation accepts the same maximum length.
`````

---

### FILE: docs/UX_REVIEW.md

`````markdown
# Jimm's Bro+ usability and product review

Reviewed September 5, 2026. These are recommendations, not accepted specification changes.

The next release should concentrate on a stable workout screen, easy corrections, and a clearer path from a plan to a workout. More analytics, modes, and customization would not resolve the main friction.

## Evidence and limits

This review uses the product specification, import format, prompts, test documentation, current SwiftUI views, AppModel, session engine, prefill rules, and saved simulator screenshots in build/. The captures show representative screens; they are earlier captures, not a new walkthrough of the current binary. Some details already differ from the source, such as preview singular/plural wording. Current source takes precedence for behavior.

Two small executable probes were compiled against the current Core sources and run successfully during this review:

- Skip set 0, then send editSet with a valid result: the set remains skipped with no result. This reproduces the mismatch between the edit sheet offered by the UI and the engine's refusal to edit an unlogged set.
- Import explicit weights 50, 60, 70 kg, log the first set at 50 kg, then request the second set's prefill with no history: the prefill is 50 kg despite a 60 kg target.

No app code or authoritative specification was changed. The complete XCTest suite was not rerun for this analysis. This is an expert review with two targeted behavior checks, not a usability study with participants. Priority reflects judgment about frequency, disruption, and implementation scope.

## Why it can feel clunky despite looking sparse

The app's original quiet-UI rules remove labels, hide nearly every secondary action, and make large numbers the main visual feature. This creates a sparse interface, but can remove the context people need to act confidently.

Five patterns recur:

1. **The layout changes while the user's task stays the same.** Logging, resting, and moving to another exercise use substantially different layouts and action positions.
2. **Control disappears at inconvenient times.** The rest screen hides access to the overview and corrections, even though rest is a natural time to check the last entry.
3. **The interface exposes technical structure.** JSON, field paths, rotation, group letters, and flattened step counts are more prominent than their practical meaning.
4. **Automation can conflict with intent.** Carrying forward a weight is useful for straight sets but surprising for explicitly programmed pyramids. Changing weight can also reset an untouched reps field.
5. **Some workflows stop short of completion.** Calendar dates do not navigate to sessions; import does not offer to activate a second plan; skipped-set editing silently does nothing.

Minimalism should remove effort and irrelevant information. Useful labels and visible access to common tasks can make an app feel simpler even when they add a few pixels. Nielsen Norman Group's discussion of minimalist interfaces specifically cautions against hiding content required for primary tasks. Its examples concern websites; applying the principle here is a design judgment, not a measured result for this app. [Source](https://www.nngroup.com/articles/characteristics-minimalism/)

## Priority order

| Order | Change | Expected benefit | Relative scope |
|---|---|---|---|
| 1 | Stable workout layout, inline rest, visible overview and minimize | Less searching and fewer interruptions every session | Medium–large |
| 2 | Immediate undo, reliable skipped-set recovery, explicit save failures | Corrections work and the app feels dependable | Medium |
| 3 | Respect intentionally different set targets; clarify prefill | Less fighting the inputs | Medium |
| 4 | Guided import, meaningful preview, explicit activation | Easier first use and plan replacement | Medium |
| 5 | Clearer Home and complete calendar interactions | Obvious next action, fewer dead ends | Small–medium |
| 6 | Consistent typography, labels, spacing, and accessible controls | More readable, cohesive presentation | Medium |
| 7 | Basic plan editing and “Do later” | Handles ordinary gym changes without another app | Medium–large |
| 8 | Small exercise-progress view and backup restoration | Useful feedback and data portability | Separate, medium features |
| 9 | Lock-screen Live Activity | More convenient rest checks if phone locking is frequent | Separate feature; validate demand |

Scope estimates are comparative, not delivery promises. Items 1–6 should precede a broad feature release. A narrow version of item 7 may be worth moving earlier if modifying plans is your most common frustration.

## 1. Keep the workout in one stable place

Current behavior: WorkoutView replaces the set card with RestOverlay, then uses TransitionView after an exercise block. The Log set button sits inside the card's scroll area, while Skip rest and Continue sit near the bottom. Timed sets put their primary action before the optional weight row.

Recommendation:

- Keep the exercise name, current set, input area, and main action in consistent positions.
- Show the current exercise's short set list: completed, current, and upcoming sets. Do not expand the entire workout onto the main screen.
- Present rest as a compact area attached to the workout. Keep the exercise and inputs visible; changing the next set's draft must not cancel rest.
- Place a clearly labeled Exercises action in the workout header. Use an overview sheet for the full sequence.
- Add a minimize control. Keep the active workout and timer running, with Resume visible in the app.
- During rest, put End rest in the same primary-action location. At expiry, return that location to Log set. Fixed and open work timers should reuse the same area for Start timer, Finish early, or Stop.
- Keep a reachable primary action above the keyboard. Make the supporting content scroll when needed.

This preserves the one-tap normal logging workflow. It does not require adding a Start set tap to every rep-based set.

The current rest screen has no overview or finish toolbar. That is a concrete access problem, not just a preference for a different layout. Workout presentation also lacks an explicit way to minimize back to the tabs while continuing the session.

**Between exercises:** Replace the full-screen completed-exercise duration with a brief completion message and the next exercise ready to view. A small “Moving on” elapsed value can remain for the original timing preference, but it should not require a separate Continue gate for rep-based work. Timed exercises still need an intentional Start timer action.

For a hypothetical workout with six separate exercises and three rep sets each, the existing design adds five Continue taps to eighteen Log set taps. Removing those gates saves five navigation actions; the more important gain is consistent context. This is an illustrative count, not a measured time saving.

Evidence: JimmsBro/Features/Workout/WorkoutView.swift, JimmsBro/Features/Rest/RestOverlay.swift, JimmsBro/Features/Transition/TransitionView.swift, JimmsBro/Features/Workout/TimerBlock.swift, JimmsBro/RootView.swift. Visuals: build/o9-step-card.png, build/o9c-rest.png, build/o32-done.png.

## 2. Make recovery immediate

An accidental log should have a brief “Set logged · Undo” affordance. Undo should restore the previous values, step status, and appropriate timer state. Editing an older result should leave the active rest timer running.

A skipped set should expose either “Do this set” or “Add result,” with the action actually supported by Core. Currently OverviewView opens EditResultSheet for every nonpending step, but SessionEngine.editSet returns immediately unless the set was logged. SessionDetailView similarly offers edits for skipped rows. The sheet dismisses after Save, creating the appearance of success without a change. The targeted probe confirmed this Core behavior.

Deleting a plan through its menu, and deleting from the Plans and History lists, currently have different confirmation behavior from deleting a session in detail. Standardize this: either provide reliable undo for ordinary deletion, or use a concise confirmation where recovery is unavailable. Keep the explicit delete-all confirmation.

Make write failures visible and recoverable. AppModel and SessionRunner suppress multiple write errors with try?. In persistCompletedSessions, a session is inserted into the persisted-ID set even if its save failed, and active-session clearing proceeds. I did not simulate a disk failure, but that control flow deserves correction before cosmetic polishing: only mark a session saved after a successful write, retain recoverable data, and offer Retry on failure.

Success feedback should be quiet. Do not add a confirmation dialog to every set.

Evidence: JimmsBro/Features/Overview/OverviewView.swift, JimmsBro/Features/SessionDetail/SessionDetailView.swift, JimmsBro/Core/SessionEngine.swift, JimmsBro/Features/Plans/PlansView.swift, JimmsBro/Features/History/HistoryView.swift, JimmsBro/Store/AppModel.swift, JimmsBro/Store/SessionRunner.swift.

## 3. Make input assistance predictable

Keep previous-session prefill and the optional progression suggestion. These are valuable shortcuts.

Revise the precedence for explicitly varied sets. A plan that deliberately programs 50 → 60 → 70 kg should not look like a repeated 50 kg workout after the first log. The current prefill deliberately prefers the previous logged weight in the same exercise; the probe confirmed the effect. Distinguish straight-set carry-forward from explicit per-set programming, and decide visibly whether an adjustment applies to “This set” or “Remaining sets.”

Avoid silently rewriting entered reps when weight changes. The current RepsDraft only protects reps once the user has edited them; otherwise it switches between historical reps and the target. A simpler starting point is to initialize the draft once and keep both values stable until the user changes them. If automatic rep adjustment is retained, make the changed value visibly understandable and test it with the owner.

Add the visible labels Reps and Weight or Load. Units explain scale but do not explain every number's purpose. Keep the target and previous result separate from the values about to be logged.

Remove duplicate history text. The current card can show a full “Last time” sequence including weight, plus another “Last 80 kg” line. A short set list with a previous-result column can communicate the relationship once.

Show progress in workout terms: “Exercise 2 of 5 · Set 2 of 3.” Drops should remain explicitly labeled as drops; supersets should show members and round position. The sample Push day contains 16 main sets and six drop steps, while the global header counts 22 “sets.” That internal flattening is useful for execution but can confuse progress at a glance.

Evidence: JimmsBro/Core/Prefill.swift, JimmsBro/Features/Workout/WorkoutView.swift, examples/valid/weekly-rotation.json and its manifest entry.

## 4. Make bringing in a plan feel guided

Keep the local JSON importer and chatbot workflow. They are useful capabilities and do not require a backend. Change the presentation.

The initial screen should explain the next action instead of presenting a large blank monospaced editor. Use “Add plan,” with Paste plan as the main path, plus a clearly named “Create with a chatbot” route and an Import file option.

For the chatbot route, show a short sequence: copy instructions, use them in your chatbot with your workout description, return and paste the reply. Preserve the draft while switching apps. A copied confirmation should briefly appear and then reset; the current button remains “Copied” for the lifetime of the view.

After pasting, show a human-readable preview. Prefer “Review plan” before “Save plan,” so users understand which action validates and which commits. Use one navigation flow rather than stacking a preview sheet over the import sheet.

The preview should allow inspection of exercises and varying set targets. It currently shows day names and counts, which cannot establish whether the chatbot produced the intended exercises, weights, or order.

Present errors at a useful level: “Bench Press, set 2 needs a rep target.” Put JSON paths and diagnostic codes under Details and retain them in the copyable repair prompt. Keep material warnings prominent. Warnings about a mismatched weight unit, removed load, or changed grouping deserve attention; stripping surrounding prose or ignoring an author field should not dominate a successful import.

Offer “Use as current plan” in the preview or save outcome, with the choice and current state clear. When another plan is already active, ImportView saves without makeActive and never asks. The new plan can be saved successfully while Home continues to show the old one.

Make replacement explicit from Plan detail. The specified Replace action is absent from the current menu, so users must discover same-name conflict handling through a fresh import.

Keep the sample plan available, but offer a short practice session before presenting the full advanced sample. The current sample's first day includes supersets, drops, and timed work. That makes it a useful regression fixture and a demanding introduction. Add a separate onboarding sample; do not modify the existing fixtures.

Evidence: JimmsBro/Features/Import/ImportView.swift, JimmsBro/Features/PlanDetail/PlanDetailView.swift, JimmsBro/Store/AppModel.swift, JimmsBro/Core/PlanLibrary.swift, docs/PROMPT.md. Visuals: build/o-import.png, build/o5-preview.png.

## 5. Make Home answer “What am I doing today?”

Lead with the selected plan, workout name, and a brief useful preview such as exercise count. Use “Start Push” or “Resume Push,” and make the workout name or Preview an obvious way to inspect it before starting. Provide a compact way to choose another day.

On a rest day, the primary copy should not pair “Rest day” with a generic Start that begins the next scheduled workout early. Say “Start Pull early” if that is the intended action, and keep the rest-day context clear.

Reduce the month calendar's default prominence. A compact current-week or recent-activity view plus an expandable month is worth testing. This is a proposal, not an assertion that the calendar has no value to you.

Complete the existing interactions before expanding calendar features. Tapping a date currently only toggles a text line; tapping again clears the selection. It cannot open the session detail or start the projected day, despite the documented design. On days with multiple sessions, the selected text chooses only the first. Make completed dates open the session or a short chooser.

Be cautious about projecting an event-driven rotation onto fixed dates. The existing projection makes assumptions about training every calendar day. Separate an actual weekday schedule from a flexible “next workout” sequence so the calendar does not suggest commitments the user never made.

Remove the tap-to-cycle six-metric sparkline from the default Home, or move metric selection into an explicit menu in History. Its interaction is hidden, and workout duration is not self-evidently a measure of progress. “2 workouts this week” is easier to understand without interpreting a line. Use wording that reports activity without implying that more duration is automatically better.

Keep the existing four native tabs for the first refinement. Moving Settings to a gear and using three tabs is optional; it would not fix the workout friction by itself.

Evidence: JimmsBro/Features/Home/HomeView.swift, JimmsBro/Core/HomeCard.swift, JimmsBro/Core/CalendarProjection.swift. Visuals: build/o29-home-seeded.png and build/o30-rest-dots.png.

## 6. Establish a coherent visual hierarchy

The blue accent and native controls are a sound starting point. The main visual work is composition:

- Use one shared spacing scale and consistent horizontal margins.
- Give the active exercise and editable values clear emphasis; use readable secondary text for targets and context.
- Reserve the largest countdown for timed work when watching it matters. A completed exercise's duration should not dominate the next action.
- Make control shapes and positions consistent across reps, timed work, rest, and completion.
- Give tappable names and disclosure rows a clear affordance. Decorative chips should not look like unexplained navigation.
- Use semantic color: accent for actions/current state, subdued neutrals for context, warning treatment for a meaningful issue.
- Use restrained pressed states and feedback. StepButton is an Image with gestures and has no explicit pressed appearance.
- Retain native navigation and familiar icons where they aid recognition. The blanket prohibition on icon-plus-text pairs is unnecessarily strict.

Plan detail should start with compact day rows and expand the selected day, rather than rendering every exercise from every day in a long list. Its exercise summary currently formats every set using only the first target: the sample's 24, 26, 28 kg incline sets are summarized as three sets at 24 kg. Show a per-set variation summary or expand the individual targets.

Accessibility is part of the professional finish. Calendar cells are assigned a 30-point height without a 44-point minimum target. Some small controls also need measurement. Apple's interface guidance recommends at least 44 × 44 points for touch controls. [Source](https://developer.apple.com/design/tips/)

Do not solve larger text by shrinking the most useful numbers: StepperRow currently uses 34-point numbers at accessibility sizes versus 44 normally. Reflow the layout, keep essential controls reachable, and verify the exercise-history action with VoiceOver. A combined accessibility label is not sufficient evidence that the link remains operable. Apple's Dynamic Type guidance emphasizes accommodating the user's text-size choice. [Source](https://developer.apple.com/videos/play/wwdc2024/10074/)

Visuals: build/o9-step-card.png, build/o18-dynamic-type.png, build/o-plandetail.png.

## 7. Make the summary useful in one glance

Show “Workout saved,” the day name, duration, and completed sets. Include one or two meaningful comparisons when the data supports them, then let users open details.

The current summary presents sequences such as “8@80, 8@80 … · last 10@80 …” in small text. Replace that with readable comparisons: “Bench press: 2 more reps at the same weight,” or a compact aligned table when loads vary. Do not invent a positive comparison when the session is not comparable.

Label total volume as Volume. A number followed only by kg can look like a lifted weight rather than reps multiplied by weight. Omit irrelevant zero volume for an entirely bodyweight or timed session.

Automatic rep-set duration includes time between the card appearing and the log tap. It cannot reliably measure actual lifting time. Demote it from the default summary and transition screen; if retained, describe it honestly. Timed exercise results remain directly useful.

Evidence: JimmsBro/Features/Summary/SummaryView.swift, JimmsBro/Core/Stats.swift, JimmsBro/Core/SessionEngine.swift. Visual: build/o13-summary.png.

## Small feature additions worth considering

**Basic plan editing.** Edit exercise names, sets, targets, load, and rest; reorder exercises; duplicate a day. This removes the need to return to a chatbot for a small change. Keep the import format and avoid building a large exercise catalog. Export/copy should represent the current edited plan, not stale sourceText.

**Do later.** When equipment is occupied, move the exercise later in the current workout while preserving it as pending. This is more useful than forcing the user to skip it or navigate individual pending sets. Add substitution only if needed; actual substitute exercises must keep their own history identity.

**A small exercise-progress view.** Make exercise lookup direct in History, then add one meaningful chart with readable units and a short result list. Do not start with a multi-metric dashboard. The Core history query already exists, but presentation and comparability still need design.

**Restore backup.** Export is already present, but there is no in-app restore. Complete that loop with validation, a preview, and a clear merge/replace choice. This can remain in Settings without adding daily interface clutter.

**Live Activity, later.** If checking rest while the phone is locked is frequent, this would be a useful convenience. It should follow the in-app flow fixes and accompany physical-device validation.

Warm-up support, session notes, per-exercise weight increments, and a plate calculator may help particular routines. Add them only when a recurring use case justifies them.

## Features and presentation to remove or postpone

Remove the mandatory full-screen exercise-completion gate, duplicated last-weight text, hidden chart-metric cycling, and prominent low-consequence import diagnostics. Demote automatic rep-set timing and dense summary dumps.

Postpone social feeds, badges, streak pressure, calorie estimates, nutrition, recovery scores, an in-app chatbot, broad exercise video libraries, extensive themes, automatic progression changes, and a large analytics dashboard. These do not solve the friction visible in the current flows.

Preserve local storage, no account requirement, Date-based timers, session snapshots, previous-result prefill, optional progression advice, supersets, drops, timed work, and export. Simplify how these capabilities are presented.

## How to validate the redesign

Before implementing a broad redesign, use the proposed workout direction for a focused owner walkthrough, then test a small SwiftUI slice on the simulator and iPhone.

Suggested acceptance criteria, not results already achieved:

1. From Home, start the intended workout without guessing which plan is active.
2. Log a normal prefilled rep set in one tap.
3. Correct the immediately previous set in at most two deliberate actions, while rest continues.
4. Recover a skipped set and verify the result survives reopening the session.
5. Inspect all exercises with one visible action during work and rest.
6. Minimize and resume with the exact active state preserved.
7. Run a pyramid with explicitly different target weights without fighting prefill.
8. Import a second plan, understand any material warning, and choose whether to activate it.
9. Tap a completed calendar day and reach the correct session, including a day with two workouts.
10. Complete the main tasks at large text sizes, with the keyboard visible, and with VoiceOver.
11. Simulate a persistence failure and verify the app retains recoverable data and offers a truthful retry.
12. Check timers, sound, locking, and one-handed use on the physical phone.

Ask a few people unfamiliar with the app to perform the same tasks without coaching. Record hesitation, wrong turns, and failed recovery as well as taps. Treat a small round as directional feedback, not a statistically representative verdict.

For implementation, revise the conflicting sections of SPEC and TEST_CASES first, then preserve the Core/view separation and finish each scoped milestone with appropriate automated and simulator checks. Existing tests establish conformance to previous rules; they do not establish that those rules produce an intuitive product.
`````

---

### FILE: schema/plan.schema.json

`````json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://jimmsbro.local/plan.schema.json",
  "title": "Jimm's Bro+ workout plan (schemaVersion 1, strict shape)",
  "description": "The canonical shape. The app additionally accepts the leniency forms in docs/PLAN_FORMAT.md §3 (bare day, numeric strings, curly quotes, rep strings like '8-12', weight strings like '60kg').",
  "type": "object",
  "required": [
    "days"
  ],
  "properties": {
    "schemaVersion": {
      "type": "integer",
      "const": 1
    },
    "name": {
      "type": "string",
      "maxLength": 100
    },
    "units": {
      "type": "string",
      "enum": [
        "kg",
        "lb"
      ]
    },
    "defaultRestSeconds": {
      "$ref": "#/$defs/rest"
    },
    "schedule": {
      "type": "string",
      "enum": [
        "rotation",
        "weekday"
      ]
    },
    "days": {
      "type": "array",
      "minItems": 1,
      "maxItems": 31,
      "items": {
        "$ref": "#/$defs/day"
      }
    },
    "cycle": {
      "type": "array",
      "minItems": 1,
      "maxItems": 31,
      "items": {
        "type": "string"
      }
    }
  },
  "$defs": {
    "rest": {
      "type": "integer",
      "minimum": 0,
      "maximum": 3600
    },
    "reps": {
      "oneOf": [
        {
          "type": "integer",
          "minimum": 1,
          "maximum": 1000
        },
        {
          "type": "string",
          "pattern": "^\\s*(\\d{1,4}\\s*[-–—/]\\s*\\d{1,4}|\\d{1,4}\\s*to\\s*\\d{1,4}|\\d{1,4}\\s*\\+?|(?i:amrap|max|failure|to failure|as many as possible))\\s*(?i:reps?)?\\s*$"
        }
      ]
    },
    "weight": {
      "oneOf": [
        {
          "type": "number",
          "minimum": 0,
          "maximum": 10000
        },
        {
          "type": "string"
        }
      ]
    },
    "day": {
      "type": "object",
      "required": [
        "exercises"
      ],
      "properties": {
        "name": {
          "type": "string",
          "maxLength": 100
        },
        "weekday": {
          "type": "string",
          "pattern": "^(?i:mon|tue|wed|thu|fri|sat|sun)[a-z]*$"
        },
        "defaultRestSeconds": {
          "$ref": "#/$defs/rest"
        },
        "exercises": {
          "type": "array",
          "minItems": 1,
          "maxItems": 50,
          "items": {
            "$ref": "#/$defs/exercise"
          }
        }
      }
    },
    "exercise": {
      "type": "object",
      "required": [
        "name"
      ],
      "properties": {
        "name": {
          "type": "string",
          "minLength": 1,
          "maxLength": 100
        },
        "group": {
          "type": [
            "string",
            "integer",
            "null"
          ]
        },
        "notes": {
          "type": [
            "string",
            "null"
          ],
          "maxLength": 500
        },
        "sets": {
          "oneOf": [
            {
              "type": "integer",
              "minimum": 1,
              "maximum": 50
            },
            {
              "type": "array",
              "minItems": 1,
              "maxItems": 50,
              "items": {
                "$ref": "#/$defs/set"
              }
            }
          ]
        },
        "reps": {
          "$ref": "#/$defs/reps"
        },
        "repRange": {
          "$ref": "#/$defs/repRange"
        },
        "durationSeconds": {
          "$ref": "#/$defs/duration"
        },
        "weight": {
          "$ref": "#/$defs/weight"
        },
        "restSeconds": {
          "$ref": "#/$defs/rest"
        },
        "drops": {
          "$ref": "#/$defs/drops"
        },
        "bodyweight": {
          "type": "boolean"
        },
        "warningBeep": {
          "$ref": "#/$defs/warningBeep"
        }
      }
    },
    "set": {
      "type": "object",
      "properties": {
        "reps": {
          "$ref": "#/$defs/reps"
        },
        "durationSeconds": {
          "$ref": "#/$defs/duration"
        },
        "weight": {
          "$ref": "#/$defs/weight"
        },
        "restSeconds": {
          "$ref": "#/$defs/rest"
        },
        "drops": {
          "$ref": "#/$defs/drops"
        },
        "warningBeep": {
          "$ref": "#/$defs/warningBeep"
        }
      },
      "not": {
        "required": [
          "reps",
          "durationSeconds"
        ]
      }
    },
    "repRange": {
      "oneOf": [
        {
          "type": "integer",
          "minimum": 1,
          "maximum": 1000
        },
        {
          "type": "string",
          "pattern": "^\\s*\\d{1,4}\\s*(?:[-–—/]|to)\\s*\\d{1,4}\\s*$|^\\s*\\d{1,4}\\s*$"
        }
      ]
    },
    "drop": {
      "type": "object",
      "properties": {
        "weight": {
          "$ref": "#/$defs/weight"
        },
        "reps": {
          "$ref": "#/$defs/reps"
        }
      }
    },
    "drops": {
      "type": "array",
      "minItems": 1,
      "maxItems": 5,
      "items": {
        "$ref": "#/$defs/drop"
      }
    },
    "duration": {
      "oneOf": [
        {
          "type": "integer",
          "minimum": 1,
          "maximum": 86400
        },
        {
          "type": "string",
          "pattern": "^\\s*(\\d{1,5}\\s*\\+?|(?i:max|open|amsap|as long as possible|to failure))\\s*$"
        }
      ]
    },
    "warningBeep": {
      "oneOf": [
        {
          "type": "boolean"
        },
        {
          "type": "integer",
          "minimum": 1,
          "maximum": 86399
        }
      ]
    }
  }
}`````

---

### FILE: tools/reference_import.py

`````python
#!/usr/bin/env python3
"""
Reference implementation of the Jimm's Bro+ import pipeline (docs/SPEC.md §6.1–6.3, docs/PLAN_FORMAT.md).
Purpose: (1) prove examples/manifest.json is consistent with the rules, (2) give the Swift port an oracle.
Run:  python3 tools/reference_import.py            -> checks every fixture against the manifest
      python3 tools/reference_import.py FILE       -> prints the normalized plan + issues for one file
No third-party dependencies.
"""
import json, re, sys, os, datetime

MARKER = "JIMMSBRO-PLAN-PROMPT-V1"
MAX_BYTES = 1_048_576
LIMITS = dict(days=31, exercises=50, sets=50, reps=1000, weight=10000, rest=3600, duration=86400, name=100, notes=500)
WEEKDAYS = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
DEFAULT_SETTINGS = dict(units="kg", defaultRestSeconds=90)


class Issue(dict):
    def __init__(self, severity, code, path, message):
        super().__init__(severity=severity, code=code, path=path, message=message)


def err(code, path, msg): return Issue("error", code, path, msg)
def warn(code, path, msg): return Issue("warning", code, path, msg)


# ---------------------------------------------------------------- 1. Extract
def _scan_json_value(t, start):
    """Return index just past the JSON value starting at t[start] ('{' or '['), string-aware. None if unbalanced."""
    depth, i, in_str, esc = 0, start, False, False
    while i < len(t):
        c = t[i]
        if in_str:
            if esc: esc = False
            elif c == "\\": esc = True
            elif c == '"': in_str = False
        else:
            if c == '"': in_str = True
            elif c in "{[": depth += 1
            elif c in "}]":
                depth -= 1
                if depth == 0: return i + 1
        i += 1
    return None


def extract(text):
    issues = []
    if len(text.encode("utf-8")) > MAX_BYTES:
        return None, [err("E_TOO_LARGE", "", "The pasted text is over 1 MB. Paste one plan at a time.")]
    t = re.sub("[﻿​‌‍]", "", text)
    if not t.strip():
        return None, [err("E_EMPTY", "", "Nothing to import. Paste the JSON the chatbot produced.")]
    fences = [m.group(1) for m in re.finditer(r"```[A-Za-z0-9_-]*[ \t]*\r?\n?(.*?)```", t, re.S)]
    fences = [f.strip() for f in fences if f.strip()]
    if MARKER in t and not fences:
        return None, [err("E_PROMPT_PASTED", "", "That's the prompt. Paste the chatbot's JSON reply instead.")]
    if fences:
        if len(fences) > 1:
            return None, [err("E_MULTIPLE_OBJECTS", "", "Found more than one code block. Paste just one plan.")]
        outside = re.sub(r"```[A-Za-z0-9_-]*[ \t]*\r?\n?.*?```", "", t, flags=re.S)
        if outside.strip():
            issues.append(warn("W_SURROUNDING_TEXT", "", "Text around the code block was ignored."))
        return fences[0], issues
    starts = [i for i in (t.find("{"), t.find("[")) if i >= 0]
    if not starts:
        return None, [err("E_NOT_JSON", "", "No JSON found in the pasted text.")]
    s = min(starts)
    e = _scan_json_value(t, s)
    if e is None:
        return t[s:], issues  # unbalanced: let the decoder produce the error message
    rest = t[e:].strip()
    if rest[:1] in ("{", "["):
        return None, [err("E_MULTIPLE_OBJECTS", "", "Found more than one JSON object. Paste just one plan.")]
    if t[:s].strip() or rest:
        issues.append(warn("W_SURROUNDING_TEXT", "", "Text around the JSON was ignored."))
    return t[s:e], issues


# ---------------------------------------------------------------- 2. Decode
def _strict_loads(s):
    def bad_const(c): raise ValueError(f"Invalid literal {c}")
    return json.loads(s, parse_constant=bad_const)


def decode(body):
    try:
        return _strict_loads(body), []
    except ValueError as first:
        if re.search("[“”„]", body):
            try:
                obj = _strict_loads(re.sub("[“”„]", '"', body))
                return obj, [warn("W_CURLY_QUOTES_FIXED", "", "Curly quotes were replaced with straight quotes.")]
            except ValueError:
                pass
        return None, [err("E_NOT_JSON", "", f"This isn't valid JSON: {first}. Ask the chatbot for strict JSON, or use Copy fix-it prompt.")]


# ---------------------------------------------------------------- 3+4. Normalize + validate
def _is_int_like(v):
    if isinstance(v, bool): return False
    if isinstance(v, int): return True
    if isinstance(v, float): return v.is_integer()
    if isinstance(v, str): return re.fullmatch(r"\s*\d+\s*", v) is not None
    return False


def _as_int(v): return int(float(v)) if not isinstance(v, str) else int(v.strip())


def _parse_int_field(v, path, code, lo, hi, issues, what):
    if v is None: return None
    if not _is_int_like(v):
        issues.append(err(code, path, f"{what} must be a whole number, got {json.dumps(v)}.")); return None
    n = _as_int(v)
    if n < lo or n > hi:
        issues.append(err(code, path, f"{what} must be between {lo} and {hi}, got {n}.")); return None
    return n


REP_WORDS = {"amrap", "max", "failure", "to failure", "as many as possible"}


def parse_reps(v, path, issues):
    """Returns ('fixed', n) | ('range', lo, hi) | ('amrap', min_or_None) or None (error appended)."""
    bad = lambda: issues.append(err("E_REPS_INVALID", path, f'{json.dumps(v, ensure_ascii=False)} is not a valid reps value. Use a whole number, a range like "8-12", "AMRAP", or "10+".'))
    if isinstance(v, bool) or v is None or isinstance(v, (dict, list)): bad(); return None
    if isinstance(v, (int, float)):
        if isinstance(v, float) and not v.is_integer(): bad(); return None
        n = int(v)
        if 1 <= n <= LIMITS["reps"]: return ("fixed", n)
        bad(); return None
    s = str(v).strip().lower()
    s = re.sub(r"\s*reps?$", "", s)
    if s in REP_WORDS: return ("amrap", None)
    m = re.fullmatch(r"(\d+)\s*\+", s)
    if m:
        n = int(m.group(1))
        if 1 <= n <= LIMITS["reps"]: return ("amrap", n)
        bad(); return None
    m = re.fullmatch(r"(\d+)\s*(?:-|–|—|/|to)\s*(\d+)", s)
    if m:
        a, b = int(m.group(1)), int(m.group(2))
        if not (1 <= a <= LIMITS["reps"] and 1 <= b <= LIMITS["reps"]): bad(); return None
        if a == b: return ("fixed", a)
        if a > b:
            issues.append(warn("W_RANGE_SWAPPED", path, f'"{v}" was read as {b}-{a}.'))
            a, b = b, a
        return ("range", a, b)
    if re.fullmatch(r"\d+", s):
        n = int(s)
        if 1 <= n <= LIMITS["reps"]: return ("fixed", n)
    bad(); return None


def parse_duration(v, path, issues):
    """PLAN_FORMAT §3.12. Returns ("duration", n) | ("open", min_or_None) | None."""
    bad = lambda: issues.append(err("E_DURATION_INVALID", path, f'{json.dumps(v, ensure_ascii=False)} is not a valid duration. Use whole seconds (1-86400), "max", or "30+".'))
    if isinstance(v, str) and not re.fullmatch(r"\s*\d+\s*", v):
        s = v.strip().lower()
        if s in OPEN_WORDS: return ("open", None)
        m = re.fullmatch(r"(\d+)\s*\+", s)
        if m and 1 <= int(m.group(1)) <= LIMITS["duration"]: return ("open", int(m.group(1)))
        bad(); return None
    tmp = []
    n = _parse_int_field(v, path, "E_DURATION_INVALID", 1, LIMITS["duration"], tmp, "durationSeconds")
    issues.extend(tmp)
    return ("duration", n) if n is not None else None


def parse_warning(v, path, issues):
    """PLAN_FORMAT §3.12. Returns "off" | "pct" | ("sec", n) | None (error appended). v is not None."""
    if isinstance(v, bool): return "pct" if v else "off"
    if not isinstance(v, str) and _is_int_like(v) and 1 <= _as_int(v) <= 86399: return ("sec", _as_int(v))
    issues.append(err("E_WARNING_BEEP_INVALID", path, f"warningBeep must be true, false, or a whole number of seconds before the end, got {json.dumps(v)}."))
    return None


def resolve_warning(spec, work, path, issues):
    """spec: None (absent) | "off" | "pct" | ("sec", n). Returns seconds or None."""
    if work is None: return None
    if work[0] != "duration":
        if spec is not None: issues.append(warn("W_WARNING_BEEP_IGNORED", path, "warningBeep only applies to sets with a fixed durationSeconds."))
        return None
    d = work[1]
    if spec is None or spec == "pct":
        return None if d < 10 else max(1, int(d / 10 + 0.5))
    if spec == "off": return None
    n = spec[1]
    if n >= d:
        issues.append(warn("W_WARNING_BEEP_IGNORED", path, f"warningBeep {n} is not before the end of a {d} s set.")); return None
    return n


BW_FLAG_WORDS = {"bw", "bodyweight", "body weight"}
BW_WORDS = {"bw", "bodyweight", "body weight", "none", ""}


def parse_weight(v, path, units, issues):
    """Returns (present: bool, value or None)."""
    bad = lambda: issues.append(err("E_WEIGHT_INVALID", path, f"{json.dumps(v, ensure_ascii=False)} is not a valid weight. Use a number in {units}, or leave it out for bodyweight."))
    if v is None: return (False, None)
    if isinstance(v, bool) or isinstance(v, (dict, list)): bad(); return (True, None)
    if isinstance(v, str):
        s = v.strip().lower()
        if s in BW_FLAG_WORDS: return (False, "bw")
        if s in BW_WORDS: return (False, None)
        m = re.fullmatch(r"\+?\s*(\d+(?:[.,]\d+)?)\s*([a-z]*)\.?", s)
        if not m: bad(); return (True, None)
        num = float(m.group(1).replace(",", "."))
        unit = m.group(2)
        unit_norm = {"kg": "kg", "kgs": "kg", "kilograms": "kg", "kilogram": "kg", "lb": "lb", "lbs": "lb", "pounds": "lb", "pound": "lb"}.get(unit)
        if unit and unit_norm is None: bad(); return (True, None)
        if unit_norm and unit_norm != units:
            issues.append(warn("W_WEIGHT_UNIT_IGNORED", path, f'The unit in "{v}" was ignored; this plan uses {units}.'))
    else:
        num = float(v)
    if num < 0 or num > LIMITS["weight"]: bad(); return (True, None)
    rounded = round(num + 1e-9, 1)
    if abs(rounded - num) > 1e-9:
        issues.append(warn("W_WEIGHT_ROUNDED", path, f"{num} was rounded to {rounded}."))
    return (True, rounded)


def _clip_name(v, path, default, issues, default_code=True):
    if v is None or not isinstance(v, str) or not v.strip():
        if default_code: issues.append(warn("W_DEFAULT_NAME", path, f'No name given; using "{default}".'))
        return default
    s = v.strip()
    if len(s) > LIMITS["name"]:
        issues.append(warn("W_NAME_TRUNCATED", path, "Name was cut to 100 characters."))
        s = s[:LIMITS["name"]]
    return s


def normalize_name(s): return re.sub(r"\s+", " ", s.strip()).lower()


KNOWN_PLAN = {"schemaVersion", "name", "units", "defaultRestSeconds", "schedule", "cycle", "days"}
KNOWN_DAY = {"name", "weekday", "defaultRestSeconds", "exercises"}
KNOWN_EX = {"name", "group", "notes", "sets", "reps", "repRange", "durationSeconds", "warningBeep", "bodyweight", "weight", "restSeconds", "drops"}
KNOWN_SET = {"reps", "durationSeconds", "warningBeep", "weight", "restSeconds", "drops"}
OPEN_WORDS = {"max", "open", "amsap", "as long as possible", "to failure"}
KNOWN_DROP = {"reps", "weight"}


def parse_drops(v, path, units, issues):
    """PLAN_FORMAT §3.11. Returns list of {"work","weight"} or None (error appended)."""
    if not isinstance(v, list) or not v or len(v) > 5 or not all(isinstance(d, dict) for d in v):
        issues.append(err("E_DROPS_INVALID", path, "drops must be a list of 1 to 5 objects like { \"weight\": 20 }.")); return None
    out = []
    for j, d in enumerate(v):
        dp = f"{path}[{j}]"
        _unknown(d, KNOWN_DROP, dp, issues)
        work = ("reps", ("amrap", None))
        if d.get("reps") is not None:
            pr = parse_reps(d["reps"], f"{dp}.reps", issues)
            work = ("reps", pr) if pr else None
        w = None
        if d.get("weight") is not None:
            _, w = parse_weight(d["weight"], f"{dp}.weight", units, issues)
            if w == "bw": w = None
        out.append({"work": work, "weight": w})
    return out


def _unknown(obj, known, path, issues):
    for k in obj:
        if k not in known:
            issues.append(warn("W_UNKNOWN_FIELD", f"{path}.{k}" if path else k, f'Field "{k}" was ignored.'))


def _parse_units(v, path, settings, issues):
    if v is None: return settings["units"]
    m = {"kg": "kg", "kgs": "kg", "kilogram": "kg", "kilograms": "kg", "lb": "lb", "lbs": "lb", "pound": "lb", "pounds": "lb"}
    u = m.get(str(v).strip().lower()) if isinstance(v, str) else None
    if u is None: issues.append(err("E_UNITS_INVALID", path, f'units must be "kg" or "lb", got {json.dumps(v)}.'))
    return u or settings["units"]


def _parse_weekday(v, path, issues):
    if not isinstance(v, str): issues.append(err("E_WEEKDAY_INVALID", path, f"{json.dumps(v)} is not a weekday.")); return None
    s = v.strip().lower()
    for w in WEEKDAYS:
        if s == w or s == w[:3]: return w
    issues.append(err("E_WEEKDAY_INVALID", path, f'"{v}" is not a weekday. Use "monday" … "sunday".')); return None


def normalize(obj, settings=DEFAULT_SETTINGS, today=None):
    issues = []
    today = today or datetime.date.today().isoformat()
    # ---- shape
    wrapped = False
    if isinstance(obj, dict) and "days" in obj:
        raw = obj
    elif isinstance(obj, dict) and "exercises" in obj:
        raw = {"name": obj.get("name"), "days": [obj]}; wrapped = True
    elif isinstance(obj, list) and obj and all(isinstance(d, dict) and "exercises" in d for d in obj):
        raw = {"days": obj}; wrapped = True
    elif isinstance(obj, list) and obj and all(isinstance(d, dict) and "name" in d and "exercises" not in d for d in obj):
        raw = {"days": [{"exercises": obj}]}; wrapped = True
    else:
        kind = type(obj).__name__ if not isinstance(obj, dict) else "an object without days or exercises"
        return None, [err("E_NOT_A_PLAN", "", f"This JSON isn't a workout plan (found {kind}).")]
    if wrapped: issues.append(warn("W_WRAPPED_SINGLE_DAY", "", "Wrapped the pasted content into a plan."))
    _unknown(raw, KNOWN_PLAN, "", issues) if not wrapped else None
    if wrapped and isinstance(obj, dict): _unknown(obj, KNOWN_DAY | {"name"}, "days[0]", issues)

    # ---- plan fields
    sv = raw.get("schemaVersion")
    if sv is not None:
        if not _is_int_like(sv) or _as_int(sv) > 1:
            issues.append(err("E_SCHEMA_VERSION", "schemaVersion", f"This plan needs schemaVersion {sv}; the app supports 1. Update the app."))
    name = _clip_name(raw.get("name"), "name", f"Imported plan {today}", issues)
    units = _parse_units(raw.get("units"), "units", settings, issues)
    plan_rest = _parse_int_field(raw.get("defaultRestSeconds"), "defaultRestSeconds", "E_REST_INVALID", 0, LIMITS["rest"], issues, "defaultRestSeconds")
    days_raw = raw.get("days")
    if not isinstance(days_raw, list) or not days_raw:
        issues.append(err("E_NO_DAYS", "days", "The plan has no days. Add at least one day with exercises."))
        return None, issues
    if len(days_raw) > LIMITS["days"]:
        issues.append(err("E_LIMIT_EXCEEDED", "days", f"Too many days ({len(days_raw)}); the limit is {LIMITS['days']}."))
        return None, issues

    days = []
    for di, d in enumerate(days_raw):
        dp = f"days[{di}]"
        if not isinstance(d, dict):
            issues.append(err("E_NO_EXERCISES", f"{dp}.exercises", "Each day must be an object with exercises.")); continue
        _unknown(d, KNOWN_DAY, dp, issues)
        dname = _clip_name(d.get("name"), f"{dp}.name", (name if (wrapped and isinstance(obj, dict)) else f"Day {di + 1}"), issues, default_code=not (wrapped and isinstance(obj, dict) and d.get("name")))
        weekday_raw = d.get("weekday")
        day_rest = _parse_int_field(d.get("defaultRestSeconds"), f"{dp}.defaultRestSeconds", "E_REST_INVALID", 0, LIMITS["rest"], issues, "defaultRestSeconds")
        exs_raw = d.get("exercises")
        if not isinstance(exs_raw, list) or not exs_raw:
            issues.append(err("E_NO_EXERCISES", f"{dp}.exercises", f'Day "{dname}" has no exercises.'))
            days.append({"name": dname, "weekday_raw": weekday_raw, "exercises": []}); continue
        if len(exs_raw) > LIMITS["exercises"]:
            issues.append(err("E_LIMIT_EXCEEDED", f"{dp}.exercises", f"Too many exercises ({len(exs_raw)}); the limit is {LIMITS['exercises']}."))
            days.append({"name": dname, "weekday_raw": weekday_raw, "exercises": []}); continue
        exercises = []
        for ei, e in enumerate(exs_raw):
            ep = f"{dp}.exercises[{ei}]"
            if not isinstance(e, dict):
                issues.append(err("E_MISSING_NAME", f"{ep}.name", "Each exercise must be an object with a name.")); continue
            _unknown(e, KNOWN_EX, ep, issues)
            ename = e.get("name")
            if not isinstance(ename, str) or not ename.strip():
                issues.append(err("E_MISSING_NAME", f"{ep}.name", "Every exercise needs a name."))
                ename = "?"
            else:
                ename = _clip_name(ename, f"{ep}.name", "?", issues)
            group = e.get("group")
            group = str(group).strip().upper() if group is not None and str(group).strip() else None
            notes = e.get("notes")
            if notes is not None and isinstance(notes, str) and len(notes) > LIMITS["notes"]:
                issues.append(warn("W_NOTES_TRUNCATED", f"{ep}.notes", "Notes were cut to 500 characters.")); notes = notes[:LIMITS["notes"]]
            if notes is not None and not isinstance(notes, str): notes = str(notes)
            ex_rest = _parse_int_field(e.get("restSeconds"), f"{ep}.restSeconds", "E_REST_INVALID", 0, LIMITS["rest"], issues, "restSeconds")
            # exercise-level defaults
            ex_reps = parse_reps(e["reps"], f"{ep}.reps", issues) if "reps" in e and e["reps"] is not None else None
            ex_dur = parse_duration(e["durationSeconds"], f"{ep}.durationSeconds", issues) if e.get("durationSeconds") is not None else None
            ex_w_present, ex_w = parse_weight(e.get("weight"), f"{ep}.weight", units, issues)
            bodyweight = False
            if ex_w == "bw": bodyweight = True; ex_w = None
            if e.get("bodyweight") is not None:
                if isinstance(e["bodyweight"], bool): bodyweight = bodyweight or e["bodyweight"]
                else: issues.append(err("E_BODYWEIGHT_INVALID", f"{ep}.bodyweight", "bodyweight must be true or false."))
            ex_warn = parse_warning(e["warningBeep"], f"{ep}.warningBeep", issues) if e.get("warningBeep") is not None else None
            if bodyweight and ex_w is not None:
                issues.append(warn("W_BODYWEIGHT_WEIGHT_IGNORED", f"{ep}.weight", "Weight ignored on a bodyweight exercise.")); ex_w = None
            has_ex_reps = "reps" in e and e["reps"] is not None
            has_ex_dur = "durationSeconds" in e and e["durationSeconds"] is not None
            ex_drops = parse_drops(e["drops"], f"{ep}.drops", units, issues) if e.get("drops") is not None else None
            # repRange (PLAN_FORMAT §3.9)
            rep_range = None
            rr = e.get("repRange")
            if rr is not None:
                if has_ex_dur and not has_ex_reps:
                    issues.append(warn("W_REPRANGE_IGNORED", f"{ep}.repRange", "repRange is ignored on a timed exercise."))
                else:
                    tmp = []
                    parsed = parse_reps(rr, f"{ep}.repRange", tmp)
                    for t in tmp:
                        if t["code"] == "E_REPS_INVALID":
                            issues.append(err("E_REPRANGE_INVALID", f"{ep}.repRange", f'{json.dumps(rr, ensure_ascii=False)} is not a valid rep range. Use a range like "8-12".'))
                        else:
                            issues.append(t)
                    if parsed and parsed[0] == "fixed": rep_range = (parsed[1], parsed[1])
                    elif parsed and parsed[0] == "range": rep_range = (parsed[1], parsed[2])
                    elif parsed and parsed[0] == "amrap":
                        issues.append(err("E_REPRANGE_INVALID", f"{ep}.repRange", f'{json.dumps(rr, ensure_ascii=False)} is not a valid rep range. Use a range like "8-12".'))
                    if rep_range and ex_reps and ex_reps[0] == "fixed" and not (rep_range[0] <= ex_reps[1] <= rep_range[1]):
                        issues.append(warn("W_REPRANGE_OUTSIDE", f"{ep}.repRange", f"The reps target {ex_reps[1]} is outside repRange {rep_range[0]}-{rep_range[1]}."))
            elif ex_reps and ex_reps[0] == "range":
                rep_range = (ex_reps[1], ex_reps[2])
            sets_raw = e.get("sets", 1)
            set_specs = None
            if sets_raw is None: sets_raw = 1
            if isinstance(sets_raw, list):
                if not sets_raw:
                    issues.append(err("E_SETS_INVALID", f"{ep}.sets", "sets must be a number of sets or a non-empty list of sets."))
                elif len(sets_raw) > LIMITS["sets"]:
                    issues.append(err("E_LIMIT_EXCEEDED", f"{ep}.sets", f"Too many sets ({len(sets_raw)}); the limit is {LIMITS['sets']}."))
                else:
                    set_specs = []
                    for si, s in enumerate(sets_raw):
                        sp = f"{ep}.sets[{si}]"
                        if not isinstance(s, dict): s = {}
                        _unknown(s, KNOWN_SET, sp, issues)
                        has_reps = "reps" in s and s["reps"] is not None
                        has_dur = "durationSeconds" in s and s["durationSeconds"] is not None
                        if has_reps and has_dur:
                            issues.append(err("E_TARGET_CONFLICT", sp, "A set can't have both reps and durationSeconds.")); continue
                        if has_reps: work = ("reps", parse_reps(s["reps"], f"{sp}.reps", issues))
                        elif has_dur:
                            pd = parse_duration(s["durationSeconds"], f"{sp}.durationSeconds", issues)
                            if pd is None: continue
                            work = pd
                        elif has_ex_reps and has_ex_dur:
                            issues.append(err("E_TARGET_CONFLICT", ep, "An exercise can't have both reps and durationSeconds.")); continue
                        elif has_ex_reps: work = ("reps", ex_reps)
                        elif has_ex_dur:
                            if ex_dur is None: continue
                            work = ex_dur
                        else:
                            issues.append(err("E_TARGET_MISSING", sp, "Each set needs reps or durationSeconds.")); continue
                        if "weight" in s and s["weight"] is not None:
                            _, w = parse_weight(s["weight"], f"{sp}.weight", units, issues)
                            if w == "bw": w = None; bodyweight = True
                            elif w is not None and bodyweight:
                                issues.append(warn("W_BODYWEIGHT_WEIGHT_IGNORED", f"{sp}.weight", "Weight ignored on a bodyweight exercise.")); w = None
                        else:
                            w = ex_w
                        if s.get("warningBeep") is not None:
                            wspec = parse_warning(s["warningBeep"], f"{sp}.warningBeep", issues); wpath = f"{sp}.warningBeep"
                        else:
                            wspec = ex_warn; wpath = f"{ep}.warningBeep"
                        if wspec is None and s.get("warningBeep") is not None: beep = None
                        else: beep = resolve_warning(wspec, work, wpath, issues)
                        r = _parse_int_field(s.get("restSeconds"), f"{sp}.restSeconds", "E_REST_INVALID", 0, LIMITS["rest"], issues, "restSeconds")
                        drops = parse_drops(s["drops"], f"{sp}.drops", units, issues) if s.get("drops") is not None else ex_drops
                        if drops and work[0] != "reps":
                            issues.append(warn("W_DROPS_IGNORED", f"{sp}.drops", "Drops are ignored on a timed set.")); drops = None
                        set_specs.append({"work": work, "weight": w, "rest": r, "beep": beep, "drops": drops or []})
            elif _is_int_like(sets_raw) and 1 <= _as_int(sets_raw) <= LIMITS["sets"]:
                n = _as_int(sets_raw)
                if has_ex_reps and has_ex_dur:
                    issues.append(err("E_TARGET_CONFLICT", ep, "An exercise can't have both reps and durationSeconds."))
                elif not has_ex_reps and not has_ex_dur:
                    issues.append(err("E_TARGET_MISSING", ep, "Each exercise needs reps or durationSeconds."))
                else:
                    work = ("reps", ex_reps) if has_ex_reps else ex_dur
                    drops = ex_drops or []
                    beep = None
                    if work is not None:
                        if drops and work[0] != "reps":
                            issues.append(warn("W_DROPS_IGNORED", f"{ep}.drops", "Drops are ignored on a timed exercise.")); drops = []
                        beep = resolve_warning(ex_warn, work, f"{ep}.warningBeep", issues)
                        set_specs = [{"work": work, "weight": ex_w, "rest": None, "beep": beep, "drops": list(drops)} for _ in range(n)]
            elif _is_int_like(sets_raw) and _as_int(sets_raw) > LIMITS["sets"]:
                issues.append(err("E_LIMIT_EXCEEDED", f"{ep}.sets", f"Too many sets ({_as_int(sets_raw)}); the limit is {LIMITS['sets']}."))
                if has_ex_reps and has_ex_dur: issues.append(err("E_TARGET_CONFLICT", ep, "An exercise can't have both reps and durationSeconds."))
            else:
                issues.append(err("E_SETS_INVALID", f"{ep}.sets", f"sets must be a whole number from 1 to 50 or a list of sets, got {json.dumps(sets_raw)}."))
                if not has_ex_reps and not has_ex_dur: issues.append(err("E_TARGET_MISSING", ep, "Each exercise needs reps or durationSeconds."))
            exercises.append({"name": ename, "group": group, "notes": notes, "repRange": list(rep_range) if rep_range else None, "bodyweight": bodyweight, "rest": ex_rest, "set_specs": set_specs or []})
        days.append({"name": dname, "weekday_raw": weekday_raw, "rest": day_rest, "exercises": exercises})

    # ---- schedule + weekdays
    sched_raw = raw.get("schedule")
    sched = sched_raw.strip().lower() if isinstance(sched_raw, str) else None
    has_wd = [d["weekday_raw"] is not None for d in days]
    inferred = "weekday" if all(has_wd) else ("rotation" if not any(has_wd) else None)
    if sched in ("rotation", "weekday"):
        schedule = sched
    else:
        if sched_raw is not None:
            issues.append(warn("W_SCHEDULE_INFERRED", "schedule", f'schedule {json.dumps(sched_raw)} is not "rotation" or "weekday"; inferred from the days.'))
        if inferred is None:
            issues.append(err("E_SCHEDULE_MIXED", "schedule", 'Some days have a weekday and some don\'t. Give every day a weekday, or none, or set "schedule".'))
        schedule = inferred or "rotation"
    seen = {}
    for di, d in enumerate(days):
        dp = f"days[{di}].weekday"
        if schedule == "rotation":
            if d["weekday_raw"] is not None: issues.append(warn("W_WEEKDAY_IGNORED", dp, "weekday is ignored in a rotation plan."))
            d["weekday"] = None
        else:
            if d["weekday_raw"] is None:
                issues.append(err("E_WEEKDAY_MISSING", dp, f'Day "{d["name"]}" needs a weekday in a weekday plan.')); d["weekday"] = None; continue
            w = _parse_weekday(d["weekday_raw"], dp, issues)
            if w and w in seen: issues.append(err("E_WEEKDAY_DUPLICATE", dp, f'Two days are on {w}: "{seen[w]}" and "{d["name"]}".'))
            elif w: seen[w] = d["name"]
            d["weekday"] = w
        del d["weekday_raw"]

    # ---- duplicate day names
    counts = {}
    for di, d in enumerate(days):
        k = normalize_name(d["name"])
        counts[k] = counts.get(k, 0) + 1
        if counts[k] > 1:
            issues.append(warn("W_DAY_RENAMED", f"days[{di}].name", f'Renamed duplicate day to "{d["name"]} ({counts[k]})".'))
            d["name"] = f"{d['name']} ({counts[k]})"

    # ---- cycle (PLAN_FORMAT §3.10)
    cycle_raw = raw.get("cycle")
    if schedule == "weekday":
        if cycle_raw is not None: issues.append(warn("W_CYCLE_IGNORED", "cycle", "cycle is ignored in a weekday plan; it is derived from the weekdays."))
        by_wd = {d["weekday"]: d["name"] for d in days if d.get("weekday")}
        cycle = [by_wd.get(w, "rest") for w in WEEKDAYS]
    elif cycle_raw is None:
        cycle = [d["name"] for d in days]
    elif not isinstance(cycle_raw, list) or not cycle_raw or len(cycle_raw) > 31 or not all(isinstance(c, str) for c in cycle_raw):
        issues.append(err("E_CYCLE_INVALID", "cycle", 'cycle must be a list of 1 to 31 day names or "rest".')); cycle = [d["name"] for d in days]
    else:
        names = {normalize_name(d["name"]): d["name"] for d in days}
        cycle = []
        for ci, c in enumerate(cycle_raw):
            k = normalize_name(c)
            if k in ("rest", "off"): cycle.append("rest")
            elif k in names: cycle.append(names[k])
            else: issues.append(err("E_CYCLE_UNKNOWN_DAY", f"cycle[{ci}]", f'"{c}" is not one of this plan\'s days.'))
        missing = [d["name"] for d in days if d["name"] not in cycle]
        if missing and not any(i["code"] == "E_CYCLE_UNKNOWN_DAY" for i in issues):
            issues.append(warn("W_CYCLE_MISSING_DAY", "cycle", f"These days never appear in the cycle: {', '.join(missing)}."))

    # ---- groups
    for di, d in enumerate(days):
        exs = d["exercises"]
        runs = []  # (group, start, end)
        i = 0
        while i < len(exs):
            g = exs[i]["group"]; j = i
            while j + 1 < len(exs) and exs[j + 1]["group"] == g and g is not None: j += 1
            runs.append((g, i, j)); i = j + 1
        seen_g = {}
        for g, a, b in runs:
            if g is None: continue
            if g in seen_g:
                new = f"{g}{seen_g[g] + 1}"; seen_g[g] += 1
                issues.append(warn("W_GROUP_SPLIT", f"days[{di}].exercises[{a}].group", f'Group "{g}" appeared again after other exercises; treating it as a separate group "{new}".'))
                for k in range(a, b + 1): exs[k]["group"] = new
                g = new
            else:
                seen_g[g] = 1
            if a == b:
                issues.append(warn("W_GROUP_SINGLE", f"days[{di}].exercises[{a}].group", f'Group "{g}" has only one exercise; treating it as a normal exercise.'))
                exs[a]["group"] = None
            else:
                ns = {len(exs[k]["set_specs"]) for k in range(a, b + 1)}
                if len(ns) > 1:
                    issues.append(warn("W_GROUP_SET_MISMATCH", f"days[{di}].exercises[{a}].group", f'Exercises in group "{g}" have different set counts; shorter ones drop out of later rounds.'))

    # ---- rest resolution + final shape
    for d in days:
        for e in d["exercises"]:
            sets = []
            warned_drop_weights = False
            for s in e["set_specs"]:
                rest = next((r for r in (s["rest"], e["rest"], d.get("rest"), plan_rest, settings["defaultRestSeconds"]) if r is not None), 90)
                drops = s.get("drops", [])
                if e.get("bodyweight") and any(dr["weight"] is not None for dr in drops):
                    if not warned_drop_weights:
                        issues.append(warn("W_BODYWEIGHT_WEIGHT_IGNORED", "", f'Drop weights ignored on bodyweight exercise "{e["name"]}".'))
                        warned_drop_weights = True
                    drops = [{"work": dr["work"], "weight": None} for dr in drops]
                sets.append({"work": s["work"], "weight": s["weight"], "restSeconds": rest, "warningBeepSeconds": s.get("beep"), "drops": drops})
            e["sets"] = sets; e["explicitRest"] = e.pop("rest"); e.pop("set_specs")
        d.pop("rest", None)

    plan = {"name": name, "units": units, "schedule": schedule, "cycle": cycle, "days": days}
    if any(i["severity"] == "error" for i in issues): return None, issues
    return plan, issues


# ---------------------------------------------------------------- Steps + execution rest (SPEC §6.2, §6.3)
def flatten(day):
    exs = day["exercises"]; steps = []; i = 0; block = 0
    while i < len(exs):
        g = exs[i]["group"]; j = i
        if g is not None:
            while j + 1 < len(exs) and exs[j + 1]["group"] == g: j += 1
        members = list(range(i, j + 1))
        rounds = max(len(exs[m]["sets"]) for m in members)
        first = len(steps)
        for r in range(rounds):
            active = [m for m in members if r < len(exs[m]["sets"])]
            for k, m in enumerate(active):
                drops = exs[m]["sets"][r].get("drops", [])
                for dI in range(len(drops) + 1):
                    steps.append({"exerciseIndex": m, "setIndex": r, "dropIndex": dI, "blockIndex": block,
                                  "isLastInRound": k == len(active) - 1 and dI == len(drops), "isLastInBlock": False})
        if len(steps) > first: steps[-1]["isLastInBlock"] = True
        i = j + 1; block += 1
    return steps


def rest_after(day, steps, i, settings=DEFAULT_SETTINGS):
    """Rest started after logging step i, assuming all later steps are pending (SPEC §6.3)."""
    if i == len(steps) - 1: return 0
    st = steps[i]
    if st["isLastInBlock"] and steps[i + 1]["blockIndex"] != st["blockIndex"]: return "transition"
    if not st["isLastInRound"]: return 0
    ex = day["exercises"][st["exerciseIndex"]]
    if ex["group"] is None: return ex["sets"][st["setIndex"]]["restSeconds"]
    members = [e for e in day["exercises"] if e["group"] == ex["group"]]
    for m in members:
        if m["explicitRest"] is not None: return m["explicitRest"]
    return ex["sets"][st["setIndex"]]["restSeconds"]


# ---------------------------------------------------------------- Pipeline
def import_plan(text, settings=DEFAULT_SETTINGS, today=None):
    body, issues = extract(text)
    if body is None: return None, issues
    obj, dec = decode(body); issues += dec
    if dec and dec[-1]["severity"] == "error": return None, issues
    plan, norm = normalize(obj, settings, today); issues += norm
    return plan, issues


# ---------------------------------------------------------------- Manifest check
def _work_str(w):
    kind, v = w
    if kind == "duration": return f"duration:{v}"
    if kind == "open": return "open" if v is None else f"open:{v}"
    if v[0] == "fixed": return f"fixed:{v[1]}"
    if v[0] == "range": return f"range:{v[1]}-{v[2]}"
    return "amrap" if v[1] is None else f"amrap:{v[1]}"


def check_manifest(root):
    man = json.load(open(os.path.join(root, "examples", "manifest.json")))
    fails = 0
    for fx in man["fixtures"]:
        path = os.path.join(root, "examples", fx["file"])
        text = open(path, encoding="utf-8").read()
        plan, issues = import_plan(text, today="2026-09-04")
        errors = [(i["code"], i["path"]) for i in issues if i["severity"] == "error"]
        warnings = sorted(i["code"] for i in issues if i["severity"] == "warning")
        problems = []
        if fx["outcome"] == "valid":
            if plan is None or errors: problems.append(f"expected valid, got errors {errors}")
            if warnings != sorted(fx.get("warnings", [])): problems.append(f"warnings {warnings} != expected {sorted(fx.get('warnings', []))}")
            for key, exp in fx.get("checks", {}).items():
                got = None
                try:
                    if key == "planName": got = plan["name"]
                    elif key == "units": got = plan["units"]
                    elif key == "schedule": got = plan["schedule"]
                    elif key == "dayNames": got = [d["name"] for d in plan["days"]]
                    elif key == "weekdays": got = [d["weekday"] for d in plan["days"]]
                    elif key == "stepsPerDay": got = [len(flatten(d)) for d in plan["days"]]
                    elif key == "exerciseNames": got = {k: [e["name"] for e in plan["days"][int(k)]["exercises"]] for k in exp}
                    elif key == "groups": got = {k: [e["group"] for e in plan["days"][int(k)]["exercises"]] for k in exp}
                    elif key == "repRange": got = {k: plan["days"][int(k.split(".")[0])]["exercises"][int(k.split(".")[1])]["repRange"] for k in exp}
                    elif key == "notes": got = {k: plan["days"][int(k.split(".")[0])]["exercises"][int(k.split(".")[1])]["notes"] for k in exp}
                    elif key == "restPerSet": got = {k: [s["restSeconds"] for s in plan["days"][int(k.split(".")[0])]["exercises"][int(k.split(".")[1])]["sets"]] for k in exp}
                    elif key == "weightPerSet": got = {k: [s["weight"] for s in plan["days"][int(k.split(".")[0])]["exercises"][int(k.split(".")[1])]["sets"]] for k in exp}
                    elif key == "workPerSet": got = {k: [_work_str(s["work"]) for s in plan["days"][int(k.split(".")[0])]["exercises"][int(k.split(".")[1])]["sets"]] for k in exp}
                    elif key == "stepOrder": got = {k: [f'{s["exerciseIndex"]}.{s["setIndex"]}' + (f'.{s["dropIndex"]}' if s["dropIndex"] else "") for s in flatten(plan["days"][int(k)])] for k in exp}
                    elif key == "cycle": got = plan["cycle"]
                    elif key == "bodyweight": got = {k: plan["days"][int(k.split(".")[0])]["exercises"][int(k.split(".")[1])]["bodyweight"] for k in exp}
                    elif key == "warningPerSet": got = {k: [s["warningBeepSeconds"] for s in plan["days"][int(k.split(".")[0])]["exercises"][int(k.split(".")[1])]["sets"]] for k in exp}
                    elif key == "dropsPerSet": got = {k: [len(s["drops"]) for s in plan["days"][int(k.split(".")[0])]["exercises"][int(k.split(".")[1])]["sets"]] for k in exp}
                    elif key == "dropTargets":
                        got = {}
                        for k in exp:
                            d, e, si = (int(x) for x in k.split("."))
                            got[k] = [[_work_str(dr["work"]), dr["weight"]] for dr in plan["days"][d]["exercises"][e]["sets"][si]["drops"]]
                    elif key == "restAfterStep":
                        got = {}
                        for k in exp:
                            di, si = k.split(":"); d = plan["days"][int(di)]
                            got[k] = rest_after(d, flatten(d), int(si))
                    else: problems.append(f"unknown check {key}"); continue
                except Exception as ex:  # noqa
                    problems.append(f"check {key} crashed: {ex!r}"); continue
                if got != exp: problems.append(f"check {key}: got {got!r}, expected {exp!r}")
        else:
            if plan is not None: problems.append("expected invalid, but import succeeded")
            exp_errors = [(e["code"], e.get("path")) for e in fx["errors"]]
            got_set = set(errors)
            for code, p in exp_errors:
                if p is None:
                    if not any(c == code for c, _ in errors): problems.append(f"missing error {code}")
                elif (code, p) not in got_set: problems.append(f"missing error {code} at {p}; got {errors}")
            if fx.get("exact", True) and len(errors) != len(exp_errors): problems.append(f"error count {len(errors)} != {len(exp_errors)}: {errors}")
            if "warnings" in fx and warnings != sorted(fx["warnings"]): problems.append(f"warnings {warnings} != {sorted(fx['warnings'])}")
        if problems:
            fails += 1; print(f"FAIL {fx['file']}"); [print("   ", p) for p in problems]
    print(f"{len(man['fixtures']) - fails}/{len(man['fixtures'])} fixtures match the manifest")
    return fails == 0


if __name__ == "__main__":
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    if len(sys.argv) > 1:
        plan, issues = import_plan(open(sys.argv[1], encoding="utf-8").read())
        print(json.dumps({"plan": plan, "issues": issues}, indent=2, ensure_ascii=False, default=str))
    else:
        sys.exit(0 if check_manifest(root) else 1)
`````

---

### FILE: tools/generate_fixtures.py

`````python
#!/usr/bin/env python3
"""Regenerates examples/valid, examples/invalid, and examples/manifest.json from scratch.
Run from anywhere:  python3 tools/generate_fixtures.py
Then verify:        python3 tools/reference_import.py
"""
import json, os, re
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
os.makedirs("examples/valid", exist_ok=True); os.makedirs("examples/invalid", exist_ok=True)
root = ROOT
V = os.path.join(root, "examples/valid"); I = os.path.join(root, "examples/invalid")

def wj(d, name, obj): open(os.path.join(d, name), "w").write(json.dumps(obj, indent=2, ensure_ascii=False) + "\n")
def wt(d, name, text): open(os.path.join(d, name), "w").write(text)

push = {"name": "Push", "defaultRestSeconds": 120, "exercises": [
    {"name": "Barbell Bench Press", "sets": 4, "reps": "6-8", "weight": 80, "restSeconds": 150, "notes": "Pause on chest"},
    {"name": "Incline Dumbbell Press", "sets": [{"reps": 12, "weight": 24}, {"reps": 10, "weight": 26}, {"reps": 8, "weight": 28}], "repRange": "8-12", "restSeconds": 90},
    {"name": "Lateral Raise", "group": "A", "sets": 3, "reps": 15, "repRange": "12-15", "weight": 10, "restSeconds": 60},
    {"name": "Tricep Pushdown", "group": "A", "sets": 3, "reps": 12, "repRange": "10-12", "weight": 25, "restSeconds": 60, "drops": [{"weight": 20}, {"weight": 15}]},
    {"name": "Plank", "sets": 3, "durationSeconds": 45, "warningBeep": True, "bodyweight": True, "restSeconds": 45}]}
pull = {"name": "Pull", "exercises": [
    {"name": "Deadlift", "sets": 3, "reps": 5, "weight": 120, "restSeconds": 180},
    {"name": "Pull-Up", "sets": 4, "reps": "AMRAP", "restSeconds": 120},
    {"name": "Barbell Row", "sets": 3, "reps": "8-10", "weight": 70, "restSeconds": 90},
    {"name": "Face Pull", "group": "B", "sets": 3, "reps": 15, "weight": 15},
    {"name": "Dumbbell Curl", "group": "B", "sets": 3, "reps": 12, "weight": 12, "restSeconds": 60}]}
legs = {"name": "Legs", "exercises": [
    {"name": "Barbell Back Squat", "sets": 4, "reps": "5", "repRange": "4-6", "weight": 100, "restSeconds": 180},
    {"name": "Romanian Deadlift", "sets": 3, "reps": "8-10", "weight": 80, "restSeconds": 120},
    {"name": "Leg Press", "sets": 3, "reps": "10-12", "weight": 160, "restSeconds": 90},
    {"name": "Walking Lunge", "sets": 2, "reps": 20, "weight": 16, "restSeconds": 60, "notes": "10 each side"},
    {"name": "Standing Calf Raise", "sets": 4, "reps": "12-15", "weight": 60, "restSeconds": 45}]}

# ---------- valid ----------
wj(V, "weekly-rotation.json", {"schemaVersion": 1, "name": "Push Pull Legs", "units": "kg", "defaultRestSeconds": 90, "schedule": "rotation", "cycle": ["Push", "Pull", "Legs", "Push", "Pull", "Legs", "rest"], "days": [push, pull, legs]})
wj(V, "weekly-weekday.json", {"schemaVersion": 1, "name": "Mon Wed Fri Full Body", "units": "kg", "schedule": "weekday", "days": [
    {"name": "Full Body A", "weekday": "monday", "exercises": [{"name": "Barbell Back Squat", "sets": 3, "reps": 5, "weight": 100, "restSeconds": 180}, {"name": "Barbell Bench Press", "sets": 3, "reps": 5, "weight": 80, "restSeconds": 150}, {"name": "Barbell Row", "sets": 3, "reps": 5, "weight": 70, "restSeconds": 120}]},
    {"name": "Full Body B", "weekday": "Wed", "exercises": [{"name": "Deadlift", "sets": 1, "reps": 5, "weight": 140, "restSeconds": 180}, {"name": "Overhead Press", "sets": 3, "reps": 5, "weight": 50, "restSeconds": 150}, {"name": "Pull-Up", "sets": 3, "reps": "AMRAP", "restSeconds": 120}]},
    {"name": "Full Body C", "weekday": "FRIDAY", "exercises": [{"name": "Barbell Back Squat", "sets": 3, "reps": 5, "weight": 102.5, "restSeconds": 180}, {"name": "Barbell Bench Press", "sets": 3, "reps": 5, "weight": 82.5, "restSeconds": 150}, {"name": "Barbell Row", "sets": 3, "reps": 5, "weight": 72.5, "restSeconds": 120}]}]})
wj(V, "no-schedule-weekdays.json", {"name": "Inferred weekday", "days": [
    {"name": "Upper", "weekday": "tuesday", "exercises": [{"name": "Barbell Bench Press", "sets": 3, "reps": 8, "weight": 70}]},
    {"name": "Lower", "weekday": "thursday", "exercises": [{"name": "Barbell Back Squat", "sets": 3, "reps": 8, "weight": 90}]}]})
wj(V, "single-day.json", {"schemaVersion": 1, "name": "Quick Upper", "units": "kg", "days": [{"name": "Quick Upper", "exercises": [
    {"name": "Push-Up", "sets": 3, "reps": "15+", "restSeconds": 60},
    {"name": "Dumbbell Row", "sets": 3, "reps": 12, "weight": 20, "restSeconds": 60}]}]})
wj(V, "single-day-bare.json", {"name": "Hotel Workout", "exercises": [
    {"name": "Push-Up", "sets": 4, "reps": 20, "restSeconds": 45},
    {"name": "Bodyweight Squat", "sets": 4, "reps": 25, "restSeconds": 45},
    {"name": "Plank", "sets": 2, "durationSeconds": 60, "restSeconds": 60}]})
wj(V, "array-of-days.json", [
    {"name": "Day 1", "exercises": [{"name": "Barbell Bench Press", "sets": 3, "reps": 8, "weight": 60}]},
    {"name": "Day 2", "exercises": [{"name": "Barbell Back Squat", "sets": 3, "reps": 8, "weight": 80}]}])
wj(V, "array-of-exercises.json", [
    {"name": "Kettlebell Swing", "sets": 5, "reps": 20, "weight": 24, "restSeconds": 60},
    {"name": "Goblet Squat", "sets": 3, "reps": 12, "weight": 24, "restSeconds": 60}])
wj(V, "minimal.json", {"days": [{"exercises": [{"name": "Burpee", "reps": 10}]}]})
wj(V, "explicit-sets-pyramid.json", {"name": "Pyramid", "units": "kg", "days": [{"name": "Chest", "exercises": [
    {"name": "Barbell Bench Press", "restSeconds": 120, "sets": [{"reps": 12, "weight": 50}, {"reps": 10, "weight": 60}, {"reps": 8, "weight": 70}, {"reps": 6, "weight": 80}, {"reps": "AMRAP", "weight": 60, "restSeconds": 180}]},
    {"name": "Cable Fly", "weight": 15, "reps": 15, "sets": [{}, {}, {"reps": "12-15"}]}]}]})
wj(V, "superset-circuit.json", {"name": "Circuit Day", "units": "kg", "defaultRestSeconds": 60, "days": [{"name": "Circuit", "exercises": [
    {"name": "Goblet Squat", "group": "a", "sets": 3, "reps": 12, "weight": 20},
    {"name": "Push-Up", "group": "A", "sets": 3, "reps": 15},
    {"name": "Kettlebell Swing", "group": "A", "sets": 2, "reps": 20, "weight": 24, "restSeconds": 90},
    {"name": "Dead Hang", "sets": 2, "durationSeconds": 30, "restSeconds": 45}]}]})
wj(V, "timed-sets.json", {"name": "Core and Cardio", "days": [{"name": "Core", "exercises": [
    {"name": "Plank", "sets": 3, "durationSeconds": 45, "restSeconds": 30},
    {"name": "Side Plank", "sets": 2, "durationSeconds": 30, "restSeconds": 30, "notes": "each side"},
    {"name": "Stationary Bike", "sets": 1, "durationSeconds": 600, "restSeconds": 0},
    {"name": "Farmer Carry", "sets": 3, "durationSeconds": 40, "weight": 32, "restSeconds": 60},
    {"name": "Dead Hang", "sets": 2, "durationSeconds": "max", "bodyweight": True, "restSeconds": 60},
    {"name": "Max Plank", "sets": 1, "durationSeconds": "30+", "restSeconds": 0},
    {"name": "Wall Sit", "durationSeconds": 60, "warningBeep": 15, "sets": [{}, {"durationSeconds": "AMSAP", "warningBeep": 5}]},
    {"name": "Hollow Hold", "sets": 2, "durationSeconds": 20, "warningBeep": False},
    {"name": "Short Hold", "sets": 1, "durationSeconds": 8},
    {"name": "Late Warning", "sets": 1, "durationSeconds": 30, "warningBeep": 45},
    {"name": "Rounding", "sets": 1, "durationSeconds": 25}]}]})
wj(V, "bodyweight.json", {"name": "Calisthenics", "days": [{"name": "A", "exercises": [
    {"name": "Push-Up", "sets": 3, "reps": "15+", "bodyweight": True, "restSeconds": 60},
    {"name": "Pull-Up", "sets": 3, "reps": "AMRAP", "weight": "bodyweight", "restSeconds": 90},
    {"name": "Dip", "sets": 3, "reps": 10, "weight": 10, "restSeconds": 90},
    {"name": "Pistol Squat", "sets": 2, "reps": 6, "bodyweight": True, "weight": 5, "restSeconds": 60},
    {"name": "Bodyweight Row", "sets": 2, "reps": 12, "bodyweight": False, "warningBeep": True, "restSeconds": 60},
    {"name": "Nordic Curl", "sets": 2, "reps": 5, "bodyweight": True, "drops": [{"weight": 5}]}]}]})
wj(V, "rest-precedence.json", {"name": "Rest chain", "defaultRestSeconds": 100, "days": [
    {"name": "Day A", "defaultRestSeconds": 80, "exercises": [
        {"name": "Ex 1", "sets": 2, "reps": 10},
        {"name": "Ex 2", "sets": 2, "reps": 10, "restSeconds": 70},
        {"name": "Ex 3", "reps": 10, "restSeconds": 70, "sets": [{}, {"restSeconds": 60}]},
        {"name": "Ex 4", "sets": 1, "reps": 10, "restSeconds": 0}]},
    {"name": "Day B", "exercises": [{"name": "Ex 5", "sets": 1, "reps": 10}]}]})
wj(V, "lenient-values.json", {"schemaVersion": "1", "name": "Lenient", "units": "KGS", "days": [{"name": "Mixed", "exercises": [
    {"name": "  Barbell Bench Press ", "sets": "4", "reps": "8 to 12", "weight": "60kg", "restSeconds": "90"},
    {"name": "Incline Press", "sets": 3.0, "reps": "12-8", "weight": "22,5"},
    {"name": "Pull-Up", "sets": 3, "reps": "to failure", "weight": "bodyweight"},
    {"name": "Dip", "sets": 3, "reps": "10 +", "weight": "+10kg"},
    {"name": "Curl", "sets": 2, "reps": "12 reps", "weight": "135 lbs"},
    {"name": "Hammer Curl", "sets": 2, "reps": 10.0, "weight": 12.55}]}]})
wj(V, "unknown-fields.json", {"name": "Extras", "author": "coach", "days": [{"name": "A", "exercises": [
    {"name": "Barbell Back Squat", "sets": 3, "reps": 5, "weight": 100, "restSeconds": 180, "tempo": "3010", "rpe": 8, "equipment": "barbell"}]}]})
wj(V, "lb-plan.json", {"name": "US plan", "units": "lbs", "days": [{"name": "A", "exercises": [{"name": "Barbell Bench Press", "sets": 3, "reps": 5, "weight": 185, "restSeconds": 180}]}]})
wj(V, "duplicate-day-names.json", {"name": "Dupes", "days": [
    {"name": "Push", "exercises": [{"name": "Barbell Bench Press", "sets": 3, "reps": 8}]},
    {"name": "push ", "exercises": [{"name": "Overhead Press", "sets": 3, "reps": 8}]},
    {"name": "Push", "exercises": [{"name": "Dip", "sets": 3, "reps": 8}]}]})
wj(V, "group-edge-cases.json", {"name": "Groups", "days": [{"name": "A", "exercises": [
    {"name": "Curl", "group": "A", "sets": 3, "reps": 12},
    {"name": "Pushdown", "group": "A", "sets": 3, "reps": 12},
    {"name": "Barbell Back Squat", "group": "B", "sets": 3, "reps": 5},
    {"name": "Lateral Raise", "group": "A", "sets": 3, "reps": 15},
    {"name": "Plank", "group": " ", "sets": 2, "durationSeconds": 30}]}]})
wj(V, "nulls-and-defaults.json", {"name": None, "days": [{"name": None, "exercises": [
    {"name": "Row", "sets": 2, "reps": 10, "weight": None, "notes": None, "group": None}]}]})
wj(V, "long-names.json", {"name": "N" * 150, "days": [{"name": "D" * 120, "exercises": [{"name": "E" * 101, "sets": 1, "reps": 10, "notes": "x" * 600}]}]})
wj(V, "unicode-names.json", {"name": "🏋️ Программа", "days": [{"name": "胸 Chest", "exercises": [{"name": "Développé couché", "sets": 3, "reps": 8, "weight": 60}]}]})
wj(V, "rotation-with-weekdays.json", {"name": "Rotation ignores weekdays", "schedule": "rotation", "days": [
    {"name": "A", "weekday": "monday", "exercises": [{"name": "Row", "sets": 1, "reps": 10}]},
    {"name": "B", "weekday": "wednesday", "exercises": [{"name": "Row", "sets": 1, "reps": 10}]}]})
wj(V, "schedule-unknown-value.json", {"name": "Schedule typo", "schedule": "Weekly", "days": [
    {"name": "A", "exercises": [{"name": "Row", "sets": 1, "reps": 10}]}]})
wj(V, "boundaries.json", {"name": "Boundaries", "days": [{"name": "A", "exercises": [
    {"name": "Max reps", "sets": 50, "reps": 1000, "weight": 10000, "restSeconds": 3600},
    {"name": "Max duration", "sets": 1, "durationSeconds": 86400, "restSeconds": 0},
    {"name": "Zero weight", "sets": 1, "reps": 1, "weight": 0}]}]})
wj(V, "reprange-cases.json", {"name": "Rep ranges", "days": [{"name": "A", "exercises": [
    {"name": "Explicit", "sets": 3, "reps": 10, "repRange": "8-12"},
    {"name": "From reps range", "sets": 3, "reps": "8-12"},
    {"name": "None", "sets": 3, "reps": 10},
    {"name": "Outside", "sets": 3, "reps": 15, "repRange": "8-12"},
    {"name": "Timed", "sets": 2, "durationSeconds": 30, "repRange": "8-12"},
    {"name": "Single number", "sets": 3, "reps": 10, "repRange": 10},
    {"name": "Swapped", "sets": 3, "reps": 10, "repRange": "12-8"},
    {"name": "Per-set reps only", "sets": [{"reps": 12}, {"reps": 10}], "repRange": "8-12"},
    {"name": "Per-set no range", "sets": [{"reps": "8-12"}, {"reps": "8-12"}]}]}]})
wj(V, "drop-sets.json", {"name": "Drops", "units": "kg", "days": [{"name": "A", "exercises": [
    {"name": "Cable Fly", "sets": 3, "reps": 12, "weight": 20, "restSeconds": 60, "drops": [{"weight": 15}, {"weight": 10, "reps": "8-10"}]},
    {"name": "Leg Extension", "reps": 12, "weight": 50, "restSeconds": 60, "sets": [{}, {}, {"drops": [{"weight": 40}]}]},
    {"name": "Lat Pulldown", "sets": 2, "reps": 10, "weight": 60, "drops": [{"weight": 45}], "restSeconds": 90},
    {"name": "Plank", "sets": 2, "durationSeconds": 30, "drops": [{"weight": 5}]}]}]})
wj(V, "cycle-cases.json", {"name": "Cycle", "cycle": ["upper", "REST", "Lower", "off"], "days": [
    {"name": "Upper", "exercises": [{"name": "Row", "sets": 1, "reps": 10}]},
    {"name": "Lower", "exercises": [{"name": "Squat", "sets": 1, "reps": 10}]},
    {"name": "Arms", "exercises": [{"name": "Curl", "sets": 1, "reps": 10}]}]})
wj(V, "cycle-weekday-ignored.json", {"name": "Cycle ignored", "cycle": ["A", "rest"], "days": [
    {"name": "A", "weekday": "tuesday", "exercises": [{"name": "Row", "sets": 1, "reps": 10}]},
    {"name": "B", "weekday": "saturday", "exercises": [{"name": "Row", "sets": 1, "reps": 10}]}]})
wj(V, "braces-in-strings.json", {"name": "Braces {in} strings", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 1, "reps": 10, "notes": "hold {tight} and [breathe]"}]}]})

inner = json.dumps({"name": "From chat", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10, "restSeconds": 60}]}]}, indent=2)
wt(V, "fenced-plain.txt", "```json\n" + inner + "\n```\n")
wt(V, "fenced-with-prose.txt", "Here is your plan in the requested format:\n\n```json\n" + inner + "\n```\n\nLet me know if you want any changes!\n")
wt(V, "fenced-other-language.txt", "```javascript\n" + inner + "\n```\n")
wt(V, "prose-no-fence.txt", "Sure! Here's the JSON:\n" + inner + "\nEnjoy your workout.\n")
wt(V, "marker-and-json.txt", "JIMMSBRO-PLAN-PROMPT-V1\n(I pasted the prompt above by mistake but here is the plan too)\n```json\n" + inner + "\n```\n")
wt(V, "curly-quotes.txt", inner.replace('"', "\u201c", 1).replace('"', "\u201d", 1).replace('"name"', "\u201cname\u201d").replace('"days"', "\u201cdays\u201d"))
wt(V, "curly-in-string-value.txt", json.dumps({"name": "Quotes", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 1, "reps": 10, "notes": "\u201cslow\u201d eccentric"}]}]}, ensure_ascii=False))
wt(V, "bom-and-zero-width.txt", "\ufeff\u200b" + inner + "\u200b\n")
wt(V, "top-level-array-fenced.txt", "```json\n" + json.dumps([{"name": "Only day", "exercises": [{"name": "Row", "sets": 1, "reps": 10}]}]) + "\n```")

# ---------- invalid ----------
wt(I, "empty.txt", "")
wt(I, "whitespace.txt", "  \n\n\t \n")
wt(I, "prompt-pasted.txt", "JIMMSBRO-PLAN-PROMPT-V1\nYou are converting a workout plan into JSON for a workout-tracking app.\nReply with ONLY one JSON object.\nMy plan:\nMon: bench 3x8\n")
wt(I, "multiple-objects-fenced.txt", "Option A:\n```json\n" + inner + "\n```\nOption B:\n```json\n" + inner + "\n```\n")
wt(I, "multiple-objects-bare.txt", inner + "\n" + inner + "\n")
wt(I, "trailing-comma.txt", '{"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10},]}],}\n')
wt(I, "truncated.txt", "```json\n" + inner[: len(inner) // 2] + "\n")
wt(I, "comments.txt", '{\n  // my plan\n  "name": "X",\n  "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10}]}]\n}\n')
wt(I, "single-quotes.txt", "{'name': 'X', 'days': [{'name': 'A', 'exercises': [{'name': 'Row', 'sets': 3, 'reps': 10}]}]}\n")
wt(I, "not-json-at-all.txt", "Monday: bench press 3x8, rows 3x10\nWednesday: squats 5x5\n")
wt(I, "too-large.txt", "{" + " " * 1048577 + "}")
wj(I, "not-a-plan.json", {"foo": 1, "bar": [1, 2, 3]})
wj(I, "null-top-level.json", None)
wj(I, "days-not-array.json", {"name": "X", "days": {"name": "A"}})
wj(I, "no-days.json", {"name": "X", "days": []})
wj(I, "days-null.json", {"name": "X", "days": None})
wj(I, "no-exercises.json", {"name": "X", "days": [{"name": "A", "exercises": []}]})
wj(I, "missing-exercise-name.json", {"name": "X", "days": [{"name": "A", "exercises": [{"sets": 3, "reps": 10}]}]})
wj(I, "blank-exercise-name.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "   ", "sets": 3, "reps": 10}]}]})
wj(I, "sets-zero.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 0, "reps": 10}]}]})
wj(I, "sets-fraction.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 2.5, "reps": 10}]}]})
wj(I, "sets-word.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": "three", "reps": 10}]}]})
wj(I, "sets-empty-array.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": [], "reps": 10}]}]})
wj(I, "sets-too-many.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 51, "reps": 10}]}]})
wj(I, "reps-word.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": "ten"}]}]})
wj(I, "reps-zero.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 0}]}]})
wj(I, "reps-fraction.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10.5}]}]})
wj(I, "reps-triple-range.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": "8-12-15"}]}]})
wj(I, "reps-open-range.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": "8-"}]}]})
wj(I, "reps-too-big.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 1001}]}]})
wj(I, "reps-bool.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": True}]}]})
wj(I, "reprange-word.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10, "repRange": "lots"}]}]})
wj(I, "reprange-amrap.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10, "repRange": "AMRAP"}]}]})
wj(I, "reprange-zero.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10, "repRange": "0-5"}]}]})
wj(I, "drops-empty.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10, "drops": []}]}]})
wj(I, "drops-too-many.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10, "drops": [{"weight": 1}] * 6}]}]})
wj(I, "drops-not-list.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10, "drops": {"weight": 5}}]}]})
wj(I, "drops-bad-weight.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10, "drops": [{"weight": "heavy"}]}]}]})
wj(I, "cycle-unknown-day.json", {"name": "X", "cycle": ["A", "Legs"], "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10}]}]})
wj(I, "cycle-empty.json", {"name": "X", "cycle": [], "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10}]}]})
wj(I, "cycle-not-list.json", {"name": "X", "cycle": "A, rest", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10}]}]})
wj(I, "warning-beep-zero.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Plank", "sets": 3, "durationSeconds": 30, "warningBeep": 0}]}]})
wj(I, "warning-beep-too-long.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Plank", "sets": 3, "durationSeconds": 30, "warningBeep": 86400}]}]})
wj(I, "warning-beep-word.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Plank", "sets": 3, "durationSeconds": 30, "warningBeep": "soon"}]}]})
wj(I, "warning-beep-fraction.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Plank", "sets": [{"durationSeconds": 30, "warningBeep": 2.5}]}]}]})
wj(I, "duration-word.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Plank", "sets": 3, "durationSeconds": "forever"}]}]})
wj(I, "bodyweight-string.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Push-Up", "sets": 3, "reps": 10, "bodyweight": "yes"}]}]})
wj(I, "target-conflict-exercise.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10, "durationSeconds": 30}]}]})
wj(I, "target-conflict-set.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": [{"reps": 10, "durationSeconds": 30}]}]}]})
wj(I, "target-missing-exercise.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3}]}]})
wj(I, "target-missing-set.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": [{"weight": 20}]}]}]})
wj(I, "duration-zero.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Plank", "sets": 3, "durationSeconds": 0}]}]})
wj(I, "duration-string-unit.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Plank", "sets": 3, "durationSeconds": "30s"}]}]})
wj(I, "duration-too-long.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Bike", "sets": 1, "durationSeconds": 86401}]}]})
wj(I, "weight-negative.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10, "weight": -5}]}]})
wj(I, "weight-word.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10, "weight": "heavy"}]}]})
wj(I, "weight-too-big.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10, "weight": 10001}]}]})
wj(I, "rest-negative.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10, "restSeconds": -1}]}]})
wj(I, "rest-too-long.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10, "restSeconds": 3601}]}]})
wj(I, "rest-fraction.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10, "restSeconds": 90.5}]}]})
wj(I, "rest-string-unit.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10, "restSeconds": "1m30"}]}]})
wj(I, "rest-day-level-invalid.json", {"name": "X", "days": [{"name": "A", "defaultRestSeconds": -10, "exercises": [{"name": "Row", "sets": 3, "reps": 10}]}]})
wj(I, "weekday-invalid.json", {"name": "X", "schedule": "weekday", "days": [{"name": "A", "weekday": "Funday", "exercises": [{"name": "Row", "sets": 3, "reps": 10}]}]})
wj(I, "weekday-duplicate.json", {"name": "X", "days": [
    {"name": "A", "weekday": "friday", "exercises": [{"name": "Row", "sets": 3, "reps": 10}]},
    {"name": "B", "weekday": "Fri", "exercises": [{"name": "Row", "sets": 3, "reps": 10}]}]})
wj(I, "weekday-missing.json", {"name": "X", "schedule": "weekday", "days": [
    {"name": "A", "weekday": "monday", "exercises": [{"name": "Row", "sets": 3, "reps": 10}]},
    {"name": "B", "exercises": [{"name": "Row", "sets": 3, "reps": 10}]}]})
wj(I, "schedule-mixed.json", {"name": "X", "days": [
    {"name": "A", "weekday": "monday", "exercises": [{"name": "Row", "sets": 3, "reps": 10}]},
    {"name": "B", "exercises": [{"name": "Row", "sets": 3, "reps": 10}]}]})
wj(I, "schema-version-2.json", {"schemaVersion": 2, "name": "X", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10}]}]})
wj(I, "units-invalid.json", {"name": "X", "units": "stone", "days": [{"name": "A", "exercises": [{"name": "Row", "sets": 3, "reps": 10}]}]})
wj(I, "too-many-days.json", {"name": "X", "days": [{"name": f"Day {i+1}", "exercises": [{"name": "Row", "sets": 1, "reps": 10}]} for i in range(32)]})
wj(I, "too-many-exercises.json", {"name": "X", "days": [{"name": "A", "exercises": [{"name": f"Ex {i+1}", "sets": 1, "reps": 10} for i in range(51)]}]})
wj(I, "multi-error.json", {"name": "X", "units": "stone", "days": [
    {"name": "A", "exercises": [{"name": "", "sets": 0, "reps": "ten"}, {"name": "Row", "sets": 3, "reps": 10, "weight": -1, "restSeconds": 5000}]},
    {"name": "B", "exercises": []}]})


# ---------------- prompt-derived fixtures
p = open("docs/PROMPT.md", encoding="utf-8").read()
block = re.search(r"## 1\. Plan prompt.*?\n```\n(.*?)\n```", p, re.S).group(1)
assert "```" not in block, "the plan prompt must not contain three backticks (see PROMPT.md marker rule)"
block = block.replace("{{units}}", "kg").replace("{{defaultRest}}", "90")
wt(I, "prompt-pasted-full.txt", block + "\nMon: bench 3x8, rows 3x10\n")
def _balanced(t, s):
    depth = 0; in_str = False; esc = False
    for i in range(s, len(t)):
        c = t[i]
        if in_str:
            if esc: esc = False
            elif c == "\\": esc = True
            elif c == '"': in_str = False
        elif c == '"': in_str = True
        elif c in "{[": depth += 1
        elif c in "}]":
            depth -= 1
            if depth == 0: return i + 1
    raise ValueError("unbalanced example JSON in prompt")
start = block.index("{"); ex = block[start:_balanced(block, start)]
wt(V, "prompt-example.txt", ex + "\n")

# ---------------- manifest
V = lambda f, warnings=(), **checks: {"file": f"valid/{f}", "outcome": "valid", "warnings": list(warnings), **({"checks": checks} if checks else {})}
def I(f, *errors, warnings=None, exact=True):
    d = {"file": f"invalid/{f}", "outcome": "invalid", "errors": [{"code": c, **({"path": p} if p is not None else {})} for c, p in errors]}
    if warnings is not None: d["warnings"] = warnings
    if not exact: d["exact"] = False
    return d
E0 = "days[0].exercises[0]"
fixtures = [
  V("weekly-rotation.json", planName="Push Pull Legs", units="kg", schedule="rotation", dayNames=["Push","Pull","Legs"], stepsPerDay=[22,16,16],
    cycle=["Push","Pull","Legs","Push","Pull","Legs","rest"], dropsPerSet={"0.3":[2,2,2], "0.2":[0,0,0]}, dropTargets={"0.3.0":[["amrap",20],["amrap",15]]},
    restPerSet={"0.0":[150,150,150,150], "0.1":[90,90,90], "0.4":[45,45,45], "1.3":[90,90,90]},
    workPerSet={"0.0":["range:6-8"]*4, "1.1":["amrap"]*4, "0.4":["duration:45"]*3, "2.0":["fixed:5"]*4},
    stepOrder={"0":["0.0","0.1","0.2","0.3","1.0","1.1","1.2","2.0","3.0","3.0.1","3.0.2","2.1","3.1","3.1.1","3.1.2","2.2","3.2","3.2.1","3.2.2","4.0","4.1","4.2"]},
    restAfterStep={"0:0":150, "0:3":"transition", "0:6":"transition", "0:7":0, "0:8":0, "0:9":0, "0:10":60, "0:14":60, "0:18":"transition", "0:19":45, "0:21":0, "1:9":"transition", "1:10":0, "1:11":60, "1:15":0},
    repRange={"0.0":[6,8], "0.1":[8,12], "0.2":[12,15], "0.3":[10,12], "0.4":None, "1.0":None, "1.1":None, "1.2":[8,10], "2.0":[4,6]}),
  V("drop-sets.json", ["W_DROPS_IGNORED"], stepsPerDay=[9+4+4+2], dropsPerSet={"0.0":[2,2,2], "0.1":[0,0,1], "0.2":[1,1], "0.3":[0,0]},
    dropTargets={"0.0.0":[["amrap",15],["range:8-10",10]], "0.1.2":[["amrap",40]]},
    stepOrder={"0":["0.0","0.0.1","0.0.2","0.1","0.1.1","0.1.2","0.2","0.2.1","0.2.2","1.0","1.1","1.2","1.2.1","2.0","2.0.1","2.1","2.1.1","3.0","3.1"]},
    restAfterStep={"0:0":0, "0:1":0, "0:2":60, "0:8":"transition", "0:9":60, "0:11":0, "0:12":"transition", "0:13":0, "0:14":90, "0:16":"transition"}),
  V("cycle-cases.json", ["W_CYCLE_MISSING_DAY"], cycle=["Upper","rest","Lower","rest"]),
  V("cycle-weekday-ignored.json", ["W_CYCLE_IGNORED"], schedule="weekday", cycle=["rest","A","rest","rest","rest","B","rest"]),
  V("reprange-cases.json", ["W_RANGE_SWAPPED","W_REPRANGE_IGNORED","W_REPRANGE_OUTSIDE"],
    repRange={"0.0":[8,12], "0.1":[8,12], "0.2":None, "0.3":[8,12], "0.4":None, "0.5":[10,10], "0.6":[8,12], "0.7":[8,12], "0.8":None}),
  V("weekly-weekday.json", schedule="weekday", weekdays=["monday","wednesday","friday"], stepsPerDay=[9,7,9], cycle=["Full Body A","rest","Full Body B","rest","Full Body C","rest","rest"]),
  V("no-schedule-weekdays.json", schedule="weekday", weekdays=["tuesday","thursday"]),
  V("single-day.json", dayNames=["Quick Upper"], cycle=["Quick Upper"], workPerSet={"0.0":["amrap:15"]*3}, weightPerSet={"0.0":[None]*3, "0.1":[20]*3}),
  V("single-day-bare.json", ["W_WRAPPED_SINGLE_DAY"], planName="Hotel Workout", dayNames=["Hotel Workout"], stepsPerDay=[10]),
  V("array-of-days.json", ["W_WRAPPED_SINGLE_DAY","W_DEFAULT_NAME"], planName="Imported plan 2026-09-04", dayNames=["Day 1","Day 2"]),
  V("array-of-exercises.json", ["W_WRAPPED_SINGLE_DAY","W_DEFAULT_NAME","W_DEFAULT_NAME"], dayNames=["Day 1"], stepsPerDay=[8]),
  V("minimal.json", ["W_DEFAULT_NAME","W_DEFAULT_NAME"], planName="Imported plan 2026-09-04", dayNames=["Day 1"], stepsPerDay=[1], restPerSet={"0.0":[90]}, workPerSet={"0.0":["fixed:10"]}),
  V("explicit-sets-pyramid.json", restPerSet={"0.0":[120,120,120,120,180], "0.1":[90,90,90]}, weightPerSet={"0.0":[50,60,70,80,60], "0.1":[15,15,15]},
    workPerSet={"0.0":["fixed:12","fixed:10","fixed:8","fixed:6","amrap"], "0.1":["fixed:15","fixed:15","range:12-15"]}),
  V("superset-circuit.json", ["W_GROUP_SET_MISMATCH"], groups={"0":["A","A","A",None]}, stepsPerDay=[10],
    stepOrder={"0":["0.0","1.0","2.0","0.1","1.1","2.1","0.2","1.2","3.0","3.1"]},
    restPerSet={"0.0":[60,60,60], "0.2":[90,90], "0.3":[45,45]},
    restAfterStep={"0:0":0, "0:1":0, "0:2":90, "0:5":90, "0:6":0, "0:7":"transition", "0:8":45, "0:9":0}),
  V("timed-sets.json", ["W_WARNING_BEEP_IGNORED","W_WARNING_BEEP_IGNORED"], workPerSet={"0.0":["duration:45"]*3, "0.2":["duration:600"], "0.3":["duration:40"]*3, "0.4":["open","open"], "0.5":["open:30"], "0.6":["duration:60","open"]},
    weightPerSet={"0.3":[32,32,32], "0.4":[None,None]}, restPerSet={"0.2":[0]}, restAfterStep={"0:5":"transition", "0:4":"transition", "0:0":30, "0:2":"transition", "0:8":"transition", "0:9":60, "0:10":"transition"},
    warningPerSet={"0.0":[5,5,5], "0.1":[3,3], "0.2":[60], "0.3":[4,4,4], "0.4":[None,None], "0.5":[None], "0.6":[15,None], "0.7":[None,None], "0.8":[None], "0.9":[None], "0.10":[3]},
    bodyweight={"0.3":False, "0.4":True, "0.5":False}, stepsPerDay=[19]),
  V("bodyweight.json", ["W_WARNING_BEEP_IGNORED","W_BODYWEIGHT_WEIGHT_IGNORED","W_BODYWEIGHT_WEIGHT_IGNORED"],
    bodyweight={"0.0":True, "0.1":True, "0.2":False, "0.3":True, "0.4":False, "0.5":True}, weightPerSet={"0.2":[10]*3, "0.3":[None,None], "0.1":[None]*3},
    warningPerSet={"0.4":[None,None]}, dropTargets={"0.5.0":[["amrap",None]]}),
  V("rest-precedence.json", restPerSet={"0.0":[80,80], "0.1":[70,70], "0.2":[70,60], "0.3":[0], "1.0":[100]}),
  V("lenient-values.json", ["W_RANGE_SWAPPED","W_WEIGHT_UNIT_IGNORED","W_WEIGHT_ROUNDED"], units="kg", bodyweight={"0.2":True, "0.3":False}, repRange={"0.0":[8,12], "0.1":[8,12], "0.2":None, "0.3":None, "0.4":None},
    exerciseNames={"0":["Barbell Bench Press","Incline Press","Pull-Up","Dip","Curl","Hammer Curl"]},
    stepsPerDay=[17],
    workPerSet={"0.0":["range:8-12"]*4, "0.1":["range:8-12"]*3, "0.2":["amrap"]*3, "0.3":["amrap:10"]*3, "0.4":["fixed:12"]*2, "0.5":["fixed:10"]*2},
    weightPerSet={"0.0":[60]*4, "0.1":[22.5]*3, "0.2":[None]*3, "0.3":[10]*3, "0.4":[135]*2, "0.5":[12.6]*2},
    restPerSet={"0.0":[90]*4}),
  V("unknown-fields.json", ["W_UNKNOWN_FIELD"]*4),
  V("lb-plan.json", units="lb"),
  V("duplicate-day-names.json", ["W_DAY_RENAMED","W_DAY_RENAMED"], dayNames=["Push","push (2)","Push (3)"]),
  V("group-edge-cases.json", ["W_GROUP_SINGLE","W_GROUP_SINGLE","W_GROUP_SPLIT"], groups={"0":["A","A",None,None,None]},
    stepOrder={"0":["0.0","1.0","0.1","1.1","0.2","1.2","2.0","2.1","2.2","3.0","3.1","3.2","4.0","4.1"]}),
  V("nulls-and-defaults.json", ["W_DEFAULT_NAME","W_DEFAULT_NAME"], weightPerSet={"0.0":[None,None]}, groups={"0":[None]}, notes={"0.0":None}),
  V("long-names.json", ["W_NAME_TRUNCATED","W_NAME_TRUNCATED","W_NAME_TRUNCATED","W_NOTES_TRUNCATED"], planName="N"*100, dayNames=["D"*100], exerciseNames={"0":["E"*100]}),
  V("unicode-names.json", planName="🏋️ Программа", dayNames=["胸 Chest"], exerciseNames={"0":["Développé couché"]}),
  V("rotation-with-weekdays.json", ["W_WEEKDAY_IGNORED","W_WEEKDAY_IGNORED"], schedule="rotation", weekdays=[None,None]),
  V("schedule-unknown-value.json", ["W_SCHEDULE_INFERRED"], schedule="rotation"),
  V("boundaries.json", stepsPerDay=[52], workPerSet={"0.1":["duration:86400"], "0.2":["fixed:1"]}, weightPerSet={"0.2":[0]}, restPerSet={"0.1":[0]}),
  V("braces-in-strings.json", planName="Braces {in} strings", notes={"0.0":"hold {tight} and [breathe]"}),
  V("fenced-plain.txt", planName="From chat"),
  V("fenced-with-prose.txt", ["W_SURROUNDING_TEXT"], planName="From chat"),
  V("fenced-other-language.txt", planName="From chat"),
  V("prose-no-fence.txt", ["W_SURROUNDING_TEXT"], planName="From chat"),
  V("marker-and-json.txt", ["W_SURROUNDING_TEXT"], planName="From chat"),
  V("curly-quotes.txt", ["W_CURLY_QUOTES_FIXED"], planName="From chat"),
  V("curly-in-string-value.txt", notes={"0.0":"“slow” eccentric"}),
  V("bom-and-zero-width.txt", planName="From chat"),
  V("top-level-array-fenced.txt", ["W_WRAPPED_SINGLE_DAY","W_DEFAULT_NAME"], dayNames=["Only day"]),
  V("prompt-example.txt", planName="Push Pull Legs", stepsPerDay=[24], cycle=["Push","rest"], workPerSet={"0.5":["open","open"]}, warningPerSet={"0.4":[5,5,5], "0.5":[None,None]}, bodyweight={"0.4":True, "0.5":True}),

  I("empty.txt", ("E_EMPTY", "")),
  I("whitespace.txt", ("E_EMPTY", "")),
  I("prompt-pasted.txt", ("E_PROMPT_PASTED", "")),
  I("prompt-pasted-full.txt", ("E_PROMPT_PASTED", "")),
  I("multiple-objects-fenced.txt", ("E_MULTIPLE_OBJECTS", "")),
  I("multiple-objects-bare.txt", ("E_MULTIPLE_OBJECTS", "")),
  I("trailing-comma.txt", ("E_NOT_JSON", "")),
  I("truncated.txt", ("E_NOT_JSON", "")),
  I("comments.txt", ("E_NOT_JSON", "")),
  I("single-quotes.txt", ("E_NOT_JSON", "")),
  I("not-json-at-all.txt", ("E_NOT_JSON", "")),
  I("too-large.txt", ("E_TOO_LARGE", "")),
  I("not-a-plan.json", ("E_NOT_A_PLAN", "")),
  I("null-top-level.json", ("E_NOT_JSON", "")),
  I("days-not-array.json", ("E_NO_DAYS", "days")),
  I("no-days.json", ("E_NO_DAYS", "days")),
  I("days-null.json", ("E_NO_DAYS", "days")),
  I("no-exercises.json", ("E_NO_EXERCISES", "days[0].exercises")),
  I("missing-exercise-name.json", ("E_MISSING_NAME", f"{E0}.name")),
  I("blank-exercise-name.json", ("E_MISSING_NAME", f"{E0}.name")),
  I("sets-zero.json", ("E_SETS_INVALID", f"{E0}.sets")),
  I("sets-fraction.json", ("E_SETS_INVALID", f"{E0}.sets")),
  I("sets-word.json", ("E_SETS_INVALID", f"{E0}.sets")),
  I("sets-empty-array.json", ("E_SETS_INVALID", f"{E0}.sets")),
  I("sets-too-many.json", ("E_LIMIT_EXCEEDED", f"{E0}.sets")),
  I("reps-word.json", ("E_REPS_INVALID", f"{E0}.reps")),
  I("reps-zero.json", ("E_REPS_INVALID", f"{E0}.reps")),
  I("reps-fraction.json", ("E_REPS_INVALID", f"{E0}.reps")),
  I("reps-triple-range.json", ("E_REPS_INVALID", f"{E0}.reps")),
  I("reps-open-range.json", ("E_REPS_INVALID", f"{E0}.reps")),
  I("reps-too-big.json", ("E_REPS_INVALID", f"{E0}.reps")),
  I("reps-bool.json", ("E_REPS_INVALID", f"{E0}.reps")),
  I("reprange-word.json", ("E_REPRANGE_INVALID", f"{E0}.repRange")),
  I("reprange-amrap.json", ("E_REPRANGE_INVALID", f"{E0}.repRange")),
  I("reprange-zero.json", ("E_REPRANGE_INVALID", f"{E0}.repRange")),
  I("drops-empty.json", ("E_DROPS_INVALID", f"{E0}.drops")),
  I("drops-too-many.json", ("E_DROPS_INVALID", f"{E0}.drops")),
  I("drops-not-list.json", ("E_DROPS_INVALID", f"{E0}.drops")),
  I("drops-bad-weight.json", ("E_WEIGHT_INVALID", f"{E0}.drops[0].weight")),
  I("cycle-unknown-day.json", ("E_CYCLE_UNKNOWN_DAY", "cycle[1]")),
  I("cycle-empty.json", ("E_CYCLE_INVALID", "cycle")),
  I("cycle-not-list.json", ("E_CYCLE_INVALID", "cycle")),
  I("warning-beep-zero.json", ("E_WARNING_BEEP_INVALID", f"{E0}.warningBeep")),
  I("warning-beep-too-long.json", ("E_WARNING_BEEP_INVALID", f"{E0}.warningBeep")),
  I("warning-beep-word.json", ("E_WARNING_BEEP_INVALID", f"{E0}.warningBeep")),
  I("warning-beep-fraction.json", ("E_WARNING_BEEP_INVALID", f"{E0}.sets[0].warningBeep")),
  I("duration-word.json", ("E_DURATION_INVALID", f"{E0}.durationSeconds")),
  I("bodyweight-string.json", ("E_BODYWEIGHT_INVALID", f"{E0}.bodyweight")),
  I("target-conflict-exercise.json", ("E_TARGET_CONFLICT", E0)),
  I("target-conflict-set.json", ("E_TARGET_CONFLICT", f"{E0}.sets[0]")),
  I("target-missing-exercise.json", ("E_TARGET_MISSING", E0)),
  I("target-missing-set.json", ("E_TARGET_MISSING", f"{E0}.sets[0]")),
  I("duration-zero.json", ("E_DURATION_INVALID", f"{E0}.durationSeconds")),
  I("duration-string-unit.json", ("E_DURATION_INVALID", f"{E0}.durationSeconds")),
  I("duration-too-long.json", ("E_DURATION_INVALID", f"{E0}.durationSeconds")),
  I("weight-negative.json", ("E_WEIGHT_INVALID", f"{E0}.weight")),
  I("weight-word.json", ("E_WEIGHT_INVALID", f"{E0}.weight")),
  I("weight-too-big.json", ("E_WEIGHT_INVALID", f"{E0}.weight")),
  I("rest-negative.json", ("E_REST_INVALID", f"{E0}.restSeconds")),
  I("rest-too-long.json", ("E_REST_INVALID", f"{E0}.restSeconds")),
  I("rest-fraction.json", ("E_REST_INVALID", f"{E0}.restSeconds")),
  I("rest-string-unit.json", ("E_REST_INVALID", f"{E0}.restSeconds")),
  I("rest-day-level-invalid.json", ("E_REST_INVALID", "days[0].defaultRestSeconds")),
  I("weekday-invalid.json", ("E_WEEKDAY_INVALID", "days[0].weekday")),
  I("weekday-duplicate.json", ("E_WEEKDAY_DUPLICATE", "days[1].weekday")),
  I("weekday-missing.json", ("E_WEEKDAY_MISSING", "days[1].weekday")),
  I("schedule-mixed.json", ("E_SCHEDULE_MIXED", "schedule")),
  I("schema-version-2.json", ("E_SCHEMA_VERSION", "schemaVersion")),
  I("units-invalid.json", ("E_UNITS_INVALID", "units")),
  I("too-many-days.json", ("E_LIMIT_EXCEEDED", "days")),
  I("too-many-exercises.json", ("E_LIMIT_EXCEEDED", "days[0].exercises")),
  I("multi-error.json", ("E_UNITS_INVALID", "units"), ("E_MISSING_NAME", f"{E0}.name"), ("E_SETS_INVALID", f"{E0}.sets"), ("E_REPS_INVALID", f"{E0}.reps"),
    ("E_WEIGHT_INVALID", "days[0].exercises[1].weight"), ("E_REST_INVALID", "days[0].exercises[1].restSeconds"), ("E_NO_EXERCISES", "days[1].exercises")),
]
man = {
  "_readme": "Expected import outcomes for every file in examples/. Run with settings units=kg, defaultRestSeconds=90, today=2026-09-04 (for default plan names). "
             "valid: 'warnings' is the exact multiset of warning codes; 'checks' keys: planName, units, schedule, dayNames, weekdays, stepsPerDay, exerciseNames{'d':[..]}, groups{'d':[..]}, notes{'d.e':..}, "
             "restPerSet{'d.e':[..]}, weightPerSet{'d.e':[..]}, workPerSet{'d.e':['fixed:10'|'range:8-12'|'amrap'|'amrap:10'|'duration:45']}, stepOrder{'d':['e.s',..]}, restAfterStep{'d:stepIndex':seconds} (rest started after logging that step, all later steps pending), repRange{'d.e':[min,max]|null}, cycle[...names or 'rest'], dropsPerSet{'d.e':[n per set]}, dropTargets{'d.e.s':[[work,weight],..]}. stepOrder entries are 'e.s' or 'e.s.d' for drops; restAfterStep values are seconds or 'transition'; workPerSet also 'open' | 'open:30'; warningPerSet{'d.e':[seconds|null]} (resolved warning-beep offset); bodyweight{'d.e':bool}. "
             "invalid: every listed error (code + path) must be reported; 'exact' (default true) also requires no other errors.",
  "settings": {"units": "kg", "defaultRestSeconds": 90, "today": "2026-09-04"},
  "fixtures": fixtures,
}
json.dump(man, open("examples/manifest.json", "w"), indent=2, ensure_ascii=False)
print("wrote", len(os.listdir("examples/valid")), "valid,", len(os.listdir("examples/invalid")), "invalid fixtures and examples/manifest.json with", len(fixtures), "entries")
`````

---

### FILE: CLAUDE.md

`````markdown
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

- Finish each milestone with its tests green before starting the next. Run the tests; do not declare a milestone done without running them. There are three routes and they check different things: `xcodebuild test` (the app, on a simulator), `swift test` (Core on the host — where the two doc-pinning tests actually run), and `python3 tools/check_core.py` (Core with no Xcode at all).
- Work on a branch, commit per milestone with the tests green, and write commit messages that say *why*. Never add an AI as a co-author.
- Keep views thin. Views call into an `AppModel`/store; they do not parse, validate, or compute.
- Use the fixtures in `examples/` verbatim in tests. Do not edit fixtures to make tests pass; if a fixture looks wrong, say so.
- Use the iOS Simulator for visual checks. The owner installs on the physical iPhone (BUILD_PLAN §Device).
- If you cannot run Xcode where you are (for example a chat session without a Mac), still write the complete project files, and give the owner exact commands to run the tests locally (`xcodebuild test -scheme JimmsBro -destination 'platform=iOS Simulator,name=iPhone 16'`). Never claim tests passed that you did not run.
`````

---

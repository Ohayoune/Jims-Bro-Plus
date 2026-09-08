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

# Jimm's Bro+

[![CI](https://github.com/Ohayoune/Jims-Bro-Plus/actions/workflows/ci.yml/badge.svg)](https://github.com/Ohayoune/Jims-Bro-Plus/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

An iPhone app that runs your workout for you. Pick a plan and tap Start; it walks you through the day one set at a time, times your rest on the Lock Screen, remembers what you lifted, and tells you when to add weight. Plans come from four built-in routines or from a prompt a chatbot answers. No account, no server, no network connection.

<p align="center">
  <img src="docs/screenshots/intro.png" width="150" alt="The introduction: a plan, then Start">
  <img src="docs/screenshots/today.png" width="150" alt="Today: the day's card, and Start">
  <img src="docs/screenshots/workout.png" width="150" alt="A rest counting down mid-workout">
  <img src="docs/screenshots/progression.png" width="150" alt="A progression of steps, one exercise on its second">
  <img src="docs/screenshots/history.png" width="150" alt="History: the month, each day in its own colour">
</p>

## What it does

- **Runs the workout.** The card shows the exercise, the target and the weight you used last time. Log what you did and the rest timer starts on its own — on the Lock Screen and in the Dynamic Island, with a notification when the phone is in your pocket. Warm-up, timed holds, supersets, drop sets, a walk between exercises.
- **Remembers.** Next time the weight is already filled in. Hit the top of your rep range and it suggests the next weight, snapped to what your plates can make. Every set is kept: a calendar with each day in its own colour, history, personal records, a chart per exercise, metrics over time.
- **Gets plans from a chatbot.** Copy the prompt, paste it into ChatGPT or Claude, paste the reply back. Long plans come in one day at a time. Four built-in routines — Full Body, Upper Lower, Push Pull Legs, At Home — to start from.
- **Progresses.** Ask the chatbot for a progression from what you actually lifted, then earn each step by hitting it. Set a goal per exercise and watch it climb.
- **Keeps your data on the phone.** Back up to a file, export history as a spreadsheet, import from Strong or Hevy. Nothing leaves the phone unless you send it. [Privacy policy](docs/PRIVACY.md).

## Status

**v1.7**, built and green on every route ([docs/BUILD_STATUS.md](docs/BUILD_STATUS.md)). Not yet on the App Store: the submission is prepared in [docs/APP_STORE.md](docs/APP_STORE.md) and waits on the paid Developer Program and a release Xcode. Until then, build it yourself.

## Build it

Xcode 16 or later on a Mac, an iPhone on iOS 17 or later.

1. Open `JimmsBro.xcodeproj` and pick the shared `JimmsBro` scheme.
2. Signing & Capabilities → choose your team (a free Apple ID works for seven days at a time).
3. Plug in the phone, choose it as the destination, press Run. [docs/BUILD_PLAN.md](docs/BUILD_PLAN.md) has the one-time steps on the phone.

The tests run on three routes — the simulator, `swift test` on the host, and a portable runner that needs no Xcode — and on every push through [GitHub Actions](.github/workflows/ci.yml). The commands are below.

## License

[MIT](LICENSE).

---

## For the implementing agent

This folder contains the design package and the app, built through **v1 (M0–M7)**, **v1.1 (R0–R6)**, **v1.2 (V0–V8)**, **v1.3 (X0–X6)**, **v1.4 (Y0–Y5)**, **v1.5 (Z0–Z6)**, **v1.6 (U0–U7)** and **v1.7 (T0–T6)**: the Core import pipeline and session engine, the JSON store, every screen, the workout's five fixed zones, plan editing, backup and restore, v1.2's warm-up, timed walk between exercises, loadable weight suggestions, anchored calendar, metrics and Lock Screen / Dynamic Island activity, and v1.3's narrower Island, changing an exercise mid-workout, JSON edits at every size, history as CSV in and out, and Progression — the chatbot round-trip run the other way; and v1.4's four built-in plans, the introduction, a workout that opens the moment it exists, and the store readiness (an opaque icon, version 1.4 on every target, the export-compliance answer, the privacy policy and the submission page); and v1.5's clearer Progression row and Copy prompt, an effort target (reps or seconds in reserve) in the plan format, a plan built in several pastes for free chatbot tiers, progression as steps you earn by performance with the calendar kept as a mode, and a goal per exercise; and v1.6's answer to the usability audit (`docs/UX_REVIEW_2026-09-09.md`): no false missed workouts, every menu confirmation an alert with a way out, the first five minutes made to ask for nothing unexplained (no warm-up on a fresh install, Start first set, the permission at the first log, a weight field that explains itself, the unit asked), and a hierarchy pass (Start under the thumb, Undo on the row, a strip that says what follows, presets) — with plain words (U4, the owner's Reading B) and a switch back to compact notation, and a Lock Screen activity that no longer outlives the app (U7); and v1.7's answer to "feels like a settings menu": Today as one card with the day's alternatives in one ···, two tabs (Today · History) with Plans behind Change plan and Settings behind a gear, the calendar in History, controls that appear when they first have something to do, and a colour per day. Open `JimmsBro.xcodeproj` and select the shared `JimmsBro` scheme. What remains is the device checklist, which needs the owner's iPhone, and the submission itself — the Developer Program, a release Xcode and the form — which is the owner's to do from `docs/APP_STORE.md`. ChatGPT / Codex reads `AGENTS.md`; Claude Code reads the identical `CLAUDE.md`.

Run the iOS tests from this folder:

```sh
xcodebuild test -scheme JimmsBro -destination 'platform=iOS Simulator,name=iPhone 17'
```

That is **332 tests** (10 of them skipped on this route — see below). The suite covers imports, steps, rest, the session engine, prefill, stats, progression, plan coordination, scheduling, calendar projection, prompts, the persistence store and its migration from v1.1's files, the app model behind the screens, the workout's input rules, timers, notifications and session lifecycle, history and metrics, plan editing, backup and restore, v1.2's warm-up, transition rest, weight rounding, suggestions, anchored schedule and Live Activity, v1.3's Island timer range, exercise substitution, JSON splices, history CSV and Progression, v1.4's start-before-the-side-effects rule, the four built-in plans and the introduction, v1.5's effort target, the outline-then-days draft, the progression's earned steps and the goals, and v1.6's usability rules — the missed-workout guard, the chip and calendar-label rules, the first-five-minutes defaults, the Summary's next line and plain words, and v1.7's Today card, tab list, calendar line, earned controls and day colours. Imports use the 115 fixtures and the manifest verbatim (the original 111, plus four for the effort target). There are no third-party dependencies, and the signing team is already set for both targets.

Core can also be checked with the independently installed Command Line Tools:

```sh
python3 tools/check_core.py --filter ImportTests
python3 tools/check_core.py
```

This portable runner compiles the actual Core sources in Swift 5 language mode and executes the same test bodies using assertion adapters. It reports a nonzero exit code on any failure; it does not run XCTest or certify app bundle/simulator behavior.

```sh
swift test
```

runs Core as an ordinary Swift Package. This route had not compiled since `AppModel` became `@Observable` — `Package.swift` declared macOS 13 and Observation needs 14 — and v1.2's V1 fixed it. It is also where the ten cases the simulator skips actually run: five pin `Prompts.swift` to `docs/PROMPT.md`, one pins the introduction's copy to the views' own source, one the sentences of D50 to theirs, two SPEC's tab list and gate table to `Core/Tabs.swift` and `Core/Gates.swift`, and one reads `DaySquare.swift` for the palette — all outside the simulator's sandbox. See `docs/BUILD_STATUS.md` for results and remaining verification.

An iOS simulator runtime must be installed in Xcode; the commands above name the iPhone 17 simulator (the one Xcode 27 ships), and any installed iPhone works.

```sh
python3 tools/check_release.py
```

checks what a script can about App Store readiness (v1.4, D49): the icon has no alpha channel, the three targets agree on a version and `docs/APP_STORE.md` says the same, the export-compliance answer is in the binary, the policy and the submission page exist, and every built-in plan is bundled. The other half is a Release build, `xcodebuild build -scheme JimmsBro -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17'`.

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
| `docs/TEST_CASES.md` | About 775 test cases, unit / ui / manual / check | the agent; you for the manual checklist |
| `docs/BUILD_PLAN.md` | Milestones M0–M8 and how to install on your iPhone | both |
| `docs/ITERATION_2_PLAN.md` | The v1.1 plan: milestones R0–R6 | both |
| `docs/ITERATION_3_PLAN.md` | The v1.2 plan: milestones V0–V8 | both |
| `docs/ITERATION_4_PLAN.md` | The v1.3 plan: milestones X0–X6 | both |
| `docs/ITERATION_5_PLAN.md` | The v1.4 plan: milestones Y0–Y5 | both |
| `docs/ITERATION_6_PLAN.md` | The v1.5 plan: milestones Z0–Z6, and the owner's readings of the notes | both |
| `docs/ITERATION_7_PLAN.md` | The v1.6 plan: milestones U0–U7 from the usability audit; plain words (U4) as the owner's Reading B | both |
| `docs/ITERATION_8_PLAN.md` | The v1.7 plan: milestones T0–T6 — Today as one card, two tabs, the calendar in History, earned controls, a colour per day | both |
| `docs/PRIVACY.md` | The privacy policy the App Store needs a URL for | you |
| `docs/APP_STORE.md` | The App Store submission: the order of things, every field, the review notes, the screenshots, the choices only you can make | you |
| `docs/PROGRESSION_FORMAT.md` | The progression reply format (D44): fields, leniency, codes | both |
| `docs/CODE_HEALTH_REVIEW.md` | The 2026-09-07 review that prompted half of v1.2, and what became of each finding | you |
| `docs/UX_REVIEW_2026-09-09.md` | The 2026-09-09 usability audit v1.6 answers: friction points, twelve defects and ideas, judged for a coach, a great-grandparent and a five-year-old | you |
| `docs/DEVICE_CHECKLIST.md` | The manual cases to run on your iPhone, one section per release, with a place to record results | you |
| `docs/BUILD_STATUS.md` | What is built, what was verified and how to reproduce it | you |
| `schema/plan.schema.json` | JSON Schema of the strict plan shape | the agent |
| `examples/` | 111 fixture files + `manifest.json` with expected results | the agent's tests |
| `tools/reference_import.py` | Python reference implementation; `python3 tools/reference_import.py` checks every fixture | the agent, as an oracle |
| `tools/generate_fixtures.py` | Regenerates all of `examples/` from scratch | the agent, if it only has the bundle |
| `tools/check_release.py` | Checks what a script can about store readiness: the icon, the versions, the compliance answer, the built-in plans | both |
| `HANDOFF_BUNDLE.md` | Everything above except the fixtures, in one file for pasting or uploading into a chat | ChatGPT (web) |
| `JimmsBro-design-package.zip` | The whole folder, for uploading into a chat | ChatGPT (web) |

Before handing off, read `docs/SPEC.md` §1 (decisions made for you) and §2 (why a native iOS app, and what the free vs $99 Apple routes mean). Change anything you disagree with in the docs first; the agent builds what the docs say.

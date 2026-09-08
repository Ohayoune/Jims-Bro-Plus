# Jimm's Bro+

A personal iPhone app that runs your workout for you: import a plan a chatbot wrote from your own description, then log each set while the app times your rest and remembers what you lifted last time.

## If you just want the app

- **What it is.** Pick a plan and tap Start. The app walks you through the day one set at a time, times your rest — on the Lock Screen and in the Dynamic Island, with a notification when the phone is in your pocket — and remembers what you lifted, so next time the weight is already filled in and it tells you when to add. Four built-in routines (Full Body, Upper Lower, Push Pull Legs, At Home), or a chatbot writes yours from a prompt the app copies for you.
- **Getting it.** It is being submitted to the App Store; `docs/APP_STORE.md` is the submission. Until it is there, build it yourself: open `JimmsBro.xcodeproj` in Xcode, choose your team under Signing & Capabilities, plug in an iPhone, press Run.
- **Privacy.** Nothing leaves the phone unless you export it. No account, no analytics, no network connection. `docs/PRIVACY.md` is the policy.
- **License.** None has been chosen yet, so the code is published to read; ask before reusing it.

Everything below is the design and handoff material the app was built from.

This folder contains the design package and the app, built through **v1 (M0–M7)**, **v1.1 (R0–R6)**, **v1.2 (V0–V8)**, **v1.3 (X0–X6)**, **v1.4 (Y0–Y5)** and **v1.5 (Z0–Z6)**: the Core import pipeline and session engine, the JSON store, every screen, the workout's five fixed zones, plan editing, backup and restore, v1.2's warm-up, timed walk between exercises, loadable weight suggestions, anchored calendar, metrics and Lock Screen / Dynamic Island activity, and v1.3's narrower Island, changing an exercise mid-workout, JSON edits at every size, history as CSV in and out, and Progression — the chatbot round-trip run the other way; and v1.4's four built-in plans, the introduction, a workout that opens the moment it exists, and the store readiness (an opaque icon, version 1.4 on every target, the export-compliance answer, the privacy policy and the submission page); and v1.5's clearer Progression row and Copy prompt, an effort target (reps or seconds in reserve) in the plan format, a plan built in several pastes for free chatbot tiers, progression as steps you earn by performance with the calendar kept as a mode, and a goal per exercise. Open `JimmsBro.xcodeproj` and select the shared `JimmsBro` scheme. What remains is the device checklist, which needs the owner's iPhone, and the submission itself — the Developer Program, a release Xcode and the form — which is the owner's to do from `docs/APP_STORE.md`. ChatGPT / Codex reads `AGENTS.md`; Claude Code reads the identical `CLAUDE.md`.

Run the iOS tests from this folder:

```sh
xcodebuild test -scheme JimmsBro -destination 'platform=iOS Simulator,name=iPhone 17'
```

That is **287 tests** (7 of them skipped on this route — see below). The suite covers imports, steps, rest, the session engine, prefill, stats, progression, plan coordination, scheduling, calendar projection, prompts, the persistence store and its migration from v1.1's files, the app model behind the screens, the workout's input rules, timers, notifications and session lifecycle, history and metrics, plan editing, backup and restore, v1.2's warm-up, transition rest, weight rounding, suggestions, anchored schedule and Live Activity, v1.3's Island timer range, exercise substitution, JSON splices, history CSV and Progression, v1.4's start-before-the-side-effects rule, the four built-in plans and the introduction, and v1.5's effort target, the outline-then-days draft, the progression's earned steps and the goals. Imports use the 115 fixtures and the manifest verbatim (the original 111, plus four for the effort target). There are no third-party dependencies, and the signing team is already set for both targets.

Core can also be checked with the independently installed Command Line Tools:

```sh
python3 tools/check_core.py --filter ImportTests
python3 tools/check_core.py
```

This portable runner compiles the actual Core sources in Swift 5 language mode and executes the same test bodies using assertion adapters. It reports a nonzero exit code on any failure; it does not run XCTest or certify app bundle/simulator behavior.

```sh
swift test
```

runs Core as an ordinary Swift Package. This route had not compiled since `AppModel` became `@Observable` — `Package.swift` declared macOS 13 and Observation needs 14 — and v1.2's V1 fixed it. It is also where the seven cases the simulator skips actually run: five pin `Prompts.swift` to `docs/PROMPT.md`, one pins the introduction's copy to the views' own source, and one pins the sentences of D50 to theirs — all outside the simulator's sandbox. See `docs/BUILD_STATUS.md` for results and remaining verification.

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
| `docs/TEST_CASES.md` | About 475 test cases, unit / ui / manual | the agent; you for the manual checklist |
| `docs/BUILD_PLAN.md` | Milestones M0–M8 and how to install on your iPhone | both |
| `docs/ITERATION_2_PLAN.md` | The v1.1 plan: milestones R0–R6 | both |
| `docs/ITERATION_3_PLAN.md` | The v1.2 plan: milestones V0–V8 | both |
| `docs/ITERATION_4_PLAN.md` | The v1.3 plan: milestones X0–X6 | both |
| `docs/ITERATION_5_PLAN.md` | The v1.4 plan: milestones Y0–Y5 | both |
| `docs/ITERATION_6_PLAN.md` | The v1.5 plan: milestones Z0–Z6, and the owner's readings of the notes | both |
| `docs/PRIVACY.md` | The privacy policy the App Store needs a URL for | you |
| `docs/APP_STORE.md` | The App Store submission: the order of things, every field, the review notes, the screenshots, the choices only you can make | you |
| `docs/PROGRESSION_FORMAT.md` | The progression reply format (D44): fields, leniency, codes | both |
| `docs/CODE_HEALTH_REVIEW.md` | The 2026-09-07 review that prompted half of v1.2, and what became of each finding | you |
| `docs/DEVICE_CHECKLIST.md` | The 32 manual cases to run on your iPhone, with a place to record results | you |
| `docs/BUILD_STATUS.md` | What is built, what was verified and how to reproduce it | you |
| `schema/plan.schema.json` | JSON Schema of the strict plan shape | the agent |
| `examples/` | 111 fixture files + `manifest.json` with expected results | the agent's tests |
| `tools/reference_import.py` | Python reference implementation; `python3 tools/reference_import.py` checks every fixture | the agent, as an oracle |
| `tools/generate_fixtures.py` | Regenerates all of `examples/` from scratch | the agent, if it only has the bundle |
| `tools/check_release.py` | Checks what a script can about store readiness: the icon, the versions, the compliance answer, the built-in plans | both |
| `HANDOFF_BUNDLE.md` | Everything above except the fixtures, in one file for pasting or uploading into a chat | ChatGPT (web) |
| `JimmsBro-design-package.zip` | The whole folder, for uploading into a chat | ChatGPT (web) |

Before handing off, read `docs/SPEC.md` §1 (decisions made for you) and §2 (why a native iOS app, and what the free vs $99 Apple routes mean). Change anything you disagree with in the docs first; the agent builds what the docs say.

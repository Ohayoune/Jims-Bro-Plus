# Jimm's Bro+

A personal iPhone app that runs your workout for you: import a plan a chatbot wrote from your own description, then log each set while the app times your rest and remembers what you lifted last time.

This folder contains the design package and the app, built through **v1 (M0–M7)**, **v1.1 (R0–R6)** and **v1.2 (V0–V7)**: the Core import pipeline and session engine, the JSON store, every screen, the workout's five fixed zones, plan editing, backup and restore, and v1.2's warm-up, timed walk between exercises, loadable weight suggestions, anchored calendar, metrics and Lock Screen / Dynamic Island activity. Open `JimmsBro.xcodeproj` and select the shared `JimmsBro` scheme. What remains is the device checklist, which needs the owner's iPhone. ChatGPT / Codex reads `AGENTS.md`; Claude Code reads the identical `CLAUDE.md`.

Run the iOS tests from this folder:

```sh
xcodebuild test -scheme JimmsBro -destination 'platform=iOS Simulator,name=iPhone 16'
```

That is **210 tests** (2 of them skipped on this route — see below). The suite covers imports, steps, rest, the session engine, prefill, stats, progression, plan coordination, scheduling, calendar projection, prompts, the persistence store and its migration from v1.1's files, the app model behind the screens, the workout's input rules, timers, notifications and session lifecycle, history and metrics, plan editing, backup and restore, and v1.2's warm-up, transition rest, weight rounding, suggestions, anchored schedule and Live Activity. Imports use the original 111 fixtures and manifest verbatim. There are no third-party dependencies, and the signing team is already set for both targets.

Core can also be checked with the independently installed Command Line Tools:

```sh
python3 tools/check_core.py --filter ImportTests
python3 tools/check_core.py
```

This portable runner compiles the actual Core sources in Swift 5 language mode and executes the same test bodies using assertion adapters. It reports a nonzero exit code on any failure; it does not run XCTest or certify app bundle/simulator behavior.

```sh
swift test
```

runs Core as an ordinary Swift Package. This route had not compiled since `AppModel` became `@Observable` — `Package.swift` declared macOS 13 and Observation needs 14 — and v1.2's V1 fixed it. It is also where the two cases the simulator skips actually run: they pin `Prompts.swift` to `docs/PROMPT.md`, which is outside the simulator's sandbox. See `docs/BUILD_STATUS.md` for results and remaining verification.

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

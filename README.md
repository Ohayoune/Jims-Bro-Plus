# Jimm's Bro+

A personal iPhone app that runs your workout for you: import a plan a chatbot wrote from your own description, then log each set while the app times your rest and remembers what you lifted last time.

This folder contains the design package, the M0 Xcode project, the M1/M2 Core implementation, the M3 JSON store, the M4 screens (Home, Plans, Plan detail, Import, Settings) and the M5 workout (step card, rest timer, timed sets, done screen, overview, summary, resume) and the M6 History (list by month, editable session detail, per-exercise history with the best set) and the M7 polish (full Settings with export and delete-all, dark mode, Dynamic Type, VoiceOver, app icon). Open `JimmsBro.xcodeproj` and select the shared `JimmsBro` scheme. What remains is the M8 device checklist. ChatGPT / Codex reads `AGENTS.md`; Claude Code reads the identical `CLAUDE.md`.

Run the iOS tests from this folder:

```sh
xcodebuild test -scheme JimmsBro -destination 'platform=iOS Simulator,name=iPhone 16'
```

The suite includes the M0 resource smoke test and Core tests for imports, steps, rest, the session engine, prefill, stats, progression, plan coordination, scheduling, calendar projection, sparklines, prompts, the persistence store, the app model behind the screens, the workout's input rules, timers, notifications and session lifecycle, the history grouping and editing, and the settings, export and accessibility text. Imports use the original 111 fixtures and manifest verbatim. There are no third-party dependencies. Select your signing Team only when installing on a physical iPhone.

Core can also be checked with the independently installed Command Line Tools:

```sh
python3 tools/check_core.py --filter ImportTests
python3 tools/check_core.py
```

This portable runner compiles the actual Core sources in Swift 5 language mode and executes the same test bodies using assertion adapters. It reports a nonzero exit code on any failure; it does not run XCTest or certify app bundle/simulator behavior. With a fully configured Xcode toolchain, `swift test` also runs Core as an ordinary Swift Package using XCTest. See `docs/BUILD_STATUS.md` for results and remaining verification.

If Xcode reports an unaccepted license, either run the command above through an Xcode whose license is already accepted (see `docs/BUILD_STATUS.md`), or review and accept it in Terminal with `sudo xcodebuild -license` and complete Xcode's first-launch component installation. The iPhone 16 simulator and an iOS simulator runtime must be installed in Xcode.

| File | What it is | Who reads it |
|---|---|---|
| `AGENTS.md` / `CLAUDE.md` | Handoff instructions and hard rules (identical; one per agent convention) | the agent |
| `docs/SPEC.md` | Product spec: decisions, platform, screens, exact behaviors, data model, persistence | you first, then the agent |
| `docs/PLAN_FORMAT.md` | The JSON plan format, what's accepted leniently, every error/warning code | the agent |
| `docs/PROMPT.md` | The exact prompt the app copies for ChatGPT/Claude, and the fix-it prompt | you, the agent |
| `docs/TEST_CASES.md` | About 475 test cases, unit / ui / manual | the agent; you for the manual checklist |
| `docs/BUILD_PLAN.md` | Milestones M0–M8 and how to install on your iPhone | both |
| `docs/DEVICE_CHECKLIST.md` | The 32 manual cases to run on your iPhone, with a place to record results | you |
| `docs/BUILD_STATUS.md` | What is built, what was verified and how to reproduce it | you |
| `schema/plan.schema.json` | JSON Schema of the strict plan shape | the agent |
| `examples/` | 111 fixture files + `manifest.json` with expected results | the agent's tests |
| `tools/reference_import.py` | Python reference implementation; `python3 tools/reference_import.py` checks every fixture | the agent, as an oracle |
| `tools/generate_fixtures.py` | Regenerates all of `examples/` from scratch | the agent, if it only has the bundle |
| `HANDOFF_BUNDLE.md` | Everything above except the fixtures, in one file for pasting or uploading into a chat | ChatGPT (web) |
| `JimmsBro-design-package.zip` | The whole folder, for uploading into a chat | ChatGPT (web) |

Before handing off, read `docs/SPEC.md` §1 (decisions made for you) and §2 (why a native iOS app, and what the free vs $99 Apple routes mean). Change anything you disagree with in the docs first; the agent builds what the docs say.

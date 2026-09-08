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

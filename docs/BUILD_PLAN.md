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

# Jimm's Bro+ — v1.4 plan (iteration 5)

The owner ran v1.3 on the phone: *"everything works."* Then four things, in their words:

1. *"Sometimes when a button is pressed it takes a second for the app to load."*
2. *"v4 should be getting the app ready for publishing"* — the repository goes public, then
   the App Store.
3. *"An introduction screen that explains how the app runs."*
4. *"A couple of prebuilt plans that cover the major workout routines, with the suggestion
   that the user builds their own. The built-in plans should all be really well thought
   out."*

Milestones **Y0–Y5, in order**. Each ends with the full suite green
(`xcodebuild test -scheme JimmsBro -destination 'platform=iOS Simulator,name=iPhone 17'`,
`swift test`, `python3 tools/check_core.py`) and one commit on `v1.4-release`, off `main`.
SPEC amendments land **before** the code that depends on them, as in every iteration since
v1.1. Each feature is one decision, D46–D49, and one Core type that a view only renders.

This is the first release strangers will install. Until now every plan came from the owner's
own chatbot round-trip, the owner's weights were in the sample, and the owner knew what the
five zones were before the screen drew them. v1.4 is the app meeting someone who knows none of
that — and it has to do it without adding chrome to Home, which is still three things (§4.1).

---

## Y0 — This plan, the branch, and the decisions

- Branch `v1.4-release` off `main` (v1.3 is merged and pushed; the repo is
  `github.com/Ohayoune/Jims-Bro-Plus`, private until the owner flips it).
- D46–D49 are written into SPEC §6 and `DECISIONS_LOG.md` by the milestone that lands them.
- The version the App Store will show is **1.4**, the same number the docs use. The first
  public build being "1.4" is honest about what it is: the fourth refinement of a working app.
- No app code.

## Y1 — A tap's result before its side effects (owner note 1, D48)

The second the owner waits is not the main thread being busy. It is the **workout cover
waiting for `startDay` to finish**, and `startDay` finishes only after everything it causes has
landed: the rest notification scheduled through `UNUserNotificationCenter` (one XPC round-trip
per request), `plans.json` rewritten through the store actor, and the Live Activity requested
through ActivityKit — which is the slow one, and the newest. Home and Plan detail both read
`try await model.startDay(...)` **then** `showWorkout = true`. On a Debug build on a phone, with
the Island being asked for the first time, that is about a second between the tap and the
screen — with nothing on screen to say the tap was heard.

The engine itself is ready in the first line of `startDay`: `library.startDay` is synchronous.
Everything after it is the system being told.

- **The rule (D48)**: a tap's visible result is on screen before its side effects run. The
  model changes state synchronously and *then* tells the system; a view never waits for the
  telling to show the change. `AppModel.startedWorkouts` counts the workouts this run of the
  app has started, incremented right after the engine exists, and `RootView` opens the cover on
  every change of it. Home's Start, "Do it now", "Another day", Plan detail's Start and the
  switch dialog stop setting `showWorkout` after their awaits. Resume already sets it directly
  and keeps doing so; a session restored at launch is offered as **Resume** on the card, exactly
  as SPEC §5.4 says, because `load` never touches the count.
- `startDay` itself stays sequential and atomic. Making the effects fire-and-forget would let
  a later event's write land before an earlier one's, and every test that calls `startDay`
  then reads the scheduler would have to learn to wait. Nothing about persistence order changes.
- **Tested with a scheduler that does not return**: a `BlockingAlerts` double whose `schedule`
  waits on a continuation. `startDay` is launched in a task; while the double is still holding
  the first notification, `hasActiveSession` is already true and `startedWorkouts` is already 1.
  A start refused with `sessionInProgress` does not count; a switch counts; `load` with an
  active session on disk does not.
- Two more things the owner should know, recorded in BUILD_STATUS rather than changed: a
  Debug build from Xcode runs SwiftUI and the import pipeline unoptimised, and TestFlight's
  Release build is what the store ships; and the first tap into a text field in a session pays
  the keyboard's own warm-up, which no app controls.

## Y2 — Built-in plans (owner note 4, D46)

Until now the only plan without a chatbot was the sample — the owner's Push Pull Legs with the
owner's weights in it, which is exactly wrong for a stranger. **Built-in plans** are four
routines covering how most people actually train, written to the app's own format, with no
weights in them, and offered next to — never instead of — writing your own.

- **The four**, one JSON each in `JimmsBro/Resources`, each through the ordinary import
  pipeline with **no errors and no warnings of either kind**:

  | Plan | Days a week | Split | Who | Equipment |
  |---|---|---|---|---|
  | **Full Body** | 3 | A / B, alternating across a 14-day repeat block (A B A, then B A B) | New to lifting, or back after a break | Barbell, rack, bench, a lat pulldown or pull-up bar |
  | **Upper Lower** | 4 | Upper A · Lower A · rest · Upper B · Lower B · rest · rest | A few months in and wanting more | A gym |
  | **Push Pull Legs** | 6 | Push · Pull · Legs, twice, one rest day | Enthusiasts who want to lift most days | A gym |
  | **At Home** | 3 | A / B on the same 14-day block | No gym, or travelling | A floor, a wall, a chair and a sturdy table |

- **What "well thought out" means here**, and what the tests check:
  - Every day opens with the biggest movement and ends with the smallest: squat, hinge, press
    or pull first; isolation and core last. Sets per day between 15 and 22; five to seven
    exercises; a session of 45–60 minutes with the plan's own rests.
  - **Every rep-based exercise carries a rep range**, so the app's own advice (§6.11) works
    from the first session: hit the top of the range on every set and it tells you to add
    weight; fall below the bottom and it says so. Main lifts run 4–6 or 6–8; secondary 8–12;
    isolation 10–15; core and holds are timed with the warning beep on.
  - Rest is written on every exercise, never left to the setting: 180 s for the squat and
    the deadlift, 150 s for the presses, 90–120 s for rows and secondary work, 60 s for
    isolation, 45 s for core. Two isolation exercises that share a rest are a superset, so the
    session stays short; the beginner plans have none, because a superset is one more thing to
    learn.
  - **No weights.** The app never guesses what a stranger can lift. The first exercise of
    every plan says so in its notes: start light, type the weight on the first set, and from
    then on the app fills it in and tells you when to add. `units` is omitted, so the plan
    takes the user's setting.
  - **One spelling per exercise across all four plans** — "Barbell Back Squat" in Full Body is
    "Barbell Back Squat" in Push Pull Legs — so moving from one routine to the next carries your
    history, prefill and records with you (§6.9). A test reads every name in every built-in
    plan and fails on two spellings of one movement.
  - Bodyweight movements are flagged, so the card never asks for a weight on a push-up. Notes
    carry the cue that matters and the substitution when the equipment is missing ("No pull-up
    bar? Lat pulldown, or a band"), under the 500-character cap. Push Pull Legs' deadlift note
    says what to do if two heavy pulls a week is too much — **Change exercise** (D42) — because
    a built-in plan should teach the app as well as the lift.
- **The catalogue** is Core: `BuiltInPlan` (an id, the name, a one-line tagline, a paragraph
  saying what the routine is and why it is built this way, who it is for, days a week, minutes,
  equipment, the resource name) and `BuiltInPlans.all`. A test checks the catalogue and the
  bundle agree: every entry has its file, every file has its entry.
- **The suggestion to build your own** is the catalogue's one shared sentence,
  `BuiltInPlans.buildYourOwn`, shown as the picker's footer: these are starting points; the
  best plan is the one written for you, and **Create with a chatbot** is where that happens.
- **Where it is offered**: Add plan gains **Choose a built-in plan** as its first row, above
  Paste plan. Home's empty state offers **Choose a built-in plan** where it offered the sample,
  next to the practice workout. The picker is one screen: four rows (name, tagline, "3 days a
  week · 45–60 min · a gym"), tapping one opens the ordinary **Review plan** sheet with the
  paragraph on top — the same days, exercises and per-set targets a pasted plan gets, the same
  "Set as current plan" toggle, the same **Save plan**. A built-in plan saved twice is kept
  both, suffixed, like any plan.
- `SamplePlan.json` stays in the bundle: the seeder, the screenshots and O1 read it, and it is
  the fixture `examples/valid/weekly-rotation.json`. It is simply no longer offered on Home.
  `PracticePlan.json` and its link stay: a six-set run to learn the app is still the fastest
  way to learn it.

## Y3 — The introduction (owner note 3, D47)

The app's premise is a loop nobody has seen before — a plan, Start, log the set, the rest runs
itself, the app remembers — and the first screen a stranger sees is "No plan yet". The
**introduction** says the loop out loud, once, and then gets out of the way.

- **The content is Core**: `Introduction.pages`, four `IntroPage`s (a symbol, a title, a
  paragraph), so what the app claims about itself is a test rather than a screenshot: every
  page names a control that exists — **Start**, **Log set**, **Add plan**, **Create with a
  chatbot**, **History**, **Progression** — and a test fails when one is renamed without the
  intro following. The four: *A plan, then Start* · *Log the set, rest, repeat* (the rest
  timer, the Lock Screen and the Island) · *It remembers* (prefill, the advice at the top of
  the range, History and records) · *Your plan, your way* (built-in plans, the chatbot
  round-trip, Progression).
- **When it appears**: on a launch where the store holds **no plans** and the intro has not
  been dismissed — a first launch, or after Delete all data, which is a first launch by choice.
  Never over a phone that already has plans: the owner's phone gets the row in Settings, not a
  cover. `Settings.introSeen` is the flag, optional in `Persistence.swift` (absent → false, so
  the frozen v1 settings file still decodes), set by dismissing the intro either way.
- **The screen**: pages you swipe with the system's page dots, one primary action —
  **Choose a plan**, which dismisses the intro and opens Add plan with the built-in picker in
  front — and one quiet **Not now**. Four screens is the ceiling; a page is one symbol, one
  line, one paragraph. Nothing on Home changes.
- **Reachable later** from Settings → About → **How the app works**, with **Done** instead of
  Choose a plan, so the explanation is there the day a friend asks.

## Y4 — Ready for the store (owner note 2, D49)

What actually stops an upload, fixed; what the store asks for, written down so the owner's
submission is a form-filling afternoon rather than a research project.

- **The icon** is re-exported **opaque**: App Store Connect rejects a 1024-pixel icon that
  carries an alpha channel, and this one does (`sips -g hasAlpha` says so). `tools/icon`
  draws it without one from now on, so regenerating it cannot bring the channel back.
- **Export compliance** answered in the binary: `ITSAppUsesNonExemptEncryption = NO` on the
  app target, because the app opens no connection at all. Without it every upload stops at a
  question.
- **Version 1.4, build 1**, on the app, the extension and the tests alike — the extension's
  version must match the app's or validation fails.
- **A Release build compiles** (`xcodebuild build -configuration Release`), which proves that
  nothing outside `#if DEBUG` refers to the screenshot hooks, the read-only store or the
  seeded launch arguments. Run, recorded in BUILD_STATUS, and one line of
  `tools/check_release.py` — the new script that checks the static facts: the icon has no
  alpha, the three versions agree, the compliance key is set, the privacy page exists, the
  catalogue's files are in the bundle.
- **`docs/PRIVACY.md`**: the privacy policy the store requires a URL for, in the app's own
  voice — nothing leaves the phone unless you export it; no account, no analytics, no
  network. The public repository's copy of the file is the URL.
- **`docs/APP_STORE.md`**: everything App Store Connect will ask, answered: the name and
  subtitle, the description, keywords, the category (Health & Fitness), the age rating
  answers, the privacy label ("Data Not Collected", and why that is true), the review notes
  (a reviewer taps Choose a built-in plan and is in a workout in three taps — no chatbot
  needed), which screenshots to take and the `tools/shot.sh` line for each, and the submission
  order: the paid Developer Program, the release Xcode (27.0 on this Mac is a beta build, which
  the store refuses), Archive, TestFlight for the device checklist, then Submit. Also the two
  things only the owner can decide, stated as choices: the LICENSE for a public repository,
  and the support URL.
- **README** gains a short first section for people rather than agents: what the app is, a
  screenshot, how to build it, where the privacy policy is. The handoff material below it is
  unchanged.

## Y5 — Docs, checklist, bundle

- SPEC §4.1, §4.4, §4.11, §5.1, §5.3 and §10 reconciled; §6.22–6.25 for D46–D49.
- `TEST_CASES.md` gains section **Y** (v1.4), per milestone as they land.
- `DEVICE_CHECKLIST.md` gains v1.4 rows: the intro on a clean install, Start opening before the
  Island appears, a built-in plan run end to end, the Release build from TestFlight.
- `BUILD_STATUS.md`, `DECISIONS_LOG.md`, README, `CLAUDE.md`/`AGENTS.md` and
  `HANDOFF_BUNDLE.md` regenerated; `tools/check_bundle.py` passes.
- The memory of what is left: the device checklist, the owner's Developer Program enrolment,
  the release Xcode, the LICENSE choice, and the submission itself.

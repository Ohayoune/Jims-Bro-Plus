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
| D18 | Home is **quiet**: one Start card, a compact month calendar, one tiny sparkline. Everything else lives in the Plans, History and Settings tabs. A screen has one primary action; secondary actions go in a "···" menu. **Revised in v1.1**: quiet, but leading with the workout. The start card names the day, the plan and the day's exercises, and its button says what it will do ("Start Push", "Resume Push · 23 min", "Start Lower early"); the month grid becomes a 7-day strip that discloses to the month; and the tap-to-cycle sparkline is replaced by one activity line. **Revised in v1.7** (D61–D65): Home is **Today**, one card with the same five zones every day — the day's name, one subtitle, the exercise names, at most one message, Start — and the day's alternatives in one ···; the calendar and the activity line move to History; the tab bar is **Today · History**, with Plans behind Change plan and Settings behind a gear; controls appear when they first have something to do; and each day has a colour. | Owner asked twice for less clutter. §4.0 has the rules. Revision: v1.1 UX review, 2026-09-05 — Start was blind (nothing on Home said what was behind it) and the sparkline's hidden tap was undiscoverable rather than quiet. Revision: v1.7, the owner's note after living with v1.6 (2026-09-13) — "sensory overload… less choices… more forcing… feels like a settings menu" (`docs/ITERATION_8_PLAN.md`). |
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
| App Store (v1.4, D49) | until the membership lapses | the same $99/yr | The paid program, a release Xcode (a beta build is refused), an opaque icon, the export-compliance answer in the binary, a privacy policy URL. `docs/APP_STORE.md` is the submission; `tools/check_release.py` checks what a script can. |

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

- **One primary action per screen**, full width, accent colour, bottom-anchored above the keyboard. Secondary actions that the primary task itself needs while it is running may be visible buttons — Exercises, Undo, rest −30 / +30, Skip rest — and everything else goes behind "···" or a swipe. **Today has one; its alternatives live in one ··· and nowhere else** (v1.7, D61, §6.37). *(v1: "Never more than two visible buttons besides the primary." That rule put Overview, undo and Skip behind a menu that did not exist during rest, which made them unreachable exactly when they were needed — P2.)*
- **Label what the value does not explain.** A bare `10` and `80` get small-caps **REPS** and **KG** labels; a volume figure is labelled Volume. A unit suffix is not a label. Do not label what is already self-evident (no "Notes:" before notes). *(v1: "No labels for things the value already says." Two unlabelled stepper rows were the most-reported confusion in both reviews — P5.)*
- No decorative dividers, cards inside cards, or badges. Group with whitespace, or with one grouped/inset list style used consistently on every screen (R4).
- **Large numbers are for values you act on right now**: the input values, a running countdown, a running timer. A number you are only being told about — a set's duration, a block's duration, a volume total — is body text. *(v1: "The most important number on a screen is the largest thing on it", which made the between-exercise block duration the hero of its own screen — D19, P1.)*
- Show a line only when it has content (no "Notes: none", no empty "Last time").
- **A control appears when it first has something to do**, and stays (v1.7, D64, §6.40). Nothing is removed by this, only delayed: §6.40's table lists every gated control and when it appears, and a control not in it is there from the first launch. Settings is never gated (D56).
- **Colour says which day; the accent says tappable** (v1.7, D65, §6.41). Each day of a plan has a colour by its place in the day list, drawn in four places — a square before the day's name on Today, the calendar's finished and planned days, a square leading each History row, and a square leading the workout header and the Lock Screen's title — and nowhere else: not Start, not the tab bar, not a background. No day is the accent, red or yellow.
- Tab bar with two tabs: **Today · History** (v1.7, D62, §6.38). Today's bar carries a gear and a ···, nothing else; History's carries the same gear in the same place. Plans is Today's ··· → **Change plan** and Settings is the gear, both pushed (§4.2, §4.11). *(v1–v1.6: "Home · Plans · History · Settings. No other navigation chrome on Home." v1.7's T1 kept four — Today · Plans · History · Settings — until D62 settled how many.)*
- **Zones do not move.** Within one task, a control keeps its position across every state of that task: nothing appears, disappears or shifts under the thumb between working, resting and timed work (§4.5, D22, P1).
- **The app speaks in words, and keeps the notation behind a switch** (v1.6, D58, §6.36). A target reads *"Aim 4–6 reps · 100 kg"*, a past set *"Last time 10 × 100 kg"* on its own line and never with "@", an exercise *"3 sets of 8–12 reps · 60 kg"*, a superset member *"paired with Tricep Pushdown"* rather than a bare **A**, a drop *"lighter set 1 of 2"* and, on the exercise's line, *"then lighter, as many as you can"*; "AMRAP" is *"as many reps as you can"*, an effort target *"stop 2 short of failure"*, and every button says the thing rather than the term — **Use this plan**, *"repeats every 7 days"* (D59). **Settings → Compact notation** restores v1.5's forms everywhere at once. Only rendered strings have two grammars: the engine, the plan format, the prompts (§7), the exports and the fixtures know nothing about this.
- **Every confirmation shows its way out** (v1.6, D56). A confirmation presented from a menu is an alert with two named buttons, never a `confirmationDialog`: from a menu anchor a dialog draws as a popover on iOS 26 and drops its cancel-role button. Finish is never red — it saves; only Discard and Delete are.

### 4.1 Today (D61, rewritten in v1.7's T1)
Today is the day's card and nothing else. Top to bottom, on every day of the plan, the same five zones:
1. **The day's name**, `largeTitle`, in ink: "Push", after a small square in the day's colour (v1.7, D65, §6.41) — the square carries the colour, never the name. On a rest day, the next workout's name (D57, unchanged).
2. **One subtitle**, the fragments that have data, in this order: "Push Pull Legs · 5 exercises · 48 min last time · step 3 of 8"; on a rest day, "Planned for Thu ·" in front (D57). "In progress · 5 of 16 sets · 23 min" replaces it while a session is open.
3. **The exercise names**, the first five and "and N more" — and the block is one tappable row with a trailing chevron that opens the day in Plan detail. This is the preview; there is no Preview button (P5: Start is never blind). VoiceOver reads it as "Exercises: Bench Press, …, and 2 more. Opens Push".
4. **At most one message line**, with its own actions, chosen in this order and never two at once: the missed workout ("Push was due Monday" · **Do it now** · **Dismiss**, D37) > the progression that has run its course ("Your progression has run its course." · **Plan the next one**, D44 — since D67 it opens the Progression screen, where it opened the plan) > notifications off (D57). Dismissing the first lets the next speak for this run. Each reads as it read in v1.6; nothing else joins the list without a decision.
5. **Start**, in the bottom slot (D59): **Start Push**, **Resume Push · 23 min**, **Start Lower** on a rest day.

Nothing on Today moves between visits. The screen does not scroll unless Dynamic Type makes it, and then the exercise list is what scrolls while the name, the subtitle and Start hold (the rule U13 set for the workout in v1.6).

**The ···**, top-right, is the only place the day's alternatives live, in this order: **Another day** (the plan's other days, the existing chooser — only when the plan has another day), **Change plan** (the Plans list, pushed onto Today — §4.2, D62), **Plan a progression** while D50 offers it (§6.26), and, while a session is open, **Discard workout** with its alert (D56). Nothing in the menu is itself a confirmation. There is no ··· until there is a plan to have alternatives for; when each item appears is §6.40's table (D64).

**No plans yet**: "No plan yet" as the headline; one sentence beneath — "Choose a built-in plan to start today, or have a chatbot write yours."; **Choose a plan** in the bottom slot — the intro's words (D47) — opening Add plan on the built-in picker (D46, §6.23, with its **Start here** badge and, one tap back, **Create with a chatbot** and **Paste plan**); and one quiet bordered button, **Try a short practice workout**. Two choices where there were three.

Gone from the screen in v1.7: the calendar and the week's line (to History, D63); **Preview** (the exercise block does it); **Another day** and **Plan a progression** as buttons (to the ···); the Week/Month control; the tapped-day line. `HomeStart` (`Core/HomeCard.swift`) resolves all of it — the wording per schedule state, the one message, the ··· items, the block's spoken label — and the view decides nothing (§6.37).

*(v1.6 — "4.1 Home (D18, rewritten in v1.1's R3)": three things, top to bottom, nothing else. **1.** **Start card**, which leads with the workout rather than with the calendar: the day's name as the headline ("Push"), a subtitle of the fragments that have data ("Push Pull Legs · 5 exercises · 48 min last time"), the day's first five exercise names and "and N more", then one button that says what it does — **Start Push**, **Resume Push · 23 min**, or, on a rest day, a "Rest day" headline with "Lower is next, Thu" and **Start Lower early**. **v1.6 (D57)*: the workout is the headline on a rest day too — "Lower" — the button is **Start Lower**, and the schedule is one quiet subtitle fragment in front of the rest, *"Planned for Thu · Upper Lower · 5 exercises"*; "Rest day" and "early" were schedule-speak to someone standing in a gym, and the calendar still shows the rest day. **Preview** opens the day in Plan detail; **Another day** offers the plan's other days (**v1.6, D59**: the Start button sits in the bottom slot every other screen keeps for its primary action, above the tab bar, and these small actions are bordered buttons that wrap, so only tappable text is blue); **Plan a progression** (D50, v1.5, §6.26) joins them only while the plan has no progression and every exercise on the day has a logged session, and opens the Progression screen. **v1.3 (D44)*: when the plan carries a progression, the subtitle also says where it is — "· week 3 of 8", or since v1.5 (D53) "· step 3 of 8", the lowest step among the day's exercises still climbing; when it has run its course, one line says so with **Plan the next one**, which opens the plan. Nothing else on Home moves. No plans yet → "No plan yet" with **Add plan**, plus "Choose a built-in plan" (D46, v1.4, §6.23) and "Try a short practice workout". (v1: "Next up · Pull" and a bare Start, which never said what you were about to do. v1.1–v1.3 offered "Try the sample plan" here — the owner's own Push Pull Legs, weights included, which is exactly wrong for a stranger.) **2.** **Calendar**: a **7-day strip of the current week** by default, with **Month** disclosing the full grid (7 columns, weeks as rows, ‹ › to change month, today outlined) and **Week** collapsing it again. Cells are at least 44 pt in both (P6). A day with a completed session shows a filled accent dot; a future day with a projected workout (§6.12) shows a hollow accent dot (**v1.6, D59**: its label in the accent and no box — twenty outlined boxes in a six-day month shouted as loudly as the done days and Start — while today is outlined in ink and the section header is ink, not accent); a scheduled rest day shows a filled grey dot; a day the plan says nothing about shows no dot at all. Tapping a day shows one line under the grid: "Wed 10 · Legs · 52 min" (tap again → session detail), "Sat 13 · Push · projected" with a small **Start this** if it's today, or "Sun 14 · Rest day". Days with no dot show no line. **3.** **One activity line**: "2 workouts this week · 1 h 32 min", or "No workouts yet this week". "This week" is the calendar week containing today, the same seven days the strip above shows. (v1 had a 44 pt sparkline whose metric changed on an undocumented tap. Both v1.1 reviews called it undiscoverable rather than quiet; `Sparkline`, `HomeMetric` and the Settings row that picked the metric were removed with it. `ExerciseHistory.series` — the per-exercise data behind the chart of D13/§10 — is untouched.))*

### 4.2 Plans
List of plans (active one marked), reached from Today's ··· → **Change plan** and pushed onto Today (v1.7, D62, §6.38 — it was a tab until then). Tap → Plan detail. Primary action: **Add plan** (§4.4). Swipe to delete, with a confirmation dialog (D25 v1.1) — swiping no longer deletes immediately.

### 4.3 Plan detail
- Name, units, schedule, and the **repeat block**: the cycle as a row of chips, `Push · Pull · Legs · Push · Pull · Legs · Rest`, with "repeats every 7 days" beneath and the current position highlighted. **v1.6 (D59)**: the line reads "kg · repeats every 7 days" (never "rotation", the format's word), the chips wrap instead of scrolling off the edge, each day ends with an **Add exercise** row and a bordered **Start** button rather than a text link, and the menu's "Set as active" reads **Use this plan**. Weekday plans show Mon…Sun with the day name or "rest" under each.
- **Progression** (D44, v1.3, §6.21) is History's since v1.7 (D67, §4.10, §6.42), for the active plan *(v1.3–v1.7's T6: one row here, under the repeat block)*. The row reads "Plan it", "Week 3 of 8", "Step 3 of 8" (D53) or "Finished" — with, since v1.5 (D50), a second line saying what it is ("A chatbot plans your next steps from what you have lifted") and the accent chevron every row that opens a screen has, opening the Progression screen: the period (4 / 6 / 8 / 12 weeks), **Use my history** when there is any, the three chatbot steps, **Paste progression**, a review of every exercise's weeks with the material warnings in yellow, **Save progression**. With one saved, the same screen reads it back, week by week with this week's targets first, and offers **Plan the next one** and Remove.
- Days: each expands to its exercises (sets, target, rest, drops, rep range).
- **Editing** (D29, v1.1): tapping an exercise opens a sheet for its name, set count, reps, rep range, weight and rest. Edit mode reorders and deletes exercises within a day; the day header's menu renames the day and duplicates it. Every change goes back through the import pipeline, and one it would refuse says why rather than appearing to work.
- **JSON edits** (D43, v1.3, §6.19): the exercise sheet's **Edit as JSON** opens the exercise's own JSON — for what the fields cannot say: one set unlike the others, drop sets, a warning beep. The day's menu has **Add exercise** (a template to fill in, or a pasted list) and **Edit day as JSON**. One sheet does all of them: monospace text, a Paste button, the friendly error sentence with the real path behind Details, Save. Every Save is a `PlanEdit.Operation` through the import pipeline.
- "···": Set as active, Rename, Copy JSON, **Edit JSON**, **Add day from JSON**, Delete. Edit JSON (v1.3, D43; v1.1 called it Replace) opens Import targeting this plan's id with the plan's text already open: saving it keeps the id, the cycle position and its anchor (D37) and, if this plan was active, keeps it active. Add day from JSON appends a pasted day — or every day of a pasted plan, which is how a week the chatbot cut short gets finished — and puts it into a rotation's repeat block. Delete confirms (D25 v1.1).
- Any day has **Start** (override). If a session is in progress this triggers the switch popup (D17): "You're in the middle of Pull (5 of 16 sets). Switching workouts mid-session isn't recommended." Buttons: **Keep going** (default), Finish Pull and start Legs, Discard Pull and start Legs.

### 4.4 Add plan (D26, rewritten in v1.1's R3)
The chatbot round-trip is this app's premise, and the v1 screen — a JSON text box — never explained it. **Add plan** offers four ways in, and the editor is a detail behind "Show text":

- **Choose a built-in plan** (D46, v1.4, §6.23), first in the list: one screen with the four routines the app ships — the name, a line, "3 days a week · about 45 min · barbell, rack, bench…", who it is for — and, beneath them, the sentence that says to build your own. **v1.6 (D57)**: Full Body carries a **Start here** badge while History is empty, and the sentence beneath sends the reader back to Add plan's **Copy prompt** by name rather than to a control that is not on this screen. Tapping one opens the same **Review plan** sheet a pasted plan gets, with the routine's paragraph on top; **Save plan** saves it like any plan. Not offered when the sheet is editing one plan's JSON.
- **Paste plan**, the one you use when the chatbot's reply is already on the clipboard. It imports immediately; the button does nothing when the clipboard holds no text (O3).
- **Create with a chatbot**, three numbered steps: 1 **Copy prompt** (the accent button since v1.5, D50; it reads "Copied" and goes back on its own after about two seconds) beside the sentence that explains the mechanism — "Copy the prompt. It tells the chatbot the exact format the app reads, so its reply pastes straight back in." — 2 paste it into your chatbot and describe your training, 3 copy its reply and come back. The section's footer says the other half: "The app never talks to the chatbot itself; you carry the text both ways." The draft in the editor survives leaving the app.
- **Build it day by day** (D52, v1.5, §6.28), beneath the three steps: the same round-trip in several pastes. **Copy outline prompt** asks the chatbot for the plan's outline — name, units, schedule, the day names, the repeat block, no exercises — and **Paste outline** turns it into a draft with one empty slot per day; each slot has **Copy day prompt** and Paste; **Review plan** appears when every slot is filled and opens the ordinary review; Save plan saves it like any plan. The draft survives leaving the app and says "Continue · 2 of 4 days pasted" on the row; the menu can discard it.
- **Import file**, for a `.json` on disk.

**Errors** lead with a plain sentence naming where the problem is — "Day 1, exercise 2, set 2 needs either a rep target or a duration." — with the path, the code and the importer's own message behind **Details (n)**, and **Copy fix-it prompt** unchanged. `IssueText.friendly` has a sentence for every `E_` code in PLAN_FORMAT §4 and falls back to the importer's message for one it doesn't know. **v1.6 (D55)**: a paste with no JSON in it at all — a plan written in words, the most natural first paste there is — gets its own sentence, *"This is a plan in words. Send it to a chatbot with the prompt and paste back what it writes."*; only JSON that will not parse is told the reply looks cut off.

**Review plan** replaces the v1 preview: name, units, schedule and cycle chips; the days as rows that expand to their exercises with **per-set** targets ("3 × 8–12 · 24 / 26 / 28 kg"), the first day already open; **material** warnings shown in yellow (a dropped unit, a removed load, a changed grouping, an inferred schedule) with **cleanup** warnings folded behind "Details (n)" (curly quotes, unknown fields, rounded weights — tidying that did not change the workout); a **"Set as current plan"** toggle, default on; then **Save plan**. **v1.6 (D57)**: when the plan did not name its unit — every built-in plan, and a pasted plan without `units` — a **kg / lb** control above the days asks for it, defaulted from Settings; the numbers on the sheet read in the chosen unit, and the choice is written into the plan and its JSON before it is saved (`ImportResult.unitsStated`). Same-name conflict → Replace / Keep both / Cancel. The toggle's value is passed through as `makeActive`; the very first plan ever saved always becomes active regardless of it, since there is nothing to compare it to.

### 4.5 Workout screen (v1.1, D22)
One screen, five fixed zones, top to bottom, identical across every state below. Only the zones' contents change; none of them appears, disappears, or moves position between working, resting, a timed set, or a block having just finished.

> **Build status**: built in R2. `WorkoutScreen.model(active:history:now:)` resolves the whole screen — zones, set rows, prefilled inputs, strip and primary action — as a `WorkoutScreenModel`, and the view only renders it, which is what makes "the zones never move" a unit test (O50) rather than a convention.

1. **Header** (v1.2, D34): the **stage** the workout is in, said in words, above a progress bar of the whole day — **Warm-up**, **Exercise 2 of 5 · Set 2 of 3**, **Resting**, **Between exercises** — led by a small square in the day's colour (v1.7, D65, §6.41), the header's one mark of which day it is. Then elapsed time · progress ("Exercise 2 of 5 · Set 2 of 3", or "· drop 1 of 2", or "A · round 2 of 3" for a superset member; **v1.6 (D56)**: omitted when it would only repeat the stage, which while working it did) · **Exercises** (opens the Overview sheet, §4.8, reachable in every state including rest) · minimize (returns to the tabs; the session and its timers keep running; Home shows "<Day> in progress · <elapsed>" with **Resume**) · "···" (Skip set, Skip exercise, Do later, **Change exercise** — v1.3, D42 — Finish workout — Rename exercise moved to Session detail, a history-editing task, not a mid-workout one).
2. **Exercise block**: the exercise's name (opens its history) and target line (with notes, truncated to one line), then the current exercise's set rows: finished rows show what was logged ("✓ 10 @ 80") and never how long it took (D19), the current row is highlighted with its target and last-time value, upcoming rows show their targets. A row carries the set's own target only — the exercise's notes appear once, on the target line above, rather than repeating on every row. In a block holding more than one exercise (a superset round) each row names its exercise instead of repeating the shared group tag, which would otherwise make two rows read identically. A superset shows the current round's members. Tapping a finished row opens the edit sheet; tapping an upcoming row jumps to it (§6.6 `jumpTo`).
3. **Inputs**: small-caps labels **REPS** and the unit (**KG**/**LB**) above the − value + rows; the weight row is omitted for bodyweight exercises (D21); an empty weight field reads *tap to type* in the secondary colour inside a soft outline, so a plan without weights (D46) does not show a blank gap between − and + (v1.6, D56), and while the field is empty and the exercise has no history one line under it says why — *"Type the weight you lift. The app remembers it from then on."* (`InputDefaults.weightHint`, v1.6, D57); a "72.5 suggested" chip appears under the weight when §6.11 produced one. Timed sets replace the reps row with the timer block described below; the weight row stays unless bodyweight.
4. **Status strip** (always present; its content depends on phase, per §4.6/§4.7 below). **v1.6 (D56)**: while a field is focused its trailing slot holds **Done**, which closes the keyboard — the system keyboard toolbar drew Done as a floating pill over the lower half of the primary button on iOS 26. At accessibility text sizes the strip drops its next-set line and the set list shows the current row only, so the inputs and the button are on screen together.
5. **Primary action**, bottom-anchored above the keyboard, full width: **Log set** while working or resting (logging during rest ends the rest early); **v1.6 (D57)**: during the *warm-up* the button reads **Start first set** and ends the warm-up (`skipRest`) — nothing has been done yet, so it never logs — while between-set and between-exercise rests keep Log set; **Start timer** / **Done** / **Stop** for a timed set, per D20. When the step waiting on the far side of a rest is a timed one, **Start timer** ends that rest and starts the work in the same tap, exactly as logging out of a rest does — the one button in the one slot is never inert.

After logging, a step's seconds (D19) remain editable in the Overview like any other value.

### 4.6 Rest, within the status strip (v1.2: one rest, three kinds)
There is one rest in the app, and it says which of three kinds it is, because "a break" that does not say what it is for is the thing the owner said was unclear:

| Kind | When | Length |
|---|---|---|
| **Warm-up** (D32) | Before the first set of the session | `Settings.warmUpSeconds`, 0 = off |
| **Rest** | Between sets of an exercise, and after a superset round | The set's resolved `restSeconds` (§6.3) |
| **Between exercises** (D33) | After a block's last step, before the next exercise | `Settings.transitionRestSeconds`, 0 = straight through, as v1.1 |

The strip shows: the kind, named; the countdown m:ss; −30 s / +30 s; **Skip** (whose label names the kind — "Skip rest", "Skip warm-up"); and "Set logged · **Undo**" (D23) for as long as the rest runs. **v1.6 (D59)**: Undo sits on the set row that was just logged (↺ beside its tick, `WorkoutScreenModel.undoStep`); the strip keeps its own Undo only at accessibility text sizes, where the list shows the current row alone. While working with nothing to report the strip says what the button will start — "Rest 1:30 starts when you log", or "Then on to Barbell Row" on a block's last set (`WorkoutScreen.idleLine`) — rather than sitting blank. Alert at zero (§6.4); at zero the strip reads "Rest over · +0:12" (or "Warm-up over") until the next log. "set 0:34" (how long the set just logged took, D19) appears in the strip in small text, never as the largest element on the screen.

None of the three gates anything. The next set's card is already on screen and the primary button works throughout — logging (or starting a timed set) during any of them ends it early, exactly as v1.1's rest did.

### 4.7 Between exercises: the status strip's block-done state (D14, revised in v1.1; timed in v1.2's D33)
There is no separate screen and no Continue gate. The moment a block's last step is logged or skipped, the next step's card appears immediately and the exercise block (zone 2) already shows the next exercise. The status strip reads the finished block's line — "Barbell Row done · 9:40 · try 72.5 kg next time".

**v1.2 (D33)**: walking to the next machine takes as long as a rest does, and v1.1 gave it no time at all — so it now runs a real countdown of `Settings.transitionRestSeconds` (default 120 s), with the same −30 / +30 / Skip controls as any other rest, and the same alert at zero. Set that setting to 0 and v1.1's behavior comes back exactly: no countdown, and the count-up "moving on · 0:42" beneath the block's line instead. The strip clears on the next log or skip, or can be dismissed directly (`dismissBlockDone`, §6.6). Timed-set logic behaves as normal throughout — there is no state in which it is suspended.

### 4.8 Overview (from "···", or the header's Exercises button)
Every step grouped by exercise with status and set time ("10 @ 60 · 0:34"); finished blocks show duration and advice. A pending row carries the set's own target only; the exercise's note is said once, on the card, never on every row (v1.6, D55). Tap logged → edit; tap pending → jump (cancels rest, and clears any block-done strip). A **skipped** step (v1.1, D27) can also be edited: the sheet's Save now sets its result, marks it logged, and updates `loggedAt` — recovering it rather than silently doing nothing. Reachable in every workout state, including rest and a block-done strip (v1.1) — previously it was attached only to the step card and unreachable during rest.

### 4.9 Summary (rewritten in v1.1's R4)
Leads with "**Workout saved**", then one line of what happened — "Push · 48 min · 16 of 18 sets · Volume 12,400 kg", with the volume fragment omitted entirely when it is zero (a bodyweight day has no volume, and "Volume 0 kg" reads like a failure). **v1.6 (D57)**: one line under it says what comes next — *"Next: Full Body B, Friday"*: tomorrow, a weekday within the week, or a date — from the same schedule the calendar draws, read after the rotation has advanced; nothing for an imported session or a plan since deleted (`SummaryText.next`). Then one section per exercise: a **sentence** comparing it to last time — "2 more reps at the same weight", "+2.5 kg", "+2.5 kg, 1 fewer rep", "5 s longer held", "First time" — plus the progression advice when there is any. When the weights varied within the exercise no single sentence is true of it, so a compact "10 @ 60 → 10 @ 62.5" table appears under a volume headline instead. An exercise nothing was logged for today reads "Nothing logged", whether or not it has a past — "First time" is for a first time that happened (v1.6, D55). Set and block durations sit behind **Details** (D19). **Done**.

*(v1 printed both sessions' raw sets — "10, 8@60 · last 10, 9@60 · kg" — and left the reader to do the subtraction, with the block duration beside it as if it mattered as much.)*

**v1.5 (D54, §6.30)**: a goal this workout was the first to reach is said under the headline — "Goal reached: Barbell Bench Press 100 kg × 5" — in the reserved green, like a record.

### 4.10 History
**The calendar first (v1.7, D63, §6.39).** History opens with the calendar that was Home's until v1.7, its drawing unchanged: a **7-day strip of the current week**, with **Month** — once a workout is older than this week (D64, §6.40) — disclosing the full grid (7 columns, weeks as rows, ‹ › to change month) and **Week** collapsing it again; cells at least 44 pt in both (P6). A finished day is filled and named in its day's colour, where v1.6 used the reserved green, and a day the plan expects is named in its day's colour, where v1.6 used the accent (D65, §6.41; §6.12: the active plan only, never more than 62 days ahead); a scheduled rest day is a short dash; a day the plan says nothing about is its number alone; today is outlined in ink. Tapping a day shows one line under the grid: "Wed 10 · Legs · 52 min ›", the way into that workout — pushed onto History like its row below, a chooser first when the day holds two — "Sat 13 · Push · planned", or "Sun 14 · Rest day"; tapping the same day again opens a finished one and otherwise clears the line. A day the plan says nothing about shows no line. There is no **Start this**: a workout starts on Today (§4.1). Under the calendar, **the week's line**: "2 workouts this week · 1 h 32 min", or "No workouts yet this week" — this week is the calendar week containing today, the seven days the strip shows. With no workouts at all the strip still shows the plan's week — worth seeing on day one — with "No workouts yet" under it, then **Import from another app** (D45) with "Finished workouts appear here." Below the calendar, as before: one block of Metrics, Find an exercise and — since D67 (§6.42), for the active plan — **Progression**, the row Plan detail had (§4.3), opening the same screen; then Goals, then the months — the block and Goals from the first workout (D64, §6.40). There is no search field (D66, §6.42): **Find an exercise** is the way to an exercise's history.

Sessions newest first by month, and under Metrics a **Find an exercise** row listing every exercise, most recently trained first, each opening its history (D59, v1.6) — since v1.7 the only way to find one. *(v1.1–v1.7's T6: also a **search box** that found an exercise by name, D30; D66 removed it, §6.42 — a second way to the list the row opens.)* (**v1.6, D59**: a session's row reads "28 min · 16 sets · 13,920 kg lifted", not "28:08 · 16 sets · 13,920 kg"; **v1.7, D65, §6.41**: each row leads with a small square in its day's colour, grey for a workout whose day is in no plan). Session detail (editable, deletable, with a confirmation on delete, and **Rename exercise**, which moved here from the workout menu in v1.1); exercise history with best set, every session that included it, and a **chart of top weight over time with the reps annotated** (D13, built in v1.1's R5). A set that beat everything before it carries a **PR** badge here and on the Summary (D30). Tapping an exercise name anywhere opens it. A skipped step in session detail can be recovered the same way as in the live Overview (D27 v1.1). **v1.5 (D54, §6.30)**: a **Goals** section at the top, under Metrics — each goal's exercise, its line ("100 kg × 5 · best 82.5 kg × 5 · by 1 Dec", or "reached 3 Sep" in green) and a bar of how far along it is; **Set a goal**; swipe to remove. An exercise's own screen has **Set a goal** too.

### 4.11 Settings
Reached from the gear at the top-left of Today and of History, and pushed (v1.7, D62, §6.38 — it was a tab until then). Units, default rest, **warm-up length** (D32, v1.2), **between exercises** (D33, v1.2) — each with a row of preset buttons (Off · 1 · 2 · 3 · 5 min; 60 · 90 · 120 · 180 s) beside its stepper since v1.6 (D59) — sound, vibration, notifications state, keep awake, weight step, **smallest weight change** (D35, v1.2), Export backup, **Import backup** (D31, v1.1), **Export history (CSV)** and **Import history (CSV)** (D45, v1.3), Delete all data, About — the version, the counts, and **How the app works** (D47, v1.4, §6.24), which reopens the introduction with **Done** in place of Choose a plan. (The home-chart metric row went with the sparkline in v1.1's R3.)

The three v1.2 rows, in the owner's words:

- **Warm-up length** — "there should be a warm-up phase before you actually start the first exercise." A duration, 0 to 30 min, 0 meaning off.
- **Between exercises** — "type how long it takes between switching different exercises." A duration, 0 to 10 min; 0 restores v1.1's behavior of moving straight on.
- **Smallest weight change** — the smallest increment the equipment actually allows, per unit. It is what every suggestion is rounded to (§6.11), so the app never says "try 134 lb" when the plates only make 135.

## 5. Flows

### 5.1 First run
**The introduction** (D47, v1.4, §6.24) comes first, over the tabs, on a launch where the store holds no plans and it has not been dismissed: four pages — *A plan, then Start* · *Log the set, rest, repeat* · *It remembers* · *Your plan, your way* — and one primary action, **Choose a plan**, which opens Add plan on the built-in picker, with **Not now** beneath. Dismissed either way it does not come back; it lives in Settings → About → **How the app works**. It is never shown over a phone that already has plans.

Today's empty card offers two ways to have something to run today (§4.1):
- **Choose a plan** (D46, v1.4, §6.23; the introduction's words since v1.7, D61), in the bottom slot, opens Add plan on the picker: four routines with no weights in them, each through the ordinary import pipeline, saved with **Save plan** → Today shows the first day, its exercises and **Start Full Body A**. *(v1.4–v1.6: a link reading **Choose a built-in plan**.)* *(v1.1–v1.3: **Try the sample plan** imported the bundled `SamplePlan.json` — the fixture `examples/valid/weekly-rotation.json` — and made it active. The file stays in the bundle for the seeder, the screenshots and O1; it is no longer offered here.)*
- **Try a short practice workout** (v1.1) imports the bundled `PracticePlan.json`: one day, three straight-set exercises (one of them bodyweight), 60 s rest, no supersets, drops or timed work — small enough to run through in a few minutes to learn the app. It goes through the same import pipeline as any other plan; nothing in `examples/` is involved.

### 5.2 Getting a plan in (the loop that makes this app different)
1. Settings has units and default rest. **Add plan** → **Copy prompt** (step 1 of the three the screen lists).
2. User opens ChatGPT/Claude, pastes the prompt, adds their plan text below it ("Mon: bench 3×8 … " or "design me a 4-day upper/lower split").
3. Chatbot replies with a ```json block. User copies it.
4. Back in the app: **Paste plan** → **Review plan** (the exercises, the per-set targets, the warnings worth reading) → **Save plan**.
5. If it fails validation: the sentence on screen says what and where; **Copy fix-it prompt** → paste into the same chat → chatbot outputs corrected JSON → repeat step 4.

### 5.3 Running a workout
Today → Start → step card → Log set → rest → … → last set of the exercise → done screen (count-up) → Continue → next exercise … → last step → Summary → Done. Notification permission is requested the first time a session starts (not at app launch). **v1.6 (D57)**: at the first **Log set** or **Start timer** of the app's life — the moment the first rest, whose end the alert announces, is about to begin — not at Start over the first card; the intro's rest page says the app will ask. If denied, a one-time in-app banner explains that alerts only work with the app open. **v1.4 (D48, §6.22)**: the workout screen appears the moment the session exists; the notification, the Lock Screen activity and the disk write follow behind it.

### 5.4 Interrupted workout
The active session is written to disk after every event. If the app is killed (or the phone dies), Today's card offers **Resume** on next launch. Resume restores the exact step and, if a rest was running, shows it with the correct remaining or overrun time computed from `endsAt`; if the done screen was showing, its stopwatch continues from its `startedAt`.

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

**v1.6 (D57)**: a fresh install's `Settings()` has `warmUpSeconds = 0` — a stranger's first tap on Start opened a five-minute countdown they had not asked for, under a permission alert — and a settings file that predates the setting decodes to `Settings.warmUpBeforeV16` (300), so the phones that lived with D32's default keep it. During the warm-up the primary button is **Start first set** (§4.5).

### 6.15 The stage (D34, v1.2)
"It should be a bit more clear what stage of the workout you're on."

`WorkoutStage` resolves, in Core, to one of: **Warm-up**, **Exercise k of n · Set j of m**, **Resting**, **Between exercises**, **Done** — plus a `progress` fraction of the whole day, which is logged-or-skipped steps over total steps. The header renders both; nothing about the stage is computed in a view, so the wording per state is a unit test.

### 6.16 Metrics (D39, v1.2)
"Should be able to select a past workout and see … metrics for the past — I don't know exactly what metrics would be, but they should be included."

Everything is a `Metric`: a label, an already-formatted value, and a one-line note where the number needs one. Views render the list; they compute nothing.

**One workout** (`SessionMetrics.of(_:history:)`, shown in Session detail): duration; **working** and **resting** time with the share of the session each took; sets done of sets planned, with the skipped count; volume; reps; time under tension for timed work; the heaviest set; personal records with the exercises that set them; the average set. A metric with nothing to say is absent rather than zero — a bodyweight day has no volume, and "Volume 0 kg" reads like a failure.

**A run of workouts** (`TrendMetrics.summary(_:days:)`, on the **Metrics** screen under History, over 7 / 30 / 90 days): how many workouts and how many a week; time trained and the average length; volume; sets; consecutive weeks with at least one workout; the most-trained exercise; and the all-time count with the month it started. Volume only adds up within one unit, because the app never converts (D10). Under the numbers, the workouts of that window, so any figure can be traced back to the days that made it.

**Getting to a past workout** is one tap from three places: the History list, the **Metrics** screen, and the calendar at the top of History (Home's until v1.7, D63) — where the line under the grid is now the way in ("Sat 6 · Legs · 28 min ›"). v1.1 wanted a second tap on the cell, which nothing on the screen said you could do.

### 6.17 Lock Screen and Dynamic Island (D40, v1.2)
"Could also have the time appear at the lock screen at the top — that would also be useful — and in the Dynamic Island."

A **Live Activity** runs for as long as a workout does. It shows the stage (Warm-up, Rest, Between exercises, or the exercise's name), the line under it ("Bench Press · set 2 of 4 · 8–12 · 60 kg"), the timer, and a bar of the day's progress. In the Dynamic Island it is the same three states compact, expanded and minimal.

- **The countdown is drawn by the system**, from a `Date`, exactly as §6.4's rest timer is. The app does not push an update per second and does not have to be awake for the number to be right.
- **`WorkoutActivityState` is resolved in Core** from the same `ActiveSession` the workout screen reads, so the Island and the app cannot disagree. `WorkoutActivityState.swift` is compiled into both the app and the widget extension — it is the contract between them, and depends on nothing but Foundation. *(v1.2–v1.6: "the one file compiled into both".)*
- **The day's colour rides along** (v1.7, D65, §6.41): `WorkoutActivityState.dayColour`, resolved with the plans, draws a square before the title on the Lock Screen and in the expanded Island, and the compact Island's figure takes it while working. `DayColour.swift` (a name, Foundation only) and `DaySquare.swift` (the one mapping to a `Color`) are compiled into the extension alongside it.
- **ActivityKit lives behind `ActivityPresenting`**, injected exactly as `NotificationScheduling` is, so what the Lock Screen would show is a unit test rather than something only a phone can answer.
- A state that has not changed is not pushed. A per-second tick that woke the system sixty times a minute would cost battery for no new information.
- The activity ends when the workout does — finished **or discarded**. A countdown for a workout that no longer exists is worse than none. **The app never assumes it is the process that started it** (D60, §6.35).
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
**v1.5 (D53, §6.29)**: a progression is a ladder of *steps* per exercise, earned by performance; what follows describes the calendar mode, kept as a choice.

"A feature called progression: based on the current workout plan, give the chatbot a JSON and have it calculate your progression over a certain period. When there is history, use it as context." The app's premise is the chatbot round-trip, and until now it ran one way. Progression runs it the other way: the app writes out what the plan is and what you have actually done, the chatbot plans the next N weeks, and the plan carries the answer week by week.

- **The model.** `Plan.progression: Progression?` — a start date, a number of weeks (1–52), and per (day, exercise) one `ProgressionWeek` per week: a weight and/or a work target for every set, or per-set overrides. Optional in `Persistence.swift`; a plan without one is exactly a v1.2 plan. `Session.progressionWeek` / `progressionWeeks` and `SessionExercise.progressionWeek` record which week a workout was.
- **The prompt** (`Prompts.progression`, marker `JIMMSBRO-PROGRESSION-PROMPT-V1`, PROMPT.md §3): the period, the plan as a compact listing (one line per exercise, not its JSON), the loadable increment (D35), and — when **Use my history** is on and there is any — the last six sessions of every exercise in the plan within 90 days, with the advice the most recent one earned. Kept under 9,000 characters by shortening the history first, never the plan.
- **The reply** (`ProgressionImport`, PROGRESSION_FORMAT.md): a small JSON — `weeks` and one entry per exercise with an array of week objects. Read with the plan importer's leniency, matched to the plan by day and exercise name (§6.9), every weight snapped to the loadable increment, weights on bodyweight exercises dropped, and everything dropped or short **said**: material warnings on the review, tidying behind Details. Nothing about the plan's structure changes.
- **The week** is calendar weeks from `startDate`, which is the day the progression is saved. `Session.start` applies the current week to the day's snapshot (D7 holds: the session records what it was asked to do) and stamps the week on the exercises it touched. An exercise, week or set the progression says nothing about keeps the plan's own target; a range of reps also becomes the rep range advice judges by. The day after the last week, the plan's own targets and advice are back — nothing lingers.
- **On the workout**, prefill shows the week's weight and reps (§6.5, rule 0) and the chip says which week (§6.11). The Summary's line and Session detail's first line carry "week 3 of 8". Home's subtitle carries it too, and when it has run out Home offers **Plan the next one**.
- **Edits keep it, Replace drops it.** A structured or JSON edit (D29, D43) carries the progression through — entries match by name, so a renamed exercise simply stops matching. Edit JSON / Replace of the whole plan, or a name-conflict Replace on import, starts a new plan without one.

### 6.22 A tap's result before its side effects (D48, v1.4)
"Sometimes when a button is pressed it takes a second for the app to load." The second was the workout cover waiting for `startDay` to finish, and `startDay` finished only when everything it causes had landed: the rest notification through `UNUserNotificationCenter` (one round-trip per request), `plans.json` through the store actor, and the Live Activity through ActivityKit, which is the slow one and the newest. The engine itself was ready in the first line; everything after it was the system being told, and Home and Plan detail both waited for the telling before setting `showWorkout`.

- **The rule.** The model changes its state synchronously and *then* tells the system; a view never waits for the telling to show the change. `AppModel.startedWorkouts` counts the workouts this run of the app has started, incremented the moment the engine exists, and `RootView` opens the workout cover on every change of it. No view sets the cover after awaiting `startDay`.
- `startDay` itself stays sequential and atomic: effects run in order, and every write lands before the next event's can. Only what the *view* waits for changed. Making the effects fire-and-forget would let a later event's write land before an earlier one's.
- **Resume** sets the cover directly, as before. A session restored at launch is offered as Resume on the card (§5.4), because `load` never touches the count. A start refused mid-session (D17) does not count; a switch does.
- Every other event already showed its result first — `library.apply` mutates before the first await, and `justCompleted` is set before the finish's writes — so Log set, Skip and the Summary were never waiting. Start was the one path whose visible result was a presentation the view held back.

### 6.23 Built-in plans (D46, v1.4)
"A couple of prebuilt plans that cover the major workout routines, with the suggestion that the user builds their own. The built-in plans should all be really well thought out." Until v1.4 the only plan without a chatbot was the sample — the owner's Push Pull Legs with the owner's weights in it. Built-in plans are four routines covering how most people actually train, written to the app's own format (`JimmsBro/Resources/<id>.json`), each through the ordinary import pipeline with **no errors and no warnings of either kind**, and offered next to — never instead of — writing your own.

- **The four**: **Full Body** (3 days a week: A and B alternating across a 14-day repeat block, A B A then B A B; new to lifting, or back after a break), **Upper Lower** (4 days: Upper A · Lower A · rest · Upper B · Lower B · rest · rest), **Push Pull Legs** (6 days: Push · Pull · Legs twice, one rest day) and **At Home** (3 days, A and B on the same 14-day block, no equipment at all). Rotation plans, every one, so the calendar and the start card work as they do for any other.
- **What "well thought out" means**, each a test (Y4–Y9): every day opens with the biggest movement and ends with the smallest, and rest never climbs as the day goes on; five to seven exercises and 15–22 sets a day; **every rep exercise carries a rep range**, so the advice of §6.11 works from the first session; every hold is a fixed duration with the warning beep on; rest is written on every exercise (180 s for the squat and the deadlift, 150 s for the presses, 90–120 s for rows and secondary work, 60 s for isolation, 30–45 s for core); two isolation exercises that share a rest are a superset in the two intermediate plans and nowhere in the two beginner ones; every exercise has a cue in its notes and the first note of every plan says what to do about the empty weight field.
- **No weights.** The app never guesses what a stranger can lift. `units` is omitted, so the plan takes the user's setting; `weight` is omitted everywhere, so the first set's field is empty, the user types what they lift, and from then on prefill (§6.5) and the advice fill it in. Bodyweight movements are flagged, so the card never asks for a weight on a push-up.
- **One spelling per movement across all four plans and the practice plan** — "Barbell Back Squat" in Full Body is "Barbell Back Squat" in Push Pull Legs — so moving from one routine to the next carries history, prefill and records along (§6.9).
- **The catalogue** is Core (`BuiltInPlan`, `BuiltInPlans.all`): the id, which is the resource name; the name; a tagline; the paragraph shown on top of the review, saying what the routine is and why it is built this way; who it is for; days a week; the equipment. Everything countable is read off the plan, not stated: the picker's "about 45 min" is `BuiltInPlans.estimatedMinutes` — the warm-up, the walk between exercises, forty seconds a set of reps or a hold's own seconds, and the plan's rest after every set that is followed by another in its block, through the real flattening — with the user's own settings, to the nearest five minutes.
- **The suggestion to build your own** is one sentence (`BuiltInPlans.buildYourOwn`), the picker's footer: these are starting points, not prescriptions; the best plan is the one written for you; **Create with a chatbot** is where that happens.
- **Where**: Add plan's first row (§4.4); Today's empty card (§4.1); the introduction's last page (§6.24). `AppModel.loadBuiltInPlan(id)` reads and imports without saving; **Save plan** saves through the ordinary path with `keepBoth`, so a built-in plan saved twice is "Full Body" and "Full Body (2)" like any plan (§6.8). An unknown id, or a file missing from the bundle, is `E_NO_BUILT_IN` with a sentence, never a crash.

### 6.24 The introduction (D47, v1.4)
"An introduction screen that explains how the app runs." The app's premise is a loop nobody has seen before — a plan, Start, log the set, the rest runs itself, the app remembers — and until v1.4 the first screen a stranger saw was "No plan yet". The introduction says the loop out loud, once, and then gets out of the way.

- **The content is Core.** `Introduction.pages`: four `IntroPage`s (a symbol, a line, a paragraph): *A plan, then Start* · *Log the set, rest, repeat* (the rest timer, the Lock Screen and the Island, a hold's own countdown, and — v1.6, D57 — that the app asks to send the alert the first time you log a set) · *It remembers* (prefill, the advice at the top of the range, History and records) · *Your plan, your way* (built-in plans, the chatbot round-trip, Progression). What the app claims about itself is a test: every control a page names — **Start**, **Log set**, **Add plan**, **Create with a chatbot**, **History**, **Progression**, a **built-in plan** — must exist by exactly that name (`Introduction.namedControls`, Y13), so a rename that leaves the intro behind goes red.
- **When.** `Introduction.isDue(plans:settings:)`: the store holds no plans and `Settings.introSeen` is false. `AppModel.introDue` adds "and the store has been read", so a launch never flashes it over a phone that turns out to have plans. A first launch, or the launch after Delete all data, which is a first launch by choice. Never over a phone with plans: the owner's phone gets the row in Settings, not a cover.
- **`Settings.introSeen`**, optional in `Persistence.swift` (absent → false, so the frozen v1 settings file still decodes), set by `markIntroSeen()` on either dismissal. In Settings rather than a flag on the side, so Delete all data brings the intro back and a backup carries it. The setting changes synchronously and the cover follows it; the write lands behind (D48).
- **The screen** (`IntroductionView`): pages you swipe with the system's page dots; one primary action — **Choose a plan**, which dismisses the intro and, once the cover is down, opens Add plan on the built-in picker (§4.4) — and one quiet **Not now**. Four screens is the ceiling; a page is one symbol, one line, one paragraph. Nothing on Home changes.
- **Reachable later** from Settings → About → **How the app works**, as a sheet with **Done** in place of Choose a plan.

### 6.25 Ready for the store (D49, v1.4)
"v4 should be getting the app ready for publishing." What actually stops an upload, fixed in the build; what the store asks for, written down once.

- **The icon is opaque.** App Store Connect rejects a 1024-pixel icon with an alpha channel, even one whose every pixel is opaque, and `tools/icon` wrote one (`premultipliedLast`). It now draws with `noneSkipLast`, the PNG's colour type is 2 (RGB), and `tools/check_release.py` reads the byte so it cannot come back.
- **Export compliance is answered in the binary**: `ITSAppUsesNonExemptEncryption = NO` on the app target, because the app uses no encryption beyond what iOS applies to its files. Without it every upload stops at a question.
- **Version 1.4, build 1**, the same on the app, the `JimmsBroActivity` extension and the tests — the extension's version must match the app's or validation fails. The number the store shows is the number the docs use.
- **A Release build compiles** (`xcodebuild build -configuration Release`), which proves that nothing outside `#if DEBUG` refers to the screenshot hooks, the read-only store or the seeded launch arguments. Run for every milestone from Y4 on; recorded in BUILD_STATUS.
- **`tools/check_release.py`** checks the static facts: the icon's colour type and size, the three versions agreeing and matching `docs/APP_STORE.md`, the compliance key on both app configurations, the extension's Info.plist not hard-coding a version of its own, the privacy policy and the submission page existing, and every catalogue id (§6.23) having its file in the bundle and in the project.
- **`docs/PRIVACY.md`** is the privacy policy the store requires a URL for: nothing leaves the phone unless you export it; no account, no analytics, no network; what you paste into a chatbot is that chatbot's business. The public repository's copy of the file is the URL.
- **`docs/APP_STORE.md`** is the submission: the order of things (the paid program, a release Xcode, Archive, the record, TestFlight for the device checklist, Submit, and how an update goes), every field of the record, the description and keywords, the review notes (a reviewer is in a workout in three taps through the built-in picker), the privacy questionnaire's answer and why it is true, the screenshot list with the `tools/shot.sh` line for each, and the choices only the owner can make: the LICENSE, the support URL, the name, the icon's design.
- **No privacy manifest** is needed: the app uses none of Apple's required-reason APIs — no `UserDefaults`, no file timestamps, no boot time, no disk space (checked in v1.4).

### 6.26 Clearer, not louder (D50, v1.5)
"Should make the progression button clearer, currently hidden, but don't make the button too obvious." and "Copy prompt button should be a bit clearer. Maybe a short explanation of the mechanism." Two controls the owner could not find, and one mechanism the app never explained.

- **The sentences are Core** (`PromptText`): the step beside Copy prompt, the footer under the chatbot section, the line under the Progression row, and the name of Home's link. The views that show them are pinned to them (Z1), so a rewording is one edit and a rename cannot leave a screen behind.
- **Copy prompt**, in Add plan (§4.4) and in Progression (§4.3), is the accent-filled small button its step deserves. The step's own text explains the mechanism once; the section's footer says the app never talks to the chatbot itself. No new screen.
- **The Progression row** stays a row — no badge, no button — with a second line saying what it is and the accent chevron. Since v1.7 (D67, §6.42) it is History's, in the block with Metrics and Find an exercise, for the active plan; until then it was Plan detail's. **Today's ···** lists **Plan a progression** (`HomeStart.offersProgression`, from D64's `Gates.planProgression`) only while the plan has no progression, the card is not a running workout, and every exercise on the card's day has a logged session (`ExerciseHistory.last`) — the same history the prompt would send. It goes away the moment a progression is attached, and never appears for a plan with nothing to plan from. That is the whole of "not too obvious". *(v1.5–v1.6: a link in Home's footnote row beside Preview and Another day; v1.7's D61 put the card's alternatives in one ···, §4.1.)*

### 6.27 The effort target (D51, v1.5)
"Also should add an effort target feature in the plan, showing how many reps/seconds to be away from failure." PLAN_FORMAT §5 kept RPE and RIR out of the format on purpose — "put them in notes" — and the owner has now asked for exactly this one, because it changes how a set is done rather than describing it.

- **The field**: `inReserve`, a whole number 0–20, at exercise or set level with the usual exercise-level default; `rir` accepted as an alias. It means *reps* in reserve on a rep set and *seconds* in reserve on a hold, which is why there is one field and not two. Anything else → `E_IN_RESERVE_INVALID`, with a sentence. Missing → none, and nothing is shown. `SetTarget.inReserve`, optional in `Persistence.swift`, so every plan and session already written still decodes; the session snapshot carries it (D7), and `Session.target(at:)` resolves it per step (a drop has none).
- **Where it shows**: the workout card's target line, after the numbers you act on, as body text — "6–8 · 80 kg · 2 in reserve" — and in the card's spoken form; `TargetText.summary` in Plan detail and the review says it once for the exercise when every set agrees ("3 × 6–8 · 80 kg · 2 in reserve"), and leaves it to the JSON when sets differ; the exercise edit sheet (D29) gets an **In reserve** field and `PlanEdit.Operation.setInReserve`; the JSON renderer writes it per set, so a JSON edit round-trips it.
- **The prompt** gains one rule — *inReserve: how many reps (or seconds, for holds) short of failure each set should stop, e.g. 2. Omit when I do not say.* — and "RPE" leaves the notes rule. `PROMPT.md` and the pin (M9) follow. The reference implementation, the schema and `generate_fixtures.py` gain the field, with four fixtures (exercise and set level, the alias, on a hold; a word; over 20) and a manifest check, `inReservePerSet`.
- **Advice does not read it** (§6.11): reps in reserve is for the person, not the algorithm. The Progression prompt's history lines carry it ("10,10,8 @ 60 kg · 2 in reserve"), so the chatbot knows the sets were not to failure.

### 6.28 A plan in several pastes (D52, v1.5)
"Main concerns include making the JSON too big. If the JSON is too big, it might be hard for people on free plans to use. Maybe include several different JSON entrances and a master JSON." A six-day plan is 4–5,000 characters of JSON, over what a free chatbot tier writes in one reply. X3's Add day from JSON already accepts one day at a time; this is the flow that starts that way on purpose, and the prompts that ask for it.

- **The outline** (`PlanDrafting.outline`): the plan prompt's shape without exercises — name, units, `defaultRestSeconds`, schedule, `cycle`, and days with names (and weekdays) only — read by the ordinary importer with `allowEmptyDays`, which skips exactly one check, `E_NO_EXERCISES`. Everything else is refused as for a plan: the prompt pasted, not JSON, no days, a cycle naming a day that is not there. A chatbot that writes the whole plan anyway is not refused: its days arrive already filled.
- **A day into its slot** (`PlanDrafting.day`): the fragment is read as generously as any (D43) — a day, a plan holding it (the day named like the slot is taken), a list of exercises — and **the slot names the day**: the outline decided the names and the repeat block refers to them, so a day the chatbot renamed takes the slot's name, and lends its weekday when the fragment has none. It is then checked alone, under the outline's header and without the repeat block (which names days not here yet), through the ordinary import; errors come back with the slot's real path, so the sentence says "Day 3, exercise 1". A refused paste changes nothing.
- **The assembly** (`PlanDrafting.assemble`): the outline's own JSON tree with every slot's day in place of its empty one, rendered with sorted keys and put through the ordinary import once, so the app holds nothing it would refuse. The plan's text is the canonical rendering, as after any edit. Incomplete → `E_DRAFT_INCOMPLETE` with "2 of 4 days still to paste."
- **`PlanDraft`** — the outline's text as pasted, the outline as a plan, one fragment per slot as pasted, the date — lives in `draft.json` (§8.1), written after every paste and removed when the plan is saved or the draft discarded; optional in the decoder's sense (a slot list defaults to empty), set aside when corrupt like any file, not part of the backup (a draft is not data worth carrying), gone with Delete all data. `AppModel.draft`; `startDraft`, `pasteDraftDay`, `assembleDraft`, `saveDraftPlan` (which saves like any plan, name conflicts included, and lets the draft go only when the save went through), `discardDraft`.
- **The prompts** (PROMPT.md §4, §5): the outline prompt asks for the outline only, under the plan prompt's marker so it cannot be pasted back as a plan; the day prompt names the day, restates the outline as a listing (`Prompts.outlineListing`: "Push Pull Legs · kg · rotation / Days: … / Repeat block: …"), shows a four-exercise example, and gives the plan prompt's rules minus the three the outline settled — computed from the same text (`Prompts.dayRules`), so the two cannot drift (Z16). A seven-day outline's day prompt is under 4,000 characters.
- **Where**: Add plan → Create with a chatbot → **Build it day by day** (§4.4), a screen of its own inside the sheet; saving there closes the sheet. The whole-plan prompt stays the default way. Add day from JSON stays where it is, for a plan already saved with one day cut short.

### 6.29 Progression by performance (D53, v1.5)
"The progression should be by performance instead of by calendar. Maybe a legacy calendar increase, but should include the progression steps." v1.3's progression was a list of weeks and the calendar turned the page; a week you missed was a week the plan skipped.

- **A ladder of steps.** `Progression.weeks` is the number of steps (the on-disk and reply name is kept), `ProgressionEntry.weeks` an exercise's steps in order, and each entry has its own `step` (0-based, the one it is on now) and `tries` (workouts at that step without achieving it). `Progression.mode` is `performance` (the default when planning) or `calendar` (v1.3's behaviour, the owner's "legacy" case). All three are optional in `Persistence.swift`: a progression written by v1.3 reads as calendar at step 0.
- **What advances a step** (`ProgressionSteps.achieved`): every main set of the exercise logged; the reps at or above the target — the top of a range, the minimum of an AMRAP — within the one-rep tolerance the advice already uses (§6.11), summed across the exercise; every logged weight at or above the set's; every hold held for its seconds (or an open hold's minimum). The targets judged are the session's own snapshot, which in a step *is* the step.
- **When**: only when the workout completes (`PlanLibrary.completeSession`, next to the rotation's advance). Each exercise the session stamped with the entry's *current* step moves on (`step + 1`, `tries = 0`) or tries again (`tries + 1`). A session started before the step moved, or a substitute (D42) with no entry, changes nothing; editing history later never moves a step.
- **Which step a workout gets** (`Progression.apply(to:on:)`): each entry's own step in performance mode — including a `{}` step, which keeps the plan's own targets but is still counted, because the workout still has to earn it — and the calendar week for all in calendar mode, where a `{}` week touches nothing (v1.3, W33). Each exercise is stamped with its step (`SessionExercise.progressionWeek`); the session's own number is the lowest of its exercises', which is what Home says, and `Session.progressionMode` records which kind it was.
- **Finished** when every entry is past its last step (performance) or the day after the last week (calendar). Today then offers **Plan the next one**, as its message line (§4.1, D61).
- **The words**: "Step 3 of 8" in performance mode, "Week 3 of 8" in calendar mode — on the Progression row, in Today's subtitle, the chip's reason ("Step 3 of 8 of your progression"), the Summary and Session detail ("step 3 of 8"). The Progression screen shows each exercise's ladder with its current step marked (▸) and "Step 3 of 8 · 2 tries" when a step has repeated; the review says "8 steps, each earned".
- **The prompt** (PROMPT.md §3) plans *steps* and carries a cadence sentence by mode: *one step is one workout's targets; I move to the next step only when I hit the current one, so make each step a small, achievable increase* — or *one step is one calendar week, starting the day I save it*. **The reply** (PROGRESSION_FORMAT.md) says `steps`; `weeks` is read as the alias with a cleanup warning. Paths say `steps[…]` and the sentences say "step".
- **Planning**: the screen asks how many steps (4 / 6 / 8 / 12) and how to advance — **When I hit the target** (default) or **Every week** — and the choice is the progression's mode; the reply never sets it.

### 6.30 Goals (D54, v1.5)
"Goals or milestones — also be a feature." A goal per exercise: a target you name — a weight for so many reps, a hold of so long, or a number of reps — with an optional date.

- **`Goal`** (`Core/Goals.swift`): the exercise (matched by §6.9), its units (sessions in the other unit never count, D10), the target, an optional date (said, never enforced), and — once reached — the date and the workout that did it. Kept in `goals.json` (§8.1), all of them rewritten when one changes, and in the backup (§8.5). Independent of any plan: a goal outlives the plan and the progression it was reached under.
- **Progress** (`Goals.progress`): the best logged set that counts, and the fraction of the target. For a weight goal only sets at or above its reps count — a heavier set for fewer reps is not the goal; for a hold the longest; for reps the most.
- **Reached**: when a workout completes (`PlanLibrary.completeSession`, beside the rotation's advance and the progression's steps), every goal it is the first to meet is marked with that workout. Reached stays reached; a later workout is not credited. The Summary says "Goal reached: …" for that workout (§4.9).
- **Where**: History's Goals section (§4.10) and the exercise's own screen. One sheet sets one: the exercise, spelt as in history (suggestions from history and the plans), the kind, the numbers, the date.
- **The chatbot knows**: the progression prompt (PROMPT.md §3, `{{goals}}`) carries the plan's unreached goals in the plan's units as a MY GOALS block, so the steps it plans climb towards them. The app never sets weights from goals itself: the chatbot plans, the app runs (D12).

### 6.31 Nothing untrue (D55, v1.6)
The 2026-09-09 usability audit (`docs/UX_REVIEW_2026-09-09.md`) walked v1.5 as a stranger and found five sentences the app volunteered that the person could contradict. Every sentence the app offers unasked must be one the person could not. The five, each a Core rule with a unit test (U1–U6):

- **A missed workout is one the plan expected** (§6.12): after the plan's import day and after its anchor; a plan with nothing completed has missed nothing.
- **"Nothing logged" outranks "First time"** (§4.9): a comparison is only a first time when something happened.
- **A calendar cell tells the plan's days apart** (§6.12, D38): labels are unique within the plan.
- **The suggestion chip never contradicts the fields** (§6.11): "do that again" is what was done — last time's reps at last time's weight, never the plan's reps at last time's weight — and a chip that says exactly what the fields already show is not drawn. In practice the chip is now advice (§6.11) or a progression step (D44/D53); "Try 8 reps · The plan's target" under a reps field reading 8 said nothing.
- **A paste that is not JSON gets the right sentence** (§4.4): a plan in words is told to send it to a chatbot, not that a reply looks cut off.

And two things that were simply wrong: the overview repeated each exercise's note on every set row (§4.8), and About said 1.4 for a repository tagged v1.5.

### 6.32 Nothing unreachable (D56, v1.6)
Six places the audit found where the way forward, or the way out, was hidden or under something — mostly for the great-grandparent, who does not guess.

- **Every confirmation shows its way out** (§4.0): Finish workout, Discard workout, Delete plan, Delete workout, Discard draft and Remove progression are presented from a ··· menu, and a `confirmationDialog` presented from a menu anchor draws as a popover on iOS 26 that omits the cancel-role button. All six are alerts with two named buttons. The list swipes keep their dialogs, which present as sheets with a Cancel.
- **Nothing sits on Log set** (§4.5): the system keyboard toolbar goes; while a field is focused the status strip's trailing slot holds Done, and the primary button commits what is typed.
- **An empty bottom action draws nothing**: `bottomAction(if:)` adds the inset only when there is a button. The padded, bar-backed inset used to be drawn around empty content, a small white rectangle at the bottom of Add plan, Build it day by day and Progression.
- **The empty weight field looks like a field** (§4.5): a placeholder and an outline while it is empty.
- **Finish is not red** (§4.0): it saves. Discard and Delete are.
- **At accessibility text sizes the inputs come first** (§4.5): the set list shows the current row, the strip drops its next-set line.
- **The stage is said once** (§4.5): `WorkoutScreenModel.progressLine` is nil while working, when the stage title already reads "Exercise 1 of 5 · Set 1 of 4".

### 6.33 The first five minutes (D57, v1.6)
The path a stranger takes, made to ask for nothing it has not explained. The audit's fresh install met, in order: a picker with no default, a unit chosen silently, a permission alert over a five-minute warm-up countdown with a button reading Log set before anything had been done, an empty field with no hint it was one, a summary that said "First time" about exercises never touched, and a Home that spoke schedule.

- **The warm-up is off until you turn it on** (§6.14): `Settings()` has no warm-up; an old file keeps its five minutes.
- **During a warm-up the button starts the set** (§4.5): **Start first set** ends the warm-up; Log set appears once the set is under way.
- **Notifications are asked for when they are about to matter** (§5.3): the first Log set or Start timer, awaited so the first rest's alert is scheduled after the answer, with the strip already counting (D48).
- **The first empty weight explains itself** (§4.5): `InputDefaults.weightHint` under the field, gone once it has a value; the built-in plans' first notes no longer carry the sentence.
- **The unit is asked, not assumed** (§4.4): `ImportResult.unitsStated`; the review's kg / lb control when it is false.
- **The picker recommends** (§4.4): **Start here** on Full Body while History is empty; the sentence beneath names Add plan's Copy prompt.
- **Today leads with the workout on every day** (§4.1; Home until v1.7): the day's name as the headline, **Start Lower**, "Planned for Thu · …" as the subtitle.
- **The Summary says what happens next** (§4.9): `SummaryText.next`.

### 6.34 Hierarchy (D59, v1.6)
Where the eye lands, and what looks tappable. The audit's great-grandparent tapped headers that were blue and missed links that were small; the coach asked for presets and a search they could see.

- **Today** (§4.1; Home until v1.7): Start in the bottom slot, like every primary button; headers in ink; planned days on the grid — History's since v1.7 (D63) — as a label, not a box. *(v1.6: also "the small actions as bordered buttons that wrap"; v1.7's D61 moved them into the ···.)*
- **The workout** (§4.5, §4.6): Undo on the logged row; the idle strip names what the button will start; Plan detail's Start is a button.
- **Plans** (§4.3, §4.4): "kg · repeats every 7 days"; chips that wrap; an Add exercise row per day; **Use this plan** for "Set as current plan" and "Set as active"; the plan in use marked with a check in the list.
- **History** (§4.10): labelled rows; a Find an exercise row.
- **Settings** (§4.11, §8.6): duration presets; sentences without "prompt", "imports" or "Xcode"; the goal sheet says the app never nags.

### 6.35 An activity outlives the app (D60, v1.6)
"After starting a workout the popup in the Dynamic Island and on the Lock Screen never goes away — I had to uninstall the app." Found on the phone, invisible to the simulator suite, and the first defect in this app that the user could not clear at all.

A Live Activity is owned by the system, not by the app: it stays on screen when the app is terminated — swiped away, stopped from Xcode, or reclaimed while the phone sits in a pocket through a long rest — which is the entire point of one. `SystemActivityPresenter` held the `Activity` handle in a stored property, so the process that came back afterwards owned nothing:

- `end()` returned early on a `nil` handle, so nothing the app could do would take the activity off the screen. It sat there until ActivityKit's own ceiling hours later, or until the app was deleted.
- `show()` requested a **second** activity, because a `nil` handle also means "none is running" — so a resumed workout could stack activities rather than continue one.
- The launch never asked at all: `refreshActivity` returns when the state has not changed, and on a fresh process with no workout the state is `nil` and the remembered state is `nil`.

**The rule: the system's list is the only truth.** `Activity.activities` survives the launch; a stored handle does not. So `SystemActivityPresenter` keeps no state of its own:

- `show` adopts whatever is already on screen (`.active` or `.stale`) and updates it, ending any duplicate; it requests a new activity only when the system has none.
- `end` ends **every** activity of the type, not merely one this process started.
- **Every launch reconciles**, `AppModel.load` → `refreshActivity(force: true)`: a workout still in progress adopts its activity, and anything left over from a run that was killed is ended. `force` exists because `nil == nil` is exactly the case that must not be skipped.
- It runs after `loaded`, so D48 still holds — the launch paints before it tells the system anything.

The seam is unchanged: `ActivityPresenting` still has only `show` and `end`, so the reconciliation is testable with the recorder, and what only a phone can answer is one device row (U33).

### 6.36 Plain words (D58, v1.6)
The 2026-09-09 audit's largest finding was not a defect. "5 (4–6) · 100 kg · last 10 @ 100" is correct, dense and exactly what a coach reads at a glance — and it was the single biggest reason the audit's other two readers, a great-grandparent and a five-year-old, could not read the screen at all. Two readings went to the owner; **Reading B** was chosen: the app speaks plainly by default, and the notation becomes a setting.

`Wording` (`.plain` / `.compact`) is chosen in one place — `Settings.compactNotation`, off on a fresh install and absent from any file written before v1.6, which reads as off. `WorkoutScreen.model(settings:)` passes it down; no view decides for itself.

| | Compact (v1.5, and the switch) | Plain (the default) |
|---|---|---|
| A target | `4–6 · 100 kg` | `Aim 4–6 reps · 100 kg` |
| A fixed count in a range | `5 (4–6) · 100 kg` | `Aim 4–6 reps · 100 kg` — the range is what is asked; the prefill puts 5 in the field |
| Timed | `45 s`, `30+ s` | `For 45 seconds`, `For at least 30 seconds` |
| AMRAP | `AMRAP`, `10+` | `As many reps as you can`, `Aim at least 10 reps` |
| An exercise | `3 × 8–12 · 60 kg` | `3 sets of 8–12 reps · 60 kg` |
| Climbing weights | `24 / 26 / 28 kg` | `24, then 26, then 28 kg` |
| A superset member | `A · Set 2 of 4` | `Set 2 of 4 · paired with Tricep Pushdown` |
| A superset round | `A · round 2 of 3 · Incline Press` | `Round 2 of 3 · Incline Press` |
| A drop | `drop 1 of 2`; `· 2 drops` | `lighter set 1 of 2`; `· then lighter, as many as you can` |
| A logged set | `10 @ 80` | `10 × 80` |
| The row's second line | `last 10 @ 100` | `Last time 10 × 100 kg`, on its own line |
| An effort target | `2 in reserve` | `stop 2 short of failure` |

- **A row that names its own exercise does not also carry the pairing** — in a superset the rows are already distinguishable, and either form would only repeat what the row beside it says (`StepCard.rowLabel`, `group: false`).
- **VoiceOver speaks the plain forms** whatever the switch says (§9): it was already written out rather than read off the screen, and "lighter set" is what it now says for a drop.
- **Two things keep the compact forms whatever the setting**, because no person reads them as a sentence: the chatbot prompt (§7 — PROMPT.md pins it, and a machine reads it), and the progression ladder's columns (`w1 8 × 80 kg · w2 …`, which is a specification of what the plan will do). The CSV export has no grammar to choose: every value is its own column, so nothing there was ever a sentence.

*(The other reading, kept for the record: leave the notation and explain each form once per install the first time it appears. It was the smaller change and would have left the numbers exactly as the owner reads them, but it teaches a notation rather than removing the need for one, and it says nothing on the four-hundredth day.)*

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
- The day the schedule expected and did not get is **said**, on Today — "Push was due Monday", with **Do it now** and **Dismiss** — rather than resolved behind your back. Only the most recent one, and only within a week: a plan you came back to after a fortnight is a fresh start, not a missed Tuesday. **v1.6 (D55)**: and only a day the plan actually expected — after its import day, and after its anchor, the day of its most recent completed workout. A plan with nothing completed has missed nothing. v1.5 anchored such a plan to today and projected the pattern backwards over the week before the plan existed ("Full Body B was due Sunday", three minutes after a fresh install), and a completion re-anchored the pattern over days already lived through ("Pull was due Tuesday" after a day run out of order).

Today's card and the grid in History's calendar (Home's until v1.7, D63) read the same function (`PlanSchedule.next(_:today:)`), so they cannot disagree. In v1.1 they were computed two different ways, which is the other half of why the calendar felt clunky.

**D38 (v1.2): what a cell says.** v1.1 drew every day as the same 5 pt dot — filled for done, outlined for planned, grey for rest — so a month of training looked like a month of anything else, and the shape of a week could not be read off the grid ("the spacing … is not perfectly clear"). A cell now carries the day's short name under its number, a finished day is filled in the reserved green, a planned day is outlined in the accent, and a rest day is a dash: a visible gap rather than another kind of dot. **v1.6 (D55)**: the short name is chosen *within the plan* — the first word when it is the only day of the plan that starts with it, else the initials of every word, else the day's number — so Full Body A and Full Body B read "FBA" and "FBB" rather than both "Full…", and Upper A / Lower B read "UA" / "LB". The spoken cell always says the whole name. Each cell reads as one VoiceOver sentence ("Monday 7 September. Planned: Push"). **v1.7 (D65, §6.41)**: a finished day is filled, and a planned day named, in its day's colour; the reserved green and the accent gave way to it.

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
- Weekday plans: Today shows the day whose weekday equals today (local calendar); else "Rest day" and the next weekday that has one. `cyclePosition` is unused.
- Starting any Day from Plan detail or the calendar is always allowed regardless of the cycle. If a session is in progress it triggers the D17 popup; "Finish X and start Y" finishes X exactly like Finish (pending → skipped, advice, cycle advance) then starts Y; "Discard X and start Y" discards X.
- Two sessions on the same calendar day are allowed. A session's `date` for grouping = local calendar date of `startedAt`.

### 6.9 Exercise name matching
`normalized(name) = name.trimmingCharacters(whitespacesAndNewlines).lowercased()` then collapse runs of whitespace to one space. No diacritic folding. Used for history lookup, plan-name conflicts, day lookup for the pointer, and group tags (uppercased instead of lowercased).

### 6.10 Input rules
- Reps field: digits only, max 3 characters, 0 allowed (a failed set logs as 0, no confirmation), empty disables Log set.
- Weight field: digits plus one decimal separator; accept both `.` and `,`; one decimal place kept; 0 allowed; empty allowed (logs no weight); max 10000.
- Seconds field (timed sets): digits, max 5 characters, 0 allowed.
- − / + buttons never go below 0. Long-press repeats.

### 6.37 Today is one card (D61, v1.7)
The owner's note after living with v1.6 — *"sensory overload… less choices… more forcing… feels like a settings menu"* — counted from the code (`docs/ITERATION_8_PLAN.md`): Home on an ordinary workout day had 16 to 19 tappable things before any notice appeared (Start; Preview, Another day, Plan a progression; Week/Month and ‹ ›; seven cells and Start this; four tabs), two competing headlines and five type sizes. §4.1 still opened "three things, top to bottom, nothing else"; each of the three had grown by decisions taken one at a time (D37, D44, D50, D57, D59), and the sum was a dashboard. The plan names what the note names — one primary action per screen (§4.0's first rule, on the books since v1.1), progressive disclosure, Hick's law, a control that appears when it first has something to do — and draws one line it does not cross: **deferred, never unreachable** (D56 stands). Everything Home offered in v1.6, Today still offers: one tap later, in one place, and only when it applies.

The app decides the **order**, never the **availability**:

- **Today's workout is the screen.** The same five zones on every day of the plan (§4.1); nothing moves between visits; the calendar and the week's line leave for History (D63).
- **Everything else is one tap away, in one place.** The exercise block is the preview; Another day, Change plan, Plan a progression and, mid-workout, Discard are the ···. `HomeStart.alternatives` lists the items in order — Another day only when the plan has another day, Plan a progression only while D50 offers it, Discard last and only while a session is open, nothing at all with no plan — and the view draws the list.
- **One message at a time.** `HomeStart.message` is chosen by priority — the missed workout (the only one with a date on it) > the progression that has run its course > notifications off — and Dismiss on the first lets the next speak. Two never share the screen. The view's per-run dismissal (D37) is an input to Core (`missedDismissed`), as is the declined permission (`notificationsOff`, D57), so the choice is a unit test.
- **The empty card makes two offers, not three**: the built-in picker in the button (**Choose a plan**, the intro's own words, with the chatbot and paste routes one tap back inside the sheet, D57) and the practice workout in a quiet link.
- **In progress, nothing leaves.** The block shows the session's exercises and opens its plan; the subtitle counts the session's steps ("5 of 16 sets"); Resume still goes to the session.

Home became **Today** in the tab bar. `RootView.Tab.today` replaces `.home` (`-uiScreen today`; `home` still resolves for older scripts); how many tabs there are is D62's (§6.38 — two, and the list moved to Core as `AppTab`).

### 6.38 Two tabs (D62, v1.7)
The tab bar read as a settings menu from the first screen because two of its four tabs were not daily destinations: Plans is visited when a plan changes, every few weeks, and Settings a handful of times in the app's life, yet both sat as peers of the workout. Three readings were put to the owner on 2026-09-13 (`docs/ITERATION_8_PLAN.md`, T2): two tabs, Today · History (A); three, keeping Plans because the chatbot round trip is the app's premise (B); or none, with History, Plans and Settings behind Today's ··· (C — which fails D56, because a menu is not a visible way out, and History is the second screen people use). **A was chosen.**

- **The tab bar says what the app is**: a workout to do and a record of the ones done. `AppTab` (`Core/Tabs.swift`) is the list, in order; `RootView` draws `AppTab.allCases` and nothing else, and a test holds the list to §4.0's (T7).
- **Plans is Today's ··· → Change plan**, pushed onto Today's stack; a plan's detail pushes onto the same stack, and back returns to Today. With no plan there is no ··· (D61) and no list to reach — it would offer only Add plan, which the empty card's **Choose a plan** opens.
- **Settings is the gear**, top-left, on Today and on History — one control in one place on both (P1) — and it is pushed, not presented, so what Settings presents, and the introduction that Delete all data makes due again, present over the tabs as they did when Settings was a tab. The gear is there with no plan too: Import backup is how a new phone gets its data back.
- **Deferred, never unreachable** (§6.37): Add plan is one tap further from launch than in v1.6 (··· → Change plan → Add plan). The owner judged that the coach notices once and the stranger never does, because the introduction and the empty Today lead to Add plan by the hand.

The screenshot hook still takes `-uiScreen plans` and `-uiScreen settings`: both land on Today, which pushes the screen.

### 6.39 The calendar lives in History (D63, v1.7)
The calendar was always the record's: it shows what happened and what the plan expects, and the one thing it did for *today* — **Start this** on today's line — Today does (§6.37). It moved, its drawing unchanged, to the top of History (§4.10), with the week's line beneath it.

- **The strip is History's first zone on every visit**, with Month a tap away. With no workouts it still shows the plan's week — the projection is worth seeing on day one — and "No workouts yet" and **Import from another app** (D45) sit under it.
- **The tapped-day line is text unless it opens something.** `CalendarText.line` returns the line and the finished sessions it opens — none for a planned day, today's included, or a rest day — so "no Start this" is a unit test (T11). It says "planned", not "projected".
- **A finished day opens pushed onto History's stack**, like its row, with the chooser first when the day holds two; over Home it opened in a sheet.
- **The week's line** is `HomeActivity.line`, unchanged (O66, re-homed as T10); "this week" is still the calendar week the strip shows.

Nothing about the projection changed (§6.12): the grid, Today's subtitle and the Summary's "Next: …" read the same schedule as before.

### 6.40 Controls are earned (D64, v1.7)
The rule behind §6.37, made a table (`docs/ITERATION_8_PLAN.md`, T4, which proposed it as §6.39 before T3's calendar took that number). A control appears the first time it has something to do, and once shown it stays. **No control is removed from the app by this, only delayed** — §6.37's line, deferred and never unreachable. The one control that leaves again is D50's, when a progression is attached.

| Control | Appears when | Core |
|---|---|---|
| **Month** (History's calendar) | a session exists that is older than the current week — the calendar week the strip shows | `Gates.month` |
| **Metrics**, **Find an exercise** and **Progression** (History) | at least one session — and, for Progression, an active plan, whose progression it opens | `Gates.metricsAndFind` |
| **Goals** section (History) | at least one session | `Gates.goals` |
| **Another day** (Today's ···) | the plan has more than one day — or any day, when nothing is scheduled and the chooser is the only way to a workout | `Gates.anotherDay` |
| **Change plan** (Today's ···) | at least one plan | `Gates.changePlan` |
| **Plan a progression** (Today's ···) | as D50: every exercise on the day has a session, and no progression is attached | `Gates.planProgression` |
| The notifications-off line (Today) | as D57: after the first **Log set** of the run has asked for the permission, and the answer was no | `Gates.notificationsOff` |

- **Settings is not gated**: a switch someone goes looking for must be there (D56).
- **A session is a finished one.** A workout still running earns nothing; History does not list it.
- **Nothing is stored.** Each gate is a function of the sessions, the plans and the date (`Core/Gates.swift`), and those only grow with time and use, so "once shown it stays" needs no flag and no field in `Settings` — the on-disk contract is untouched. Deleting what earned a control takes it back: Delete all data returns the app to its first day.
- **Week stays while the month grid is open**, so the grid can always be closed, even when the history that earned Month has been deleted under it.
- **A control that is not there from the first launch adds its row here first**, and its function to `Gates`; the views ask `Gates` rather than counting for themselves, and a test holds the table and the type together (T21).

### 6.41 A colour per day (D65, v1.7)
Parked from iteration 7 and chosen with v1.7's plan (`docs/ITERATION_8_PLAN.md`, T5) — the one addition in a release of subtractions. History was a column of identical grey rows, and a five-year-old reads a colour before a word. **Colour says which day; the accent says tappable** (§4.0).

- **A day's colour is its place in the plan's day list**: the first day green, then orange, purple, pink, teal and indigo, and the seventh green again (`DayColour.index(dayIndex:)`, `Core/DayColour.swift`). Six system colours, so they follow dark mode; none is the accent (tappable, D59), red (destructive) or yellow (a warning), and a test holds the palette to that (T23).
- **Derived, never stored.** Nothing joins `Plan`, `Session` or `Settings`, so no file on the phone changes shape; reordering a plan's days recolours them, which is the price of leaving the on-disk contract alone. A workout's colour is its day's in its plan as the plan is now, found by the plan's id and the day's name, as the calendar finds its label (`DayColour.of(session:plans:)`); a workout whose plan is gone, or whose day was renamed, has none.
- **Exactly four places**, each saying *which day* and none saying *tap here*:
  1. **Today**: a small filled square before the day's name — never the name itself, which is ink (§4.1).
  2. **The calendar**: a finished day is filled, and a planned day named, in its day's colour, where the reserved green and the accent were (§4.10, D38). A day with two workouts takes the first's, the one its label names; a finished day with no colour is grey.
  3. **History**: the same square leading each workout's row, grey for a workout with no colour, so the column stays a column (§4.10).
  4. **The workout header**: the square leads the stage line — the header names no day, since D34 made it the stage — and the Lock Screen activity carries it too, before its title there and in the expanded Island; the compact Island, which has room for a colour and nothing else (D41), draws its figure in it while working, and a break keeps the accent (§4.5, §6.17).
- **Nowhere else**: not Start, not the tab bar, not a background, not the Summary. Core decides the colour — `HomeStart.dayColour`, `DayEntry.dayColour(plans:)`, `DayColour.of(session:plans:)`, `WorkoutActivityState.dayColour` — and the view layer owns the mapping to a `Color` in one file, `DaySquare.swift`, compiled into the app and the widget extension alike (T23 reads it).
- **Green is also the colour reserved for "this happened"** (§4.0, v1.1) — a logged set, a record, a goal reached. The palette keeps it for the first day, as the plan chose: in the calendar the fill now says *happened* and the colour says *which day*, so a plan's first day reads as it did in v1.6.

### 6.42 Before v1.7 shipped: the owner's review (D66–D68)
The owner walked v1.7 on 2026-09-13, before it went to `main`, and asked for the release's own rule once more — one way to a thing, in the place it belongs.

- **One way to find an exercise (D66).** History's search field is gone. It and the **Find an exercise** row (D59) led to the same exercises, and the field was the screen's top control, above the calendar it was meant to sit under. The row stays, under Metrics, from the first workout (§6.40); `ExerciseText.search` still orders its list, most recently trained first (J28). A pin holds `HistoryView` to no search field (T27).
- **Progression lives in History (D67).** The Progression row (D44, D50) left Plan detail for History's block, under Metrics and Find an exercise: a progression is planned from what was lifted, which is History's, while Plan detail is the plan's contents. The row is unchanged — its second line, its step or "Plan it", the accent chevron — and opens the same screen as a sheet, for the **active plan**, the plan Today runs. So it needs an active plan as well as the block's first workout (§6.40); another plan's progression is planned by making it the active plan first (Plan detail's ··· → **Use this plan**). Before the first workout there is no Progression row anywhere — nothing lifted to plan from, which is also when D50's offer stays away. Today's **Plan the next one** opens the Progression screen itself, since Plan detail no longer leads there; Today's ··· keeps **Plan a progression** while D50 offers it. Pins hold the row to `HistoryView` and out of `PlanDetailView` (T28; Z3's and Y13's pins moved with it).

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
struct SetTarget: Codable { var work: WorkTarget; var weight: Double?; var restSeconds: Int; var warningBeepSeconds: Int?; var drops: [DropTarget]; var inReserve: Int? }   // rest and warning offset already resolved; warning only on fixed durations; inReserve is v1.5's effort target (D51), optional on disk
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
  draft.json               { "fileVersion": 1, ...PlanDraft }       present only while a plan is built day by day (D52, v1.5)
  goals.json               { "fileVersion": 1, "goals": [Goal] }      present once a goal is set (D54, v1.5)
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
`{ "exportedAt", "appVersion", "fileVersion": 1, "settings", "plans", "sessions": [...], "activePlanId", "goals" }` written to a temp file and offered via ShareLink. `activePlanId` was added in v1.1 and is optional, so a v1 backup still restores — it just leaves the first plan active. `goals` (D54, v1.5) is optional too: Replace all takes the backup's, Merge adds the ones not already here by id, and a backup without any restores with none.

**Restoring** (D31, v1.1): Settings → Import backup reads the file and reports its date, its app version, how many plans and workouts it holds, and how many of each a Merge would actually add. Nothing is written until **Merge** or **Replace all** is chosen. Merge adds only ids not already on disk and leaves the current settings, the active plan and anything edited since the backup untouched; Replace all empties the store first and takes the backup's settings and active plan. A running workout is discarded before either. A file that isn't a backup, or whose `fileVersion` is newer than this app's, is refused with a message before anything is written.

**History as CSV** (D45, v1.3, §6.20): the backup is the app-to-app format; CSV is the app-to-*other*-app one. `HistoryCSV.render` writes one row per logged set in the column order Strong writes and Hevy reads, plus the unit last; `HistoryCSV.parse` reads that, a Strong export and a Hevy export by header name. Import is read-then-describe-then-Import, like a backup, and a workout already in History is never added twice.

### 8.6 Data survival on the free-account 7-day reinstall
Re-running from Xcode over the existing install keeps the container. Deleting the app deletes everything. Settings says so next to Export — since v1.6 (D59) without the word Xcode, which a stranger does not have.

## 9. Non-functional
- Launch to Today under 1 s with 1000 sessions on disk.
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

# Device checklist (M8, and v1.1's R6)

Every `manual` case from `TEST_CASES.md`, to run on the owner's iPhone. The simulator cannot do
notifications while locked, real haptics, the silent switch, or the free-account expiry, which is why
these are here rather than automated.

Everything else — 287 automated tests plus the simulator screen checks — is green; see
`BUILD_STATUS.md`. **v1.3** added the rows W3, W12, W21, W30 and W40 at the end; none has been run yet.
**v1.4** added Y3, Y11, Y16 and Y19 after them, and **v1.5** Z4, Z10, Z17, Z25 and Z31. Y19 needs a TestFlight build, which needs the paid
Developer Program (`APP_STORE.md` §1); with it, the free-account expiry (O24) is n/a, and every
other row is best run against the TestFlight build, which is the Release binary reviewers get.

**What the phone has actually seen.** On 2026-09-08 the owner installed v1.3 from Xcode and
reported that everything worked, without recording rows here; the one thing raised was a
second's lag on Start, which v1.4's D48 fixed. The rows below are therefore still unticked: the
evidence so far is the owner's word for v1.3 as a whole, not this table, and v1.4 and v1.5 have
not been on a phone at all.

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
6. Choose a built-in plan from Home (v1.4), or paste a real one, before starting the timer cases.

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

## v1.4 rows (new or changed in Y1–Y4)

| Case | What to do | Expected | Result | Notes |
|---|---|---|---|---|
| **Y3** | Home → **Start** | The workout screen is up at once — before the notification prompt (first time) and before the Island appears; nothing waits on either. Log a set: the card moves on before the rest notification is scheduled |  |  |
| **Y11** | Home → **Choose a built-in plan** → At Home → Save plan → **Start At Home A** | The picker's rows show days, minutes and equipment; the review opens on the paragraph with the days beneath; Home names At Home A; the first card asks for reps only (no weight field); the day takes about the minutes the picker said |  |  |
| **Y16** | Delete the app, install, launch; then Settings → About → **How the app works** | The intro covers the tabs on the clean install; four pages; **Choose a plan** lands on the built-in picker; after Cancel, Home is the empty card and the intro does not return on relaunch; the Settings row reopens it, ending on **Done** |  |  |
| **Y19** | Install from TestFlight | The icon is the barbell on blue; Settings → About reads 1.4 (1); the rest of this checklist is run against this build |  |  |

## v1.5 rows (new or changed in Z1–Z5)

| Case | What to do | Expected | Result | Notes |
|---|---|---|---|---|
| **Z4** | Add plan, then Plans → a plan | Copy prompt is the filled accent button beside the sentence that explains it; the footer under the steps says the app never talks to the chatbot; the Progression row has its line and an accent chevron; Home shows **Plan a progression** only on a day whose every exercise has history, and not once one is attached |  |  |
| **Z10** | Paste a plan with `"inReserve": 2` on an exercise (or add it in the exercise's edit sheet), then start it | The review and Plan detail read "… · 2 in reserve" once for the exercise; the card reads "6–8 · 80 kg · 2 in reserve" under the target; VoiceOver says it |  |  |
| **Z17** | Add plan → Create with a chatbot → **Build it day by day**, with a free ChatGPT tab | Copy outline prompt; paste the reply into Paste outline — one slot per day; Copy day prompt per slot, paste each reply; a slot refused says which day and why; leave the app and come back to "Continue · 2 of 3 days pasted"; Review plan, Save plan; the plan is on Home and the draft is gone |  |  |
| **Z25** | Plan → Progression → **When I hit the target**, paste the reply, Save; run a day hitting one exercise and missing another | The chip reads "Step 1 of N of your progression"; after Finish, the Progression screen shows the hit exercise at step 2 with ▸ moved and the other at "Step 1 of N · 1 try"; Home's subtitle reads "step 1 of N" until every exercise of the day moves |  |  |
| **Z31** | History → **Set a goal** for an exercise you do (a weight you can lift for the reps), then run a workout that meets it | The Goals section shows the line and the bar; the Summary says "Goal reached: …" in green; the goal reads "reached" with the date; Plan → Progression → Copy prompt has a MY GOALS block |  |  |

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

For the v1.4 rows: a `fail` on Y3 points at `RootView`'s `onChange(of: model.startedWorkouts)`, or
at a view that still sets the cover after awaiting `startDay` (D48); on Y11 at `BuiltInPlansView`
or `AppModel.loadBuiltInPlan`; on Y16 at `AppModel.introDue` and the cover's binding, or at
`Settings.introSeen` in `Persistence.swift`; on Y19 at signing, or at `tools/check_release.py`.

For the v1.5 rows: a `fail` on Z4 points at `PromptText` and the views pinned to it; on Z10 at
`PlanImport`'s `reserve` and `TargetText`; on Z17 at `PlanDrafting` or `DraftPlanView`; on Z25 at
`ProgressionSteps.achieved` / `advance` and `PlanLibrary.completeSession`; on Z31 at
`Goals.markReached` and `GoalsSection`.

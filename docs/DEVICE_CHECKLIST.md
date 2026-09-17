# Device checklist (M8, and v1.1's R6)

Every `manual` case from `TEST_CASES.md`, to run on the owner's iPhone. The simulator cannot do
notifications while locked, real haptics, the silent switch, or the free-account expiry, which is why
these are here rather than automated.

Everything else — 438 automated tests plus the simulator screen checks — is green; see
`BUILD_STATUS.md`. **v1.3** added the rows W3, W12, W21, W30 and W40 at the end; none has been run yet.
**v1.4** added Y3, Y11, Y16 and Y19 after them, **v1.5** Z4, Z10, Z17, Z25 and Z31, **v1.6** U9, U10, U13, U22, U23, U28, U33 and U37, **v1.7** T5, T9, T13, T24 and T29, **v1.8** TS5, TS11, TS12 and TS16, **v1.9** TQ18, TQ19, TQ20, TQ24, TQ29, TQ33, TQ38 and TQ39, **v1.10** TP7, TP16, TP23, TP29, TP35 and TP42, and **v1.11** TN15, TN16, TN22, TN31 and TN39. Y19 needs a TestFlight build, which needs the paid
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
6. **Choose a plan** from Today (v1.4, v1.7), or paste a real one, before starting the timer cases.

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
| **Z4** | Add plan, then Plans → a plan | Copy prompt is the filled accent button beside the sentence that explains it; the footer under the steps says the app never talks to the chatbot; the Progression row has its line and an accent chevron; Home shows **Plan a progression** only on a day whose every exercise has history, and not once one is attached (since v1.9, D75, not on Today at all: History's Progression row is the way) |  |  |
| **Z10** | Paste a plan with `"inReserve": 2` on an exercise (or add it in the exercise's edit sheet), then start it | The review and Plan detail read "… · 2 in reserve" once for the exercise; the card reads "6–8 · 80 kg · 2 in reserve" under the target; VoiceOver says it |  |  |
| **Z17** | Add plan → Create with a chatbot → **Build it day by day**, with a free ChatGPT tab | Copy outline prompt; paste the reply into Paste outline — one slot per day; Copy day prompt per slot, paste each reply; a slot refused says which day and why; leave the app and come back to "Continue · 2 of 3 days pasted"; Review plan, Save plan; the plan is on Home and the draft is gone |  |  |
| **Z25** | Plan → Progression → **When I hit the target**, paste the reply, Save; run a day hitting one exercise and missing another | The chip reads "Step 1 of N of your progression"; after Finish, the Progression screen shows the hit exercise at step 2 with ▸ moved and the other at "Step 1 of N · 1 try"; Home's subtitle reads "step 1 of N" until every exercise of the day moves |  |  |
| **Z31** | *Removed in v1.7 (D68): goals went — skip this row.* History → **Set a goal** for an exercise you do (a weight you can lift for the reps), then run a workout that meets it | The Goals section shows the line and the bar; the Summary says "Goal reached: …" in green; the goal reads "reached" with the date; Plan → Progression → Copy prompt has a MY GOALS block |  |  |

## v1.6 rows (new or changed in U1–U5, U7, U4)

| Case | What to do | Expected | Result | Notes |
|---|---|---|---|---|
| **U9** | In a workout, ··· → Finish workout (with sets left, and again with nothing logged); Plans → a plan → ··· → Delete; History → a workout → ··· → Delete workout | Each is an alert with two named buttons — Finish workout / Keep going, Discard / Keep going, Delete / Cancel — and Finish is not red |  |  |
| **U10** | In a workout, tap the weight field | The keyboard rises with no system toolbar; the strip's trailing slot reads **Done**; nothing sits over Log set; Log set commits what is typed; Done closes the keyboard |  |  |
| **U13** | Settings → Accessibility → Larger Text at the largest size, then a workout | The current set row only, the strip without its next-set and set-time lines, the reps and weight rows and Log set on screen without scrolling; Exercises still lists every set |  |  |
| **U22** | Delete the app, install, and go through the intro to a first workout with Full Body | The picker shows **Start here**; the review asks kg / lb; Home reads "Full Body A" with **Start Full Body A**; Start opens the first card with no warm-up and no permission alert; the empty weight reads *tap to type* with the hint under it; the first Log set raises the permission alert over a counting rest; the Summary ends with "Next: Full Body B, …"; Home never says a day was missed |  |  |
| **U23** | Settings → Warm-up → 5 min, then Start | The card opens in the warm-up with **Start first set**; tapping it shows the first set with **Log set** |  |  |
| **U28** | Log a set, then look at the row and the strip | ↺ beside the logged row's tick undoes it; the strip shows no Undo at the normal text size; before logging, the strip read "Rest … starts when you log" |  |  |
| **U33** | Start a workout, log a set so a rest is counting, then force-quit the app (swipe it away) and reopen it. Then finish the workout. Then force-quit mid-rest again, and this time open the app on a day with no workout | After the reopen: **one** activity on the Lock Screen and in the Island, still counting — not two, and not frozen. After Finish: both clear. After the last step: the leftover activity is gone within a second of the app opening, without deleting the app |  |  |
| **U37** | Settings → Compact notation, off then on, looking at a workout card, Plan detail and a past workout between each | Off: "Aim 8–12 reps · 60 kg", "Last time 10 × 60 kg" on its own line under the current row, "paired with …" on a superset, "3 sets of 8–12 reps" in Plan detail. On: "8–12 · 60 kg", "last 10 @ 60", the A badge, "3 × 8–12". The switch changes every screen, and survives force-quitting the app |  |  |

For the v1.6 rows: a `fail` on U9 points at the `.alert` modifiers in `WorkoutView`, `PlanDetailView`
and `SessionDetailView`; on U10 at `StatusStripView`'s `done` slot and the removed keyboard toolbar;
on U13 at the `isAccessibilitySize` branches in `WorkoutView`; on U22 at `Settings()`'s warm-up,
`SessionRunner.apply`'s permission request, `InputDefaults.weightHint`, `ImportResult.unitsStated`
and `PlanSchedule.missed`; on U23 at `WorkoutScreen.primary(resting:)`; on U28 at
`WorkoutScreenModel.undoStep` and `WorkoutScreen.idleLine`; on U33 at
`SystemActivityPresenter` (it must read `Activity.activities` rather than a stored handle) and
`AppModel.load`'s closing `refreshActivity(force: true)`; on U37 at `Settings.wording` and
whichever screen still calls a text function without passing it.

## v1.7 rows (new or changed in T1–T5 and the owner's review)

| Case | What to do | Expected | Result | Notes |
|---|---|---|---|---|
| **T5** | Settings → Accessibility → Larger Text at the largest size, then Today in each state — a workout day, a rest day, mid-workout, the empty card | The day's name, the subtitle and Start stay on screen without scrolling; the exercise list is what scrolls; the ··· sits top-right on every state that has one, and Discard from it is an alert with **Keep going** |  |  |
| **T9** | With a plan, on Today: tap the ···, then **Change plan**; open a plan, then go back twice. Tap the gear on Today and go back; switch to History and tap its gear. Then delete every plan from the Plans list and look at Today | The tab bar shows **Today** and **History** and nothing else. Plans is two taps from Today and a plan's detail one more; back returns to Today each time. The gear sits top-left in the same place on both tabs and opens Settings with a back button. With no plan, Today still has its gear (Import backup is in Settings) |  |  |
| **T13** | With a plan and a few finished workouts, open History. Tap **Month**, then **Week**. Tap a done day once, then again; go back. Tap today when it is a planned day. Then, on a fresh install with a built-in plan chosen and nothing done, open History | History opens with the week strip and the week's line ("2 workouts this week · …") above Metrics. Month and Week switch the grid. A done day's first tap shows "… · Legs · 52 min ›", its second opens the workout pushed onto History, and back returns to History. Today's planned day shows "… · planned" and no button. The fresh install shows the plan's week — its days named, rest days as dashes — above "No workouts yet" and **Import from another app** |  |  |
| **T24** | With a plan of three or more days and two different days done, look at Today; open History (the strip, then **Month**); start the day Today shows, lock the phone during a rest, then unlock and open the Dynamic Island. Then Settings → Display & Brightness → Dark, and look at each again | The square before the day's name on Today, that day's fill and name in the calendar, the square on its History rows, the square leading the workout header, and the square before the title on the Lock Screen and in the expanded Island are one colour, and the compact Island's figure is that colour while working; every other day has a different colour. Start, the tab bar and the backgrounds have none. In dark mode each is still the same colour as the others, and every calendar label is legible |  |  |
| **T29** | With a plan and one finished workout, open History and look between the calendar and the months; tap **Progression**, then close it. Open the plan from Today's ··· → **Change plan**. If a progression has run its course, tap Today's **Plan the next one** | No search field anywhere on History. One block of **Metrics**, **Find an exercise** and **Progression**; Progression has its second line, "Plan it" or its step, and an accent chevron, and opens the active plan's Progression screen. Plan detail has no Progression row. **Plan the next one** opens the Progression screen, not the plan. No Goals section on History, and no **Set a goal** on an exercise's screen (D68) |  |  |

For the v1.7 rows: a `fail` on T5 points at `HomeView` (`Features/Home/HomeView.swift`) — SPEC §4.1
lets only the exercise list scroll; on T9 at `AppTab` (`Core/Tabs.swift`), `settingsGear` in
`RootView.swift` and Today's `NavigationPath`; on T13 at `Features/History/CalendarView.swift`,
`CalendarText.line` and `Gates.month`; on T24 at `DaySquare.swift`, which both targets compile and
which is the only mapping from a `DayColour` to a `Color`, then at `DayColour.of(session:plans:)`
and `WorkoutActivityState.dayColour` for the Lock Screen and the Island. A `fail` on T29 points at
`HistoryView` (`Features/History/HistoryView.swift`) and, for **Plan the next one**, at `HomeView`'s
message line.

## v1.8 rows (new in S1–S3, written with S4)

| Case | What to do | Expected | Result | Notes |
|---|---|---|---|---|
| **TS5** | Settings → Accessibility → Larger Text at the largest size, then Today on a workout day, and again on a rest day | Workout day: the name, the meta row, the exercise list and Start stay on screen without scrolling, the list is what scrolls, and the set blocks grow with the text. Rest day: the name (**Rest**), the strip and Start stay on screen with nothing clipped; the z's keep their fixed size rather than growing, and **No exercise Today** stays readable and disabled |  |  |
| **TS11** | With the same text size, look at the strip's seven squares beside the clock | The strip stays one row and wraps nothing; each square keeps a tappable width |  |  |
| **TS12** | Tap a day other than today on the strip (for example Pull on a Tuesday), background the app, and return to it; then force-quit the app and reopen it | Backgrounding and returning: the card still shows the tapped day (Pull). After the force-quit: the card shows today, not the tapped day |  |  |
| **TS16** | Look at a rest day's card in light mode, then Settings → Display & Brightness → Dark and look again; turn on VoiceOver and swipe through the card | The z's rise to the right in the accent, and the moon sits where the clock would, legible in both. VoiceOver reads "Rest", then the seven strip squares ("Today, rest", "Tomorrow, Pull", …), then "No exercise Today", dimmed |  |  |

For the v1.8 rows: a `fail` on TS5 points at `HomeView`'s accessibility branches or `HomeStart.rows`'
block sizing; on TS11 or TS12 at `Core/WeekStrip.swift` and the view's `@State shownOffset`, which
must reset on relaunch but not on backgrounding; on TS16 at the rest-day branch of `HomeView` and
its VoiceOver labels.

## v1.9 rows (new in Q2–Q6, written with Q7)

A swap needs a workout finished on a day the plan did not expect it: on Today's strip tap a later
square, **Start** that day, log at least one set and finish. Use a plan that already has a finished
workout — a rotation's first workout anchors it rather than swapping.

| Case | What to do | Expected | Result | Notes |
|---|---|---|---|---|
| **TQ18** | Finish another day's workout today (above) and look at the strip. Then Settings → Accessibility → Motion → **Reduce Motion** on, and look again. Then tap the ringed square and choose an option in its block | Today's square has a dot beneath it in the colour today's own day would have had; the square whose workout was taken is ringed in yellow, and the ring breathes, about 2.4 s a breath. With Reduce Motion on, the ring holds still at full strength. Once answered, the ring is faint and still |  |  |
| **TQ19** | After TQ18: long-press today's square, then tap elsewhere. Long-press the answered, ringed square. Then tap any square quickly | Today's long press raises a callout — the pattern's square and "was *day*" (for example "was Push") — and a tap elsewhere dismisses it. The ringed square's long press shows its day with the block back and the choice checked. A quick tap is still a tap: it shows that day and nothing more |  |  |
| **TQ20** | Settings → Accessibility → Larger Text at the largest size, then tap a ringed square so its question shows | The block keeps every option on screen — the squares wrap rather than leave it, and the block scrolls if it must — while the day's name, the strip and the button in the bottom slot stay put |  |  |
| **TQ24** | On Today, tap the ···. Then Settings → Display & Brightness → Dark, and tap it again | **Change plan** has the plan's cycle beside it as tiny squares in the days' colours, grey for rest, and **Change *day*'s exercises** the shown day's square. Both keep their colours in light and in dark and read as squares at the menu's size |  |  |
| **TQ29** | With two plans — yours active and a second (Plans → **Add plan** → **Choose a built-in plan**; if the new one becomes active, tap your plan's circle and then **Use**) — tap a later square on the strip, ··· → **Change *day*'s exercises**, and pick a day of the second plan. On another square, ··· → Change *day*'s exercises → **Write a day just for *day***, and save the text it opens with. Look in light and in dark, with each square shown and not | The borrowed day's square is outlined in the second plan's colour and the own day's in ink. Beside the filled squares each still reads as a square at the strip's size, shown (larger) and not, and so does the square before the day's name when the card shows that day |  |  |
| **TQ33** | Plans → your plan → tap a day to open it → the menu on its row → **Edit day as JSON**. Change a `"reps"` value to `"lots"` and tap **Replace *day*** (for example **Replace Push**). Then type one character. Repeat at the largest text size and in dark mode | The line with `"reps"` is tinted, with a red bar at its edge; the sentence sits beneath it and pushes the lines below down rather than covering them; the box scrolls to it; typing unmarks it. The same at accessibility XL and in dark |  |  |
| **TQ38** | Settings → Accessibility → Larger Text at the largest size. Open Plans, then a plan, then tap one of its days. Look in light and in dark | On the list each row's symbol stands above its name. On the page the squares row wraps with every name legible, and an open day keeps its Start reachable |  |  |
| **TQ39** | With two plans, open Plans and tap the other plan's circle. Go back to Today without tapping **Use**, then return to Plans | While it is marked: **Use *name*** in the bottom slot. After going back and returning: the active plan's circle is filled, there is no button, and Today runs the plan it ran |  |  |

For the v1.9 rows: a `fail` on TQ18 or TQ19 points at `WeekStripView` and `QuestionRing` in
`Features/Home/HomeView.swift` and at `WeekStrip.Square.hold` (`Core/WeekStrip.swift`); on TQ20 at
`SwapQuestionView`; on TQ24 at `CycleSymbol` in `DaySquare.swift` and the `ImageRenderer` pictures
handed to the ··· menu; on TQ29 at `DaySquare(outlined:)`; on TQ33 at the `UITextView` box in
`Features/PlanDetail/JSONFragmentSheet.swift` and at `Core/JSONLocator.swift`; on TQ38 at
`PlansView` and `PlanDetailView`; on TQ39 at `PlansView`'s mark, which is never stored. If no swap
appears at all, look at `PlanLibrary.settle` (`Core/DaySwap.swift`) and whether `swaps.json` was
written beside `plans.json`.

## v1.10 rows (new in P1–P6, written with P7)

Most rows need a workout running. Use a plan whose day has about sixteen sets — the built-in
**Full Body** (15) or **Push Pull Legs**' Push (19) — so the bar has enough marks to judge. To reach
the walk between exercises without waiting, Settings → **Between exercises** at 1 min, and log the
first exercise's sets quickly.

| Case | What to do | Expected | Result | Notes |
|---|---|---|---|---|
| **TP7** | Start a sixteen-set day and log a few sets. Hold the phone at arm's length and find the set that is on. Then Settings → Display & Brightness → Dark and look again | The header has no words but the elapsed time: a segment per exercise, a tick cutting each set inside one, a gap between segments. Done sets are the day's colour, the set that is on is blue, the rest grey; the blue mark is findable at arm's length. The same in dark. A tap on the bar opens the Overview |  |  |
| **TP16** | Settings → Accessibility → Larger Text at the largest size, then start an exercise with a long range (for example 12–15, or a 30+ s hold). Look in light and in dark | The name, the dots and the card stay inside the page: the card's cells wrap onto more lines inside it, the dots wrap, and the inputs and **Log set** stay on screen together without scrolling |  |  |
| **TP23** | With the walk at 1 min, finish an exercise on a Push day and watch the strip until well past the minute; tap the ring. Repeat on a Pull day, then in dark | The ring fills clockwise from twelve o'clock, red at the start, amber about halfway, green near the end, and then a green disc with a white check at the minute — the count-up keeps going, smaller and grey. The hues read as red, amber and green beside the day's colour (Push's and Pull's orange) in light and in dark. There is no −30 / +30 / Skip. A tap on the ring shows one sentence ("At least 1:00 between exercises…") |  |  |
| **TP29** | Mid-workout, swipe zone 2 left and right a few times: during a set, during a rest and during the walk. On a page ahead, tap **▶ Do this now**; after a swipe back, **↩ Back to …**. Type a number into reps, swipe away and back, and **Log set**. Turn on VoiceOver and swipe three fingers left. Lock the phone while looking at another page | One swipe moves one exercise and the next page's edge peeks at the side, in light and dark; a page behind is fainter with a check, a page ahead grey, neither with inputs. The rest and the walk keep counting through a swipe. The number typed before swiping is what Log set logs. Do this now works that exercise, and the one that was on comes back after the exercises after it are done. Back returns to the page that is on. VoiceOver's three-finger swipe turns the page. The Lock Screen shows the set that is on, not the page looked at |  |  |
| **TP35** | Finish the same day of a plan three times, with one exercise clearly longer than the others (more rest, or more sets) and one clearly quicker. Start that day a fourth time and look at the bar; then lock the phone | The segments are no longer in proportion to the sets: the long exercise's segment is longer and the quick one's shorter, and none is a sliver or fills the bar, in light and dark. The Lock Screen's bar is unchanged from before |  |  |
| **TP42** | On a rotation plan whose days include Push, Pull and Legs: Plans → the plan → ··· → **Edit JSON**, and make `cycle` ten entries (for example `"Push", "Pull", "Legs", "rest", "Push", "Pull", "Legs", "rest", "rest", "Push"`); save. Look at the Plans list, then the plan's page. Then on Today tap ··· → **Change *day*** (for example **Change Push**), tap another tile, look at the button, go back without pressing it; open it again, mark a tile and press the button. Repeat in dark | On the list the plan's symbol is 7 squares over 3, touching, as one shape; on its page the same in larger squares with names beneath and today's square outlined. In the picker the tiles touch in a joined strip, a tapped tile takes a ring and a check, and the button reads the change with both squares (for example **Push → Pull**). Going back changes nothing; pressing the button returns to Today, which shows the change. Each reads as one thing in light and dark |  |  |

For the v1.10 rows: a `fail` on TP7 points at `BarView` in `Features/Workout/WorkoutView.swift`
and `WorkoutBar` (`Core/WorkoutBar.swift`), and the state colours at `MarkState` in
`DaySquare.swift`; on TP16 at `DotView`, `SetCardView` and `CellView` and at `RepCells`
(`Core/RepCells.swift`); on TP23 at `WalkRingView` and `StatusStripView` and at `StatusStrip.ring`
(`WalkRing.colour`); on TP29 at `OnePagePerSwipe` and the pager in `WorkoutScreenView`, and at
`WorkoutScreen.page` and `jumpTo`; on TP35 at `Pace.weights` (`Core/Pace.swift`), which reads the
past sessions' `startedAt` and `loggedAt`; on TP42 at `CycleStrip` in `DaySquare.swift`,
`CycleGlyph.rows` (`Core/DayColour.swift`) and `ChangeDayView`.

## v1.11 rows (new in N1–N5, written with N7)

The round trip needs a chatbot on the phone: the **ChatGPT** app or the **Claude** app installed and
signed in, or a chatbot in Safari for the Copy half. Use a plan with five or six exercises a day —
the built-in **Push Pull Legs** — so Progression's review has eighteen ladders to judge. TN15 and
TN16 are the two halves of one trip: run them in order, on the same reply.

| Case | What to do | Expected | Result | Notes |
|---|---|---|---|---|
| **TN15** | Today → ··· → Change plan → **Add plan** (or the empty card's **Choose a plan**) → **Send the prompt**. Look at the sheet, send it to the ChatGPT app; come back. Repeat and send it to the Claude app; repeat once more and **cancel** the sheet. Then try **Copy the prompt** instead | The share sheet opens with the prompt as text and a subject the apps that take one show. ChatGPT and Claude each open with the whole prompt in a new message, not a file or a link. **Copy** is a row of the same sheet. However the sheet closes — shared or cancelled — Add plan is on **Paste** when you come back, with the strip lit at *Paste*, and the ··· offers **Send the prompt again**. Copy the prompt does the same without a sheet |  |  |
| **TN16** | In the chatbot, let the reply finish, copy it, switch back to the app and tap **Paste**. Then tap **Paste** again with nothing copied (copy a photo first, or clear the clipboard) | The system Paste button pastes with **no permission alert** and the review opens on the plan — the cycle in squares, the days closed, **Use *name*** at the bottom. With no text on the clipboard the button does nothing at all: no alert, no error, no state change |  |  |
| **TN22** | History → **Progression** on a Push Pull Legs plan with a few workouts logged. Mark **8** and **Every week**, then **When I hit it** again; Send the prompt, come back, paste the reply. Read the ladders at arm's length; then Settings → Accessibility → Larger Text at the largest size, and Display & Brightness → Dark. Tap **Start step 1** | The tiles mark under a thumb with no mis-taps between neighbours, and dim on Paste; **Send the prompt again** brings them back marked as they were. The review's eighteen ladders each read at a glance — a climb, a dip, a level row — in light and dark and at the largest text, the first bar lit and the numbers beside it (*82.5 kg · 6–8*). **Start step 1** closes the review, and History's row reads *Step 1 of 6*. An *Every week* reply says **Start week 1** and *Week 1 of 6* |  |  |
| **TN31** | Today → ··· → **Change *day*** → the date's exercises card. Drag a row by its handle to a new place; swipe another row left and Delete; tap a row, change its weight, Save; **Add exercise** and type a name the app does not know. Then **Use for Wednesday** | The handle drags and the rows follow the finger with no jump; the swipe shows Delete and the row goes. A row opens the exercise sheet and its Save puts the change back in the row. Add exercise's field reads **Find an exercise**, and a name nothing matches is offered as **Add “…”**. **Use for Wednesday** returns to Today in one step, the day's square outlined in ink |  |  |
| **TN39** | Settings → Accessibility → VoiceOver on. Open Add plan and swipe through it on Ask, on Paste, and on a refusal (paste the prompt back into itself) | The strip is **one** element, read *"Prompt, done. Chat, now. Paste, not yet."* for the state it is in — not three squares to swipe through, and not announced as a button. The next swipe lands on the bottom slot's button, which reads its own words (**Send the prompt**, **Paste**, **Ask for the whole plan**) |  |  |

For the v1.11 rows: a `fail` on TN15 points at `PromptButtons` (`Features/Shared/PromptButtons.swift`),
whose `UIActivityViewController` completion calls `sent` — a sheet that leaves the screen on Ask
means the completion never fired; on TN16 at `PasteButton` in `ImportView` (the system's, which is
what avoids the alert) and at `ImportTrip.pasted`; on TN22 at `ProgressionScreen`'s tiles and
`ProgressionLadder.of` (`Core/ProgressionLadder.swift`), and at `ProgressionView`'s layout for the
large-text half; on TN31 at `DayEditorView`'s `.onMove` / `.onDelete` and at `DayEdit`
(`Core/DayEdit.swift`); on TN39 at `TripStripView` in `DaySquare.swift` — the strip needs
`accessibilityElement(children: .ignore)` with `TripStrip.spoken` as its label, and must not be a
control (§6.62).


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
`ProgressionSteps.achieved` / `advance` and `PlanLibrary.completeSession`. Z31 went with goals (D68).

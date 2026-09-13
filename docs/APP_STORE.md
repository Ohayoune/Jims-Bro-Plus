# App Store submission (v1.4, D49)

Everything App Store Connect will ask, answered here so the submission is a form-filling
afternoon rather than a research project. `python3 tools/check_release.py` checks the facts in
the build that can be checked; the rest is typed into the form from this page.

## 1. The order of things

1. **Enrol in the Apple Developer Program** as an individual (99 USD a year). This Mac holds
   only an *Apple Development* certificate and the checklist assumed a free account with the
   seven-day expiry; publishing, TestFlight and a distribution certificate all need the paid
   membership. Enrolment usually clears within a couple of days.
2. **Install a release Xcode.** The Xcode on this Mac (27.0, build `27A5252f`) is a beta
   build, and App Store Connect refuses uploads made with a beta Xcode or SDK. The release
   normally arrives in mid-September alongside the new iOS. When it is installed, run the
   three test routes once on it (`docs/BUILD_STATUS.md`) before archiving.
3. **Make the repository public** if the privacy policy URL below is to work, and decide the
   LICENSE (§6).
4. **Archive and upload.** Xcode → the `JimmsBro` scheme → destination *Any iOS Device* →
   Product → Archive → Distribute App → App Store Connect → Upload. Automatic signing creates
   the distribution certificate and profile on first use.
5. **Create the app record** in App Store Connect → My Apps → **+** → New App: iOS, the name
   below, English (U.K. or U.S.), bundle id `com.ohayoune.jimmsbro`, SKU `jimmsbro`.
6. **TestFlight first.** Add your own Apple ID as an internal tester, install the build on the
   phone, and run `docs/DEVICE_CHECKLIST.md` on it. A TestFlight build lasts 90 days and is the
   same binary reviewers get.
7. **Fill in the form** from §2–§5, attach the build, and **Submit for Review**. First reviews
   usually take one to two days.
8. **Updating later**: bump `MARKETING_VERSION` (1.5 → 1.6) and `CURRENT_PROJECT_VERSION`
   (1 → 2) on all three targets, tests green, Archive, Upload, Submit. Screenshots only need
   redoing when the screens changed. `tools/check_release.py` fails if the three versions
   disagree.

## 2. The record

| Field | Value |
|---|---|
| Name | **Jimm's Bro+** (30 characters max; the store requires it to be unique — if it is taken, *Jimm's Bro+ Workout*) |
| Subtitle | *Your workout, one set at a time* |
| Primary category | Health & Fitness |
| Secondary category | none |
| Price | Free |
| Availability | All territories |
| Bundle id | `com.ohayoune.jimmsbro` |
| Version | **1.5**, build **1** — the same on the app, the `JimmsBroActivity` extension and the tests; the extension's must match the app's or validation fails |
| Content rights | Contains no third-party content |
| Age rating | None of the descriptors apply; Unrestricted Web Access: No; Gambling: No → **4+** |

## 3. Description, keywords, notes

**Promotional text** (170 characters, can change without a new build):

> A plan, then Start. Log each set while the app times your rest, remembers what you lifted, and tells you when to add weight.

**Description** (4,000 characters max):

> Jimm's Bro+ runs your workout for you.
>
> Pick a plan and tap Start. The app walks you through the day one set at a time: the exercise, the target, and the weight you lifted last time. Type what you did, tap Log set, and the rest timer starts on its own — on the Lock Screen and in the Dynamic Island, with a notification when it ends, even with the phone in your pocket.
>
> It remembers everything. Next time the weight is already filled in. Hit the top of your rep range on every set and the app tells you to add weight; fall below it and it says so. History keeps every workout, your personal records and a chart for every exercise.
>
> Start with a built-in plan — Full Body, Upper Lower, Push Pull Legs, or At Home with no equipment — or have a chatbot write one from your own description: copy the prompt, paste it into ChatGPT or Claude, paste back the plan. Progression runs the loop the other way: the app writes out what you have actually lifted and the chatbot plans your next weeks.
>
> Everything stays on your phone. No account, no subscription, no ads, no network connection. Export a backup or your history as a spreadsheet whenever you like, and bring history in from Strong or Hevy.
>
> • Rest timer that alerts you while the phone is locked
> • Warm-up and a timed walk between exercises
> • Supersets, drop sets, timed holds with a warning beep
> • Weights snapped to what you can actually load
> • Change an exercise mid-workout when the machine is taken
> • Four built-in routines, and a prompt that gets a chatbot to write yours
> • History as CSV, in and out
> • Lock Screen and Dynamic Island

**Keywords** (100 characters, comma-separated, no spaces after commas):

`workout,lifting,gym,rest timer,strength,training plan,sets,reps,progression,log,weights`

**What's New** (first release): *First release.*

**Support URL**: `https://github.com/Ohayoune/Jims-Bro-Plus/issues` (once the repository is
public; see §6 for the alternative).

**Marketing URL**: none.

**Privacy policy URL**: `https://github.com/Ohayoune/Jims-Bro-Plus/blob/main/docs/PRIVACY.md`
(once the repository is public).

**Copyright**: `2026 <your name>`.

**App Review notes** (the reviewer installs cold and must be able to use the app):

> No account or sign-in. To try a workout in three taps: on the first screen tap "Choose a plan", pick "At Home" (no equipment needed), tap "Save plan", then "Start At Home A". Log a set with "Log set"; the rest timer starts on its own and can be skipped. Notifications are optional — the app asks the first time a workout starts, and everything works without them. The chatbot features (Add plan → Create with a chatbot, and Progression) copy text to the clipboard for the user to paste into a chatbot of their own; the app itself makes no network connection.

## 4. App privacy

The questionnaire's answer is **Data Not Collected**, and it is true: the app has no network
code at all, no analytics, no third-party SDKs, no account. The two things that look like data
leaving the phone are user-initiated — Export writes a file and hands it to the share sheet;
Copy prompt puts text on the clipboard — and neither is collection by the developer.

**Export compliance**: answered in the binary. `ITSAppUsesNonExemptEncryption = NO` is in the
app target's Info settings, because the app uses no encryption beyond what iOS applies to its
files, so the upload does not stop at the question.

**Required-reason APIs**: none. The app uses no `UserDefaults`, no file-timestamp APIs, no
system boot time and no disk-space APIs (checked in v1.4), so no privacy manifest is required.

## 5. Screenshots

App Store Connect requires the **6.9-inch** set (iPhone 17 Pro Max) and scales it for the
other sizes; 1320 × 2868 pixels, portrait, up to ten. `tools/shot.sh` takes them from the
simulator, seeded through the app's own store, so what they show is what the app writes:

| # | What it shows | How |
|---|---|---|
| 1 | Home with a plan: the day, its exercises, **Start** | `SEED=1 DEVICE="iPhone 17 Pro Max" tools/shot.sh build/store-1.png -uiNoAsk` |
| 2 | The workout mid-set: the card, the inputs, **Log set** | `SKIP_BUILD=1 DEVICE="iPhone 17 Pro Max" tools/shot.sh build/store-2.png -uiScreen workout -uiNoAsk -uiSkipWaits -uiAdvance 1` |
| 3 | The rest countdown | `SKIP_BUILD=1 DEVICE="iPhone 17 Pro Max" tools/shot.sh build/store-3.png -uiScreen workout -uiNoAsk -uiAdvance 1` |
| 4 | The built-in picker | `SKIP_BUILD=1 DEVICE="iPhone 17 Pro Max" tools/shot.sh build/store-4.png -uiScreen import -uiBuiltIns -uiNoAsk` |
| 5 | History with the chart | `SKIP_BUILD=1 DEVICE="iPhone 17 Pro Max" tools/shot.sh build/store-5.png -uiScreen history -uiNoAsk` |
| 6 | The introduction's first page | uninstall the app, then `SKIP_BUILD=1 DEVICE="iPhone 17 Pro Max" tools/shot.sh build/store-6.png -uiNoAsk` |

The Lock Screen and the Dynamic Island cannot be captured on the simulator; take those two on
the phone (Settings → Developer → Live Activities is not needed, a workout's rest is enough).
Screenshots may not be shown inside device frames with home-screen backgrounds that are not
the app's own; the plain captures above are fine as they are.

## 6. Choices only the owner can make

- **LICENSE.** Chosen: MIT, in `LICENSE` at the root, with the GitHub handle as the holder.
  Change the holder to a legal name if that is preferred; the app itself does not need a
  license to ship.
- **Support URL.** The repository's issues page, above, or any page with a way to reach you.
  App Review checks that it loads.
- **The name.** "Jimm's Bro+" must be unique on the store; the fallback in §2 is one option.
- **The icon.** Opaque now, as the store requires. It is a white barbell on blue, drawn by
  `tools/icon`; a more distinctive one would be the first thing strangers see, and is a
  design decision rather than a build step.

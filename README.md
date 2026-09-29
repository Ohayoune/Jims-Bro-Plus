# Jimm's Bro+

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

An iPhone app that runs your workout for you. Pick a plan and tap Start; it walks you through the day one set at a time, times your rest on the Lock Screen, remembers what you lifted, and tells you when to add weight. Plans come from four built-in routines or from a prompt a chatbot answers. No account, no server, no network connection.

<p align="center">
  <img src="docs/screenshots/intro.png" width="125" alt="The introduction: a plan, then Start">
  <img src="docs/screenshots/add-plan.png" width="125" alt="Add plan: Send the prompt, and the built-in plans as squares">
  <img src="docs/screenshots/today.png" width="125" alt="Today: the day's card, and Start">
  <img src="docs/screenshots/workout.png" width="125" alt="The workout in symbols: the bar, a dot per set, the card of cells, a rest counting down">
  <img src="docs/screenshots/progression.png" width="125" alt="A progression of steps, one exercise on its second">
  <img src="docs/screenshots/history.png" width="125" alt="History: the month, each day in its own colour">
</p>

## What it does

- **Runs the workout.** In marks rather than sentences: a bar for the day, a dot per set, and a card with a cell per rep — the target solid, a line where you reached last time — with the weight you used already filled in. Swipe to look at the exercises before and after. Log what you did and the rest timer starts on its own — on the Lock Screen and in the Dynamic Island, with a notification when the phone is in your pocket. Warm-up, timed holds, supersets, drop sets, a walk between exercises.
- **Remembers.** Next time the weight is already filled in. Hit the top of your rep range and it suggests the next weight, snapped to what your plates can make. Every set is kept: a calendar with each day in its own colour, history, personal records, a chart per exercise, metrics over time.
- **Gets plans from a chatbot.** Tap **Send the prompt** and the share sheet hands it to ChatGPT or Claude — or copy it for a chatbot in a browser — then paste the reply back and use the plan. The same three steps ask for a progression, or for a change said in one sentence. A reply that came cut short can be finished one day at a time. Four built-in routines — Full Body, Upper Lower, Push Pull Legs, At Home — to start from.
- **Progresses.** Ask the chatbot for a progression from what you actually lifted, then earn each step by hitting it.
- **Keeps your data on the phone.** Back up to a file, export history as a spreadsheet, import from Strong or Hevy. Nothing leaves the phone unless you send it. [Privacy policy](docs/PRIVACY.md).

## Status

**v1.12**, built and green on every route ([docs/BUILD_STATUS.md](docs/BUILD_STATUS.md)). Not yet on the App Store: the submission is prepared in [docs/APP_STORE.md](docs/APP_STORE.md) and waits on the paid Developer Program and a release Xcode. Until then, build it yourself.

## Build it

Xcode 26 or later on a Mac, an iPhone on iOS 17 or later.

1. Open `JimmsBro.xcodeproj` and pick the shared `JimmsBro` scheme.
2. Signing & Capabilities → choose your team (a free Apple ID works for seven days at a time).
3. Plug in the phone, choose it as the destination, press Run. [docs/BUILD_PLAN.md](docs/BUILD_PLAN.md) has the one-time steps on the phone.

The tests run on three routes — the simulator, `swift test` on the host, and a portable runner that needs no Xcode — all run on this Mac by `tools/check_all.sh`. [GitHub Actions](.github/workflows/ci.yml) can run the same checks, but only when started by hand. The commands are below.

## License

[MIT](LICENSE).

---

## For developers

The design package, the test routes and the tools are described in [docs/DEVELOPING.md](docs/DEVELOPING.md).

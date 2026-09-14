# Frozen store files

One file of every type the app writes, exactly as **v1.1** wrote it, captured before v1.2 added
any field. `JimmsBroTests/StoreMigrationTests.swift` decodes each one and checks what it holds.

They exist because synthesized `Codable` makes a defaulted property a *required* key: without a
test that reads a real old file, adding one field to `Settings`, `Plan` or `Session` would make
every file already on a phone fail to decode, and SPEC §8.3's corruption path would quietly move
the user's plans and history aside. `JimmsBro/Core/Persistence.swift` is the rule these check.

**Never regenerate these to make a test pass.** They are what is on the owner's phone. If one no
longer decodes, that is the bug.

| File | Holds |
|---|---|
| `v1/settings.json` | Every setting v1.1 had, at non-default values where it matters |
| `v1/plans.json` | One plan with a superset (so `groupRestSeconds` is exercised) and an active plan id |
| `v1/session.json` | A completed session: logged sets, skipped sets, timestamps, advice |
| `v1/active-session.json` | A workout interrupted mid-rest: phase, `lastCompletedStep`, `workWeight` |

**v1.9 (D72)** added three, written by the app's own encoder on 2026-09-14 for the plan's example — Push · Pull · Legs · Rest · Push · Pull · Legs, with Legs finished on Monday 14 September, which expected Push (`JimmsBroTests/SwapTests.swift`, TQ10). The same rule applies: never regenerate them to make a test pass.

| File | Holds |
|---|---|
| `v1/swaps.json` | The two swaps that workout wrote: Monday's record and Wednesday's open question |
| `v1/backup-1.9.json` | A backup that carries them, with the plan and the session |
| `v1/backup-1.7.json` | The same backup as v1.7 wrote it: `goals`, no `swaps` — it restores with none |

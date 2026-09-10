import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// M5 — N3–N7 input rules, H1/H2/H17 rest timing, and the session lifecycle behind the
/// workout screens (start, run, switch day, finish, discard, resume).
final class WorkoutTests: XCTestCase {
    private func makeRoot() -> URL { CoreTestSupport.makeRoot() }
    private func discard(_ root: URL) { CoreTestSupport.discard(root) }
    private func sample() throws -> String { try FixtureLoader.text("valid/weekly-rotation.json") }

    // N3: both separators mean the same number.
    func testWeightAcceptsBothSeparators() {
        XCTAssertEqual(InputRules.weight("62,5"), "62.5")
        XCTAssertEqual(InputRules.weight("62.5"), "62.5")
        XCTAssertEqual(InputRules.weightValue("62,5"), 62.5)
        XCTAssertEqual(InputRules.weightValue("62.5"), 62.5)
        // A half-typed number stays put so the user can finish typing.
        XCTAssertEqual(InputRules.weight("62."), "62.")
        XCTAssertNil(InputRules.weightValue(""))
        XCTAssertEqual(InputRules.weightValue("0"), 0, "0 is a valid weight")
    }

    // N4: one decimal place is kept on commit.
    func testWeightRoundsToOneDecimalOnCommit() {
        XCTAssertEqual(InputRules.weightValue("62.55"), 62.6)
        XCTAssertEqual(InputRules.weightValue("62.54"), 62.5)
        XCTAssertEqual(InputRules.weightValue("100"), 100)
        XCTAssertEqual(InputRules.weightText(62.6), "62.6")
        XCTAssertEqual(InputRules.weightText(60), "60", "a whole number drops its .0")
        XCTAssertEqual(InputRules.weightText(nil), "")
    }

    // N5: nonsense is refused and the field keeps what it had.
    func testWeightRejectsInvalidInput() {
        for bad in ["abc", "1.2.3", "-5", "6 0", "62.5kg", "1e3"] {
            XCTAssertEqual(InputRules.weight(bad, previous: "60"), "60", "\(bad) must be refused")
        }
        // Over the maximum is refused too, and the boundary itself is allowed.
        XCTAssertEqual(InputRules.weight("10001", previous: "60"), "60")
        XCTAssertEqual(InputRules.weight("10000", previous: "60"), "10000")
        // Clearing the field is allowed: it means "no weight".
        XCTAssertEqual(InputRules.weight("", previous: "60"), "")
    }

    // N6: the reps field truncates to three digits, and refuses non-digits.
    func testRepsFieldLimits() {
        XCTAssertEqual(InputRules.reps("1000"), "100")
        XCTAssertEqual(InputRules.reps("12"), "12")
        XCTAssertEqual(InputRules.reps("0"), "0", "a failed set logs as 0")
        XCTAssertEqual(InputRules.reps("1a", previous: "12"), "12")
        XCTAssertEqual(InputRules.reps("-1", previous: "12"), "12")
        XCTAssertNil(InputRules.repsValue(""))
        XCTAssertEqual(InputRules.repsValue("0"), 0)
        // Seconds allow five digits.
        XCTAssertEqual(InputRules.seconds("123456"), "12345")
        XCTAssertEqual(InputRules.seconds("45x", previous: "45"), "45")
    }

    // N7: − never goes below zero.
    func testSteppersNeverGoBelowZero() {
        XCTAssertEqual(InputRules.stepped(weight: 2.5, by: 2.5, up: false), 0)
        XCTAssertEqual(InputRules.stepped(weight: 0, by: 2.5, up: false), 0)
        XCTAssertEqual(InputRules.stepped(weight: nil, by: 2.5, up: false), 0)
        XCTAssertEqual(InputRules.stepped(weight: 0, by: 2.5, up: true), 2.5)
        XCTAssertEqual(InputRules.stepped(weight: 60, by: 5, up: true), 65)
        XCTAssertEqual(InputRules.stepped(weight: 10_000, by: 5, up: true), 10_000)
        XCTAssertEqual(InputRules.stepped(reps: 0, up: false), 0)
        XCTAssertEqual(InputRules.stepped(reps: nil, up: true), 1)
        XCTAssertEqual(InputRules.stepped(seconds: 5, by: 15, up: false), 0)
    }

    // O7 / O34 / O39: the card's lines for every target kind, in the compact notation —
    // which since D58 (v1.6) is Settings' switch rather than the only voice the app has.
    // U34 pins the plain grammar that replaced it as the default.
    func testStepCardLines() throws {
        let plan = CoreTestSupport.plan(sets: 3, secondExercise: true)
        var session = CoreTestSupport.session(plan)
        XCTAssertEqual(StepCard.header(session: session, step: 0), "Set 1 of 6")
        XCTAssertEqual(StepCard.setLine(session: session, step: 0, wording: .compact), "Set 1 of 3")
        XCTAssertEqual(StepCard.targetLine(session: session, step: 0, wording: .compact),
                       "8–12 · 60 kg")

        // A fixed count inside a range, AMRAP, an open minimum and a fixed duration.
        let cases: [(WorkTarget, String)] = [
            (.reps(.fixed(10)), "10 (8–12) · 60 kg"),
            (.reps(.amrap(min: nil)), "AMRAP · 60 kg"),
            (.reps(.amrap(min: 10)), "10+ · 60 kg"),
            (.duration(seconds: 45), "45 s · 60 kg"),
            (.openDuration(minSeconds: 30), "30+ s · 60 kg"),
        ]
        for (work, expected) in cases {
            var one = CoreTestSupport.plan(sets: 1, work: work)
            one.days[0].exercises[0].repRange = RepRange(min: 8, max: 12)
            let s = CoreTestSupport.session(one)
            XCTAssertEqual(StepCard.targetLine(session: s, step: 0, wording: .compact), expected)
        }

        // A superset member is tagged, and a drop names its position.
        let grouped = CoreTestSupport.plan(sets: 2, secondExercise: true,
                                           drops: [DropTarget(work: .reps(.amrap(min: nil)), weight: 40)],
                                           group: "A")
        session = CoreTestSupport.session(grouped)
        XCTAssertEqual(StepCard.setLine(session: session, step: 0, wording: .compact), "A · Set 1 of 2")
        let dropStep = try XCTUnwrap(session.steps.firstIndex { $0.dropIndex == 1 })
        XCTAssertEqual(StepCard.setLine(session: session, step: dropStep, wording: .compact),
                       "A · Set 1 of 2 · drop 1 of 1")

        // Bodyweight hides the weight everywhere.
        let bodyweight = CoreTestSupport.plan(sets: 2, weight: nil, bodyweight: true)
        let body = CoreTestSupport.session(bodyweight)
        XCTAssertFalse(Prefill.values(session: body, step: 0, history: []).showsWeight)
        XCTAssertEqual(StepCard.targetLine(session: body, step: 0, wording: .compact), "8–12")

        // O8: Log set needs a number, unless the set is timed.
        XCTAssertFalse(StepCard.canLog(repsText: "", isTimed: false))
        XCTAssertTrue(StepCard.canLog(repsText: "0", isTimed: false))
        XCTAssertTrue(StepCard.canLog(repsText: "", isTimed: true))
    }

    /// I40–I43 (v1.1, D22/D14): the Core text and row data R2's workout screen will render.
    func testProgressSetRowsAndBlockDoneLine() throws {
        let plain = CoreTestSupport.plan(sets: 3, secondExercise: true)
        var session = CoreTestSupport.session(plain)
        XCTAssertEqual(StepCard.progress(session: session, step: 0, wording: .compact),
                       "Exercise 1 of 2 · Set 1 of 3")
        session.steps[0].status = .logged
        session.steps[0].result = .reps(count: 10, weight: 60)
        let rows = StepCard.setRows(session: session, step: 1, history: [], wording: .compact)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows.map(\.isCurrent), [false, true, false])
        XCTAssertEqual(rows[0].status, .logged); XCTAssertEqual(rows[0].value, "10 @ 60")
        XCTAssertEqual(rows[1].status, .pending); XCTAssertEqual(rows[1].value, "8–12 · 60 kg")

        let grouped = CoreTestSupport.plan(sets: 2, secondExercise: true, group: "A")
        let groupedSession = CoreTestSupport.session(grouped)
        XCTAssertEqual(StepCard.progress(session: groupedSession, step: 0, wording: .compact),
                       "A · round 1 of 2 · Bench Press")
        let groupRows = StepCard.setRows(session: groupedSession, step: 0, history: [])
        XCTAssertEqual(groupRows.count, 2, "only this round's members, not every round")
        XCTAssertEqual(Set(groupRows.map(\.stepIndex)), [0, 1])

        let dropped = CoreTestSupport.plan(sets: 1, drops: [DropTarget(work: .reps(.amrap(min: nil)), weight: 40)])
        let droppedSession = CoreTestSupport.session(dropped)
        let dropIndex = try XCTUnwrap(droppedSession.steps.firstIndex { $0.dropIndex == 1 })
        XCTAssertEqual(StepCard.progress(session: droppedSession, step: dropIndex, wording: .compact),
                      "Exercise 1 of 1 · Set 1 of 1 · drop 1 of 1")

        var e = CoreTestSupport.engine(CoreTestSupport.plan(sets: 1, secondExercise: true))
        e.apply(.logSet(step: 0, result: .reps(count: 12, weight: 60)), now: CoreTestSupport.now)
        let blockDone = try XCTUnwrap(e.active.blockDone)
        let line = try XCTUnwrap(StepCard.blockDoneLine(session: e.session, blockDone: blockDone))
        XCTAssertTrue(line.hasPrefix("Bench Press done"), line)
        XCTAssertTrue(line.contains("Try 62.5 kg next time"), line)
    }

    // H1 / H17: rest is Date-based, so remaining time is correct however long the app was away.
    @MainActor func testRestCountsDownFromDates() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let recorder = RecordingAlerts()
        let model = AppModel(store: Store(root: root), scheduler: recorder, alerts: recorder,
                             sampleJSON: { nil })
        await model.load()
        let plan = try XCTUnwrap(model.runImport(CoreTestSupport.planJSON()).plan)
        await model.save(plan, makeActive: true)
        let start = CoreTestSupport.now
        try await model.startDay(planId: try XCTUnwrap(model.activePlanId), dayIndex: 0, now: start)

        await model.apply(.logSet(step: 0, result: .reps(count: 10, weight: 60)), now: start)
        guard case let .resting(rest) = try XCTUnwrap(model.phase) else {
            return XCTFail("logging the first set starts a rest")
        }
        XCTAssertEqual(rest.endsAt.timeIntervalSince(start), 90, accuracy: 0.001)
        // Remaining is derived, never counted: a long gap gives the same answer as many ticks.
        XCTAssertEqual(rest.endsAt.timeIntervalSince(start.addingTimeInterval(1)), 89, accuracy: 0.001)
        XCTAssertEqual(rest.endsAt.timeIntervalSince(start.addingTimeInterval(89)), 1, accuracy: 0.001)

        let scheduled = try XCTUnwrap(recorder.pending.first { $0.id == AlertIdentifier.rest })
        XCTAssertEqual(scheduled.date, rest.endsAt)
        XCTAssertEqual(scheduled.title, "Rest over")
        XCTAssertTrue(scheduled.body.contains("set 2 of 3"))
        XCTAssertEqual(scheduled.sound, .standard)

        // H17: coming back long after the end lands on the next step, with no replayed beep.
        recorder.reset()
        await model.tick(now: start.addingTimeInterval(600), replayMissed: false)
        XCTAssertEqual(model.phase, .working(step: 1))
        XCTAssertEqual(recorder.played, [], "a rest that ended while away must not beep on return")
        XCTAssertTrue(recorder.cancelled.contains(AlertIdentifier.rest))
    }

    // H2: +30 twice then −30 nets +30, and the notification is rescheduled each time.
    @MainActor func testRestAdjustmentsRescheduleTheNotification() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let recorder = RecordingAlerts()
        let model = AppModel(store: Store(root: root), scheduler: recorder, alerts: recorder,
                             sampleJSON: { nil })
        await model.load()
        let plan = try XCTUnwrap(model.runImport(CoreTestSupport.planJSON()).plan)
        await model.save(plan, makeActive: true)
        let start = CoreTestSupport.now
        try await model.startDay(planId: try XCTUnwrap(model.activePlanId), dayIndex: 0, now: start)
        await model.apply(.logSet(step: 0, result: .reps(count: 10, weight: 60)), now: start)

        recorder.reset()
        for seconds in [30, 30, -30] {
            await model.apply(.adjustRest(seconds: seconds), now: start)
        }
        guard case let .resting(rest) = try XCTUnwrap(model.phase) else { return XCTFail("still resting") }
        XCTAssertEqual(rest.endsAt.timeIntervalSince(start), 120, accuracy: 0.001, "90 + 30 + 30 − 30")
        XCTAssertEqual(recorder.scheduled.filter { $0.id == AlertIdentifier.rest }.count, 3,
                       "each adjustment reschedules")
        XCTAssertEqual(try XCTUnwrap(recorder.pending.first { $0.id == AlertIdentifier.rest }).date,
                       rest.endsAt)

        // Shrinking rest past now ends it immediately and cancels the notification.
        recorder.reset()
        await model.apply(.adjustRest(seconds: -30), now: start.addingTimeInterval(115))
        XCTAssertEqual(model.phase, .working(step: 1))
        XCTAssertTrue(recorder.cancelled.contains(AlertIdentifier.rest))
        XCTAssertTrue(recorder.pending.isEmpty)
    }

    // Fixed-duration sets: two notifications with the right sounds, then auto-log at zero.
    @MainActor func testFixedTimerSchedulesWarningAndEnd() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let recorder = RecordingAlerts()
        let model = AppModel(store: Store(root: root), scheduler: recorder, alerts: recorder,
                             sampleJSON: { nil })
        await model.load()
        let json = CoreTestSupport.planJSON(exercise:
            #"{ "name": "Plank", "sets": 2, "durationSeconds": 45, "warningBeep": 5, "bodyweight": true, "restSeconds": 30 }"#)
        let plan = try XCTUnwrap(model.runImport(json).plan)
        await model.save(plan, makeActive: true)
        let start = CoreTestSupport.now
        try await model.startDay(planId: try XCTUnwrap(model.activePlanId), dayIndex: 0, now: start)

        recorder.reset()
        await model.apply(.startTimer(step: 0), now: start)
        let end = try XCTUnwrap(recorder.pending.first { $0.id == AlertIdentifier.setEnd })
        let warning = try XCTUnwrap(recorder.pending.first { $0.id == AlertIdentifier.setWarning })
        XCTAssertEqual(end.date.timeIntervalSince(start), 45, accuracy: 0.001)
        XCTAssertEqual(warning.date.timeIntervalSince(start), 40, accuracy: 0.001)
        XCTAssertEqual(warning.sound, .warning, "the warning uses the bundled warning.caf")
        XCTAssertEqual(end.sound, .standard)
        XCTAssertEqual(warning.body, "5 s left")

        // Foregrounded through both moments: they play in order and are not replayed.
        await model.tick(now: start.addingTimeInterval(41))
        XCTAssertEqual(recorder.played, [.warning])
        await model.tick(now: start.addingTimeInterval(46))
        XCTAssertEqual(recorder.played, [.warning, .end])
        XCTAssertEqual(model.session?.steps[0].result, .duration(seconds: 45, weight: nil),
                       "reaching zero logs the full duration")
        await model.tick(now: start.addingTimeInterval(47))
        XCTAssertEqual(recorder.played, [.warning, .end], "beeps never replay")
    }

    // Open-duration sets: one minimum beep, and Stop logs the elapsed seconds.
    @MainActor func testOpenTimerBeepsAtMinimumAndStopLogsElapsed() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let recorder = RecordingAlerts()
        let model = AppModel(store: Store(root: root), scheduler: recorder, alerts: recorder,
                             sampleJSON: { nil })
        await model.load()
        let json = CoreTestSupport.planJSON(exercise:
            #"{ "name": "Dead Hang", "sets": 2, "durationSeconds": "30+", "bodyweight": true, "restSeconds": 30 }"#)
        let plan = try XCTUnwrap(model.runImport(json).plan)
        await model.save(plan, makeActive: true)
        let start = CoreTestSupport.now
        try await model.startDay(planId: try XCTUnwrap(model.activePlanId), dayIndex: 0, now: start)

        recorder.reset()
        await model.apply(.startTimer(step: 0), now: start)
        let minimum = try XCTUnwrap(recorder.pending.first { $0.id == AlertIdentifier.setMinimum })
        XCTAssertEqual(minimum.date.timeIntervalSince(start), 30, accuracy: 0.001)
        XCTAssertNil(recorder.pending.first { $0.id == AlertIdentifier.setEnd },
                     "an open set has no end")

        await model.tick(now: start.addingTimeInterval(31))
        XCTAssertEqual(recorder.played, [.minimum])
        // It keeps running past the minimum; Stop decides.
        await model.tick(now: start.addingTimeInterval(50))
        XCTAssertEqual(model.phase, .working(step: 0))
        await model.apply(.stopTimer(step: 0), now: start.addingTimeInterval(52))
        XCTAssertEqual(model.session?.steps[0].result, .duration(seconds: 52, weight: nil))
        XCTAssertTrue(recorder.cancelled.contains(AlertIdentifier.setMinimum))
    }

    // O11 / O12: the counts the Finish confirmations quote, and discard writing nothing.
    @MainActor func testFinishAndDiscard() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let recorder = RecordingAlerts()
        let model = AppModel(store: Store(root: root), scheduler: recorder, alerts: recorder,
                             sampleJSON: { nil })
        await model.load()
        let plan = try XCTUnwrap(model.runImport(CoreTestSupport.planJSON()).plan)
        await model.save(plan, makeActive: true)
        let planId = try XCTUnwrap(model.activePlanId)
        let start = CoreTestSupport.now

        // Discard: nothing is written, and the active file goes away.
        try await model.startDay(planId: planId, dayIndex: 0, now: start)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("active-session.json").path))
        XCTAssertEqual(model.pendingStepCount, 3)
        XCTAssertEqual(model.loggedStepCount, 0)
        await model.discardSession()
        XCTAssertFalse(model.hasActiveSession)
        XCTAssertEqual(model.sessions, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("active-session.json").path))

        // Finish with some pending: the count is what the confirmation quotes.
        try await model.startDay(planId: planId, dayIndex: 0, now: start)
        await model.apply(.logSet(step: 0, result: .reps(count: 10, weight: 60)), now: start)
        XCTAssertEqual(model.pendingStepCount, 2)
        XCTAssertEqual(model.loggedStepCount, 1)
        await model.finish(now: start.addingTimeInterval(300))
        XCTAssertFalse(model.hasActiveSession)
        XCTAssertEqual(model.sessions.count, 1)
        XCTAssertEqual(model.sessions[0].steps.filter { $0.status == .skipped }.count, 2)
        XCTAssertNotNil(model.sessions[0].endedAt)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("active-session.json").path))

        // It reloads from disk as history, and the rotation pointer moved.
        let reloaded = AppModel(store: Store(root: root), sampleJSON: { nil })
        await reloaded.load()
        XCTAssertEqual(reloaded.sessions.count, 1)
        XCTAssertNil(reloaded.engine)
        XCTAssertEqual(reloaded.plans.first?.cyclePosition, 0)
    }

    // O36 / D17: starting another day mid-session needs a choice.
    @MainActor func testSwitchDayRequiresAChoice() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let recorder = RecordingAlerts()
        let model = AppModel(store: Store(root: root), scheduler: recorder, alerts: recorder,
                             sampleJSON: { nil })
        await model.load()
        let plan = try XCTUnwrap(model.runImport(try sample()).plan)
        await model.save(plan, makeActive: true)
        let planId = try XCTUnwrap(model.activePlanId)
        let start = CoreTestSupport.now
        try await model.startDay(planId: planId, dayIndex: 0, now: start)
        await model.apply(.logSet(step: 0, result: .reps(count: 8, weight: 80)), now: start)

        // Keep going: no choice given, so it refuses rather than silently switching.
        do {
            try await model.startDay(planId: planId, dayIndex: 1, now: start)
            XCTFail("switching mid-session must require a choice")
        } catch {
            XCTAssertEqual(error as? LibraryError, .sessionInProgress)
        }
        XCTAssertEqual(model.session?.dayName, "Push")
        XCTAssertEqual(model.sessions, [])

        // Finish X and start Y: the first is saved, the second is running.
        try await model.startDay(planId: planId, dayIndex: 1, switching: .finish,
                                 now: start.addingTimeInterval(60))
        XCTAssertEqual(model.sessions.count, 1)
        XCTAssertEqual(model.sessions[0].dayName, "Push")
        XCTAssertEqual(model.session?.dayName, "Pull")

        // Discard X and start Y: the discarded one is never saved.
        await model.apply(.logSet(step: 0, result: .reps(count: 8, weight: 80)),
                          now: start.addingTimeInterval(120))
        try await model.startDay(planId: planId, dayIndex: 2, switching: .discard,
                                 now: start.addingTimeInterval(180))
        XCTAssertEqual(model.sessions.count, 1, "the discarded Pull was not saved")
        XCTAssertEqual(model.session?.dayName, "Legs")

        // Everything that survived is on disk.
        let reloaded = AppModel(store: Store(root: root), sampleJSON: { nil })
        await reloaded.load()
        XCTAssertEqual(reloaded.sessions.map(\.dayName), ["Push"])
        XCTAssertEqual(reloaded.session?.dayName, "Legs")
    }

    // SPEC §5.4: a killed app resumes on the exact step, with rest time computed from endsAt.
    @MainActor func testResumeRestoresStepAndRest() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let recorder = RecordingAlerts()
        let model = AppModel(store: Store(root: root), scheduler: recorder, alerts: recorder,
                             sampleJSON: { nil })
        await model.load()
        let plan = try XCTUnwrap(model.runImport(CoreTestSupport.planJSON()).plan)
        await model.save(plan, makeActive: true)
        let start = CoreTestSupport.now
        try await model.startDay(planId: try XCTUnwrap(model.activePlanId), dayIndex: 0, now: start)
        await model.apply(.logSet(step: 0, result: .reps(count: 11, weight: 62.5)), now: start)

        // A fresh model over the same directory is the relaunch.
        let resumed = AppModel(store: Store(root: root), sampleJSON: { nil })
        await resumed.load()
        XCTAssertTrue(resumed.hasActiveSession)
        guard case let .resting(rest) = try XCTUnwrap(resumed.phase) else {
            return XCTFail("the rest that was running must come back")
        }
        XCTAssertEqual(rest.endsAt.timeIntervalSince(start), 90, accuracy: 0.001)
        XCTAssertEqual(resumed.currentStep, 1)
        XCTAssertEqual(resumed.session?.steps[0].result, .reps(count: 11, weight: 62.5))
        // The card that comes back prefills from the set just logged.
        let values = Prefill.values(session: try XCTUnwrap(resumed.session), step: 1,
                                    history: resumed.sessions)
        XCTAssertEqual(values.weight, 62.5)

        // The Home card offers Resume rather than Start.
        let card = resumed.startCard(now: start.addingTimeInterval(23 * 60))
        XCTAssertEqual(card.buttonTitle, "Resume")
        XCTAssertEqual(card.title, "Push in progress · 23 min")
    }

    // The Summary needs the finished session after the engine has been cleared (SPEC §4.9).
    // Completing nils the engine immediately, which used to dismiss the workout past the Summary.
    @MainActor func testFinishedSessionSurvivesForTheSummary() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let recorder = RecordingAlerts()
        let model = AppModel(store: Store(root: root), scheduler: recorder, alerts: recorder,
                             sampleJSON: { nil })
        await model.load()
        let plan = try XCTUnwrap(model.runImport(CoreTestSupport.planJSON()).plan)
        await model.save(plan, makeActive: true)
        let planId = try XCTUnwrap(model.activePlanId)
        let start = CoreTestSupport.now

        try await model.startDay(planId: planId, dayIndex: 0, now: start)
        XCTAssertNil(model.justCompleted)
        for step in 0..<3 {
            await model.apply(.logSet(step: step, result: .reps(count: 10, weight: 60)),
                              now: start.addingTimeInterval(Double(step) * 120))
            if case .resting = model.phase { await model.apply(.skipRest) }
        }
        // The engine is gone, but the finished session is still available to render.
        XCTAssertNil(model.engine)
        let finished = try XCTUnwrap(model.justCompleted)
        XCTAssertEqual(finished.steps.filter { $0.status == .logged }.count, 3)
        XCTAssertNotNil(finished.endedAt)
        XCTAssertEqual(finished.id, model.sessions.last?.id)

        model.dismissSummary()
        XCTAssertNil(model.justCompleted, "tapping Done clears it")

        // Finishing as part of a day switch goes straight into the new workout, no Summary.
        try await model.startDay(planId: planId, dayIndex: 0, now: start.addingTimeInterval(600))
        await model.apply(.logSet(step: 0, result: .reps(count: 10, weight: 60)),
                          now: start.addingTimeInterval(600))
        try await model.startDay(planId: planId, dayIndex: 0, switching: .finish,
                                 now: start.addingTimeInterval(900))
        XCTAssertNil(model.justCompleted, "a switch must not raise a Summary over the new workout")
        XCTAssertTrue(model.hasActiveSession)

        // Discarding raises no Summary either.
        await model.discardSession()
        XCTAssertNil(model.justCompleted)
        XCTAssertFalse(model.hasActiveSession)
    }

    /// K19 (D24, v1.1): a session write failure during completion keeps `active-session.json`,
    /// never marks the session persisted, and surfaces `saveFailure`; retrying after the write
    /// path is unblocked finishes the job (clears the file, persists it, clears the failure).
    @MainActor func testSessionWriteFailureIsKeptAndRetried() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let recorder = RecordingAlerts()
        let model = AppModel(store: Store(root: root), scheduler: recorder, alerts: recorder,
                             sampleJSON: { nil })
        await model.load()
        let plan = try XCTUnwrap(model.runImport(CoreTestSupport.planJSON()).plan)
        await model.save(plan, makeActive: true)
        let planId = try XCTUnwrap(model.activePlanId)
        let start = CoreTestSupport.now
        try await model.startDay(planId: planId, dayIndex: 0, now: start)
        for step in 0..<2 {
            await model.apply(.logSet(step: step, result: .reps(count: 10, weight: 60)),
                              now: start.addingTimeInterval(Double(step) * 120))
            if case .resting = model.phase { await model.apply(.skipRest) }
        }

        // Block sessions/ right before the log that completes the workout.
        let sessionsDir = root.appendingPathComponent("sessions")
        try FileManager.default.removeItem(at: sessionsDir)
        try Data().write(to: sessionsDir)

        await model.apply(.logSet(step: 2, result: .reps(count: 10, weight: 60)),
                          now: start.addingTimeInterval(240))
        let finished = try XCTUnwrap(model.justCompleted)
        XCTAssertEqual(model.saveFailure, .session(finished))
        XCTAssertFalse(model.persistedSessionIds.contains(finished.id))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("active-session.json").path),
            "the active session file must survive a failed completion write")

        // Unblock and retry: the data was never discarded, so this now succeeds.
        try FileManager.default.removeItem(at: sessionsDir)
        try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        await model.retrySaveFailure()
        XCTAssertNil(model.saveFailure)
        XCTAssertTrue(model.persistedSessionIds.contains(finished.id))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("active-session.json").path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: sessionsDir.appendingPathComponent("\(finished.id.uuidString).json").path))
    }

    /// K20 (D24, v1.1): an `active-session.json` whose phase is already `.completed` — a prior
    /// run whose session write succeeded but whose file-clear didn't — is recovered as a normal
    /// session on the next launch rather than resumed as a live workout or silently dropped.
    @MainActor func testLaunchRecoversACompletedActiveSessionFile() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let recorder = RecordingAlerts()
        let model = AppModel(store: Store(root: root), scheduler: recorder, alerts: recorder,
                             sampleJSON: { nil })
        await model.load()
        let plan = try XCTUnwrap(model.runImport(CoreTestSupport.planJSON()).plan)
        await model.save(plan, makeActive: true)
        let planId = try XCTUnwrap(model.activePlanId)
        let start = CoreTestSupport.now
        try await model.startDay(planId: planId, dayIndex: 0, now: start)
        for step in 0..<3 {
            await model.apply(.logSet(step: step, result: .reps(count: 10, weight: 60)),
                              now: start.addingTimeInterval(Double(step) * 120))
            if case .resting = model.phase { await model.apply(.skipRest) }
        }
        let finishedId = try XCTUnwrap(model.justCompleted?.id)
        let completed = try XCTUnwrap(model.sessions.first { $0.id == finishedId })
        // Simulate the file-clear step from a prior run never having happened.
        try await Store(root: root).save(activeSession: ActiveSession(session: completed, phase: .completed))

        let relaunched = AppModel(store: Store(root: root), scheduler: RecordingAlerts(),
                                  alerts: RecordingAlerts(), sampleJSON: { nil })
        await relaunched.load()
        XCTAssertFalse(relaunched.hasActiveSession)
        XCTAssertTrue(relaunched.sessions.contains { $0.id == finishedId })
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("active-session.json").path))
    }

    // Every alert identifier the app can schedule is cancelled together.
    @MainActor func testCancelAllAlertsCoversEveryIdentifier() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let recorder = RecordingAlerts()
        let model = AppModel(store: Store(root: root), scheduler: recorder, alerts: recorder,
                             sampleJSON: { nil })
        await model.load()
        for id in AlertIdentifier.all {
            await recorder.schedule(AlertRouting.request(id: id, at: CoreTestSupport.now, body: "x"))
        }
        XCTAssertEqual(recorder.pending.count, 4)
        await model.cancelAllAlerts()
        XCTAssertTrue(recorder.pending.isEmpty)
        // And each id gets a title of its own, so a delivered notification reads sensibly.
        XCTAssertEqual(AlertIdentifier.rest.title, "Rest over")
        XCTAssertEqual(AlertIdentifier.setEnd.title, "Time!")
        XCTAssertEqual(Set(AlertIdentifier.all.map(\.title)).count, 4)
        // Only the warning uses the short bundled sound.
        XCTAssertEqual(AlertIdentifier.all.filter { $0.sound == .warning }, [.setWarning])
    }
}

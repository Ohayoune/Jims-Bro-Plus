import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// R2 (v1.1) — the fixed-zone workout screen of SPEC §4.5: O50–O62. The zones, the strip, the
/// one primary slot, undo, and the removal of the between-exercise Continue gate.
final class WorkoutScreenTests: XCTestCase {
    private let now = CoreTestSupport.now

    private func makeRoot() -> URL { CoreTestSupport.makeRoot() }
    private func discard(_ root: URL) { CoreTestSupport.discard(root) }

    private func model(session: Session, phase: Phase, blockDone: BlockDone? = nil,
                       timerRunning: Bool = false, lastCompleted: Int? = nil,
                       history: [Session] = [], at date: Date? = nil) -> WorkoutScreenModel? {
        let active = ActiveSession(session: session, phase: phase, timerRunning: timerRunning,
                                   blockDone: blockDone, lastCompletedStep: lastCompleted)
        return WorkoutScreen.model(active: active, history: history, now: date ?? now)
    }

    // O50: the five zones are present, in the same order, in every state the screen has.
    func testZonesNeverChangeBetweenStates() throws {
        // 1. Working.
        var working = CoreTestSupport.engine(CoreTestSupport.plan(sets: 3))
        let workingModel = try XCTUnwrap(WorkoutScreen.model(active: working.active, history: [], now: now))

        // 2. Resting.
        working.apply(.logSet(step: 0, result: .reps(count: 10, weight: 60)), now: now)
        guard case .resting = working.phase else { return XCTFail("logging a set starts a rest") }
        let restingModel = try XCTUnwrap(WorkoutScreen.model(active: working.active, history: [],
                                                             now: now.addingTimeInterval(30)))

        // 3. A timed set, running.
        var timed = CoreTestSupport.engine(CoreTestSupport.plan(sets: 1, work: .duration(seconds: 45)))
        timed.apply(.startTimer(step: 0), now: now)
        let timedModel = try XCTUnwrap(WorkoutScreen.model(active: timed.active, history: [],
                                                           now: now.addingTimeInterval(10)))

        // 4. A block having just finished.
        var block = CoreTestSupport.engine(CoreTestSupport.plan(sets: 1, secondExercise: true))
        block.apply(.logSet(step: 0, result: .reps(count: 12, weight: 60)), now: now)
        XCTAssertNotNil(block.active.blockDone, "a finished block leaves a strip, not a screen")
        let blockModel = try XCTUnwrap(WorkoutScreen.model(active: block.active, history: [],
                                                           now: now.addingTimeInterval(42)))

        let expected: [WorkoutZone] = [.header, .exercise, .inputs, .strip, .primary]
        for (name, screen) in [("working", workingModel), ("resting", restingModel),
                               ("timed", timedModel), ("blockDone", blockModel)] {
            XCTAssertEqual(screen.zones, expected, "\(name) must show the same five zones in order")
        }
        // Only the contents differ — and each state does say something different.
        XCTAssertEqual(workingModel.strip.kind, .empty)
        XCTAssertEqual(restingModel.strip.kind, .resting)
        XCTAssertEqual(timedModel.strip.kind, StatusStrip.Kind.timed)
        XCTAssertEqual(blockModel.strip.kind, .blockDone)
        // The completed session is the one state the workout screen does not own.
        XCTAssertNil(model(session: working.session, phase: .completed))
    }

    // O51: logging during rest logs the set, ends the rest, and cancels its notification.
    func testLogSetDuringRestEndsTheRest() throws {
        var engine = CoreTestSupport.engine(CoreTestSupport.plan(sets: 3))
        engine.apply(.logSet(step: 0, result: .reps(count: 10, weight: 60)), now: now)
        guard case let .resting(rest) = engine.phase else { return XCTFail("expected a rest") }
        XCTAssertEqual(rest.nextStep, 1)

        // The primary button reads "Log set" throughout the rest, and acts on the next step.
        let resting = try XCTUnwrap(WorkoutScreen.model(active: engine.active, history: [],
                                                        now: now.addingTimeInterval(30)))
        XCTAssertEqual(resting.primary, PrimaryAction(title: "Log set", kind: .log))
        XCTAssertEqual(resting.step, 1)

        let effects = engine.apply(.logSet(step: 1, result: .reps(count: 9, weight: 60)),
                                   now: now.addingTimeInterval(30))
        XCTAssertEqual(engine.session.steps[1].status, .logged)
        XCTAssertTrue(effects.contains(.cancelNotification(id: AlertIdentifier.rest)),
                      "the rest that was interrupted must not fire later")
        guard case let .resting(next) = engine.phase else { return XCTFail("the next rest starts") }
        XCTAssertEqual(next.nextStep, 2, "the rest that follows belongs to the set just logged")
    }

    // O52: undo returns the row to pending and hands back what it held, so the inputs refill.
    @MainActor func testUndoRestoresTheRowAndTheInputs() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let recorder = RecordingAlerts()
        let model = AppModel(store: Store(root: root), scheduler: recorder, alerts: recorder,
                             sampleJSON: { nil })
        await model.load()
        let plan = try XCTUnwrap(model.runImport(CoreTestSupport.planJSON()).plan)
        await model.save(plan, makeActive: true)
        try await model.startDay(planId: try XCTUnwrap(model.activePlanId), dayIndex: 0, now: now)

        await model.apply(.logSet(step: 0, result: .reps(count: 11, weight: 62.5)), now: now)
        XCTAssertTrue(model.canUndo)
        recorder.reset()

        await model.undoLast(now: now.addingTimeInterval(4))
        XCTAssertEqual(model.restoredInputs, .reps(count: 11, weight: 62.5),
                       "the inputs come back holding what was just taken away")
        XCTAssertEqual(model.session?.steps[0].status, .pending)
        XCTAssertNil(model.session?.steps[0].result)
        XCTAssertFalse(model.canUndo, "one undo, not a stack")
        XCTAssertEqual(model.phase, .working(step: 0))
        XCTAssertTrue(recorder.cancelled.contains(AlertIdentifier.rest),
                      "the rest that the undone set started is cancelled (G56)")

        // Taking them clears them: a later reload of the same step prefills normally.
        XCTAssertEqual(model.takeRestoredInputs(), .reps(count: 11, weight: 62.5))
        XCTAssertNil(model.takeRestoredInputs())

        // And the strip offers Undo only while it would work.
        let active = try XCTUnwrap(model.engine?.active)
        XCTAssertNil(WorkoutScreen.model(active: active, history: [], now: now)?.strip.undo)
    }

    // O54: minimize and come back — same step, same inputs, rest remaining read from the clock.
    @MainActor func testResumeRestoresStepInputsAndRemainingRest() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let model = AppModel(store: Store(root: root), scheduler: RecordingAlerts(),
                             alerts: RecordingAlerts(), sampleJSON: { nil })
        await model.load()
        let plan = try XCTUnwrap(model.runImport(CoreTestSupport.planJSON()).plan)
        await model.save(plan, makeActive: true)
        try await model.startDay(planId: try XCTUnwrap(model.activePlanId), dayIndex: 0, now: now)
        await model.apply(.logSet(step: 0, result: .reps(count: 10, weight: 60)), now: now)
        let before = try XCTUnwrap(WorkoutScreen.model(active: try XCTUnwrap(model.engine?.active),
                                                       history: model.sessions,
                                                       now: now.addingTimeInterval(20)))

        // A relaunch is the strongest form of "minimize": nothing is kept in memory.
        let resumed = AppModel(store: Store(root: root), scheduler: RecordingAlerts(),
                               alerts: RecordingAlerts(), sampleJSON: { nil })
        await resumed.load()
        let after = try XCTUnwrap(WorkoutScreen.model(active: try XCTUnwrap(resumed.engine?.active),
                                                      history: resumed.sessions,
                                                      now: now.addingTimeInterval(20)))
        XCTAssertEqual(after.step, before.step)
        XCTAssertEqual(after.inputs, before.inputs)
        XCTAssertEqual(after.strip.countdown, before.strip.countdown)
        XCTAssertEqual(after.strip.countdown, "1:10", "90 s of rest, 20 s gone — derived, not counted")

        // Away for longer than the rest: the strip reports the overrun rather than freezing at 0.
        let late = try XCTUnwrap(WorkoutScreen.model(active: try XCTUnwrap(resumed.engine?.active),
                                                     history: resumed.sessions,
                                                     now: now.addingTimeInterval(102)))
        XCTAssertEqual(late.strip.kind, .restOver)
        XCTAssertEqual(late.strip.countdown, "+0:12")
        XCTAssertEqual(late.strip.title, "Rest over")
    }

    // O57: the current exercise's rows — done, current, upcoming, skipped, and superset rounds.
    // Since v1.10 (D81) the Workout screen draws dots and a card; the rows are Core's, pinned here.
    func testSetRowsDescribeTheCurrentExercise() throws {
        let history = [CoreTestSupport.completed([10, 10, 9])]
        var engine = CoreTestSupport.engine(CoreTestSupport.plan(sets: 3, secondExercise: true))
        engine.apply(.logSet(step: 0, result: .reps(count: 11, weight: 62.5)), now: now)
        engine.apply(.skipSet(step: 1), now: now.addingTimeInterval(60))

        let screen = try XCTUnwrap(WorkoutScreen.model(active: engine.active, history: history,
                                                       now: now.addingTimeInterval(60)))
        let rows = StepCard.setRows(session: engine.session, step: screen.step, history: history)
        XCTAssertEqual(rows.count, 3, "only this exercise's sets, not the whole day")
        XCTAssertEqual(rows.map(\.status), [.logged, .skipped, .pending])
        XCTAssertEqual(rows.map(\.isCurrent), [false, false, true])
        XCTAssertEqual(rows[0].value, "11 × 62.5",
                       "D19: the row says what was lifted, not how long it took")
        XCTAssertEqual(rows[1].value, "skipped")
        XCTAssertEqual(rows[2].value, "Aim 8–12 reps · 60 kg", "an upcoming row shows its target")
        // D58 (v1.6): the row's second line is a sentence, and it carries its unit.
        XCTAssertEqual(rows[2].lastTime, "Last time 9 × 60 kg",
                       "the current row says what to beat")
        XCTAssertEqual(screen.progress, "Exercise 1 of 2 · Set 3 of 3")

        // The exercise's notes belong to the exercise's own line, once — not to each of its rows.
        let target = SetTarget(work: .reps(.range(min: 8, max: 12)), weight: 80, restSeconds: 90)
        let noted = Plan(name: "Noted", units: .kg, schedule: .rotation,
                         days: [Day(name: "Push", exercises: [
                            Exercise(name: "Bench Press", notes: "Pause on chest",
                                     repRange: RepRange(min: 8, max: 12),
                                     sets: Array(repeating: target, count: 3))])],
                         importedAt: now, sourceText: "", cycle: [.day(0)])
        let notedEngine = SessionEngine(session: CoreTestSupport.session(noted), settings: CoreTestSupport.classic, now: now)
        let withNotes = try XCTUnwrap(WorkoutScreen.model(active: notedEngine.active, history: [], now: now))
        XCTAssertEqual(StepCard.targetLine(session: notedEngine.session, step: withNotes.step),
                       "Aim 8–12 reps · 80 kg · Pause on chest")
        XCTAssertEqual(withNotes.notes, "Pause on chest", "and on the screen, behind the ? (D81)")
        XCTAssertEqual(StepCard.setRows(session: notedEngine.session, step: withNotes.step, history: []).map(\.value), Array(repeating: "Aim 8–12 reps · 80 kg", count: 3),
                       "four rows repeating the same note is noise, not information")

        // A superset lists the round in front of you, not every round of the block.
        let grouped = CoreTestSupport.engine(CoreTestSupport.plan(sets: 2, secondExercise: true,
                                                                  group: "A"))
        let round = try XCTUnwrap(WorkoutScreen.model(active: grouped.active, history: [], now: now))
        let roundRows = StepCard.setRows(session: grouped.session, step: round.step, history: [])
        XCTAssertEqual(roundRows.count, 2)
        XCTAssertEqual(round.progress, "Round 1 of 2 · Bench Press")
        // Both rows of a superset round would otherwise read "A · Set 1 of 2" and be
        // indistinguishable, which is the defect M5 fixed in the Overview and R2 must not
        // reintroduce on the screen you are actually working from.
        XCTAssertEqual(roundRows.map(\.label), ["Bench Press · Set 1 of 2", "Row · Set 1 of 2"])
        // A straight exercise keeps the plain line: there is nothing to disambiguate.
        XCTAssertEqual(rows.map(\.label),
                       ["Set 1 of 3", "Set 2 of 3", "Set 3 of 3"])
    }

    // O58: a whole multi-exercise day runs through with no Continue gate anywhere (D14).
    func testAWholeDayNeedsNoContinueTaps() throws {
        var exercises: [Exercise] = []
        for name in ["Bench Press", "Row", "Squat", "Curl", "Plank", "Calf Raise"] {
            let target = SetTarget(work: .reps(.range(min: 8, max: 12)), weight: 50, restSeconds: 60)
            exercises.append(Exercise(name: name, repRange: RepRange(min: 8, max: 12),
                                      sets: Array(repeating: target, count: 2)))
        }
        let plan = Plan(name: "Big", units: .kg, schedule: .rotation,
                        days: [Day(name: "Everything", exercises: exercises)],
                        importedAt: now, sourceText: "", cycle: [.day(0)])
        var engine = SessionEngine(session: CoreTestSupport.session(plan), settings: CoreTestSupport.classic, now: now)
        XCTAssertEqual(engine.session.steps.count, 12)

        var clock = now
        var phasesSeen: Set<String> = []
        var stepsLogged = 0
        // Bounded by construction: a failed assertion does not break a `while`, and a workout
        // that cannot finish must fail the test rather than hang the suite.
        for _ in 0..<200 where engine.phase != .completed {
            clock = clock.addingTimeInterval(30)
            switch engine.phase {
            case let .working(index):
                phasesSeen.insert("working")
                engine.apply(.logSet(step: index, result: .reps(count: 12, weight: 50)), now: clock)
                stepsLogged += 1
            case .resting:
                phasesSeen.insert("resting")
                engine.apply(.skipRest, now: clock)
            case .completed:
                break
            }
        }
        XCTAssertEqual(engine.phase, .completed, "the day must actually finish")
        XCTAssertEqual(stepsLogged, 12, "every set logged, and nothing else was ever required")
        XCTAssertEqual(phasesSeen, ["working", "resting"],
                       "no third phase exists to tap through between exercises")
        XCTAssertEqual(engine.session.steps.filter { $0.status == .logged }.count, 12)
    }

    // O59: the log haptic is played once per logged set, and for nothing else.
    @MainActor func testLoggedFeedbackIsPlayedOncePerSet() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let recorder = RecordingAlerts()
        let model = AppModel(store: Store(root: root), scheduler: recorder, alerts: recorder,
                             sampleJSON: { nil })
        await model.load()
        let plan = try XCTUnwrap(model.runImport(CoreTestSupport.planJSON()).plan)
        await model.save(plan, makeActive: true)
        try await model.startDay(planId: try XCTUnwrap(model.activePlanId), dayIndex: 0, now: now)

        await model.apply(.logSet(step: 0, result: .reps(count: 10, weight: 60)), now: now)
        XCTAssertEqual(recorder.feedback, [.logged])
        await model.apply(.skipRest, now: now.addingTimeInterval(10))
        await model.apply(.logSet(step: 1, result: .reps(count: 9, weight: 60)), now: now.addingTimeInterval(10))
        XCTAssertEqual(recorder.feedback, [.logged, .logged])

        // Not for an edit, not for a skip, and not for an input the engine refused.
        await model.apply(.editSet(step: 0, result: .reps(count: 11, weight: 60)), now: now)
        await model.apply(.skipSet(step: 2), now: now)
        await model.apply(.logSet(step: 99, result: .reps(count: 8, weight: 60)), now: now)
        XCTAssertEqual(recorder.feedback, [.logged, .logged])

        // And it is silent: the vibration setting alone gates it.
        await model.setVibration(false)
        recorder.reset()
        await model.apply(.logSet(step: 3, result: .reps(count: 8, weight: 60)), now: now)
        XCTAssertTrue(recorder.feedback.isEmpty)
    }

    // O61: the strip after a block ends names it, times it, carries the advice, and counts up.
    func testStripReportsTheFinishedBlock() throws {
        var engine = CoreTestSupport.engine(CoreTestSupport.plan(sets: 1, secondExercise: true))
        engine.apply(.logSet(step: 0, result: .reps(count: 12, weight: 60)),
                     now: now.addingTimeInterval(40))
        let screen = try XCTUnwrap(WorkoutScreen.model(active: engine.active, history: [],
                                                       now: now.addingTimeInterval(82)))
        XCTAssertEqual(screen.strip.kind, .blockDone)
        let title = try XCTUnwrap(screen.strip.title)
        XCTAssertTrue(title.hasPrefix("Bench Press done · 0:40"), title)
        XCTAssertTrue(title.contains("Try 62.5 kg next time"), title)
        XCTAssertEqual(screen.strip.detail, "moving on · 0:42")
        XCTAssertFalse(screen.strip.showsRestControls, "there is no rest to adjust between blocks")
        XCTAssertEqual(screen.strip.undo, "Set logged · Undo", "P3: still one tap back")
        // The next exercise is already the one on screen — that is the point of removing the gate.
        XCTAssertEqual(screen.exerciseName, "Row")
        XCTAssertEqual(screen.step, 1)

        // The next log clears it without anyone having to dismiss it.
        engine.apply(.logSet(step: 1, result: .reps(count: 10, weight: 60)), now: now.addingTimeInterval(120))
        XCTAssertNil(engine.active.blockDone)
    }

    // O62: a timed set uses the same bottom slot, and can be started straight out of a rest.
    func testTimedSetSharesTheOnePrimarySlot() throws {
        let fixed = CoreTestSupport.plan(sets: 1, work: .duration(seconds: 45))
        var engine = SessionEngine(session: CoreTestSupport.session(fixed), settings: CoreTestSupport.classic, now: now)
        var screen = try XCTUnwrap(WorkoutScreen.model(active: engine.active, history: [], now: now))
        XCTAssertEqual(screen.primary, PrimaryAction(title: "Start timer", kind: .startTimer))
        XCTAssertEqual(screen.timer?.text, "0:45", "the timer takes the reps slot")
        XCTAssertTrue(screen.inputs.showsWeight, "the weight row stays (SPEC §4.5)")

        engine.apply(.startTimer(step: 0), now: now)
        screen = try XCTUnwrap(WorkoutScreen.model(active: engine.active, history: [],
                                                   now: now.addingTimeInterval(41)))
        XCTAssertEqual(screen.primary, PrimaryAction(title: "Done", kind: .doneTimer))
        XCTAssertEqual(screen.timer?.text, "0:04")
        XCTAssertEqual(screen.timer?.accented, true, "past the warning point")

        // An open set stops rather than finishing, in the same slot.
        let open = CoreTestSupport.plan(sets: 1, work: .openDuration(minSeconds: 30))
        var openEngine = SessionEngine(session: CoreTestSupport.session(open), settings: CoreTestSupport.classic, now: now)
        XCTAssertEqual(WorkoutScreen.model(active: openEngine.active, history: [], now: now)?.timer?.minimumNote,
                       "30+ s")
        openEngine.apply(.startTimer(step: 0), now: now)
        XCTAssertEqual(WorkoutScreen.model(active: openEngine.active, history: [], now: now)?.primary,
                       PrimaryAction(title: "Stop", kind: .stopTimer))

        // D22: the second set of a timed exercise waits on the far side of a rest, and still
        // starts from the one button. Before v1.1 the engine accepted `startTimer` only while
        // already working, so the primary action would have been inert for the whole rest.
        var twoPlanks = SessionEngine(session: CoreTestSupport.session(
            CoreTestSupport.plan(sets: 2, work: .duration(seconds: 45))),
            settings: CoreTestSupport.classic, now: now)
        twoPlanks.apply(.startTimer(step: 0), now: now)
        twoPlanks.apply(.timerDone(step: 0), now: now.addingTimeInterval(45))
        guard case let .resting(rest) = twoPlanks.phase else { return XCTFail("expected a rest") }
        XCTAssertEqual(rest.nextStep, 1)
        XCTAssertEqual(WorkoutScreen.model(active: twoPlanks.active, history: [],
                                           now: now.addingTimeInterval(60))?.primary,
                       PrimaryAction(title: "Start timer", kind: .startTimer))
        let effects = twoPlanks.apply(.startTimer(step: 1), now: now.addingTimeInterval(60))
        XCTAssertEqual(twoPlanks.phase, .working(step: 1))
        XCTAssertTrue(twoPlanks.active.timerRunning)
        XCTAssertTrue(effects.contains(.cancelNotification(id: AlertIdentifier.rest)),
                      "the rest it cut short must not fire later")
        XCTAssertEqual(twoPlanks.session.steps[1].startedAt, now.addingTimeInterval(60),
                       "the set is timed from the tap, not from when the rest ended")
    }
}

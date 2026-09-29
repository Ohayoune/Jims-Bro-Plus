import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// V3 (v1.2) — Q21–Q30: the warm-up (D32), the rest between exercises (D33) and the stage the
/// header names (D34). All three came from the owner running v1.1 on the phone: the workout did
/// not say where you were in it, there was no warm-up, and the walk to the next machine was
/// given no time at all.
final class WarmUpAndTransitionTests: XCTestCase {
    private let now = CoreTestSupport.now
    /// Both v1.2 settings on, at v1.2's defaults: 5 min of warm-up, 2 min between exercises.
    /// (D57, v1.6: a fresh install now starts with the warm-up off, so it is said here.)
    private let settings = CoreTestSupport.warmUp

    private func engine(_ plan: Plan, _ settings: Settings? = nil) -> SessionEngine {
        CoreTestSupport.engine(plan, settings: settings ?? self.settings)
    }

    // MARK: - Warm-up (D32)

    // Q21: a session starts in a warm-up, not on set 1.
    func testASessionStartsInAWarmUp() throws {
        let engine = engine(CoreTestSupport.plan(sets: 3))
        guard case let .resting(rest) = engine.phase else {
            return XCTFail("expected a warm-up, got \(engine.phase)")
        }
        XCTAssertEqual(rest.kind, .warmUp)
        XCTAssertEqual(rest.nextStep, 0, "the warm-up runs before the first step")
        XCTAssertEqual(rest.endsAt, now.addingTimeInterval(300))
        // It schedules its own alert, like any other rest.
        XCTAssertTrue(engine.initialEffects.contains { effect in
            if case let .scheduleNotification(id, at, _) = effect {
                return id == .rest && at == rest.endsAt
            }
            return false
        })
        XCTAssertTrue(engine.initialEffects.contains(.persist))
    }

    // Q22: it is a rest in every mechanical sense — adjustable, skippable, and you may log
    // straight out of it, exactly as §4.6 says.
    func testTheWarmUpAdjustsSkipsAndLogsLikeAnyOtherRest() throws {
        var engine = engine(CoreTestSupport.plan(sets: 3))
        engine.apply(.adjustRest(seconds: -60), now: now)
        guard case let .resting(shorter) = engine.phase else { return XCTFail("still warming up") }
        XCTAssertEqual(shorter.endsAt, now.addingTimeInterval(240))
        XCTAssertEqual(shorter.kind, .warmUp, "adjusting must not change what kind of break it is")

        engine.apply(.skipRest, now: now.addingTimeInterval(30))
        XCTAssertEqual(engine.phase, .working(step: 0))

        // And from a fresh one, logging ends it and logs the set.
        var logging = self.engine(CoreTestSupport.plan(sets: 3))
        logging.apply(.logSet(step: 0, result: .reps(count: 10, weight: 60)),
                      now: now.addingTimeInterval(20))
        XCTAssertEqual(logging.session.steps[0].status, .logged)
    }

    // Q23: a warm-up that runs out becomes the first set, and nothing was logged by it.
    func testTheWarmUpEndsIntoTheFirstSet() {
        var engine = engine(CoreTestSupport.plan(sets: 3))
        let effects = engine.apply(.restElapsed, now: now.addingTimeInterval(300))
        XCTAssertEqual(engine.phase, .working(step: 0))
        XCTAssertTrue(effects.contains(.playAlert(.end)))
        XCTAssertEqual(SessionStats.loggedCount(engine.session), 0, "a warm-up is not a set")
        XCTAssertNil(engine.session.steps[0].result)
    }

    // Q24: warm-up off is v1.1 exactly.
    func testWarmUpOffStartsOnTheFirstSet() {
        let engine = engine(CoreTestSupport.plan(sets: 3), CoreTestSupport.classic)
        XCTAssertEqual(engine.phase, .working(step: 0))
        XCTAssertEqual(engine.initialEffects, [.persist], "nothing to schedule")
    }

    // MARK: - Between exercises (D33)

    // Q25: finishing a block starts a real countdown, and the next exercise is already up.
    func testFinishingABlockStartsTheBetweenExercisesRest() throws {
        var engine = engine(CoreTestSupport.plan(sets: 1, secondExercise: true),
                            Settings(warmUpSeconds: 0))
        engine.apply(.logSet(step: 0, result: .reps(count: 12, weight: 60)), now: now)
        guard case let .resting(rest) = engine.phase else {
            return XCTFail("expected a walk to the next exercise, got \(engine.phase)")
        }
        XCTAssertEqual(rest.kind, .betweenExercises)
        XCTAssertEqual(rest.endsAt, now.addingTimeInterval(120), "from the setting, not the set")
        XCTAssertEqual(rest.nextStep, 1)
        XCTAssertNotNil(engine.active.blockDone, "the strip still says which block finished")

        let screen = try XCTUnwrap(WorkoutScreen.model(active: engine.active, history: [],
                                                       now: now.addingTimeInterval(5)))
        XCTAssertEqual(screen.exerciseName, "Row", "the next exercise is already on screen")
        XCTAssertEqual(screen.strip.restKind, .betweenExercises)
        // D82 (v1.10): the walk counts up beside a ring and has no −30 / +30 / Skip.
        XCTAssertFalse(screen.strip.showsRestControls, "v1.2–v1.9: −30 / +30 / Skip, like any other rest")
        XCTAssertEqual(screen.strip.countdown, "0:05", "v1.2–v1.9: 1:55, counting down")
        XCTAssertEqual(screen.strip.direction, .up)
        XCTAssertEqual(screen.strip.ring?.minimum, 120)
        XCTAssertEqual(screen.strip.next, "Row", "v1.10: the next exercise, beside the walk")
        XCTAssertEqual(try XCTUnwrap(screen.strip.title).hasPrefix("Bench Press done"), true,
                       "and it still says what just finished, to VoiceOver")
    }

    // Q26: a *skipped* set that ends a block still gets the walk. Skipping the set does not
    // move the next machine any closer.
    func testASkippedSetStillGetsTheWalkButNotTheRest() {
        var engine = engine(CoreTestSupport.plan(sets: 2, secondExercise: true),
                            Settings(warmUpSeconds: 0))
        // Mid-block: a skipped set gets no rest, exactly as in v1.1.
        engine.apply(.skipSet(step: 0), now: now)
        XCTAssertEqual(engine.phase, .working(step: 1))
        // Ending the block: the walk happens either way.
        engine.apply(.skipSet(step: 1), now: now.addingTimeInterval(10))
        guard case let .resting(rest) = engine.phase else {
            return XCTFail("a skipped last set still ends the block")
        }
        XCTAssertEqual(rest.kind, .betweenExercises)
    }

    // Q27: set it to 0 and v1.1's behavior comes back — no countdown, the block-done strip with
    // its count-up instead; since v1.10 (D82) the count-up is the strip's figure and the ring
    // starts full.
    func testTransitionRestOffRestoresTheBlockDoneStrip() throws {
        var engine = engine(CoreTestSupport.plan(sets: 1, secondExercise: true),
                            CoreTestSupport.classic)
        engine.apply(.logSet(step: 0, result: .reps(count: 12, weight: 60)), now: now)
        XCTAssertEqual(engine.phase, .working(step: 1))
        let screen = try XCTUnwrap(WorkoutScreen.model(active: engine.active, history: [],
                                                       now: now.addingTimeInterval(42),
                                                       walk: engine.walk))
        XCTAssertEqual(screen.strip.kind, .blockDone)
        XCTAssertEqual(screen.strip.countdown, "0:42", "v1.1–v1.9: \"moving on · 0:42\" in small text")
        XCTAssertEqual(screen.strip.ring?.full, true)
        XCTAssertFalse(screen.strip.showsRestControls)
    }

    // Q28: a rest between sets is still resolved from the set, not from the setting.
    func testTheRestBetweenSetsIsUnchanged() {
        var engine = engine(CoreTestSupport.plan(sets: 3, rest: 90), Settings(warmUpSeconds: 0))
        engine.apply(.logSet(step: 0, result: .reps(count: 10, weight: 60)), now: now)
        guard case let .resting(rest) = engine.phase else { return XCTFail("expected a rest") }
        XCTAssertEqual(rest.kind, .betweenSets)
        XCTAssertEqual(rest.endsAt, now.addingTimeInterval(90))
    }

    // MARK: - The stage (D34)

    // Q29: the header says which stage the workout is in, in words, for every state.
    func testTheStageNamesEveryState() throws {
        var engine = engine(CoreTestSupport.plan(sets: 3, secondExercise: true))
        func stage() throws -> WorkoutStage {
            try XCTUnwrap(WorkoutScreen.model(active: engine.active, history: [], now: now)).stage
        }

        XCTAssertEqual(try stage(), .warmUp)
        XCTAssertEqual(try stage().title, "Warm-up")
        XCTAssertTrue(try stage().isBreak)

        engine.apply(.skipRest, now: now)
        XCTAssertEqual(try stage(), .working(exercise: 1, exercises: 2, set: 1, sets: 3))
        XCTAssertEqual(try stage().title, "Exercise 1 of 2 · Set 1 of 3")
        XCTAssertFalse(try stage().isBreak)

        engine.apply(.logSet(step: 0, result: .reps(count: 10, weight: 60)), now: now)
        XCTAssertEqual(try stage(), .resting)
        XCTAssertEqual(try stage().title, "Resting")

        engine.apply(.skipRest, now: now)
        engine.apply(.logSet(step: 1, result: .reps(count: 10, weight: 60)), now: now)
        engine.apply(.skipRest, now: now)
        engine.apply(.logSet(step: 2, result: .reps(count: 10, weight: 60)), now: now)
        XCTAssertEqual(try stage(), .betweenExercises)
        XCTAssertEqual(try stage().title, "Between exercises")
        XCTAssertTrue(try stage().isBreak)
    }

    // Q30: progress counts sets, so a long exercise moves the bar instead of sitting still.
    func testProgressCountsEverySetThatIsDone() {
        var engine = engine(CoreTestSupport.plan(sets: 4), Settings(warmUpSeconds: 0))
        XCTAssertEqual(WorkoutStage.progress(engine.session), 0)
        engine.apply(.logSet(step: 0, result: .reps(count: 10, weight: 60)), now: now)
        XCTAssertEqual(WorkoutStage.progress(engine.session), 0.25, accuracy: 0.001)
        engine.apply(.skipSet(step: 1), now: now)
        XCTAssertEqual(WorkoutStage.progress(engine.session), 0.5, accuracy: 0.001,
                       "a skipped set is done with, too")
        engine.apply(.finish, now: now)
        XCTAssertEqual(WorkoutStage.progress(engine.session), 1, accuracy: 0.001)
    }

    // Q31: a v1.1 active-session file has no rest kind; whatever it was holding was a rest
    // between sets, and it must still resume as one.
    func testAV1RestDecodesAsARestBetweenSets() throws {
        let data = Data("""
        {"startedAt":"2023-11-14T22:13:20.000Z","endsAt":"2023-11-14T22:14:50.000Z",
         "nextStep":2,"isWork":false}
        """.utf8)
        let rest = try StoreCoder.decoder.decode(RestState.self, from: data)
        XCTAssertEqual(rest.kind, .betweenSets)
        XCTAssertEqual(rest.nextStep, 2)
    }
}

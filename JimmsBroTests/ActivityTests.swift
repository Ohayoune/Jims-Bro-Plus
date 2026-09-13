import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// V7 (v1.2) — Q64–Q70: the Lock Screen and Dynamic Island activity of D40. "Could also have
/// the time appear at the lock screen at the top — and in the Dynamic Island."
///
/// ActivityKit lives in the widget extension, behind `ActivityPresenting`, exactly as
/// UserNotifications lives behind `NotificationScheduling` — so what the Island would show is
/// a unit test rather than something only a phone can answer.
final class ActivityTests: XCTestCase {
    private let now = CoreTestSupport.now

    /// v1.2's defaults — the warm-up on — which these states were written against. (D57,
    /// v1.6: a fresh install's warm-up is off, so it is said here.)
    private func engine(_ plan: Plan = CoreTestSupport.plan(sets: 3, secondExercise: true),
                        settings: Settings = Settings(warmUpSeconds: 300)) -> SessionEngine {
        SessionEngine(session: CoreTestSupport.session(plan), settings: settings, now: now)
    }

    // Q64: a warm-up is a countdown with the first exercise named under it.
    func testTheWarmUpIsShownAsACountdown() throws {
        let engine = engine()
        let state = try XCTUnwrap(WorkoutActivityState.of(engine.active, now: now))
        XCTAssertEqual(state.title, "Warm-up")
        XCTAssertTrue(state.isBreak)
        XCTAssertEqual(state.endsAt, now.addingTimeInterval(300))
        XCTAssertTrue(state.detail.hasPrefix("Bench Press · set 1 of 3"), state.detail)
        XCTAssertEqual(state.done, 0)
        XCTAssertEqual(state.total, engine.session.steps.count)
    }

    // Q65: working is the exercise's name and no countdown — there is nothing to count.
    func testWorkingShowsTheExerciseAndNoTimer() throws {
        var engine = engine(settings: CoreTestSupport.classic)
        let state = try XCTUnwrap(WorkoutActivityState.of(engine.active, now: now))
        XCTAssertEqual(state.title, "Bench Press")
        XCTAssertFalse(state.isBreak)
        XCTAssertNil(state.endsAt)
        XCTAssertNil(state.startedAt)

        // And logging moves both the progress and the title.
        engine.apply(.logSet(step: 0, result: .reps(count: 10, weight: 60)), now: now)
        let resting = try XCTUnwrap(WorkoutActivityState.of(engine.active, now: now))
        XCTAssertEqual(resting.title, "Rest")
        XCTAssertTrue(resting.isBreak)
        XCTAssertEqual(resting.endsAt, now.addingTimeInterval(90))
        XCTAssertEqual(resting.done, 1)
    }

    // Q66: a running timed set counts **up** from when it started, with no end when it is open.
    func testARunningTimedSetCountsUp() throws {
        var engine = engine(CoreTestSupport.plan(sets: 1, work: .openDuration(minSeconds: 30)),
                            settings: CoreTestSupport.classic)
        engine.apply(.startTimer(step: 0), now: now)
        let state = try XCTUnwrap(WorkoutActivityState.of(engine.active, now: now))
        XCTAssertEqual(state.startedAt, now)
        XCTAssertNil(state.endsAt, "an open hold has no end to count down to")

        // A fixed duration has both: it started then, and it ends there.
        var fixed = self.engine(CoreTestSupport.plan(sets: 1, work: .duration(seconds: 45)),
                                settings: CoreTestSupport.classic)
        fixed.apply(.startTimer(step: 0), now: now)
        let timed = try XCTUnwrap(WorkoutActivityState.of(fixed.active, now: now))
        XCTAssertEqual(timed.startedAt, now)
        XCTAssertEqual(timed.endsAt, now.addingTimeInterval(45))
    }

    // Q67: a finished workout has nothing to show.
    func testACompletedSessionHasNoActivity() {
        var engine = engine(settings: CoreTestSupport.classic)
        engine.apply(.finish, now: now)
        XCTAssertNil(WorkoutActivityState.of(engine.active, now: now))
    }

    // Q68: the app starts an activity when a workout starts, and ends it when it does.
    @MainActor func testTheAppStartsAndEndsTheActivity() async throws {
        let root = CoreTestSupport.makeRoot("V7Tests")
        defer { CoreTestSupport.discard(root) }
        let activities = RecordingActivities()
        let model = AppModel(store: Store(root: root), activities: activities,
                             sampleJSON: { nil }, practiceJSON: { nil })
        await model.load()
        // The launch reconciles the Lock Screen before anything else (D60); that end is U31's
        // subject, and counting it here would say nothing about the workout.
        activities.reset()
        await model.setWarmUp(0)

        let plan = try XCTUnwrap(PlanImport.run(try FixtureLoader.text("valid/single-day.json"),
                                                settings: model.settings, now: now).plan)
        await model.save(plan, makeActive: true)
        try await model.startDay(planId: plan.id, dayIndex: 0, now: now)
        XCTAssertEqual(activities.ends, 0)
        let started = try XCTUnwrap(activities.current)
        XCTAssertFalse(started.title.isEmpty)
        XCTAssertEqual(started.done, 0)

        await model.finish(now: now.addingTimeInterval(600))
        XCTAssertEqual(activities.ends, 1, "the activity ends when the workout does")
    }

    // Q69: a tick that changes nothing pushes nothing. A per-second timer that woke the system
    // sixty times a minute would cost battery for no new information.
    @MainActor func testAnUnchangedTickPushesNothing() async throws {
        let root = CoreTestSupport.makeRoot("V7Tests")
        defer { CoreTestSupport.discard(root) }
        let activities = RecordingActivities()
        let model = AppModel(store: Store(root: root), activities: activities,
                             sampleJSON: { nil }, practiceJSON: { nil })
        await model.load()
        let plan = try XCTUnwrap(PlanImport.run(try FixtureLoader.text("valid/single-day.json"),
                                                settings: model.settings, now: now).plan)
        await model.save(plan, makeActive: true)
        try await model.startDay(planId: plan.id, dayIndex: 0, now: now)
        let pushes = activities.shown.count

        for second in 1...5 { await model.tick(now: now.addingTimeInterval(Double(second))) }
        XCTAssertEqual(activities.shown.count, pushes,
                       "five seconds of a running countdown is not five updates")
    }

    // Q70: discarding a workout takes the activity off the Lock Screen too. A countdown for a
    // workout that no longer exists is worse than none.
    @MainActor func testDiscardingEndsTheActivity() async throws {
        let root = CoreTestSupport.makeRoot("V7Tests")
        defer { CoreTestSupport.discard(root) }
        let activities = RecordingActivities()
        let model = AppModel(store: Store(root: root), activities: activities,
                             sampleJSON: { nil }, practiceJSON: { nil })
        await model.load()
        activities.reset()  // the launch's own end (D60) is U31's subject, not this one's.
        let plan = try XCTUnwrap(PlanImport.run(try FixtureLoader.text("valid/single-day.json"),
                                                settings: model.settings, now: now).plan)
        await model.save(plan, makeActive: true)
        try await model.startDay(planId: plan.id, dayIndex: 0, now: now)
        await model.discardSession()
        XCTAssertEqual(activities.ends, 1)
    }

    // MARK: - D41 (v1.3): the Island is never wider than "59:59"

    // W1: a rest counts down from now to its end; one that has already run out is still a
    // one-second range, never an inverted one (which `Text(timerInterval:)` would crash on).
    func testACountdownIsBoundedBelowByOneSecond() throws {
        var engine = engine(settings: CoreTestSupport.classic)
        engine.apply(.logSet(step: 0, result: .reps(count: 10, weight: 60)), now: now)
        let state = try XCTUnwrap(WorkoutActivityState.of(engine.active, now: now))
        XCTAssertTrue(state.timerCountsDown)
        XCTAssertEqual(state.timerRange(now: now), now...now.addingTimeInterval(90))

        // Two minutes later the rest is over but the activity has not been told yet.
        let late = now.addingTimeInterval(120)
        let range = try XCTUnwrap(state.timerRange(now: late))
        XCTAssertEqual(range.lowerBound, late)
        XCTAssertEqual(range.upperBound, late.addingTimeInterval(1))
    }

    // W2: a count-up is cut at 59:59 rather than running to the end of time, which is what
    // let the compact Island reserve room for "999:59:59"; a working state has no timer.
    func testACountUpNeverReachesAnHour() throws {
        let plan = CoreTestSupport.plan(work: .openDuration(minSeconds: 30), weight: nil)
        var engine = engine(plan, settings: CoreTestSupport.classic)
        XCTAssertNil(try XCTUnwrap(WorkoutActivityState.of(engine.active, now: now)).timerRange(now: now))

        engine.apply(.startTimer(step: 0), now: now)
        let state = try XCTUnwrap(WorkoutActivityState.of(engine.active, now: now))
        XCTAssertFalse(state.timerCountsDown)
        let range = try XCTUnwrap(state.timerRange(now: now.addingTimeInterval(5)))
        XCTAssertEqual(range.lowerBound, now)
        XCTAssertEqual(range.upperBound, now.addingTimeInterval(3599))
        XCTAssertLessThan(range.upperBound.timeIntervalSince(range.lowerBound), 3600)
    }

    // MARK: - D60 (v1.6): an activity outlives the app that started it

    // U31: the defect the owner hit. A workout was running when the app was terminated — swiped
    // away, or reclaimed while the phone sat in a pocket through a long rest — so the activity
    // is still on the Lock Screen and in the Island, and the process that knew about it is gone.
    // The launch that follows owns nothing and must still end it; before D60 the only cure was
    // to delete the app.
    @MainActor func testALaunchEndsAnActivityLeftOverFromTheLastRun() async throws {
        let root = CoreTestSupport.makeRoot("V7Tests")
        defer { CoreTestSupport.discard(root) }
        let activities = RecordingActivities()
        let model = AppModel(store: Store(root: root), activities: activities,
                             sampleJSON: { nil }, practiceJSON: { nil })
        await model.load(now: now)

        XCTAssertNil(model.engine, "no workout was in progress")
        XCTAssertEqual(activities.ends, 1, "the launch asks for the end regardless of what it remembers")
        XCTAssertTrue(activities.shown.isEmpty)
        XCTAssertNil(model.shownActivity)
    }

    // U32: the other half of the same reconciliation — a workout that *is* still in progress
    // keeps its activity. The relaunch pushes the resumed state once; it does not end the
    // countdown the user is watching, and it does not start a second one beside it.
    @MainActor func testALaunchMidWorkoutResumesTheActivityInsteadOfEndingIt() async throws {
        let root = CoreTestSupport.makeRoot("V7Tests")
        defer { CoreTestSupport.discard(root) }
        let first = AppModel(store: Store(root: root), activities: RecordingActivities(),
                             sampleJSON: { nil }, practiceJSON: { nil })
        await first.load(now: now)
        let plan = try XCTUnwrap(PlanImport.run(try FixtureLoader.text("valid/single-day.json"),
                                                settings: first.settings, now: now).plan)
        await first.save(plan, makeActive: true)
        try await first.startDay(planId: plan.id, dayIndex: 0, now: now)

        // The app is killed here: no `finish`, no `discardSession`, just a new process.
        let activities = RecordingActivities()
        let relaunched = AppModel(store: Store(root: root), activities: activities,
                                  sampleJSON: { nil }, practiceJSON: { nil })
        await relaunched.load(now: now)

        XCTAssertNotNil(relaunched.engine, "the workout is resumed")
        XCTAssertEqual(activities.ends, 0, "the countdown the user is watching is not taken away")
        XCTAssertEqual(activities.shown.count, 1, "pushed once, not stacked")
        XCTAssertEqual(activities.current, relaunched.shownActivity)

        // And the launch push is the state of the workout on disk, not a stale one.
        let expected = try XCTUnwrap(WorkoutActivityState.of(try XCTUnwrap(relaunched.engine).active,
                                                             now: now))
        XCTAssertEqual(activities.current, expected)

        // A tick that changes nothing still does not push again: `force` is the launch only.
        await relaunched.refreshActivity(now: now)
        XCTAssertEqual(activities.shown.count, 1)
    }
}

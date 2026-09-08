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

    private func engine(_ plan: Plan = CoreTestSupport.plan(sets: 3, secondExercise: true),
                        settings: Settings = Settings()) -> SessionEngine {
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
        let plan = try XCTUnwrap(PlanImport.run(try FixtureLoader.text("valid/single-day.json"),
                                                settings: model.settings, now: now).plan)
        await model.save(plan, makeActive: true)
        try await model.startDay(planId: plan.id, dayIndex: 0, now: now)
        await model.discardSession()
        XCTAssertEqual(activities.ends, 1)
    }
}

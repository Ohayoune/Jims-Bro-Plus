import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// Z5 (v1.5) — D54: a goal per exercise. How close you are, the workout that reaches it, the
/// file, the backup, the prompt, and the words.
final class GoalTests: XCTestCase {
    private let now = CoreTestSupport.now

    private func goal(_ target: GoalTarget, name: String = "Bench Press", units: WeightUnit = .kg, by: Date? = nil) -> Goal {
        Goal(exerciseName: name, units: units, target: target, by: by, createdAt: now)
    }

    /// A completed Bench Press session with the given sets, at `weight`, `daysAgo`.
    private func done(_ reps: [Int], weight: Double, daysAgo: Int = 1) -> Session {
        CoreTestSupport.completed(reps, weights: reps.map { _ in weight }, plan: CoreTestSupport.plan(sets: reps.count, weight: weight),
                                  start: now.addingTimeInterval(-Double(daysAgo) * 86_400))
    }

    // Z26: progress — the best set that counts, and only sets at the goal's reps count for a
    // weight goal.
    func testProgress() {
        let hundred = goal(.weight(100, reps: 5))
        XCTAssertEqual(Goals.progress(hundred, sessions: []), GoalProgress(best: nil, fraction: 0, reached: false))

        let history = [done([5, 5, 5], weight: 80, daysAgo: 10), done([8, 8, 6], weight: 82.5, daysAgo: 3), done([3, 3, 3], weight: 95, daysAgo: 1)]
        let progress = Goals.progress(hundred, sessions: history)
        XCTAssertEqual(progress.best, "82.5 kg × 8", "95 kg for 3 is not the goal's 5")
        XCTAssertEqual(progress.fraction, 0.825, accuracy: 0.001)
        XCTAssertFalse(progress.reached)

        let met = Goals.progress(hundred, sessions: history + [done([5, 5, 4], weight: 100)])
        XCTAssertEqual(met.best, "100 kg × 5")
        XCTAssertEqual(met.fraction, 1)
        XCTAssertTrue(met.reached)

        // Other units never count (D10).
        XCTAssertNil(Goals.progress(goal(.weight(100, reps: 5), units: .lb), sessions: history).best)
        // Another exercise never counts.
        XCTAssertNil(Goals.progress(goal(.weight(100, reps: 5), name: "Squat"), sessions: history).best)

        // A hold, and reps.
        var hold = CoreTestSupport.session(CoreTestSupport.plan(sets: 2, work: .duration(seconds: 45), weight: nil, bodyweight: true), start: now.addingTimeInterval(-86_400))
        for index in hold.steps.indices {
            hold.steps[index].status = .logged
            hold.steps[index].result = .duration(seconds: 40 + index * 10, weight: nil)
            hold.steps[index].loggedAt = hold.startedAt.addingTimeInterval(Double(index) * 60)
        }
        hold.endedAt = hold.steps.last?.loggedAt
        let minute = goal(.seconds(60))
        let held = Goals.progress(minute, sessions: [hold])
        XCTAssertEqual(held.best, "0:50")
        XCTAssertEqual(held.fraction, 50.0 / 60, accuracy: 0.001)
        XCTAssertFalse(held.reached)
        let ten = goal(.reps(10))
        let reps = Goals.progress(ten, sessions: history)
        XCTAssertEqual(reps.best, "8 reps")
        XCTAssertEqual(reps.fraction, 0.8, accuracy: 0.001)
        XCTAssertTrue(Goals.meets(ten, .reps(count: 10, weight: nil)))
        XCTAssertFalse(Goals.meets(hundred, .reps(count: 5, weight: 97.5)))
        XCTAssertTrue(Goals.meets(hundred, .reps(count: 6, weight: 102.5)))
    }

    // Z27: the workout that reaches a goal marks it, once, through the model; the Summary can
    // name it; and it is on disk.
    @MainActor func testTheWorkoutThatReachesIt() async throws {
        let root = CoreTestSupport.makeRoot("Goals")
        defer { CoreTestSupport.discard(root) }
        let model = AppModel(store: Store(root: root))
        await model.load()
        XCTAssertTrue(model.goals.isEmpty)
        await model.setWarmUp(0)
        await model.setTransitionRest(0)
        let plan = CoreTestSupport.plan(sets: 2, weight: 60)
        await model.save(plan, makeActive: true)
        let target = goal(.weight(60, reps: 8))
        let far = goal(.weight(200, reps: 1))
        let pounds = goal(.weight(60, reps: 8), units: .lb)
        await model.addGoal(target)
        await model.addGoal(far)
        await model.addGoal(pounds)
        XCTAssertEqual(model.goals.count, 3)
        XCTAssertNil(model.saveFailure)

        try await model.startDay(planId: plan.id, dayIndex: 0, now: now)
        var clock = now
        while let phase = model.phase, phase != .completed, let step = model.currentStep {
            if case .resting = phase { await model.apply(.skipRest, now: clock); continue }
            await model.apply(.logSet(step: step, result: .reps(count: 8, weight: 60)), now: clock)
            clock = clock.addingTimeInterval(60)
        }
        await model.finish(now: clock)
        let session = try XCTUnwrap(model.sessions.first)
        let reached = model.goalsReached(by: session)
        XCTAssertEqual(reached.map(\.id), [target.id])
        XCTAssertEqual(model.goals[0].reachedAt, session.startedAt)
        XCTAssertNil(model.goals[1].reachedAt, "200 kg is a way off")
        XCTAssertNil(model.goals[2].reachedAt, "pounds never count against kilos")
        XCTAssertEqual(Goals.reachedLine(reached[0]), "Goal reached: Bench Press 60 kg × 8")
        XCTAssertEqual(Goals.line(model.goals[0], progress: model.goalProgress(model.goals[0])), "60 kg × 8 · reached \(Goals.short(session.startedAt))")

        // Reached stays reached, and a later workout is not credited.
        try await model.startDay(planId: plan.id, dayIndex: 0, now: clock.addingTimeInterval(86_400))
        clock = clock.addingTimeInterval(86_400)
        while let phase = model.phase, phase != .completed, let step = model.currentStep {
            if case .resting = phase { await model.apply(.skipRest, now: clock); continue }
            await model.apply(.logSet(step: step, result: .reps(count: 10, weight: 62.5)), now: clock)
            clock = clock.addingTimeInterval(60)
        }
        await model.finish(now: clock)
        XCTAssertEqual(model.goals[0].reachedSessionId, session.id)
        XCTAssertTrue(model.goalsReached(by: try XCTUnwrap(model.sessions.last)).isEmpty)

        // On disk, and back on relaunch.
        let relaunched = AppModel(store: Store(root: root))
        await relaunched.load()
        XCTAssertEqual(relaunched.goals, model.goals)
        await relaunched.removeGoal(far.id)
        XCTAssertEqual(relaunched.goals.count, 2)
        let again = AppModel(store: Store(root: root))
        await again.load()
        XCTAssertEqual(again.goals.map(\.id), [target.id, pounds.id])
        XCTAssertEqual(again.exerciseNames.first, "Bench Press")
        await again.deleteAllData()
        XCTAssertTrue(again.goals.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("goals.json").path))
    }

    // Z28: the file's decoder, and the backup — which carries goals, restores without them, and
    // merges by id.
    @MainActor func testTheFileAndTheBackup() async throws {
        let sparse = Data(#"{ "fileVersion": 1, "exerciseName": "Bench Press", "units": "kg", "target": { "weight": { "_0": 100, "reps": 5 } } }"#.utf8)
        let decoded = try StoreCoder.decode(Goal.self, from: sparse)
        XCTAssertEqual(decoded.target, .weight(100, reps: 5))
        XCTAssertNil(decoded.by)
        XCTAssertNil(decoded.reachedAt)
        XCTAssertEqual(decoded.createdAt, Date(timeIntervalSince1970: 0))
        let full = goal(.seconds(60), by: now.addingTimeInterval(30 * 86_400))
        XCTAssertEqual(try StoreCoder.decode(Goal.self, from: try StoreCoder.encode(full)), full)

        let root = CoreTestSupport.makeRoot("GoalsBackup")
        defer { CoreTestSupport.discard(root) }
        let model = AppModel(store: Store(root: root))
        await model.load()
        await model.addGoal(full)
        let exported = await model.store.exportData(appVersion: "test", now: now)
        let backup = try XCTUnwrap(exported)
        let document = try StoreCoder.decoder.decode(ExportDocument.self, from: backup)
        XCTAssertEqual(document.goals, [full])

        // Restored elsewhere: replace takes them, merge adds only what is new.
        let other = CoreTestSupport.makeRoot("GoalsRestore")
        defer { CoreTestSupport.discard(other) }
        let target = AppModel(store: Store(root: other))
        await target.load()
        let mine = goal(.reps(10))
        await target.addGoal(mine)
        try await target.store.restore(document, mode: .merge)
        await target.load()
        XCTAssertEqual(target.goals.map(\.id), [mine.id, full.id])
        try await target.store.restore(document, mode: .merge)
        await target.load()
        XCTAssertEqual(target.goals.count, 2, "the same backup twice adds nothing")
        try await target.store.restore(document, mode: .replaceAll)
        await target.load()
        XCTAssertEqual(target.goals, [full])

        // A backup written before goals existed restores with none.
        var old = document
        old.goals = nil
        let stripped = try StoreCoder.encoder.encode(old)
        XCTAssertFalse(String(decoding: stripped, as: UTF8.self).contains("\"goals\""))
        try await target.store.restore(try StoreCoder.decoder.decode(ExportDocument.self, from: stripped), mode: .replaceAll)
        await target.load()
        XCTAssertTrue(target.goals.isEmpty)
    }

    // Z29: the progression prompt carries the plan's unreached goals, and nothing when there
    // are none.
    func testThePromptCarriesTheGoals() {
        let plan = CoreTestSupport.plan(secondExercise: true)
        let bench = goal(.weight(100, reps: 5), by: now.addingTimeInterval(90 * 86_400))
        var reachedRow = goal(.reps(15), name: "Row")
        reachedRow.reachedAt = now
        let elsewhere = goal(.seconds(90), name: "Plank")
        let text = Prompts.progression(plan: plan, history: [], weeks: 4, includeHistory: false,
                                       settings: Settings(), now: now, mode: .performance,
                                       goals: [bench, reachedRow, elsewhere])
        XCTAssertTrue(text.contains("\nMY GOALS\n- Bench Press: 100 kg × 5 by "), text)
        XCTAssertFalse(text.contains("Row: 15"), "reached goals are done")
        XCTAssertFalse(text.contains("Plank"), "a goal for an exercise not in the plan is not the plan's business")
        XCTAssertTrue(text.contains("MY PLAN\nPush:\n- Bench Press: 3 × "), "the plan comes first")
        let none = Prompts.progression(plan: plan, history: [], weeks: 4, includeHistory: false, settings: Settings(), now: now)
        XCTAssertFalse(none.contains("MY GOALS"))
    }

    // Z30: the words.
    func testTheWords() {
        let by = CoreTestSupport.date(1, hour: 12)
        let weight = goal(.weight(100, reps: 5), by: by)
        XCTAssertEqual(Goals.targetText(weight), "100 kg × 5")
        XCTAssertEqual(Goals.line(weight, progress: GoalProgress(best: nil, fraction: 0, reached: false)), "100 kg × 5 · nothing logged yet · by 1 Sep")
        XCTAssertEqual(Goals.line(weight, progress: GoalProgress(best: "82.5 kg × 5", fraction: 0.825, reached: false)), "100 kg × 5 · best 82.5 kg × 5 · by 1 Sep")
        XCTAssertEqual(Goals.targetText(goal(.seconds(90))), "1:30")
        XCTAssertEqual(Goals.targetText(goal(.reps(1))), "1 rep")
        XCTAssertEqual(Goals.promptLine(weight), "- Bench Press: 100 kg × 5 by 2026-09-01")
        XCTAssertEqual(Goals.promptLine(goal(.reps(10), name: "Pull-Up")), "- Pull-Up: 10 reps")
    }
}

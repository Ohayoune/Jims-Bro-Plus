import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// Z4 (v1.5) — D53: steps you earn. A progression is a ladder of steps per exercise; a
/// workout that achieves the current step moves the exercise on, a miss repeats it, and the
/// calendar stops mattering. The calendar stays as a mode for the owner's "legacy" case.
final class StepProgressionTests: XCTestCase {
    private let now = CoreTestSupport.now
    private let calendar = CoreTestSupport.utc()
    private let settings = CoreTestSupport.classic

    /// Push: Bench 3 × 8–12 @ 60, Plank 3 × 45 s. Pull: Row 3 × 8–12 @ 50.
    private func plan() -> Plan {
        let bench = Exercise(name: "Bench Press", repRange: RepRange(min: 8, max: 12),
                             sets: Array(repeating: SetTarget(work: .reps(.range(min: 8, max: 12)), weight: 60, restSeconds: 90), count: 3))
        let plank = Exercise(name: "Plank", bodyweight: true,
                             sets: Array(repeating: SetTarget(work: .duration(seconds: 45), weight: nil, restSeconds: 45, warningBeepSeconds: 5), count: 3))
        let row = Exercise(name: "Row", repRange: RepRange(min: 8, max: 12),
                           sets: Array(repeating: SetTarget(work: .reps(.range(min: 8, max: 12)), weight: 50, restSeconds: 90), count: 3))
        return Plan(name: "PP", units: .kg, schedule: .rotation,
                    days: [Day(name: "Push", exercises: [bench, plank]), Day(name: "Pull", exercises: [row])],
                    importedAt: now, sourceText: "", cycle: [.day(0), .day(1)])
    }

    /// Bench climbs in four steps (a range, a weight, nothing, a heavier range); Plank in two;
    /// Row in one.
    private func progression(mode: ProgressionMode = .performance) -> Progression {
        Progression(startDate: calendar.startOfDay(for: now), weeks: 4, entries: [
            ProgressionEntry(dayName: "Push", exerciseName: "Bench Press", weeks: [
                ProgressionWeek(weight: 60, work: .reps(.range(min: 8, max: 10))),
                ProgressionWeek(weight: 62.5),
                ProgressionWeek(),
                ProgressionWeek(weight: 65, work: .reps(.range(min: 6, max: 8))),
            ]),
            ProgressionEntry(dayName: "Push", exerciseName: "Plank", weeks: [
                ProgressionWeek(work: .duration(seconds: 50)),
                ProgressionWeek(work: .duration(seconds: 60)),
            ]),
            ProgressionEntry(dayName: "Pull", exerciseName: "Row", weeks: [ProgressionWeek(weight: 52.5)]),
        ], mode: mode)
    }

    private func days(_ count: Int) -> Date { now.addingTimeInterval(Double(count) * 86_400) }

    /// A completed session of Push with every Bench set as given and every Plank held for
    /// `plankSeconds`, at `weight`.
    private func session(_ plan: Plan, bench reps: [Int], weight: Double = 60, plankSeconds: Int = 50,
                         skip: Set<Int> = []) throws -> Session {
        var s = try XCTUnwrap(Session.start(plan: plan, dayIndex: 0, now: now, calendar: calendar))
        for index in s.steps.indices {
            let step = s.steps[index]
            if skip.contains(index) { s.steps[index].status = .skipped; continue }
            s.steps[index].status = .logged
            s.steps[index].result = step.exerciseIndex == 0
                ? .reps(count: reps[step.setIndex], weight: weight)
                : .duration(seconds: plankSeconds, weight: nil)
            s.steps[index].loggedAt = now.addingTimeInterval(Double(index) * 60)
        }
        s.endedAt = s.steps.last?.loggedAt
        return s
    }

    // Z18: where each exercise is, in performance mode, does not depend on the date.
    func testStepsDoNotDependOnTheDate() {
        var p = progression()
        XCTAssertEqual(p.stepIndex(for: p.entries[0], on: now, calendar: calendar), 0)
        XCTAssertEqual(p.stepIndex(for: p.entries[0], on: days(100), calendar: calendar), 0, "the calendar has nothing to say")
        XCTAssertEqual(p.currentStep(on: days(100), calendar: calendar), 0)
        XCTAssertFalse(p.isFinished(on: days(100), calendar: calendar))
        XCTAssertEqual(ProgressionText.status(p, on: days(100), calendar: calendar), "Step 1 of 4")

        p.entries[0].step = 2
        p.entries[1].step = 1
        XCTAssertEqual(p.stepIndex(for: p.entries[0], on: now, calendar: calendar), 2)
        XCTAssertEqual(p.currentStep(dayName: "Push", on: now, calendar: calendar), 1, "the lowest among the day's exercises")
        XCTAssertEqual(p.currentStep(dayName: "Pull", on: now, calendar: calendar), 0)
        XCTAssertEqual(ProgressionText.status(p, on: now, calendar: calendar), "Step 1 of 4")

        p.entries[1].step = 2
        XCTAssertNil(p.stepIndex(for: p.entries[1], on: now, calendar: calendar), "past its last step")
        XCTAssertNil(p.currentStep(dayName: "Push", on: now, calendar: calendar).flatMap { $0 == 2 ? nil : $0 })
        XCTAssertFalse(p.isFinished(on: now, calendar: calendar), "Bench and Row are still climbing")
        p.entries[0].step = 4
        p.entries[2].step = 1
        XCTAssertTrue(p.isFinished(on: now, calendar: calendar))
        XCTAssertEqual(ProgressionText.status(p, on: now, calendar: calendar), "Finished")

        // The calendar mode is what it was in v1.3.
        let c = progression(mode: .calendar)
        XCTAssertEqual(c.stepIndex(for: c.entries[0], on: days(8), calendar: calendar), 1)
        XCTAssertEqual(ProgressionText.status(c, on: days(8), calendar: calendar), "Week 2 of 4")
        XCTAssertTrue(c.isFinished(on: days(28), calendar: calendar))
    }

    // Z19: each entry's own step is applied, a `{}` step still counts, and the session says
    // which step each exercise carried.
    func testEachExerciseCarriesItsOwnStep() throws {
        var plan = plan()
        var p = progression()
        p.entries[0].step = 1
        plan.progression = p
        let applied = p.apply(to: plan.days[0], on: now, calendar: calendar)
        XCTAssertEqual(applied.steps, [0: 2, 1: 1])
        XCTAssertEqual(applied.day.exercises[0].sets.map(\.weight), [62.5, 62.5, 62.5])
        XCTAssertEqual(applied.day.exercises[1].sets.map(\.work), Array(repeating: .duration(seconds: 50), count: 3))

        let session = try XCTUnwrap(Session.start(plan: plan, dayIndex: 0, now: days(100), calendar: calendar))
        XCTAssertEqual(session.exercises[0].progressionWeek, 2)
        XCTAssertEqual(session.exercises[1].progressionWeek, 1)
        XCTAssertEqual(session.progressionWeek, 1, "the lowest")
        XCTAssertEqual(session.progressionWeeks, 4)
        XCTAssertEqual(session.progressionMode, .performance)
        XCTAssertEqual(ProgressionText.weekLine(session), "step 1 of 4")

        // The `{}` step: the plan's own targets, and the exercise still on the ladder.
        p.entries[0].step = 2
        plan.progression = p
        let plain = try XCTUnwrap(Session.start(plan: plan, dayIndex: 0, now: now, calendar: calendar))
        XCTAssertEqual(plain.exercises[0].progressionWeek, 3)
        XCTAssertEqual(plain.exercises[0].targets.map(\.weight), [60, 60, 60])
        // In calendar mode a `{}` week touches nothing, as in v1.3 (W33).
        var c = plan
        c.progression = progression(mode: .calendar)
        let week3 = try XCTUnwrap(Session.start(plan: c, dayIndex: 0, now: days(15), calendar: calendar))
        XCTAssertNil(week3.exercises[0].progressionWeek)
        XCTAssertNil(week3.progressionMode, "nothing applied, nothing recorded")

        // Past the last step: the plan's own targets, nothing stamped.
        p.entries[0].step = 4
        p.entries[1].step = 2
        plan.progression = p
        let done = try XCTUnwrap(Session.start(plan: plan, dayIndex: 0, now: now, calendar: calendar))
        XCTAssertNil(done.progressionWeek)
        XCTAssertEqual(done.exercises[0].targets.map(\.weight), [60, 60, 60])
    }

    // Z20: what counts as achieving a step.
    func testWhatCountsAsAchieved() throws {
        var plan = plan()
        plan.progression = progression()   // step 1: Bench 3 × 8–10 @ 60, Plank 3 × 50 s
        func bench(_ s: Session) -> Bool { ProgressionSteps.achieved(exercise: s.exercises[0], steps: s.steps.filter { $0.exerciseIndex == 0 }) }
        func plank(_ s: Session) -> Bool { ProgressionSteps.achieved(exercise: s.exercises[1], steps: s.steps.filter { $0.exerciseIndex == 1 }) }

        XCTAssertTrue(bench(try session(plan, bench: [10, 10, 10])))
        XCTAssertTrue(bench(try session(plan, bench: [10, 10, 9])), "one rep short across the exercise is within the tolerance")
        XCTAssertFalse(bench(try session(plan, bench: [10, 9, 9])), "two short is not")
        XCTAssertTrue(bench(try session(plan, bench: [12, 12, 8])), "the tolerance is across the exercise")
        XCTAssertFalse(bench(try session(plan, bench: [10, 10, 10], weight: 57.5)), "lighter than the step")
        XCTAssertTrue(bench(try session(plan, bench: [10, 10, 10], weight: 62.5)), "heavier is fine")
        XCTAssertFalse(bench(try session(plan, bench: [10, 10, 10], skip: [2])), "a skipped set is a miss")
        XCTAssertTrue(plank(try session(plan, bench: [10, 10, 10], plankSeconds: 50)))
        XCTAssertFalse(plank(try session(plan, bench: [10, 10, 10], plankSeconds: 45)), "a hold short of its seconds")

        // AMRAP with a minimum, and an open hold with one.
        var amrap = CoreTestSupport.plan(work: .reps(.amrap(min: 12)), weight: nil, bodyweight: true)
        amrap.days[0].exercises[0].repRange = nil
        var s = try XCTUnwrap(Session.start(plan: amrap, dayIndex: 0, now: now))
        for index in s.steps.indices { s.steps[index].status = .logged; s.steps[index].result = .reps(count: 12, weight: nil) }
        XCTAssertTrue(ProgressionSteps.achieved(exercise: s.exercises[0], steps: s.steps))
        s.steps[0].result = .reps(count: 10, weight: nil)
        XCTAssertFalse(ProgressionSteps.achieved(exercise: s.exercises[0], steps: s.steps))
        XCTAssertFalse(ProgressionSteps.achieved(exercise: s.exercises[0], steps: []), "nothing done is nothing achieved")
    }

    // Z21: a completed workout moves the exercises it achieved, repeats the rest, and never
    // touches an entry the session was not at; the calendar mode never moves by performance.
    @MainActor func testACompletedWorkoutMovesTheStep() async throws {
        let root = CoreTestSupport.makeRoot("Steps")
        defer { CoreTestSupport.discard(root) }
        let model = AppModel(store: Store(root: root))
        await model.load()
        var plan = plan()
        plan.progression = progression()
        await model.save(plan, makeActive: true)
        await model.setWarmUp(0)
        await model.setTransitionRest(0)

        // Push, hitting Bench and missing the Plank.
        try await model.startDay(planId: plan.id, dayIndex: 0, now: now)
        XCTAssertEqual(model.session?.exercises[0].progressionWeek, 1)
        var clock = now
        while let phase = model.phase, phase != .completed, let step = model.currentStep {
            if case .resting = phase { await model.apply(.skipRest, now: clock); continue }
            let exercise = model.session?.steps[step].exerciseIndex
            if exercise == 0 {
                await model.apply(.logSet(step: step, result: .reps(count: 10, weight: 60)), now: clock)
            } else {
                await model.apply(.startTimer(step: step), now: clock)
                clock = clock.addingTimeInterval(40)
                await model.apply(.timerDone(step: step), now: clock)
            }
            clock = clock.addingTimeInterval(60)
            if model.blockDone != nil { await model.apply(.dismissBlockDone, now: clock) }
        }
        await model.finish(now: clock)
        let after = try XCTUnwrap(model.plans.first?.progression)
        XCTAssertEqual(after.entries[0].step, 1, "Bench moved on")
        XCTAssertEqual(after.entries[0].tries, 0)
        XCTAssertEqual(after.entries[1].step, 0, "the Plank was held for 40 s of 50")
        XCTAssertEqual(after.entries[1].tries, 1)
        XCTAssertEqual(after.entries[2].step, 0, "Pull was not trained")
        XCTAssertEqual(ProgressionText.entryStatus(after.entries[1], of: 4), "Step 1 of 4 · 1 try")
        XCTAssertEqual(HomeStart.current(library: model.library, now: now.addingTimeInterval(86_400), calendar: calendar).subtitle?.contains("step 1 of 4"), true,
                       "the day is at its lowest exercise's step")

        // It reached the disk.
        let relaunched = AppModel(store: Store(root: root))
        await relaunched.load()
        XCTAssertEqual(relaunched.plans.first?.progression?.entries.map(\.step), [1, 0, 0])
        XCTAssertEqual(relaunched.plans.first?.progression?.mode, .performance)

        // A session stamped at a step the entry has already left changes nothing.
        var stale = try session(plan, bench: [10, 10, 10])
        stale.exercises[0].progressionWeek = 1
        var moved = after
        ProgressionSteps.advance(&moved, after: stale)
        XCTAssertEqual(moved.entries[0].step, 1, "Bench is on step 2 now; a step-1 session is history")
        // A substitute (D42) has no entry and moves nothing.
        var substituted = try session(plan, bench: [10, 10, 10])
        substituted.exercises[0].name = "Dumbbell Press"
        substituted.exercises[0].progressionWeek = 2
        ProgressionSteps.advance(&moved, after: substituted)
        XCTAssertEqual(moved.entries[0].step, 1)
        // The calendar never moves by performance.
        var byCalendar = progression(mode: .calendar)
        XCTAssertEqual(ProgressionSteps.advance(&byCalendar, after: try session(plan, bench: [12, 12, 12])), [])
        XCTAssertEqual(byCalendar.entries.map(\.step), [0, 0, 0])
    }

    // Z22: the reply in steps, the alias for weeks, the mode from the screen, and what the
    // screens say.
    func testTheReplyAndTheWords() throws {
        let plan = plan()
        let reply = #"{ "steps": 2, "exercises": [ { "day": "Push", "name": "Bench Press", "steps": [ { "weight": 60 }, { "weight": 62.5 } ] } ] }"#
        let result = ProgressionImport.run(reply, plan: plan, settings: settings, now: now, calendar: calendar, mode: .performance)
        let p = try XCTUnwrap(result.progression, "\(result.issues)")
        XCTAssertEqual(p.mode, .performance)
        XCTAssertEqual(p.weeks, 2)
        XCTAssertEqual(p.entries.first?.weeks.map(\.weight), [60, 62.5])
        XCTAssertEqual(p.entries.first?.step, 0)
        XCTAssertTrue(result.issues.isEmpty, "\(result.issues)")

        let old = #"{ "weeks": 2, "exercises": [ { "name": "Bench Press", "weeks": [ { "weight": 60 }, { "weight": 61 } ] } ] }"#
        let alias = ProgressionImport.run(old, plan: plan, settings: settings, now: now, calendar: calendar, mode: .performance)
        XCTAssertNotNil(alias.progression)
        XCTAssertTrue(alias.issues.contains { $0.code == "W_PROGRESSION_WEEKS_ALIAS" })
        XCTAssertTrue(IssueText.split(alias.issues).material.isEmpty, "the alias is tidying, not news")
        XCTAssertTrue(alias.issues.contains { $0.code == "W_PROGRESSION_ROUNDED" && $0.path == "exercises[0].weeks[1].weight" })
        let bad = ProgressionImport.run(#"{ "steps": 2, "exercises": [ { "name": "Row", "steps": [ { "reps": "eight" }, {} ] } ] }"#, plan: plan, settings: settings, now: now, calendar: calendar)
        XCTAssertEqual(bad.errors.first?.path, "exercises[0].steps[0].reps")
        XCTAssertEqual(IssueText.location("exercises[0].steps[0].reps"), "exercise 1, step 1")
        XCTAssertEqual(ProgressionImport.run(#"{ "steps": 0, "exercises": [] }"#, plan: plan, settings: settings, now: now).errors.first?.code, "E_PROGRESSION_WEEKS_INVALID")

        // The words.
        var full = progression()
        XCTAssertEqual(ProgressionText.reason(week: 2, of: 4, mode: .performance), "Step 2 of 4 of your progression")
        XCTAssertEqual(ProgressionText.reason(week: 2, of: 4), "Week 2 of 4 of your progression")
        XCTAssertEqual(ProgressionText.entryStatus(full.entries[0], of: 4), "Step 1 of 4")
        full.entries[0].tries = 2
        XCTAssertEqual(ProgressionText.entryStatus(full.entries[0], of: 4), "Step 1 of 4 · 2 tries")
        full.entries[0].step = 4
        XCTAssertEqual(ProgressionText.entryStatus(full.entries[0], of: 4), "Done")
        XCTAssertEqual(ProgressionText.ladder(full.entries[1], units: .kg, bodyweight: true, current: 1), "1) 50 s · ▸ 2) 60 s")
        XCTAssertEqual(ProgressionText.ladder(full.entries[0], units: .kg, bodyweight: false, current: nil), "1) 8–10 × 60 kg · 2) 62.5 kg · 3) same · 4) 6–8 × 65 kg")

        // The chip in a step says the step.
        var with = plan
        with.progression = progression()
        let s = try XCTUnwrap(Session.start(plan: with, dayIndex: 0, now: now, calendar: calendar))
        let values = Prefill.values(session: s, step: 0, history: [], settings: settings)
        XCTAssertEqual(values.suggestion?.reason, "Step 1 of 4 of your progression")
        XCTAssertEqual(values.weight, 60)

        // Home: the step, then the offer when every exercise is done.
        var library = PlanLibrary()
        library.save(with, makeActive: true)
        XCTAssertTrue(HomeStart.current(library: library, now: now, calendar: calendar).subtitle?.hasSuffix("step 1 of 4") == true)
        library.plans[0].progression?.entries[0].step = 4
        library.plans[0].progression?.entries[1].step = 2
        library.plans[0].progression?.entries[2].step = 1
        let done = HomeStart.current(library: library, now: now, calendar: calendar)
        XCTAssertTrue(done.progressionFinished)
        XCTAssertFalse(done.subtitle?.contains("step") == true)
    }

    // Z23: on disk — a v1.3 progression reads as calendar at step 0; the new fields round-trip.
    func testOnDisk() throws {
        // What v1.3 wrote: the app's own file with the three v1.5 keys taken out.
        var written = plan()
        written.progression = progression(mode: .calendar)
        var text = String(decoding: try StoreCoder.encode(PlansPayload(activePlanId: written.id, plans: [written])), as: UTF8.self)
        for key in ["mode", "step", "tries"] {
            text = text.replacing("\n *\"\(key)\" : [^\n]*,?", with: "")
        }
        XCTAssertFalse(text.contains("\"mode\""))
        XCTAssertFalse(text.contains("\"tries\""))
        let payload = try StoreCoder.decode(PlansPayload.self, from: Data(text.utf8))
        let p = try XCTUnwrap(payload.plans.first?.progression)
        XCTAssertEqual(p.mode, .calendar, "everything written before v1.5 is a calendar progression")
        XCTAssertEqual(p.entries.first?.step, 0)
        XCTAssertEqual(p.entries.first?.tries, 0)
        XCTAssertEqual(p.entries.first?.weeks.map(\.weight), [60, 62.5, nil, 65])

        var plan = plan()
        var performance = progression()
        performance.entries[0].step = 2
        performance.entries[0].tries = 1
        plan.progression = performance
        let back = try StoreCoder.decode(PlansPayload.self, from: try StoreCoder.encode(PlansPayload(activePlanId: plan.id, plans: [plan])))
        XCTAssertEqual(back.plans.first?.progression, performance)

        let session = try XCTUnwrap(Session.start(plan: plan, dayIndex: 0, now: now, calendar: calendar))
        XCTAssertEqual(try StoreCoder.decode(Session.self, from: try StoreCoder.encode(session)).progressionMode, .performance)
        let frozen = try StoreCoder.decode(Session.self, from: try FixtureLoader.data("store/v1/session.json"))
        XCTAssertNil(frozen.progressionMode)
    }

    // Z24: the prompt says what a step is.
    func testThePromptSaysWhatAStepIs() {
        let plan = plan()
        let earned = Prompts.progression(plan: plan, history: [], weeks: 8, includeHistory: false, settings: settings, now: now, mode: .performance)
        XCTAssertTrue(earned.contains("as 8 steps"))
        XCTAssertTrue(earned.contains("\"steps\": 8"))
        XCTAssertTrue(earned.contains("I move to the next step only when I hit the current one"))
        XCTAssertFalse(earned.contains("{{"))
        let weekly = Prompts.progression(plan: plan, history: [], weeks: 4, includeHistory: false, settings: settings, now: now, mode: .calendar)
        XCTAssertTrue(weekly.contains("One step is one calendar week"))
        XCTAssertFalse(weekly.contains("only when I hit"))
        XCTAssertLessThan(earned.count, Prompts.progressionBound)
    }
}

import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// Z2 (v1.5) — D51: the effort target. Reps (or seconds, on a hold) to stop short of failure,
/// as a field of the plan rather than a note.
final class InReserveTests: XCTestCase {
    private let now = CoreTestSupport.now

    private func plan(_ exercises: String) -> ImportResult {
        PlanImport.run("""
        { "name": "Effort", "units": "kg", "days": [ { "name": "A", "exercises": [ \(exercises) ] } ] }
        """, settings: Settings(), now: now)
    }

    // Z5: the field at both levels, its alias, on a hold, and what is refused.
    func testTheFieldIsReadAndRefused() throws {
        let result = plan("""
        { "name": "Barbell Bench Press", "reps": "6-8", "weight": 80, "restSeconds": 150, "inReserve": 2, "sets": [ {}, {}, { "inReserve": 1 } ] },
        { "name": "Barbell Row", "sets": 2, "reps": "8-10", "weight": 70, "rir": 3 },
        { "name": "Plank", "sets": 2, "durationSeconds": 45, "bodyweight": true, "inReserve": 5 },
        { "name": "Dumbbell Curl", "sets": 1, "reps": 12, "weight": 12 }
        """)
        XCTAssertTrue(result.issues.isEmpty, "\(result.issues)")
        let day = try XCTUnwrap(result.plan?.days.first)
        XCTAssertEqual(day.exercises[0].sets.map(\.inReserve), [2, 2, 1])
        XCTAssertEqual(day.exercises[1].sets.map(\.inReserve), [3, 3])
        XCTAssertEqual(day.exercises[2].sets.map(\.inReserve), [5, 5], "seconds, on a hold")
        XCTAssertEqual(day.exercises[3].sets.map(\.inReserve), [nil])

        let word = plan(#"{ "name": "Curl", "sets": 2, "reps": 10, "inReserve": "two" }"#)
        XCTAssertNil(word.plan)
        let error = try XCTUnwrap(word.errors.first)
        XCTAssertEqual(error.code, "E_IN_RESERVE_INVALID")
        XCTAssertEqual(error.path, "days[0].exercises[0].inReserve")
        XCTAssertTrue(IssueText.friendly(error).contains("0 to 20"), IssueText.friendly(error))
        XCTAssertTrue(IssueText.friendly(error).hasPrefix("Day 1, exercise 1:"), IssueText.friendly(error))

        let tooMany = plan(#"{ "name": "Curl", "reps": 10, "sets": [ {}, { "rir": 25 } ] }"#)
        XCTAssertEqual(tooMany.errors.first?.code, "E_IN_RESERVE_INVALID")
        XCTAssertEqual(tooMany.errors.first?.path, "days[0].exercises[0].sets[1].rir")

        // A string of digits is a number, as everywhere else in the format (§3.7).
        let digits = plan(#"{ "name": "Curl", "sets": 1, "reps": 10, "rir": "2" }"#)
        XCTAssertEqual(digits.plan?.days[0].exercises[0].sets.first?.inReserve, 2)
        XCTAssertTrue(digits.issues.isEmpty, "\(digits.issues)")
    }

    // Z6: where it shows — the card, its spoken form, the next line, the summary.
    func testWhereItShows() throws {
        let imported = try XCTUnwrap(plan("""
        { "name": "Barbell Bench Press", "sets": 3, "reps": "6-8", "weight": 80, "restSeconds": 150, "inReserve": 2, "drops": [ { "weight": 60 } ] },
        { "name": "Curl", "reps": 12, "weight": 12, "sets": [ { "inReserve": 2 }, { "inReserve": 1 } ] },
        { "name": "Row", "sets": 2, "reps": 10, "weight": 50 }
        """).plan)
        let session = try XCTUnwrap(Session.start(plan: imported, dayIndex: 0, now: now))
        XCTAssertEqual(session.target(at: 0)?.reserve, 2)
        XCTAssertEqual(StepCard.targetLine(session: session, step: 0), "6–8 · 80 kg · 2 in reserve")
        XCTAssertTrue(StepCard.spoken(session: session, step: 0).contains("2 in reserve"))
        // The drop after the first set has no effort target of its own.
        XCTAssertEqual(session.steps[1].dropIndex, 1)
        XCTAssertNil(session.target(at: 1)?.reserve)
        XCTAssertFalse(StepCard.targetLine(session: session, step: 1).contains("in reserve"))
        XCTAssertEqual(WorkoutScreen.nextLine(session: session, step: 0),
                       "Next: Barbell Bench Press · set 1 of 3 · 6–8 · 80 kg · 2 in reserve")

        let bench = imported.days[0].exercises[0]
        XCTAssertEqual(TargetText.summary(bench, units: .kg), "3 × 6–8 · 80 kg · 3 drops · 2 in reserve")
        let curl = imported.days[0].exercises[1]
        XCTAssertFalse(TargetText.summary(curl, units: .kg).contains("in reserve"), "sets that differ are the JSON's business")
        let row = imported.days[0].exercises[2]
        XCTAssertEqual(TargetText.summary(row, units: .kg), "2 × 10 · 50 kg")
    }

    // Z7: on disk — round trip, the frozen files, the session's snapshot.
    func testOnDisk() throws {
        let imported = try XCTUnwrap(plan(#"{ "name": "Curl", "sets": 2, "reps": 10, "weight": 12, "inReserve": 2 }"#).plan)
        let data = try StoreCoder.encode(PlansPayload(activePlanId: imported.id, plans: [imported]))
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"inReserve\" : 2"))
        let back = try StoreCoder.decode(PlansPayload.self, from: data)
        XCTAssertEqual(back.plans.first?.days[0].exercises[0].sets.map(\.inReserve), [2, 2])

        let frozen = try StoreCoder.decode(PlansPayload.self, from: try FixtureLoader.data("store/v1/plans.json"))
        XCTAssertTrue(frozen.plans.flatMap(\.days).flatMap(\.exercises).flatMap(\.sets).allSatisfy { $0.inReserve == nil })
        let session = try StoreCoder.decode(Session.self, from: try FixtureLoader.data("store/v1/session.json"))
        XCTAssertTrue(session.exercises.flatMap(\.targets).allSatisfy { $0.inReserve == nil })

        let started = try XCTUnwrap(Session.start(plan: imported, dayIndex: 0, now: now))
        XCTAssertEqual(started.exercises[0].targets.map(\.inReserve), [2, 2], "D7: the snapshot carries it")
        let stored = try StoreCoder.decode(Session.self, from: try StoreCoder.encode(started))
        XCTAssertEqual(stored.exercises[0].targets.map(\.inReserve), [2, 2])
    }

    // Z8: the structured edit, and the JSON round trip.
    func testTheEdit() throws {
        let imported = try XCTUnwrap(plan(#"{ "name": "Curl", "sets": 3, "reps": 10, "weight": 12 }"#).plan)
        let set = PlanEdit.apply(.setInReserve(day: 0, exercise: 0, value: 2), to: imported, settings: Settings(), now: now)
        XCTAssertTrue(set.issues.isEmpty, "\(set.issues)")
        let edited = try XCTUnwrap(set.plan)
        XCTAssertEqual(edited.days[0].exercises[0].sets.map(\.inReserve), [2, 2, 2])
        XCTAssertEqual(edited.id, imported.id)
        XCTAssertTrue(edited.sourceText.contains("\"inReserve\": 2"), "the rendered JSON says it per set")

        let cleared = try XCTUnwrap(PlanEdit.apply(.setInReserve(day: 0, exercise: 0, value: nil), to: edited, settings: Settings(), now: now).plan)
        XCTAssertEqual(cleared.days[0].exercises[0].sets.map(\.inReserve), [nil, nil, nil])
        XCTAssertFalse(cleared.sourceText.contains("inReserve"))

        let refused = PlanEdit.apply(.setInReserve(day: 0, exercise: 0, value: 21), to: imported, settings: Settings(), now: now)
        XCTAssertNil(refused.plan)
        XCTAssertEqual(refused.errors.first?.code, "E_EDIT_INVALID")

        // Rendered and imported back, the plan is the same plan.
        let again = PlanImport.run(edited.sourceText, settings: Settings(), now: now)
        XCTAssertTrue(again.issues.isEmpty, "\(again.issues)")
        XCTAssertEqual(again.plan?.days[0].exercises[0].sets.map(\.inReserve), [2, 2, 2])
    }

    // Z9: the prompts know.
    func testThePromptsKnow() throws {
        let prompt = Prompts.render(settings: Settings())
        XCTAssertTrue(prompt.contains("- inReserve: how many reps (or seconds, for holds) short of failure each set should stop, e.g. 2. Omit when I do not say."))
        XCTAssertFalse(prompt.contains("RPE"), "RPE no longer goes to notes; the effort target is a field")

        // A history line carries it when every logged set of the exercise had it.
        let imported = try XCTUnwrap(plan(#"{ "name": "Curl", "sets": 2, "reps": "8-12", "repRange": "8-12", "weight": 12, "inReserve": 2 }"#).plan)
        var session = try XCTUnwrap(Session.start(plan: imported, dayIndex: 0, now: now.addingTimeInterval(-86_400)))
        for index in session.steps.indices {
            session.steps[index].status = .logged
            session.steps[index].result = .reps(count: 10, weight: 12)
            session.steps[index].loggedAt = session.startedAt.addingTimeInterval(Double(index) * 60)
        }
        session.endedAt = session.steps.last?.loggedAt
        let listing = Prompts.historyListing(plan: imported, history: [session], now: now, sessionsPerExercise: 6)
        XCTAssertTrue(listing.contains("10,10 @ 12 kg · 2 in reserve"), listing)

        let plain = try XCTUnwrap(plan(#"{ "name": "Curl", "sets": 2, "reps": "8-12", "repRange": "8-12", "weight": 12 }"#).plan)
        var quiet = try XCTUnwrap(Session.start(plan: plain, dayIndex: 0, now: now.addingTimeInterval(-86_400)))
        for index in quiet.steps.indices {
            quiet.steps[index].status = .logged
            quiet.steps[index].result = .reps(count: 10, weight: 12)
            quiet.steps[index].loggedAt = quiet.startedAt.addingTimeInterval(Double(index) * 60)
        }
        quiet.endedAt = quiet.steps.last?.loggedAt
        XCTAssertFalse(Prompts.historyListing(plan: plain, history: [quiet], now: now, sessionsPerExercise: 6).contains("in reserve"))
    }
}

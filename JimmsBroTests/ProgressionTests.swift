import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// X5 (v1.3) — D44, W31–W39: Progression, the chatbot round-trip run the other way. The app
/// writes out the plan and the history, the chatbot plans the next N weeks, and the plan
/// carries the answer week by week.
final class ProgressionTests: XCTestCase {
    private let now = CoreTestSupport.now
    private let calendar = CoreTestSupport.utc()
    private let settings = Settings()

    /// Push: Bench Press 3 × 8–12 @ 60, Push-Up 3 × AMRAP (bodyweight). Pull: Row 3 × 8–12 @ 50.
    private func plan() -> Plan {
        let bench = Exercise(name: "Bench Press", repRange: RepRange(min: 8, max: 12),
                             sets: Array(repeating: SetTarget(work: .reps(.range(min: 8, max: 12)), weight: 60, restSeconds: 90), count: 3))
        let pushUp = Exercise(name: "Push-Up", bodyweight: true,
                              sets: Array(repeating: SetTarget(work: .reps(.amrap(min: nil)), weight: nil, restSeconds: 60), count: 3))
        let row = Exercise(name: "Row", repRange: RepRange(min: 8, max: 12),
                           sets: Array(repeating: SetTarget(work: .reps(.range(min: 8, max: 12)), weight: 50, restSeconds: 90), count: 3))
        return Plan(name: "PP", units: .kg, schedule: .rotation,
                    days: [Day(name: "Push", exercises: [bench, pushUp]), Day(name: "Pull", exercises: [row])],
                    importedAt: now, sourceText: "", cycle: [.day(0), .day(1)])
    }

    /// Four weeks for Bench Press — a lighter range, then heavier, then nothing, then two
    /// varied sets — and one week for Push-Up.
    private func progression() -> Progression {
        Progression(startDate: calendar.startOfDay(for: now), weeks: 4, entries: [
            ProgressionEntry(dayName: "Push", exerciseName: "Bench Press", weeks: [
                ProgressionWeek(weight: 60, work: .reps(.range(min: 8, max: 10))),
                ProgressionWeek(weight: 62.5),
                ProgressionWeek(),
                ProgressionWeek(sets: [ProgressionSet(weight: 65, work: .reps(.fixed(8))),
                                       ProgressionSet(weight: 67.5, work: .reps(.fixed(6)))]),
            ]),
            ProgressionEntry(dayName: "Push", exerciseName: "Push-Up", weeks: [
                ProgressionWeek(work: .reps(.amrap(min: 12))),
            ]),
        ])
    }

    private func days(_ count: Int) -> Date { now.addingTimeInterval(Double(count) * 86_400) }

    // W31: the week is calendar weeks from the start date; the last one ends, it does not linger.
    func testTheWeekIsCountedFromTheStartDate() {
        let p = progression()
        XCTAssertEqual(p.weekIndex(on: now, calendar: calendar), 0)
        XCTAssertEqual(p.weekIndex(on: days(6), calendar: calendar), 0)
        XCTAssertEqual(p.weekIndex(on: days(7), calendar: calendar), 1)
        XCTAssertEqual(p.weekIndex(on: days(27), calendar: calendar), 3)
        XCTAssertNil(p.weekIndex(on: days(28), calendar: calendar))
        XCTAssertNil(p.weekIndex(on: days(-1), calendar: calendar))
        XCTAssertFalse(p.isFinished(on: days(27), calendar: calendar))
        XCTAssertTrue(p.isFinished(on: days(28), calendar: calendar))
        XCTAssertEqual(ProgressionText.status(p, on: days(8), calendar: calendar), "Week 2 of 4")
        XCTAssertEqual(ProgressionText.status(p, on: days(30), calendar: calendar), "Finished")
        XCTAssertEqual(ProgressionText.reason(week: 2, of: 4, mode: .calendar), "Week 2 of 4 of your progression")
    }

    // W32: a week changes only what it says; everything else keeps the plan's own target.
    func testApplyingAWeekChangesOnlyWhatItSays() {
        let p = progression()
        let day = plan().days[0]

        let w0 = p.apply(to: day, week: 0)
        XCTAssertEqual(w0.touched, [0, 1])
        XCTAssertEqual(w0.day.exercises[0].sets.map(\.weight), [60, 60, 60])
        XCTAssertEqual(w0.day.exercises[0].sets.map(\.work), Array(repeating: .reps(.range(min: 8, max: 10)), count: 3))
        XCTAssertEqual(w0.day.exercises[0].repRange, RepRange(min: 8, max: 10), "a range is also the range advice judges by")
        XCTAssertEqual(w0.day.exercises[1].sets.map(\.work), Array(repeating: .reps(.amrap(min: 12)), count: 3))
        XCTAssertEqual(w0.day.exercises[1].sets.map(\.weight), [nil, nil, nil])

        let w1 = p.apply(to: day, week: 1)
        XCTAssertEqual(w1.touched, [0], "Push-Up has only one week")
        XCTAssertEqual(w1.day.exercises[0].sets.map(\.weight), [62.5, 62.5, 62.5])
        XCTAssertEqual(w1.day.exercises[0].sets.map(\.work), day.exercises[0].sets.map(\.work), "reps untouched")

        let w2 = p.apply(to: day, week: 2)
        XCTAssertEqual(w2.touched, [], "{} is no change")
        XCTAssertEqual(w2.day, day)

        let w3 = p.apply(to: day, week: 3)
        XCTAssertEqual(w3.day.exercises[0].sets.map(\.weight), [65, 67.5, 60])
        XCTAssertEqual(w3.day.exercises[0].sets.map(\.work), [.reps(.fixed(8)), .reps(.fixed(6)), .reps(.range(min: 8, max: 12))])

        XCTAssertEqual(p.apply(to: plan().days[1], week: 0).touched, [], "Pull has no entry")
        XCTAssertEqual(ProgressionText.change(p.entries[0].weeks[3], units: .kg, bodyweight: false), "8 · 65 / 6 · 67.5 kg")
        XCTAssertEqual(ProgressionText.change(p.entries[0].weeks[2], units: .kg, bodyweight: false), "same")
        XCTAssertEqual(ProgressionText.change(p.entries[0].weeks[1], units: .kg, bodyweight: false), "62.5 kg")
    }

    // W33: starting a day writes the week's targets into the snapshot and stamps the week.
    func testStartingADayAppliesTheCurrentWeek() throws {
        var plan = plan()
        plan.progression = progression()
        let session = try XCTUnwrap(Session.start(plan: plan, dayIndex: 0, now: days(8), calendar: calendar))
        XCTAssertEqual(session.progressionWeek, 2)
        XCTAssertEqual(session.progressionWeeks, 4)
        XCTAssertEqual(session.exercises[0].progressionWeek, 2)
        XCTAssertNil(session.exercises[1].progressionWeek, "Push-Up has nothing for week 2")
        XCTAssertEqual(session.exercises[0].targets.map(\.weight), [62.5, 62.5, 62.5])
        XCTAssertTrue(ExerciseText.summary(session).hasSuffix("week 2 of 4"), ExerciseText.summary(session))
        XCTAssertEqual(ProgressionText.weekLine(session), "week 2 of 4")

        let after = try XCTUnwrap(Session.start(plan: plan, dayIndex: 0, now: days(40), calendar: calendar))
        XCTAssertNil(after.progressionWeek)
        XCTAssertEqual(after.exercises[0].targets.map(\.weight), [60, 60, 60], "the plan's own targets are back")

        let plain = try XCTUnwrap(Session.start(plan: self.plan(), dayIndex: 0, now: now, calendar: calendar))
        XCTAssertNil(plain.progressionWeek)
        XCTAssertNil(plain.exercises[0].progressionWeek)
        XCTAssertNil(ProgressionText.weekLine(plain))
    }

    // W34: in a progression week the week's target is the prefill and the chip, even when last
    // time was heavier; after the last week, last time wins again.
    func testTheWeeksTargetIsThePrefillAndTheChip() throws {
        var plan = plan()
        plan.progression = progression()
        var earlier = CoreTestSupport.plan(sets: 3, weight: 70)
        earlier.days[0].exercises[0].name = "Bench Press"
        let history = [CoreTestSupport.completed([10, 10, 10], weights: [70, 70, 70], plan: earlier)]

        let session = try XCTUnwrap(Session.start(plan: plan, dayIndex: 0, now: days(8), calendar: calendar))
        let values = Prefill.values(session: session, step: 0, history: history, settings: settings)
        XCTAssertEqual(values.weight, 62.5)
        XCTAssertEqual(values.reps, 8)
        XCTAssertEqual(values.lastWeight, 70, "last time is still said")
        let chip = try XCTUnwrap(values.suggestion)
        XCTAssertEqual(chip.text, "8 × 62.5 kg")
        XCTAssertEqual(chip.reason, "Week 2 of 4 of your progression")
        XCTAssertTrue(chip.isProgression)

        let after = try XCTUnwrap(Session.start(plan: plan, dayIndex: 0, now: days(40), calendar: calendar))
        let later = Prefill.values(session: after, step: 0, history: history, settings: settings)
        XCTAssertEqual(later.weight, 70)
        // D55 (v1.6): last time is back in the fields, so there is nothing left to suggest.
        XCTAssertNil(later.suggestion)

        // Bodyweight in its week: reps only, nothing invented for the weight.
        let first = try XCTUnwrap(Session.start(plan: plan, dayIndex: 0, now: now, calendar: calendar))
        let pushUp = try XCTUnwrap(first.steps.firstIndex { $0.exerciseIndex == 1 })
        let bodyweight = Prefill.values(session: first, step: pushUp, history: [], settings: settings)
        XCTAssertNil(bodyweight.weight)
        XCTAssertFalse(bodyweight.showsWeight)
        XCTAssertNil(bodyweight.suggestion, "AMRAP with no weight has no number to suggest")
    }

    // W35: a reply — with prose around it, a wrong name, an unmatched entry, a bodyweight
    // weight, an unloadable weight, a short list, a null week and per-set values — is read,
    // matched to the plan, snapped, and everything it dropped is said.
    func testAReplyIsReadMatchedAndSnapped() throws {
        let reply = """
        Here is your progression:
        ```json
        { "weeks": 4, "exercises": [
          { "day": "Push", "name": "Barbell Bench Press", "weeks": [ {"weight": 60}, {"weight": 61}, {}, null ] },
          { "name": "bench press", "weeks": [ {"weight": 60}, {"weight": 62.5, "rpe": 8}, {"weight": 65}, null ] },
          { "name": "Push-Up", "weeks": [ {"reps": "12+", "weight": 10}, {"reps": "AMRAP"} ] },
          { "name": "Row", "weeks": [ {"sets": [ {"weight": 50, "reps": 10}, {"weight": 52, "reps": 8} ]}, {}, {}, {} ] }
        ] }
        ```
        """
        let result = ProgressionImport.run(reply, plan: plan(), settings: settings, now: now, calendar: calendar, mode: .calendar)
        let p = try XCTUnwrap(result.progression, "\(result.issues)")
        XCTAssertEqual(p.weeks, 4)
        XCTAssertEqual(p.startDate, calendar.startOfDay(for: now))
        XCTAssertEqual(p.entries.map(\.exerciseName), ["Bench Press", "Push-Up", "Row"], "the plan's spelling, not the reply's")
        XCTAssertEqual(p.entries.map(\.dayName), ["Push", "Push", "Pull"])
        XCTAssertEqual(p.entries[0].weeks.map(\.weight), [60, 62.5, 65, nil])
        XCTAssertEqual(p.entries[1].weeks.map(\.weight), [nil, nil])
        XCTAssertEqual(p.entries[1].weeks[0].work, .reps(.amrap(min: 12)))
        XCTAssertEqual(p.entries[2].weeks[0].sets?.map(\.weight), [50, 52.5], "52 is not loadable in 2.5s")

        let codes = Set(result.issues.map(\.code))
        XCTAssertTrue(codes.isSuperset(of: ["W_PROGRESSION_UNMATCHED", "W_PROGRESSION_WEIGHT_IGNORED", "W_PROGRESSION_ROUNDED",
                                            "W_PROGRESSION_SHORT", "W_SURROUNDING_TEXT", "W_UNKNOWN_FIELD"]), "\(codes)")
        XCTAssertEqual(IssueText.split(result.issues).material.map(\.code).sorted(),
                       ["W_PROGRESSION_SHORT", "W_PROGRESSION_UNMATCHED", "W_PROGRESSION_WEIGHT_IGNORED"])
        XCTAssertTrue(result.issues.contains { $0.code == "W_PROGRESSION_UNMATCHED" && $0.message.contains("Barbell Bench Press") })
    }

    // W36: what a reply is refused for, with the real place.
    func testWhatAReplyIsRefusedFor() {
        let plan = plan()
        func run(_ text: String) -> ProgressionImport.Result {
            ProgressionImport.run(text, plan: plan, settings: settings, now: now, calendar: calendar, mode: .calendar)
        }
        XCTAssertEqual(run("just words").errors.first?.code, "E_NOT_JSON")
        let prompt = Prompts.progression(plan: plan, history: [], weeks: 8, settings: settings, now: now, mode: .calendar)
        XCTAssertEqual(run(prompt).errors.first?.code, "E_PROMPT_PASTED")
        XCTAssertEqual(run(#"{ "weeks": 0, "exercises": [] }"#).errors.first?.code, "E_PROGRESSION_WEEKS_INVALID")
        XCTAssertEqual(run(#"{ "weeks": 4, "exercises": [ { "name": "Nothing", "weeks": [ {} ] } ] }"#).errors.first?.code, "E_PROGRESSION_EMPTY")
        XCTAssertEqual(run(#"{ "weeks": 4, "exercises": [ { "weeks": [ {} ] } ] }"#).errors.first?.code, "E_PROGRESSION_EXERCISE_INVALID")
        let bad = run(#"{ "weeks": 2, "exercises": [ { "name": "Row", "weeks": [ { "reps": "eight" }, {} ] } ] }"#)
        XCTAssertEqual(bad.errors.first?.code, "E_REPS_INVALID")
        XCTAssertEqual(bad.errors.first?.path, "exercises[0].weeks[0].reps")
        XCTAssertEqual(IssueText.location("exercises[0].weeks[0].reps"), "exercise 1, week 1")
        XCTAssertEqual(run(#"{ "weeks": 2, "exercises": [ { "name": "Row", "weeks": [ { "reps": 8, "durationSeconds": 30 }, {} ] } ] }"#).errors.first?.code, "E_TARGET_CONFLICT")
        XCTAssertEqual(run("[1, 2]").errors.first?.code, "E_PROGRESSION_EXERCISE_INVALID")
        XCTAssertEqual(run(#"{ "weeks": 2, "exercises": [ { "name": "Row", "weeks": [ 5, {} ] } ] }"#).errors.first?.code, "E_PROGRESSION_WEEK_INVALID")
        // Leniency: the wrapper, an inferred period, unit text, and "bw".
        let lenient = run(#"{ "progression": { "exercises": [ { "name": "Row", "weeks": [ {"weight": "55 kg"}, {"weight": "bw", "reps": "8 to 10"} ] } ] } }"#)
        XCTAssertEqual(lenient.progression?.weeks, 2)
        XCTAssertEqual(lenient.progression?.entries.first?.weeks.map(\.weight), [55, nil])
        XCTAssertEqual(lenient.progression?.entries.first?.weeks[1].work, .reps(.range(min: 8, max: 10)))
    }

    // W37: the prompt says the plan, the period, the increment and — whenever there is any — the history.
    func testThePromptSaysThePlanThePeriodAndTheHistory() throws {
        let plan = plan()
        var earlier = CoreTestSupport.plan(sets: 3, weight: 60)
        earlier.days[0].exercises[0].name = "Bench Press"
        var done = CoreTestSupport.completed([12, 12, 12], weights: [60, 60, 60], plan: earlier, start: days(-3))
        done.exercises[0].advice = .increase(to: 62.5)

        let text = Prompts.progression(plan: plan, history: [done], weeks: 8, settings: settings, now: now, mode: .calendar)
        XCTAssertTrue(text.hasPrefix(Prompts.progressionMarker))
        XCTAssertTrue(text.contains("as 8 steps"))
        XCTAssertTrue(text.contains("\"steps\": 8"))
        XCTAssertTrue(text.contains("exactly 8 objects"))
        XCTAssertTrue(text.contains(Prompts.cadence(.calendar)), "the default is the calendar for this old signature")
        XCTAssertTrue(text.contains("multiple of 2.5 kg"))
        XCTAssertTrue(text.contains("MY PLAN\nPush:\n- Bench Press: 3 × "), text)
        XCTAssertTrue(text.contains("60 kg · rest 90 s"), text)
        XCTAssertTrue(text.contains("- Push-Up: 3 × ") && text.contains("· bodyweight"), text)
        XCTAssertTrue(text.contains("\nPull:\n- Row: "), text)
        XCTAssertTrue(text.contains("MY HISTORY (most recent last)\n- Bench Press: "), text)
        XCTAssertTrue(text.contains(" 12,12,12 @ 60 kg (advice: "), text)
        XCTAssertTrue(text.contains("62.5 kg"), text)
        XCTAssertFalse(text.contains("```"), "a fence in the prompt would look like a reply")
        XCTAssertLessThan(text.count, Prompts.progressionBound)

        // v1.11 (J5): no switch leaves the history out; a plan with none has no block.
        let without = Prompts.progression(plan: plan, history: [], weeks: 4, settings: settings, now: now, mode: .calendar)
        XCTAssertFalse(without.contains("MY HISTORY"))
        XCTAssertTrue(without.contains("as 4 steps"))
        XCTAssertFalse(without.hasSuffix("\n\n"), "no dangling history block")
    }

    // W38: the progression survives the disk and edits; an old plans file has none; Replace
    // drops it, because that is a new plan.
    func testTheProgressionSurvivesTheDiskAndEdits() throws {
        var plan = plan()
        plan.progression = progression()
        let payload = try StoreCoder.decode(PlansPayload.self, from: try StoreCoder.encode(PlansPayload(activePlanId: plan.id, plans: [plan])))
        XCTAssertEqual(payload.plans.first?.progression, plan.progression)
        let old = try StoreCoder.decode(PlansPayload.self, from: try FixtureLoader.data("store/v1/plans.json"))
        XCTAssertNil(old.plans.first?.progression)

        var session = try XCTUnwrap(Session.start(plan: plan, dayIndex: 0, now: now, calendar: calendar))
        session.endedAt = now
        let back = try StoreCoder.decode(Session.self, from: try StoreCoder.encode(session))
        XCTAssertEqual(back.progressionWeek, 1)
        XCTAssertEqual(back.progressionWeeks, 4)
        XCTAssertEqual(back.exercises[0].progressionWeek, 1)

        let edited = try XCTUnwrap(PlanEdit.apply(.renameDay(day: 1, name: "Back"), to: plan, settings: settings, now: now).plan)
        XCTAssertEqual(edited.progression, plan.progression)
        let spliced = try XCTUnwrap(PlanEdit.apply(.insertExercisesJSON(day: 1, at: nil, text: #"{ "name": "Curl", "sets": 3, "reps": 12 }"#),
                                                   to: plan, settings: settings, now: now).plan)
        XCTAssertEqual(spliced.progression, plan.progression)

        var library = PlanLibrary()
        library.save(plan, makeActive: true)
        library.replace(plan.id, with: self.plan())
        XCTAssertNil(library.plans[0].progression)
    }

    // W39: the week, and the next one once the progression has run out. Today said the week —
    // a subtitle until v1.8, the ···'s line in v1.8 — and since D75 (v1.9) History's
    // Progression row says it; Today only offers the next one.
    func testHomeSaysTheWeekAndOffersTheNextOne() throws {
        var library = PlanLibrary()
        var plan = plan()
        plan.progression = progression()
        library.save(plan, makeActive: true)
        let saved = try XCTUnwrap(library.plans[0].progression)

        let card = HomeStart.current(library: library, now: days(8), calendar: calendar)
        XCTAssertEqual(ProgressionText.status(saved, on: days(8), calendar: calendar), "Week 2 of 4")
        XCTAssertFalse(card.progressionFinished)

        let later = HomeStart.current(library: library, now: days(30), calendar: calendar)
        XCTAssertTrue(later.progressionFinished)
        XCTAssertEqual(ProgressionText.status(saved, on: days(30), calendar: calendar), "Finished")

        library.plans[0].progression = nil
        let none = HomeStart.current(library: library, now: days(8), calendar: calendar)
        XCTAssertFalse(none.progressionFinished)
    }
}

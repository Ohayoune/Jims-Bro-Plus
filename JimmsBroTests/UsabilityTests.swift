import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// U1 (v1.6) — D55: nothing untrue. The 2026-09-09 audit found five places where the app
/// volunteered a sentence the person knew to be false; each was a Core rule, and each is a test.
final class UsabilityTests: XCTestCase {
    private let calendar = CoreTestSupport.utc()
    private func day(_ number: Int) -> Date { CoreTestSupport.date(number) }

    /// Push / Pull / Legs / rest, imported on the 1st.
    private func rotation(anchor: Int?, position: Int? = nil, imported: Int = 1) -> Plan {
        var plan = Plan(name: "PPL", units: .kg, schedule: .rotation,
                        days: [Day(name: "Push", exercises: []),
                               Day(name: "Pull", exercises: []),
                               Day(name: "Legs", exercises: [])],
                        importedAt: day(imported), sourceText: "",
                        cycle: [.day(0), .day(1), .day(2), .rest])
        plan.cyclePosition = position
        plan.cycleAnchor = anchor.map { calendar.startOfDay(for: day($0)) }
        return plan
    }

    private func missed(_ plan: Plan, today: Int, sessions: [Session] = []) -> Int? {
        PlanSchedule.missed(plan, sessions: sessions, today: day(today), calendar: calendar)?.dayIndex
    }

    // U1: a missed workout is one the plan actually expected.
    func testAMissedDayIsAfterTheImportAndAfterTheAnchor() {
        // A fresh plan: nothing completed, no anchor. Three minutes old, it has missed nothing —
        // v1.5 projected the pattern backwards over the week before it existed.
        XCTAssertNil(missed(rotation(anchor: nil, imported: 9), today: 9))
        XCTAssertNil(missed(rotation(anchor: nil, imported: 9), today: 10))
        // Imported ten days ago and never started: still nothing missed. You never began.
        XCTAssertNil(missed(rotation(anchor: nil, imported: 1), today: 11))

        // Push done on the 7th (the anchor), today the 9th: Pull on the 8th was missed.
        XCTAssertEqual(missed(rotation(anchor: 7, position: 0), today: 9), 1)
        // The anchor day itself is never "missed" — it is the day that was done.
        XCTAssertNil(missed(rotation(anchor: 7, position: 0), today: 8))

        // A day run out of order re-anchors the pattern: Legs done on the 9th puts Pull on the
        // 8th in the projection, but the 8th was lived through before the anchor moved.
        XCTAssertNil(missed(rotation(anchor: 9, position: 2), today: 10))
        // And the import day is a floor of its own: a plan imported on the 8th and anchored the
        // same day cannot have missed the 7th.
        XCTAssertNil(missed(rotation(anchor: 8, position: 1, imported: 8), today: 9))

        // The v1.2 rule still holds within those bounds: having trained on the 8th, nothing.
        var trained = CoreTestSupport.session(CoreTestSupport.plan(), start: day(8))
        trained.endedAt = day(8)
        XCTAssertNil(missed(rotation(anchor: 7, position: 0), today: 9, sessions: [trained]))
        // And it still looks no further back than a week: anchored on the 1st and away until
        // the 20th, only the most recent projected day is reported, not the 2nd.
        XCTAssertNotEqual(PlanSchedule.missed(rotation(anchor: 1, position: 0), sessions: [], today: day(20),
                                              calendar: calendar)?.date, calendar.startOfDay(for: day(2)))

        // Home says the same thing the schedule does.
        var library = PlanLibrary()
        library.save(rotation(anchor: nil, imported: 9), makeActive: true)
        XCTAssertNil(HomeStart.current(library: library, now: day(9), calendar: calendar).missed)
    }

    // U2: "Nothing logged" outranks "First time".
    func testNothingLoggedOutranksFirstTime() {
        let plan = CoreTestSupport.plan()
        let untouched = CoreTestSupport.session(plan)       // every step pending
        XCTAssertEqual(SessionStats.comparison(for: "Bench Press", session: untouched, history: []).headline,
                       "Nothing logged", "no history and nothing logged is not a first time")
        let before = CoreTestSupport.completed([10, 10, 8], plan: plan)
        XCTAssertEqual(SessionStats.comparison(for: "Bench Press", session: untouched, history: [before]).headline,
                       "Nothing logged")
        // A first time that happened is still a first time.
        let first = CoreTestSupport.completed([10, 10, 8], plan: plan, start: CoreTestSupport.now)
        XCTAssertEqual(SessionStats.comparison(for: "Bench Press", session: first, history: []).headline,
                       "First time")
    }

    // U3: a calendar cell tells the plan's days apart.
    func testCalendarLabelsAreUniqueWithinThePlan() {
        func labels(_ names: [String]) -> [String] { names.map { CalendarText.short($0, among: names) } }
        XCTAssertEqual(labels(["Push", "Pull", "Legs"]), ["Push", "Pull", "Legs"])
        XCTAssertEqual(labels(["Upper Body", "Lower Body"]), ["Upper", "Lower"])
        // The audit's case: both days read "Full…".
        XCTAssertEqual(labels(["Full Body A", "Full Body B"]), ["FBA", "FBB"])
        XCTAssertEqual(labels(["Upper A", "Lower A", "Upper B", "Lower B"]), ["UA", "LA", "UB", "LB"])
        XCTAssertEqual(labels(["Day 1", "Day 2", "Day 3"]), ["D1", "D2", "D3"])
        XCTAssertEqual(labels(["Push A", "Push B"]), ["PA", "PB"])
        // Names whose initials also collide fall back to their number in the plan.
        XCTAssertEqual(labels(["Push A", "Push Alpha"]), ["1", "2"])
        // Mixed: only the colliding names change.
        XCTAssertEqual(labels(["Push", "Full Body A", "Full Body B"]), ["Push", "FBA", "FBB"])
        // A name the plan does not hold keeps the plain rule, as does a one-day plan.
        XCTAssertEqual(CalendarText.short("Shoulders and Arms", among: ["Push", "Pull"]), "Shou…")
        XCTAssertEqual(CalendarText.short("Full Body A", among: ["Full Body A"]), "Full")

        // Through the cell itself: a projected day and a completed session of the same plan.
        var plan = CoreTestSupport.plan()
        plan.days[0].name = "Full Body A"
        var b = plan.days[0]; b.id = UUID(); b.name = "Full Body B"
        plan.days.append(b)
        XCTAssertEqual(CalendarText.label(.projected(planId: plan.id, dayIndex: 1), plans: [plan]), "FBB")
        var session = CoreTestSupport.session(plan)
        session.endedAt = session.startedAt.addingTimeInterval(1800)
        XCTAssertEqual(CalendarText.label(.completed([session]), plans: [plan]), "FBA")
        // The spoken cell still says the whole name.
        XCTAssertTrue(CalendarText.spoken(CalendarDay(date: day(9), entry: .completed([session])),
                                          plans: [plan], calendar: calendar).hasSuffix("Done: Full Body A"))
    }

    // U4: the suggestion chip never contradicts the fields.
    func testTheChipNeverContradictsTheFields() throws {
        // A fixed target of 5 in a 4–6 range, last time 10 at the same weight.
        var plan = CoreTestSupport.plan(sets: 4, work: .reps(.fixed(5)), weight: 100)
        plan.days[0].exercises[0].repRange = RepRange(min: 4, max: 6)
        let last = CoreTestSupport.completed([10, 10, 10, 10], weights: [100, 100, 100, 100], plan: plan)
        let session = CoreTestSupport.session(plan)
        let target = try XCTUnwrap(session.target(at: 0))

        // "Do that again" is what was done — never the plan's 5 at last time's 100.
        let again = Prefill.setSuggestion(session: session, step: 0, exercise: session.exercises[0],
                                          target: target, last: .reps(count: 10, weight: 100),
                                          lastWeight: 100, advice: nil, adviceReason: nil, units: .kg)
        XCTAssertEqual(again?.text, "10 × 100 kg")
        XCTAssertEqual(again?.reason, "Last time 10 × 100 kg")

        // And since the fields are prefilled with exactly that, the card shows no chip at all.
        let values = Prefill.values(session: session, step: 0, history: [last])
        XCTAssertEqual(values.reps, 10); XCTAssertEqual(values.weight, 100)
        XCTAssertNil(values.suggestion)
        XCTAssertNil(StepCard.suggestionChip(values, units: .kg))

        // Advice differs from the fields, so it is shown, with its reason.
        var advised = last
        advised.exercises[0].advice = .increase(to: 102.5)
        let withAdvice = Prefill.values(session: session, step: 0, history: [advised])
        XCTAssertEqual(withAdvice.suggestion?.weight, 102.5)
        XCTAssertEqual(withAdvice.suggestion?.reason, "You hit the top of 4–6 last time")
        XCTAssertEqual(StepCard.suggestionChip(withAdvice, units: .kg), "Try 5 × 102.5 kg")

        // The first set of a plan with no weights: the fields already show the target's reps.
        let first = Prefill.values(session: CoreTestSupport.session(CoreTestSupport.plan(weight: nil)),
                                   step: 0, history: [])
        XCTAssertEqual(first.reps, 8); XCTAssertNil(first.weight)
        XCTAssertNil(first.suggestion, "\"Try 8 reps · The plan's target\" under a field reading 8 said nothing")

        // A held set keeps its chip: it is judged by its seconds, which the fields do not show.
        let held = CoreTestSupport.plan(work: .duration(seconds: 45), weight: nil)
        var longer = CoreTestSupport.session(held, start: CoreTestSupport.now.addingTimeInterval(-86400))
        for index in longer.steps.indices {
            longer.steps[index].status = .logged
            longer.steps[index].result = .duration(seconds: 60, weight: nil)
            longer.steps[index].loggedAt = longer.startedAt.addingTimeInterval(Double(index) * 90)
        }
        longer.endedAt = longer.steps.last?.loggedAt
        let hold = Prefill.values(session: CoreTestSupport.session(held), step: 0, history: [longer])
        XCTAssertEqual(hold.suggestion?.text, "60 s")
    }

    // U5: the right sentence for a paste that is not JSON.
    func testAPlanInWordsIsNotACutOffReply() {
        let words = PlanImport.run("Monday: bench press 3x8 at 60 kg, squat 3x5 at 80 kg, rest 2 minutes")
        XCTAssertEqual(words.errors.first?.code, "E_NOT_JSON")
        XCTAssertEqual(IssueText.friendly(words.errors[0]),
                       "This is a plan in words. Send it to a chatbot with the prompt and paste back what it writes.")
        // JSON that will not parse is still a reply that looks cut off.
        let cut = PlanImport.run(String(CoreTestSupport.planJSON().dropLast(20)))
        XCTAssertEqual(cut.errors.first?.code, "E_NOT_JSON")
        XCTAssertTrue(IssueText.friendly(cut.errors[0]).contains("looks cut off"))
    }

    // U6: the overview's rows carry the set's target, never the exercise's note.
    func testTheOverviewRowLeavesTheNoteToTheExercise() {
        var plan = CoreTestSupport.plan()
        plan.days[0].exercises[0].notes = "Bar on the upper back, big breath, sit down between the knees."
        let session = CoreTestSupport.session(plan)
        XCTAssertEqual(StepCard.targetLine(session: session, step: 0, notes: false), "8–12 · 60 kg")
        XCTAssertEqual(StepCard.targetLine(session: session, step: 0),
                       "8–12 · 60 kg · Bar on the upper back, big breath, sit down between the knees.")
    }
}

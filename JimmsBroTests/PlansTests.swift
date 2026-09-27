import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// Q6 (v1.9) — Plans speak in squares (D78): TQ34–TQ37.
///
/// The plan's example: Push · Pull · Legs · Rest · Push · Pull · Legs, anchored so Monday
/// 14 September 2026 is Push (Push was done on the 7th). Push is green, Pull orange, Legs
/// purple (§6.41). Upper Lower is a weekday plan: Upper A Monday, Lower A Tuesday, Upper B
/// Thursday, Lower B Friday.
final class PlansTests: XCTestCase {
    private let calendar = CoreTestSupport.utc()
    private static let set = SetTarget(work: .reps(.fixed(5)), weight: 60, restSeconds: 90)

    private func day(_ name: String, _ exercise: String = "Squat", _ weekday: Weekday? = nil) -> Day {
        Day(name: name, weekday: weekday, exercises: [Exercise(name: exercise, sets: [Self.set])])
    }

    private func makePlan(_ name: String = "Push Pull Legs", schedule: Schedule = .rotation,
                          days: [Day], cycle: [CycleEntry]) -> Plan {
        Plan(name: name, units: .kg, schedule: schedule, days: days,
             importedAt: CoreTestSupport.date(1), sourceText: "", cycle: cycle)
    }

    private func upperLower() -> Plan {
        makePlan("Upper Lower", schedule: .weekday,
                 days: [day("Upper A", "Bench Press", .monday), day("Lower A", "Squat", .tuesday),
                        day("Upper B", "Row", .thursday), day("Lower B", "Deadlift", .friday)],
                 cycle: [])
    }

    // TQ34 (D78): how often, beneath the name — counted from the squares the symbol draws — and
    // the button the circle raises.
    func testHowOftenAndTheButton() {
        XCTAssertEqual(PlanText.howOften(CoreTestSupport.sevenDayRotation()), "6 days a week", "a seven-entry rotation")
        XCTAssertEqual(PlanText.howOften(upperLower()), "4 days a week", "a weekday plan")
        let fullBody = makePlan("Full Body", days: [day("A"), day("B"), day("C")],
                                cycle: [.day(0), .rest, .day(1), .rest, .rest, .day(2), .rest, .rest, .rest, .rest])
        XCTAssertEqual(PlanText.howOften(fullBody), "3 days every 10")
        XCTAssertEqual(PlanText.howOften(makePlan(days: [day("A")], cycle: [.day(0)])), "Every day", "a cycle of one")
        XCTAssertEqual(PlanText.howOften(makePlan(days: [day("A"), day("B")],
                                                  cycle: [.day(0), .day(1), .day(0), .day(1), .day(0), .day(1), .day(0)])),
                       "Every day", "seven workouts in seven days")
        XCTAssertEqual(PlanText.howOften(makePlan(schedule: .weekday, days: [day("Long", "Run", .sunday)], cycle: [])),
                       "1 day a week")
        XCTAssertEqual(PlanText.howOften(makePlan(days: [day("A")], cycle: [.day(0)] + Array(repeating: .rest, count: 6))),
                       "1 day a week")
        XCTAssertEqual(PlanText.howOften(makePlan(days: [day("A")], cycle: [.day(0), .day(5)])), "1 day every 2",
                       "an entry naming no day is grey in the symbol, and no workout in the words")
        XCTAssertNil(PlanText.howOften(makePlan(days: [], cycle: [])), "no days")
        XCTAssertNil(PlanText.howOften(makePlan(days: [day("A")], cycle: [.rest, .rest])), "nothing but rest")

        let ppl = CoreTestSupport.sevenDayRotation(), ul = upperLower()
        let plans = [ppl, ul]
        XCTAssertNil(PlanText.toUse(marked: nil, activePlanId: ppl.id, plans: plans), "nothing tapped: no button")
        XCTAssertNil(PlanText.toUse(marked: ppl.id, activePlanId: ppl.id, plans: plans),
                     "the active plan's own circle: no button")
        XCTAssertEqual(PlanText.toUse(marked: ul.id, activePlanId: ppl.id, plans: plans)?.id, ul.id)
        XCTAssertEqual(PlanText.useTitle(ul), "Use Upper Lower")
        XCTAssertNil(PlanText.toUse(marked: UUID(), activePlanId: ppl.id, plans: plans), "a plan deleted since")
        XCTAssertEqual(PlanText.toUse(marked: ul.id, activePlanId: nil, plans: plans)?.id, ul.id, "no plan active yet")
    }

    // TQ35 (D78): the cycle as squares — `DayColour`'s colours, the names beneath, the entry
    // Next up would start marked.
    func testTheCycleAsSquares() {
        let plan = CoreTestSupport.sevenDayRotation()
        let monday = RepeatBlock.squares(plan, today: CoreTestSupport.date(14), calendar: calendar)
        XCTAssertEqual(monday.map(\.name), ["Push", "Pull", "Legs", "Rest", "Push", "Pull", "Legs"])
        XCTAssertEqual(monday.map(\.colour), [.green, .orange, .purple, nil, .green, .orange, .purple])
        XCTAssertEqual(monday.map(\.colour), DayColour.cycle(of: plan), "the squares the list's symbol draws")
        XCTAssertEqual(monday.map(\.isNow), [true, false, false, false, false, false, false], "Monday is Push")
        XCTAssertTrue(monday.allSatisfy { $0.weekday == nil })
        let thursday = RepeatBlock.squares(plan, today: CoreTestSupport.date(17), calendar: calendar)
        XCTAssertEqual(thursday.indices.filter { thursday[$0].isNow }, [4],
                       "on Thursday's rest, the entry Next up would start: Friday's Push")

        let week = RepeatBlock.squares(upperLower(), today: CoreTestSupport.date(14), calendar: calendar)
        XCTAssertEqual(week.map { $0.weekday.map(WeekdayText.short) }, ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        XCTAssertEqual(week.map(\.name), ["Upper A", "Lower A", "Rest", "Upper B", "Lower B", "Rest", "Rest"])
        XCTAssertEqual(week.map(\.colour), [.green, .orange, nil, .purple, .pink, nil, nil])
        XCTAssertFalse(week.contains { $0.isNow }, "a weekday plan marks none, as since v1.1")
    }

    // TQ36 (D78): the page's rows are the whole cycle, repeats included; the same day twice
    // opens the same exercises, and no day is out of reach.
    func testThePageListsTheWholeCycle() throws {
        let plan = CoreTestSupport.sevenDayRotation()
        let rows = PlanPage.rows(plan)
        XCTAssertEqual(rows.map(\.name), ["Push", "Pull", "Legs", "Rest", "Push", "Pull", "Legs"])
        XCTAssertEqual(rows.map(\.dayIndex), [0, 1, 2, nil, 0, 1, 2])
        XCTAssertEqual(rows.map(\.colour), [.green, .orange, .purple, nil, .green, .orange, .purple])
        XCTAssertEqual(rows.map(\.id), Array(0..<7), "each row its own place, so opening one opens only it")
        XCTAssertTrue(rows.allSatisfy { $0.weekday == nil })
        let third = try XCTUnwrap(rows[2].dayIndex), seventh = try XCTUnwrap(rows[6].dayIndex)
        XCTAssertEqual(plan.days[third].exercises, plan.days[seventh].exercises, "Legs twice, the same exercises")
        XCTAssertNil(rows[3].dayIndex, "a rest has nothing to open")

        let week = PlanPage.rows(upperLower())
        XCTAssertEqual(week.map { $0.weekday.map(WeekdayText.full) }, ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"])
        XCTAssertEqual(week.map(\.name), ["Upper A", "Lower A", "Rest", "Upper B", "Lower B", "Rest", "Rest"])
        XCTAssertEqual(week.map(\.dayIndex), [0, 1, nil, 2, 3, nil, nil])

        let arms = makePlan(days: [day("Push"), day("Pull"), day("Legs"), day("Arms", "Curl")],
                            cycle: [.day(0), .day(1), .day(2), .rest, .day(9)])
        let armsRows = PlanPage.rows(arms)
        XCTAssertEqual(armsRows.map(\.name), ["Push", "Pull", "Legs", "Rest", "Rest", "Arms"],
                       "an entry naming no day is a rest, and a day the cycle never reaches follows the cycle")
        XCTAssertEqual(armsRows.last?.dayIndex, 3)
        XCTAssertEqual(armsRows.last?.colour, .pink)
        XCTAssertEqual(PlanPage.rows(makePlan(days: [day("A"), day("B")], cycle: [])).map(\.dayIndex), [0, 1],
                       "a plan with no cycle still opens every day")
        XCTAssertEqual(PlanPage.rows(makePlan(days: [], cycle: [])), [])
    }

    // TQ37 (D78, pin): the circle is the one way to change plan, and the page speaks in squares.
    func testTheCircleIsTheOneWay() throws {
        let list = try FixtureLoader.requiredDoc("JimmsBro/Features/Plans/PlansView.swift")
        let page = try FixtureLoader.requiredDoc("JimmsBro/Features/PlanDetail/PlanDetailView.swift")
        XCTAssertFalse(page.contains("Use this plan"), "Plan detail's ··· offers Use this plan again")
        XCTAssertFalse(page.contains("setActivePlan"), "Plan detail changes the active plan again")
        XCTAssertTrue(page.contains("RepeatBlock.squares(plan)"), "the page lost the cycle as squares")
        XCTAssertFalse(page.contains("RepeatBlock.chips("), "the page draws chips again")
        XCTAssertTrue(page.contains("PlanPage.rows(plan)"), "the page lost the whole cycle as rows")
        for literal in ["CycleSymbol(cycle: DayColour.cycle(of: plan))", "PlanText.howOften(plan)",
                        "\"checkmark.circle.fill\"", "\"circle\"", "PlanText.toUse(",
                        "PrimaryButton(title: PlanText.useTitle(", "setActivePlan"] {
            XCTAssertTrue(list.contains(literal), "the Plans list lost \(literal)")
        }
        XCTAssertFalse(list.contains("NavigationLink("), "a row's chevron is at its left, not a link's at its right")
    }
}

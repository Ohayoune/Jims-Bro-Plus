import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// V5 (v1.2) — Q44–Q52: the anchored rotation of D37 and the calendar cell of D38.
///
/// The owner's note: "if one day of the week is messed up then it compounds." v1.1 walked the
/// cycle forward from *today*, and `cyclePosition` only moved when a session completed — so a
/// missed workout slid every later day by one, and by one more for each further day missed.
final class ScheduleAnchorTests: XCTestCase {
    private let calendar = CoreTestSupport.utc()
    private func day(_ number: Int) -> Date { CoreTestSupport.date(number) }

    /// Push / Pull / Legs / rest, anchored to the 7th with Push just done.
    private func plan() -> Plan {
        var plan = Plan(name: "PPL", units: .kg, schedule: .rotation,
                        days: [Day(name: "Push", exercises: []),
                               Day(name: "Pull", exercises: []),
                               Day(name: "Legs", exercises: [])],
                        importedAt: day(1), sourceText: "",
                        cycle: [.day(0), .day(1), .day(2), .rest])
        plan.cyclePosition = 0                  // Push
        plan.cycleAnchor = calendar.startOfDay(for: day(7))
        return plan
    }

    private func entry(_ plan: Plan, _ number: Int) -> CycleEntry? {
        PlanSchedule.entry(plan, on: day(number), today: day(8), calendar: calendar)?.entry
    }

    // Q44: the pattern is nailed to the calendar, forwards and backwards.
    func testTheCycleIsProjectedFromItsAnchor() {
        let plan = plan()
        XCTAssertEqual(entry(plan, 7), .day(0), "the anchor day is the one that was done")
        XCTAssertEqual(entry(plan, 8), .day(1))
        XCTAssertEqual(entry(plan, 9), .day(2))
        XCTAssertEqual(entry(plan, 10), .rest)
        XCTAssertEqual(entry(plan, 11), .day(0), "and round again")
        XCTAssertEqual(entry(plan, 6), .rest, "days before the anchor are ordinary")
    }

    // Q45: **the compounding is gone.** Miss Tuesday, miss Wednesday, miss Thursday: Friday
    // still says exactly what it said before any of them were missed.
    func testMissingWorkoutsDoesNotSlideTheCalendar() {
        let plan = plan()
        let before = (8...20).map { entry(plan, $0) }
        // Time passes and nothing is completed, so nothing about the plan changes.
        let after = (8...20).map {
            PlanSchedule.entry(plan, on: day($0), today: day(12), calendar: calendar)?.entry
        }
        XCTAssertEqual(before, after, "a missed workout must not move any other day")
    }

    // Q46: the one moment the pattern is allowed to move is finishing a workout, and it moves
    // to the day that workout was actually done.
    func testFinishingAWorkoutReAnchorsToTheDayItHappened() {
        var plan = plan()
        PlanSchedule.advance(&plan, completedDayName: "Legs", on: day(12), calendar: calendar)
        XCTAssertEqual(plan.cyclePosition, 2)
        XCTAssertEqual(plan.cycleAnchor, calendar.startOfDay(for: day(12)))
        XCTAssertEqual(PlanSchedule.entry(plan, on: day(12), today: day(12), calendar: calendar)?.entry,
                       .day(2))
        XCTAssertEqual(PlanSchedule.entry(plan, on: day(13), today: day(12), calendar: calendar)?.entry,
                       .rest)
        XCTAssertEqual(PlanSchedule.entry(plan, on: day(14), today: day(12), calendar: calendar)?.entry,
                       .day(0))
    }

    // Q47: "Next up" is the next training day at or after today, and never the one just done.
    func testNextIsTheNextTrainingDayFromToday() throws {
        let plan = plan()
        let next = try XCTUnwrap(PlanSchedule.next(plan, today: day(7), calendar: calendar))
        XCTAssertEqual(next.dayIndex, 1, "Push was done on the anchor day; Pull is next")
        XCTAssertEqual(next.date, calendar.startOfDay(for: day(8)))
        // Three days later, without training, it is simply whatever today's pattern says next.
        let later = try XCTUnwrap(PlanSchedule.next(plan, today: day(10), calendar: calendar))
        XCTAssertEqual(later.dayIndex, 0, "the 10th is a rest day, so the 11th's Push is next")
        XCTAssertEqual(later.date, calendar.startOfDay(for: day(11)))
    }

    // Q48: Home and the calendar read the same function, so they cannot disagree.
    func testHomeAndTheCalendarAgreeOnTheNextDay() throws {
        var library = PlanLibrary()
        library.save(plan(), makeActive: true)
        let card = StartCard.current(library: library, now: day(8), calendar: calendar)
        guard case let .nextUp(_, dayIndex, name) = card else {
            return XCTFail("expected a rotation's next day, got \(card)")
        }
        XCTAssertEqual(name, "Pull")
        let entries = CalendarProjection.entries(month: day(8), activePlan: library.activePlan,
                                                 sessions: [], today: day(8), calendar: calendar)
        let eighth = try XCTUnwrap(entries.first { calendar.isDate($0.date, inSameDayAs: day(8)) })
        XCTAssertEqual(eighth.entry, .projected(planId: library.activePlan!.id, dayIndex: dayIndex))
    }

    // Q49: a workout the schedule expected and did not get is reported, not resolved silently.
    func testAMissedWorkoutIsReported() throws {
        var library = PlanLibrary()
        library.save(plan(), makeActive: true)
        // The 8th was Pull, and nothing was logged on it.
        let missed = try XCTUnwrap(PlanSchedule.missed(plan(), sessions: [], today: day(9),
                                                       calendar: calendar))
        XCTAssertEqual(missed.dayIndex, 1)
        XCTAssertEqual(missed.date, calendar.startOfDay(for: day(8)))

        let card = HomeStart.current(library: library, now: day(9), calendar: calendar)
        XCTAssertEqual(card.missed?.dayName, "Pull")
        XCTAssertTrue(try XCTUnwrap(card.missed?.text).hasPrefix("Pull was due "))

        // Having trained yesterday, nothing was missed.
        var session = CoreTestSupport.session(CoreTestSupport.plan(), start: day(8))
        session.endedAt = day(8)
        XCTAssertNil(PlanSchedule.missed(plan(), sessions: [session], today: day(9),
                                         calendar: calendar))
    }

    // Q50: a plan that predates anchors gets one, once, from the day its last workout actually
    // happened — which is what makes the grid and the card agree from the first launch.
    func testTheAnchorMigrationUsesTheDayTheLastWorkoutHappened() throws {
        var old = plan()
        old.cycleAnchor = nil                       // v1.1: a position, and no date for it
        XCTAssertTrue(PlanSchedule.anchorIfNeeded(&old, lastCompleted: day(7), today: day(8),
                                                  calendar: calendar))
        XCTAssertEqual(old.cycleAnchor, calendar.startOfDay(for: day(7)))
        XCTAssertEqual(PlanSchedule.next(old, today: day(8), calendar: calendar)?.date,
                       calendar.startOfDay(for: day(8)),
                       "Push was done on the 7th, so Pull is due today, not tomorrow")

        // With nothing completed to point at, it falls back to today — v1.1's reading exactly.
        var blind = plan(); blind.cycleAnchor = nil
        XCTAssertTrue(PlanSchedule.anchorIfNeeded(&blind, today: day(8), calendar: calendar))
        XCTAssertEqual(blind.cycleAnchor, calendar.startOfDay(for: day(8)))

        // And it only runs once.
        XCTAssertFalse(PlanSchedule.anchorIfNeeded(&old, today: day(9), calendar: calendar))
        // A plan that has completed nothing has no position to anchor.
        var fresh = plan(); fresh.cycleAnchor = nil; fresh.cyclePosition = nil
        XCTAssertFalse(PlanSchedule.anchorIfNeeded(&fresh, today: day(8), calendar: calendar))
    }

    // Q51: the cell says which workout it is (D38), and a rest day says nothing, which is how
    // the gaps become visible.
    func testCalendarCellsNameTheirDay() {
        let plan = plan()
        XCTAssertEqual(CalendarText.label(.projected(planId: plan.id, dayIndex: 0), plans: [plan]),
                       "Push")
        XCTAssertNil(CalendarText.label(.rest, plans: [plan]))
        XCTAssertNil(CalendarText.label(.none, plans: [plan]))
        XCTAssertEqual(CalendarText.short("Push"), "Push")
        XCTAssertEqual(CalendarText.short("Upper Body"), "Upper")
        XCTAssertEqual(CalendarText.short("Shoulders and Arms"), "Shou…")
        // A completed day names what was done, from the session rather than from the plan.
        var session = CoreTestSupport.session(CoreTestSupport.plan(), start: day(7))
        session.endedAt = day(7)
        XCTAssertEqual(CalendarText.label(.completed([session]), plans: [plan]), "Push")
    }

    // Q52: and each cell reads as one sentence, because a four-letter label is no use aloud.
    func testCalendarCellsReadAsASentence() {
        let plan = plan()
        let projected = CalendarDay(date: day(8), entry: .projected(planId: plan.id, dayIndex: 1))
        XCTAssertTrue(CalendarText.spoken(projected, plans: [plan]).contains("Planned: Pull"))
        let rest = CalendarDay(date: day(10), entry: .rest)
        XCTAssertTrue(CalendarText.spoken(rest, plans: [plan]).hasSuffix("Rest day"))
    }
}

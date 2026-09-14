import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// T5 (v1.7) — a colour per day (D65, SPEC §6.41): where the palette wraps (T22), what it may
/// not be (T23), and one day as one colour wherever Core hands it out (T25). T24 is the phone's:
/// the same day in the same colour on every screen, in light and in dark.
final class DayColourTests: XCTestCase {
    private let calendar = CoreTestSupport.utc()

    /// Push / Pull / Legs / rest, two sets of each exercise so that a logged set leaves a rest.
    private func plan() -> Plan {
        func day(_ name: String, _ exercise: String) -> Day {
            let set = SetTarget(work: .reps(.range(min: 8, max: 12)), weight: 60, restSeconds: 90)
            return Day(name: name, exercises: [Exercise(name: exercise, repRange: RepRange(min: 8, max: 12),
                                                        sets: [set, set])])
        }
        return Plan(name: "Push Pull Legs", units: .kg, schedule: .rotation,
                    days: [day("Push", "Bench Press"), day("Pull", "Row"), day("Legs", "Squat")],
                    importedAt: CoreTestSupport.date(1), sourceText: "",
                    cycle: [.day(0), .day(1), .day(2), .rest])
    }

    /// A finished workout of the plan's `dayIndex`-th day.
    private func finished(_ plan: Plan, dayIndex: Int, on day: Int) throws -> Session {
        var session = try XCTUnwrap(Session.start(plan: plan, dayIndex: dayIndex, now: CoreTestSupport.date(day)))
        session.endedAt = CoreTestSupport.date(day, hour: 13)
        return session
    }

    // T22: six days, six positions; the seventh wraps to the first.
    func testSixDaysSixPositionsTheSeventhWraps() {
        XCTAssertEqual((0..<6).map { DayColour.index(dayIndex: $0) }, [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(DayColour.index(dayIndex: 6), 0, "the seventh day wraps to the first")
        XCTAssertEqual(DayColour.index(dayIndex: 13), 1)
        XCTAssertEqual((0..<7).map { DayColour.of(dayIndex: $0) },
                       [.green, .orange, .purple, .pink, .teal, .indigo, .green])
        XCTAssertEqual(DayColour.index(dayIndex: -1), 5, "never out of range, whatever it is handed")
    }

    // T23: no accent (tappable, D59), no red (destructive), no yellow (a warning) — and the
    // accent is a blue, so no blue either.
    func testThePaletteIsNotTheAccentRedOrYellow() {
        let names = DayColour.allCases.map(\.rawValue)
        XCTAssertEqual(names, ["green", "orange", "purple", "pink", "teal", "indigo"])
        for forbidden in ["accent", "blue", "red", "yellow"] {
            XCTAssertFalse(names.contains { $0.lowercased().contains(forbidden) }, forbidden)
        }
    }

    // T23: and the view layer draws each name as the system colour of that name and nothing
    // else, so no day can be drawn in the accent, red or yellow whatever Core calls it.
    func testEachDayColourIsTheSystemColourOfItsName() throws {
        guard let source = FixtureLoader.doc("JimmsBro/DaySquare.swift") else {
            throw XCTSkip("the checkout is outside the simulator's sandbox; this pin runs on the host routes")
        }
        for colour in DayColour.allCases {
            XCTAssertTrue(source.contains("case .\(colour.rawValue): return .\(colour.rawValue)\n"), colour.rawValue)
        }
        for forbidden in ["accentColor", ".red", ".yellow", ".blue", ".tint", "Color.done"] {
            XCTAssertFalse(source.contains(forbidden), forbidden)
        }
    }

    // TQ23 (D75, v1.9): a plan's cycle as the ···'s symbol draws it — a square per entry in its
    // day's colour and grey (nil) for rest, a weekday plan Monday to Sunday, and past fourteen
    // the first fourteen and a trailing mark.
    func testTheCycleSymbol() throws {
        let set = SetTarget(work: .reps(.fixed(5)), weight: 100, restSeconds: 180)
        func day(_ name: String, _ weekday: Weekday? = nil) -> Day {
            Day(name: name, weekday: weekday, exercises: [Exercise(name: "Squat", sets: [set])])
        }
        let rotation = Plan(name: "Push Pull Legs", units: .kg, schedule: .rotation,
                            days: [day("Push"), day("Pull"), day("Legs")],
                            importedAt: CoreTestSupport.date(1), sourceText: "",
                            cycle: [.day(0), .day(1), .day(2), .rest, .day(0), .day(1), .day(2)])
        XCTAssertEqual(DayColour.cycle(of: rotation), [.green, .orange, .purple, nil, .green, .orange, .purple],
                       "the repeat block as written, from its first entry")
        var dead = rotation
        dead.cycle = [.day(0), .day(5)]
        XCTAssertEqual(DayColour.cycle(of: dead), [.green, nil], "an entry naming no day is grey")

        let weekday = Plan(name: "Push Pull Legs", units: .kg, schedule: .weekday,
                           days: [day("Push", .monday), day("Pull", .wednesday), day("Legs", .friday)],
                           importedAt: CoreTestSupport.date(1), sourceText: "", cycle: [])
        XCTAssertEqual(DayColour.cycle(of: weekday), [.green, nil, .orange, nil, .purple, nil, nil],
                       "Monday to Sunday")

        let week = CycleGlyph(DayColour.cycle(of: rotation))
        XCTAssertEqual(week.squares.count, 7)
        XCTAssertFalse(week.continues)
        let fortnight = CycleGlyph(Array(repeating: DayColour?.some(.green), count: 14))
        XCTAssertEqual(fortnight.squares.count, 14)
        XCTAssertFalse(fortnight.continues, "fourteen fit")
        let month = (0..<31).map { $0 % 3 == 2 ? nil : DayColour.of(dayIndex: $0) }
        let cut = CycleGlyph(month)
        XCTAssertEqual(cut.squares, Array(month.prefix(14)), "the first fourteen, in order")
        XCTAssertTrue(cut.continues, "and a trailing mark")

        guard let square = FixtureLoader.doc("JimmsBro/DaySquare.swift"),
              let today = FixtureLoader.doc("JimmsBro/Features/Home/HomeView.swift") else {
            throw XCTSkip("the checkout is outside the simulator's sandbox; this pin runs on the host routes")
        }
        XCTAssertTrue(square.contains("let glyph = CycleGlyph(cycle)"), "CycleSymbol no longer cuts through CycleGlyph")
        XCTAssertTrue(today.contains("CycleSymbol(cycle: cycle)"), "Change plan lost its symbol")
    }

    // T25: one day, one colour, wherever Core hands it out — Today's card, the calendar's
    // planned and finished days, a History row and the Lock Screen — so that T24 on the phone
    // is about the drawing, not the arithmetic. And derived: move the day and its colour moves.
    func testOneDayIsOneColourEverywhere() throws {
        var library = PlanLibrary()
        library.save(plan(), makeActive: true)
        let saved = try XCTUnwrap(library.plans.first)
        let plans = [saved]

        // Today: the colour of the day the card names; none on the empty card.
        let card = HomeStart.current(library: library, now: CoreTestSupport.date(9), calendar: calendar)
        let shown = try XCTUnwrap(card.dayIndex)
        XCTAssertEqual(card.dayColour, DayColour.of(dayIndex: shown))
        let empty = HomeStart.current(library: PlanLibrary(), now: CoreTestSupport.date(9), calendar: calendar)
        XCTAssertNil(empty.dayColour)

        // The calendar: a planned day is its day's colour, a finished day its workout's — the
        // first's when it holds two, the one its label names.
        XCTAssertEqual(DayEntry.projected(planId: saved.id, dayIndex: 1).dayColour(plans: plans), .orange)
        XCTAssertNil(DayEntry.rest.dayColour(plans: plans))
        XCTAssertNil(DayEntry.none.dayColour(plans: plans))
        let legs = try finished(saved, dayIndex: 2, on: 8)
        let pull = try finished(saved, dayIndex: 1, on: 8)
        XCTAssertEqual(DayEntry.completed([legs]).dayColour(plans: plans), .purple)
        XCTAssertEqual(DayEntry.completed([legs, pull]).dayColour(plans: plans), .purple)

        // A History row: the workout's day in its plan, by the plan's id and the day's name.
        XCTAssertEqual(DayColour.of(session: legs, plans: plans), .purple)
        var spaced = legs
        spaced.dayName = "  legs "
        XCTAssertEqual(DayColour.of(session: spaced, plans: plans), .purple, "matched as the label is")
        XCTAssertNil(DayColour.of(session: legs, plans: []), "its plan is gone")
        var renamed = saved
        renamed.days[2].name = "Lower"
        XCTAssertNil(DayColour.of(session: legs, plans: [renamed]), "its day was renamed")

        // Derived, never stored: reorder the days and the colour follows the day's new place.
        var reordered = saved
        reordered.days.swapAt(0, 2)
        XCTAssertEqual(DayColour.of(session: legs, plans: [reordered]), .green)

        // Mid-workout, Today's square is the running session's day.
        try library.startDay(planId: saved.id, dayIndex: 2, now: CoreTestSupport.date(9))
        let running = HomeStart.current(library: library, now: CoreTestSupport.date(9), calendar: calendar)
        XCTAssertTrue(running.isInProgress)
        XCTAssertEqual(running.dayColour, .purple)

        // The Lock Screen: working and resting alike carry the day; without the plans, nothing.
        let now = CoreTestSupport.now
        var engine = SessionEngine(session: try XCTUnwrap(Session.start(plan: saved, dayIndex: 1, now: now)),
                                   settings: CoreTestSupport.classic, now: now)
        let working = try XCTUnwrap(WorkoutActivityState.of(engine.active, now: now, plans: plans))
        XCTAssertFalse(working.isBreak)
        XCTAssertEqual(working.dayColour, .orange)
        let unplanned = try XCTUnwrap(WorkoutActivityState.of(engine.active, now: now))
        XCTAssertNil(unplanned.dayColour)
        engine.apply(.logSet(step: 0, result: .reps(count: 10, weight: 60)), now: now)
        let resting = try XCTUnwrap(WorkoutActivityState.of(engine.active, now: now, plans: plans))
        XCTAssertTrue(resting.isBreak)
        XCTAssertEqual(resting.dayColour, .orange)
    }
}

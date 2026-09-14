import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// Q1 (v1.9) — a day swapped, not a plan changed (D72), and Slide (D73): TQ1–TQ13.
///
/// The plan's example: Push · Pull · Legs · Rest · Push · Pull · Legs, anchored so Monday
/// 14 September 2026 is Push (Push was done on the 7th). Push is green, Pull orange, Legs
/// purple (§6.41). The owner tapped Wednesday's square and finished Legs on Monday.
final class SwapTests: XCTestCase {
    private let calendar = CoreTestSupport.utc()
    private func day(_ n: Int) -> Date { CoreTestSupport.date(n) }
    private func start(_ n: Int) -> Date { calendar.startOfDay(for: day(n)) }

    private static let set = SetTarget(work: .reps(.fixed(5)), weight: 60, restSeconds: 90)

    /// The seven-day rotation, Push done on the 7th.
    private func rotation() -> Plan {
        func day(_ name: String, _ exercise: String) -> Day {
            Day(name: name, exercises: [Exercise(name: exercise, sets: [Self.set])])
        }
        var plan = Plan(name: "Push Pull Legs", units: .kg, schedule: .rotation,
                        days: [day("Push", "Bench Press"), day("Pull", "Row"), day("Legs", "Squat")],
                        importedAt: self.day(1), sourceText: "",
                        cycle: [.day(0), .day(1), .day(2), .rest, .day(0), .day(1), .day(2)])
        plan.cyclePosition = 0
        plan.cycleAnchor = start(7)
        return plan
    }

    /// Mon Push / Wed Pull / Fri Legs.
    private func weekdayPlan() -> Plan {
        func day(_ name: String, _ weekday: Weekday, _ exercise: String) -> Day {
            Day(name: name, weekday: weekday, exercises: [Exercise(name: exercise, sets: [Self.set])])
        }
        return Plan(name: "Weekdays", units: .kg, schedule: .weekday,
                    days: [day("Push", .monday, "Bench Press"), day("Pull", .wednesday, "Row"),
                           day("Legs", .friday, "Squat")],
                    importedAt: self.day(1), sourceText: "", cycle: [])
    }

    private func library(_ plan: Plan) -> PlanLibrary {
        var library = PlanLibrary()
        library.calendar = calendar
        library.save(plan, makeActive: true)
        return library
    }

    /// A workout of `plan`'s `dayIndex`-th day, every set logged, on the `n`th at noon.
    private func finished(_ plan: Plan, dayIndex: Int, on n: Int) throws -> Session {
        var session = try XCTUnwrap(Session.start(plan: plan, dayIndex: dayIndex, now: day(n)))
        for i in session.steps.indices {
            session.steps[i].status = .logged
            session.steps[i].result = .reps(count: 5, weight: 60)
            session.steps[i].startedAt = day(n)
            session.steps[i].loggedAt = day(n).addingTimeInterval(34)
        }
        session.endedAt = day(n).addingTimeInterval(60)
        return session
    }

    /// Finishes a workout through the library's own completion, the way the engine does.
    private func complete(_ library: inout PlanLibrary, _ plan: Plan? = nil, dayIndex: Int, on n: Int) throws {
        let plan = try XCTUnwrap(plan ?? library.activePlan)
        let session = try finished(plan, dayIndex: dayIndex, on: n)
        library.engine = SessionEngine(active: ActiveSession(session: session, phase: .completed),
                                       settings: library.settings)
        library.completeSession()
    }

    private func swap(_ library: PlanLibrary, on n: Int) -> DaySwap? {
        library.activePlan.flatMap {
            PlanSchedule.swap($0, on: day(n), swaps: library.swaps, calendar: calendar)
        }
    }

    private func week(_ library: PlanLibrary, from n: Int) -> [DayEntry] {
        CalendarProjection.next(days: 7, from: day(n), activePlan: library.activePlan,
                                sessions: library.sessions, swaps: library.swaps, today: day(n),
                                calendar: calendar).map(\.entry)
    }

    private func strip(_ library: PlanLibrary, on n: Int) -> [WeekStrip.Square] {
        WeekStrip.days(plan: library.activePlan, sessions: library.sessions, swaps: library.swaps,
                       today: day(n), calendar: calendar)
    }

    private func card(_ library: PlanLibrary, on n: Int, showing: Int = 0,
                      reopened: Bool = false) -> HomeStart {
        HomeStart.current(library: library, now: day(n), calendar: calendar, showing: showing,
                          reopened: reopened)
    }

    /// The plan's example: Legs on Monday the 14th, which expected Push.
    private func legsOnMonday() throws -> PlanLibrary {
        var library = library(rotation())
        try complete(&library, dayIndex: 2, on: 14)
        return library
    }

    // TQ1: Legs on a Monday expecting Push writes two swaps, and moves nothing in the plan.
    func testAnOffDayWorkoutWritesTwoSwapsAndMovesNothing() throws {
        let library = try legsOnMonday()
        let plan = try XCTUnwrap(library.activePlan)
        XCTAssertEqual(plan.cyclePosition, 0, "the cycle position is not moved")
        XCTAssertEqual(plan.cycleAnchor, start(7), "the anchor is not moved")
        XCTAssertEqual(library.swaps.count, 2)

        let monday = try XCTUnwrap(swap(library, on: 14))
        XCTAssertEqual(monday.date, start(14))
        XCTAssertEqual(monday.original, .day(name: "Push"))
        XCTAssertEqual(monday.replacement, .day(name: "Legs"))
        XCTAssertNil(monday.askedOn)
        XCTAssertTrue(monday.answered, "today's own record asks nothing")
        XCTAssertFalse(monday.isQuestion)

        let wednesday = try XCTUnwrap(swap(library, on: 16))
        XCTAssertEqual(wednesday.date, start(16), "the next date the pattern projects Legs")
        XCTAssertEqual(wednesday.original, .day(name: "Legs"))
        XCTAssertEqual(wednesday.replacement, .day(name: "Push"), "the default: today's day")
        XCTAssertEqual(wednesday.askedOn, start(14))
        XCTAssertFalse(wednesday.answered, "the question is open")
        XCTAssertTrue(wednesday.isQuestion)
        XCTAssertNil(swap(library, on: 15))
    }

    // TQ2: the projection for Monday…Sunday reads Legs (completed), Pull, Push, rest, Push,
    // Pull, Legs — and the strip, the card and the grid all say so.
    func testTheProjectionReadsTheSwaps() throws {
        let library = try legsOnMonday()
        let plan = try XCTUnwrap(library.activePlan)
        let entries = week(library, from: 14)
        guard case let .completed(sessions)? = entries.first else { return XCTFail("Monday is done") }
        XCTAssertEqual(sessions.map(\.dayName), ["Legs"])
        XCTAssertEqual(Array(entries.dropFirst()),
                       [.projected(planId: plan.id, dayIndex: 1), .projected(planId: plan.id, dayIndex: 0),
                        .rest, .projected(planId: plan.id, dayIndex: 0),
                        .projected(planId: plan.id, dayIndex: 1), .projected(planId: plan.id, dayIndex: 2)])

        // The strip: Monday purple with a green dot under it, Wednesday green with a ring.
        let squares = strip(library, on: 14)
        XCTAssertEqual(squares.map(\.dayName), ["Legs", "Pull", "Push", nil, "Push", "Pull", "Legs"])
        XCTAssertEqual(squares[0].colour, .purple)
        XCTAssertTrue(squares[0].hasDot)
        XCTAssertEqual(squares[0].original, .green, "the dot is the pattern's colour")
        XCTAssertEqual(squares[0].ring, .none)
        XCTAssertEqual(squares[2].colour, .green)
        XCTAssertTrue(squares[2].hasDot)
        XCTAssertEqual(squares[2].original, .purple)
        XCTAssertEqual(squares[2].ring, .asking)
        XCTAssertEqual(squares[2].spoken, "Wednesday, Push, question")
        XCTAssertFalse(squares[1].hasDot)
        XCTAssertEqual(squares[1].ring, .none)
        XCTAssertEqual(squares[1].spoken, "Tomorrow, Pull")
        XCTAssertFalse(squares.contains { $0.outline })

        // Today's card: done today; Tuesday's: Pull; the Wednesday square's card carries the
        // question with its options in order.
        let today = card(library, on: 14)
        XCTAssertTrue(today.isRest)
        XCTAssertEqual(today.buttonMark, .check)
        XCTAssertEqual(today.buttonTitle, HomeStart.doneTitle)
        XCTAssertNil(today.question, "Monday's own record asks nothing")
        XCTAssertEqual(StartCard.current(library: library, now: day(15), calendar: calendar),
                       .nextUp(planId: plan.id, dayIndex: 1, dayName: "Pull"))
        let wednesday = card(library, on: 14, showing: 2)
        XCTAssertEqual(wednesday.buttonTitle, "Start Wednesday's Push")
        let question = try XCTUnwrap(wednesday.question)
        XCTAssertEqual(question.date, start(16))
        XCTAssertEqual(question.originalName, "Legs")
        XCTAssertEqual(question.options.map(\.kind), [.rest, .todays, .keep, .slide])
        XCTAssertEqual(question.options.map(\.title), ["Rest", "Push", "Legs", "Slide"])
        XCTAssertEqual(question.options.map(\.isDefault), [false, true, false, false])
        XCTAssertEqual(question.chosen, .day(name: "Push"))
        XCTAssertFalse(question.answered)

        // The month grid reads the same slots (the owner's 9): Wednesday is named Push.
        let grid = CalendarProjection.entries(month: day(14), activePlan: plan, sessions: library.sessions,
                                              swaps: library.swaps, today: day(14), calendar: calendar)
        XCTAssertEqual(CalendarText.label(grid[15].entry, plans: [plan]), "Push")
        XCTAssertEqual(grid[15].entry.dayColour(plans: [plan]), .green)
    }

    // TQ3: the same workout on a Thursday rest day: the original is rest, the default is
    // rest, and the options are Rest, Keep and Slide.
    func testAnOffDayWorkoutOnARestDay() throws {
        var library = library(rotation())
        try complete(&library, dayIndex: 2, on: 17)
        XCTAssertEqual(library.activePlan?.cycleAnchor, start(7))
        let thursday = try XCTUnwrap(swap(library, on: 17))
        XCTAssertEqual(thursday.original, .rest)
        XCTAssertEqual(thursday.replacement, .day(name: "Legs"))
        XCTAssertTrue(thursday.answered)
        let sunday = try XCTUnwrap(swap(library, on: 20), "the next Legs is Sunday's")
        XCTAssertEqual(sunday.original, .day(name: "Legs"))
        XCTAssertEqual(sunday.replacement, .rest, "today was rest, so today's day is rest")
        XCTAssertEqual(sunday.askedOn, start(17))
        XCTAssertFalse(sunday.answered)
        let question = try XCTUnwrap(library.question(for: sunday.id, now: day(17)))
        XCTAssertEqual(question.options.map(\.kind), [.rest, .keep, .slide])
        XCTAssertEqual(question.options.map(\.isDefault), [true, false, false])
        // The strip: Thursday purple with a grey dot (the pattern said rest), Sunday grey
        // with a purple dot and the ring.
        let squares = strip(library, on: 17)
        XCTAssertEqual(squares[0].colour, .purple)
        XCTAssertTrue(squares[0].hasDot)
        XCTAssertNil(squares[0].original)
        XCTAssertTrue(squares[3].isRest)
        XCTAssertTrue(squares[3].hasDot)
        XCTAssertEqual(squares[3].original, .purple)
        XCTAssertEqual(squares[3].ring, .asking)
        XCTAssertEqual(squares[3].spoken, "Sunday, rest, question")
    }

    // TQ4: Push already done Monday, then Legs: Monday keeps its Push, and Wednesday's
    // options are Rest and Keep (and Slide), default Rest (the owner's 8).
    func testTodaysOwnDayDoneFirstKeepsTodaysColour() throws {
        var library = library(rotation())
        try complete(&library, dayIndex: 0, on: 14)
        XCTAssertEqual(library.activePlan?.cycleAnchor, start(14), "the expected day re-anchors")
        XCTAssertEqual(library.swaps, [])
        try complete(&library, dayIndex: 2, on: 14)
        XCTAssertNil(swap(library, on: 14), "Monday keeps what it has")
        XCTAssertEqual(library.swaps.count, 1)
        let wednesday = try XCTUnwrap(swap(library, on: 16))
        XCTAssertEqual(wednesday.original, .day(name: "Legs"))
        XCTAssertEqual(wednesday.replacement, .rest, "today's colour is taken")
        XCTAssertEqual(wednesday.askedOn, start(14))
        let question = try XCTUnwrap(library.question(for: wednesday.id, now: day(14)))
        XCTAssertEqual(question.options.map(\.kind), [.rest, .keep, .slide])
        XCTAssertEqual(question.options.map(\.isDefault), [true, false, false])
        // Monday's square is Push, the first workout's, as the calendar labels it; no dot.
        let squares = strip(library, on: 14)
        XCTAssertEqual(squares[0].dayName, "Push")
        XCTAssertFalse(squares[0].hasDot)
        XCTAssertTrue(card(library, on: 14).isRest)
        XCTAssertEqual(card(library, on: 14).buttonTitle, HomeStart.doneTitle)
    }

    // TQ5: each answer's projection — Rest, Push, Legs — and that Keep or Rest raise no
    // missed message on Tuesday.
    func testEachAnswersProjection() throws {
        let asked = try legsOnMonday()
        let plan = try XCTUnwrap(asked.activePlan)
        let id = try XCTUnwrap(swap(asked, on: 16)).id
        func answered(_ slot: DaySwap.Slot) -> PlanLibrary {
            var library = asked
            library.answer(swap: id, with: slot)
            return library
        }
        let rest = answered(.rest)
        XCTAssertEqual(week(rest, from: 14)[2], .rest)
        XCTAssertEqual(strip(rest, on: 14)[2].ring, .answered)
        XCTAssertTrue(strip(rest, on: 14)[2].hasDot)
        XCTAssertEqual(strip(rest, on: 14)[2].original, .purple)
        XCTAssertEqual(strip(rest, on: 14)[2].spoken, "Wednesday, rest")
        XCTAssertNil(card(rest, on: 15).missed, "Legs is not repeated, and nothing is said about Push")
        XCTAssertEqual(card(rest, on: 14, showing: 2).question?.answered, true)
        XCTAssertEqual(card(rest, on: 14, showing: 2).question?.chosen, .rest)

        let push = answered(.day(name: "Push"))
        XCTAssertEqual(week(push, from: 14)[2], .projected(planId: plan.id, dayIndex: 0))
        XCTAssertEqual(strip(push, on: 14)[2].ring, .answered)

        let keep = answered(.day(name: "Legs"))
        XCTAssertEqual(week(keep, from: 14)[2], .projected(planId: plan.id, dayIndex: 2))
        XCTAssertFalse(strip(keep, on: 14)[2].hasDot, "keeping is no override, so no dot")
        XCTAssertEqual(strip(keep, on: 14)[2].ring, .answered, "but the swap stays, answered")
        XCTAssertEqual(keep.swaps.count, 2)
        XCTAssertNil(card(keep, on: 15).missed)
        // Every answer leaves the plan alone.
        for library in [rest, push, keep] {
            XCTAssertEqual(library.activePlan?.cyclePosition, 0)
            XCTAssertEqual(library.activePlan?.cycleAnchor, start(7))
        }
    }

    // TQ6: Slide re-anchors exactly as advance would have on Monday, remembers what it
    // replaced, and answering Push afterwards restores it (D73).
    func testSlideCarriesOnFromTheWorkoutYouDid() throws {
        var library = try legsOnMonday()
        let plan = try XCTUnwrap(library.activePlan)
        let id = try XCTUnwrap(swap(library, on: 16)).id
        var expected = plan
        PlanSchedule.advance(&expected, completedDayName: "Legs", on: day(14), calendar: calendar)

        library.answer(swap: id, with: .slide)
        XCTAssertEqual(library.activePlan?.cyclePosition, expected.cyclePosition)
        XCTAssertEqual(library.activePlan?.cyclePosition, 2)
        XCTAssertEqual(library.activePlan?.cycleAnchor, start(14))
        let slid = try XCTUnwrap(swap(library, on: 16))
        XCTAssertEqual(slid.replacement, .slide)
        XCTAssertTrue(slid.answered)
        XCTAssertEqual(slid.slideUndo, SlideUndo(cyclePosition: 0, cycleAnchor: start(7)))
        // Tuesday Rest, Wednesday Push, Thursday Pull, Friday Legs — what v1.8 did after every
        // off-day workout, chosen now on purpose.
        XCTAssertEqual(Array(week(library, from: 14).dropFirst(1).prefix(4)),
                       [.rest, .projected(planId: plan.id, dayIndex: 0),
                        .projected(planId: plan.id, dayIndex: 1), .projected(planId: plan.id, dayIndex: 2)])
        let squares = strip(library, on: 14)
        XCTAssertFalse(squares[2].hasDot, "the pattern decides, so nothing is overridden")
        XCTAssertEqual(squares[2].ring, .answered)
        XCTAssertFalse(squares[0].hasDot, "and Monday's Legs is the pattern's own now")

        library.answer(swap: id, with: .day(name: "Push"))
        XCTAssertEqual(library.activePlan?.cyclePosition, 0, "leaving the slide puts the position back")
        XCTAssertEqual(library.activePlan?.cycleAnchor, start(7))
        let restored = try XCTUnwrap(swap(library, on: 16))
        XCTAssertNil(restored.slideUndo)
        XCTAssertEqual(restored.replacement, .day(name: "Push"))
        XCTAssertEqual(week(library, from: 14)[2], .projected(planId: plan.id, dayIndex: 0))
    }

    // TQ7: Push on Wednesday after the swap moves nothing and writes nothing; Push on
    // Monday, as expected, re-anchors to the day and keeps the grid.
    func testWhatTheDateSaidIsNoSwap() throws {
        var swapped = try legsOnMonday()
        let planBefore = swapped.activePlan
        let swapsBefore = swapped.swaps
        try complete(&swapped, dayIndex: 0, on: 16)
        XCTAssertEqual(swapped.activePlan, planBefore)
        XCTAssertEqual(swapped.swaps, swapsBefore)
        XCTAssertEqual(swapped.sessions.count, 2)

        var expected = library(rotation())
        let grid = week(expected, from: 14)
        try complete(&expected, dayIndex: 0, on: 14)
        XCTAssertEqual(expected.swaps, [])
        XCTAssertEqual(expected.activePlan?.cyclePosition, 0)
        XCTAssertEqual(expected.activePlan?.cycleAnchor, start(14), "a refresh of the anchor")
        XCTAssertEqual(Array(week(expected, from: 14).dropFirst()), Array(grid.dropFirst()),
                       "that changes nothing on the grid — even with Push twice in the cycle")
    }

    // TQ8: a session of another plan, or a discarded one, writes nothing.
    func testOtherPlansAndDiscardsWriteNothing() throws {
        var library = library(rotation())
        var other = rotation()
        other.name = "Other"
        other.cycleAnchor = nil
        other.cyclePosition = nil
        library.save(other)
        let active = try XCTUnwrap(library.activePlan)
        try complete(&library, other, dayIndex: 2, on: 14)
        XCTAssertEqual(library.swaps, [], "the owner's 8")
        XCTAssertEqual(library.activePlan, active)

        var discarded = self.library(rotation())
        try discarded.startDay(planId: try XCTUnwrap(discarded.activePlanId), dayIndex: 2, now: day(14))
        discarded.discardSession()
        XCTAssertEqual(discarded.swaps, [])
        XCTAssertEqual(discarded.activePlan?.cycleAnchor, start(7))

        // And a finished workout with nothing logged records nothing either.
        var nothing = self.library(rotation())
        let session = try XCTUnwrap(Session.start(plan: try XCTUnwrap(nothing.activePlan), dayIndex: 2, now: day(14)))
        nothing.engine = SessionEngine(active: ActiveSession(session: session, phase: .completed),
                                       settings: nothing.settings)
        nothing.completeSession()
        XCTAssertEqual(nothing.swaps, [])
    }

    // TQ9: the missed rule reads the swaps: no "Push was due Monday" after the swap; "Push
    // was due Wednesday" on Thursday when the swapped Push was not done; a date whose swap
    // says rest is never missed.
    func testMissedReadsTheSwaps() throws {
        var library = try legsOnMonday()
        let plan = try XCTUnwrap(library.activePlan)
        XCTAssertNil(PlanSchedule.missed(plan, sessions: library.sessions, swaps: library.swaps,
                                         today: day(15), calendar: calendar))
        XCTAssertNil(card(library, on: 15).missed)
        let thursday = try XCTUnwrap(PlanSchedule.missed(plan, sessions: library.sessions, swaps: library.swaps,
                                                         today: day(17), calendar: calendar))
        XCTAssertEqual(thursday.date, start(16))
        XCTAssertEqual(thursday.name, "Push")
        XCTAssertEqual(thursday.dayIndex, 0, "Do it now starts the swapped day")
        let message = try XCTUnwrap(card(library, on: 17).missed)
        XCTAssertTrue(message.text.hasPrefix("Push was due "), message.text)
        XCTAssertEqual(message.dayIndex, 0)

        let id = try XCTUnwrap(swap(library, on: 16)).id
        library.answer(swap: id, with: .rest)
        let afterRest = try XCTUnwrap(PlanSchedule.missed(plan, sessions: library.sessions, swaps: library.swaps,
                                                          today: day(17), calendar: calendar))
        XCTAssertEqual(afterRest.name, "Pull", "Wednesday's rest is never missed; Tuesday's Pull was")
        XCTAssertEqual(afterRest.date, start(15))
    }

    // TQ10: swaps.json round-trips, a missing file is no swaps, an unreadable one is set
    // aside, the frozen file decodes, the v1.7 backup restores with none and the v1.9 one
    // with its swaps, and deleting a plan deletes its swaps.
    func testSwapsOnDisk() async throws {
        let root = CoreTestSupport.makeRoot("Swaps")
        defer { CoreTestSupport.discard(root) }
        let store = Store(root: root)
        let fresh = await store.load()
        XCTAssertEqual(fresh.swaps, [], "a missing file is no swaps")
        XCTAssertEqual(fresh.corruptFiles, [])

        let library = try legsOnMonday()
        try await store.save(swaps: library.swaps)
        let loaded = await store.load()
        XCTAssertEqual(loaded.swaps, library.swaps)
        let json = try XCTUnwrap(String(data: try Data(contentsOf: root.appendingPathComponent("swaps.json")), encoding: .utf8))
        XCTAssertTrue(json.contains("\"fileVersion\" : 1"))
        XCTAssertTrue(json.contains("\"kind\" : \"day\""), "a slot is written as a kind")

        try Data("not a swaps file".utf8).write(to: root.appendingPathComponent("swaps.json"))
        let aside = await store.load()
        XCTAssertEqual(aside.swaps, [])
        XCTAssertEqual(aside.corruptFiles, ["swaps.json"])
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertTrue(names.contains { $0.hasPrefix("swaps.json.corrupt-") }, "set aside, never deleted")

        // The frozen file, as the app wrote it.
        let frozen = try StoreCoder.decode(SwapsPayload.self, from: try FixtureLoader.data("store/v1/swaps.json"))
        XCTAssertEqual(frozen.swaps.count, 2)
        XCTAssertEqual(frozen.swaps.map(\.original), [.day(name: "Push"), .day(name: "Legs")])
        XCTAssertEqual(frozen.swaps.map(\.replacement), [.day(name: "Legs"), .day(name: "Push")])
        XCTAssertEqual(frozen.swaps.map(\.answered), [true, false])
        XCTAssertEqual(frozen.swaps[1].askedOn, frozen.swaps[0].date)
        // Identity is required; the rest may be absent.
        let minimal = Data("""
        {"fileVersion":1,"swaps":[{"id":"\(UUID().uuidString)","planId":"\(UUID().uuidString)",
         "date":"2026-09-16T00:00:00Z","original":{"kind":"rest"},"replacement":{"kind":"slide"},"answered":true}]}
        """.utf8)
        XCTAssertEqual(try StoreCoder.decode(SwapsPayload.self, from: minimal).swaps.first?.replacement, .slide)
        let broken = Data(#"{"fileVersion":1,"swaps":[{"date":"2026-09-16T00:00:00Z","answered":true}]}"#.utf8)
        XCTAssertThrowsError(try StoreCoder.decode(SwapsPayload.self, from: broken))
        let unknown = Data("""
        {"fileVersion":1,"swaps":[{"id":"\(UUID().uuidString)","planId":"\(UUID().uuidString)",
         "date":"2026-09-16T00:00:00Z","original":{"kind":"rest"},"replacement":{"kind":"holiday"},"answered":true}]}
        """.utf8)
        XCTAssertThrowsError(try StoreCoder.decode(SwapsPayload.self, from: unknown), "an unknown kind is corrupt, not rest")

        // Backups: the one from before swaps restores with none, the new one with its swaps.
        let old = try await store.readBackup(try FixtureLoader.data("store/v1/backup-1.7.json"))
        try await store.restore(old.document, mode: .replaceAll)
        let afterOld = await store.load()
        XCTAssertEqual(afterOld.plans.count, 1)
        XCTAssertEqual(afterOld.swaps, [])
        let new = try await store.readBackup(try FixtureLoader.data("store/v1/backup-1.9.json"))
        try await store.restore(new.document, mode: .replaceAll)
        let afterNew = await store.load()
        XCTAssertEqual(afterNew.swaps.count, 2)
        XCTAssertEqual(afterNew.swaps.map(\.planId), [afterNew.plans[0].id, afterNew.plans[0].id])
        // A merge adds only the swaps it does not have, by id; the export carries them.
        try await store.save(swaps: Array(afterNew.swaps.prefix(1)))
        try await store.restore(new.document, mode: .merge)
        let merged = await store.load()
        XCTAssertEqual(merged.swaps.count, 2)
        let exportedData = await store.exportData(appVersion: "1.9")
        let exported = try XCTUnwrap(exportedData)
        XCTAssertEqual(try StoreCoder.decoder.decode(ExportDocument.self, from: exported).swaps?.count, 2)
        try await store.restore(old.document, mode: .merge)
        let mergedOld = await store.load()
        XCTAssertEqual(mergedOld.swaps.count, 2, "a backup with no swaps takes none away")

        // Deleting a plan deletes its swaps.
        var deleting = library
        deleting.deletePlan(try XCTUnwrap(deleting.activePlanId))
        XCTAssertEqual(deleting.swaps, [])
    }

    // TQ11: a weekday plan: Legs on Monday, a Push day; Friday's Legs becomes Push; no Slide.
    func testAWeekdayPlanSwapsToo() throws {
        var library = library(weekdayPlan())
        let plan = try XCTUnwrap(library.activePlan)
        try complete(&library, dayIndex: 2, on: 14)
        XCTAssertEqual(library.swaps.count, 2)
        XCTAssertEqual(swap(library, on: 14)?.original, .day(name: "Push"))
        XCTAssertEqual(swap(library, on: 14)?.replacement, .day(name: "Legs"))
        let friday = try XCTUnwrap(swap(library, on: 18))
        XCTAssertEqual(friday.original, .day(name: "Legs"))
        XCTAssertEqual(friday.replacement, .day(name: "Push"))
        XCTAssertEqual(friday.askedOn, start(14))
        let question = try XCTUnwrap(library.question(for: friday.id, now: day(14)))
        XCTAssertEqual(question.options.map(\.kind), [.rest, .todays, .keep], "nothing to slide on weekdays")
        XCTAssertEqual(week(library, from: 14).map { $0 },
                       [.completed(library.sessions), .rest, .projected(planId: plan.id, dayIndex: 1), .rest,
                        .projected(planId: plan.id, dayIndex: 0), .rest, .rest])
        XCTAssertEqual(StartCard.current(library: library, now: day(18), calendar: calendar),
                       .today(planId: plan.id, dayIndex: 0, dayName: "Push"))
        XCTAssertEqual(card(library, on: 18).buttonTitle, "Start Today's Push")
        XCTAssertEqual(strip(library, on: 14)[4].ring, .asking)
        // Slide is refused on a weekday plan even if asked for.
        library.answer(swap: friday.id, with: .slide)
        XCTAssertEqual(swap(library, on: 18)?.replacement, .day(name: "Push"))
        XCTAssertNil(swap(library, on: 18)?.slideUndo)
    }

    // TQ12 (pin): the projection's three functions, the strip and the missed rule take the
    // swaps with no default, so no caller can forget them.
    func testTheSwapsHaveNoDefault() throws {
        guard let projection = FixtureLoader.doc("JimmsBro/Core/CalendarProjection.swift"),
              let strip = FixtureLoader.doc("JimmsBro/Core/WeekStrip.swift"),
              let schedule = FixtureLoader.doc("JimmsBro/Core/PlanLibrary.swift") else {
            throw XCTSkip("the checkout is outside the simulator's sandbox; this pin runs on the host routes")
        }
        let signatures = [
            (projection, "static func entries(month:"), (projection, "static func next(days count:"),
            (projection, "static func week(containing date:"), (strip, "static func days(plan:"),
            (schedule, "static func missed(_ plan:"),
        ]
        for (source, name) in signatures {
            guard let range = source.range(of: name) else { return XCTFail("\(name) not found") }
            let declaration = source[range.lowerBound...].prefix(while: { $0 != "{" })
            XCTAssertTrue(declaration.contains("swaps: [DaySwap],"), "\(name) takes the swaps")
            XCTAssertFalse(declaration.contains("swaps: [DaySwap] ="), "\(name) has no default for them")
        }
    }

    // TQ13: a day whose name left the plan projects `.none`, and the past keeps D37's rule.
    func testARenamedDayLosesItsSwapAndThePastIsHistory() throws {
        var library = try legsOnMonday()
        let plan = try XCTUnwrap(library.activePlan)
        library.write(DaySwap(planId: plan.id, date: start(16), original: .day(name: "Legs"),
                              replacement: .day(name: "Ghost"), askedOn: start(14), answered: true))
        XCTAssertEqual(week(library, from: 14)[2], .none)
        XCTAssertNil(strip(library, on: 14)[2].dayName)
        XCTAssertNil(strip(library, on: 14)[2].colour)
        XCTAssertTrue(strip(library, on: 14)[2].hasDot)
        // Renaming the day the swap names loses it the way it loses its colour (§6.41).
        var renamed = try legsOnMonday()
        renamed.plans[0].days[0].name = "Upper"
        XCTAssertEqual(week(renamed, from: 14)[2], .none, "Wednesday's Push is a name the plan no longer has")
        XCTAssertNil(strip(renamed, on: 14)[2].dayName)
        let question = try XCTUnwrap(card(renamed, on: 14, showing: 2).question)
        XCTAssertEqual(question.chosen, .day(name: "Push"), "the swap keeps the name it was written with")
        XCTAssertEqual(question.options.first { $0.kind == .todays }?.title, "Upper",
                       "and today's day is the pattern's, by its name now")

        // The past: a swap on a day gone by is history — done or nothing, never planned.
        library.write(DaySwap(planId: plan.id, date: start(10), original: .rest,
                              replacement: .day(name: "Push"), askedOn: nil, answered: true))
        let month = CalendarProjection.entries(month: day(14), activePlan: plan, sessions: library.sessions,
                                               swaps: library.swaps, today: day(14), calendar: calendar)
        XCTAssertEqual(month[9].entry, .none)
        guard case .completed = month[13].entry else { return XCTFail("Monday is done") }
        // A swap only counts for its own plan.
        var other = rotation()
        other.name = "Other"
        library.write(DaySwap(planId: other.id, date: start(15), original: .day(name: "Pull"),
                              replacement: .rest, askedOn: nil, answered: true))
        XCTAssertEqual(week(library, from: 14)[1], .projected(planId: plan.id, dayIndex: 1))
    }

    // MARK: - Q2 (v1.9): Today shows it (D74, SPEC §6.48)

    // TQ14: the strip's marks after TQ1 — the dot and its words, the ring, and what a long
    // press does — then answered, then past; and a done date asks nothing.
    func testTheStripCarriesTheSwapsMarks() throws {
        let library = try legsOnMonday()
        let squares = strip(library, on: 14)
        XCTAssertTrue(squares[0].hasDot)
        XCTAssertEqual(squares[0].original, .green)
        XCTAssertEqual(squares[0].was, "was Push")
        XCTAssertEqual(squares[0].ring, .none)
        XCTAssertEqual(squares[0].hold, .was, "a long press on today's square shows what it was")
        XCTAssertEqual(squares[2].ring, .asking)
        XCTAssertEqual(squares[2].was, "was Legs")
        XCTAssertEqual(squares[2].hold, .question)
        for plain in [1, 3, 4, 5, 6] {
            XCTAssertFalse(squares[plain].hasDot, "square \(plain)")
            XCTAssertEqual(squares[plain].ring, .none, "square \(plain)")
            XCTAssertNil(squares[plain].was, "square \(plain)")
            XCTAssertEqual(squares[plain].hold, .tap, "square \(plain)")
        }

        var answered = library
        answered.answer(swap: try XCTUnwrap(squares[2].swapId), with: .day(name: "Push"))
        XCTAssertEqual(strip(answered, on: 14)[2].ring, .answered)
        XCTAssertEqual(strip(answered, on: 14)[2].hold, .question, "a long press reopens it")

        // Thursday: Monday and Wednesday are past, and nothing on the strip is marked.
        XCTAssertFalse(strip(library, on: 17).contains { $0.hasDot || $0.ring != .none || $0.was != nil })

        // Wednesday, its Push done with the question still open: the day is done and no answer
        // could change it, so the ring and the block go; the dot stays, which is still true.
        var done = library
        try complete(&done, dayIndex: 0, on: 16)
        let wednesday = strip(done, on: 16)[0]
        XCTAssertEqual(wednesday.ring, .none)
        XCTAssertTrue(wednesday.hasDot)
        XCTAssertEqual(wednesday.was, "was Legs")
        XCTAssertNil(card(done, on: 16).question)
        XCTAssertFalse(card(done, on: 16).showsQuestion)
    }

    // TQ15: the block's words and squares for a workout day and a rest day, and Slide's three
    // squares are the pattern Slide makes.
    func testTheQuestionBlockSaysItInWordsAndSquares() throws {
        let library = try legsOnMonday()
        let question = try XCTUnwrap(card(library, on: 14, showing: 2).question)
        XCTAssertEqual(question.heading, "Wednesday's Legs is done. Make Wednesday:")
        XCTAssertEqual(question.squares.map(\.title), ["Rest", "Push", "Legs"])
        XCTAssertEqual(question.squares.map(\.colour), [nil, .green, .purple])
        XCTAssertEqual(question.squares.map(\.isChosen), [false, true, false], "the default, applied at once")
        XCTAssertEqual(question.slideOption?.isChosen, false)
        let slide = try XCTUnwrap(question.slide)
        XCTAssertEqual(slide.colours, [.green, .orange, .purple], "Wednesday Push, Thursday Pull, Friday Legs")
        XCTAssertEqual(slide.spoken, "Slide: Push, Pull, Legs")
        XCTAssertEqual(library.activePlan?.cycleAnchor, start(7), "previewing a slide moves nothing")

        var slid = library
        slid.answer(swap: question.swapId, with: .slide)
        XCTAssertEqual(slide.colours, strip(slid, on: 14)[2...4].map(\.colour),
                       "the preview is the answer's own projection")
        // Reopened after the slide, the question offers what it first offered, Slide checked.
        let after = try XCTUnwrap(card(slid, on: 14, showing: 2, reopened: true).question)
        XCTAssertEqual(after.squares.map(\.title), ["Rest", "Push", "Legs"])
        XCTAssertEqual(after.squares.map(\.isChosen), [false, false, false])
        XCTAssertEqual(after.slideOption?.isChosen, true)
        XCTAssertEqual(after.slide, slide, "once slid, the preview is the pattern as it is")

        // A rest day: Legs on Thursday takes Sunday's, and today's day is rest, so rest is chosen.
        var rest = self.library(rotation())
        try complete(&rest, dayIndex: 2, on: 17)
        let sunday = try XCTUnwrap(card(rest, on: 17, showing: 3).question)
        XCTAssertEqual(sunday.heading, "Sunday's Legs is done. Make Sunday:")
        XCTAssertEqual(sunday.squares.map(\.title), ["Rest", "Legs"])
        XCTAssertEqual(sunday.squares.map(\.colour), [nil, .purple])
        XCTAssertEqual(sunday.squares.map(\.isChosen), [true, false])
        var slidRest = rest
        slidRest.answer(swap: sunday.swapId, with: .slide)
        XCTAssertEqual(sunday.slide?.colours, strip(slidRest, on: 17)[3...5].map(\.colour))

        // A weekday plan has no Slide, so no row.
        var weekdays = self.library(weekdayPlan())
        try complete(&weekdays, dayIndex: 2, on: 14)
        let friday = try XCTUnwrap(card(weekdays, on: 14, showing: 4).question)
        XCTAssertEqual(friday.heading, "Friday's Legs is done. Make Friday:")
        XCTAssertEqual(friday.squares.map(\.title), ["Rest", "Push", "Legs"])
        XCTAssertNil(friday.slide)
        XCTAssertNil(friday.slideOption)
    }

    // TQ16: the shown card's button follows each option; one tap closes the block and a long
    // press reopens it with nothing else changed; on the question's own day the block is on
    // today's card — and never on the card of an open session.
    func testTheShownCardFollowsTheChoice() throws {
        let asked = try legsOnMonday()
        let id = try XCTUnwrap(swap(asked, on: 16)).id
        let asking = card(asked, on: 14, showing: 2)
        XCTAssertTrue(asking.showsQuestion, "the block stands while the question asks")
        XCTAssertEqual(asking.title, "Push")
        XCTAssertEqual(asking.dayColour, .green)
        XCTAssertEqual(asking.buttonTitle, "Start Wednesday's Push")
        XCTAssertEqual(asking.buttonMark, .play)
        XCTAssertTrue(asking.buttonEnabled)
        XCTAssertFalse(card(asked, on: 14, showing: 1).showsQuestion, "Tuesday carries no question")
        XCTAssertFalse(card(asked, on: 14, showing: 1, reopened: true).showsQuestion)

        let answers: [(DaySwap.Slot, String, String, HomeStart.Mark)] = [
            (.rest, HomeStart.restTitle, "No exercise Wednesday", .moon),
            (.day(name: "Push"), "Push", "Start Wednesday's Push", .play),
            (.day(name: "Legs"), "Legs", "Start Wednesday's Legs", .play),
            (.slide, "Push", "Start Wednesday's Push", .play),
        ]
        for (slot, title, button, mark) in answers {
            var library = asked
            library.answer(swap: id, with: slot)
            let shown = card(library, on: 14, showing: 2)
            XCTAssertEqual(shown.title, title, "\(slot)")
            XCTAssertEqual(shown.buttonTitle, button, "\(slot)")
            XCTAssertEqual(shown.buttonMark, mark, "\(slot)")
            XCTAssertEqual(shown.buttonEnabled, mark == .play, "\(slot)")
            XCTAssertFalse(shown.showsQuestion, "one tap chooses and closes: \(slot)")
            let reopened = card(library, on: 14, showing: 2, reopened: true)
            XCTAssertTrue(reopened.showsQuestion, "a long press brings it back: \(slot)")
            XCTAssertEqual(reopened.question?.chosen, slot)
            XCTAssertEqual(reopened.buttonTitle, button, "reopening changes nothing but the block")
        }

        // On Wednesday itself the question is on today's card.
        let today = card(asked, on: 16)
        XCTAssertTrue(today.showsQuestion)
        XCTAssertEqual(today.buttonTitle, "Start Today's Push")

        // Never on the card of an open session (the owner's 11): the question waits on its square.
        var running = asked
        let plan = try XCTUnwrap(running.activePlan)
        let session = try XCTUnwrap(Session.start(plan: plan, dayIndex: 0, now: day(16)))
        running.engine = SessionEngine(active: ActiveSession(session: session, phase: .working(step: 0)),
                                       settings: running.settings)
        let open = card(running, on: 16)
        XCTAssertTrue(open.isInProgress)
        XCTAssertFalse(open.showsQuestion)
        XCTAssertEqual(strip(running, on: 16)[0].ring, .asking, "the ring still asks")
    }

    // TQ17: VoiceOver reads the question on the square, and the dot as the square's value.
    func testTheSquareSaysItsQuestion() throws {
        let library = try legsOnMonday()
        let squares = strip(library, on: 14)
        XCTAssertEqual(squares[2].spoken, "Wednesday, Push, question")
        XCTAssertEqual(squares[0].spoken, "Today, Legs")
        XCTAssertEqual(squares[0].was, "was Push")
        var answered = library
        answered.answer(swap: try XCTUnwrap(squares[2].swapId), with: .day(name: "Push"))
        XCTAssertEqual(strip(answered, on: 14)[2].spoken, "Wednesday, Push", "answered, it asks nothing")

        var rest = self.library(rotation())
        try complete(&rest, dayIndex: 2, on: 17)
        let thursday = strip(rest, on: 17)
        XCTAssertEqual(thursday[0].was, "was rest")
        XCTAssertEqual(thursday[3].spoken, "Sunday, rest, question")
        XCTAssertEqual(thursday[3].was, "was Legs")
    }

    // MARK: - Q4 (D76): change a day's exercises

    /// Upper Lower — Upper green, Lower orange — a second plan to borrow a day from.
    private func upperLower() -> Plan {
        func day(_ name: String, _ exercise: String) -> Day {
            Day(name: name, exercises: [Exercise(name: exercise, sets: [Self.set])])
        }
        return Plan(name: "Upper Lower", units: .kg, schedule: .rotation,
                    days: [day("Upper", "Overhead Press"), day("Lower", "Deadlift")],
                    importedAt: self.day(1), sourceText: "", cycle: [.day(0), .day(1), .rest])
    }

    /// The strip as Today draws it, with every plan a borrowed day can come from.
    private func strip(all library: PlanLibrary, on n: Int) -> [WeekStrip.Square] {
        WeekStrip.days(plan: library.activePlan, plans: library.plans, sessions: library.sessions,
                       swaps: library.swaps, today: day(n), calendar: calendar)
    }

    /// Every step of the open session logged, finished on the `n`th, through the library's own
    /// completion.
    private func finishOpen(_ library: inout PlanLibrary, on n: Int) throws {
        var session = try XCTUnwrap(library.engine?.session)
        for i in session.steps.indices {
            session.steps[i].status = .logged
            session.steps[i].result = .reps(count: 5, weight: 60)
            session.steps[i].startedAt = day(n)
            session.steps[i].loggedAt = day(n).addingTimeInterval(34)
        }
        session.endedAt = day(n).addingTimeInterval(60)
        library.engine = SessionEngine(active: ActiveSession(session: session, phase: .completed),
                                       settings: library.settings)
        library.completeSession()
    }

    // TQ25: the picker's sections — this plan first, then each other plan with days, and the
    // own-day row last — in the strip's words for when, with the date in full.
    func testThePickerListsThisPlanThenTheOthersThenADayOfItsOwn() throws {
        var library = library(rotation())
        let alone = try XCTUnwrap(library.dayChoices(for: day(16), now: day(14)))
        XCTAssertEqual(alone.title, "Change Wednesday's exercises")
        XCTAssertEqual(alone.line, "For Wednesday 16 September only. The plan does not change.")
        XCTAssertEqual(alone.sections.map(\.title), ["Push Pull Legs · this plan"], "no others section with one plan")
        let mine = alone.sections[0].rows
        XCTAssertEqual(mine.map(\.name), ["Push", "Pull", "Legs"])
        XCTAssertEqual(mine.map(\.colour), [.green, .orange, .purple])
        XCTAssertEqual(mine.map(\.outlined), [false, false, false])
        XCTAssertEqual(mine.map(\.slot), [.day(name: "Push"), .day(name: "Pull"), .day(name: "Legs")])
        XCTAssertEqual(mine.map(\.isChosen), [false, false, true], "Wednesday is Legs")
        XCTAssertEqual(alone.ownTitle, "Write a day just for Wednesday")
        XCTAssertEqual(alone.ownName, "Wednesday's own day")
        // D77 (v1.9): the sheet's point, which says what the JSON is and where it lands.
        XCTAssertEqual(alone.point.saveTitle, "Use for Wednesday")
        XCTAssertEqual(alone.point.title, "A day just for Wednesday")
        XCTAssertEqual(alone.point.place, "For Wednesday 16 September. Not saved to Push Pull Legs.")
        XCTAssertNil(alone.own)

        library.save(upperLower())
        library.plans.append(Plan(name: "Empty", units: .kg, schedule: .rotation, days: [],
                                  importedAt: day(1), sourceText: "", cycle: []))
        let other = try XCTUnwrap(library.plans.first { $0.name == "Upper Lower" })
        let both = try XCTUnwrap(library.dayChoices(for: day(16), now: day(14)))
        XCTAssertEqual(both.sections.map(\.title), ["Push Pull Legs · this plan", "Upper Lower"],
                       "a plan with no days has no section")
        let theirs = both.sections[1].rows
        XCTAssertEqual(theirs.map(\.name), ["Upper", "Lower"])
        XCTAssertEqual(theirs.map(\.colour), [.green, .orange], "each day in its own plan's colour")
        XCTAssertEqual(theirs.map(\.outlined), [true, true], "outlined: not from this plan")
        XCTAssertEqual(theirs[1].slot, .borrowed(planId: other.id, name: "Lower"))
        XCTAssertEqual(theirs.map(\.isChosen), [false, false])

        let today = try XCTUnwrap(library.dayChoices(for: day(14), now: day(14)))
        XCTAssertEqual(today.title, "Change Today's exercises")
        XCTAssertEqual(today.line, "For Monday 14 September only. The plan does not change.")
        XCTAssertEqual(today.ownTitle, "Write a day just for Today")
        XCTAssertEqual(today.ownName, "Monday's own day", "the name keeps the weekday, for History")
        XCTAssertEqual(today.point.saveTitle, "Use for Today")
        XCTAssertEqual(today.point.place, "For Monday 14 September. Not saved to Push Pull Legs.")
        XCTAssertEqual(try XCTUnwrap(library.dayChoices(for: day(15), now: day(14))).title,
                       "Change Tomorrow's exercises")
        XCTAssertNil(PlanLibrary().dayChoices(for: day(16), now: day(14)), "no plan, no picker")
    }

    // TQ26: choosing Pull writes `.day(Pull)` for the date, answered and asked by nobody; the
    // pattern's own day removes the swap; a date carrying a question is answered, not replaced.
    func testChoosingADayWritesTheDateAndThePatternsOwnDayRemovesIt() throws {
        var library = library(rotation())
        library.choose(.day(name: "Pull"), for: day(16), now: day(14))
        let written = try XCTUnwrap(swap(library, on: 16))
        XCTAssertEqual(written.date, start(16))
        XCTAssertEqual(written.original, .day(name: "Legs"))
        XCTAssertEqual(written.replacement, .day(name: "Pull"))
        XCTAssertNil(written.askedOn)
        XCTAssertTrue(written.answered)
        XCTAssertEqual(library.swaps.count, 1)
        let plan = try XCTUnwrap(library.activePlan)
        XCTAssertEqual(plan.cyclePosition, 0, "the plan does not change")
        XCTAssertEqual(plan.cycleAnchor, start(7))

        let squares = strip(library, on: 14)
        XCTAssertEqual(squares[2].dayName, "Pull")
        XCTAssertEqual(squares[2].colour, .orange)
        XCTAssertTrue(squares[2].hasDot)
        XCTAssertEqual(squares[2].original, .purple, "the dot is the pattern's Legs")
        XCTAssertEqual(squares[2].ring, .none, "a choice asks nothing")
        XCTAssertFalse(squares[2].outline, "a day of this plan is filled")
        let wednesday = card(library, on: 14, showing: 2)
        XCTAssertEqual(wednesday.title, "Pull")
        XCTAssertEqual(wednesday.buttonTitle, "Start Wednesday's Pull")
        XCTAssertEqual(wednesday.dayIndex, 1)
        XCTAssertFalse(wednesday.isOutlined)
        XCTAssertEqual(try XCTUnwrap(library.dayChoices(for: day(16), now: day(14))).sections[0].rows.map(\.isChosen),
                       [false, true, false])

        library.choose(.day(name: "Legs"), for: day(16), now: day(14))
        XCTAssertTrue(library.swaps.isEmpty, "the pattern's own day removes the swap")
        XCTAssertEqual(strip(library, on: 14)[2].colour, .purple)
        XCTAssertFalse(strip(library, on: 14)[2].hasDot)

        // After Legs on Monday, Wednesday carries a question: the picker answers it.
        var asked = try legsOnMonday()
        let question = try XCTUnwrap(swap(asked, on: 16))
        asked.choose(.day(name: "Pull"), for: day(16), now: day(14))
        let answered = try XCTUnwrap(swap(asked, on: 16))
        XCTAssertEqual(answered.id, question.id, "the question is kept")
        XCTAssertEqual(answered.replacement, .day(name: "Pull"))
        XCTAssertTrue(answered.answered)
        XCTAssertEqual(answered.askedOn, start(14))
        XCTAssertEqual(strip(asked, on: 14)[2].ring, .answered)
    }

    // TQ27: a day of another plan projects as that plan's day, outlined in that plan's colour;
    // its session is that plan's, and finishing it moves neither plan and writes nothing.
    func testABorrowedDayIsThatPlansDayOutlinedAndMovesNeitherPlan() throws {
        var library = library(rotation())
        library.save(upperLower())
        let other = try XCTUnwrap(library.plans.first { $0.name == "Upper Lower" })
        library.choose(.borrowed(planId: other.id, name: "Lower"), for: day(16), now: day(14))
        XCTAssertEqual(swap(library, on: 16)?.replacement, .borrowed(planId: other.id, name: "Lower"))

        let entries = CalendarProjection.next(days: 7, from: day(14), activePlan: library.activePlan,
                                              plans: library.plans, sessions: library.sessions,
                                              swaps: library.swaps, today: day(14), calendar: calendar)
        XCTAssertEqual(entries[2].entry, .projected(planId: other.id, dayIndex: 1))
        XCTAssertEqual(entries[2].entry.dayColour(plans: library.plans), .orange)
        XCTAssertEqual(CalendarText.label(entries[2].entry, plans: library.plans), "Lower")

        let squares = strip(all: library, on: 14)
        XCTAssertEqual(squares[2].dayName, "Lower")
        XCTAssertEqual(squares[2].colour, .orange, "Lower's colour in Upper Lower")
        XCTAssertTrue(squares[2].outline)
        XCTAssertEqual(squares[2].planId, other.id)
        XCTAssertEqual(squares[2].original, .purple)

        let wednesday = card(library, on: 14, showing: 2)
        XCTAssertEqual(wednesday.title, "Lower")
        XCTAssertEqual(wednesday.planId, other.id)
        XCTAssertEqual(wednesday.dayIndex, 1)
        XCTAssertEqual(wednesday.dayColour, .orange)
        XCTAssertTrue(wednesday.isOutlined)
        XCTAssertEqual(wednesday.rows.map(\.name), ["Deadlift"])
        XCTAssertEqual(wednesday.buttonTitle, "Start Wednesday's Lower")

        // Not done by Thursday: named by its own name, and Do it now starts it as its plan's.
        let missed = try XCTUnwrap(card(library, on: 17).missed)
        XCTAssertEqual(missed.dayName, "Lower")
        XCTAssertEqual(missed.date, start(16))
        XCTAssertEqual(missed.planId, other.id)
        XCTAssertEqual(missed.dayIndex, 1)

        let before = try XCTUnwrap(library.activePlan)
        try complete(&library, other, dayIndex: 1, on: 16)
        let session = try XCTUnwrap(library.sessions.last)
        XCTAssertEqual(session.planId, other.id, "its session is that plan's")
        XCTAssertEqual(library.activePlan?.cyclePosition, before.cyclePosition)
        XCTAssertEqual(library.activePlan?.cycleAnchor, before.cycleAnchor)
        let after = try XCTUnwrap(library.plans.first { $0.id == other.id })
        XCTAssertNil(after.cycleAnchor, "not even the other plan's first workout anchors it")
        XCTAssertNil(after.cyclePosition)
        XCTAssertEqual(library.swaps.count, 1, "no swap is written")
        XCTAssertEqual(DayColour.of(session: session, plans: library.plans), .orange, "History colours it by its plan")
        let done = strip(all: library, on: 16)[0]
        XCTAssertEqual(done.colour, .orange)
        XCTAssertTrue(done.outline, "still outlined once done")
        XCTAssertEqual(card(library, on: 16).buttonTitle, HomeStart.doneTitle)

        // Chosen for today, the card behind the first square is Upper, started as its plan's.
        var today = self.library(rotation())
        today.save(upperLower())
        let upper = try XCTUnwrap(today.plans.first { $0.name == "Upper Lower" })
        today.choose(.borrowed(planId: upper.id, name: "Upper"), for: day(14), now: day(14))
        XCTAssertEqual(StartCard.current(library: today, now: day(14), calendar: calendar),
                       .nextUp(planId: upper.id, dayIndex: 0, dayName: "Upper"))
        let first = card(today, on: 14)
        XCTAssertEqual(first.title, "Upper")
        XCTAssertEqual(first.planId, upper.id)
        XCTAssertEqual(first.dayColour, .green)
        XCTAssertTrue(first.isOutlined)
        XCTAssertEqual(first.buttonTitle, "Start Today's Upper")
    }

    // TQ28: a day written just for a date — read as a paste is, refused as the importer refuses,
    // held by the swap and never by the plan, outlined in ink, and started as the plan's session
    // under its own name, which gives it no colour.
    func testADayOfItsOwnIsReadLikeAPasteAndHeldByTheSwap() throws {
        let prose = try FixtureLoader.text("valid/fenced-with-prose.txt")
        let read = PlanLibrary.ownDay(prose, named: "Wednesday's own day", units: .kg,
                                      settings: Settings(), now: day(14))
        let own = try XCTUnwrap(read.day)
        XCTAssertTrue(read.issues.isEmpty, "a fixture day with prose around it is accepted")
        XCTAssertEqual(own.name, "A")
        XCTAssertEqual(own.exercises.map(\.name), ["Row"])
        XCTAssertNil(own.weekday)

        let nameless = PlanLibrary.ownDay(#"{"exercises": [{"name": "Plank", "sets": 3, "durationSeconds": 30}]}"#,
                                          named: "Wednesday's own day", units: .kg, settings: Settings(), now: day(14))
        let unnamed = try XCTUnwrap(nameless.day)
        XCTAssertEqual(unnamed.name, "Wednesday's own day", "a nameless day is named for its date")

        let emptyText = #"{"name": "Nothing", "exercises": []}"#
        let refused = PlanLibrary.ownDay(emptyText, named: "Wednesday's own day", units: .kg,
                                         settings: Settings(), now: day(14))
        XCTAssertNil(refused.day)
        let importer = PlanImport.run(#"{"name": "P", "days": [\#(emptyText)]}"#).issues.filter { $0.severity == .error }
        XCTAssertFalse(importer.isEmpty)
        XCTAssertEqual(refused.issues.map(\.code), importer.map(\.code), "the importer's refusal")
        XCTAssertEqual(refused.issues.map(\.message), importer.map(\.message), "in the importer's sentence")

        let two = PlanLibrary.ownDay(try FixtureLoader.text("valid/array-of-days.json"), named: "x",
                                     units: .kg, settings: Settings(), now: day(14))
        XCTAssertNil(two.day, "one day only")
        XCTAssertEqual(two.issues.map(\.severity), [.error])

        var library = library(rotation())
        let planId = try XCTUnwrap(library.activePlanId)
        library.choose(.own(own), for: day(16), now: day(14))
        XCTAssertEqual(swap(library, on: 16)?.replacement, .own(own), "the swap holds the day")
        XCTAssertEqual(library.activePlan?.days.map(\.name), ["Push", "Pull", "Legs"], "nothing joins the plan")
        XCTAssertEqual(try XCTUnwrap(library.dayChoices(for: day(16), now: day(14))).own, own)

        let square = strip(library, on: 14)[2]
        XCTAssertEqual(square.dayName, "A")
        XCTAssertNil(square.colour, "no plan's colour")
        XCTAssertTrue(square.outline, "outlined, in ink")
        XCTAssertEqual(square.own, own)
        let wednesday = card(library, on: 14, showing: 2)
        XCTAssertEqual(wednesday.title, "A")
        XCTAssertNil(wednesday.dayColour)
        XCTAssertTrue(wednesday.isOutlined)
        XCTAssertEqual(wednesday.ownDay, own)
        XCTAssertNil(wednesday.dayIndex)
        XCTAssertEqual(wednesday.rows.map(\.name), ["Row"])
        XCTAssertEqual(wednesday.buttonTitle, "Start Wednesday's A")

        // Not done by Thursday: Do it now has the day to start.
        let missed = try XCTUnwrap(card(library, on: 17).missed)
        XCTAssertEqual(missed.dayName, "A")
        XCTAssertEqual(missed.date, start(16))
        XCTAssertEqual(missed.own, own)

        // A nameless own day's button says when once.
        var named = library
        named.choose(.own(unnamed), for: day(16), now: day(14))
        XCTAssertEqual(card(named, on: 14, showing: 2).buttonTitle, "Start Wednesday's own day")

        // Chosen for today, it is today's card.
        var today = self.library(rotation())
        let todayPlan = try XCTUnwrap(today.activePlanId)
        today.choose(.own(own), for: day(14), now: day(14))
        XCTAssertEqual(StartCard.current(library: today, now: day(14), calendar: calendar),
                       .own(planId: todayPlan, day: own, daysAway: 0, weekday: .monday))
        let first = card(today, on: 14)
        XCTAssertEqual(first.title, "A")
        XCTAssertEqual(first.ownDay, own)
        XCTAssertTrue(first.isOutlined)
        XCTAssertEqual(first.buttonTitle, "Start Today's A")

        // Started and finished on Wednesday: the plan's session under the day's own name, with
        // no colour; the plan does not move and nothing is written.
        try library.startOwnDay(own, on: planId, now: day(16))
        let open = try XCTUnwrap(library.engine?.session)
        XCTAssertEqual(open.planId, planId)
        XCTAssertEqual(open.dayName, "A")
        XCTAssertEqual(open.exercises.map(\.name), ["Row"])
        try finishOpen(&library, on: 16)
        XCTAssertEqual(library.activePlan?.cyclePosition, 0)
        XCTAssertEqual(library.activePlan?.cycleAnchor, start(7))
        XCTAssertEqual(library.swaps.count, 1, "what the date said: nothing written")
        XCTAssertEqual(library.activePlan?.days.count, 3)
        XCTAssertNil(DayColour.of(session: try XCTUnwrap(library.sessions.last), plans: library.plans),
                     "a name no plan has: grey in History")
    }
}

private extension DaySwap.Slot {
    var dayName: String? {
        if case let .day(name) = self { return name }
        return nil
    }
}

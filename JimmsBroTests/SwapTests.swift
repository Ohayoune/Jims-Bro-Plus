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

    private func card(_ library: PlanLibrary, on n: Int, showing: Int = 0) -> HomeStart {
        HomeStart.current(library: library, now: day(n), calendar: calendar, showing: showing)
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
}

private extension DaySwap.Slot {
    var dayName: String? {
        if case let .day(name) = self { return name }
        return nil
    }
}

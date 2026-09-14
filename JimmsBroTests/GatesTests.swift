import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// T4 (v1.7) — controls are earned (D64): one test per row of SPEC §6.40's table, each at its
/// boundary, and the pin that holds the table and `Gates` together. T14–T21 (T16, the Goals
/// section's, went with goals in D68; T17, Another day's, with the chooser the week strip
/// replaced in v1.8, D70), and T27–T28 from the owner's review.
final class GatesTests: XCTestCase {
    private func day(_ n: Int) -> Date { CoreTestSupport.date(n) }

    /// A finished workout started on the nth of September 2026, at noon UTC.
    private func finished(on n: Int) -> Session { CoreTestSupport.completed(start: day(n)) }

    /// The same workout, still running.
    private func running(on n: Int) -> Session {
        var session = finished(on: n)
        session.endedAt = nil
        return session
    }

    /// UTC, with the week starting on `firstWeekday` (1 Sunday, 2 Monday).
    private func calendar(firstWeekday: Int) -> Calendar {
        var calendar = CoreTestSupport.utc()
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    // T14: Month, once a workout is older than the week the strip shows. September 2026: the
    // 7th and the 14th are Mondays, the 13th a Sunday.
    func testMonthOnceAWorkoutIsOlderThanThisWeek() {
        let monday = calendar(firstWeekday: 2)
        let sunday = calendar(firstWeekday: 1)
        XCTAssertFalse(Gates.month(sessions: [], today: day(14), calendar: monday), "no workouts, no Month")

        // Six days old on a Monday: last Tuesday, before this week began.
        let lastTuesday = finished(on: 8)
        XCTAssertTrue(Gates.month(sessions: [lastTuesday], today: day(14), calendar: monday))

        // Six days old on a Sunday: last Monday — this week's first day when weeks start on
        // Monday, so the strip already shows it; last week's when they start on Sunday.
        let lastMonday = finished(on: 7)
        XCTAssertFalse(Gates.month(sessions: [lastMonday], today: day(13), calendar: monday))
        XCTAssertTrue(Gates.month(sessions: [lastMonday], today: day(13), calendar: sunday))
        let strip = CalendarProjection.week(containing: day(13), activePlan: nil, sessions: [lastMonday],
                                            swaps: [],
                                            today: day(13), calendar: monday)
        XCTAssertTrue(strip.first.map { monday.isDate($0.date, inSameDayAs: day(7)) } ?? false,
                      "the gate's week is the strip's week")

        // Once earned it stays: the next day, and at the month's end.
        XCTAssertTrue(Gates.month(sessions: [lastMonday], today: day(14), calendar: monday))
        XCTAssertTrue(Gates.month(sessions: [lastMonday], today: day(30), calendar: monday))

        // A workout still running earns nothing.
        XCTAssertFalse(Gates.month(sessions: [running(on: 1)], today: day(14), calendar: monday))
    }

    // T15: Metrics, Find an exercise and Progression — History's block — from the first workout.
    func testMetricsAndFindFromTheFirstWorkout() {
        XCTAssertFalse(Gates.metricsAndFind(sessions: []))
        XCTAssertTrue(Gates.metricsAndFind(sessions: [finished(on: 8)]))
        XCTAssertFalse(Gates.metricsAndFind(sessions: [running(on: 8)]), "a running workout is not in History")
    }

    // T18: Change plan, once there is a plan.
    func testChangePlanOnceThereIsAPlan() {
        XCTAssertFalse(Gates.changePlan(plans: []))
        XCTAssertTrue(Gates.changePlan(plans: [CoreTestSupport.plan()]))
    }

    // T19: Plan a progression (D50) — every exercise on the day logged once, and no
    // progression attached.
    func testPlanAProgressionOnceEveryExerciseHasHistory() {
        let plan = CoreTestSupport.plan()
        XCTAssertFalse(Gates.planProgression(plan: plan, dayIndex: 0, sessions: []))

        // A session of another exercise is no history for this one.
        var other = plan
        other.days[0].exercises[0].name = "Squat"
        XCTAssertFalse(Gates.planProgression(plan: plan, dayIndex: 0,
                                             sessions: [CoreTestSupport.completed(plan: other)]))

        let logged = [CoreTestSupport.completed(plan: plan)]
        XCTAssertTrue(Gates.planProgression(plan: plan, dayIndex: 0, sessions: logged))

        // It leaves the moment a progression is attached — the one control that does.
        var progressed = plan
        progressed.progression = Progression(startDate: day(9), weeks: 4, entries: [])
        XCTAssertFalse(Gates.planProgression(plan: progressed, dayIndex: 0, sessions: logged))
        XCTAssertFalse(Gates.planProgression(plan: plan, dayIndex: 1, sessions: logged), "no such day")
    }

    // T20: the notifications-off line (D57) — once the first Log set has asked, and only if
    // the answer was no.
    func testNotificationsOffAfterTheFirstLogSet() {
        XCTAssertFalse(Gates.notificationsOff(askedAtLogSet: false, allowed: false), "not asked yet: nothing to say")
        XCTAssertFalse(Gates.notificationsOff(askedAtLogSet: false, allowed: true))
        XCTAssertTrue(Gates.notificationsOff(askedAtLogSet: true, allowed: false))
        XCTAssertFalse(Gates.notificationsOff(askedAtLogSet: true, allowed: true))
    }

    // T20, through the model: Start asks nothing, and the first Log set asks — a refusal is
    // what earns the line.
    @MainActor func testTheFirstLogSetEarnsTheNotificationsLine() async throws {
        let root = CoreTestSupport.makeRoot()
        defer { CoreTestSupport.discard(root) }
        let recorder = RecordingAlerts()
        recorder.authorized = false
        let model = AppModel(store: Store(root: root), scheduler: recorder, alerts: recorder,
                             sampleJSON: { nil })
        await model.load()
        await model.setWarmUp(0)
        let plan = CoreTestSupport.plan()
        await model.save(plan, makeActive: true)

        try await model.startDay(planId: plan.id, dayIndex: 0, now: day(9))
        XCTAssertFalse(model.showNotificationBanner, "Start does not ask (D57)")

        let step = try XCTUnwrap(model.currentStep)
        await model.apply(.logSet(step: step, result: .reps(count: 8, weight: 60)), now: day(9))
        XCTAssertTrue(model.showNotificationBanner, "the first Log set asked, and the answer was no")
    }

    // T21: SPEC §6.40's table and `Gates` name the same controls, one row per function, so a
    // control that is not there from the first launch needs SPEC's row before it can appear.
    func testEveryGateIsARowOfSpec() throws {
        guard let spec = FixtureLoader.doc("docs/SPEC.md"),
              let source = FixtureLoader.doc("JimmsBro/Core/Gates.swift") else {
            throw XCTSkip("the checkout is outside the simulator's sandbox; this pin runs on the host routes")
        }
        // Every function a view may ask: each `static func` that is not private.
        let functions = source.components(separatedBy: "\n").compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("static func ") else { return nil }
            return String(trimmed.dropFirst("static func ".count).prefix { $0.isLetter || $0.isNumber })
        }
        // Five since v1.8 (D70): Another day's gate went with the chooser the strip replaced.
        XCTAssertEqual(functions.count, 5, "one function per row of the plan's table")

        let lines = spec.components(separatedBy: "\n")
        let heading = try XCTUnwrap(lines.firstIndex { $0.hasPrefix("### 6.40 ") }, "SPEC has no §6.40")
        let section = lines[(heading + 1)...].prefix { !$0.hasPrefix("#") }
        let rows = section.filter { $0.hasPrefix("| ") && !$0.hasPrefix("| Control ") }
        let named = rows.compactMap { row -> String? in
            guard let start = row.range(of: "`Gates.") else { return nil }
            return String(row[start.upperBound...].prefix { $0.isLetter || $0.isNumber })
        }
        // D70 (v1.8): a row whose Core cell is "—" records a control the table leaves ungated
        // on purpose — the strip and its tap, live from the first plan — and it is the only one.
        let ungated = rows.filter { $0.hasSuffix("| — |") }
        XCTAssertEqual(ungated.count, 1, "§6.40 records one deliberately ungated control, the strip")
        XCTAssertTrue(ungated.first?.contains("strip") ?? false, "the ungated row is not the strip's")
        XCTAssertEqual(named.count + ungated.count, rows.count, "a row of §6.40 names no Gates function")
        XCTAssertEqual(named.sorted(), functions.sorted(), "§6.40's table and Gates disagree")
    }

    // MARK: - T7 (v1.7): the owner's review before the push (SPEC §6.42)

    // T27 (D66): one way to find an exercise — the row. The search field was a second way to
    // the same list, at the top of History, and it went.
    func testHistoryHasOneWayToFindAnExercise() throws {
        guard let source = FixtureLoader.doc("JimmsBro/Features/History/HistoryView.swift") else {
            throw XCTSkip("the checkout is outside the simulator's sandbox; this pin runs on the host routes")
        }
        XCTAssertFalse(source.contains(".searchable("), "History draws a search field again")
        XCTAssertTrue(source.contains("Label(\"Find an exercise\""), "History lost its Find an exercise row")
    }

    // T28 (D67): Progression is History's — the row beside Metrics and Find an exercise, and
    // the screen it opens — and Plan detail no longer has it. Today's Plan the next one opens
    // the screen itself, since the plan no longer leads there.
    func testProgressionIsHistorys() throws {
        guard let history = FixtureLoader.doc("JimmsBro/Features/History/HistoryView.swift"),
              let detail = FixtureLoader.doc("JimmsBro/Features/PlanDetail/PlanDetailView.swift"),
              let today = FixtureLoader.doc("JimmsBro/Features/Home/HomeView.swift") else {
            throw XCTSkip("the checkout is outside the simulator's sandbox; this pin runs on the host routes")
        }
        for literal in ["Text(\"Progression\")", "PromptText.progressionRow", "ProgressionView(planId:"] {
            XCTAssertTrue(history.contains(literal), "History no longer has \(literal)")
        }
        XCTAssertFalse(detail.contains("ProgressionView("), "Plan detail opens Progression again")
        XCTAssertFalse(detail.contains("Text(\"Progression\")"), "Plan detail has a Progression row again")

        let finished = try XCTUnwrap(today.range(of: "case .progressionFinished:"))
        let next = try XCTUnwrap(today.range(of: "case .notificationsOff:",
                                             range: finished.upperBound..<today.endIndex))
        let action = String(today[finished.upperBound..<next.lowerBound])
        XCTAssertTrue(action.contains("planningProgression ="), "Plan the next one no longer opens Progression")
        XCTAssertFalse(action.contains("previewing ="), "Plan the next one opens the plan again")
    }
}

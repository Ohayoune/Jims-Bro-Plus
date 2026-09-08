import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// V6 (v1.2) — Q55–Q60: the metrics of D39. "There should be metrics for the past — I don't
/// know exactly what metrics would be, but they should be included." v1.1 could open a past
/// workout and read its sets back, and that was all.
final class MetricsTests: XCTestCase {
    private let now = CoreTestSupport.now

    private func value(_ metrics: [Metric], _ label: String) -> String? {
        metrics.first { $0.label == label }?.value
    }
    private func note(_ metrics: [Metric], _ label: String) -> String? {
        metrics.first { $0.label == label }?.note
    }

    /// A 30-minute session: three sets of 10 at 60 kg, each set taking 34 s.
    private func session(start: Date? = nil) -> Session {
        var session = CoreTestSupport.completed([10, 10, 10], weights: [60, 60, 60],
                                                start: start ?? now.addingTimeInterval(-86_400))
        session.endedAt = session.startedAt.addingTimeInterval(1800)
        return session
    }

    // Q55: what a workout was — duration, how much of it was working, sets, volume, reps.
    func testASessionsMetricsAnswerTheObviousQuestions() {
        let metrics = SessionMetrics.of(session())
        XCTAssertEqual(value(metrics, "Duration"), "30 min")
        XCTAssertEqual(value(metrics, "Working"), "1 min")   // 3 × 34 s
        XCTAssertEqual(value(metrics, "Resting"), "28 min")
        XCTAssertEqual(value(metrics, "Sets"), "3 of 3")
        XCTAssertEqual(value(metrics, "Volume"), "1,800 kg")
        XCTAssertEqual(value(metrics, "Reps"), "30")
        XCTAssertEqual(value(metrics, "Heaviest set"), "60 kg × 10")
        XCTAssertEqual(value(metrics, "Average set"), "0:34")
        XCTAssertEqual(note(metrics, "Working"), "6% of the session")
    }

    // Q56: a skipped set is counted and said, not quietly dropped from the total.
    func testSkippedSetsAreSaid() {
        var session = self.session()
        session.steps[2].status = .skipped
        session.steps[2].result = nil
        let metrics = SessionMetrics.of(session)
        XCTAssertEqual(value(metrics, "Sets"), "2 of 3")
        XCTAssertEqual(note(metrics, "Sets"), "1 skipped")
        XCTAssertEqual(value(metrics, "Volume"), "1,200 kg")
    }

    // Q57: a bodyweight or timed workout has no volume, and says what it does have instead of
    // printing "0 kg", which reads like a failure.
    func testATimedWorkoutReportsTimeUnderTensionAndNoVolume() {
        let plan = CoreTestSupport.plan(sets: 3, work: .duration(seconds: 45), weight: nil,
                                        bodyweight: true)
        var session = CoreTestSupport.completed([1, 1, 1], plan: plan)
        for index in session.steps.indices {
            session.steps[index].result = .duration(seconds: 45, weight: nil)
        }
        session.endedAt = session.startedAt.addingTimeInterval(600)
        let metrics = SessionMetrics.of(session)
        XCTAssertNil(value(metrics, "Volume"))
        XCTAssertNil(value(metrics, "Reps"))
        XCTAssertEqual(value(metrics, "Time under tension"), "2 min")
    }

    // Q58: a record is a metric of its own, and names what set it.
    func testPersonalRecordsAreCounted() {
        let earlier = CoreTestSupport.completed([10, 10, 10], weights: [50, 50, 50],
                                                start: now.addingTimeInterval(-172_800))
        let heavier = session()
        let metrics = SessionMetrics.of(heavier, history: [earlier, heavier])
        XCTAssertEqual(value(metrics, "Personal records"), "1")
        XCTAssertEqual(note(metrics, "Personal records"), "Bench Press")
    }

    // Q59: over a window — how often, for how long, how much, and for how many weeks running.
    func testTrendMetricsOverAWindow() {
        let sessions = (1...4).map { session(start: now.addingTimeInterval(Double(-$0) * 86_400 * 3)) }
        let metrics = TrendMetrics.summary(sessions, days: 30, now: now)
        XCTAssertEqual(value(metrics, "Workouts"), "4")
        XCTAssertEqual(note(metrics, "Workouts"), "0.9 a week over 30 days")
        XCTAssertEqual(value(metrics, "Time trained"), "2 h")
        XCTAssertEqual(value(metrics, "Volume"), "7,200 kg")
        XCTAssertEqual(value(metrics, "Sets logged"), "12")
        XCTAssertEqual(value(metrics, "Most trained"), "Bench Press")
        XCTAssertEqual(value(metrics, "All time"), "4 workouts")
        // Nothing at all is nothing to report, rather than a screen of zeroes.
        XCTAssertTrue(TrendMetrics.summary([], now: now).isEmpty)
    }

    // Q60: the streak counts consecutive calendar weeks with at least one workout in them, and
    // stops at the first week without one.
    func testTheStreakCountsWeeksNotDays() {
        let calendar = CoreTestSupport.utc()
        func weeksAgo(_ n: Int) -> Session {
            session(start: calendar.date(byAdding: .weekOfYear, value: -n, to: now)!)
        }
        XCTAssertEqual(TrendMetrics.streakWeeks([weeksAgo(0), weeksAgo(1), weeksAgo(2)],
                                                now: now, calendar: calendar), 3)
        // A gap ends it: this week and three weeks ago is a streak of one.
        XCTAssertEqual(TrendMetrics.streakWeeks([weeksAgo(0), weeksAgo(3)],
                                                now: now, calendar: calendar), 1)
        // And a week with nothing in it, this one included, is a streak of none.
        XCTAssertEqual(TrendMetrics.streakWeeks([weeksAgo(1)], now: now, calendar: calendar), 0)
    }
}

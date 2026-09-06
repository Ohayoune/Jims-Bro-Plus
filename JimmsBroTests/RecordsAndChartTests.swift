import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// R5.3 (v1.1) — the personal-record marker and History's exercise search (D30): J26–J28.
/// The chart itself is a Swift Charts view over `ExerciseHistory.series`, which J-section tests
/// already cover; what is testable here is which sets count as records and what search finds.
final class RecordsAndChartTests: XCTestCase {
    private let now = CoreTestSupport.now

    /// One exercise, `reps` at `weights`, on a given day.
    private func session(_ reps: [Int], _ weights: [Double?], daysAgo: Int,
                         units: WeightUnit = .kg, bodyweight: Bool = false) -> Session {
        var plan = CoreTestSupport.plan(sets: reps.count, bodyweight: bodyweight)
        plan.units = units
        var s = CoreTestSupport.session(plan, start: now.addingTimeInterval(Double(-daysAgo) * 86_400))
        s.units = units
        for i in s.steps.indices {
            s.steps[i].status = .logged
            s.steps[i].result = .reps(count: reps[i], weight: bodyweight ? nil : weights[i])
            s.steps[i].loggedAt = s.startedAt.addingTimeInterval(Double(i) * 100)
        }
        s.endedAt = s.steps.last?.loggedAt
        return s
    }

    // J26: a record is a set that beats everything logged for that exercise before it.
    func testPersonalRecordsBeatEverythingEarlier() throws {
        let old = session([5, 5, 5], [100, 100, 100], daysAgo: 7)
        // Nothing to beat: the very first session sets no records, or every set would be one.
        XCTAssertTrue(SessionStats.personalRecords(session: old, history: []).isEmpty)

        let heavier = session([5, 3, 5], [100, 105, 100], daysAgo: 0)
        XCTAssertEqual(SessionStats.personalRecords(session: heavier, history: [old]), [1],
                       "only the heavier set")

        // Equalling the old best is not beating it.
        let equal = session([5, 5, 5], [100, 100, 100], daysAgo: 0)
        XCTAssertTrue(SessionStats.personalRecords(session: equal, history: [old]).isEmpty)

        // At the same weight, more reps wins.
        let moreReps = session([6, 5, 5], [100, 100, 100], daysAgo: 0)
        XCTAssertEqual(SessionStats.personalRecords(session: moreReps, history: [old]), [0])

        // Two records in one session: the running best moves as it goes.
        let twice = session([6, 3, 5], [100, 105, 100], daysAgo: 0)
        XCTAssertEqual(SessionStats.personalRecords(session: twice, history: [old]), [0, 1])

        // A lighter session sets nothing.
        let lighter = session([8, 8, 8], [90, 90, 90], daysAgo: 0)
        XCTAssertTrue(SessionStats.personalRecords(session: lighter, history: [old]).isEmpty)
    }

    // J27: units never convert (D10), and a set that was not logged cannot be a record.
    func testRecordsRespectUnitsAndStatus() throws {
        let heavyPounds = session([5, 5, 5], [200, 200, 200], daysAgo: 7, units: .lb)
        let kilos = session([5, 5, 5], [100, 100, 100], daysAgo: 0, units: .kg)
        // 200 lb is more than 100 kg as a number, and the app must not compare them at all.
        XCTAssertTrue(SessionStats.personalRecords(session: kilos, history: [heavyPounds]).isEmpty,
                      "a different unit is not history for this exercise")

        let old = session([5, 5, 5], [100, 100, 100], daysAgo: 7)
        var skipped = session([5, 5, 5], [105, 105, 105], daysAgo: 0)
        skipped.steps[0].status = .skipped
        skipped.steps[0].result = nil
        XCTAssertEqual(SessionStats.personalRecords(session: skipped, history: [old]), [1],
                       "the skipped set is not a record, and the next one still is")

        // Bodyweight compares reps; timed compares seconds held.
        let bodyOld = session([10, 10, 10], [nil, nil, nil], daysAgo: 7, bodyweight: true)
        let bodyNew = session([12, 10, 10], [nil, nil, nil], daysAgo: 0, bodyweight: true)
        XCTAssertEqual(SessionStats.personalRecords(session: bodyNew, history: [bodyOld]), [0])

        XCTAssertEqual(SessionStats.score(.reps(count: 5, weight: 100)), [100, 5])
        XCTAssertEqual(SessionStats.score(.duration(seconds: 45, weight: nil)), [0, 45])
        XCTAssertNil(SessionStats.score(nil))
    }

    // J28: History's search finds an exercise by name, most recent first.
    func testExerciseSearch() throws {
        func named(_ names: [String], daysAgo: Int) -> Session {
            var s = session([10], [60], daysAgo: daysAgo)
            s.exercises = names.map { SessionExercise(name: $0, targets: []) }
            return s
        }
        let sessions = [named(["Barbell Bench Press", "Incline Bench Press"], daysAgo: 5),
                        named(["Barbell Row", "Barbell Bench Press"], daysAgo: 1)]

        XCTAssertEqual(ExerciseText.search("bench", sessions: sessions),
                       ["Barbell Bench Press", "Incline Bench Press"])
        XCTAssertEqual(ExerciseText.search("BARBELL", sessions: sessions),
                       ["Barbell Row", "Barbell Bench Press", "Incline Bench Press"].filter {
                           $0.lowercased().contains("barbell")
                       },
                       "case-insensitive, most recently trained first")
        XCTAssertEqual(ExerciseText.search("row", sessions: sessions), ["Barbell Row"])
        XCTAssertTrue(ExerciseText.search("deadlift", sessions: sessions).isEmpty)
        // An empty query lists everything, de-duplicated by normalized name.
        XCTAssertEqual(ExerciseText.search("", sessions: sessions).count, 3)
        XCTAssertEqual(ExerciseText.search("  ", sessions: sessions).count, 3)
    }

    // J28: the chart's data source only plots what it has a weight for.
    func testChartSeriesSkipsWeightlessSessions() throws {
        let weighted = session([5, 5, 5], [100, 100, 100], daysAgo: 3)
        let body = session([10, 10, 10], [nil, nil, nil], daysAgo: 1, bodyweight: true)
        let series = ExerciseHistory(sessions: [weighted, body]).series(name: "Bench Press", units: .kg)
        XCTAssertEqual(series.count, 2, "both sessions are history")
        XCTAssertEqual(series.filter { $0.topWeight != nil }.count, 1,
                       "only one has a weight to plot, so a chart of one point is not drawn")
        XCTAssertEqual(series.first?.topWeight, 100)
        XCTAssertEqual(series.first?.topSetReps, 5)
    }
}

import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// M6 — O14 grouping, O15 editing a past session, O16's reachable exercise names, and the
/// best-set text of SPEC §6.7.
final class HistoryTests: XCTestCase {
    private func makeRoot() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JimmsBroM6Tests-\(UUID().uuidString)", isDirectory: true)
    }
    private func discard(_ root: URL) { try? FileManager.default.removeItem(at: root) }

    private func session(day: Int, month: Int = 9, reps: [Int] = [10, 10, 8],
                         weights: [Double?]? = nil) -> Session {
        let calendar = CoreTestSupport.utc()
        let start = calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
        return CoreTestSupport.completed(reps, weights: weights, start: start)
    }

    // O14: newest month first, newest session first inside it, and running sessions excluded.
    func testGroupingByMonthNewestFirst() throws {
        let calendar = CoreTestSupport.utc()
        let july = session(day: 2, month: 7)
        let earlySeptember = session(day: 1)
        let lateSeptember = session(day: 20)
        let alsoLate = session(day: 20)   // same day, later hour
        var later = alsoLate
        later.id = UUID()
        later.startedAt = alsoLate.startedAt.addingTimeInterval(3600)

        var running = session(day: 21)
        running.id = UUID()
        running.endedAt = nil

        let months = HistoryGrouping.months([earlySeptember, july, lateSeptember, later, running],
                                            calendar: calendar, locale: Locale(identifier: "en_US"))
        XCTAssertEqual(months.count, 2)
        XCTAssertEqual(months[0].title, "September 2026")
        XCTAssertEqual(months[1].title, "July 2026")
        XCTAssertEqual(months.map(\.id), months.map(\.id).sorted(by: >))

        // Newest first inside the month, and the unfinished session is not history.
        XCTAssertEqual(months[0].sessions.map(\.id), [later.id, lateSeptember.id, earlySeptember.id])
        XCTAssertFalse(months.flatMap(\.sessions).contains { $0.id == running.id })
        XCTAssertEqual(months[1].sessions.map(\.id), [july.id])

        XCTAssertEqual(HistoryGrouping.months([], calendar: calendar), [])
    }

    // Months are the local calendar's, so a session near a boundary lands in the right one.
    func testMonthBoundaryUsesTheLocalCalendar() throws {
        var utc = CoreTestSupport.utc()
        let firstOfOctoberUTC = utc.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 1))!
        let session = CoreTestSupport.completed(start: firstOfOctoberUTC)

        let inUTC = HistoryGrouping.months([session], calendar: utc, locale: Locale(identifier: "en_US"))
        XCTAssertEqual(inUTC.first?.title, "October 2026")

        utc.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let inPacific = HistoryGrouping.months([session], calendar: utc, locale: Locale(identifier: "en_US"))
        XCTAssertEqual(inPacific.first?.title, "September 2026",
                       "1 October 01:00 UTC is still September in Pacific time")
    }

    // O15: an edit is saved, volume updates, and the next session's prefill uses it.
    @MainActor func testEditingAPastSessionPersistsAndFeedsPrefill() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let model = AppModel(store: Store(root: root), sampleJSON: { nil })
        await model.load()
        let plan = try XCTUnwrap(model.runImport(CoreTestSupport.planJSON()).plan)
        await model.save(plan, makeActive: true)

        let past = session(day: 1, reps: [10, 10, 10], weights: [60, 60, 60])
        try await model.store.save(session: past)
        await model.load()
        XCTAssertEqual(model.sessions.count, 1)
        XCTAssertEqual(SessionStats.volume(try XCTUnwrap(model.sessions.first).steps), 1800)

        await model.editHistorySession(past.id, step: 0, result: .reps(count: 12, weight: 65))
        let edited = try XCTUnwrap(model.sessions.first)
        XCTAssertEqual(edited.steps[0].result, .reps(count: 12, weight: 65))
        XCTAssertEqual(SessionStats.volume(edited.steps), 12 * 65 + 600 + 600)

        // It is on disk, not just in memory.
        let reloaded = AppModel(store: Store(root: root), sampleJSON: { nil })
        await reloaded.load()
        XCTAssertEqual(reloaded.sessions.first?.steps[0].result, .reps(count: 12, weight: 65))

        // And the next workout prefills from the edited value.
        let planId = try XCTUnwrap(reloaded.activePlanId)
        try await reloaded.startDay(planId: planId, dayIndex: 0,
                                    now: past.startedAt.addingTimeInterval(86_400))
        let values = Prefill.values(session: try XCTUnwrap(reloaded.session), step: 0,
                                    history: reloaded.sessions)
        XCTAssertEqual(values.weight, 65)
        XCTAssertEqual(values.reps, 12)
    }

    // Deleting a past session removes its file and leaves the others alone.
    @MainActor func testDeletingAPastSession() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let model = AppModel(store: Store(root: root), sampleJSON: { nil })
        await model.load()
        let keep = session(day: 1)
        var drop = session(day: 3)
        drop.id = UUID()
        for session in [keep, drop] { try await model.store.save(session: session) }
        await model.load()
        XCTAssertEqual(model.sessions.count, 2)

        await model.deleteHistorySession(drop.id)
        XCTAssertEqual(model.sessions.map(\.id), [keep.id])
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("sessions/\(drop.id.uuidString).json").path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("sessions/\(keep.id.uuidString).json").path))

        let reloaded = AppModel(store: Store(root: root), sampleJSON: { nil })
        await reloaded.load()
        XCTAssertEqual(reloaded.sessions.map(\.id), [keep.id])

        // Deleting the same session again is not an error.
        await reloaded.deleteHistorySession(drop.id)
        XCTAssertEqual(reloaded.sessions.count, 1)
    }

    // SPEC §6.7's best set, including its fallbacks.
    func testBestSetText() throws {
        let weighted = CoreTestSupport.completed([10, 8, 5], weights: [60, 80, 100])
        XCTAssertEqual(ExerciseText.best(steps: weighted.steps, units: .kg), "Best: 100 kg × 5")

        // A tie on weight is broken by reps.
        let tied = CoreTestSupport.completed([5, 9, 3], weights: [100, 100, 60])
        XCTAssertEqual(ExerciseText.best(steps: tied.steps, units: .kg), "Best: 100 kg × 9")

        // No weighted sets: most reps, with no unit.
        let bodyweight = CoreTestSupport.completed([10, 15, 12], weights: [nil, nil, nil])
        XCTAssertEqual(ExerciseText.best(steps: bodyweight.steps, units: .kg), "Best: 15 reps")

        // Only timed sets: the longest hold.
        var plank = CoreTestSupport.session(CoreTestSupport.plan(sets: 3, work: .duration(seconds: 45),
                                                                weight: nil, bodyweight: true))
        for (index, seconds) in [40, 52, 45].enumerated() {
            plank.steps[index].status = .logged
            plank.steps[index].result = .duration(seconds: seconds, weight: nil)
        }
        XCTAssertEqual(ExerciseText.best(steps: plank.steps, units: .kg), "Best: 0:52")

        // Nothing logged at all.
        let empty = CoreTestSupport.session()
        XCTAssertNil(ExerciseText.best(steps: empty.steps, units: .kg))
    }

    // The row text the detail screens show, and the History row's one-line summary.
    func testResultAndSummaryText() throws {
        // Three sets, so there is a logged, a skipped and a pending row to render.
        var session = CoreTestSupport.completed([10, 10, 10], weights: [60, 60, 60])
        XCTAssertEqual(ExerciseText.result(session.steps[0]), "10 @ 60 · 0:34")

        session.steps[1].status = .skipped
        session.steps[1].result = nil
        XCTAssertEqual(ExerciseText.result(session.steps[1]), "skipped")
        session.steps[2].status = .pending
        session.steps[2].result = nil
        XCTAssertEqual(ExerciseText.result(session.steps[2]), "—")

        var timed = CoreTestSupport.session(CoreTestSupport.plan(sets: 1, work: .duration(seconds: 45),
                                                                weight: nil, bodyweight: true))
        timed.steps[0].status = .logged
        timed.steps[0].result = .duration(seconds: 52, weight: nil)
        XCTAssertEqual(ExerciseText.result(timed.steps[0]), "0:52")

        let summary = ExerciseText.summary(CoreTestSupport.completed([10, 10, 8], weights: [60, 60, 60]))
        XCTAssertTrue(summary.contains("3 sets"), summary)
        // v1.1 (R4): a volume total is grouped. The old expectation was the ungrouped "1680 kg".
        XCTAssertTrue(summary.contains("1,680 kg"), summary)
    }

    // O16: every exercise name a session shows is a history destination, de-duplicated.
    @MainActor func testExerciseHistoryReachableByName() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let model = AppModel(store: Store(root: root), sampleJSON: { nil })
        await model.load()

        let plan = CoreTestSupport.plan(sets: 2, secondExercise: true)
        var first = CoreTestSupport.completed([10, 10, 10, 10], weights: [60, 60, 60, 60], plan: plan,
                                              start: session(day: 1).startedAt)
        first.id = UUID()
        var second = CoreTestSupport.completed([12, 12, 12, 12], weights: [65, 65, 65, 65], plan: plan,
                                               start: session(day: 8).startedAt)
        second.id = UUID()
        for s in [first, second] { try await model.store.save(session: s) }
        await model.load()

        XCTAssertEqual(ExerciseText.exerciseNames(first), ["Bench Press", "Row"])

        // The series is oldest first, one point per session containing the exercise.
        let series = model.history(for: "Bench Press", units: .kg)
        XCTAssertEqual(series.count, 2)
        XCTAssertEqual(series.map(\.date), series.map(\.date).sorted())
        XCTAssertEqual(series.last?.topWeight, 65)
        XCTAssertEqual(series.last?.topSetReps, 12)

        // Name matching is normalized, and a different unit is a different history.
        XCTAssertEqual(model.history(for: "  bench   press ", units: .kg).count, 2)
        XCTAssertEqual(model.history(for: "Bench Press", units: .lb).count, 0)
        XCTAssertEqual(model.history(for: "Never Done", units: .kg).count, 0)
    }

    // The History tab's own grouping, straight off the model.
    @MainActor func testModelHistoryMonths() async throws {
        let root = makeRoot()
        defer { discard(root) }
        let model = AppModel(store: Store(root: root), sampleJSON: { nil })
        await model.load()
        XCTAssertEqual(model.historyMonths, [])

        var july = session(day: 2, month: 7)
        july.id = UUID()
        for s in [session(day: 1), july] { try await model.store.save(session: s) }
        await model.load()
        XCTAssertEqual(model.historyMonths.count, 2)
        XCTAssertEqual(model.historyMonths.flatMap(\.sessions).count, 2)
    }
}

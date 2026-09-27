import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// X4 (v1.3) — D45, W22–W29: history as a file another app can read, and a file from another
/// app read here. One row per logged set, in the column order Strong writes and Hevy reads.
final class HistoryCSVTests: XCTestCase {
    private let now = CoreTestSupport.now
    private let utc = CoreTestSupport.utc().timeZone

    /// Bench 10, 10, 8 @ 60 kg, then a second session a day later with one set skipped and a
    /// comma in its name, then a timed one.
    private func history() -> [Session] {
        let first = CoreTestSupport.completed([10, 10, 8], start: now.addingTimeInterval(-2 * 86_400))
        var second = CoreTestSupport.completed([12, 12, 12], start: now.addingTimeInterval(-86_400))
        second.id = UUID()
        second.dayName = "Push, heavy"
        second.steps[1].status = .skipped
        second.steps[1].result = nil
        var plank = CoreTestSupport.plan(sets: 2, work: .duration(seconds: 45), weight: nil, bodyweight: true)
        plank.days[0].exercises[0].name = "Plank"
        var third = CoreTestSupport.session(plank, start: now)
        for index in third.steps.indices {
            third.steps[index].status = .logged
            third.steps[index].result = .duration(seconds: 40 + index * 5, weight: nil)
            third.steps[index].loggedAt = now.addingTimeInterval(Double(index + 1) * 90)
        }
        third.endedAt = now.addingTimeInterval(180)
        return [first, second, third]
    }

    // W22: the file, line by line.
    func testRenderWritesOneRowPerLoggedSet() throws {
        let text = HistoryCSV.render(history(), timeZone: utc)
        let lines = text.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines[0], "Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE,Weight Unit")
        // 3 + 2 (one skipped) + 2 timed = 7 rows, oldest first.
        XCTAssertEqual(lines.count, 8)
        XCTAssertEqual(lines[1], "2023-11-12 22:13:20,Push,2m,Bench Press,1,60,10,,,,,,kg")
        XCTAssertEqual(lines[3], "2023-11-12 22:13:20,Push,2m,Bench Press,3,60,8,,,,,,kg")
        // The skipped set is not a row, so the set order runs 1, 2 — and the name is quoted.
        XCTAssertEqual(lines[4], "2023-11-13 22:13:20,\"Push, heavy\",2m,Bench Press,1,60,12,,,,,,kg")
        XCTAssertEqual(lines[5], "2023-11-13 22:13:20,\"Push, heavy\",2m,Bench Press,2,60,12,,,,,,kg")
        // Timed work: seconds, no reps, no weight.
        XCTAssertEqual(lines[6], "2023-11-14 22:13:20,Push,3m,Plank,1,,,,40,,,,kg")
        XCTAssertEqual(lines[7], "2023-11-14 22:13:20,Push,3m,Plank,2,,,,45,,,,kg")
        XCTAssertEqual(HistoryCSV.durationText(65 * 60 + 30), "1h 5m")
        XCTAssertEqual(HistoryCSV.field("a \"b\" c"), "\"a \"\"b\"\" c\"")
    }

    // W23: what the app writes, the app reads back.
    func testTheExportReadsBackAsTheSameHistory() throws {
        let original = history()
        let parsed = HistoryCSV.parse(HistoryCSV.render(original, timeZone: utc), defaultUnits: .lb, timeZone: utc)
        XCTAssertEqual(parsed.errors, [])
        XCTAssertNil(parsed.assumedUnits, "every row carried its unit")
        XCTAssertEqual(parsed.sessions.count, 3)
        for (back, mine) in zip(parsed.sessions, original) {
            XCTAssertEqual(back.dayName, mine.dayName)
            XCTAssertEqual(back.units, .kg)
            XCTAssertEqual(back.startedAt, mine.startedAt)
            XCTAssertNil(back.planId)
            let logged = mine.steps.filter { $0.status == .logged }
            XCTAssertEqual(back.steps.count, logged.count)
            XCTAssertEqual(back.steps.map(\.result), logged.map(\.result))
            XCTAssertEqual(back.steps.map(\.status), Array(repeating: .logged, count: logged.count))
            XCTAssertEqual(back.exercises.map(\.name), mine.exercises.map(\.name))
            let duration = back.endedAt!.timeIntervalSince(back.startedAt)
            XCTAssertEqual(duration, SessionStats.duration(mine), accuracy: 60, "minutes are what the file keeps")
        }
        XCTAssertTrue(parsed.sessions[2].exercises[0].bodyweight, "no weight on any set: bodyweight")
        XCTAssertFalse(parsed.sessions[0].exercises[0].bodyweight)
        // Read as ordinary history: "last time" and the best set come out of it.
        let last = try XCTUnwrap(ExerciseHistory.last(name: "bench press", units: .kg, sessions: parsed.sessions))
        XCTAssertEqual(last.dayName, "Push, heavy")
        XCTAssertEqual(SessionStats.best(ExerciseHistory.steps(name: "Bench Press", session: last)), .reps(count: 12, weight: 60))
    }

    // W24: a Strong export, both shapes it has had — with a unit column and semicolons, and
    // without either (the unit is then the setting, and said).
    func testAStrongExportReads() throws {
        let newer = """
        Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE
        2024-01-15 18:02:11,Pull,52m,Deadlift (Barbell),1,120,5,0,0,,,
        2024-01-15 18:02:11,Pull,52m,Deadlift (Barbell),2,120,5,0,0,,,8
        2024-01-15 18:02:11,Pull,52m,Pull Up,1,0,8,0,0,,,
        2024-01-17 07:30:00,Push,1h 5m,Bench Press (Barbell),1,80,6,0,0,"Pause, on chest",,
        """
        let parsed = HistoryCSV.parse(newer, defaultUnits: .lb, timeZone: utc)
        XCTAssertEqual(parsed.errors, [])
        XCTAssertEqual(parsed.assumedUnits, .lb, "no unit anywhere in the file: the setting, reported")
        XCTAssertEqual(parsed.sessions.map(\.dayName), ["Pull", "Push"])
        let pull = parsed.sessions[0]
        XCTAssertEqual(pull.units, .lb)
        XCTAssertEqual(pull.exercises.map(\.name), ["Deadlift (Barbell)", "Pull Up"])
        XCTAssertEqual(pull.steps.map(\.result), [.reps(count: 5, weight: 120), .reps(count: 5, weight: 120),
                                                 .reps(count: 8, weight: nil)])
        XCTAssertTrue(pull.exercises[1].bodyweight, "Strong writes 0 for a bodyweight set")
        XCTAssertEqual(pull.endedAt?.timeIntervalSince(pull.startedAt), 52 * 60)
        XCTAssertEqual(parsed.sessions[1].endedAt?.timeIntervalSince(parsed.sessions[1].startedAt), 65 * 60)
        XCTAssertEqual(HistoryCSV.parseDate("2024-01-15 18:02:11", timeZone: utc)?.timeIntervalSince1970, 1_705_341_731)

        let older = """
        Date;Workout Name;Exercise Name;Set Order;Weight;Weight Unit;Reps;RPE;Distance;Distance Unit;Seconds;Notes;Workout Notes;Workout Duration
        2023-05-02 07:15:00;Push;Bench Press (Barbell);1;60;kg;10;;0;;0;;;48m
        2023-05-02 07:15:00;Push;Bench Press (Barbell);2;60;kg;9;;0;;0;;;48m
        """
        let old = HistoryCSV.parse(older, defaultUnits: .lb, timeZone: utc)
        XCTAssertEqual(old.errors, [])
        XCTAssertNil(old.assumedUnits)
        XCTAssertEqual(old.sessions.count, 1)
        XCTAssertEqual(old.sessions[0].units, .kg)
        XCTAssertEqual(old.sessions[0].steps.map { $0.result?.reps }, [10, 9])
        XCTAssertEqual(old.sessions[0].endedAt?.timeIntervalSince(old.sessions[0].startedAt), 48 * 60)
    }

    // W25: a Hevy export — the unit in the header, the date in words, the end time, and
    // columns this app has no use for.
    func testAHevyExportReads() throws {
        let hevy = """
        title,start_time,end_time,description,exercise_title,superset_id,exercise_notes,set_index,set_type,weight_kg,reps,distance_km,duration_seconds,rpe
        "Push Day","12 Jan 2024, 07:30","12 Jan 2024, 08:25","","Bench Press (Barbell)",,"",0,warmup,40,10,,,
        "Push Day","12 Jan 2024, 07:30","12 Jan 2024, 08:25","","Bench Press (Barbell)",,"",1,normal,60,8,,,7
        "Push Day","12 Jan 2024, 07:30","12 Jan 2024, 08:25","","Plank",,"",0,normal,,,,45,
        "Legs","14 Jan 2024, 17:00","14 Jan 2024, 17:50","","Squat (Barbell)",,"",0,normal,100,5,,,
        """
        let parsed = HistoryCSV.parse(hevy, defaultUnits: .lb, timeZone: utc)
        XCTAssertEqual(parsed.errors, [])
        XCTAssertNil(parsed.assumedUnits, "weight_kg says the unit")
        XCTAssertEqual(parsed.sessions.map(\.dayName), ["Push Day", "Legs"])
        let push = parsed.sessions[0]
        XCTAssertEqual(push.units, .kg)
        XCTAssertEqual(push.startedAt, HistoryCSV.parseDate("2024-01-12 07:30", timeZone: utc))
        XCTAssertEqual(push.endedAt?.timeIntervalSince(push.startedAt), 55 * 60, "from the end time")
        XCTAssertEqual(push.exercises.map(\.name), ["Bench Press (Barbell)", "Plank"])
        XCTAssertEqual(push.steps.map(\.result), [.reps(count: 10, weight: 40), .reps(count: 8, weight: 60),
                                                 .duration(seconds: 45, weight: nil)])
        XCTAssertEqual(parsed.sessions[1].steps.first?.result, .reps(count: 5, weight: 100))
    }

    // W26: what cannot be read is said, per line, and the rest is read anyway.
    func testBadInputIsNamedAndTheRestIsRead() throws {
        let missing = HistoryCSV.parse("Foo,Bar\n1,2\n", defaultUnits: .kg, timeZone: utc)
        XCTAssertEqual(missing.errors.first?.code, "E_CSV_COLUMNS")
        XCTAssertEqual(HistoryCSV.parse("   \n", defaultUnits: .kg, timeZone: utc).errors.first?.code, "E_EMPTY")

        let mixed = """
        Date,Workout Name,Exercise Name,Set Order,Weight,Reps,Seconds
        yesterday,Push,Bench Press,1,60,10,
        2024-01-15 18:00:00,Push,Bench Press,1,60,10,
        2024-01-15 18:00:00,Push,,2,60,10,
        2024-01-15 18:00:00,Push,Bench Press,3,60,,
        2024-01-15 18:00:00,Push,Bench Press,4,60,8,
        """
        let parsed = HistoryCSV.parse(mixed, defaultUnits: .kg, timeZone: utc)
        XCTAssertEqual(parsed.errors, [])
        XCTAssertEqual(parsed.sessions.count, 1)
        XCTAssertEqual(parsed.sessions[0].steps.map { $0.result?.reps }, [10, 8])
        let skipped = parsed.issues.filter { $0.code == "W_CSV_ROW_SKIPPED" }
        XCTAssertEqual(skipped.map(\.path), ["line 2", "line 4", "line 5"])
        XCTAssertTrue(skipped[0].message.contains("yesterday"), skipped[0].message)

        let nothing = HistoryCSV.parse("Date,Exercise Name,Reps\nnope,Bench,10\n", defaultUnits: .kg, timeZone: utc)
        XCTAssertEqual(nothing.errors.first?.code, "E_CSV_NO_ROWS")
    }

    // W27: the same file twice adds nothing; a different workout at the same minute is new.
    func testImportingTheSameFileTwiceAddsNothing() throws {
        let original = history()
        let parsed = HistoryCSV.parse(HistoryCSV.render(original, timeZone: utc), defaultUnits: .kg, timeZone: utc)
        XCTAssertEqual(HistoryCSV.new(parsed.sessions, against: []).count, 3)
        XCTAssertEqual(HistoryCSV.new(parsed.sessions, against: original).count, 0)
        var other = parsed.sessions[0]
        other.dayName = "Pull"
        XCTAssertEqual(HistoryCSV.new([other], against: original).count, 1)
        var later = parsed.sessions[0]
        later.startedAt = later.startedAt.addingTimeInterval(59)
        XCTAssertEqual(HistoryCSV.new([later], against: original).count, 0, "the same minute is the same workout")

        let summary = HistoryCSV.Summary.of(parsed, existing: [original[0]])
        XCTAssertEqual(summary.workouts, 2)
        XCTAssertEqual(summary.sets, 4)
        XCTAssertEqual(summary.alreadyHere, 1)
    }

    // W28: what the dialog says before anything is written.
    func testTheSummarySentence() throws {
        let summary = HistoryCSV.Summary(workouts: 2, sets: 6, from: now.addingTimeInterval(-2 * 86_400), to: now,
                                         alreadyHere: 1, skippedLines: 0, assumedUnits: .kg)
        let text = summary.text(locale: Locale(identifier: "en_US_POSIX"), timeZone: utc)
        XCTAssertTrue(text.hasPrefix("2 workouts (6 sets) from "), text)
        XCTAssertTrue(text.hasSuffix(" · 1 already here · weights read as kg"), text)
        XCTAssertTrue(text.contains("Nov 12") && text.contains("Nov 14"), text)

        let one = HistoryCSV.Summary(workouts: 1, sets: 1, from: now, to: now, alreadyHere: 0, skippedLines: 2, assumedUnits: nil)
        let single = one.text(locale: Locale(identifier: "en_US_POSIX"), timeZone: utc)
        XCTAssertEqual(single, "1 workout (1 set) on Nov 14 · 2 lines skipped")
    }

    // W29: through the app — read, described, imported, on disk, and history to the workout.
    @MainActor func testTheAppReadsDescribesAndImports() async throws {
        let root = CoreTestSupport.makeRoot()
        defer { CoreTestSupport.discard(root) }
        let model = AppModel(store: Store(root: root), sampleJSON: { nil })
        await model.load()
        await model.setUnits(.lb)

        let text = HistoryCSV.render(history(), timeZone: utc)
        guard case let .read(pending) = model.read(csv: text) else { return XCTFail("should read") }
        XCTAssertEqual(pending.summary.workouts, 3)
        XCTAssertEqual(model.sessions.count, 0, "reading writes nothing")

        await model.importHistory(pending)
        XCTAssertEqual(model.sessions.count, 3)
        XCTAssertNil(model.saveFailure)
        let files = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("sessions").path)
        XCTAssertEqual(files.count, 3)

        // Again: nothing new, nothing added.
        guard case let .read(again) = model.read(csv: text) else { return XCTFail("should read") }
        XCTAssertEqual(again.summary.workouts, 0)
        XCTAssertEqual(again.summary.alreadyHere, 3)
        await model.importHistory(again)
        XCTAssertEqual(model.sessions.count, 3)

        // And the workout screen treats an imported session as last time.
        let session = CoreTestSupport.session(CoreTestSupport.plan(), start: now.addingTimeInterval(86_400))
        let values = Prefill.values(session: session, step: 0, history: model.sessions)
        XCTAssertEqual(values.weight, 60)
        XCTAssertEqual(values.reps, 12)

        guard case let .failed(message) = model.read(csv: "not,a,history\n1,2,3\n") else { return XCTFail("should fail") }
        XCTAssertTrue(message.contains("columns"), message)
        let exported = await model.exportHistoryCSV()
        XCTAssertNotNil(exported)
    }
}

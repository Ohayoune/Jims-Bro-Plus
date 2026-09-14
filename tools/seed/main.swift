import Foundation

// Seeds a simulator container with the sample plan and a few completed sessions,
// using the app's own Store so the files are exactly what the app writes.
let arguments = CommandLine.arguments
guard arguments.count >= 3 else { fatalError("usage: seed <container> <plan.json>") }
let root = URL(fileURLWithPath: arguments[1])
    .appendingPathComponent("Library/Application Support/JimmsBro", isDirectory: true)
let text = try String(contentsOf: URL(fileURLWithPath: arguments[2]), encoding: .utf8)

let store = Store(root: root)
let now = Date()
var result = PlanImport.run(text, settings: Settings(), now: now)
guard var plan = result.plan else { fatalError("sample plan failed to import: \(result.issues)") }

var library = PlanLibrary()
library.save(plan, makeActive: true)
plan = library.plans[0]

// Six finished workouts across two weeks, so the calendar, the activity line and the
// per-exercise chart (which needs at least two sessions of the same exercise) all have content.
// v1.7 (D63): `--no-history` seeds none, so History can be shot as a new phone sees it — the
// plan's week above "No workouts yet".
var sessions: [Session] = []
let history: [(Int, Int)] = arguments.contains("--no-history")
    ? [] : [(12, 0), (10, 1), (8, 2), (5, 0), (3, 1), (1, 2)]
/// A workout of `plan`'s `dayIndex`-th day begun at `start`, every set logged.
func finished(_ plan: Plan, _ dayIndex: Int, at start: Date, lighter: Bool) -> Session? {
    guard var session = Session.start(plan: plan, dayIndex: dayIndex, now: start) else { return nil }
    for index in session.steps.indices {
        session.steps[index].status = .logged
        let target = session.target(at: index)
        switch target?.work {
        case let .duration(seconds): session.steps[index].result = .duration(seconds: seconds, weight: nil)
        case .openDuration: session.steps[index].result = .duration(seconds: 40, weight: nil)
        default:
            // The older week is lighter, so the chart climbs and the newer week sets records.
            let base = target?.weight ?? 40
            session.steps[index].result = .reps(count: 10, weight: lighter ? max(0, base - 5) : base)
        }
        session.steps[index].startedAt = start.addingTimeInterval(Double(index) * 110)
        session.steps[index].loggedAt = start.addingTimeInterval(Double(index) * 110 + 38)
    }
    session.endedAt = session.steps.last?.loggedAt
    return session
}
for (offset, dayIndex) in history {
    let start = Calendar.current.date(byAdding: .day, value: -offset, to: now)!
    guard let session = finished(plan, dayIndex, at: start, lighter: offset > 6) else { continue }
    sessions.append(session)
    // v1.2: on the day it happened, so the seeded plan's cycle anchor (D37) is real and the
    // calendar the screenshots show is the one a phone with this history would show.
    PlanSchedule.advance(&plan, completedDayName: session.dayName, on: start)
}

// v1.9 (D72, D74): `--swap` finishes a workout today that the pattern did not expect — two
// days on from the one it did, as the plan's example finishes Legs on a Push day — through the
// library's own completion, so Today has a dotted square and, further along the strip, a
// ringed one carrying the question.
var swaps: [DaySwap] = []
if arguments.contains("--swap"), plan.days.count > 1 {
    var dayIndex = 2 % plan.days.count
    if case let .day(expected) = PlanSchedule.base(plan, on: now, today: now) {
        dayIndex = (expected + 2) % plan.days.count
        if dayIndex == expected { dayIndex = (expected + 1) % plan.days.count }
    }
    let start = max(Calendar.current.startOfDay(for: now), now.addingTimeInterval(-3600))
    if let session = finished(plan, dayIndex, at: start, lighter: false) {
        var swapping = PlanLibrary()
        swapping.save(plan, makeActive: true)
        swapping.sessions = sessions + [session]
        swapping.settle(session)
        plan = swapping.plans[0]
        sessions.append(session)
        swaps = swapping.swaps
    }
}

// v1.3 (D44): `seed <container> <plan.json> --progression` attaches a four-week progression
// to the seeded plan — 2.5 kg a week on every weighted exercise, a deload in week 3 — so the
// Progression screen, Plan detail's row and Home's subtitle have something to show.
if arguments.contains("--progression") {
    let entries = plan.days.flatMap { day in
        day.exercises.compactMap { exercise -> ProgressionEntry? in
            guard !exercise.bodyweight, let base = exercise.sets.first?.weight else { return nil }
            // Snapped as the import would snap them (D35): every weight the app shows is loadable.
            func loadable(_ weight: Double) -> Double { WeightRounding.snap(max(0, weight), increment: 2.5) }
            return ProgressionEntry(dayName: day.name, exerciseName: exercise.name, weeks: [
                ProgressionWeek(weight: loadable(base)),
                ProgressionWeek(weight: loadable(base + 2.5)),
                ProgressionWeek(weight: loadable(base - 5)),
                ProgressionWeek(weight: loadable(base + 5)),
            ])
        }
    }
    plan.progression = Progression(startDate: Calendar.current.startOfDay(for: now), weeks: 4, entries: entries)
    // v1.5 (D53): `--steps` makes it a progression of steps you earn, with the first exercise
    // already on its second step and the second one that has missed its first once, so the
    // ladder, the ▸ and "1 try" all have something to show.
    if arguments.contains("--steps") {
        plan.progression?.mode = .performance
        if plan.progression?.entries.indices.contains(0) == true { plan.progression?.entries[0].step = 1 }
        if plan.progression?.entries.indices.contains(1) == true { plan.progression?.entries[1].tries = 1 }
    }
}

try await store.save(settings: Settings())
try await store.save(plans: [plan], activePlanId: plan.id)
for session in sessions { try await store.save(session: session) }
if !swaps.isEmpty { try await store.save(swaps: swaps) }
print("seeded \(sessions.count) sessions into \(root.path)")

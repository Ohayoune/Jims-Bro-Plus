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
var sessions: [Session] = []
for (offset, dayIndex) in [(12, 0), (10, 1), (8, 2), (5, 0), (3, 1), (1, 2)] {
    let start = Calendar.current.date(byAdding: .day, value: -offset, to: now)!
    guard var session = Session.start(plan: plan, dayIndex: dayIndex, now: start) else { continue }
    for index in session.steps.indices {
        session.steps[index].status = .logged
        let target = session.target(at: index)
        switch target?.work {
        case let .duration(seconds): session.steps[index].result = .duration(seconds: seconds, weight: nil)
        case .openDuration: session.steps[index].result = .duration(seconds: 40, weight: nil)
        default:
            // The older week is lighter, so the chart climbs and the newer week sets records.
            let base = target?.weight ?? 40
            session.steps[index].result = .reps(count: 10, weight: offset > 6 ? max(0, base - 5) : base)
        }
        session.steps[index].startedAt = start.addingTimeInterval(Double(index) * 110)
        session.steps[index].loggedAt = start.addingTimeInterval(Double(index) * 110 + 38)
    }
    session.endedAt = session.steps.last?.loggedAt
    sessions.append(session)
    PlanSchedule.advance(&plan, completedDayName: session.dayName)
}

try await store.save(settings: Settings())
try await store.save(plans: [plan], activePlanId: plan.id)
for session in sessions { try await store.save(session: session) }
print("seeded \(sessions.count) sessions into \(root.path)")

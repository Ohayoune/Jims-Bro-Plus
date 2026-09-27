import Foundation
#if !CORE_CHECKS
import XCTest
#endif
#if !CORE_CHECKS
@testable import JimmsBro
#endif

enum CoreTestSupport {
    static let now = Date(timeIntervalSince1970: 1_700_000_000)
    static func plan(sets: Int = 3, secondExercise: Bool = false, work: WorkTarget = .reps(.range(min:8,max:12)), weight: Double? = 60, rest: Int = 90, bodyweight: Bool = false, drops: [DropTarget] = [], group: String? = nil) -> Plan {
        let target = SetTarget(work:work,weight:weight,restSeconds:rest,warningBeepSeconds:work.isTimed ? 5 : nil,drops:drops)
        var exercises = [Exercise(name:"Bench Press",group:group,repRange:work.isTimed ? nil : RepRange(min:8,max:12),bodyweight:bodyweight,sets:Array(repeating:target,count:sets))]
        if secondExercise { exercises.append(Exercise(name:"Row",group:group,repRange:RepRange(min:8,max:12),sets:Array(repeating:target,count:sets))) }
        return Plan(name:"Training",units:.kg,schedule:.rotation,days:[Day(name:"Push",exercises:exercises)],importedAt:now,sourceText:"",cycle:[.day(0)])
    }
    static func session(_ plan: Plan = plan(), start: Date = now) -> Session { Session.start(plan:plan,dayIndex:0,now:start)! }
    static func completed(_ reps: [Int] = [10,10,8], weights: [Double?]? = nil, plan: Plan? = nil, start: Date = now.addingTimeInterval(-86400)) -> Session {
        var s = session(plan ?? self.plan(sets:reps.count),start:start)
        for i in s.steps.indices {
            s.steps[i].status = .logged
            s.steps[i].result = .reps(count:reps[min(i,reps.count-1)],weight:weights?[safe:i] ?? 60)
            s.steps[i].startedAt = start.addingTimeInterval(Double(i*60))
            s.steps[i].loggedAt = start.addingTimeInterval(Double(i*60+34))
        }
        s.endedAt = s.steps.last?.loggedAt ?? start
        return s
    }
    /// v1.1's settings: no warm-up, and no countdown between exercises. Every test written
    /// before v1.2 asserts the flow these produce, and that flow is still exactly what the app
    /// does when both settings are Off — so they keep asserting it, explicitly, instead of
    /// being rewritten to expect the new defaults. `warmUpSeconds` and `transitionRestSeconds`
    /// have their own tests (WarmUpAndTransitionTests).
    static let classic = Settings(warmUpSeconds: 0, transitionRestSeconds: 0)
    /// v1.2's defaults, the warm-up on: 5 min of it, 2 min between exercises. D57 (v1.6) turned
    /// a fresh install's warm-up off, so the tests written against these say so.
    static let warmUp = Settings(warmUpSeconds: 300)
    static func engine(_ plan: Plan = plan(), settings: Settings = classic, history: [Session] = []) -> SessionEngine {
        SessionEngine(session:session(plan),settings:settings,history:history,now:now)
    }
    /// Three exercises of two sets each, 50 kg, 8–12, 60 s rest, so a block has somewhere to go.
    static func threeExercises(group: String? = nil) -> Plan {
        let target = SetTarget(work: .reps(.range(min: 8, max: 12)), weight: 50, restSeconds: 60)
        let exercises = ["Bench Press", "Row", "Squat"].map {
            Exercise(name: $0, group: group, repRange: RepRange(min: 8, max: 12), sets: [target, target])
        }
        return Plan(name: "Full", units: .kg, schedule: .rotation, days: [Day(name: "All", exercises: exercises)],
                    importedAt: now, sourceText: "", cycle: [.day(0)])
    }
    /// The exercise of every step, in the order the session will do them.
    static func stepNames(_ engine: SessionEngine) -> [String] {
        engine.session.steps.map { engine.session.exercises[$0.exerciseIndex].name }
    }
    /// A day `count` days from `now`; negative for days back.
    static func days(_ count: Int) -> Date { now.addingTimeInterval(Double(count) * 86_400) }
    /// One exercise logged with the given reps and weights, `daysAgo` days back: a set every
    /// 100 s, each taking 40 s.
    static func logged(_ reps: [Int], _ weights: [Double?], daysAgo: Int, units: WeightUnit = .kg, bodyweight: Bool = false) -> Session {
        var plan = plan(sets: reps.count, bodyweight: bodyweight)
        plan.units = units
        var s = session(plan, start: days(-daysAgo))
        s.units = units
        for i in s.steps.indices {
            s.steps[i].status = .logged
            s.steps[i].result = .reps(count: reps[i], weight: bodyweight ? nil : weights[i])
            s.steps[i].startedAt = s.startedAt.addingTimeInterval(Double(i) * 100)
            s.steps[i].loggedAt = s.startedAt.addingTimeInterval(Double(i) * 100 + 40)
        }
        s.endedAt = s.steps.last?.loggedAt
        return s
    }
    /// Push / Pull / Legs / rest / Push / Pull / Legs, one set of 5 at 60 kg each, imported on
    /// the 1st and anchored with Push done on the 7th.
    static func sevenDayRotation() -> Plan {
        let set = SetTarget(work: .reps(.fixed(5)), weight: 60, restSeconds: 90)
        func day(_ name: String, _ exercise: String) -> Day { Day(name: name, exercises: [Exercise(name: exercise, sets: [set])]) }
        var plan = Plan(name: "Push Pull Legs", units: .kg, schedule: .rotation,
                        days: [day("Push", "Bench Press"), day("Pull", "Row"), day("Legs", "Squat")],
                        importedAt: date(1), sourceText: "",
                        cycle: [.day(0), .day(1), .day(2), .rest, .day(0), .day(1), .day(2)])
        plan.cyclePosition = 0
        plan.cycleAnchor = utc().startOfDay(for: date(7))
        return plan
    }
    /// Push / Pull / Legs / rest with no exercises, imported on the `imported`th, at `position`
    /// since the `anchor`th.
    static func fourDayRotation(anchor: Int?, position: Int? = nil, imported: Int = 1) -> Plan {
        var plan = Plan(name: "PPL", units: .kg, schedule: .rotation,
                        days: [Day(name: "Push", exercises: []), Day(name: "Pull", exercises: []), Day(name: "Legs", exercises: [])],
                        importedAt: date(imported), sourceText: "", cycle: [.day(0), .day(1), .day(2), .rest])
        plan.cyclePosition = position
        plan.cycleAnchor = anchor.map { utc().startOfDay(for: date($0)) }
        return plan
    }
    /// A one-day plan as JSON, so tests exercise the real import (resolved rest, warning offsets).
    static func planJSON(exercise: String = #"{ "name": "Bench Press", "sets": 3, "reps": "8-12", "repRange": "8-12", "weight": 60, "restSeconds": 90 }"#) -> String {
        """
        { "schemaVersion": 1, "name": "Training", "units": "kg", "schedule": "rotation",
          "cycle": ["Push"], "days": [ { "name": "Push", "exercises": [ \(exercise) ] } ] }
        """
    }
    /// A paste through the real importer, with the default settings.
    static func importing(_ text: String) -> ImportResult { PlanImport.run(text, settings: Settings(), now: now) }
    static func importing(fixture path: String) throws -> ImportResult { importing(try FixtureLoader.text(path)) }
    /// The plan a paste makes, or a failure that names its issues.
    static func imported(_ text: String, file: StaticString = #filePath, line: UInt = #line) throws -> Plan {
        let result = importing(text)
        return try XCTUnwrap(result.plan, "\(result.issues)", file: file, line: line)
    }
    static func imported(fixture path: String, file: StaticString = #filePath, line: UInt = #line) throws -> Plan {
        let result = try importing(fixture: path)
        return try XCTUnwrap(result.plan, "\(path): \(result.issues)", file: file, line: line)
    }
    /// A fresh, empty store directory, and the way to get rid of it. Every store-backed test
    /// wants one; eight files had pasted their own copy.
    static func makeRoot(_ label: String = "Tests") -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JimmsBro\(label)-\(UUID().uuidString)", isDirectory: true)
    }
    static func discard(_ root: URL) { try? FileManager.default.removeItem(at: root) }
    static func utc() -> Calendar { var c = Calendar(identifier:.gregorian); c.timeZone = TimeZone(secondsFromGMT:0)!; return c }
    static func date(_ day: Int, hour: Int = 12) -> Date { utc().date(from:DateComponents(year:2026,month:9,day:day,hour:hour))! }
}

/// Records what would have been scheduled or played. Used by tests and by previews.
final class RecordingAlerts: NotificationScheduling, AlertPlaying, @unchecked Sendable {
    private let lock = NSLock()
    private var _scheduled: [NotificationRequest] = []
    private var _cancelled: [AlertIdentifier] = []
    private var _played: [TimerBeep] = []
    private var _feedback: [Feedback] = []
    var authorized = true

    var scheduled: [NotificationRequest] { lock.withLock { _scheduled } }
    var cancelled: [AlertIdentifier] { lock.withLock { _cancelled } }
    var played: [TimerBeep] { lock.withLock { _played } }
    var feedback: [Feedback] { lock.withLock { _feedback } }
    /// The requests that have not since been cancelled, in scheduling order.
    var pending: [NotificationRequest] {
        lock.withLock {
            var live: [AlertIdentifier: NotificationRequest] = [:]
            var order: [AlertIdentifier] = []
            for request in _scheduled {
                if live[request.id] == nil { order.append(request.id) }
                live[request.id] = request
            }
            for id in _cancelled where live[id] != nil { live[id] = nil }
            return order.compactMap { live[$0] }
        }
    }

    var asked = false
    func requestAuthorization() async -> Bool { asked = true; return authorized }
    func authorizationState() async -> NotificationState {
        guard asked else { return .notAsked }
        return authorized ? .allowed : .denied
    }
    func schedule(_ request: NotificationRequest) async {
        lock.withLock { _scheduled.append(request); _cancelled.removeAll { $0 == request.id } }
    }
    func cancel(ids: [AlertIdentifier]) async { lock.withLock { _cancelled.append(contentsOf: ids) } }
    func play(_ beep: TimerBeep, sound: Bool, vibration: Bool) {
        lock.withLock { if sound || vibration { _played.append(beep) } }
    }
    func play(feedback: Feedback, vibration: Bool) {
        lock.withLock { if vibration { _feedback.append(feedback) } }
    }
    func reset() { lock.withLock { _scheduled = []; _cancelled = []; _played = []; _feedback = [] } }
}

/// D40 (v1.2): records what the app asked the Lock Screen and the Dynamic Island to show, so
/// the behavior is testable without ActivityKit or a device.
final class RecordingActivities: ActivityPresenting, @unchecked Sendable {
    private let lock = NSLock()
    private var _shown: [WorkoutActivityState] = []
    private var _ends = 0

    /// Every state pushed, in order.
    var shown: [WorkoutActivityState] { lock.withLock { _shown } }
    /// The state currently on screen, if the activity has not been ended.
    var current: WorkoutActivityState? { lock.withLock { _shown.last } }
    var ends: Int { lock.withLock { _ends } }

    func show(_ state: WorkoutActivityState) async { lock.withLock { _shown.append(state) } }
    func end() async { lock.withLock { _ends += 1 } }
    func reset() { lock.withLock { _shown = []; _ends = 0 } }
}

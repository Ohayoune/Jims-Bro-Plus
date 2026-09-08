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
    static func engine(_ plan: Plan = plan(), settings: Settings = classic) -> SessionEngine {
        SessionEngine(session:session(plan),settings:settings,now:now)
    }
    /// A one-day plan as JSON, so tests exercise the real import (resolved rest, warning offsets).
    static func planJSON(exercise: String = #"{ "name": "Bench Press", "sets": 3, "reps": "8-12", "repRange": "8-12", "weight": 60, "restSeconds": 90 }"#) -> String {
        """
        { "schemaVersion": 1, "name": "Training", "units": "kg", "schedule": "rotation",
          "cycle": ["Push"], "days": [ { "name": "Push", "exercises": [ \(exercise) ] } ] }
        """
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

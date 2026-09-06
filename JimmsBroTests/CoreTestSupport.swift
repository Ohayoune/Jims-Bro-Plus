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
    static func engine(_ plan: Plan = plan()) -> SessionEngine { SessionEngine(session:session(plan),now:now) }
    /// A one-day plan as JSON, so tests exercise the real import (resolved rest, warning offsets).
    static func planJSON(exercise: String = #"{ "name": "Bench Press", "sets": 3, "reps": "8-12", "repRange": "8-12", "weight": 60, "restSeconds": 90 }"#) -> String {
        """
        { "schemaVersion": 1, "name": "Training", "units": "kg", "schedule": "rotation",
          "cycle": ["Push"], "days": [ { "name": "Push", "exercises": [ \(exercise) ] } ] }
        """
    }
    static func utc() -> Calendar { var c = Calendar(identifier:.gregorian); c.timeZone = TimeZone(secondsFromGMT:0)!; return c }
    static func date(_ day: Int, hour: Int = 12) -> Date { utc().date(from:DateComponents(year:2026,month:9,day:day,hour:hour))! }
}

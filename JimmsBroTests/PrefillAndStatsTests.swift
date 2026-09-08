import Foundation
#if !CORE_CHECKS
import XCTest
#endif
#if !CORE_CHECKS
@testable import JimmsBro
#endif

final class PrefillAndStatsTests: XCTestCase {
    let now = CoreTestSupport.now
    func testPrefillWithoutHistoryAndLastAchieved() {
        let current = CoreTestSupport.session()
        XCTAssertEqual(Prefill.values(session:current,step:0,history:[]).reps,8)
        XCTAssertEqual(Prefill.values(session:current,step:0,history:[]).weight,60)
        let last = CoreTestSupport.completed([14,10,8])
        let values = Prefill.values(session:current,step:0,history:[last])
        XCTAssertEqual(values.weight,60); XCTAssertEqual(values.reps,14)
        let fixed = CoreTestSupport.session(CoreTestSupport.plan(work:.reps(.fixed(10)),weight:nil))
        XCTAssertEqual(Prefill.values(session:fixed,step:0,history:[]).reps,10)
        XCTAssertNil(Prefill.values(session:fixed,step:0,history:[]).weight)
        let amrap = CoreTestSupport.session(CoreTestSupport.plan(work:.reps(.amrap(min:nil)),weight:nil))
        XCTAssertNil(Prefill.values(session:amrap,step:0,history:[]).reps)
    }
    func testCurrentWeightPrecedenceAndMissingHistoricalSet() {
        var current = CoreTestSupport.session(CoreTestSupport.plan(sets:4))
        let last = CoreTestSupport.completed([12,9],weights:[62.5,65])
        let missing = Prefill.values(session:current,step:3,history:[last])
        XCTAssertEqual(missing.weight,65); XCTAssertEqual(missing.reps,9)
        current.steps[0].status = .logged; current.steps[0].result = .reps(count:10,weight:70); current.steps[0].loggedAt = now
        let next = Prefill.values(session:current,step:1,history:[last])
        XCTAssertEqual(next.weight,70); XCTAssertEqual(next.reps,8); XCTAssertEqual(next.lastWeight,65)
    }
    func testMissingHistoricalWeightAndDropDoNotInventHistory() {
        let current = CoreTestSupport.session()
        var last = CoreTestSupport.completed([10,9,8],weights:[60,65,70])
        last.steps[1].result = .reps(count:9,weight:nil)
        let value = Prefill.values(session:current,step:1,history:[last])
        XCTAssertEqual(value.weight,70); XCTAssertEqual(value.lastWeight,70); XCTAssertEqual(value.reps,8)
        let p = CoreTestSupport.plan(sets:3,drops:[DropTarget(work:.reps(.fixed(6)),weight:15)])
        let shortPlan = CoreTestSupport.plan(sets:1,drops:[DropTarget(work:.reps(.fixed(6)),weight:15)])
        let short = CoreTestSupport.completed([10,8],weights:[60,10],plan:shortPlan)
        let longer = CoreTestSupport.session(p)
        let missingDrop = Prefill.values(session:longer,step:3,history:[short])
        XCTAssertEqual(missingDrop.weight,15); XCTAssertEqual(missingDrop.reps,6)
    }
    func testHistoryFilteringNormalizationAndRenames() {
        var current = CoreTestSupport.session()
        let oldest = CoreTestSupport.completed([9,9,9],start:now.addingTimeInterval(-3*86400))
        var lb = CoreTestSupport.completed([15,15,15],start:now.addingTimeInterval(-86400)); lb.units = .lb
        var skipped = CoreTestSupport.completed([20,20,20],start:now.addingTimeInterval(-100)); skipped.steps = skipped.steps.map { var s=$0; s.status = .skipped; s.result=nil; return s }
        var inProgress = CoreTestSupport.completed([30,30,30],start:now.addingTimeInterval(-50)); inProgress.endedAt = nil
        current.exercises[0].name = " bench   PRESS "
        XCTAssertEqual(Prefill.values(session:current,step:0,history:[lb,skipped,inProgress,oldest]).reps,9)
        current.exercises[0].name = "DB Bench"
        XCTAssertEqual(Prefill.values(session:current,step:0,history:[oldest]).reps,8)
        var renamed = oldest; renamed.exercises[0].name = "DB Bench"; renamed.steps[0].result = .reps(count:11,weight:60)
        XCTAssertEqual(Prefill.values(session:current,step:0,history:[renamed]).reps,11)
        XCTAssertEqual(Prefill.values(session:current,step:0,history:[]).reps,8)
    }
    /// I35: v1.1 revises D11 — a straight exercise still carries a suggestion chip, and its
    /// weight prefill is untouched by the dynamic-reps removal below.
    func testSuggestionChipFromLastSessionAdvice() {
        let current = CoreTestSupport.session()
        var last = CoreTestSupport.completed([10,10,8]); last.exercises[0].advice = .increase(to:62.5)
        let values = Prefill.values(session:current,step:0,history:[last])
        XCTAssertEqual(values.suggestedWeight,62.5); XCTAssertEqual(values.weight,60)
    }

    private func pyramidPlan() -> Plan {
        let targets = [50.0,60.0,70.0].map { SetTarget(work:.reps(.range(min:8,max:12)),weight:$0,restSeconds:90) }
        let exercise = Exercise(name:"Bench Press",repRange:RepRange(min:8,max:12),sets:targets)
        return Plan(name:"Training",units:.kg,schedule:.rotation,days:[Day(name:"Push",exercises:[exercise])],importedAt:now,sourceText:"",cycle:[.day(0)])
    }

    /// I35: 50 → 60 → 70 kg no longer prefills 50 for every later set once set 1 is logged.
    func testVariedTargetsDoNotCarryForwardWithinSession() {
        let plan = pyramidPlan()
        var session = CoreTestSupport.session(plan)
        XCTAssertTrue(session.exercises[0].hasVariedTargets)
        session.steps[0].status = .logged; session.steps[0].result = .reps(count:10,weight:50); session.steps[0].loggedAt = now
        XCTAssertEqual(Prefill.values(session:session,step:1,history:[]).weight,60)
        XCTAssertEqual(Prefill.values(session:session,step:2,history:[]).weight,70)
    }

    /// I36: a straight exercise (uniform target weight) is unaffected by the varied-target rule.
    func testStraightTargetsAreNotVaried() {
        XCTAssertFalse(CoreTestSupport.session(CoreTestSupport.plan(sets:4)).exercises[0].hasVariedTargets)
    }

    /// I37: with history present, a varied exercise reads last session's own set index rather
    /// than anything carried forward from earlier in the current session.
    func testVariedTargetsPrefillFromLastSessionSameIndex() {
        let plan = pyramidPlan()
        var last = CoreTestSupport.session(plan,start:now.addingTimeInterval(-86400))
        let lastWeights = [52.5,62.5,72.5]
        for i in last.steps.indices {
            last.steps[i].status = .logged
            last.steps[i].result = .reps(count:8,weight:lastWeights[i])
            last.steps[i].loggedAt = now.addingTimeInterval(-86400)
        }
        last.endedAt = now.addingTimeInterval(-86400)
        var current = CoreTestSupport.session(plan)
        current.steps[0].status = .logged; current.steps[0].result = .reps(count:10,weight:50); current.steps[0].loggedAt = now
        XCTAssertEqual(Prefill.values(session:current,step:1,history:[last]).weight,62.5)
        XCTAssertEqual(Prefill.values(session:current,step:2,history:[last]).weight,72.5)
    }
    func testLastTimeLinesAndMissingIndices() {
        let current = CoreTestSupport.session(CoreTestSupport.plan(sets:4))
        var last = CoreTestSupport.completed([10,10,8])
        var line = Prefill.lastTime(session:current,step:1,history:[last])!
        XCTAssertEqual(line.text,"10, 10, 8 @ 60 kg"); XCTAssertEqual(line.entries.map(\.isCurrent),[false,true,false])
        last.steps[2].result = .reps(count:8,weight:65)
        XCTAssertEqual(Prefill.lastTime(session:current,step:1,history:[last])?.text,"10@60, 10@60, 8@65 kg")
        for i in last.steps.indices { last.steps[i].result = .reps(count:[10,10,8][i],weight:nil) }
        XCTAssertEqual(Prefill.lastTime(session:current,step:1,history:[last])?.text,"10, 10, 8")
        last.steps[1].status = .skipped; last.steps[1].result=nil
        line = Prefill.lastTime(session:current,step:1,history:[last])!
        XCTAssertEqual(line.text,"10, –, 8"); XCTAssertTrue(line.entries[1].isCurrent)
        XCTAssertFalse(Prefill.lastTime(session:current,step:3,history:[last])!.entries.contains(where: \.isCurrent))
    }
    func testBodyweightAndDropPrefill() {
        let body = CoreTestSupport.plan(work:.reps(.amrap(min:nil)),weight:nil,bodyweight:true)
        let current = CoreTestSupport.session(body)
        var history = CoreTestSupport.completed([12,11,10],plan:body)
        history.steps = history.steps.map { var s=$0; s.result = .reps(count:12,weight:0); return s }
        let bw = Prefill.values(session:current,step:0,history:[history])
        XCTAssertEqual(bw.reps,12); XCTAssertFalse(bw.showsWeight); XCTAssertNil(bw.weight); XCTAssertNil(bw.lastWeight)
        let p = CoreTestSupport.plan(sets:2,drops:[DropTarget(work:.reps(.amrap(min:nil)),weight:nil)])
        var s = CoreTestSupport.session(p)
        s.steps[0].status = .logged; s.steps[0].result = .reps(count:10,weight:20)
        XCTAssertEqual(Prefill.values(session:s,step:1,history:[]).weight,20)
        XCTAssertNil(Prefill.values(session:s,step:1,history:[]).reps)
        let last = CoreTestSupport.completed([10,8,9,7],weights:[20,15,20,15],plan:p)
        let drop = Prefill.values(session:s,step:1,history:[last])
        XCTAssertEqual(drop.weight,15); XCTAssertEqual(drop.reps,8)
        let line = Prefill.lastTime(session:s,step:1,history:[last])!
        XCTAssertEqual(line.text,"10@20↓8@15, 9@20↓7@15 kg")
        XCTAssertEqual(line.entries.map(\.isCurrent),[false,true,false,false])
    }
    func testTimedPrefillAndLastTime() {
        let p = CoreTestSupport.plan(sets:2,work:.duration(seconds:45),weight:nil)
        let current = CoreTestSupport.session(p)
        XCTAssertEqual(Prefill.values(session:current,step:0,history:[]).seconds,45)
        var last = CoreTestSupport.completed([1,1],plan:p)
        last.steps[0].result = .duration(seconds:52,weight:nil); last.steps[1].result = .duration(seconds:48,weight:nil)
        XCTAssertEqual(Prefill.values(session:current,step:1,history:[last]).seconds,48)
        let open = CoreTestSupport.session(CoreTestSupport.plan(sets:2,work:.openDuration(minSeconds:nil),weight:nil))
        XCTAssertNil(Prefill.values(session:open,step:1,history:[last]).seconds)
        let line = Prefill.lastTime(session:open,step:1,history:[last])!
        XCTAssertEqual(line.text,"0:52, 0:48"); XCTAssertTrue(line.entries[1].isCurrent)
    }
    func testAdviceThresholdsAndEdgeCases() {
        let rows: [([Int],Advice?)] = [([12,12,12],.increase(to:62.5)),([12,12,11],.increase(to:62.5)),([12,11,11],nil),([8,8,8],nil),([8,8,7],.decrease(to:57.5)),([5,5,5],.decrease(to:57.5)),([12,12,5],nil),([12],.increase(to:62.5)),([7],.decrease(to:57.5))]
        for (reps,expected) in rows {
            let s = CoreTestSupport.completed(reps)
            XCTAssertEqual(ProgressionAdvice.evaluate(exercise:s.exercises[0],steps:s.steps,weightStep:2.5),expected,"\(reps)")
        }
        var s = CoreTestSupport.completed([12,12,12],weights:[60,60,65])
        XCTAssertNil(ProgressionAdvice.evaluate(exercise:s.exercises[0],steps:s.steps,weightStep:2.5))
        s = CoreTestSupport.completed([12,12,12]); s.steps[2].status = .skipped
        XCTAssertEqual(ProgressionAdvice.evaluate(exercise:s.exercises[0],steps:s.steps,weightStep:2.5),.increase(to:62.5))
        for i in s.steps.indices { s.steps[i].status = .skipped }
        XCTAssertNil(ProgressionAdvice.evaluate(exercise:s.exercises[0],steps:s.steps,weightStep:2.5))
        s = CoreTestSupport.completed([12,12,12]); s.exercises[0].repRange = nil
        XCTAssertNil(ProgressionAdvice.evaluate(exercise:s.exercises[0],steps:s.steps,weightStep:2.5))
        s = CoreTestSupport.completed([12,12,12]); s.steps[0].result = .duration(seconds:12,weight:60)
        XCTAssertNil(ProgressionAdvice.evaluate(exercise:s.exercises[0],steps:s.steps,weightStep:2.5))
        s = CoreTestSupport.completed([7],weights:[2])
        XCTAssertEqual(ProgressionAdvice.evaluate(exercise:s.exercises[0],steps:s.steps,weightStep:2.5),.decrease(to:0))
        s = CoreTestSupport.completed([12,12,12])
        XCTAssertEqual(ProgressionAdvice.evaluate(exercise:s.exercises[0],steps:s.steps,weightStep:5),.increase(to:65))
        s.exercises[0].bodyweight = true
        XCTAssertEqual(ProgressionAdvice.evaluate(exercise:s.exercises[0],steps:s.steps,weightStep:2.5),.increaseLoad)
        for i in s.steps.indices { s.steps[i].result = .reps(count:6,weight:nil) }
        XCTAssertEqual(ProgressionAdvice.evaluate(exercise:s.exercises[0],steps:s.steps,weightStep:2.5),.decreaseLoad)
        s = CoreTestSupport.completed([10,10,10]); s.exercises[0].repRange = RepRange(min:10,max:10)
        XCTAssertEqual(ProgressionAdvice.evaluate(exercise:s.exercises[0],steps:s.steps,weightStep:2.5),.increase(to:62.5))
        let p = CoreTestSupport.plan(sets:3,drops:[DropTarget(work:.reps(.amrap(min:nil)),weight:30),DropTarget(work:.reps(.amrap(min:nil)),weight:20)])
        s = CoreTestSupport.completed([12,8,6,12,8,6,12,8,6],weights:[60,30,20,60,30,20,60,30,20],plan:p)
        XCTAssertEqual(ProgressionAdvice.evaluate(exercise:s.exercises[0],steps:s.steps,weightStep:2.5),.increase(to:62.5))
    }
    func testAdviceMessagesAndEditingReevaluates() {
        XCTAssertEqual(ProgressionAdvice.message(.increase(to:62.5),range:RepRange(min:8,max:12),loggedSets:3,currentWeight:60,units:.kg),"All sets hit the top of 8–12. Try 62.5 kg next time.")
        XCTAssertEqual(ProgressionAdvice.message(.decrease(to:57.5),range:RepRange(min:8,max:12),loggedSets:3,currentWeight:60,units:.kg),"Below 8–12 across 3 sets. Try 57.5 kg next time, or keep 60 kg and build up.")
        let s = CoreTestSupport.completed([12,12,12])
        var e = SessionEngine(active:ActiveSession(session:s,phase:.completed))
        e.apply(.editSet(step:0,result:.reps(count:2,weight:60)),now:now)
        XCTAssertNil(e.session.exercises[0].advice)
        e.apply(.editSet(step:0,result:.reps(count:12,weight:60)),now:now)
        XCTAssertEqual(e.session.exercises[0].advice,.increase(to:62.5))
    }
    func testStatsVolumeBestDurationsAndSeries() {
        var s = CoreTestSupport.completed([10,10,8],weights:[60,60,65])
        XCTAssertEqual(SessionStats.volume(s.steps),1720)
        XCTAssertEqual(SessionStats.best(s.steps),.reps(count:8,weight:65))
        XCTAssertEqual(SessionStats.averageSetSeconds(s),34)
        s.steps[1].status = .skipped
        XCTAssertEqual(SessionStats.loggedCount(s),2); XCTAssertNil(s.steps[1].setSeconds)
        s.steps[0].startedAt=nil; XCTAssertNil(s.steps[0].setSeconds)
        s.steps[2].result = .duration(seconds:45,weight:65)
        XCTAssertEqual(SessionStats.volume(s.steps),600)
        s.steps[0].result = .reps(count:10,weight:nil)
        XCTAssertEqual(SessionStats.volume(s.steps),0)
        XCTAssertEqual(SessionStats.best(s.steps),.reps(count:10,weight:nil))
        s.steps[0].result = .duration(seconds:30,weight:nil)
        XCTAssertNil(SessionStats.best(s.steps))
        let high = CoreTestSupport.completed([5,3,8],weights:[100,100,95])
        XCTAssertEqual(SessionStats.best(high.steps),.reps(count:5,weight:100))
        // J9 (rewritten in v1.1's R4): the comparison is structured now, not one raw string.
        // The old expectation was "5@100, 3@100, 8@95 · last … · kg"; see J25.
        XCTAssertEqual(SessionStats.comparison(for:"Bench Press",session:high,history:[]),
                       ExerciseComparison(headline:"First time",rows:[]))
        var lb = high; lb.id=UUID(); lb.units = .lb
        let older = CoreTestSupport.completed([10,10,10],start:now.addingTimeInterval(-2*86400))
        let points = ExerciseHistory(sessions:[high,lb,older]).series(name:" bench press ",units:.kg)
        XCTAssertEqual(points.count,2); XCTAssertEqual(points[0].date,older.startedAt); XCTAssertEqual(points[1].topWeight,100); XCTAssertEqual(points[1].topSetReps,5)
        let volume = CoreTestSupport.completed([10,8,6],weights:[60,65,65])
        let point = ExerciseHistory(sessions:[volume]).series(name:"Bench Press",units:.kg)[0]
        XCTAssertEqual(point.volume,1510); XCTAssertEqual(point.topSetReps,8); XCTAssertEqual(point.setSeconds,[34,34,34])
        s.steps[1].result=nil
        let timed = ExerciseHistory(sessions:[s]).series(name:"Bench Press",units:.kg)[0]
        XCTAssertEqual(timed.topSeconds,45); XCTAssertNil(timed.topWeight); XCTAssertEqual(timed.volume,0); XCTAssertNil(timed.setSeconds[1])
    }
    func testBlockDurationsAndHistoryPerformance() {
        var s = CoreTestSupport.session(CoreTestSupport.plan(sets:1,secondExercise:true))
        XCTAssertNil(SessionStats.blockDuration(0,session:s))
        for i in s.steps.indices { s.steps[i].status = .logged; s.steps[i].result = .reps(count:10,weight:60) }
        s.steps[0].loggedAt = now.addingTimeInterval(580); s.steps[1].loggedAt = now.addingTimeInterval(1020); s.endedAt = s.steps[1].loggedAt
        XCTAssertEqual(SessionStats.blockDuration(0,session:s),580); XCTAssertEqual(SessionStats.blockDuration(1,session:s),440)
        XCTAssertEqual(SessionStats.duration(s),1020)
        s.steps[0].status = .skipped; XCTAssertNil(SessionStats.blockDuration(0,session:s))
        let sessions = (0..<1000).map { CoreTestSupport.completed(start:now.addingTimeInterval(-Double($0)*86400)) }
        let start = Date(); let points = ExerciseHistory(sessions:sessions).series(name:"Bench Press",units:.kg)
        XCTAssertEqual(points.count,1000)
        // A ceiling, not a measurement: it is here to catch an accidental O(n^2), so it is far
        // above anything a healthy machine takes and does not fail on a busy one or at -Onone.
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed,2.0,"1000 sessions of history took \(elapsed)s")
    }
}

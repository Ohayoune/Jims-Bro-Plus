import Foundation
#if !CORE_CHECKS
import XCTest
#endif
#if !CORE_CHECKS
@testable import JimmsBro
#endif

final class StepsAndEngineTests: XCTestCase {
    let now = CoreTestSupport.now
    func testManifestStepOrderAndRest() throws {
        for fixture in try FixtureLoader.manifest().fixtures where fixture.outcome == .valid {
            let p = try XCTUnwrap(PlanImport.run(try FixtureLoader.text(fixture.file)).plan)
            if case let .array(expected)? = fixture.checks?["stepsPerDay"] { XCTAssertEqual(p.days.map { JSONValue.number(Double(flatten(day:$0).count)) },expected,fixture.file) }
            if case let .object(expected)? = fixture.checks?["stepOrder"] {
                for (key,value) in expected {
                    let day = p.days[Int(key)!]
                    let order = flatten(day:day).map { JSONValue.string("\($0.exerciseIndex).\($0.setIndex)" + ($0.dropIndex == 0 ? "" : ".\($0.dropIndex)")) }
                    XCTAssertEqual(.array(order),value,fixture.file)
                }
            }
            if case let .object(expected)? = fixture.checks?["restAfterStep"] {
                for (key,value) in expected {
                    let parts = key.split(separator:":").map { Int($0)! }
                    let s = Session.start(plan:p,dayIndex:parts[0],now:now)!
                    let i = parts[1]
                    let next = i + 1 < s.steps.count ? i + 1 : nil
                    let result = RestResolution.after(i,next:next,steps:s.steps,exercises:s.exercises)
                    let actual: JSONValue
                    // The fixture's JSON label is "transition" (SPEC's v1 name for this case);
                    // the Swift case is `.blockDone` since v1.1 — see DECISIONS_LOG.
                    switch result { case .completed: actual = .number(0); case .blockDone: actual = .string("transition"); case let .rest(n): actual = .number(Double(n)) }
                    XCTAssertEqual(actual,value,"\(fixture.file): \(key)")
                }
            }
            for day in p.days {
                let steps = flatten(day:day)
                XCTAssertEqual(steps.count,day.exercises.flatMap(\.sets).reduce(0) { $0 + 1 + $1.drops.count })
                let blocks = Set(steps.map(\.blockIndex))
                XCTAssertEqual(steps.filter(\.isLastInBlock).count,blocks.count)
                for i in steps.indices where steps[i].dropIndex > 0 {
                    XCTAssertGreaterThan(i,0)
                    XCTAssertEqual(steps[i].exerciseIndex,steps[i-1].exerciseIndex)
                    XCTAssertEqual(steps[i].setIndex,steps[i-1].setIndex)
                    XCTAssertEqual(steps[i].dropIndex,steps[i-1].dropIndex+1)
                }
            }
        }
    }
    func testFlattenEmptySingleCircuitAndPerformance() {
        XCTAssertTrue(flatten(day:Day(name:"Empty",exercises:[])).isEmpty)
        let one = flatten(day:CoreTestSupport.plan(sets:1).days[0])
        XCTAssertEqual(one.count,1); XCTAssertTrue(one[0].isLastInBlock); XCTAssertTrue(one[0].isLastInRound)
        var p = CoreTestSupport.plan(sets:3,secondExercise:true,group:"A")
        p.days[0].exercises[1].sets.removeLast()
        XCTAssertEqual(flatten(day:p.days[0]).map(\.exerciseIndex),[0,1,0,1,0])
        XCTAssertEqual(flatten(day:p.days[0]).map(\.isLastInRound),[false,true,false,true,true])
        let big = Day(name:"Big",exercises:Array(repeating:CoreTestSupport.plan(sets:50).days[0].exercises[0],count:50))
        let start = Date()
        let steps = flatten(day:big)
        XCTAssertEqual(steps.count,2500)
        XCTAssertLessThan(Date().timeIntervalSince(start),0.01)
    }
    func testLoggingRestAdjustmentAndCompletion() {
        var e = CoreTestSupport.engine()
        XCTAssertEqual(e.phase,.working(step:0)); XCTAssertEqual(e.initialEffects,[.persist]); XCTAssertEqual(e.session.steps[0].startedAt,now)
        let log = e.apply(.logSet(step:0,result:.reps(count:10,weight:60)),now:now.addingTimeInterval(34.9))
        XCTAssertEqual(e.session.steps[0].setSeconds,34)
        let rest = RestState(startedAt:now.addingTimeInterval(34.9),endsAt:now.addingTimeInterval(124.9),nextStep:1)
        XCTAssertEqual(e.phase,.resting(rest))
        XCTAssertTrue(log.contains { if case let .scheduleNotification(id,at,body) = $0 { return id == "rest-timer" && at == rest.endsAt && body.contains("set 2 of 3") }; return false })
        let adjust = e.apply(.adjustRest(seconds:30),now:now.addingTimeInterval(40))
        XCTAssertEqual(adjust.first,.cancelNotification(id:"rest-timer")); XCTAssertEqual(adjust.last,.persist)
        e.apply(.adjustRest(seconds:-30),now:now.addingTimeInterval(40))
        XCTAssertEqual(e.phase,.resting(rest))
        let oldPhase = e.phase
        let edit = e.apply(.editSet(step:0,result:.reps(count:11,weight:62.5)),now:now.addingTimeInterval(50))
        XCTAssertEqual(e.phase,oldPhase); XCTAssertEqual(edit,[.persist]); XCTAssertEqual(e.session.steps[0].loggedAt,now.addingTimeInterval(34.9))
        let elapsed = e.apply(.restElapsed,now:rest.endsAt)
        XCTAssertTrue(elapsed.contains(.playAlert(.end))); XCTAssertTrue(elapsed.contains(.cancelNotification(id:"rest-timer")))
        XCTAssertEqual(e.phase,.working(step:1)); XCTAssertEqual(e.active.lastRestEndedAt,rest.endsAt)
        XCTAssertEqual(e.session.steps[1].startedAt,rest.endsAt)
        e.apply(.logSet(step:1,result:.reps(count:10,weight:60)),now:now.addingTimeInterval(150))
        e.apply(.skipRest,now:now.addingTimeInterval(160))
        let last = e.apply(.logSet(step:2,result:.reps(count:10,weight:60)),now:now.addingTimeInterval(200))
        XCTAssertEqual(e.phase,.completed); XCTAssertEqual(e.session.endedAt,now.addingTimeInterval(200)); XCTAssertTrue(last.contains(.sessionCompleted))
        XCTAssertFalse(last.contains { if case .scheduleNotification = $0 { return true }; return false })
        XCTAssertEqual(e.loggedCount,3); XCTAssertEqual(e.elapsed(now:now.addingTimeInterval(999)),200)
    }
    func testExpiredRestSkipAndInvalidEvents() {
        for action in [Event.restElapsed, .skipRest, .adjustRest(seconds:-30)] {
            var e = CoreTestSupport.engine()
            e.apply(.logSet(step:0,result:.reps(count:10,weight:60)),now:now)
            let t = actionTime(action)
            let effects = e.apply(action,now:now.addingTimeInterval(t))
            XCTAssertEqual(e.phase,.working(step:1)); XCTAssertFalse(effects.contains(.playAlert(.end)))
        }
        var e = CoreTestSupport.engine()
        let original = e.active
        for event in [Event.restElapsed,.dismissBlockDone,.startTimer(step:0),.stopTimer(step:0),.skipSet(step:-1),.jumpTo(step:999),.logSet(step:0,result:.reps(count:-1,weight:60)),.renameExercise(exerciseIndex:0,name:"  "),.undoLog(step:0)] {
            XCTAssertTrue(e.apply(event,now:now).isEmpty); XCTAssertEqual(e.active,original)
        }
        e.apply(.logSet(step:0,result:.reps(count:10,weight:60)),now:now)
        XCTAssertTrue(e.apply(.restElapsed,now:now.addingTimeInterval(89)).isEmpty)
        XCTAssertEqual(e.apply(.skipRest,now:now).last,.persist)
    }
    private func actionTime(_ event: Event) -> Double { if case .adjustRest = event { return 70 }; return 390 }
    func testSkipJumpWrapAndValueSemantics() {
        var e = CoreTestSupport.engine(CoreTestSupport.plan(secondExercise:true))
        let copy = e
        let skip = e.apply(.skipSet(step:0),now:now)
        XCTAssertEqual(e.phase,.working(step:1)); XCTAssertEqual(e.session.steps[0].status,.skipped); XCTAssertNil(e.session.steps[0].setSeconds)
        XCTAssertFalse(skip.contains { if case .scheduleNotification = $0 { return true }; return false })
        XCTAssertEqual(copy.session.steps[0].status,.pending)
        e.apply(.jumpTo(step:5),now:now.addingTimeInterval(10))
        // v1.1: a block-ending log advances straight into working(next) — no separate phase to
        // continue out of — with `blockDone` recording what the status strip shows (SPEC §6.3).
        e.apply(.logSet(step:5,result:.reps(count:10,weight:60)),now:now.addingTimeInterval(20))
        XCTAssertEqual(e.phase,.working(step:1))
        XCTAssertEqual(e.active.blockDone,BlockDone(finishedBlock:1,startedAt:now.addingTimeInterval(20)))
        XCTAssertEqual(e.session.steps[1].startedAt,now.addingTimeInterval(20))
        e.apply(.logSet(step:1,result:.reps(count:10,weight:60)),now:now.addingTimeInterval(40))
        let jump = e.apply(.jumpTo(step:0),now:now.addingTimeInterval(50))
        XCTAssertTrue(jump.contains(.cancelNotification(id:"rest-timer"))); XCTAssertEqual(e.active.lastRestEndedAt,now.addingTimeInterval(50))
        XCTAssertEqual(e.session.steps[0].startedAt,now.addingTimeInterval(50))
        e.apply(.logSet(step:0,result:.reps(count:12,weight:60)),now:now.addingTimeInterval(60))
        XCTAssertEqual(e.session.steps[0].setSeconds,10)
        e.apply(.skipExercise(exerciseIndex:0),now:now.addingTimeInterval(70))
        XCTAssertEqual(e.session.steps[1].status,.logged); XCTAssertEqual(e.session.steps[2].status,.skipped)
        XCTAssertNotNil(e.active.blockDone, "Expected finished block status")
    }
    /// v1.1: was testTransitionDropsZeroRestAndAdvice. A block-ending log no longer enters a
    /// separate `.transition` phase (D14); it advances straight to `working(next)` and records
    /// `BlockDone` for the status strip. `dismissBlockDone` (was `continueTransition`) only
    /// clears that flag — it does not re-enter the step, so `startedAt` stays put (SPEC §6.3).
    func testBlockDoneDropsZeroRestAndAdvice() throws {
        var e = CoreTestSupport.engine(CoreTestSupport.plan(sets:1,secondExercise:true))
        let effects = e.apply(.logSet(step:0,result:.reps(count:12,weight:60)),now:now.addingTimeInterval(34))
        XCTAssertEqual(e.phase,.working(step:1))
        XCTAssertEqual(e.active.blockDone,BlockDone(finishedBlock:0,startedAt:now.addingTimeInterval(34)))
        XCTAssertEqual(e.session.steps[1].startedAt,now.addingTimeInterval(34))
        XCTAssertEqual(e.adviceForBlockJustFinished,[.increase(to:62.5)])
        XCTAssertFalse(effects.contains { if case .scheduleNotification = $0 { return true }; return false })
        let restored = try JSONDecoder().decode(ActiveSession.self,from:JSONEncoder().encode(e.active))
        XCTAssertEqual(restored,e.active)
        e.apply(.dismissBlockDone,now:now.addingTimeInterval(334))
        XCTAssertNil(e.active.blockDone)
        XCTAssertEqual(e.session.steps[1].startedAt,now.addingTimeInterval(34))
        var drop = CoreTestSupport.engine(CoreTestSupport.plan(sets:2,drops:[DropTarget(work:.reps(.amrap(min:nil)),weight:40)]))
        drop.apply(.logSet(step:0,result:.reps(count:10,weight:60)),now:now)
        XCTAssertEqual(drop.phase,.working(step:1))
        drop.apply(.logSet(step:1,result:.reps(count:8,weight:40)),now:now)
        guard case .resting = drop.phase else { return XCTFail("Rest after the last drop") }
        var zero = CoreTestSupport.engine(CoreTestSupport.plan(rest:0))
        zero.apply(.logSet(step:0,result:.reps(count:10,weight:60)),now:now)
        XCTAssertEqual(zero.phase,.working(step:1))
    }
    func testFinishRenameAndRelog() {
        var e = CoreTestSupport.engine()
        e.apply(.renameExercise(exerciseIndex:0,name:"  DB Bench  "),now:now)
        XCTAssertEqual(e.session.exercises[0].name,"DB Bench")
        e.apply(.logSet(step:0,result:.reps(count:12,weight:60)),now:now)
        e.apply(.logSet(step:0,result:.reps(count:11,weight:60)),now:now.addingTimeInterval(1))
        XCTAssertEqual(e.session.steps[0].result,.reps(count:11,weight:60))
        let effects = e.apply(.finish,now:now.addingTimeInterval(60))
        XCTAssertEqual(e.session.steps.map(\.status),[.logged,.skipped,.skipped]); XCTAssertEqual(e.phase,.completed)
        XCTAssertTrue(effects.contains(.cancelNotification(id:"rest-timer"))); XCTAssertTrue(effects.contains(.sessionCompleted))
        var empty = CoreTestSupport.engine(); empty.apply(.finish,now:now)
        XCTAssertEqual(empty.loggedCount,0); XCTAssertEqual(empty.nextStep(after:0),nil)
    }
    func testFixedTimersWarningsEarlyCompletionAndCancellation() {
        var e = CoreTestSupport.engine(CoreTestSupport.plan(work:.duration(seconds:45)))
        XCTAssertNil(e.session.steps[0].startedAt)
        let effects = e.apply(.startTimer(step:0),now:now)
        XCTAssertEqual(e.session.steps[0].startedAt,now)
        XCTAssertTrue(effects.contains { if case let .scheduleNotification(id,date,_) = $0 { return id == "set-end" && date == now.addingTimeInterval(45) }; return false })
        XCTAssertTrue(effects.contains(.scheduleNotification(id:"set-warning",at:now.addingTimeInterval(40),body:"5 s left")))
        XCTAssertTrue(e.beepDue(now:now.addingTimeInterval(39)).isEmpty)
        XCTAssertEqual(e.beepDue(now:now.addingTimeInterval(40)),[.warning]); XCTAssertTrue(e.beepDue(now:now.addingTimeInterval(40)).isEmpty)
        XCTAssertEqual(e.beepDue(now:now.addingTimeInterval(45)),[.end])
        let end = e.apply(.timerElapsed(step:0),now:now.addingTimeInterval(45))
        XCTAssertEqual(e.session.steps[0].result,.duration(seconds:45,weight:60))
        for id in ["set-end","set-warning","set-minimum"] { XCTAssertTrue(end.contains(.cancelNotification(id:id))) }
        var early = CoreTestSupport.engine(CoreTestSupport.plan(work:.duration(seconds:45)))
        early.apply(.startTimer(step:0),now:now)
        early.apply(.timerDone(step:0),now:now.addingTimeInterval(30.9))
        XCTAssertEqual(early.session.steps[0].result?.seconds,30)
        var background = CoreTestSupport.engine(CoreTestSupport.plan(work:.duration(seconds:45)))
        background.apply(.startTimer(step:0),now:now)
        XCTAssertTrue(background.beepDue(now:now.addingTimeInterval(60),replayMissed:false).isEmpty)
        XCTAssertTrue(background.beepDue(now:now.addingTimeInterval(61)).isEmpty)
    }
    func testOpenTimersAndTimedGuards() {
        for minimum in [nil,30] as [Int?] {
            var e = CoreTestSupport.engine(CoreTestSupport.plan(work:.openDuration(minSeconds:minimum),weight:nil,bodyweight:true))
            let start = e.apply(.startTimer(step:0),now:now)
            XCTAssertEqual(start.filter { if case .scheduleNotification = $0 { return true }; return false }.count,minimum == nil ? 0 : 1)
            if minimum != nil { XCTAssertEqual(e.beepDue(now:now.addingTimeInterval(30)),[.minimum]) }
            e.apply(.stopTimer(step:0),now:now.addingTimeInterval(52.8))
            XCTAssertEqual(e.session.steps[0].result,.duration(seconds:52,weight:nil))
        }
        var e = CoreTestSupport.engine(CoreTestSupport.plan(work:.duration(seconds:45)))
        XCTAssertTrue(e.apply(.startTimer(step:1),now:now).isEmpty)
        e.apply(.startTimer(step:0),now:now)
        XCTAssertTrue(e.apply(.startTimer(step:0),now:now).isEmpty)
        XCTAssertTrue(e.apply(.timerElapsed(step:0),now:now.addingTimeInterval(44)).isEmpty)
        XCTAssertTrue(e.apply(.stopTimer(step:0),now:now.addingTimeInterval(10)).isEmpty)
        let jump = e.apply(.jumpTo(step:1),now:now)
        for id in ["set-end","set-warning","set-minimum"] { XCTAssertTrue(jump.contains(.cancelNotification(id:id))) }
        XCTAssertFalse(e.active.timerRunning)
    }
    func testTimedWeightPrefillEditsAndRestore() throws {
        let p = CoreTestSupport.plan(work:.duration(seconds:45),weight:60)
        let last = CoreTestSupport.completed([1,1,1],weights:[70,70,70],plan:p)
        var e = SessionEngine(session:CoreTestSupport.session(p),history:[last],now:now)
        XCTAssertEqual(e.active.workWeight,70)
        XCTAssertEqual(e.apply(.setWorkWeight(step:0,weight:72.5),now:now),[.persist])
        e.apply(.startTimer(step:0),now:now)
        let encoded = try JSONEncoder().encode(e.active)
        var restored = SessionEngine(active:try JSONDecoder().decode(ActiveSession.self,from:encoded))
        restored.apply(.timerDone(step:0),now:now.addingTimeInterval(30))
        XCTAssertEqual(restored.session.steps[0].result,.duration(seconds:30,weight:72.5))
        var empty = CoreTestSupport.engine(p)
        empty.apply(.setWorkWeight(step:0,weight:nil),now:now)
        empty.apply(.startTimer(step:0),now:now)
        empty.apply(.timerElapsed(step:0),now:now.addingTimeInterval(45))
        XCTAssertNil(empty.session.steps[0].result?.weight)
        var body = CoreTestSupport.engine(CoreTestSupport.plan(work:.duration(seconds:45),bodyweight:true))
        body.apply(.setWorkWeight(step:0,weight:100),now:now)
        XCTAssertNil(body.active.workWeight)
        XCTAssertTrue(body.apply(.setWorkWeight(step:0,weight:.infinity),now:now).isEmpty)
    }
    func testGroupRestFallbackCircuitAndSkipCompletion() throws {
        for (first,second,expected) in [(60,nil,60),(nil,45,45),(nil,nil,80)] as [(Int?,Int?,Int)] {
            let exercises: [[String:Any]] = [first,second].enumerated().map { i, rest in
                var ex: [String:Any] = ["name":"E\(i)","group":"A","sets":2,"reps":10]
                if let rest { ex["restSeconds"]=rest }; return ex
            }
            let raw: [String:Any] = ["days":[["name":"A","defaultRestSeconds":80,"exercises":exercises]]]
            let text = String(decoding:try JSONSerialization.data(withJSONObject:raw),as:UTF8.self)
            let p = try XCTUnwrap(PlanImport.run(text).plan)
            let s = CoreTestSupport.session(p)
            XCTAssertEqual(RestResolution.after(1,next:2,steps:s.steps,exercises:s.exercises),.rest(expected))
        }
        var p = CoreTestSupport.plan(sets:2,secondExercise:true,group:"A")
        p.days[0].exercises.append(p.days[0].exercises[0])
        XCTAssertEqual(flatten(day:p.days[0]).map(\.exerciseIndex),[0,1,2,0,1,2])
        var skip = CoreTestSupport.engine(CoreTestSupport.plan(sets:1,secondExercise:true))
        skip.apply(.skipSet(step:0),now:now)
        XCTAssertEqual(skip.session.steps[0].startedAt,now)
        XCTAssertEqual(skip.phase,.working(step:1))
        XCTAssertNotNil(skip.active.blockDone, "Skip last step of block ends the block")
        skip.apply(.jumpTo(step:1),now:now.addingTimeInterval(1))
        XCTAssertEqual(skip.phase,.working(step:1))
        let end = skip.apply(.skipSet(step:1),now:now.addingTimeInterval(2))
        XCTAssertEqual(skip.phase,.completed); XCTAssertTrue(end.contains(.sessionCompleted))
        var fixed = CoreTestSupport.plan(work:.duration(seconds:45))
        fixed.days[0].exercises[0].sets[0].warningBeepSeconds=nil
        var timer = CoreTestSupport.engine(fixed)
        let start = timer.apply(.startTimer(step:0),now:now)
        XCTAssertEqual(start.filter { if case .scheduleNotification = $0 { return true }; return false }.count,1)
        timer.apply(.timerDone(step:0),now:now.addingTimeInterval(20))
        XCTAssertTrue(timer.apply(.dismissBlockDone,now:now).isEmpty)
    }
    func testFullWorkoutAndSameBlockWrap() {
        var e = CoreTestSupport.engine(CoreTestSupport.plan(sets:18))
        for i in 0..<18 {
            let time = now.addingTimeInterval(Double(i*150))
            if case .resting = e.phase { e.apply(.restElapsed,now:time) }
            XCTAssertEqual(e.phase,.working(step:i))
            e.apply(.logSet(step:i,result:.reps(count:10,weight:60)),now:time.addingTimeInterval(34))
        }
        XCTAssertEqual(e.loggedCount,18); XCTAssertEqual(e.phase,.completed)
        var wrapped = CoreTestSupport.engine()
        wrapped.apply(.jumpTo(step:2),now:now)
        wrapped.apply(.logSet(step:2,result:.reps(count:10,weight:60)),now:now)
        guard case let .resting(rest) = wrapped.phase else { return XCTFail("Same block wrap should rest") }
        XCTAssertEqual(rest.nextStep,0)
    }
}

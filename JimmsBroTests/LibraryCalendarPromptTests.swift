import Foundation
#if !CORE_CHECKS
import XCTest
#endif
#if !CORE_CHECKS
@testable import JimmsBro
#endif

final class LibraryCalendarPromptTests: XCTestCase {
    let now = CoreTestSupport.now
    func rotation() -> Plan {
        var p = CoreTestSupport.plan()
        p.days += [Day(name:"Pull",exercises:p.days[0].exercises),Day(name:"Legs",exercises:p.days[0].exercises)]
        p.cycle = [.day(0),.day(1),.day(2),.day(0),.day(1),.day(2),.rest]
        return p
    }
    func testLibraryActivationConflictsReplaceAndDelete() {
        var library = PlanLibrary()
        let p = rotation()
        XCTAssertEqual(library.save(p),p.id); XCTAssertEqual(library.activePlanId,p.id)
        var other = p; other.id=UUID(); other.name="Other"
        library.save(other); XCTAssertEqual(library.activePlanId,p.id)
        var copy = p; copy.name=" training  "; copy.id=UUID()
        XCTAssertNotNil(library.conflict(for:copy)); XCTAssertNil(library.save(copy))
        let newID = library.save(copy,conflict:.keepBoth)
        XCTAssertNotNil(newID); XCTAssertEqual(library.plans.last?.name,"training (2)")
        library.plans[0].cyclePosition=1
        var replacement = p; replacement.days.swapAt(1,2); replacement.cycle=[.day(0),.day(1),.rest,.day(2)]
        library.save(replacement,conflict:.replace)
        XCTAssertEqual(library.plans[0].id,p.id); XCTAssertEqual(library.plans[0].cyclePosition,3)
        let past = CoreTestSupport.completed(); library.sessions=[past]
        library.deletePlan(p.id); XCTAssertEqual(library.sessions,[past]); XCTAssertNil(library.activePlanId)
        library.activePlanId=other.id
        library.deletePlan(other.id); XCTAssertEqual(library.activePlanId,newID)
    }
    /// D25 (v1.1): Plan detail's explicit Replace ignores name matching entirely and keeps id,
    /// cycle position and active status — unlike `save(conflict: .replace)`.
    func testExplicitReplacePreservesIdAndActiveStatus() {
        var library = PlanLibrary()
        let p = rotation()
        library.save(p)
        library.plans[0].cyclePosition = 1
        var incoming = p; incoming.id = UUID(); incoming.name = "Renamed Entirely"
        let result = library.replace(p.id, with: incoming)
        XCTAssertEqual(result, p.id)
        XCTAssertEqual(library.plans[0].id, p.id, "the id is preserved, not the incoming one")
        XCTAssertEqual(library.plans[0].name, "Renamed Entirely")
        XCTAssertEqual(library.activePlanId, p.id, "stayed active")
        XCTAssertEqual(library.plans[0].cyclePosition, 1, "same day names resolve the same position")

        var other = p; other.id = UUID(); other.name = "Other"
        library.save(other)
        XCTAssertNotEqual(library.activePlanId, other.id)
        var otherRevised = other; otherRevised.name = "Other v2"
        library.replace(other.id, with: otherRevised)
        XCTAssertNotEqual(library.activePlanId, other.id, "replacing an inactive plan leaves it inactive")

        XCTAssertNil(library.replace(UUID(), with: incoming), "a missing id is a no-op")
    }
    func testCycleNextAdvancementAndReplacement() {
        var p = rotation()
        XCTAssertEqual(PlanSchedule.next(p)?.dayIndex,0)
        for (position,next) in [(2,3),(5,0),(6,0)] {
            p.cyclePosition=position; XCTAssertEqual(PlanSchedule.next(p)?.cycleIndex,next)
        }
        for (position,name,expected) in [(nil,"Pull",1),(0,"Pull",1),(3,"Pull",4),(5,"Legs",2)] as [(Int?,String,Int)] {
            p.cyclePosition=position; PlanSchedule.advance(&p,completedDayName:name); XCTAssertEqual(p.cyclePosition,expected)
        }
        p.cyclePosition=1; PlanSchedule.advance(&p,completedDayName:"Unknown"); XCTAssertEqual(p.cyclePosition,1)
        var new = p; new.cycle=[.day(0),.day(2),.rest,.day(0),.day(1)]
        XCTAssertEqual(PlanSchedule.positionAfterReplacement(old:p,new:new),4)
        new.days.remove(at:1); new.cycle=[.day(0),.day(1)]
        XCTAssertNil(PlanSchedule.positionAfterReplacement(old:p,new:new))
        var simple = p; simple.cycle=[.day(0),.day(1),.day(2)]; simple.cyclePosition=2
        XCTAssertEqual(PlanSchedule.next(simple)?.dayIndex,0)
        simple.cyclePosition=nil; PlanSchedule.advance(&simple,completedDayName:"legs"); XCTAssertEqual(simple.cyclePosition,2)
        simple.cyclePosition=Int.max; XCTAssertEqual(PlanSchedule.next(simple)?.dayIndex,0)
    }
    func testStartSwitchCompletionDiscardAndHistoryEdits() throws {
        // v1.1's flow: no warm-up, so a started day is on its first step. The warm-up has its
        // own tests (WarmUpAndTransitionTests); this one is about switching and finishing days.
        var library = PlanLibrary(); library.settings = CoreTestSupport.classic
        let p = rotation(); library.save(p)
        try library.startDay(planId:p.id,dayIndex:0,now:now)
        XCTAssertThrowsError(try library.startDay(planId:p.id,dayIndex:1,now:now)) { XCTAssertEqual($0 as? LibraryError,.sessionInProgress) }
        library.apply(.logSet(step:0,result:.reps(count:12,weight:60)),now:now.addingTimeInterval(30))
        let switchEffects = try library.startDay(planId:p.id,dayIndex:1,now:now.addingTimeInterval(40),switching:.finish)
        XCTAssertTrue(switchEffects.contains(.cancelNotification(id:.rest)))
        XCTAssertEqual(library.sessions.count,1); XCTAssertEqual(library.plans[0].cyclePosition,0)
        XCTAssertEqual(library.engine?.phase,.working(step:0)); XCTAssertEqual(library.engine?.session.dayName,"Pull")
        try library.startDay(planId:p.id,dayIndex:2,now:now.addingTimeInterval(50),switching:.discard)
        XCTAssertEqual(library.sessions.count,1); XCTAssertEqual(library.plans[0].cyclePosition,0)
        library.apply(.finish,now:now.addingTimeInterval(60)); XCTAssertNil(library.engine)
        XCTAssertEqual(library.sessions.count,1) // No logged steps are discarded.
        try library.startDay(planId:p.id,dayIndex:2,now:now.addingTimeInterval(70))
        library.apply(.logSet(step:0,result:.reps(count:10,weight:60)),now:now.addingTimeInterval(80))
        library.apply(.finish,now:now.addingTimeInterval(90))
        XCTAssertEqual(library.sessions.count,2); XCTAssertEqual(library.plans[0].cyclePosition,2)
        let id = library.sessions[0].id
        library.editSession(id,step:0,result:.reps(count:5,weight:60),now:now)
        XCTAssertEqual(library.sessions[0].steps[0].result?.reps,5)
        XCTAssertEqual(library.sessions[0].exercises[0].advice,.decrease(to:57.5))
        library.deleteSession(id); XCTAssertEqual(library.sessions.count,1)
        try library.startDay(planId:p.id,dayIndex:0,now:now.addingTimeInterval(100))
        library.deletePlan(p.id)
        library.apply(.logSet(step:0,result:.reps(count:10,weight:60)),now:now.addingTimeInterval(110))
        library.apply(.finish,now:now.addingTimeInterval(120))
        XCTAssertEqual(library.sessions.count,2)
    }
    func testWeekdayLookupAndCalendarProjection() {
        let calendar = CoreTestSupport.utc()
        var p = rotation(); p.schedule = .weekday
        p.days[0].weekday = .monday; p.days[1].weekday = .wednesday; p.days[2].weekday = .friday
        XCTAssertEqual(PlanSchedule.weekday(p,today:CoreTestSupport.date(9),calendar:calendar)?.dayIndex,1)
        XCTAssertEqual(PlanSchedule.weekday(p,today:CoreTestSupport.date(8),calendar:calendar)?.daysAway,1)
        XCTAssertEqual(PlanSchedule.weekday(p,today:CoreTestSupport.date(12),calendar:calendar)?.daysAway,2)
        let month = CoreTestSupport.date(1), today = CoreTestSupport.date(8)
        let entries = CalendarProjection.entries(month:month,activePlan:p,sessions:[],today:today,calendar:calendar)
        XCTAssertEqual(entries.count,30)
        XCTAssertEqual(entries[8].entry,.projected(planId:p.id,dayIndex:1))
        XCTAssertEqual(entries[9].entry,.rest,"a weekday plan's unlisted weekdays are rest days")
        XCTAssertEqual(entries[10].entry,.projected(planId:p.id,dayIndex:2))
        // Past days the plan says nothing about stay blank rather than becoming rest days.
        XCTAssertEqual(entries[0].entry,.none)
        let completed = CoreTestSupport.completed(start:today)
        let another = CoreTestSupport.completed(start:today.addingTimeInterval(3600))
        let logged = CalendarProjection.entries(month:month,activePlan:p,sessions:[completed,another],today:today,calendar:calendar)
        if case let .completed(sessions) = logged[7].entry { XCTAssertEqual(sessions.count,2) } else { XCTFail("Completed day") }
        let far = CalendarProjection.entries(month:calendar.date(byAdding:.month,value:3,to:month)!,activePlan:p,sessions:[],today:today,calendar:calendar)
        XCTAssertTrue(far.allSatisfy { $0.entry == .none })
        var pacific = calendar; pacific.timeZone = TimeZone(identifier:"America/Los_Angeles")!
        let mondayUTC = calendar.date(from:DateComponents(year:2026,month:9,day:7,hour:1))!
        XCTAssertEqual(PlanSchedule.weekday(p,today:mondayUTC,calendar:calendar)?.daysAway,0)
        XCTAssertEqual(PlanSchedule.weekday(p,today:mondayUTC,calendar:pacific)?.daysAway,1)
    }
    func testRotationCalendarWithAndWithoutRest() {
        var p = rotation(); p.cyclePosition=2
        let calendar = CoreTestSupport.utc(), today = CoreTestSupport.date(8)
        let entries = CalendarProjection.entries(month:today,activePlan:p,sessions:[],today:today,calendar:calendar)
        XCTAssertEqual(entries[8].entry,.projected(planId:p.id,dayIndex:0))
        XCTAssertEqual(entries[9].entry,.projected(planId:p.id,dayIndex:1))
        XCTAssertEqual(entries[10].entry,.projected(planId:p.id,dayIndex:2))
        XCTAssertEqual(entries[11].entry,.rest,"the cycle's rest entry shows as a rest day")
        XCTAssertEqual(entries[12].entry,.projected(planId:p.id,dayIndex:0))
        XCTAssertEqual(entries[18].entry,.rest,"and again one cycle later")
        // Today and the past are never painted as rest days by a rotation cycle.
        XCTAssertEqual(entries[7].entry,.none)
        XCTAssertEqual(entries[0].entry,.none)
        // Beyond the 62-day horizon nothing is painted at all.
        let far = CalendarProjection.entries(month:calendar.date(byAdding:.month,value:3,to:today)!,
                                             activePlan:p,sessions:[],today:today,calendar:calendar)
        XCTAssertTrue(far.allSatisfy { $0.entry == .none },"no rest dots past the projection horizon")

        // D37 (v1.2): a rest-free cycle is painted for the whole horizon. v1.1 projected only
        // tomorrow and left the rest of the month blank, because without an anchor it was
        // guessing; with one it is a real repeating pattern, and a blank month was the thing
        // that made the calendar feel like it did not know what it was doing.
        p.cycle=[.day(0),.day(1),.day(2)]
        let noRest = CalendarProjection.entries(month:today,activePlan:p,sessions:[],today:today,calendar:calendar)
        XCTAssertEqual(noRest[8].entry,.projected(planId:p.id,dayIndex:0))
        XCTAssertEqual(noRest[9].entry,.projected(planId:p.id,dayIndex:1))
        XCTAssertEqual(noRest[10].entry,.projected(planId:p.id,dayIndex:2))
        XCTAssertEqual(noRest[11].entry,.projected(planId:p.id,dayIndex:0),"and round again")
        // Still no rest days: this cycle has none.
        XCTAssertTrue(noRest.allSatisfy { $0.entry != .rest })
        // And still nothing in the past or on today.
        XCTAssertEqual(noRest[7].entry,.none)

        // A cycle entry pointing at a deleted day is broken, not a rest day.
        var dangling = p; dangling.cycle=[.day(0),.day(9),.rest]; dangling.cyclePosition=0
        let broken = CalendarProjection.entries(month:today,activePlan:dangling,sessions:[],today:today,calendar:calendar)
        XCTAssertEqual(broken[8].entry,.none)
        XCTAssertEqual(broken[9].entry,.rest)
    }
    func testMissingCycleDaySupersetMetricsAndLocalCalendar() {
        var p=rotation(); p.cycle=[.day(0),.rest]; p.cyclePosition=0
        PlanSchedule.advance(&p,completedDayName:"Pull"); XCTAssertEqual(p.cyclePosition,0)
        var renamed=p; renamed.days[0].name="Other"; PlanSchedule.advance(&renamed,completedDayName:"Push")
        XCTAssertEqual(renamed.cyclePosition,0)
        let grouped = CoreTestSupport.plan(sets:1,secondExercise:true,drops:[DropTarget(work:.reps(.fixed(6)),weight:20)],group:"A")
        let date = CoreTestSupport.date(10)
        let session = CoreTestSupport.completed([12,6,10,8],weights:[60,20,60,20],plan:grouped,start:date)
        XCTAssertEqual(SessionStats.blockDuration(0,session:session),214)
        XCTAssertNil(SessionStats.blockDuration(1,session:session))
        var pacific=CoreTestSupport.utc(); pacific.timeZone=TimeZone(identifier:"America/Los_Angeles")!
        let utcStart=CoreTestSupport.date(10,hour:1)
        let late=CoreTestSupport.completed(start:utcStart)
        let entries=CalendarProjection.entries(month:date,activePlan:nil,sessions:[late],today:date,calendar:pacific)
        if case .completed = entries[8].entry { } else { XCTFail("UTC Sept 10 01:00 belongs to Sept 9 in Pacific time") }
        XCTAssertEqual(entries[9].entry,.none)
    }
    func testPromptRenderingAndLongPasteRegression() throws {
        let prompt = Prompts.render(settings:Settings(units:.lb,defaultRestSeconds:120))
        XCTAssertTrue(prompt.hasPrefix("JIMMSBRO-PLAN-PROMPT-V1\n"))
        XCTAssertTrue(prompt.contains("\"units\": \"lb\"")); XCTAssertTrue(prompt.contains("\"defaultRestSeconds\": 120")); XCTAssertTrue(prompt.contains("number in lb"))
        XCTAssertLessThan(prompt.count,4000); XCTAssertFalse(prompt.contains("{{")); XCTAssertFalse(prompt.contains("```"))
        XCTAssertEqual(PlanImport.run(prompt).errors.first?.code,"E_PROMPT_PASTED")
        let result = PlanImport.run(Prompts.exampleJSON)
        XCTAssertNotNil(result.plan); XCTAssertTrue(result.issues.isEmpty)
        XCTAssertEqual(try JSONDecoder().decode(RawJSON.self,from:Data(Prompts.exampleJSON.utf8)),try JSONDecoder().decode(RawJSON.self,from:FixtureLoader.data("valid/prompt-example.txt")))
        let errors = (0..<25).map { Issue(severity:.error,code:"E_NOT_JSON",path:"days[\($0)]",message:"Unexpected end of file.") }
        let fix = Prompts.render(errors:errors)
        XCTAssertEqual(fix.components(separatedBy:"\n").filter { $0.hasPrefix("- days[") }.count,20)
        XCTAssertTrue(fix.contains("…and 5 more")); XCTAssertTrue(fix.hasPrefix(Prompts.marker)); XCTAssertTrue(fix.contains("Unexpected end of file"))
        XCTAssertEqual(Prompts.render(errors:Array(errors.prefix(3))).components(separatedBy:"\n").filter { $0.hasPrefix("- days[") }.count,3)
        let exercise: [String:Any] = ["name":"胸 Bench","reps":10,"notes":String(repeating:"x",count:500)]
        let long: [String:Any] = ["name":"Large","days":(0..<31).map { ["name":"Day \($0)","exercises":Array(repeating:exercise,count:50)] as [String:Any] }]
        let data = try JSONSerialization.data(withJSONObject:long,options:[.sortedKeys])
        XCTAssertGreaterThan(data.count,10000); XCTAssertLessThan(data.count,PlanImport.maxBytes)
        let text = String(decoding:data,as:UTF8.self)
        let imported = PlanImport.run(text)
        XCTAssertEqual(imported.plan?.days.count,31); XCTAssertEqual(imported.plan?.days.last?.exercises.count,50)
        XCTAssertEqual(imported.plan?.sourceText,text)
        XCTAssertEqual(PlanImport.run(String(text.dropLast(20))).errors.first?.code,"E_NOT_JSON")
        let exact = "{\"days\":[]}" + String(repeating:" ",count:PlanImport.maxBytes-11)
        XCTAssertEqual(exact.utf8.count,PlanImport.maxBytes)
        XCTAssertFalse(PlanImport.run(exact).errors.contains { $0.code == "E_TOO_LARGE" })
        XCTAssertEqual(PlanImport.run(exact+" ").errors.first?.code,"E_TOO_LARGE")
    }
}

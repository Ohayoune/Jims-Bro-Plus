import Foundation
#if !CORE_CHECKS
import XCTest
#endif
#if !CORE_CHECKS
@testable import JimmsBro
#endif

final class ImportTests: XCTestCase {
    static var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    static let now = Date(timeIntervalSince1970: 1_788_480_000) // Date supplied below from manifest components.
    static var fixtureDate: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 4))! }
    func run(_ text: String, units: WeightUnit = .kg) -> ImportResult { PlanImport.run(text, settings: Settings(units: units), now: Self.fixtureDate, calendar: Self.calendar) }
    func object(_ value: Any) throws -> String { String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys,.fragmentsAllowed]), as: UTF8.self) }
    func plan(_ fields: [String: Any]) throws -> ImportResult {
        try run(object(["name":"Test","days":[["name":"A","exercises":[fields]]]]))
    }
    func testManifestM1() throws {
        let manifest = try FixtureLoader.manifest()
        for fixture in manifest.fixtures {
            let result = run(try FixtureLoader.text(fixture.file))
            if fixture.outcome == .valid {
                let p = try XCTUnwrap(result.plan, "\(fixture.file): \(result.issues)")
                XCTAssertTrue(result.errors.isEmpty, fixture.file)
                XCTAssertEqual(result.issues.filter { $0.severity == .warning }.map(\.code).sorted(), (fixture.warnings ?? []).sorted(), fixture.file)
                for (key, expected) in fixture.checks ?? [:] {
                    // Steps/rest at execution are verified by M2's manifest test.
                    if ["stepsPerDay","stepOrder","restAfterStep"].contains(key) { continue }
                    XCTAssertEqual(try manifestCheck(key, expected: expected, plan: p), expected, "\(fixture.file): \(key)")
                }
                XCTAssertEqual(try JSONDecoder().decode(Plan.self, from: JSONEncoder().encode(p)), p, fixture.file)
                var again = try XCTUnwrap(run(try FixtureLoader.text(fixture.file)).plan)
                again.id = p.id
                for d in p.days.indices {
                    again.days[d].id = p.days[d].id
                    for e in p.days[d].exercises.indices { again.days[d].exercises[e].id = p.days[d].exercises[e].id }
                }
                XCTAssertEqual(again, p, fixture.file)
            } else {
                XCTAssertNil(result.plan, fixture.file)
                for error in fixture.errors ?? [] {
                    XCTAssertTrue(result.errors.contains { $0.code == error.code && (error.path == nil || $0.path == error.path) }, "\(fixture.file): missing \(error)")
                }
                if fixture.exact ?? true { XCTAssertEqual(result.errors.count, fixture.errors?.count ?? 0, "\(fixture.file): \(result.errors)") }
                if let warnings = fixture.warnings { XCTAssertEqual(result.issues.filter { $0.severity == .warning }.map(\.code).sorted(), warnings.sorted(), fixture.file) }
                XCTAssertEqual(result.issues.map(\.path), result.issues.map(\.path).sorted())
                XCTAssertTrue(result.errors.allSatisfy { !$0.message.isEmpty })
            }
        }
    }
    func testExtractAndDecodeBoundaries() throws {
        let valid = try FixtureLoader.text("valid/single-day.json").trimmed
        XCTAssertEqual(PlanImport.extract(valid).value, valid) // A1
        for fence in ["json", "javascript", ""] {
            let result = run("```\(fence)\n\(valid)\n```")
            XCTAssertNotNil(result.plan); XCTAssertFalse(result.issues.contains { $0.code == "W_SURROUNDING_TEXT" }) // A2,A4
        }
        for s in ["", "  ", "\n\n", "\u{FEFF}\u{200B}"] { XCTAssertEqual(run(s).errors.first?.code, "E_EMPTY") }
        XCTAssertEqual(run(String(repeating: " ", count: 1_048_577)).errors.first?.code, "E_TOO_LARGE")
        XCTAssertEqual(run(String(repeating: "胸", count: 349_526)).errors.first?.code, "E_TOO_LARGE")
        XCTAssertEqual(run("```json\n\(valid)\n\(valid)\n```").errors.first?.code, "E_MULTIPLE_OBJECTS")
        for text in ["{'days': []}", "{\"days\": [],}", "{\"x\": NaN}", "{\"x\": Infinity}", "{\"x\": 01}", "{\"x\": 1.}", "null", "12", "\"hello\"", "{\n// comment\n\"days\":[]}"] {
            XCTAssertEqual(run(text).errors.first?.code, "E_NOT_JSON", text)
        }
        XCTAssertTrue(run("{\"days\":[").errors.first?.message.contains("Unexpected end of file") == true)
        XCTAssertTrue(run("{\"days\":[],}").errors.first?.message.contains("line") == true)
        let nested = String(repeating: "[", count: 300) + "0" + String(repeating: "]", count: 300)
        XCTAssertEqual(run(nested).errors.first?.code, "E_NOT_JSON")
        XCTAssertEqual(normalized(" \nBench\t Press  "), "bench press")
        XCTAssertNotEqual(normalized("Développé"), normalized("Developpe"))
    }
    func testScalarLeniencyTables() throws {
        for value in [10, 10.0, "10", " 10 ", "10 reps"] as [Any] {
            XCTAssertEqual(try plan(["name":"E","reps":value]).plan?.days[0].exercises[0].sets[0].work, .reps(.fixed(10)))
        }
        for value in ["8-12","8 - 12","8–12","8—12","8 to 12","8/12","8-12 reps"] {
            XCTAssertEqual(try plan(["name":"E","reps":value]).plan?.days[0].exercises[0].sets[0].work, .reps(.range(min: 8,max: 12)))
        }
        for value in ["AMRAP","amrap","Max","failure","to failure","as many as possible"] {
            XCTAssertEqual(try plan(["name":"E","reps":value]).plan?.days[0].exercises[0].sets[0].work, .reps(.amrap(min: nil)))
        }
        for value in ["10+","10 +"] { XCTAssertEqual(try plan(["name":"E","reps":value]).plan?.days[0].exercises[0].sets[0].work, .reps(.amrap(min: 10))) }
        let invalid: [Any] = [0, -5, 10.5, "ten", "", "8-", "-12", "8-12-15", true, [String:Int](), [Int](), 1001, "5-2000"]
        for value in invalid { XCTAssertTrue(try plan(["name":"E","reps":value]).errors.contains { $0.code == "E_REPS_INVALID" }, "\(value)") }
        for value in ["lots","AMRAP","0-5","10+",2.5,true] as [Any] { XCTAssertTrue(try plan(["name":"E","reps":10,"repRange":value]).errors.contains { $0.code == "E_REPRANGE_INVALID" }) }
        for (value, expected) in [(60,60),(62.5,62.5),("60",60),("62,5",62.5),("60 KG",60),("135 lbs",135),("+10kg",10),("+10",10),(62.55,62.6),(0,0),(10000,10000),("none",nil),("",nil),(NSNull(),nil)] as [(Any, Double?)] {
            XCTAssertEqual(try plan(["name":"E","reps":10,"weight":value]).plan?.days[0].exercises[0].sets[0].weight, expected)
        }
        for value in [-5,"heavy",true,[String:Int](),10001] as [Any] { XCTAssertTrue(try plan(["name":"E","reps":10,"weight":value]).errors.contains { $0.code == "E_WEIGHT_INVALID" }) }
        for value in [0,-1,2.5,true,"three"] as [Any] { XCTAssertTrue(try plan(["name":"E","reps":10,"sets":value]).errors.contains { $0.code == "E_SETS_INVALID" }) }
        for value in [3,3.0,"3"] as [Any] { XCTAssertEqual(try plan(["name":"E","reps":10,"sets":value]).plan?.days[0].exercises[0].sets.count, 3) }
        for value in [-1,3601,90.5,"1m30"] as [Any] { XCTAssertTrue(try plan(["name":"E","reps":10,"restSeconds":value]).errors.contains { $0.code == "E_REST_INVALID" }) }
        for value in ["90",90.0,3600,0] as [Any] { XCTAssertNotNil(try plan(["name":"E","reps":10,"restSeconds":value]).plan) }
        for value in [0,-1,30.5,"30s",86401,"forever","0+"] as [Any] { XCTAssertTrue(try plan(["name":"E","durationSeconds":value]).errors.contains { $0.code == "E_DURATION_INVALID" }) }
        for value in [45,"45",45.0,86400,"max","open","AMSAP","as long as possible","to failure","30+"] as [Any] { XCTAssertNotNil(try plan(["name":"E","durationSeconds":value]).plan) }
        for value in [0,-1,2.5,"soon",86400,"5"] as [Any] { XCTAssertTrue(try plan(["name":"E","durationSeconds":30,"warningBeep":value]).errors.contains { $0.code == "E_WARNING_BEEP_INVALID" }) }
        for (seconds, offset) in [(45,5),(25,3),(30,3),(600,60),(8,nil)] as [(Int,Int?)] {
            XCTAssertEqual(try plan(["name":"E","durationSeconds":seconds]).plan?.days[0].exercises[0].sets[0].warningBeepSeconds, offset)
        }
        for value in ["bw","BW","bodyweight","body weight"] { XCTAssertEqual(try plan(["name":"E","reps":10,"weight":value]).plan?.days[0].exercises[0].bodyweight, true) }
        for value in ["yes",1] as [Any] { XCTAssertTrue(try plan(["name":"E","reps":10,"bodyweight":value]).errors.contains { $0.code == "E_BODYWEIGHT_INVALID" }) }
    }
    func testDefaultsOverridesLimitsAndIdentity() throws {
        XCTAssertEqual(run(try FixtureLoader.text("valid/minimal.json"), units: .lb).plan?.units, .lb)
        for (input, unit) in [("KG",WeightUnit.kg),("kgs",.kg),("lbs",.lb),("Pounds",.lb),("kilograms",.kg)] {
            XCTAssertEqual(run(try object(["units":input,"days":[["exercises":[["name":"E","reps":1]]]]])).plan?.units, unit)
        }
        for input in ["Mon","monday","MONDAY","  tue "] {
            XCTAssertNotNil(run(try object(["days":[["weekday":input,"exercises":[["name":"E","reps":1]]]]])).plan)
        }
        for input in ["Funday","M","Mondays"] {
            XCTAssertTrue(run(try object(["days":[["weekday":input,"exercises":[["name":"E","reps":1]]]]])).errors.contains { $0.code == "E_WEEKDAY_INVALID" })
        }
        let p = try XCTUnwrap(plan(["name":"E","reps":8,"weight":60,"restSeconds":70,"sets":[["reps":10,"weight":50],["restSeconds":120],["durationSeconds":30]]]).plan)
        XCTAssertEqual(p.days[0].exercises[0].sets.map(\.weight), [50,60,60])
        XCTAssertEqual(p.days[0].exercises[0].sets.map(\.restSeconds), [70,120,70])
        XCTAssertEqual(p.days[0].exercises[0].sets.map(\.work), [.reps(.fixed(10)),.reps(.fixed(8)),.duration(seconds:30)])
        let reverse = try plan(["name":"E","durationSeconds":30,"sets":[["reps":10]]])
        XCTAssertEqual(reverse.plan?.days[0].exercises[0].sets[0].work,.reps(.fixed(10)))
        let day: [String:Any] = ["name":"A","exercises":[["name":"E","reps":10]]]
        XCTAssertEqual(run(try object(["days":Array(repeating:day,count:31)])).plan?.days.count,31)
        XCTAssertEqual(run(try object(["days":Array(repeating:day,count:32)])).errors.first?.code,"E_LIMIT_EXCEEDED")
        let names = run(try object(["days":[day,day,day]])).plan?.days.map(\.name)
        XCTAssertEqual(names,["A","A (2)","A (3)"])
        let source = try FixtureLoader.text("valid/fenced-with-prose.txt")
        XCTAssertEqual(run(source).plan?.sourceText, source)
        let lateBW = try plan(["name":"E","sets":[["reps":10,"weight":5],["reps":10,"weight":"bw"]]])
        XCTAssertEqual(lateBW.plan?.days[0].exercises[0].sets.map(\.weight),[nil,nil])
        let drops = try plan(["name":"E","reps":10,"drops":[["weight":15]],"sets":[[:],["drops":[["weight":10],["reps":8]]]]])
        XCTAssertEqual(drops.plan?.days[0].exercises[0].sets.map { $0.drops.count },[1,2])
    }
    func testRemainingNormalizeBoundaries() throws {
        XCTAssertEqual(try plan(["name":"E","reps":"1 rep"]).plan?.days[0].exercises[0].sets[0].work,.reps(.fixed(1)))
        for drops in [[5], [["weight":1],["weight":1],["weight":1],["weight":1],["weight":1],["weight":1]]] as [Any] {
            XCTAssertTrue(try plan(["name":"E","reps":10,"drops":drops]).errors.contains { $0.code == "E_DROPS_INVALID" })
        }
        let badReps = try plan(["name":"E","reps":10,"drops":[["reps":"ten"]]])
        XCTAssertTrue(badReps.errors.contains { $0.code == "E_REPS_INVALID" && $0.path == "days[0].exercises[0].drops[0].reps" })
        let extra = try plan(["name":"E","reps":10,"drops":[["tempo":"slow"]]])
        XCTAssertEqual(extra.issues.map(\.code),["W_UNKNOWN_FIELD"])
        XCTAssertEqual(extra.plan?.days[0].exercises[0].sets[0].drops[0],DropTarget(work:.reps(.amrap(min:nil)),weight:nil))
        let beep = try plan(["name":"E","durationSeconds":60,"warningBeep":15,"sets":[[:],["warningBeep":5]]])
        XCTAssertEqual(beep.plan?.days[0].exercises[0].sets.map(\.warningBeepSeconds),[15,5])
        let bw = try plan(["name":"E","reps":10,"bodyweight":true,"sets":[["weight":5]]])
        XCTAssertNil(bw.plan?.days[0].exercises[0].sets[0].weight); XCTAssertEqual(bw.issues.first?.code,"W_BODYWEIGHT_WEIGHT_IGNORED")
        let weighted = try plan(["name":"E","reps":10,"bodyweight":false,"weight":10])
        XCTAssertEqual(weighted.plan?.days[0].exercises[0].sets[0].weight,10)
        let openDrops = try plan(["name":"E","durationSeconds":"max","drops":[["weight":5]]])
        XCTAssertEqual(openDrops.issues.first?.code,"W_DROPS_IGNORED"); XCTAssertTrue(openDrops.plan?.days[0].exercises[0].sets[0].drops.isEmpty == true)
        let ex: [String:Any] = ["name":"E","group":1,"reps":10]
        let grouped = run(try object(["days":[["name":"Upper Body","exercises":[ex,ex]]],"cycle":[" upper   BODY ","rest"]]))
        XCTAssertEqual(grouped.plan?.days[0].exercises.map(\.group),["1","1"])
        XCTAssertEqual(grouped.plan?.cycle,[.day(0),.rest])
        for cycle in [Array(repeating:"A",count:32),[1,2]] as [Any] {
            let result = run(try object(["days":[["name":"A","exercises":[ex]]],"cycle":cycle]))
            XCTAssertTrue(result.errors.contains { $0.code == "E_CYCLE_INVALID" && $0.path == "cycle" })
        }
    }
    private func manifestCheck(_ key: String, expected: JSONValue, plan p: Plan) throws -> JSONValue {
        func json<T: Encodable>(_ v: T) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(v)) }
        func work(_ w: WorkTarget) -> String { workString(w) }
        switch key {
        case "planName": return .string(p.name)
        case "units": return .string(p.units.rawValue)
        case "schedule": return .string(p.schedule.rawValue)
        case "dayNames": return try json(p.days.map(\.name))
        case "weekdays": return try json(p.days.map { $0.weekday?.rawValue })
        case "cycle": return try json(p.cycle.map { if case let .day(i) = $0 { return p.days[i].name }; return "rest" })
        // TP18 (v1.10, D82): the plan's walk between exercises, or null.
        case "restBetweenExercises": return p.restBetweenExercises.map { .number(Double($0)) } ?? .null
        default:
            guard case let .object(entries) = expected else { XCTFail("Unexpected check shape \(key)"); return .null }
            var result: [String:JSONValue] = [:]
            for path in entries.keys {
                let parts = path.split(separator:".").compactMap { Int($0) }
                let d = p.days[parts[0]]
                if key == "exerciseNames" { result[path] = try json(d.exercises.map(\.name)); continue }
                if key == "groups" { result[path] = try json(d.exercises.map(\.group)); continue }
                let e = d.exercises[parts[1]]
                switch key {
                case "notes": result[path] = try json(e.notes)
                case "bodyweight": result[path] = .bool(e.bodyweight)
                case "repRange": result[path] = try json(e.repRange.map { [$0.min,$0.max] })
                case "restPerSet": result[path] = try json(e.sets.map(\.restSeconds))
                case "weightPerSet": result[path] = try json(e.sets.map(\.weight))
                case "workPerSet": result[path] = try json(e.sets.map { work($0.work) })
                case "warningPerSet": result[path] = try json(e.sets.map(\.warningBeepSeconds))
                case "inReservePerSet": result[path] = try json(e.sets.map(\.inReserve))
                case "dropsPerSet": result[path] = try json(e.sets.map { $0.drops.count })
                case "dropTargets": result[path] = .array(e.sets[parts[2]].drops.map { .array([.string(work($0.work)), $0.weight.map(JSONValue.number) ?? .null]) })
                default: XCTFail("Unrecognized manifest check: \(key)")
                }
            }
            return .object(result)
        }
    }
}
func workString(_ w: WorkTarget) -> String {
    switch w {
    case let .duration(n): return "duration:\(n)"
    case let .openDuration(n): return n.map { "open:\($0)" } ?? "open"
    case let .reps(r):
        switch r {
        case let .fixed(n): return "fixed:\(n)"
        case let .range(a,b): return "range:\(a)-\(b)"
        case let .amrap(n): return n.map { "amrap:\($0)" } ?? "amrap"
        }
    }
}

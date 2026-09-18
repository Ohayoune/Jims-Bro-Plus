import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// v1.12 (D96): one owner for each piece of logic. Where two copies disagreed, these pin the side
/// that won, so a copy that grows back and drifts shows up here.
final class OneOwnerTests: XCTestCase {
    private let settings = Settings(warmUpSeconds: 0, transitionRestSeconds: 0)

    private func step(_ fields: String) -> ProgressionImport.Result {
        let reply = #"{ "steps": 1, "exercises": [ { "name": "Bench Press", "steps": [ "# + fields + #" ] } ] }"#
        return ProgressionImport.run(reply, plan: CoreTestSupport.plan(), settings: settings,
                                     now: CoreTestSupport.now, mode: .calendar)
    }

    private func planReps(_ reps: String) -> ImportResult {
        PlanImport.run(CoreTestSupport.planJSON(exercise: #"{ "name": "Bench Press", "sets": 1, "reps": "\#(reps)" }"#),
                       settings: settings, now: CoreTestSupport.now)
    }

    // TL1: reps mean the same in a plan, a progression step and the exercise sheet — 1 to 1000,
    // the same words and separators. A step said "reps": 0 was accepted while a plan refused it.
    func testRepsReadTheSameEverywhere() {
        XCTAssertEqual(planReps("0").errors.map(\.code), ["E_REPS_INVALID"])
        XCTAssertEqual(step(#"{ "reps": 0 }"#).errors.map(\.code), ["E_REPS_INVALID"])
        XCTAssertNil(PlanEdit.parseWork("0"))

        XCTAssertTrue(planReps("1000").errors.isEmpty)
        XCTAssertNotNil(step(#"{ "reps": 1000 }"#).progression)
        XCTAssertEqual(PlanEdit.parseWork("1000"), .reps(.fixed(1000)))

        for text in ["8 to 12", "8/12", "8—12", "8-12 reps"] {
            XCTAssertEqual(planReps(text).plan?.days[0].exercises[0].sets[0].work, .reps(.range(min: 8, max: 12)), text)
            XCTAssertEqual(step(#"{ "reps": ""# + text + #"" }"#).progression?.entries.first?.weeks.first?.work,
                           .reps(.range(min: 8, max: 12)), text)
            XCTAssertEqual(PlanEdit.parseWork(text), .reps(.range(min: 8, max: 12)), text)
        }
    }

    // TL1: a range written high to low is swapped with a warning wherever there is a warning to
    // give, and refused in the sheet, which has none.
    func testABackwardsRangeIsSwappedOrRefused() {
        XCTAssertEqual(planReps("12-8").plan?.warnings.map(\.code), ["W_RANGE_SWAPPED"])
        let swapped = step(#"{ "reps": "12-8" }"#)
        XCTAssertEqual(swapped.issues.map(\.code), ["W_RANGE_SWAPPED"])
        XCTAssertEqual(swapped.progression?.entries.first?.weeks.first?.work, .reps(.range(min: 8, max: 12)))
        XCTAssertNil(PlanEdit.parseWork("12-8"))
        XCTAssertNil(PlanEdit.parseRange("12-8"))
    }

    // TL2: the sheet's range field reads a range as a plan's repRange is read, so a plan whose
    // repRange is 8–8 opens in the sheet and saves untouched.
    func testTheRangeFieldReadsARepRange() throws {
        XCTAssertEqual(PlanEdit.parseRange("8"), RepRange(min: 8, max: 8))
        XCTAssertEqual(PlanEdit.parseRange("8-8"), RepRange(min: 8, max: 8))
        XCTAssertEqual(PlanEdit.parseRange("8 to 12"), RepRange(min: 8, max: 12))
        var plan = CoreTestSupport.plan()
        plan.days[0].exercises[0].repRange = RepRange(min: 8, max: 8)
        let fields = PlanEdit.ExerciseFields(plan.days[0].exercises[0])
        XCTAssertTrue(fields.canSave)
        XCTAssertTrue(fields.changes(from: plan.days[0].exercises[0]).isEmpty)
    }

    // TL3: a progression step's weight reads as a plan's does — a stray unit is named, "+10" is
    // ten — and keeps its own "same", and is snapped rather than rounded to a tenth.
    func testAStepWeightReadsAsAPlanWeight() {
        let pounds = step(#"{ "weight": "60 lb" }"#)
        XCTAssertEqual(pounds.issues.map(\.code), ["W_WEIGHT_UNIT_IGNORED"])
        XCTAssertEqual(pounds.progression?.entries.first?.weeks.first?.weight, 60)
        XCTAssertEqual(step(#"{ "weight": "+10" }"#).progression?.entries.first?.weeks.first?.weight, 10)
        XCTAssertEqual(step(#"{ "weight": "same" }"#).progression?.entries.first?.weeks.first?.weight, nil)
        XCTAssertEqual(step(#"{ "weight": 20000 }"#).errors.map(\.code), ["E_WEIGHT_INVALID"])
        let odd = step(#"{ "weight": 62.55 }"#)
        XCTAssertEqual(odd.issues.map(\.code), ["W_PROGRESSION_ROUNDED"], "snapped once, not rounded first")
    }

    // TL4: every piece of JSON the app writes by hand quotes its text with the one escaper, so
    // a name with a quote in it still parses. `exampleDay` wrote the name in raw.
    func testHandWrittenJSONQuotesItsText() throws {
        let name = #"Push "heavy" \ day"#
        let day = PlanImport.decode(JSONPoint.exampleDay(name: name)).value
        XCTAssertEqual(day?["name"]?.string, name)

        var plan = CoreTestSupport.plan()
        plan.days[0].name = name
        plan.days[0].exercises[0].name = #"Bench "flat""#
        let reply = PlanImport.decode(ProgressionScreen.exampleReply(plan: plan, steps: 2)).value
        XCTAssertEqual(reply?["exercises"]?.array?.first?["day"]?.string, name)
        XCTAssertEqual(reply?["exercises"]?.array?.first?["name"]?.string, #"Bench "flat""#)
    }

    // TL5: E_NOT_JSON's two readings — a plan in words, or a reply cut short — are one
    // predicate each, read by the refusal and by the friendly text alike.
    func testNotJSONHasTwoReadings() throws {
        let words = try XCTUnwrap(PlanImport.run("Monday: bench 3x8, rows 3x10").errors.first)
        let cut = try XCTUnwrap(PlanImport.run(#"{ "name": "Push", "days": ["#).errors.first)
        XCTAssertTrue(words.isPlanInWords); XCTAssertFalse(words.isCutShort)
        XCTAssertTrue(cut.isCutShort); XCTAssertFalse(cut.isPlanInWords)
        XCTAssertEqual(ImportTrip.Refusal.of([words]).sends, .prompt)
        XCTAssertTrue(ImportTrip.Refusal.of([cut]).offersDayByDay)
        XCTAssertTrue(IssueText.friendly(words).contains("plan in words"))
        XCTAssertTrue(IssueText.friendly(cut).contains("cut off"))
    }
}

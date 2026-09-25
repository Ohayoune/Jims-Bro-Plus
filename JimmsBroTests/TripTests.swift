import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// TN1–TN6 (v1.11, N1): the trunk the four tracks build on — the trip's stage, strip and buttons
/// (D87, D89), the exercise sheet's two forms (D93's seam), the change prompt (D94's text), and
/// the documents and project file that make the tracks independent.
final class TripTests: XCTestCase {
    // TN1: the strip for every stage — three marks, always, lit where the stage is.
    func testTheStripForEveryStage() {
        XCTAssertEqual(TripStrip.names, ["Prompt", "Chat", "Paste"])
        XCTAssertEqual(TripStrip.of(.ask).marks, [.now, .todo, .todo])
        XCTAssertEqual(TripStrip.of(.paste).marks, [.done, .done, .now])
        XCTAssertEqual(TripStrip.of(.review).marks, [.done, .done, .done])
        XCTAssertEqual(TripStrip.of(.refused).marks, [.done, .now, .todo], "the fix is at Chat by default")
        XCTAssertEqual(TripStrip.of(.refused, fix: .chat).marks, [.done, .now, .todo], "ask the chatbot again")
        XCTAssertEqual(TripStrip.of(.refused, fix: .paste).marks, [.done, .done, .now], "the prompt itself, or nothing, was pasted")
        // The fix is only read on a refusal, and never makes a fourth mark.
        XCTAssertEqual(TripStrip.of(.ask, fix: .paste), TripStrip.of(.ask))
        for stage in [TripStage.ask, .paste, .review, .refused] {
            for fix in TripFix.allCases {
                let strip = TripStrip.of(stage, fix: fix)
                XCTAssertEqual(strip.marks.count, 3, "\(stage) at \(fix)")
                XCTAssertLessThanOrEqual(strip.marks.filter { $0 == .now }.count, 1, "\(stage) at \(fix)")
            }
        }
        XCTAssertEqual(TripStrip.of(.refused, fix: .chat).spoken, "Prompt, done. Chat, now. Paste, not yet.")
    }

    // TN2: the bottom slot's words.
    func testTheButtonsWords() {
        XCTAssertEqual(TripButtons.ask(), TripButtons(primary: "Send the prompt", secondary: "Copy the prompt"))
        XCTAssertEqual(TripButtons.ask("the outline prompt").primary, "Send the outline prompt")
        XCTAssertEqual(TripButtons.ask("the prompt for Pull").secondary, "Copy the prompt for Pull")
        XCTAssertEqual(TripButtons.paste.primary, "Paste")
        XCTAssertNil(TripButtons.paste.secondary)
        XCTAssertEqual(TripButtons.effect("Use Push Pull Legs"), TripButtons(primary: "Use Push Pull Legs", secondary: nil))
        XCTAssertEqual(TripButtons.effect("Apply 2 changes").primary, "Apply 2 changes")
    }

    // TN3: the exercise sheet's value form and its operation form make the same exercise from
    // the same edits — the operation form through `PlanEdit.apply` on a one-exercise plan.
    func testTheSheetsTwoFormsAgree() throws {
        let settings = Settings()
        let plan = CoreTestSupport.plan()
        let original = plan.days[0].exercises[0]

        let untouched = PlanEdit.ExerciseFields(original)
        XCTAssertTrue(untouched.canSave)
        XCTAssertEqual(untouched.changes(from: original), [], "an untouched exercise is untouched")
        XCTAssertEqual(PlanEdit.edited(original, []), original)

        var fields = untouched
        fields.name = "Dumbbell Bench Press"
        fields.sets = 4
        fields.reps = "6-8"
        fields.range = "6-8"
        fields.weight = "32"
        fields.rest = "120"
        fields.reserve = "2"
        XCTAssertTrue(fields.canSave)
        let changes = fields.changes(from: original)
        XCTAssertEqual(changes, [.name("Dumbbell Bench Press"), .setCount(4), .reps("6-8"), .range("6-8"),
                                 .weight(32), .rest(120), .inReserve(2)])

        var operated = plan
        for change in changes {
            let result = PlanEdit.apply(change.operation(day: 0, exercise: 0), to: operated, settings: settings)
            operated = try XCTUnwrap(result.plan, "\(change): \(result.issues)")
        }
        let byOperations = operated.days[0].exercises[0]
        let byValue = try XCTUnwrap(PlanEdit.edited(original, changes))

        XCTAssertEqual(PlanJSON.render(exercise: byValue), PlanJSON.render(exercise: byOperations))
        for exercise in [byValue, byOperations] {
            XCTAssertEqual(exercise.name, "Dumbbell Bench Press")
            XCTAssertEqual(exercise.sets.count, 4)
            XCTAssertEqual(exercise.repRange, RepRange(min: 6, max: 8))
            XCTAssertTrue(exercise.sets.allSatisfy { $0.work == .reps(.range(min: 6, max: 8)) })
            XCTAssertEqual(Set(exercise.sets.map(\.weight)), [32])
            XCTAssertEqual(Set(exercise.sets.map(\.restSeconds)), [120])
            XCTAssertEqual(Set(exercise.sets.map(\.inReserve)), [2])
        }

        // Clearing the optional fields agrees too, and what cannot be saved says so.
        var cleared = PlanEdit.ExerciseFields(byValue)
        cleared.range = ""
        cleared.weight = ""
        cleared.reserve = ""
        let clearing = cleared.changes(from: byValue)
        XCTAssertEqual(clearing, [.range(nil), .weight(nil), .inReserve(nil)])
        var reoperated = operated
        for change in clearing {
            reoperated = try XCTUnwrap(PlanEdit.apply(change.operation(day: 0, exercise: 0), to: reoperated, settings: settings).plan)
        }
        XCTAssertEqual(PlanJSON.render(exercise: try XCTUnwrap(PlanEdit.edited(byValue, clearing))),
                       PlanJSON.render(exercise: reoperated.days[0].exercises[0]))
        cleared.reps = "eight"
        XCTAssertFalse(cleared.canSave)
        XCTAssertNil(PlanEdit.edited(original, [.setCount(0)]), "a change the operation form refuses")
    }

    // TN4: the change prompt carries the marker, the request as typed and the plan's canonical
    // JSON, and no history; pasted back, it is the prompt.
    func testTheChangePrompt() throws {
        let plan = CoreTestSupport.plan(secondExercise: true)
        let request = "Swap the barbell bench press for dumbbells. Pull is too long, drop one exercise."
        let text = Prompts.change(plan: plan, request: request, settings: Settings())

        XCTAssertTrue(text.hasPrefix(Prompts.changeMarker + "\n"))
        XCTAssertEqual(Prompts.changeMarker, "JIMMSBRO-CHANGE-PROMPT-V1")
        XCTAssertTrue(text.contains("reply with the WHOLE plan as ONE complete JSON object in a single code block tagged json"))
        XCTAssertTrue(text.contains("WHAT TO CHANGE\n" + request + "\n\nMY PLAN\n"), text)
        XCTAssertTrue(text.contains("MY PLAN\n" + PlanJSON.render(plan)), "the plan as its canonical JSON")
        XCTAssertFalse(text.contains(Prompts.planListing(plan)), "not the listing, which loses rest, notes and in reserve")
        XCTAssertTrue(text.contains("a multiple of 2.5 kg"))
        XCTAssertFalse(text.contains("MY HISTORY"))
        XCTAssertFalse(text.contains("{{"), "every placeholder filled")
        XCTAssertFalse(text.contains("```"), "a fence in the prompt would look like a reply")

        // A request that happens to name a placeholder is the words it was.
        let odd = Prompts.change(plan: plan, request: "Leave {{plan}} alone", settings: Settings())
        XCTAssertTrue(odd.contains("WHAT TO CHANGE\nLeave {{plan}} alone\n"))
        XCTAssertEqual(odd.components(separatedBy: PlanJSON.render(plan)).count, 2, "the plan once")

        // Pasted back, it is the prompt — though it holds a whole plan's JSON.
        XCTAssertEqual(PlanImport.run(text, settings: Settings()).issues.first?.code, "E_PROMPT_PASTED")
        // The reply, fenced, imports as the plan.
        let reply = "Here it is:\n```json\n" + PlanJSON.render(plan) + "\n```"
        XCTAssertNotNil(PlanImport.run(reply, settings: Settings()).plan)
    }

    // TN5 (pin): SPEC names the three states and the strip's three words as Core does, and the
    // one sentence about carrying the text is the introduction's, not the prompt's.
    func testTheRuleIsSpecsAndTheSentenceIsTheIntroductions() throws {
        let sentence = "The app never talks to the chatbot itself; you carry the text both ways."
        XCTAssertEqual(Introduction.mechanism, sentence)
        XCTAssertTrue(Introduction.pages[0].title == "A plan, then Start")
        XCTAssertTrue(Introduction.pages[0].body.contains(sentence), "the introduction's first page says it")
        XCTAssertEqual(Introduction.pages.filter { $0.body.contains(sentence) }.count, 1, "said once")
        XCTAssertFalse(Prompts.render(settings: Settings()).contains(sentence), "the chatbot is not told it")

        guard let spec = FixtureLoader.doc("docs/SPEC.md") else {
            throw XCTSkip("the checkout is outside the simulator's sandbox; this pin runs on the host routes")
        }
        let rule = try section(spec, "### 6.60 ")
        for state in ["Ask", "Paste", "Review", "Refused"] {
            XCTAssertTrue(rule.contains("\n- **\(state).**"), "§6.60 no longer names \(state) as a state")
        }
        let strip = try section(spec, "### 6.62 ")
        XCTAssertTrue(strip.contains(TripStrip.names.map { "*\($0)*" }.joined(separator: ", ")),
                      "§6.62's words are not TripStrip.names")
    }

    // TN6 (pin): TEST_CASES has a block per milestone of the release, and the project file
    // already holds every file a track fills — so no track adds one.
    func testTheTracksFindTheirFilesAndTheirBlocks() throws {
        guard let cases = FixtureLoader.doc("docs/TEST_CASES.md"),
              let project = FixtureLoader.doc("JimmsBro.xcodeproj/project.pbxproj"),
              let package = FixtureLoader.doc("Package.swift") else {
            throw XCTSkip("the checkout is outside the simulator's sandbox; this pin runs on the host routes")
        }
        let release = try section(cases, "## TN. ", until: "## ")
        let blocks = release.components(separatedBy: "\n").filter { $0.hasPrefix("### N") }
        XCTAssertEqual(blocks.map { String($0.prefix(6)) },
                       ["### N1", "### N2", "### N3", "### N4", "### N5", "### N6"])

        let core = ["Trip", "ImportTrip", "DraftTrip", "ProgressionScreen", "ProgressionLadder", "DayEdit",
                    "ExerciseNames", "PlanDiff", "ChangeRequest"]
        let views = ["PromptButtons", "DayEditorView", "ChangePlanView", "ExerciseEditSheet"]
        let tests = ["TripTests", "RoundTripImportTests", "RoundTripProgressionTests", "DayEditTests", "PlanDiffTests"]
        for name in core + views + tests {
            XCTAssertTrue(project.contains("/* \(name).swift in Sources */"), "\(name).swift is not built")
        }
        for name in tests {
            XCTAssertTrue(package.contains("\"JimmsBroTests/\(name).swift\""), "swift test does not run \(name)")
        }
        XCTAssertTrue(project.contains("path = Shared;"), "no Features/Shared group")
    }

    // TN38 (pin): what N6 took out stays out. The merge deleted the day-by-day screen, the two
    // sentences the numbered steps carried (D87), the picker's closing line and the word JSON
    // from the doors, so no file under JimmsBro/ names any of them again.
    func testWhatTheMergeTookOutStaysOut() throws {
        let sources = try Self.swiftSources()
        guard !sources.isEmpty else {
            throw XCTSkip("the checkout is outside the simulator's sandbox; this pin runs on the host routes")
        }
        // A name that must appear nowhere, and what replaced it.
        let gone = [("copyStep", "D87: the trip strip says where you are"),
                    ("PromptText.mechanism", "D87: the sentence is the introduction's first page"),
                    ("DraftPlanView", "D91: a draft is Add plan's own review"),
                    ("buildYourOwn", "D90: the built-in plans are a row on Add plan"),
                    ("AddPlanRequest.builtIns", "D90: every door opens the same screen"),
                    ("Show text", "D95: the text is the ···'s Edit the text"),
                    ("Edit day as JSON", "D77, D95: the sheet is named for what the text is")]
        for (name, why) in gone {
            let named = sources.filter { $0.text.contains(name) }.map(\.path)
            XCTAssertTrue(named.isEmpty, "\(named.joined(separator: ", ")) still names \(name) — \(why)")
        }
        // And the one word each door uses is Core's, written once (§6.68).
        let editors = sources.filter { $0.path.hasPrefix("JimmsBro/Features/") && $0.text.contains("\"Edit the text\"") }
        XCTAssertTrue(editors.isEmpty, "\(editors.map(\.path).joined(separator: ", ")) writes Edit the text out again")
    }

    /// Every Swift file of the app target, as (path relative to the checkout, contents) — empty
    /// when the checkout is out of reach, as it is inside the simulator.
    static func swiftSources() throws -> [(path: String, text: String)] {
        let root = FixtureLoader.sourceRoot
        let app = root.appendingPathComponent("JimmsBro")
        guard let walk = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil) else { return [] }
        var out: [(String, String)] = []
        for case let url as URL in walk where url.pathExtension == "swift" {
            let path = url.path.replacingOccurrences(of: root.path + "/", with: "")
            out.append((path, try String(contentsOf: url, encoding: .utf8)))
        }
        return out
    }

    /// The lines under a heading that starts with `heading`, up to the next heading that starts
    /// with `until`.
    private func section(_ text: String, _ heading: String, until: String = "#") throws -> String {
        let lines = text.components(separatedBy: "\n")
        let start = try XCTUnwrap(lines.firstIndex { $0.hasPrefix(heading) }, "no \(heading)")
        return lines[(start + 1)...].prefix { !$0.hasPrefix(until) }.joined(separator: "\n")
    }
}

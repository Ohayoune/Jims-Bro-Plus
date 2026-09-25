import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// TN7–TN14 (v1.11, N2): **Add plan** as a round trip — Ask, Paste, Review and Refused
/// (`ImportTrip`, D87, D88), the built-in plans as a row (D90), and day by day offered on a
/// refusal (`DraftTrip`, D91). TN15–TN16 are on the device.
final class RoundTripImportTests: XCTestCase {
    private let now = CoreTestSupport.now
    private let settings = Settings()

    private func imported(_ fixture: String) throws -> ImportResult {
        PlanImport.run(try FixtureLoader.text(fixture), settings: settings, now: now)
    }

    // TN7: the transitions, on the fixtures: a valid paste, the prompt, nothing, a reply cut
    // short, a plan in words, any other refusal, the fix, a built-in.
    func testAddPlansTransitions() throws {
        var trip = ImportTrip()
        XCTAssertEqual(trip.stage, .ask)
        XCTAssertEqual(trip.buttons, .ask())
        XCTAssertEqual(trip.prompt(settings: settings), Prompts.render(settings: settings))
        XCTAssertEqual(trip.subject, "A workout plan")

        trip.sent()
        XCTAssertEqual(trip.stage, .paste)
        XCTAssertEqual(trip.buttons, .paste, "Paste sends nothing; its one button is the system's")

        let valid = CoreTestSupport.planJSON()
        trip.pasted(result: PlanImport.run(valid, settings: settings, now: now), text: valid)
        XCTAssertEqual(trip.stage, .review)
        XCTAssertEqual(trip.review?.name, "Training")
        XCTAssertNil(trip.refusal)
        XCTAssertEqual(trip.buttons, .effect("Use Training"))

        // The prompt pasted back, and nothing pasted: fixed at Paste, by sending the prompt again.
        for fixture in ["invalid/prompt-pasted.txt", "invalid/empty.txt"] {
            var refused = ImportTrip()
            refused.sent()
            refused.pasted(result: try imported(fixture))
            XCTAssertEqual(refused.stage, .refused, fixture)
            XCTAssertEqual(refused.refusal?.fix, .paste, fixture)
            XCTAssertEqual(refused.strip.marks, [.done, .done, .now], fixture)
            XCTAssertEqual(refused.buttons, .ask(), fixture)
            XCTAssertEqual(refused.refusal?.sends, .prompt, fixture)
            XCTAssertEqual(refused.prompt(settings: settings), Prompts.render(settings: settings), fixture)
            XCTAssertEqual(refused.refusal?.offersDayByDay, false, fixture)
            XCTAssertNil(refused.review, fixture)
        }

        // A reply cut short: asked for whole at Chat, or day by day.
        var cut = ImportTrip()
        cut.sent()
        cut.pasted(result: try imported("invalid/truncated.txt"))
        XCTAssertEqual(cut.refusal?.fix, .chat)
        XCTAssertEqual(cut.strip.marks, [.done, .now, .todo])
        XCTAssertEqual(cut.buttons, TripButtons(primary: "Ask for the whole plan", secondary: "Copy the prompt"))
        XCTAssertEqual(cut.refusal?.offersDayByDay, true, "Get it day by day, a button of its own beneath")
        XCTAssertEqual(TripRefusal.dayByDay, "Get it day by day")
        XCTAssertEqual(cut.refusal?.sends, .wholePlan)
        XCTAssertEqual(cut.prompt(settings: settings), Prompts.render(errors: try imported("invalid/truncated.txt").errors))
        XCTAssertEqual(cut.refusal?.sentences.first,
                       "The plan isn't complete — the chatbot's reply looks cut off. Ask it to send the whole plan again.",
                       "the refusal offers day by day exactly where IssueText says cut off")

        // A plan in words has not met the prompt yet: its sentence says to send it one (D55).
        var words = ImportTrip()
        words.pasted(result: try imported("invalid/not-json-at-all.txt"))
        XCTAssertEqual(words.refusal?.fix, .chat)
        XCTAssertEqual(words.buttons, .ask())
        XCTAssertEqual(words.refusal?.offersDayByDay, false)
        XCTAssertTrue(words.refusal?.sentences.first?.hasPrefix("This is a plan in words.") == true)

        // Any other refusal: Ask for the whole plan, alone.
        for fixture in ["invalid/no-days.json", "invalid/multi-error.json", "invalid/cycle-unknown-day.json"] {
            var other = ImportTrip()
            other.pasted(result: try imported(fixture))
            XCTAssertEqual(other.stage, .refused, fixture)
            XCTAssertEqual(other.refusal?.fix, .chat, fixture)
            XCTAssertEqual(other.buttons, TripButtons(primary: "Ask for the whole plan", secondary: "Copy the prompt"), fixture)
            XCTAssertEqual(other.refusal?.offersDayByDay, false, fixture)
            XCTAssertEqual(other.refusal?.sends, .wholePlan, fixture)
        }

        // The fix went back to the chatbot: the screen waits for its reply.
        cut.sent()
        XCTAssertEqual(cut.stage, .paste)
        XCTAssertNil(cut.refusal)

        // A built-in: straight to the review, with its paragraph, asking the unit.
        var builtIn = ImportTrip()
        let plan = try XCTUnwrap(PlanImport.run(valid, settings: settings, now: now).plan)
        builtIn.builtIn(plan, about: "Two workouts, A and B.")
        XCTAssertEqual(builtIn.stage, .review)
        XCTAssertEqual(builtIn.about, "Two workouts, A and B.")
        XCTAssertTrue(builtIn.asksUnits)
        XCTAssertTrue(builtIn.fromBuiltIn, "saved beside a copy of itself, as the picker did")
        XCTAssertFalse(trip.fromBuiltIn)
        builtIn.restart()
        XCTAssertEqual(builtIn.stage, .ask)
        XCTAssertNil(builtIn.review)
        XCTAssertNil(builtIn.about)
    }

    // TN8: Add plan's strip is `TripStrip.of` at every stage — three marks, lit where it is.
    func testAddPlansStrip() throws {
        var trip = ImportTrip()
        XCTAssertEqual(trip.strip, TripStrip.of(.ask))
        trip.sent()
        XCTAssertEqual(trip.strip, TripStrip.of(.paste))
        trip.pasted(result: try imported("invalid/no-days.json"))
        XCTAssertEqual(trip.strip, TripStrip.of(.refused, fix: .chat))
        trip.pasted(result: try imported("invalid/prompt-pasted.txt"))
        XCTAssertEqual(trip.strip, TripStrip.of(.refused, fix: .paste))
        trip.pasted(result: PlanImport.run(CoreTestSupport.planJSON(), settings: settings, now: now))
        XCTAssertEqual(trip.strip, TripStrip.of(.review))
        XCTAssertEqual(trip.strip.marks.count, 3)
    }

    // TN9: the review's button uses the plan; the ··· keeps it without, and ends with Edit the
    // text, whose example saves as it stands and whose errors land on their lines.
    @MainActor func testUseAndKeepWithoutUsing() async throws {
        var trip = ImportTrip()
        XCTAssertEqual(trip.menu.map(\.title), ["Open a file", "Edit the text"])
        trip.sent()
        XCTAssertEqual(trip.menu.map(\.title), ["Send the prompt again", "Open a file", "Edit the text"])
        let text = CoreTestSupport.planJSON()
        trip.pasted(result: PlanImport.run(text, settings: settings, now: now), text: text)
        XCTAssertEqual(trip.buttons.primary, "Use Training")
        XCTAssertEqual(trip.menu, [.keepWithoutUsing, .editText])
        XCTAssertEqual(trip.menu.last?.title, "Edit the text")
        XCTAssertFalse(trip.asksUnits, "the plan named kg")
        XCTAssertEqual(trip.textPoint.template, trip.review?.sourceText, "the review's text is the plan's")
        XCTAssertFalse(trip.textPoint.title.contains("JSON"))
        XCTAssertEqual(trip.textPoint.saveTitle, "Review the plan")

        let root = CoreTestSupport.makeRoot("RoundTripImport")
        defer { CoreTestSupport.discard(root) }
        let model = AppModel(store: Store(root: root))
        await model.load()

        // The first plan ever saved becomes current either way; after it, Use makes a plan
        // current and Keep without using does not.
        let first = try XCTUnwrap(trip.planToSave(units: .kg))
        await model.save(first, makeActive: false)
        XCTAssertEqual(model.activePlanId, first.id, "the very first plan is current either way")

        let used = try XCTUnwrap(model.runImport(CoreTestSupport.planJSON().replacingOccurrences(of: "Training", with: "Used"), now: now).plan)
        await model.save(used, makeActive: true)
        XCTAssertEqual(model.activePlanId, used.id, "Use")
        let kept = try XCTUnwrap(model.runImport(CoreTestSupport.planJSON().replacingOccurrences(of: "Training", with: "Kept"), now: now).plan)
        await model.save(kept, makeActive: false)
        XCTAssertEqual(model.activePlanId, used.id, "Keep without using")
        XCTAssertEqual(Set(model.plans.map(\.name)), ["Training", "Used", "Kept"])

        // Edit the text on Ask opens on a plan the importer takes as it stands.
        let example = PlanImport.run(ImportTrip().textPoint.template, settings: settings, now: now)
        XCTAssertNotNil(example.plan, "\(example.issues)")
        XCTAssertTrue(example.errors.isEmpty)
        // After a cut-short reply it opens on what was pasted; after the prompt, on the example.
        var cut = ImportTrip()
        let truncated = try FixtureLoader.text("invalid/truncated.txt")
        cut.pasted(result: PlanImport.run(truncated, settings: settings, now: now), text: truncated)
        XCTAssertEqual(cut.textPoint.template, truncated)
        var prompt = ImportTrip()
        let promptText = try FixtureLoader.text("invalid/prompt-pasted.txt")
        prompt.pasted(result: PlanImport.run(promptText, settings: settings, now: now), text: promptText)
        XCTAssertEqual(prompt.textPoint.template, JSONPoint.examplePlan)

        // A whole plan's error is marked at its line.
        let broken = """
        {
          "name": "Two days",
          "days": [
            { "name": "A", "exercises": [ { "name": "Squat", "sets": 3, "reps": 5 } ] },
            { "name": "B", "exercises": [ { "name": "Row", "sets": 3, "reps": "lots" } ] }
          ]
        }
        """
        let refusal = PlanImport.run(broken, settings: settings, now: now).errors
        XCTAssertFalse(refusal.isEmpty)
        let marks = JSONPoint.replacing("Two days", text: broken).marks(for: refusal, in: broken)
        XCTAssertEqual(marks.marked.map(\.line), [5], "B's line, counted from 1: \(refusal) → \(marks)")
        XCTAssertEqual(JSONPoint.replacing("Two days", text: broken).saveTitle, "Replace Two days")
    }

    // TN10: a plan that named no unit asks kg / lb on the review, and Use writes the one chosen.
    @MainActor func testTheReviewAsksTheUnit() async throws {
        let silent = CoreTestSupport.planJSON().replacingOccurrences(of: #""units": "kg", "#, with: "")
        var trip = ImportTrip()
        trip.pasted(result: PlanImport.run(silent, settings: settings, now: now), text: silent)
        XCTAssertEqual(trip.stage, .review)
        XCTAssertTrue(trip.asksUnits)
        let plan = try XCTUnwrap(trip.planToSave(units: .lb))
        XCTAssertEqual(plan.units, .lb)
        XCTAssertTrue(plan.sourceText.contains(#""units" : "lb""#) || plan.sourceText.contains(#""units": "lb""#), plan.sourceText)

        let root = CoreTestSupport.makeRoot("RoundTripUnits")
        defer { CoreTestSupport.discard(root) }
        let model = AppModel(store: Store(root: root))
        await model.load()
        await model.save(plan, makeActive: true)
        XCTAssertEqual(model.plans.first?.units, .lb)

        // A plan that named one does not ask, and keeps it whatever the control would say.
        var stated = ImportTrip()
        stated.pasted(result: PlanImport.run(CoreTestSupport.planJSON(), settings: settings, now: now))
        XCTAssertFalse(stated.asksUnits)
        XCTAssertEqual(stated.planToSave(units: .lb)?.units, .kg)
    }

    // The example's outline, and its three days (the plan's Push Pull Legs).
    private let outlineJSON = """
    {
      "schemaVersion": 1, "name": "Push Pull Legs", "units": "kg", "defaultRestSeconds": 90,
      "schedule": "rotation", "cycle": ["Push", "Pull", "Legs", "Push", "Pull", "Legs", "rest"],
      "days": [ { "name": "Push" }, { "name": "Pull" }, { "name": "Legs" } ]
    }
    """
    private let pushDay = #"{ "name": "Push", "exercises": [ { "name": "Barbell Bench Press", "sets": 4, "reps": "6-8", "weight": 80, "restSeconds": 150 } ] }"#
    private let pullDay = #"{ "name": "Pull", "exercises": [ { "name": "Barbell Row", "sets": 3, "reps": "8-10", "weight": 70, "restSeconds": 120 } ] }"#
    private let legsDay = #"[ { "name": "Barbell Back Squat", "sets": 4, "reps": "5", "weight": 100, "restSeconds": 180 } ]"#

    // TN11: a draft of three days — hollow until pasted, the buttons for the first hollow day,
    // a refused day left hollow with its sentence, and Use once none is.
    func testDayByDayOnTheReview() throws {
        let outline = PlanDrafting.outline(outlineJSON, settings: settings, now: now)
        var trip = DraftTrip(draft: try XCTUnwrap(outline.draft), settings: settings, now: now)
        XCTAssertEqual(trip.stage, .ask)
        XCTAssertEqual(trip.hollow, [0, 1, 2])
        XCTAssertEqual(trip.next, 0)
        XCTAssertEqual(trip.buttons, TripButtons(primary: "Send the prompt for Push", secondary: "Copy the prompt for Push"))
        XCTAssertEqual(trip.menu.map(\.title), ["Discard the draft", "Edit the text"])
        XCTAssertEqual(trip.prompt(settings: settings), Prompts.day(outline: try XCTUnwrap(outline.draft).outline, dayIndex: 0, settings: settings))
        XCTAssertEqual(trip.subject, "Push, one day")

        // The review's squares: the cycle, every day hollow, the rest not.
        let preview = try XCTUnwrap(trip.preview)
        let squares = ImportTrip.squares(preview, hollow: trip.hollow)
        XCTAssertEqual(squares.map(\.name), ["Push", "Pull", "Legs", "Push", "Pull", "Legs", "Rest"])
        XCTAssertEqual(squares.map(\.hollow), [true, true, true, true, true, true, false])

        trip.sent()
        XCTAssertEqual(trip.stage, .paste)
        XCTAssertEqual(trip.buttons.primary, "Paste Push")
        var draft = try XCTUnwrap(trip.draft)
        trip.pasted(PlanDrafting.day(pushDay, into: draft, index: 0, settings: settings, now: now), settings: settings, now: now)
        XCTAssertEqual(trip.stage, .ask)
        XCTAssertEqual(trip.hollow, [1, 2])
        XCTAssertEqual(trip.buttons.primary, "Send the prompt for Pull")
        XCTAssertEqual(ImportTrip.squares(try XCTUnwrap(trip.preview), hollow: trip.hollow).map(\.hollow),
                       [false, true, true, false, true, true, false])
        XCTAssertEqual(trip.preview?.days[0].exercises.map(\.name), ["Barbell Bench Press"],
                       "a pasted day shows its exercises on the review")

        // A day the pipeline refuses stays hollow, with the sentence under the strip.
        trip.sent()
        draft = try XCTUnwrap(trip.draft)
        let bad = #"{ "name": "Pull", "exercises": [ { "name": "Row", "sets": 3, "reps": "lots" } ] }"#
        trip.pasted(PlanDrafting.day(bad, into: draft, index: 1, settings: settings, now: now), settings: settings, now: now)
        XCTAssertEqual(trip.stage, .refused)
        XCTAssertEqual(trip.hollow, [1, 2])
        XCTAssertEqual(trip.next, 1)
        XCTAssertFalse(trip.refusal?.sentences.isEmpty ?? true)
        XCTAssertTrue(trip.refusal?.sentences.first?.contains("Day 2") == true, "\(trip.refusal?.sentences ?? [])")
        XCTAssertEqual(trip.buttons.primary, "Send the prompt for Pull")
        // The prompt pasted in a day's place is fixed at Paste.
        trip.pasted(PlanDrafting.day(try FixtureLoader.text("invalid/prompt-pasted.txt"), into: draft, index: 1, settings: settings, now: now),
                    settings: settings, now: now)
        XCTAssertEqual(trip.strip, TripStrip.of(.refused, fix: .paste))

        trip.sent()
        trip.pasted(PlanDrafting.day(pullDay, into: draft, index: 1, settings: settings, now: now), settings: settings, now: now)
        draft = try XCTUnwrap(trip.draft)
        XCTAssertEqual(trip.textPoint(assembled: nil).title, "One day")
        XCTAssertEqual(trip.textPoint(assembled: nil).saveTitle, "Add Legs")
        XCTAssertNotNil(PlanDrafting.day(trip.textPoint(assembled: nil).template, into: draft, index: 2, settings: settings, now: now).draft,
                        "the day's example saves as it stands")
        trip.sent()
        trip.pasted(PlanDrafting.day(legsDay, into: draft, index: 2, settings: settings, now: now), settings: settings, now: now)
        XCTAssertEqual(trip.stage, .review)
        XCTAssertTrue(trip.hollow.isEmpty)
        XCTAssertNil(trip.next)
        XCTAssertEqual(trip.buttons, .effect("Use Push Pull Legs"))
        XCTAssertEqual(trip.strip, TripStrip.of(.review))
        XCTAssertEqual(trip.menu, [.keepWithoutUsing, .discardDraft, .editText])

        // Use runs the assembly, and the plan is the one the review showed.
        let assembled = PlanDrafting.assemble(try XCTUnwrap(trip.draft), settings: settings, now: now)
        let plan = try XCTUnwrap(assembled.plan, "\(assembled.issues)")
        XCTAssertEqual(plan.days.map { $0.exercises.map(\.name) },
                       trip.preview?.days.map { $0.exercises.map(\.name) })
        XCTAssertEqual(trip.textPoint(assembled: assembled.plan?.sourceText).title, "The plan")

        // A draft in progress reopens where it was.
        XCTAssertEqual(DraftTrip(draft: trip.draft, settings: settings).stage, .review)
        XCTAssertEqual(DraftTrip(draft: outline.draft, settings: settings).buttons.primary, "Send the prompt for Push")
    }

    // TN12: Get it day by day starts a draft on the outline prompt; the outline's paste opens
    // the review with every day hollow, or refuses as a plan would.
    func testGetItDayByDay() throws {
        var trip = DraftTrip(draft: nil, settings: settings)
        XCTAssertEqual(trip.stage, .ask)
        XCTAssertEqual(trip.prompt(settings: settings), Prompts.outline(settings: settings))
        XCTAssertEqual(trip.subject, "A plan's outline")
        XCTAssertNil(trip.preview)
        XCTAssertEqual(trip.strip, TripStrip.of(.ask))
        XCTAssertEqual(trip.buttons, TripButtons(primary: "Send the outline prompt", secondary: "Copy the outline prompt"))
        XCTAssertEqual(trip.menu, [.editText])
        XCTAssertEqual(trip.textPoint(assembled: nil).title, "The outline")
        XCTAssertNotNil(PlanDrafting.outline(trip.textPoint(assembled: nil).template, settings: settings, now: now).draft,
                        "the outline's example saves as it stands")

        trip.sent()
        XCTAssertEqual(trip.buttons.primary, "Paste the outline")
        trip.pasted(PlanDrafting.outline(try FixtureLoader.text("invalid/prompt-pasted.txt"), settings: settings, now: now),
                    settings: settings, now: now)
        XCTAssertEqual(trip.stage, .refused)
        XCTAssertEqual(trip.refusal?.fix, .paste)
        XCTAssertNil(trip.draft)
        XCTAssertEqual(trip.buttons.primary, "Send the outline prompt")

        trip.sent()
        trip.pasted(PlanDrafting.outline(outlineJSON, settings: settings, now: now), settings: settings, now: now)
        XCTAssertEqual(trip.stage, .ask)
        XCTAssertEqual(trip.hollow, [0, 1, 2])
        XCTAssertEqual(trip.buttons.primary, "Send the prompt for Push")

        // A chatbot that wrote the whole plan anyway: nothing hollow, straight to Use.
        var whole = DraftTrip(draft: nil, settings: settings)
        whole.pasted(PlanDrafting.outline(CoreTestSupport.planJSON(), settings: settings, now: now), settings: settings, now: now)
        XCTAssertEqual(whole.stage, .review)
        XCTAssertEqual(whole.buttons.primary, "Use Training")

        // The refusal that offers it is the cut-short one, and only that one.
        let cut = TripRefusal.of(try imported("invalid/truncated.txt").errors, way: .wholePlanOrDayByDay)
        XCTAssertTrue(cut.offersDayByDay)
        for fixture in ["invalid/not-json-at-all.txt", "invalid/no-days.json", "invalid/prompt-pasted.txt", "invalid/empty.txt"] {
            XCTAssertFalse(TripRefusal.of(try imported(fixture).errors, way: .wholePlanOrDayByDay).offersDayByDay, fixture)
        }
    }

    // TN13 (pin): Add plan's footers, Show text, Import file row and Build it day by day row are
    // gone from the source — and no title or placeholder says JSON.
    func testAddPlanLostItsInstructionManual() throws {
        guard let source = FixtureLoader.doc("JimmsBro/Features/Import/ImportView.swift") else {
            throw XCTSkip("ImportView.swift is outside the simulator's sandbox; this pin runs on the host routes")
        }
        for gone in ["footer:", "Show text", "Import file", "Build it day by day", "Copy prompt\"", "\"Copied\"",
                     "Toggle(", "Review plan\"", "Save plan\""] {
            XCTAssertFalse(source.contains(gone), "ImportView still shows \(gone)")
        }
        let titled = source.split(separator: "\n").filter { $0.contains("navigationTitle(") || $0.contains("Text(\"") }
        XCTAssertFalse(titled.contains { $0.contains("JSON") }, "a title or placeholder names JSON")
        if let row = FixtureLoader.doc("JimmsBro/Features/Import/BuiltInPlansView.swift") {
            XCTAssertFalse(row.contains("footer:"), "the picker's footer went with the picker")
        }
    }

    // TN14 (ui, with a unit half): the built-ins row is D46's four, in order, each drawn by its
    // own cycle — the squares the review draws for the same plan.
    @MainActor func testTheBuiltInsRow() async throws {
        XCTAssertEqual(BuiltInPlans.all.count, 4)
        let root = CoreTestSupport.makeRoot("RoundTripBuiltIns")
        defer { CoreTestSupport.discard(root) }
        let model = AppModel(store: Store(root: root), scheduler: RecordingAlerts(), alerts: RecordingAlerts(),
                             bundledPlanJSON: { id in try? FixtureLoader.appResource(id, extension: "json") })
        await model.load()
        for entry in BuiltInPlans.all {
            let plan = try XCTUnwrap(model.loadBuiltInPlan(entry.id, now: now).plan, entry.id)
            let squares = ImportTrip.squares(plan)
            XCTAssertEqual(squares.map(\.colour), DayColour.cycle(of: plan), entry.id)
            XCTAssertFalse(squares.contains { $0.hollow }, entry.id)
            var trip = ImportTrip()
            trip.builtIn(plan, about: entry.about)
            XCTAssertEqual(trip.buttons.primary, "Use \(plan.name)")
            XCTAssertEqual(trip.about, entry.about)
        }
    }
}

import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// TN32–TN36 (v1.11, N5): **Say what should change** (D94, SPEC §6.67) — what a change did to a
/// plan, the screen's trip, and Apply as an edit that keeps the progression. The example is the
/// plan's: Push Pull Legs, and a reply that swaps Barbell Bench Press for Dumbbell Bench Press
/// 4 × 6–8 at 32 kg and drops Hammer Curl.
final class PlanDiffTests: XCTestCase {
    private let now = CoreTestSupport.now
    private let settings = Settings()
    private let request = "Swap the barbell bench press for dumbbells. Pull is too long, drop one exercise."

    private struct Ex {
        var name: String
        var sets = 3
        var reps = "8-12"
        var weight: Double? = nil
        var rest = 90
        var notes: String? = nil
        var group: String? = nil

        var json: String {
            var fields = [#""name": "\#(name)""#, #""sets": \#(sets)"#, #""reps": "\#(reps)""#, #""restSeconds": \#(rest)"#]
            if let weight { fields.append(#""weight": \#(TargetText.number(weight))"#) }
            if let notes { fields.append(#""notes": "\#(notes)""#) }
            if let group { fields.append(#""group": "\#(group)""#) }
            return "{ " + fields.joined(separator: ", ") + " }"
        }
    }

    private var push: [Ex] {
        [Ex(name: "Barbell Bench Press", sets: 4, reps: "6-8", weight: 80),
         Ex(name: "Overhead Press", reps: "8-10", weight: 40),
         Ex(name: "Incline Dumbbell Press", weight: 26),
         Ex(name: "Lateral Raise", reps: "12-15", weight: 10),
         Ex(name: "Tricep Pushdown", reps: "10-12", weight: 30),
         Ex(name: "Overhead Tricep Extension", reps: "10-12", weight: 20)]
    }
    private var pull: [Ex] {
        [Ex(name: "Barbell Row", sets: 4, reps: "6-8", weight: 70),
         Ex(name: "Lat Pulldown", weight: 55),
         Ex(name: "Face Pull", reps: "12-15", weight: 20),
         Ex(name: "Hammer Curl", reps: "10-12", weight: 14)]
    }
    private var legs: [Ex] {
        [Ex(name: "Back Squat", sets: 4, reps: "5-8", weight: 100),
         Ex(name: "Romanian Deadlift", weight: 80)]
    }

    private func text(name: String = "Push Pull Legs", units: String? = "kg",
                      cycle: [String] = ["Push", "Pull", "Legs", "Push", "Pull", "Legs", "rest"],
                      days: [(String, [Ex])]) -> String {
        let dayJSON = days.map { day in
            #"{ "name": "\#(day.0)", "exercises": [\#(day.1.map(\.json).joined(separator: ", "))] }"#
        }
        var fields = [#""name": "\#(name)""#, #""schedule": "rotation""#,
                      #""cycle": [\#(cycle.map { "\"\($0)\"" }.joined(separator: ", "))]"#,
                      #""days": [\#(dayJSON.joined(separator: ", "))]"#]
        if let units { fields.insert(#""units": "\#(units)""#, at: 1) }
        return "{ " + fields.joined(separator: ", ") + " }"
    }

    private func imported(_ text: String, file: StaticString = #filePath, line: UInt = #line) throws -> Plan {
        let result = PlanImport.run(text, settings: settings, now: now)
        return try XCTUnwrap(result.plan, "\(result.issues)", file: file, line: line)
    }

    private var example: String { text(days: [("Push", push), ("Pull", pull), ("Legs", legs)]) }

    /// The chatbot's reply to the example request.
    private var reply: String {
        var push = self.push
        push[0] = Ex(name: "Dumbbell Bench Press", sets: 4, reps: "6-8", weight: 32)
        return text(days: [("Push", push), ("Pull", Array(pull.dropLast())), ("Legs", legs)])
    }

    // TN32: what a change did to a plan.
    func testTheDiffOfTheExample() throws {
        let old = try imported(example)
        let diff = PlanDiff.between(old: old, new: try imported(reply))
        XCTAssertEqual(diff.count, 2)
        XCTAssertEqual(diff.lines.count, 3)
        guard case let .replaced(day, oldName, new) = diff.lines[0] else { return XCTFail("\(diff.lines[0])") }
        XCTAssertEqual(day, "Push")
        XCTAssertEqual(oldName, "Barbell Bench Press")
        XCTAssertEqual(new.name, "Dumbbell Bench Press")
        XCTAssertEqual(diff.lines[1], .removed(day: "Pull", name: "Hammer Curl"))
        XCTAssertEqual(diff.lines[2], .dayUnchanged("Legs"))
        XCTAssertEqual(diff.groups.map(\.day), ["Push", "Pull", "Legs"])
        XCTAssertEqual(diff.groups.map(\.dayIndex), [0, 1, 2], "each day's square is its colour in the plan")

        // The rows: the old name struck above the new, with the new targets; a removed one struck.
        XCTAssertEqual(diff.row(diff.lines[0]),
                       PlanDiff.Row(mark: .replaced, struck: "Barbell Bench Press", name: "Dumbbell Bench Press",
                                    detail: "4 sets of 6–8 reps · 32 kg"))
        XCTAssertEqual(diff.row(diff.lines[1]), PlanDiff.Row(mark: .removed, struck: "Hammer Curl", name: nil, detail: "removed"))
        XCTAssertEqual(diff.row(diff.lines[2]).mark, .unchanged)

        // The same plan twice — imported twice, so every id differs — is every day unchanged.
        let same = PlanDiff.between(old: old, new: try imported(example))
        XCTAssertEqual(same.lines, [.dayUnchanged("Push"), .dayUnchanged("Pull"), .dayUnchanged("Legs")])
        XCTAssertEqual(same.count, 0)

        // A day renamed is a day removed and a day added, the removed one where it stood; the
        // cycle's own line stays out, since the days' lines already say it.
        let renamed = PlanDiff.between(old: old, new: try imported(text(
            cycle: ["Push", "Pull", "Lower", "Push", "Pull", "Lower", "rest"],
            days: [("Push", push), ("Pull", pull), ("Lower", legs)])))
        XCTAssertEqual(renamed.count, 2)
        XCTAssertEqual(renamed.lines.count, 4)
        XCTAssertEqual(renamed.lines[2], .dayRemoved("Legs"))
        guard case let .dayAdded(lower) = renamed.lines[3] else { return XCTFail("\(renamed.lines)") }
        XCTAssertEqual(lower.name, "Lower")
        XCTAssertEqual(renamed.groups.map(\.dayIndex), [0, 1, 2, 2])

        // An exercise moved within its day is two lines, not none — the plan's choice (a moved
        // line is parked).
        var moved = push
        moved.swapAt(2, 3)
        let move = PlanDiff.between(old: old, new: try imported(text(days: [("Push", moved), ("Pull", pull), ("Legs", legs)])))
        XCTAssertEqual(move.count, 2)
        let pushLines = move.lines.filter { if case .dayUnchanged = $0 { return false }; return true }
        XCTAssertEqual(pushLines.count, 2)
        XCTAssertTrue(pushLines.contains { if case .removed("Push", _) = $0 { return true }; return false })
        XCTAssertTrue(pushLines.contains { if case .added("Push", _) = $0 { return true }; return false })

        // A day in reverse is removed and added, never "replaced" by a name still in the day.
        let reversed = PlanDiff.between(old: old, new: try imported(text(days: [("Push", push), ("Pull", Array(pull.reversed())), ("Legs", legs)])))
        XCTAssertFalse(reversed.lines.contains { if case .replaced = $0 { return true }; return false })
        XCTAssertGreaterThan(reversed.count, 0)

        // The same name with other targets is changed, both sides said; a change the summary does
        // not say still reads differently on either side of the arrow.
        var heavier = push
        heavier[1].weight = 42.5
        heavier[5].rest = 120
        let changed = PlanDiff.between(old: old, new: try imported(text(days: [("Push", heavier), ("Pull", pull), ("Legs", legs)])))
        XCTAssertEqual(changed.count, 2)
        XCTAssertEqual(changed.lines[0], .changed(day: "Push", name: "Overhead Press",
                                                 from: "3 sets of 8–10 reps · 40 kg", to: "3 sets of 8–10 reps · 42.5 kg"))
        guard case let .changed(_, name, from, to) = changed.lines[1] else { return XCTFail("\(changed.lines)") }
        XCTAssertEqual(name, "Overhead Tricep Extension")
        XCTAssertTrue(from.hasSuffix("rest 1:30"), from)
        XCTAssertTrue(to.hasSuffix("rest 2:00"), to)
        XCTAssertEqual(changed.row(changed.lines[0]).detail, "3 sets of 8–10 reps · 40 kg → 3 sets of 8–10 reps · 42.5 kg")

        // A superset whose partner is removed is one line, the removal: the group's round rest is
        // the importer's to work out, not a change the reply wrote. A pairing the reply did write
        // says who with.
        var paired = pull
        paired[2].group = "B"
        paired[3].group = "B"
        let supersetPlan = try imported(text(days: [("Push", push), ("Pull", paired), ("Legs", legs)]))
        let partnerGone = PlanDiff.between(old: supersetPlan, new: try imported(text(days: [("Push", push), ("Pull", Array(paired.dropLast())), ("Legs", legs)])))
        XCTAssertEqual(partnerGone.count, 1, "\(partnerGone.lines)")
        XCTAssertEqual(partnerGone.lines[1], .removed(day: "Pull", name: "Hammer Curl"))
        var repaired = paired
        repaired[1].group = "B"
        let joined = PlanDiff.between(old: supersetPlan, new: try imported(text(days: [("Push", push), ("Pull", repaired), ("Legs", legs)])))
        guard case let .changed("Pull", "Lat Pulldown", _, to) = joined.lines.first(where: { if case .changed = $0 { return true }; return false }) else {
            return XCTFail("\(joined.lines)")
        }
        XCTAssertTrue(to.hasSuffix("paired with Face Pull and Hammer Curl"), to)

        // An exercise added, and one replaced beside a removal, pair by position between matches.
        var added = pull
        added.insert(Ex(name: "Chin-Up", reps: "6-10"), at: 2)
        let addition = PlanDiff.between(old: old, new: try imported(text(days: [("Push", push), ("Pull", added), ("Legs", legs)])))
        XCTAssertEqual(addition.count, 1)
        guard case let .added("Pull", chin) = addition.lines[1] else { return XCTFail("\(addition.lines)") }
        XCTAssertEqual(chin.name, "Chin-Up")
        XCTAssertEqual(addition.row(addition.lines[1]).detail, "added · 3 sets of 6–10 reps")

        // The plan's own fields are lines, so a reply that only moved the rest day is not
        // Nothing changed.
        let cycle = PlanDiff.between(old: old, new: try imported(text(
            cycle: ["Push", "Pull", "rest", "Legs", "Push", "Pull", "Legs"],
            days: [("Push", push), ("Pull", pull), ("Legs", legs)])))
        XCTAssertEqual(cycle.count, 1)
        XCTAssertEqual(cycle.groups.first?.day, nil)
        XCTAssertEqual(cycle.lines.first, .plan(.schedule, from: "Push · Pull · Legs · Push · Pull · Legs · rest",
                                                to: "Push · Pull · rest · Legs · Push · Pull · Legs"))
        let renamedPlan = PlanDiff.between(old: old, new: try imported(text(name: "PPL", days: [("Push", push), ("Pull", pull), ("Legs", legs)])))
        XCTAssertEqual(renamedPlan.lines.first, .plan(.name, from: "Push Pull Legs", to: "PPL"))
        XCTAssertEqual(renamedPlan.count, 1)
    }

    // TN33: the screen's trip — typed, sent, pasted, and the three ways a reply comes back.
    func testTheChangeRequestsTransitions() throws {
        let plan = try imported(example)
        var screen = ChangeRequest(plan: plan)
        XCTAssertEqual(screen.stage, .ask)
        XCTAssertFalse(screen.canSend, "Send waits for something typed")
        XCTAssertEqual(screen.buttons, .ask())
        screen.sent()
        XCTAssertEqual(screen.stage, .ask, "nothing to send")
        screen.say("   ")
        XCTAssertFalse(screen.canSend)

        // Typed → Ask; sent → Paste.
        screen.say(request)
        XCTAssertTrue(screen.canSend)
        XCTAssertEqual(screen.strip, .of(.ask))
        XCTAssertEqual(screen.prompt(settings: settings), Prompts.change(plan: plan, request: request, settings: settings))
        XCTAssertEqual(screen.subject, "Change Push Pull Legs")
        screen.sent()
        XCTAssertEqual(screen.stage, .paste)
        XCTAssertEqual(screen.strip, .of(.paste))
        XCTAssertEqual(screen.buttons, .paste)

        // A plan pasted → Review, with what changed.
        screen.pasted(result: PlanImport.run(reply, settings: settings, now: now))
        XCTAssertEqual(screen.stage, .review)
        XCTAssertEqual(screen.strip, .of(.review))
        XCTAssertEqual(screen.diff?.count, 2)
        XCTAssertEqual(screen.reply?.days[0].exercises[0].name, "Dumbbell Bench Press")
        XCTAssertFalse(screen.isNothingChanged)
        XCTAssertNil(screen.sentence)
        XCTAssertEqual(screen.textPoint().template, screen.reply?.sourceText, "Edit the text opens on the reply")
        XCTAssertEqual(screen.heading, "2 changes")
        XCTAssertEqual(screen.diff.map { $0.row($0.lines[0]).spoken },
                       "Barbell Bench Press, replaced by Dumbbell Bench Press, 4 sets of 6–8 reps · 32 kg")

        // The ···'s Send the prompt again: back to Ask with the request kept.
        var again = screen
        again.restart()
        XCTAssertEqual(again.stage, .ask)
        XCTAssertEqual(again.request, request)
        XCTAssertNil(again.diff)
        XCTAssertEqual(again.heading, "Say what should change")

        // Saying it differently is a different prompt: back to Ask.
        screen.say(request + " And add a rest day.")
        XCTAssertEqual(screen.stage, .ask)
        XCTAssertNil(screen.diff)
        XCTAssertNil(screen.reply)
        XCTAssertEqual(screen.textPoint().template, PlanJSON.render(plan), "before a reply, the plan as it stands")

        // The same plan → Nothing changed: no button, the strip lit at Chat, the sentence.
        screen.sent()
        screen.pasted(result: PlanImport.run(example, settings: settings, now: now))
        XCTAssertEqual(screen.stage, .review)
        XCTAssertTrue(screen.isNothingChanged)
        XCTAssertNil(screen.buttons)
        XCTAssertEqual(screen.fixAt, 1)
        XCTAssertEqual(screen.strip, .of(.refused, fixAt: 1))
        XCTAssertEqual(screen.title, "Nothing changed")
        XCTAssertEqual(screen.sentence, "The reply is the plan as it was. Say it differently, or ask the chatbot again.")

        // Not a plan → Refused at Chat, with Ask for the whole plan and the fix-it prompt.
        screen.sent()
        XCTAssertEqual(screen.stage, .paste)
        let words = PlanImport.run("Sure! I swapped the bench press and dropped the curls.", settings: settings, now: now)
        screen.pasted(result: words)
        XCTAssertEqual(screen.stage, .refused)
        XCTAssertEqual(screen.fixAt, 1)
        XCTAssertEqual(screen.strip, .of(.refused, fixAt: 1))
        XCTAssertEqual(screen.buttons, TripButtons(primary: "Ask for the whole plan", secondary: "Copy the prompt"))
        XCTAssertEqual(screen.sentence, IssueText.friendly(try XCTUnwrap(words.errors.first)))
        XCTAssertEqual(screen.prompt(settings: settings), Prompts.render(errors: words.errors))
        XCTAssertNil(screen.diff)

        // Cut short → Refused the same way.
        screen.sent()
        screen.pasted(result: PlanImport.run(String(reply.prefix(reply.count / 2)), settings: settings, now: now))
        XCTAssertEqual(screen.stage, .refused)
        XCTAssertEqual(screen.buttons, ChangeRequest.askAgain)

        // The prompt pasted back → Refused at Paste, with Send the prompt again.
        screen.sent()
        screen.pasted(result: PlanImport.run(screen.prompt(settings: settings), settings: settings, now: now))
        XCTAssertEqual(screen.stage, .refused)
        XCTAssertEqual(screen.refusal.first?.code, "E_PROMPT_PASTED")
        XCTAssertEqual(screen.fixAt, 2)
        XCTAssertEqual(screen.strip.marks, [.done, .done, .now])
        XCTAssertEqual(screen.buttons, .ask())
        XCTAssertEqual(screen.prompt(settings: settings), Prompts.change(plan: plan, request: screen.request, settings: settings))
        screen.sent()
        XCTAssertEqual(screen.stage, .paste)

        // A reply that dropped its unit keeps the plan's, rather than a change of unit nobody asked for.
        let pounds = try imported(text(units: "lb", days: [("Push", push), ("Pull", pull), ("Legs", legs)]))
        var lb = ChangeRequest(plan: pounds)
        lb.say(request)
        lb.sent()
        lb.pasted(result: PlanImport.run(text(units: nil, days: [("Push", push), ("Pull", pull), ("Legs", legs)]),
                                         settings: settings, now: now))
        XCTAssertEqual(lb.reply?.units, .lb)
        XCTAssertTrue(lb.isNothingChanged)

        // Edit the text: the whole plan, a Save that says its effect, the word JSON nowhere.
        let point = ChangeRequest(plan: plan).textPoint()
        XCTAssertEqual(point.title, "The plan")
        XCTAssertEqual(point.saveTitle, "See what changed")
        XCTAssertFalse((point.title + point.place + point.saveTitle + point.footer).contains("JSON"))
        // Its marks read the whole plan's paths at their own lines.
        let broken = example.replacingOccurrences(of: #""sets": 4, "reps": "5-8""#, with: #""sets": "four", "reps": "5-8""#)
        let refusal = PlanImport.run(broken, settings: settings, now: now)
        XCTAssertNil(refusal.plan)
        let marks = point.marks(for: refusal.errors, in: broken)
        XCTAssertFalse(marks.marked.isEmpty, "\(refusal.errors)")

        // The words of the door and the field (TN37's, in Core).
        XCTAssertEqual(ChangeRequest.menuItem, "Say what should change")
        XCTAssertEqual(ChangeRequest.placeholder, "What should change?")
    }

    // TN34: the review's title and its button, by count.
    func testTheReviewsTitleAndButtonByCount() throws {
        XCTAssertEqual(ChangeRequest.title(count: 0), "Nothing changed")
        XCTAssertEqual(ChangeRequest.title(count: 1), "1 change")
        XCTAssertEqual(ChangeRequest.title(count: 2), "2 changes")
        XCTAssertEqual(ChangeRequest.apply(count: 1), "Apply 1 change")
        XCTAssertEqual(ChangeRequest.apply(count: 2), "Apply 2 changes")

        var screen = ChangeRequest(plan: try imported(example))
        screen.say("Drop the hammer curls.")
        screen.sent()
        screen.pasted(result: PlanImport.run(text(days: [("Push", push), ("Pull", Array(pull.dropLast())), ("Legs", legs)]),
                                             settings: settings, now: now))
        XCTAssertEqual(screen.title, "1 change")
        XCTAssertEqual(screen.buttons, .effect("Apply 1 change"))

        screen.say(request)
        screen.sent()
        screen.pasted(result: PlanImport.run(reply, settings: settings, now: now))
        XCTAssertEqual(screen.title, "2 changes")
        XCTAssertEqual(screen.buttons, TripButtons(primary: "Apply 2 changes", secondary: nil))
    }

    // TN35: Apply is an edit, not a Replace — the id, the import date, the cycle's place and
    // anchor, and the progression stay; the renamed exercise's entry stops matching.
    @MainActor func testApplyKeepsThePlanAndItsProgression() async throws {
        let root = CoreTestSupport.makeRoot("ApplyChange")
        defer { CoreTestSupport.discard(root) }
        let model = AppModel(store: Store(root: root), scheduler: RecordingAlerts(), alerts: RecordingAlerts())
        await model.load()

        var plan = try imported(example)
        plan.progression = Progression(startDate: now, weeks: 6, entries: [
            ProgressionEntry(dayName: "Push", exerciseName: "Barbell Bench Press",
                             weeks: [ProgressionWeek(weight: 82.5), ProgressionWeek(weight: 85)]),
            ProgressionEntry(dayName: "Push", exerciseName: "Overhead Press",
                             weeks: [ProgressionWeek(weight: 42.5)]),
        ], mode: .performance)
        let saved = await model.save(plan, makeActive: true)
        let id = try XCTUnwrap(saved)
        let anchor = now.addingTimeInterval(-86_400)
        model.library.plans[0].cyclePosition = 3
        model.library.plans[0].cycleAnchor = anchor
        let before = model.library.plans[0]

        var screen = ChangeRequest(plan: before)
        screen.say(request)
        screen.sent()
        screen.pasted(result: model.runImport(reply, now: now.addingTimeInterval(3_600)))
        let replied = try XCTUnwrap(screen.reply)
        XCTAssertNotEqual(replied.id, id)

        let applied = await model.applyChange(planId: id, plan: replied)
        XCTAssertTrue(applied)
        let after = try XCTUnwrap(model.plans.first { $0.id == id })
        XCTAssertEqual(model.plans.count, 1)
        XCTAssertEqual(model.library.activePlanId, id)
        XCTAssertEqual(after.importedAt, before.importedAt)
        XCTAssertEqual(after.cyclePosition, 3, "the second Push is still the second Push")
        XCTAssertEqual(after.cycleAnchor, anchor)
        XCTAssertEqual(after.progression, before.progression, "Apply keeps the progression, as every edit does")
        XCTAssertEqual(after.sourceText, PlanJSON.render(after), "the text is the canonical rendering")
        XCTAssertEqual(after.days[0].exercises.map(\.name).first, "Dumbbell Bench Press")
        XCTAssertFalse(after.days[1].exercises.contains { $0.name == "Hammer Curl" })

        // Entries match by name: Overhead Press still does, the renamed bench press no longer does.
        let progression = try XCTUnwrap(after.progression)
        let touched = progression.apply(to: after.days[0], week: 0).touched
        XCTAssertEqual(touched, [1])
        XCTAssertNotNil(progression.entry(day: "Push", exercise: "Barbell Bench Press"))
        XCTAssertFalse(after.days[0].exercises.contains { normalized($0.name) == normalized("Barbell Bench Press") })

        // On disk too.
        let reloaded = AppModel(store: Store(root: root), scheduler: RecordingAlerts(), alerts: RecordingAlerts())
        await reloaded.load()
        XCTAssertEqual(reloaded.plans.first { $0.id == id }, after)

        // Whereas the whole-plan replace of Edit the text still drops it (D43).
        var library = model.library
        library.replace(id, with: replied)
        XCTAssertNil(library.plans[0].progression)

        // A plan that has gone is not applied to.
        let missing = await model.applyChange(planId: UUID(), plan: replied)
        XCTAssertFalse(missing)

        // Where the cycle moved under the place, the place follows its day by name.
        var shifted = try imported(text(cycle: ["Legs", "Push", "Pull", "rest"], days: [("Push", push), ("Pull", pull), ("Legs", legs)]))
        shifted = ChangeRequest.applied(shifted, to: before)
        XCTAssertEqual(shifted.cyclePosition, 1, "Push, wherever it now stands")
        XCTAssertEqual(shifted.cycleAnchor, anchor)
    }

    // TN36 (pin): PROMPT.md §7's marker and first sentence are what the screen sends.
    func testTheChangePromptOpensAsPublished() throws {
        guard let document = FixtureLoader.doc("docs/PROMPT.md") else {
            throw XCTSkip("docs/PROMPT.md is outside the simulator's sandbox; "
                          + "this pin runs under `swift test` and `tools/check_core.py`")
        }
        let section = try XCTUnwrap(document.components(separatedBy: "## 7. Change prompt").dropFirst().first)
        let block = try XCTUnwrap(section.components(separatedBy: "```").dropFirst().first)
        let lines = block.split(separator: "\n", omittingEmptySubsequences: true).prefix(2).map(String.init)
        XCTAssertEqual(lines.first, "JIMMSBRO-CHANGE-PROMPT-V1")
        XCTAssertEqual(lines.first, PlanImport.changePromptMarker)
        XCTAssertTrue(lines.last?.hasPrefix("Change the plan below as I ask") == true)

        var screen = ChangeRequest(plan: try imported(example))
        screen.say(request)
        let sent = screen.prompt(settings: settings)
        XCTAssertTrue(sent.hasPrefix(lines.joined(separator: "\n") + "\n"), String(sent.prefix(300)))
        XCTAssertTrue(sent.contains("WHAT TO CHANGE\n" + request))
    }
}

import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// Y3 (v1.4) — D47: the introduction, when it is due, and what it is allowed to claim.
final class IntroductionTests: XCTestCase {
    private let now = CoreTestSupport.now

    // Y12: four pages, each with a symbol, a line and a paragraph; and every control the copy
    // is allowed to name is actually named somewhere in it.
    func testTheFourPages() {
        XCTAssertEqual(Introduction.pages.count, 4)
        for page in Introduction.pages {
            XCTAssertFalse(page.symbol.isEmpty)
            XCTAssertFalse(page.title.isEmpty)
            XCTAssertGreaterThan(page.body.count, 80, page.title)
            XCTAssertLessThan(page.body.count, 400, "\(page.title): a page is one paragraph")
        }
        XCTAssertEqual(Introduction.pages.map(\.title),
                       ["A plan, then Start", "Log the set, rest, repeat", "It remembers", "Your plan, your way"])
        let text = Introduction.pages.map { $0.title + " " + $0.body }.joined(separator: " ")
        for control in Introduction.namedControls {
            XCTAssertTrue(text.contains(control), "the intro no longer mentions \(control)")
        }
        XCTAssertEqual(Introduction.choosePlan, "Choose a plan")
        XCTAssertEqual(Introduction.notNow, "Not now")
        XCTAssertEqual(Introduction.done, "Done")
    }

    // Y13: the controls the intro names exist by those names. The ones Core owns are checked
    // against Core; the ones that are view literals are read from the views' own source, on
    // the routes that can see the checkout.
    @MainActor func testEveryControlTheIntroNamesExists() throws {
        // "Choose a plan" and "Start …" are the empty and the ready card's buttons (D61, v1.7:
        // the empty card says what the intro's button says); "Add plan" is the Plans list's.
        var library = PlanLibrary()
        XCTAssertEqual(HomeStart.current(library: library, now: now).buttonTitle, Introduction.choosePlan)
        library.save(CoreTestSupport.plan(), makeActive: true)
        XCTAssertEqual(HomeStart.current(library: library, now: now).buttonTitle, "Start Today's Push")
        // "Log set" is the workout's primary action on a set of reps.
        let engine = CoreTestSupport.engine()
        let screen = try XCTUnwrap(WorkoutScreen.model(active: engine.active, history: [], now: now,
                                                       settings: CoreTestSupport.classic))
        XCTAssertEqual(screen.primary.title, "Log set")
        // "History" is a tab's title, which is Core's since v1.7 (D62): `RootView` draws
        // `AppTab.allCases` (T7). T8 is this test, re-run for T2.
        XCTAssertEqual(AppTab.history.title, "History")
        XCTAssertTrue(AppTab.allCases.contains(.history))
        XCTAssertTrue(Introduction.namedControls.contains(AppTab.history.title))
        // "Send the prompt" is Core's (D88, v1.11), and a "built-in plan" is one of Core's four —
        // the screens that draw them are rewritten in v1.11's tracks, so the pin is the data.
        XCTAssertEqual(TripButtons.ask().primary, "Send the prompt")
        XCTAssertTrue(Introduction.namedControls.contains(TripButtons.ask().primary))
        XCTAssertEqual(BuiltInPlans.all.count, 4)

        let literals: [(control: String, file: String, literal: String)] = [
            // D88 (v1.11): every chatbot screen's primary button is Core's, drawn by one view.
            ("Send the prompt", "JimmsBro/Features/Shared/PromptButtons.swift", "buttons.primary"),
            // D67 (v1.7): History's row since the owner's review.
            ("Progression", "JimmsBro/Features/History/HistoryView.swift", "Text(\"Progression\")"),
            // D78 (v1.9): at the list's top right, since the bottom slot is the circle's Use.
            ("Add plan", "JimmsBro/Features/Plans/PlansView.swift", "Button(\"Add plan\") { addPlan = .plan }"),
        ]
        for pin in literals {
            guard let source = FixtureLoader.doc(pin.file) else {
                throw XCTSkip("\(pin.file) is outside the simulator's sandbox; this pin runs on the host routes")
            }
            XCTAssertTrue(source.contains(pin.literal), "\(pin.file) no longer has \(pin.literal)")
            XCTAssertTrue(Introduction.namedControls.contains(pin.control))
        }
    }

    // Y14: when the intro is due — no plans and not dismissed — through the model, on disk,
    // and back again after Delete all data.
    @MainActor func testWhenTheIntroIsDue() async throws {
        XCTAssertTrue(Introduction.isDue(plans: [], settings: Settings()))
        XCTAssertFalse(Introduction.isDue(plans: [CoreTestSupport.plan()], settings: Settings()))
        XCTAssertFalse(Introduction.isDue(plans: [], settings: Settings(introSeen: true)))

        let root = CoreTestSupport.makeRoot("Intro")
        defer { CoreTestSupport.discard(root) }
        let model = AppModel(store: Store(root: root))
        XCTAssertFalse(model.introDue, "not before the store has been read")
        await model.load()
        XCTAssertTrue(model.introDue, "a first launch")

        await model.markIntroSeen()
        XCTAssertFalse(model.introDue)
        XCTAssertTrue(model.settings.introSeen)
        XCTAssertNil(model.saveFailure)

        // Dismissed is remembered across launches.
        let relaunched = AppModel(store: Store(root: root))
        await relaunched.load()
        XCTAssertFalse(relaunched.introDue)
        XCTAssertTrue(relaunched.settings.introSeen)

        // A phone with plans never sees it uninvited, dismissed or not.
        let withPlans = AppModel(store: Store(root: CoreTestSupport.makeRoot("IntroPlans")))
        await withPlans.load()
        await withPlans.save(CoreTestSupport.plan(), makeActive: true)
        XCTAssertFalse(withPlans.introDue)
        XCTAssertFalse(withPlans.settings.introSeen, "it was never shown, and never will be")

        // Delete all data is a first launch by choice.
        await relaunched.deleteAllData()
        XCTAssertTrue(relaunched.introDue)
    }

    // Y15: `introSeen` on disk — written, read back, absent from an older file.
    func testIntroSeenOnDisk() throws {
        var settings = Settings()
        settings.introSeen = true
        let data = try StoreCoder.encode(settings)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"introSeen\" : true"))
        XCTAssertEqual(try StoreCoder.decode(Settings.self, from: data), settings)

        // The frozen v1.1 file predates the flag: it decodes, and the intro is not marked seen.
        let frozen = try StoreCoder.decode(Settings.self, from: try FixtureLoader.data("store/v1/settings.json"))
        XCTAssertFalse(frozen.introSeen)
        XCTAssertEqual(frozen.defaultRestSeconds, 90, "and everything it held is still there")

        // A file that says so, says so.
        let seen = Data(#"{ "fileVersion": 1, "units": "kg", "introSeen": true }"#.utf8)
        XCTAssertTrue(try StoreCoder.decode(Settings.self, from: seen).introSeen)
    }
}

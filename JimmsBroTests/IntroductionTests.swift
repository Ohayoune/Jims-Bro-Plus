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
        // "Add plan" and "Start …" are the empty and the ready card's buttons.
        var library = PlanLibrary()
        XCTAssertEqual(HomeStart.current(library: library, now: now).buttonTitle, "Add plan")
        library.save(CoreTestSupport.plan(), makeActive: true)
        XCTAssertEqual(HomeStart.current(library: library, now: now).buttonTitle, "Start Push")
        // "Log set" is the workout's primary action on a set of reps.
        let engine = CoreTestSupport.engine()
        let screen = try XCTUnwrap(WorkoutScreen.model(active: engine.active, history: [], now: now,
                                                       settings: CoreTestSupport.classic))
        XCTAssertEqual(screen.primary.title, "Log set")

        let literals: [(control: String, file: String, literal: String)] = [
            ("Create with a chatbot", "JimmsBro/Features/Import/ImportView.swift", "Text(\"Create with a chatbot\")"),
            ("History", "JimmsBro/RootView.swift", "Label(\"History\""),
            ("Progression", "JimmsBro/Features/PlanDetail/PlanDetailView.swift", "Text(\"Progression\")"),
            ("built-in plan", "JimmsBro/Features/Import/ImportView.swift", "Label(\"Choose a built-in plan\""),
            ("built-in plan", "JimmsBro/Features/Home/HomeView.swift", "Button(\"Choose a built-in plan\")"),
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

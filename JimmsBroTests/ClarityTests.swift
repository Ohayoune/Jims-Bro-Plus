import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// Z1 (v1.5) — D50: clearer, not louder. The sentences that explain the chatbot round-trip,
/// and the views pinned to them. (Z2, the rule for Home's quiet link, went with the link in
/// v1.9: D75 took Plan a progression off Today, and TQ22 holds its absence.)
final class ClarityTests: XCTestCase {
    // Z1: the sentence says what it must — three until v1.11, when D87 took the numbered step and
    // the mechanism off the chatbot screens (the mechanism is the introduction's now, TN5), and
    // four until v1.9, when the link's name went with the link (D75).
    func testTheSentences() {
        XCTAssertFalse(PromptText.progressionRow.trimmed.isEmpty)
        XCTAssertTrue(PromptText.progressionRow.contains("chatbot") && PromptText.progressionRow.contains("lifted"))
    }

    // Z3: the views show the Core sentences, not copies of them. (Until v1.11 Add plan and
    // Progression were pinned to `copyStep` and `mechanism` too; D87 takes both sentences off
    // those screens and puts the mechanism on the introduction's first page, TN5.)
    func testTheViewsShowTheCoreSentences() throws {
        let pins: [(file: String, literal: String)] = [
            // D67 (v1.7): the Progression row is History's since the owner's review.
            ("JimmsBro/Features/History/HistoryView.swift", "PromptText.progressionRow"),
            // D61 (v1.7): Today's ··· takes its titles from Core, `HomeStart.Alternative.title`.
            // (Until v1.9 one of them was PromptText's Plan a progression; D75 took it off Today.)
            ("JimmsBro/Features/Home/HomeView.swift", "alternative.title"),
        ]
        for pin in pins {
            let source = try FixtureLoader.requiredDoc(pin.file)
            XCTAssertTrue(source.contains(pin.literal), "\(pin.file) no longer shows \(pin.literal)")
        }
        // And the old bare sentences are gone from the views.
        if let source = FixtureLoader.doc("JimmsBro/Features/Import/ImportView.swift") {
            XCTAssertFalse(source.contains("step(1, \"Copy the prompt.\")"))
        }
    }
}

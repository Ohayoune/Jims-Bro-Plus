import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// V2 (v1.2) — M9: the prompt the app copies is the prompt the docs publish.
///
/// `docs/PROMPT.md` is what the owner reads and what a future agent is told to implement.
/// Nothing connected it to `Prompts.swift`, so the two could drift silently — and the example
/// JSON inside the prompt was, until v1.2, written out twice in the Swift alone.
final class PromptPinningTests: XCTestCase {
    /// The text inside the nth fenced block of a markdown document.
    private func fenced(_ markdown: String, _ index: Int) throws -> String {
        let blocks = markdown.components(separatedBy: "\n```")
        // components: [before, block0, between, block1, ...] — the odd entries are the blocks.
        let block = try XCTUnwrap(blocks[safe: index * 2 + 1])
        return block.hasPrefix("\n") ? String(block.dropFirst()) : block
    }

    /// The published prompt, or a skip when the checkout is out of reach (see `FixtureLoader.doc`).
    private func document() throws -> String {
        guard let text = FixtureLoader.doc("docs/PROMPT.md") else {
            throw XCTSkip("docs/PROMPT.md is outside the simulator's sandbox; "
                          + "this pin runs under `swift test` and `tools/check_core.py`")
        }
        return text
    }

    // M9: the plan prompt, placeholders and all.
    func testPlanPromptMatchesTheDocument() throws {
        let published = try fenced(try document(), 0)
        XCTAssertEqual(Prompts.planTemplate.trimmedTrailingNewlines,
                       published.trimmedTrailingNewlines,
                       "docs/PROMPT.md §1 and Prompts.planTemplate have drifted apart")
    }

    // M9: and the fix-it prompt.
    func testFixItPromptMatchesTheDocument() throws {
        let published = try fenced(try document(), 1)
        XCTAssertEqual(Prompts.fixTemplate.trimmedTrailingNewlines,
                       published.trimmedTrailingNewlines,
                       "docs/PROMPT.md §2 and Prompts.fixTemplate have drifted apart")
    }

    // W37 (v1.3): and the progression prompt of D44 (docs/PROMPT.md §3).
    func testProgressionPromptMatchesTheDocument() throws {
        let published = try fenced(try document(), 2)
        XCTAssertEqual(Prompts.progressionTemplate.trimmedTrailingNewlines,
                       published.trimmedTrailingNewlines,
                       "docs/PROMPT.md §3 and Prompts.progressionTemplate have drifted apart")
    }

    // The example JSON is now written once. It must still be a plan the app imports, and it
    // must still be inside the prompt the chatbot is given.
    func testTheExampleIsWrittenOnceAndStillImports() {
        let rendered = Prompts.render(settings: Settings(units: .lb, defaultRestSeconds: 120))
        XCTAssertTrue(rendered.contains(Prompts.exampleJSONText(units: .lb, defaultRest: 120)))
        let result = PlanImport.run(Prompts.exampleJSON, settings: Settings(), now: CoreTestSupport.now)
        XCTAssertNotNil(result.plan, "\(result.issues)")
        XCTAssertTrue(result.issues.filter { $0.severity == .error }.isEmpty)
    }
}

extension String {
    var trimmedTrailingNewlines: String {
        var text = self
        while text.hasSuffix("\n") { text.removeLast() }
        return text
    }
}

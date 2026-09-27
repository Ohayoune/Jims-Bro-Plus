import Foundation
#if !CORE_CHECKS
import XCTest
@testable import JimmsBro
#endif

/// R4 (v1.1) — the Summary said in words (J25, O74) and the Plan detail line that shows what
/// varies (O76). The visual rules themselves (O75, O77, O78) are simulator checks.
final class SummaryAndVisualTests: XCTestCase {
    private let now = CoreTestSupport.now

    // J25: the comparable, non-comparable, varied-weight and first-time cases.
    func testComparisonReadsAsASentence() throws {
        let name = "Bench Press"
        func compare(_ current: Session, _ history: [Session]) -> ExerciseComparison {
            SessionStats.comparison(for: name, session: current, history: history)
        }

        // No history at all.
        XCTAssertEqual(compare(CoreTestSupport.logged([10, 10, 10], [60, 60, 60], daysAgo: 0), []),
                       ExerciseComparison(headline: "First time", rows: []))

        let last = CoreTestSupport.logged([10, 10, 8], [60, 60, 60], daysAgo: 7)

        // Same weight, more reps — the sentence a lifter actually wants.
        XCTAssertEqual(compare(CoreTestSupport.logged([10, 10, 10], [60, 60, 60], daysAgo: 0), [last]),
                       ExerciseComparison(headline: "2 more reps at the same weight", rows: []))
        XCTAssertEqual(compare(CoreTestSupport.logged([10, 10, 7], [60, 60, 60], daysAgo: 0), [last]).headline,
                       "1 fewer rep at the same weight", "one rep is singular")
        XCTAssertEqual(compare(CoreTestSupport.logged([10, 10, 8], [60, 60, 60], daysAgo: 0), [last]).headline,
                       "Same as last time")

        // The weight moved, with and without the reps moving too.
        XCTAssertEqual(compare(CoreTestSupport.logged([10, 10, 8], [62.5, 62.5, 62.5], daysAgo: 0), [last]).headline,
                       "+2.5 kg")
        XCTAssertEqual(compare(CoreTestSupport.logged([10, 10, 7], [62.5, 62.5, 62.5], daysAgo: 0), [last]).headline,
                       "+2.5 kg, 1 fewer rep")
        XCTAssertEqual(compare(CoreTestSupport.logged([10, 10, 8], [57.5, 57.5, 57.5], daysAgo: 0), [last]).headline,
                       "−2.5 kg")

        // Bodyweight both times: reps are the whole story, and no weight is invented.
        let lastBW = CoreTestSupport.logged([12, 10, 8], [nil, nil, nil], daysAgo: 7, bodyweight: true)
        XCTAssertEqual(compare(CoreTestSupport.logged([12, 12, 8], [nil, nil, nil], daysAgo: 0, bodyweight: true),
                               [lastBW]).headline,
                       "2 more reps")

        // Weights that varied within the session: no one sentence is true, so show the sets.
        let variedThen = CoreTestSupport.logged([12, 10, 8], [24, 26, 28], daysAgo: 7)
        let variedNow = CoreTestSupport.logged([12, 10, 8], [24, 26, 30], daysAgo: 0)
        let varied = compare(variedNow, [variedThen])
        XCTAssertEqual(varied.rows, ["12 × 24 → 12 × 24", "10 × 26 → 10 × 26", "8 × 28 → 8 × 30"])
        XCTAssertEqual(varied.headline, "Volume up 16 kg")

        // A comparison needs something on both sides.
        var empty = CoreTestSupport.logged([10], [60], daysAgo: 0)
        empty.steps[0].status = .pending
        empty.steps[0].result = nil
        XCTAssertEqual(compare(empty, [last]).headline, "Nothing logged")
    }

    // J25: timed work compares seconds held, not reps.
    func testTimedComparisonUsesSeconds() throws {
        let plan = CoreTestSupport.plan(sets: 2, work: .duration(seconds: 45), bodyweight: true)
        func plank(_ seconds: [Int], daysAgo: Int) -> Session {
            var s = CoreTestSupport.session(plan, start: CoreTestSupport.days(-daysAgo))
            for i in s.steps.indices {
                s.steps[i].status = .logged
                s.steps[i].result = .duration(seconds: seconds[i], weight: nil)
                s.steps[i].loggedAt = s.startedAt.addingTimeInterval(Double(i) * 100)
            }
            s.endedAt = s.steps.last?.loggedAt
            return s
        }
        let then = plank([45, 40], daysAgo: 7)
        XCTAssertEqual(SessionStats.comparison(for: "Bench Press", session: plank([45, 45], daysAgo: 0),
                                               history: [then]).headline,
                       "5 s longer held")
        XCTAssertEqual(SessionStats.comparison(for: "Bench Press", session: plank([40, 40], daysAgo: 0),
                                               history: [then]).headline,
                       "5 s shorter held")
        XCTAssertEqual(SessionStats.comparison(for: "Bench Press", session: plank([45, 40], daysAgo: 0),
                                               history: [then]).headline,
                       "Same as last time")
    }

    // O74: the Summary's one headline line, and the volume fragment that disappears at zero.
    func testSummaryHeadlineOmitsVolumeWhenZero() throws {
        let loaded = CoreTestSupport.logged([10, 10, 8], [60, 60, 60], daysAgo: 0)
        XCTAssertEqual(SessionStats.volume(loaded.steps), 1680)
        XCTAssertEqual(SessionStats.loggedCount(loaded), 3)

        // The Summary composes these; the parts themselves are what a test can hold to.
        let bodyweight = CoreTestSupport.logged([12, 12, 12], [nil, nil, nil], daysAgo: 0, bodyweight: true)
        XCTAssertEqual(SessionStats.volume(bodyweight.steps), 0,
                       "a bodyweight day has no volume, and the line must not print \"0 kg\"")
        XCTAssertEqual(HomeActivity.duration(SessionStats.duration(loaded)), "4 min")
        XCTAssertEqual(HomeActivity.duration(48 * 60), "48 min")
        XCTAssertEqual(HomeActivity.duration(92 * 60), "1 h 32 min")
        // A session's volume is routinely four digits, so it is grouped; weights are not.
        XCTAssertEqual(TargetText.grouped(12_400), "12,400")
        XCTAssertEqual(TargetText.grouped(4_864), "4,864")
        XCTAssertEqual(TargetText.grouped(62.5), "62.5")
        XCTAssertEqual(TargetText.number(62.5), "62.5", "a weight keeps its plain form")
    }

    // O76: Plan detail and the review sheet show what varies, not the first set repeated.
    func testPlanDetailShowsPerSetVariation() throws {
        let plan = CoreTestSupport.plan(sets: 3)
        let straight = try XCTUnwrap(plan.days.first?.exercises.first)
        XCTAssertEqual(TargetText.summary(straight, units: .kg, wording: .compact), "3 × 8–12 · 60 kg")

        var pyramid = straight
        pyramid.sets = [SetTarget(work: .reps(.range(min: 8, max: 12)), weight: 24, restSeconds: 90),
                        SetTarget(work: .reps(.range(min: 8, max: 12)), weight: 26, restSeconds: 90),
                        SetTarget(work: .reps(.range(min: 8, max: 12)), weight: 28, restSeconds: 90)]
        XCTAssertEqual(TargetText.summary(pyramid, units: .kg, wording: .compact),
                       "3 × 8–12 · 24 / 26 / 28 kg")
        XCTAssertNotEqual(TargetText.summary(pyramid, units: .kg),
                          TargetText.summary(straight, units: .kg),  // plain, the default
                          "v1 printed the same line for both, which is the defect this fixes")
    }
}

import XCTest
@testable import JimmsBro

final class ProjectSkeletonTests: XCTestCase {
    func testM0BundlesFixturesAndAppResources() throws {
        let manifest = try FixtureLoader.manifest()
        XCTAssertFalse(manifest.fixtures.isEmpty)
        XCTAssertEqual(manifest.settings.units, "kg")
        XCTAssertEqual(manifest.settings.defaultRestSeconds, 90)
        XCTAssertEqual(manifest.settings.today, "2026-09-04")

        for fixture in manifest.fixtures {
            // Some invalid fixtures are intentionally empty or malformed JSON.
            _ = try FixtureLoader.text(fixture.file)
        }

        let sample = try XCTUnwrap(Bundle.main.url(forResource: "SamplePlan", withExtension: "json"))
        XCTAssertEqual(try Data(contentsOf: sample),
                       try FixtureLoader.data("valid/weekly-rotation.json"))
        let beep = try XCTUnwrap(Bundle.main.url(forResource: "beep", withExtension: "wav"))
        XCTAssertEqual(try Data(contentsOf: beep).prefix(4), Data("RIFF".utf8))
    }
}

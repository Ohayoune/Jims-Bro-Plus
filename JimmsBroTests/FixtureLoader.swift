import Foundation
#if !CORE_CHECKS
import XCTest
#endif

/// Reads the folder reference in the test bundle, independent of the checkout path.
enum FixtureLoader {
    private final class BundleToken {}

    static func data(_ path: String) throws -> Data {
        #if CORE_CHECKS
        return try Data(contentsOf: sourceRoot.appendingPathComponent("examples").appendingPathComponent(path))
        #else
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: BundleToken.self)
        #endif
        guard let root = bundle.resourceURL else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: root.appendingPathComponent("examples", isDirectory: true)
            .appendingPathComponent(path))
        #endif
    }

    static func text(_ path: String) throws -> String {
        let bytes = try data(path)
        guard let text = String(data: bytes, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return text
    }

    /// A file the app ships in its own bundle (`JimmsBro/Resources`), as opposed to a fixture.
    /// Read from the app bundle under XCTest and from the source tree under the portable
    /// runner, so both check the file that actually ships rather than a copy of it.
    static func appResource(_ name: String, extension ext: String) throws -> String {
        #if CORE_CHECKS || SWIFT_PACKAGE
        // Neither route builds an app bundle: the portable runner has no bundle at all, and
        // SwiftPM builds Core as a library, so `JimmsBro/Resources` only exists in the source
        // tree. Read it from there.
        return try String(contentsOf: sourceRoot.appendingPathComponent("JimmsBro/Resources")
            .appendingPathComponent("\(name).\(ext)"), encoding: .utf8)
        #else
        guard let url = Bundle.main.url(forResource: name, withExtension: ext)
                ?? Bundle(for: BundleToken.self).url(forResource: name, withExtension: ext) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try String(contentsOf: url, encoding: .utf8)
        #endif
    }

    /// The checkout root. `JIMMSBRO_FIXTURE_ROOT` wins when set (the portable runner sets it);
    /// otherwise it is derived from this file's own path, which is right under SwiftPM
    /// whatever the working directory happens to be.
    static var sourceRoot: URL {
        if let root = ProcessInfo.processInfo.environment["JIMMSBRO_FIXTURE_ROOT"] {
            return URL(fileURLWithPath: root)
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // JimmsBroTests/
            .deletingLastPathComponent()   // the checkout root
    }

    /// A document from the repository itself, for the tests that pin code to the docs.
    ///
    /// Nil when the checkout is out of reach, which it is under XCTest on a simulator: the
    /// test bundle runs inside the simulator's sandbox and the source tree is on the host.
    /// The pinning tests therefore skip on that route and run on the other two (`swift test`
    /// and `tools/check_core.py`, both of which execute on the host).
    static func doc(_ path: String) -> String? {
        try? String(contentsOf: sourceRoot.appendingPathComponent(path), encoding: .utf8)
    }

    /// A document a pin needs, or the skip that says the pin runs on the host routes.
    static func requiredDoc(_ path: String) throws -> String {
        guard let text = doc(path) else { throw outOfReach(path) }
        return text
    }

    /// Every Swift file of the app target, as (path relative to the checkout, contents), or the
    /// skip when the checkout is out of reach.
    static func swiftSources() throws -> [(path: String, text: String)] {
        let app = sourceRoot.appendingPathComponent("JimmsBro")
        var out: [(String, String)] = []
        if let walk = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil) {
            for case let url as URL in walk where url.pathExtension == "swift" {
                let path = url.path.replacingOccurrences(of: sourceRoot.path + "/", with: "")
                out.append((path, try String(contentsOf: url, encoding: .utf8)))
            }
        }
        guard !out.isEmpty else { throw outOfReach("JimmsBro/") }
        return out
    }

    /// The lines under a heading that starts with `heading`, up to the next heading that starts
    /// with `until`.
    static func section(_ text: String, _ heading: String, until: String = "#") throws -> String {
        let lines = text.components(separatedBy: "\n")
        let start = try XCTUnwrap(lines.firstIndex { $0.hasPrefix(heading) }, "no \(heading)")
        return lines[(start + 1)...].prefix { !$0.hasPrefix(until) }.joined(separator: "\n")
    }

    /// The text from `start` up to and including the first `end` after it.
    static func block(_ text: String, from start: String, to end: String) -> String? {
        guard let head = text.range(of: start),
              let tail = text.range(of: end, range: head.upperBound..<text.endIndex) else { return nil }
        return String(text[head.lowerBound..<tail.upperBound])
    }

    /// Source text without its comment lines, so a pin reads the code and not what it says.
    static func withoutComments(_ source: String) -> String {
        source.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private static func outOfReach(_ path: String) -> XCTSkip {
        XCTSkip("\(path) is outside the simulator's sandbox; this pin runs on the host routes")
    }

    static func manifest() throws -> FixtureManifest {
        try JSONDecoder().decode(FixtureManifest.self, from: data("manifest.json"))
    }
}

struct FixtureManifest: Decodable {
    struct Settings: Decodable {
        let units: String
        let defaultRestSeconds: Int
        let today: String
    }

    struct Fixture: Decodable {
        enum Outcome: String, Decodable { case valid, invalid }

        struct ExpectedError: Decodable {
            let code: String
            let path: String?
        }

        let file: String
        let outcome: Outcome
        let warnings: [String]?
        let errors: [ExpectedError]?
        let exact: Bool?
        let checks: [String: JSONValue]?
    }

    let settings: Settings
    let fixtures: [Fixture]
}

/// Preserves all heterogeneous manifest expectations for the later import tests.
indirect enum JSONValue: Decodable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }
}

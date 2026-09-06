import Foundation

/// Reads the folder reference in the test bundle, independent of the checkout path.
enum FixtureLoader {
    private final class BundleToken {}

    static func data(_ path: String) throws -> Data {
        #if CORE_CHECKS
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["JIMMSBRO_FIXTURE_ROOT"] ?? FileManager.default.currentDirectoryPath)
        return try Data(contentsOf: root.appendingPathComponent("examples").appendingPathComponent(path))
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
        #if CORE_CHECKS
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["JIMMSBRO_FIXTURE_ROOT"]
                       ?? FileManager.default.currentDirectoryPath)
        return try String(contentsOf: root.appendingPathComponent("JimmsBro/Resources")
            .appendingPathComponent("\(name).\(ext)"), encoding: .utf8)
        #else
        guard let url = Bundle.main.url(forResource: name, withExtension: ext)
                ?? Bundle(for: BundleToken.self).url(forResource: name, withExtension: ext) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try String(contentsOf: url, encoding: .utf8)
        #endif
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

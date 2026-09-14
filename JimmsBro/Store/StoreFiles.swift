import Foundation

/// Every file this app writes carries the same version number (SPEC §8.1).
let storeFileVersion = 1

enum StoreError: Error, Equatable {
    case unsupportedFileVersion(Int)
    /// D31 (v1.1): the file offered as a backup isn't one.
    case notABackup
    #if DEBUG
    /// D24, device check H33: every write refused, under `-uiReadOnlyStore`. Debug only.
    case writesRefusedForTesting
    #endif

    /// What Settings shows when a restore is refused.
    var message: String {
        switch self {
        case let .unsupportedFileVersion(version):
            return "That backup was written by a newer version of the app (file version \(version))."
        case .notABackup:
            return "That file isn't a Jimm's Bro+ backup."
        #if DEBUG
        case .writesRefusedForTesting:
            return "Writes are refused by the -uiReadOnlyStore launch argument."
        #endif
        }
    }
}

/// Encodes `{ "fileVersion": 1, ...Payload }`: the version sits alongside the payload's own
/// keys rather than wrapping them, because both write into the encoder's single keyed container.
struct VersionedFile<Payload: Codable>: Codable {
    var payload: Payload

    init(_ payload: Payload) { self.payload = payload }

    private enum VersionKey: String, CodingKey { case fileVersion }

    init(from decoder: Decoder) throws {
        let version = try decoder.container(keyedBy: VersionKey.self).decode(Int.self, forKey: .fileVersion)
        // `<=`, not `==`: a v2 reader must still read a v1 file, which is the whole point of
        // writing a version down. A *newer* file is the one it cannot know how to read.
        guard version <= storeFileVersion else { throw StoreError.unsupportedFileVersion(version) }
        payload = try Payload(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        try payload.encode(to: encoder)
        var container = encoder.container(keyedBy: VersionKey.self)
        try container.encode(storeFileVersion, forKey: .fileVersion)
    }
}

/// The body of `plans.json` beneath its `fileVersion`.
struct PlansPayload: Codable, Equatable {
    var activePlanId: UUID?
    var plans: [Plan]
}

/// The backup document of SPEC §8.5. Its shape is the on-disk shape, so restoring it later is trivial.
struct ExportDocument: Codable, Equatable {
    var exportedAt: Date
    var appVersion: String
    var fileVersion: Int = storeFileVersion
    var settings: Settings
    var plans: [Plan]
    var sessions: [Session]
    /// v1.1 (D31): which plan was active. Optional, so a backup written by v1 still decodes;
    /// restoring one of those just leaves the first plan active.
    var activePlanId: UUID?
    // v1.5–v1.7 wrote `goals` here too (D54). D68 removed goals; a backup that carries them
    // still decodes — an unknown key is ignored — and restores everything else (T30).
}

/// D31 (v1.1): what a backup holds, so Settings can say so before anything is applied.
struct BackupSummary: Equatable {
    var exportedAt: Date
    var appVersion: String
    var plans: Int
    var sessions: Int
    /// What a **Merge** would actually add — the rest is already here, by id.
    var newPlans: Int
    var newSessions: Int
}

enum RestoreMode: Equatable { case replaceAll, merge }

/// What the app says when a restore fails. In Core rather than in the view, so the one thing
/// that must be true of it — that it never claims nothing changed after **Replace all**, which
/// empties the store before it writes — is a unit test (v1.2).
enum RestoreText {
    static func failure(_ mode: RestoreMode) -> String {
        switch mode {
        case .replaceAll:
            return "The backup couldn't be fully restored, and Replace all had already cleared "
                + "what was here. Try again with the same file — restoring it twice is safe."
        case .merge:
            return "The backup couldn't be restored. A merge only ever adds, so nothing you "
                + "already had was changed."
        }
    }
}

/// ISO-8601 with fractional seconds, and sorted keys so identical values produce identical bytes.
enum StoreCoder {
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let whole: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func string(from date: Date) -> String { formatter.string(from: date) }
    static func date(from text: String) -> Date? { formatter.date(from: text) ?? whole.date(from: text) }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(string(from: date))
        }
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = date(from: text) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "Not an ISO-8601 date: \(text)"))
            }
            return date
        }
        return decoder
    }

    static func encode<T: Codable>(_ value: T) throws -> Data { try encoder.encode(VersionedFile(value)) }
    static func decode<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(VersionedFile<T>.self, from: data).payload
    }
}

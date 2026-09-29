import Foundation

/// Lenient DTO: all fields remain optional and retain their JSON types until normalization.
indirect enum RawJSON: Codable, Equatable {
    case null, bool(Bool), number(Double), string(String), array([RawJSON]), object([String: RawJSON])
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([RawJSON].self) { self = .array(v) }
        else { self = .object(try c.decode([String: RawJSON].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case let .bool(v): try c.encode(v)
        case let .number(v): try c.encode(v)
        case let .string(v): try c.encode(v)
        case let .array(v): try c.encode(v)
        case let .object(v): try c.encode(v)
        }
    }
    var object: [String: RawJSON]? { if case let .object(v) = self { return v }; return nil }
    var array: [RawJSON]? { if case let .array(v) = self { return v }; return nil }
    var string: String? { if case let .string(v) = self { return v }; return nil }
    var bool: Bool? { if case let .bool(v) = self { return v }; return nil }
    var number: Double? {
        switch self {
        case let .number(n): return n
        case let .string(s): return Double(s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
        default: return nil
        }
    }
    var integer: Int? {
        if case let .string(s) = self, !s.trimmed.matches(#"^\d+$"#) { return nil }
        guard let n = number, n.isFinite, n.rounded() == n, abs(n) < Double(Int.max) else { return nil }
        return Int(n)
    }
    var display: String {
        if let s = string { return s }
        guard let data = try? JSONEncoder().encode(self), let text = String(data: data, encoding: .utf8) else { return "null" }
        return text
    }
    /// The tree as JSON text for the pipeline: sorted keys and indented, so the same tree is the
    /// same bytes. Empty if it cannot be written (a number that is not finite).
    var jsonText: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        guard let data = try? encoder.encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
    subscript(_ key: String) -> RawJSON? {
        guard let value = object?[key], value != .null else { return nil }
        return value
    }
}
typealias RawPlan = RawJSON
extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    func matches(_ pattern: String) -> Bool { range(of: pattern, options: .regularExpression) != nil }
    func replacing(_ pattern: String, with value: String) -> String { replacingOccurrences(of: pattern, with: value, options: .regularExpression) }
    func captures(_ pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern), let m = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self)) else { return nil }
        return (0..<m.numberOfRanges).map { Range(m.range(at: $0), in: self).map { String(self[$0]) } ?? "" }
    }
}

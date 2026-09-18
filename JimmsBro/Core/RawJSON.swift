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

/// Foundation accepts some non-standard JSON (including trailing commas). Check grammar first.
struct StrictJSON {
    private var bytes: [UInt8]
    private var index = 0
    init(_ text: String) { bytes = Array(text.utf8) }
    mutating func validate() throws {
        try value(depth: 0); whitespace()
        guard index == bytes.count else { throw error("Unexpected text after the JSON value") }
    }
    private func error(_ message: String) -> NSError {
        let prefix = bytes.prefix(index)
        let line = prefix.filter { $0 == 10 }.count + 1
        let column = index - (prefix.lastIndex(of: 10) ?? -1)
        return NSError(domain: "StrictJSON", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(message) at line \(line), column \(column)."])
    }
    private mutating func whitespace() { while index < bytes.count && [9,10,13,32].contains(bytes[index]) { index += 1 } }
    private mutating func take(_ byte: UInt8) -> Bool {
        whitespace()
        guard index < bytes.count, bytes[index] == byte else { return false }
        index += 1; return true
    }
    private mutating func value(depth: Int) throws {
        whitespace()
        guard index < bytes.count else { throw error("Unexpected end of file") }
        guard depth <= 256 else { throw error("JSON is nested too deeply") }
        switch bytes[index] {
        case 123, 91:
            let object = bytes[index] == 123, end: UInt8 = bytes[index] == 123 ? 125 : 93
            index += 1
            if take(end) { return }
            while true {
                if object {
                    whitespace(); try string()
                    guard take(58) else { throw error("Expected a colon") }
                }
                try value(depth: depth + 1)
                if take(end) { return }
                guard take(44) else { throw error(index == bytes.count ? "Unexpected end of file" : "Expected a comma or closing bracket") }
            }
        case 34: try string()
        case 116: try literal("true")
        case 102: try literal("false")
        case 110: try literal("null")
        default:
            let start = index
            if bytes[index] == 45 { index += 1 }
            guard index < bytes.count else { throw error("Unexpected end of file") }
            if bytes[index] == 48 { index += 1 }
            else {
                guard (49...57).contains(bytes[index]) else { throw error("Expected a JSON value") }
                while index < bytes.count && (48...57).contains(bytes[index]) { index += 1 }
            }
            if index < bytes.count && bytes[index] == 46 {
                index += 1
                guard index < bytes.count && (48...57).contains(bytes[index]) else { throw error("Expected fractional digits") }
                while index < bytes.count && (48...57).contains(bytes[index]) { index += 1 }
            }
            if index < bytes.count && [69,101].contains(bytes[index]) {
                index += 1
                if index < bytes.count && [43,45].contains(bytes[index]) { index += 1 }
                guard index < bytes.count && (48...57).contains(bytes[index]) else { throw error("Expected exponent digits") }
                while index < bytes.count && (48...57).contains(bytes[index]) { index += 1 }
            }
            guard index > start else { throw error("Expected a JSON value") }
        }
    }
    private mutating func string() throws {
        guard index < bytes.count, bytes[index] == 34 else { throw error(index == bytes.count ? "Unexpected end of file" : "Expected a double-quoted string") }
        index += 1
        while index < bytes.count {
            let b = bytes[index]; index += 1
            if b == 34 { return }
            if b < 32 { throw error("Unescaped control character") }
            if b == 92 {
                guard index < bytes.count else { throw error("Unexpected end of file") }
                let escape = bytes[index]; index += 1
                if escape == 117 {
                    for _ in 0..<4 {
                        guard index < bytes.count, (48...57).contains(bytes[index]) || (65...70).contains(bytes[index]) || (97...102).contains(bytes[index]) else { throw error("Invalid Unicode escape") }
                        index += 1
                    }
                } else if ![34,92,47,98,102,110,114,116].contains(escape) { throw error("Invalid string escape") }
            }
        }
        throw error("Unexpected end of file")
    }
    private mutating func literal(_ token: String) throws {
        let expected = Array(token.utf8)
        guard bytes.dropFirst(index).starts(with: expected) else { throw error("Invalid JSON literal") }
        index += expected.count
    }
}

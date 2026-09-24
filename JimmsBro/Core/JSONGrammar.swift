import Foundation

/// JSON's grammar, read once (D96, v1.12) and strictly, as RFC 8259 writes it: no trailing comma,
/// no comment, no single quote, no NaN. Three readers share it — the importer, which checks a paste
/// with it before Foundation decodes one (Foundation alone lets a trailing comma through); the JSON
/// sheet, which follows a path to its line through the offsets a parse keeps (`JSONLocator`); and
/// the extraction's cut of one value out of a reply (`valueEnd(in:from:)`), which reads the same
/// strings more loosely.
struct JSONGrammar {
    /// A value, and the byte where it begins.
    struct Node {
        enum Kind {
            case object([Member])
            case array([Node])
            case scalar
        }

        var kind: Kind
        var start: Int
    }

    /// A member of an object: its key, the byte where the key begins, and its value.
    struct Member {
        /// Nil when the key is spelled with an escape: matched by nothing, rather than decoded here.
        var key: String?
        var keyStart: Int
        var value: Node
    }

    /// Where the grammar broke, and how. E_NOT_JSON quotes its description — *"Expected a colon
    /// at line 3, column 9."* — whose column counts bytes.
    struct Failure: LocalizedError, Equatable {
        var message: String
        var offset: Int
        var line: Int
        var column: Int

        var errorDescription: String? { "\(message) at line \(line), column \(column)." }
    }

    /// `text` as exactly one JSON value with nothing but whitespace around it, or the first place
    /// where it is not.
    static func parse(_ text: String) throws -> Node {
        var reader = JSONGrammar(text)
        let root = try reader.value(depth: 0)
        reader.whitespace()
        guard reader.index == reader.bytes.count else { throw reader.failure("Unexpected text after the JSON value") }
        return root
    }

    /// The 1-based line of byte `offset` in `text`. Lines end at a line feed.
    static func line(at offset: Int, in text: String) -> Int {
        position(of: offset, in: text.utf8).line
    }

    /// Where the bracketed value that begins at `start` ends, reading only its strings and its
    /// brackets: the extraction's cut (`PlanImport.extract`), which has to find the end of a reply
    /// that is not strict JSON yet — a trailing comma, curly quotes — so the decoder can say what
    /// is wrong with it. Its strings are read loosely: a backslash takes the next byte, whatever it
    /// is, and a control character passes. Nil when the brackets never close.
    static func valueEnd(in text: String, from start: String.Index) -> String.Index? {
        let utf8 = text.utf8
        var reader = JSONGrammar(text)
        reader.index = utf8.distance(from: utf8.startIndex, to: start)
        var depth = 0
        while reader.index < reader.bytes.count {
            switch reader.bytes[reader.index] {
            case 34: // "
                do { try reader.string(strict: false) } catch { return nil }
                continue
            case 123, 91: // { [
                depth += 1
            case 125, 93: // } ]
                depth -= 1
                if depth == 0 { return utf8.index(utf8.startIndex, offsetBy: reader.index + 1) }
            default:
                break
            }
            reader.index += 1
        }
        return nil
    }

    private let bytes: [UInt8]
    private var index = 0

    private init(_ text: String) { bytes = Array(text.utf8) }

    /// The line and the column, both from 1, of byte `offset`.
    private static func position<Bytes: Collection>(of offset: Int, in bytes: Bytes) -> (line: Int, column: Int)
    where Bytes.Element == UInt8 {
        var line = 1, lineStart = 0
        for (index, byte) in bytes.prefix(offset).enumerated() where byte == 10 {
            line += 1
            lineStart = index + 1
        }
        return (line, offset - lineStart + 1)
    }

    private func failure(_ message: String) -> Failure {
        let (line, column) = Self.position(of: index, in: bytes)
        return Failure(message: message, offset: index, line: line, column: column)
    }

    private mutating func whitespace() {
        while index < bytes.count, [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
    }

    private mutating func take(_ byte: UInt8) -> Bool {
        whitespace()
        guard index < bytes.count, bytes[index] == byte else { return false }
        index += 1
        return true
    }

    private mutating func value(depth: Int) throws -> Node {
        whitespace()
        guard index < bytes.count else { throw failure("Unexpected end of file") }
        guard depth <= 256 else { throw failure("JSON is nested too deeply") }
        let start = index
        switch bytes[index] {
        case 123, 91: // { [
            let isObject = bytes[index] == 123, close: UInt8 = isObject ? 125 : 93
            index += 1
            var members: [Member] = [], elements: [Node] = []
            if !take(close) {
                while true {
                    if isObject {
                        whitespace()
                        let keyStart = index
                        let plain = try string()
                        guard take(58) else { throw failure("Expected a colon") }
                        let key = plain.map { String(decoding: bytes[$0], as: UTF8.self) }
                        members.append(Member(key: key, keyStart: keyStart, value: try value(depth: depth + 1)))
                    } else {
                        elements.append(try value(depth: depth + 1))
                    }
                    if take(close) { break }
                    guard take(44) else {
                        throw failure(index == bytes.count ? "Unexpected end of file" : "Expected a comma or closing bracket")
                    }
                }
            }
            return Node(kind: isObject ? .object(members) : .array(elements), start: start)
        case 34: try string() // "
        case 116: try literal("true")
        case 102: try literal("false")
        case 110: try literal("null")
        default: try number()
        }
        return Node(kind: .scalar, start: start)
    }

    /// The string at the cursor, and the bytes between its quotes when no escape is among them.
    /// Strictly, a control character, an escape JSON has no letter for and a short `\u` are
    /// refusals; loosely — the cut — a backslash takes the next byte, whatever it is, and only a
    /// string that never closes is one.
    @discardableResult
    private mutating func string(strict: Bool = true) throws -> Range<Int>? {
        guard index < bytes.count, bytes[index] == 34 else {
            throw failure(index == bytes.count ? "Unexpected end of file" : "Expected a double-quoted string")
        }
        index += 1
        let start = index
        var plain = true
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if byte == 34 { return plain ? start..<index - 1 : nil }
            if byte < 32, strict { throw failure("Unescaped control character") }
            if byte == 92 { // \
                plain = false
                guard index < bytes.count else { throw failure("Unexpected end of file") }
                let escape = bytes[index]
                index += 1
                guard strict else { continue }
                if escape == 117 { // u
                    for _ in 0..<4 {
                        guard index < bytes.count, isHex(bytes[index]) else { throw failure("Invalid Unicode escape") }
                        index += 1
                    }
                } else if ![34, 92, 47, 98, 102, 110, 114, 116].contains(escape) {
                    throw failure("Invalid string escape")
                }
            }
        }
        throw failure("Unexpected end of file")
    }

    private func isHex(_ byte: UInt8) -> Bool {
        (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
    }

    private mutating func literal(_ word: String) throws {
        let expected = Array(word.utf8)
        guard bytes[index...].starts(with: expected) else { throw failure("Invalid JSON literal") }
        index += expected.count
    }

    private mutating func number() throws {
        if bytes[index] == 45 { index += 1 } // -
        guard index < bytes.count else { throw failure("Unexpected end of file") }
        if bytes[index] == 48 {
            index += 1
        } else {
            guard (49...57).contains(bytes[index]) else { throw failure("Expected a JSON value") }
            digits()
        }
        if index < bytes.count, bytes[index] == 46 { // .
            index += 1
            guard index < bytes.count, (48...57).contains(bytes[index]) else { throw failure("Expected fractional digits") }
            digits()
        }
        if index < bytes.count, bytes[index] == 69 || bytes[index] == 101 { // E e
            index += 1
            if index < bytes.count, bytes[index] == 43 || bytes[index] == 45 { index += 1 }
            guard index < bytes.count, (48...57).contains(bytes[index]) else { throw failure("Expected exponent digits") }
            digits()
        }
    }

    private mutating func digits() {
        while index < bytes.count, (48...57).contains(bytes[index]) { index += 1 }
    }
}

import Foundation

/// SPEC §6.19 (D77, v1.9): where in a text a path of the import pipeline is written, so the JSON
/// sheet can mark the line an error names.
///
/// It walks the text as strict JSON, keeping where each key and each element begins, and follows
/// the path — `days[0].exercises[1].sets[0].reps`, `[1].name` — to the line where the member's
/// key, or the element, starts. Its rule is honesty: that line, or nothing. Text that is not
/// exactly one JSON value (prose around it, a fence, a trailing comma, the curly quotes the
/// importer would have mended), a key written twice, a path into a key or an index that is not
/// there, and the empty path — the whole text, which no one line is — all answer nil, and the
/// sheet then shows the sentence under the box with no line marked. It never marks the wrong line.
enum JSONLocator {
    /// One step of a path: a member's key, or an element's index.
    enum Component: Equatable {
        case key(String)
        case index(Int)
    }

    /// The 1-based line where `path` is written in `text`, or nil.
    static func line(of path: String, in text: String) -> Int? {
        components(path).flatMap { line(of: $0, in: text) }
    }

    static func line(of path: [Component], in text: String) -> Int? {
        guard !path.isEmpty else { return nil }
        var parser = LocatorParser(text)
        guard var node = parser.document() else { return nil }
        var offset = node.start
        for component in path {
            switch (component, node.kind) {
            case let (.key(key), .object(members)):
                let named = members.filter { $0.key == key }
                // A key written twice is two places; which one the importer read is not this
                // walker's to guess.
                guard named.count == 1 else { return nil }
                node = named[0].value
                offset = named[0].keyStart
            case let (.index(index), .array(elements)):
                guard elements.indices.contains(index) else { return nil }
                node = elements[index]
                offset = node.start
            default:
                return nil
            }
        }
        return parser.line(at: offset)
    }

    /// "days[1].exercises[2].reps" → days, 1, exercises, 2, reps; "[0].name" → 0, name; "" → no
    /// steps. Nil when the text is not a path.
    static func components(_ path: String) -> [Component]? {
        var out: [Component] = []
        var key = ""
        var digits: String?
        // Just after "]": only "." or "[" may follow.
        var closed = false
        for character in path {
            if let open = digits {
                if character == "]" {
                    guard let index = Int(open) else { return nil }
                    out.append(.index(index))
                    digits = nil
                    closed = true
                } else if character.isASCII, character.isNumber {
                    digits = open + String(character)
                } else {
                    return nil
                }
                continue
            }
            switch character {
            case "[":
                if !key.isEmpty { out.append(.key(key)); key = "" }
                digits = ""
                closed = false
            case ".":
                if !key.isEmpty { out.append(.key(key)); key = "" } else if !closed { return nil }
                closed = false
            default:
                guard !closed else { return nil }
                key.append(character)
            }
        }
        guard digits == nil else { return nil }
        if !key.isEmpty { out.append(.key(key)) }
        return out
    }

    /// The characters of line `line` (1-based) of `text`, without its line feed, or nil past the
    /// end. Lines end at a line feed, as `line(of:in:)` counts them.
    static func range(ofLine line: Int, in text: String) -> Range<String.Index>? {
        guard line >= 1 else { return nil }
        let bytes = text.utf8
        var start = bytes.startIndex
        for _ in 1..<line {
            guard let feed = bytes[start...].firstIndex(of: 10) else { return nil }
            start = bytes.index(after: feed)
        }
        return start..<(bytes[start...].firstIndex(of: 10) ?? bytes.endIndex)
    }
}

/// A value of the text, and where it begins.
private struct LocatorNode {
    enum Kind {
        case object([LocatorMember])
        case array([LocatorNode])
        case scalar
    }

    var kind: Kind
    var start: Int
}

private struct LocatorMember {
    /// Nil when the key is spelled with an escape: matched by nothing, rather than decoded here.
    var key: String?
    var keyStart: Int
    var value: LocatorNode
}

/// `StrictJSON`'s grammar, keeping offsets instead of only saying yes or no.
private struct LocatorParser {
    private let bytes: [UInt8]
    private var index = 0

    init(_ text: String) { bytes = Array(text.utf8) }

    /// The text as one JSON value with nothing but whitespace around it, or nil.
    mutating func document() -> LocatorNode? {
        guard let root = value(depth: 0) else { return nil }
        whitespace()
        return index == bytes.count ? root : nil
    }

    func line(at offset: Int) -> Int {
        bytes[..<offset].reduce(1) { $1 == 10 ? $0 + 1 : $0 }
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

    private mutating func value(depth: Int) -> LocatorNode? {
        whitespace()
        guard index < bytes.count, depth <= 256 else { return nil }
        let start = index
        switch bytes[index] {
        case 123:
            index += 1
            var members: [LocatorMember] = []
            if take(125) { return LocatorNode(kind: .object(members), start: start) }
            while true {
                whitespace()
                let keyStart = index
                guard let key = string(), take(58), let child = value(depth: depth + 1) else { return nil }
                members.append(LocatorMember(key: key.plain ? key.text : nil, keyStart: keyStart, value: child))
                if take(125) { return LocatorNode(kind: .object(members), start: start) }
                guard take(44) else { return nil }
            }
        case 91:
            index += 1
            var elements: [LocatorNode] = []
            if take(93) { return LocatorNode(kind: .array(elements), start: start) }
            while true {
                guard let child = value(depth: depth + 1) else { return nil }
                elements.append(child)
                if take(93) { return LocatorNode(kind: .array(elements), start: start) }
                guard take(44) else { return nil }
            }
        case 34:
            return string() == nil ? nil : LocatorNode(kind: .scalar, start: start)
        case 116:
            return literal("true") ? LocatorNode(kind: .scalar, start: start) : nil
        case 102:
            return literal("false") ? LocatorNode(kind: .scalar, start: start) : nil
        case 110:
            return literal("null") ? LocatorNode(kind: .scalar, start: start) : nil
        default:
            return number() ? LocatorNode(kind: .scalar, start: start) : nil
        }
    }

    /// A string literal — its text, and whether it was written without escapes — or nil.
    private mutating func string() -> (text: String, plain: Bool)? {
        guard index < bytes.count, bytes[index] == 34 else { return nil }
        index += 1
        let start = index
        var plain = true
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if byte == 34 { return (String(decoding: bytes[start..<index - 1], as: UTF8.self), plain) }
            if byte < 32 { return nil }
            if byte == 92 {
                plain = false
                guard index < bytes.count else { return nil }
                let escape = bytes[index]
                index += 1
                if escape == 117 {
                    for _ in 0..<4 {
                        guard index < bytes.count, isHex(bytes[index]) else { return nil }
                        index += 1
                    }
                } else if ![34, 92, 47, 98, 102, 110, 114, 116].contains(escape) {
                    return nil
                }
            }
        }
        return nil
    }

    private func isHex(_ byte: UInt8) -> Bool {
        (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
    }

    private mutating func literal(_ word: String) -> Bool {
        let expected = Array(word.utf8)
        guard bytes[index...].starts(with: expected) else { return false }
        index += expected.count
        return true
    }

    private mutating func number() -> Bool {
        let start = index
        if index < bytes.count, bytes[index] == 45 { index += 1 }
        guard index < bytes.count else { return false }
        if bytes[index] == 48 {
            index += 1
        } else {
            guard (49...57).contains(bytes[index]) else { return false }
            digits()
        }
        if index < bytes.count, bytes[index] == 46 {
            index += 1
            guard index < bytes.count, (48...57).contains(bytes[index]) else { return false }
            digits()
        }
        if index < bytes.count, bytes[index] == 69 || bytes[index] == 101 {
            index += 1
            if index < bytes.count, bytes[index] == 43 || bytes[index] == 45 { index += 1 }
            guard index < bytes.count, (48...57).contains(bytes[index]) else { return false }
            digits()
        }
        return index > start
    }

    private mutating func digits() {
        while index < bytes.count, (48...57).contains(bytes[index]) { index += 1 }
    }
}

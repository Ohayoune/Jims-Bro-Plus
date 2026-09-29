import Foundation

/// SPEC §6.19 (D77, v1.9): where in a text a path of the import pipeline is written, so the JSON
/// sheet can mark the line an error names.
///
/// It reads the text with the importer's own grammar (`JSONGrammar`), which keeps where each key
/// and each element begins, and follows the path — `days[0].exercises[1].sets[0].reps`,
/// `[1].name` — to the line where the member's key, or the element, starts. Its rule is honesty:
/// that line, or nothing. Text that is not exactly one JSON value (prose around it, a fence, a
/// trailing comma, the curly quotes the importer would have mended), a key written twice, a path
/// into a key or an index that is not there, and the empty path — the whole text, which no one
/// line is — all answer nil, and the sheet then shows the sentence under the box with no line
/// marked. It never marks the wrong line.
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
        guard !path.isEmpty, var node = try? JSONGrammar.parse(text) else { return nil }
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
        return JSONGrammar.line(at: offset, in: text)
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

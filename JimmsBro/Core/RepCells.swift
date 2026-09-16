import Foundation

/// SPEC §6.54 (D81, v1.10): a set drawn, not written — one cell per rep, or per five seconds of a
/// timed set. The owner: *"for the required range, you should have solid vertical bars, and for
/// the remaining bars in the recommended range you should have transparent vertical bars."*
///
/// A **target** is solid to the minimum and faint to the top of the range, with a caret under the
/// cell of the number in the field; a **logged** set is solid to what was done. Past the top of
/// the range a cell is yellow, a warning rather than a state (§6.52). A line above marks the cell
/// last time reached. The view draws exactly this; it decides nothing.
struct RepCells: Equatable {
    /// What a set asks, in its own units — reps, or seconds before they become cells.
    struct Bounds: Equatable {
        var minimum: Int
        /// Nil when the range has no top: as many as you can, or a hold with only a minimum.
        var maximum: Int?

        /// The bounds a target draws: a range as written; a fixed count inside an exercise's
        /// range draws the range, as `TargetText.workWithRange` says it (§6.36); a fixed
        /// duration is a range of one.
        static func of(_ work: WorkTarget, range: RepRange?) -> Bounds {
            switch work {
            case let .reps(.fixed(n)):
                guard let range, range.min != n || range.max != n else { return Bounds(minimum: n, maximum: n) }
                return Bounds(minimum: range.min, maximum: range.max)
            case let .reps(.range(low, high)): return Bounds(minimum: low, maximum: high)
            case let .reps(.amrap(minimum)): return Bounds(minimum: minimum ?? 0, maximum: nil)
            case let .duration(seconds): return Bounds(minimum: seconds, maximum: seconds)
            case let .openDuration(minimum): return Bounds(minimum: minimum ?? 0, maximum: nil)
            }
        }
    }

    struct Cell: Equatable {
        enum Fill: String, Equatable { case solid, faint }
        var fill: Fill
        /// Past the top of the range: drawn yellow.
        var over = false
        /// The caret beneath: the cell of the number in the field.
        var caret = false
        /// The line above: the cell last time reached.
        var last = false
        /// Which five the cell is in; a gap falls where it changes, so 12–15 counts at a glance.
        var group: Int
    }

    var cells: [Cell]

    /// A timed set draws a cell per five seconds, rounded up: 30–45 s is nine cells, six solid.
    static let secondsPerCell = 5
    /// Three lines of twenty. A field holds up to 999 reps and a hold 99,999 seconds; past this
    /// the card draws the cap rather than a view per rep.
    static let maximumCells = 60

    static func target(_ bounds: Bounds, reps: Int?, lastTime: Int? = nil) -> RepCells {
        let minimum = max(0, bounds.minimum)
        let top = bounds.maximum.map { max($0, minimum) }
        return make(count: max(top ?? minimum, reps ?? 0, lastTime ?? 0), top: top,
                    solid: minimum, caret: reps, last: lastTime)
    }

    static func logged(_ bounds: Bounds, result: Int, lastTime: Int? = nil) -> RepCells {
        let minimum = max(0, bounds.minimum)
        let top = bounds.maximum.map { max($0, minimum) }
        let done = max(0, result)
        return make(count: max(top ?? minimum, done, lastTime ?? 0), top: top,
                    solid: done, caret: nil, last: lastTime)
    }

    /// `bounds`, `seconds` and `lastTime` in seconds. A running or waiting hold has no field, so
    /// its target has no caret; a logged one is solid to its own length.
    static func timed(_ bounds: Bounds, seconds: Int?, logged isLogged: Bool = false,
                      lastTime: Int? = nil) -> RepCells {
        let cellBounds = Bounds(minimum: cells(bounds.minimum), maximum: bounds.maximum.map(cells))
        if isLogged {
            return logged(cellBounds, result: cells(seconds ?? 0), lastTime: lastTime.map(cells))
        }
        return target(cellBounds, reps: seconds.map(cells), lastTime: lastTime.map(cells))
    }

    private static func cells(_ seconds: Int) -> Int {
        (max(0, seconds) + secondsPerCell - 1) / secondsPerCell
    }

    private static func make(count: Int, top: Int?, solid: Int, caret: Int?, last: Int?) -> RepCells {
        RepCells(cells: (0..<min(count, maximumCells)).map { i in
            let n = i + 1
            return Cell(fill: n <= solid ? .solid : .faint, over: top.map { n > $0 } ?? false,
                        caret: n == caret, last: n == last, group: i / 5)
        })
    }
}

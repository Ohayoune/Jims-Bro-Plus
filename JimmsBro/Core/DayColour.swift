import Foundation

/// SPEC §6.41 (D65, v1.7): a colour per day. Every day of a plan takes a colour by its place in
/// the plan's day list, so the same day reads the same on Today, in the calendar, on its
/// History row and in the workout header — and on the Lock Screen. Colour says *which day*; the
/// accent says *tappable* (§4.0).
///
/// Six colours, none of them the accent (D59), red (destructive) or yellow (warnings), all of
/// them the system's so they follow dark mode; the seventh day wraps to the first. Derived,
/// never stored: reordering a plan's days recolours them, which is the price of leaving the
/// on-disk contract alone.
///
/// This file is compiled into **both** the app and the widget extension, like
/// `WorkoutActivityState.swift`, so it depends on nothing but Foundation. Here a colour is only
/// a name; the mapping to a `Color` is the view layer's (`DaySquare.swift`).
enum DayColour: String, CaseIterable, Codable, Hashable, Sendable {
    case green, orange, purple, pink, teal, indigo

    /// The palette position of the plan's `dayIndex`-th day: its place in the day list,
    /// wrapping after six.
    static func index(dayIndex: Int) -> Int {
        let count = allCases.count
        return (dayIndex % count + count) % count
    }

    /// The colour of the plan's `dayIndex`-th day.
    static func of(dayIndex: Int) -> DayColour { allCases[index(dayIndex: dayIndex)] }
}

/// D75 (v1.9, §6.49): a plan's cycle as one symbol draws it — one row of equal squares, a day's
/// colour each and nil (grey) for rest. A cycle longer than fourteen draws its first fourteen
/// and a trailing mark, so a month-long block stays a glyph rather than a line of dust. Here
/// beside `DayColour` so `CycleSymbol` can ask it in both targets.
struct CycleGlyph: Equatable, Sendable {
    static let limit = 14
    /// The squares drawn, in the cycle's order.
    var squares: [DayColour?]
    /// The cycle has more entries than are drawn, and a trailing mark says so.
    var continues: Bool

    init(_ cycle: [DayColour?]) {
        squares = Array(cycle.prefix(Self.limit))
        continues = cycle.count > Self.limit
    }
}

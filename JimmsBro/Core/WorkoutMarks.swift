import Foundation

/// SPEC §6.52 (D79, v1.10): on the Workout screen and the Lock Screen activity, every mark that
/// stands for a set or an exercise is in one of three colours, and the colour says its state —
/// *"incompleted exercises grey, current set blue (a reserved colour), and finished sets the
/// colour of the day"*. Done is the day's colour, now is the accent, not yet is grey.
///
/// This file is compiled into both the app and the widget extension, as
/// `WorkoutActivityState.swift` is, so it depends on nothing but Foundation. The rule that
/// gives a step its state reads a running workout and lives beside its first caller, in
/// `WorkoutBar.swift` (`MarkState.of(step:session:)`), which only the app builds; the one
/// mapping to a `Color` is `DaySquare.swift`'s.
enum MarkState: String, CaseIterable, Equatable, Hashable, Codable, Sendable {
    /// Logged — or skipped and then given a result, which logs it (D27).
    case done
    /// The current set, and only it.
    case now
    /// Every set ahead, and a skipped set: grey has one job, *not yet*, and a skip never happened.
    case todo
}

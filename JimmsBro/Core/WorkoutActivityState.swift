import Foundation

/// SPEC §6.17 (D40, v1.2): what the Lock Screen and the Dynamic Island show while a workout is
/// running. "Could also have the time appear at the lock screen at the top — that would also be
/// useful — and in the Dynamic Island."
///
/// This file is compiled into **both** the app and the widget extension: it is the contract
/// between them, so it depends on nothing but Foundation. How it is derived from a running
/// workout lives next door in `WorkoutActivity.swift`, which only the app builds.
struct WorkoutActivityState: Equatable, Hashable, Codable, Sendable {
    /// "Warm-up", "Rest", "Between exercises", or the exercise's own name while working.
    var title: String
    /// "Bench Press · set 2 of 4 · 8–12 · 60 kg" — the line under the timer.
    var detail: String
    /// When the countdown ends. Nil while working, when there is nothing counting down.
    /// A `Date` rather than a number of seconds: the system draws the timer itself, so it stays
    /// right without the app being awake — SPEC §6.4's rule, one layer out.
    var endsAt: Date?
    /// A running timed set counts **up** from here; a rest counts down to `endsAt`.
    var startedAt: Date?
    /// Sets logged or skipped, over sets planned, for the little progress bar.
    var done: Int
    var total: Int
    /// True for a break of any kind, so the Island can colour it.
    var isBreak: Bool
    /// D65 (v1.7, §6.41): the day's colour — the square before the title, and the compact
    /// Island's figure while working. Nil when the day is in no plan, and in a state from
    /// before v1.7. `DayColour.swift` is compiled into the extension alongside this file.
    var dayColour: DayColour? = nil

    /// D41 (v1.3): no timer the Island draws is ever allowed to grow to `h:mm:ss`. A count-up
    /// that ran to `.distantFuture` reserved the width of "999:59:59" in the compact Island,
    /// which is most of why it was "too wide". Nothing here runs an hour: a rest is at most
    /// 3600 s, a warm-up 30 min, and an open hold that long is not a set.
    static let longestTimer: TimeInterval = 3599

    /// Whether the timer counts down to `endsAt` or up from `startedAt` — its direction. A
    /// running timed set and, since v1.10 (D82), the walk between exercises count up.
    var timerCountsDown: Bool { endsAt != nil }

    /// The closed range the system timer draws — `Text(timerInterval:)` needs one and crashes
    /// on an inverted one — or nil when nothing is running. A countdown whose end has already
    /// passed is still a one-second range, never `now...past`; a count-up is cut at 59:59.
    func timerRange(now: Date = Date()) -> ClosedRange<Date>? {
        if let endsAt { return now...max(endsAt, now.addingTimeInterval(1)) }
        if let startedAt { return startedAt...startedAt.addingTimeInterval(Self.longestTimer) }
        return nil
    }
}

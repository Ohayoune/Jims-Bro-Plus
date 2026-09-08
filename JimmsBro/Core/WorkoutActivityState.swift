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
}

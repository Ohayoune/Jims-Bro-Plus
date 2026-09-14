import Foundation

/// SPEC §6.40 (D64, v1.7): controls are earned. A control appears the first time it has
/// something to do; none is removed from the app by this, only delayed. One function per row of
/// §6.40's table — a new gated control adds its row there before it adds a function here, and a
/// test holds the two together (T21) — and the views ask these rather than counting for
/// themselves.
///
/// Nothing is stored. Each gate is a function of the data, and the data only grows with time
/// and use, so a control once shown stays; deleting what earned it takes it back (Delete all
/// data returns the app to its first day). The one control that leaves on its own is D50's.
///
/// D70 (v1.8): the week strip and its tap are deliberately *not* here — live from the first
/// plan, recorded as such in §6.40's table — and **Another day**'s gate went with the chooser
/// the strip replaced (§6.44).
enum Gates {
    /// **Month**, on History's calendar: once a workout is older than the current week. Until
    /// then the strip is the whole record. "This week" is the calendar week the strip shows
    /// (`CalendarProjection.week(containing:)`), so pass the strip's calendar.
    static func month(sessions: [Session], today: Date, calendar: Calendar = .current) -> Bool {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: today) else { return false }
        return finished(sessions).contains { $0.startedAt < week.start }
    }

    /// **Metrics**, **Find an exercise** and — for the active plan — **Progression** (D67): one
    /// block on History, once there is a workout to count, to find an exercise in, or to plan a
    /// progression from. (Until D66 the search field came with them; it went.)
    static func metricsAndFind(sessions: [Session]) -> Bool { !finished(sessions).isEmpty }

    /// **Change plan**, in Today's ···: once there is a plan, and so a list to change it in.
    static func changePlan(plans: [Plan]) -> Bool { !plans.isEmpty }

    /// **Plan a progression**, in Today's ··· (D50): every exercise on the day has a logged
    /// session to plan from, and the plan carries no progression — so it leaves again the
    /// moment one is attached.
    static func planProgression(plan: Plan, dayIndex: Int, sessions: [Session]) -> Bool {
        guard plan.progression == nil, let day = plan.days[safe: dayIndex],
              !day.exercises.isEmpty else { return false }
        return day.exercises.allSatisfy { exercise in
            ExerciseHistory.last(name: exercise.name, units: plan.units, sessions: sessions) != nil
        }
    }

    /// The notifications-off line on Today (D57): once this run's first **Log set** — or first
    /// timer started — has asked for the permission, and the answer was no. Before that the app
    /// has not asked, so there is nothing to say.
    static func notificationsOff(askedAtLogSet: Bool, allowed: Bool) -> Bool {
        askedAtLogSet && !allowed
    }

    /// A workout still running earns nothing: History does not list it.
    private static func finished(_ sessions: [Session]) -> [Session] {
        sessions.filter { $0.endedAt != nil }
    }
}

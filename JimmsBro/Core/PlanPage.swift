import Foundation

/// SPEC §4.2 and §6.51 (D78, v1.9): the Plans list speaks in squares. A row names its plan by
/// the cycle — the ···'s own symbol (`DayColour.cycle(of:)`, D75) — and says beneath the name
/// how often it trains; a circle marks a plan and a button confirms it (the owner's 15). Decided
/// here, so the list draws what it is handed (§6.37).
enum PlanText {
    /// How often the plan trains, beneath its name: "6 days a week" for a cycle of seven — every
    /// weekday plan is one — "3 days every 10" otherwise, and "Every day" when every entry is a
    /// workout, a cycle of one among them. Counted from the squares its symbol draws, so the
    /// words and the symbol beside them cannot disagree. Nil when no entry is a workout: there
    /// is nothing true to say.
    static func howOften(_ plan: Plan) -> String? {
        let cycle = DayColour.cycle(of: plan)
        let workouts = cycle.compactMap { $0 }.count
        guard workouts > 0 else { return nil }
        if workouts == cycle.count { return "Every day" }
        let days = "\(workouts) day\(workouts == 1 ? "" : "s")"
        return cycle.count == 7 ? "\(days) a week" : "\(days) every \(cycle.count)"
    }

    /// The plan the bottom button would make active: the marked one, unless it is the active
    /// plan already or has been deleted since. Nil is no button — with the active plan's own
    /// circle marked there is nothing to confirm.
    static func toUse(marked: UUID?, activePlanId: UUID?, plans: [Plan]) -> Plan? {
        guard let marked, marked != activePlanId else { return nil }
        return plans.first { $0.id == marked }
    }

    /// The button's words, which say what it does: "Use Upper Lower".
    static func useTitle(_ plan: Plan) -> String { "Use \(plan.name)" }
}

extension RepeatBlock {
    /// D78 (v1.9, §4.3): a square of the repeat block, where D59's chips were — the day's colour,
    /// its name beneath, and the entry Next up would start named in ink.
    struct Square: Equatable {
        /// The day's colour; nil (grey) for rest.
        var colour: DayColour?
        /// The day's name, or "Rest".
        var name: String
        /// A weekday plan's weekday above its square, "Mon"; nil on a rotation.
        var weekday: String?
        var isNow: Bool
    }

    /// A rotation's repeat block as written, with the entry Next up would start marked (as the
    /// chip was highlighted); a weekday plan's Monday to Sunday, none marked, as since v1.1. The
    /// colours are `DayColour.cycle(of:)`'s, the squares the Plans list's symbol draws.
    static func squares(_ plan: Plan, today: Date = Date(), calendar: Calendar = .current) -> [Square] {
        let colours = DayColour.cycle(of: plan)
        switch plan.schedule {
        case .rotation:
            let now = PlanSchedule.nextInPattern(plan, today: today, calendar: calendar)?.cycleIndex
            return chips(plan).enumerated().map { offset, name in
                Square(colour: colours[offset], name: name, weekday: nil, isNow: offset == now)
            }
        case .weekday:
            return Weekday.allCases.enumerated().map { offset, weekday in
                Square(colour: colours[offset], name: plan.days.first { $0.weekday == weekday }?.name ?? "Rest",
                       weekday: WeekdayText.short(weekday), isNow: false)
            }
        }
    }
}

/// D78 (v1.9, §4.3): the plan's page lists the whole cycle again as rows, repeats included (the
/// owner's 16) — a day, closed until tapped, or a rest with nothing to open — so the view opens
/// what it is handed. The same day twice is two rows opening the same exercises.
enum PlanPage {
    struct Row: Equatable, Identifiable {
        /// Its place on the page: the view keeps which rows are open by it, never stored.
        var id: Int
        var colour: DayColour?
        /// The day's name, or "Rest".
        var name: String
        /// A weekday plan's weekday, "Monday"; nil on a rotation.
        var weekday: String?
        /// The day the row opens; nil for a rest.
        var dayIndex: Int?
    }

    /// A rotation's cycle as written, an entry naming no day a rest as the projection draws it
    /// (§6.12); a weekday plan's Monday to Sunday. Then every day the cycle never reaches, in
    /// the plan's order, so nothing the page could do before is out of reach (the owner's 30).
    static func rows(_ plan: Plan) -> [Row] {
        var rows: [Row] = []
        func append(_ dayIndex: Int?, weekday: Weekday? = nil) {
            rows.append(Row(id: rows.count, colour: dayIndex.map { DayColour.of(dayIndex: $0) },
                            name: dayIndex.map { plan.days[$0].name } ?? "Rest",
                            weekday: weekday.map(WeekdayText.full), dayIndex: dayIndex))
        }
        switch plan.schedule {
        case .rotation:
            for entry in plan.cycle {
                if case let .day(index) = entry, plan.days.indices.contains(index) { append(index) } else { append(nil) }
            }
        case .weekday:
            for weekday in Weekday.allCases {
                append(plan.days.firstIndex { $0.weekday == weekday }, weekday: weekday)
            }
        }
        let reached = Set(rows.compactMap(\.dayIndex))
        for index in plan.days.indices where !reached.contains(index) { append(index) }
        return rows
    }
}

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
        let days = "\(TargetText.counted(workouts, "day"))"
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

    /// F2 (2026-09-24): a swipe's question before an exercise leaves the plan — "Delete Bench
    /// Press from Push?" — nil when the address has gone since.
    static func deleteExercise(_ plan: Plan, day: Int, exercise: Int) -> String? {
        guard let named = plan.days[safe: day], let gone = named.exercises[safe: exercise] else { return nil }
        return "Delete \(gone.name) from \(named.name)?"
    }
}

/// D96 (v1.12 L3): one place of a plan's cycle as a screen draws it — a square of the plan's
/// page (§4.3, D78, D86) or of Add plan's review (§6.63, D91), and a row of either page. The one
/// projection behind all three, which each had a struct of its own.
struct CycleSquare: Equatable, Identifiable {
    /// Its place: in the cycle, then — on a page's rows — after it. The view keeps which rows are
    /// open by it, never stored.
    var id: Int
    /// The day's colour; nil (grey) for rest.
    var colour: DayColour?
    /// The day's name, or "Rest".
    var name: String
    /// A weekday plan's weekday — "Mon" above a square, "Monday" beside a row (`WeekdayText`);
    /// nil on a rotation.
    var weekday: Weekday?
    /// The day the place opens; nil for a rest.
    var dayIndex: Int?
    /// D91 (v1.11): a day a plan built day by day has not filled yet, on Add plan's review.
    var hollow = false
    /// The entry Next up would start, named in ink on the plan's page (as the chip was
    /// highlighted); a rotation's only.
    var isNow = false
    /// D86 (v1.10, §6.59): the entry today falls on, outlined in ink on the plan's page as the
    /// calendar outlines today — a rotation's by its anchor, a weekday plan's by the weekday.
    var isToday = false

    /// A rotation's cycle as written, an entry naming no day a rest as the projection draws it
    /// (§6.12); a weekday plan's Monday to Sunday, each weekday's day. `DayColour.cycle(of:)` is
    /// its colours, the squares the Plans list's symbol draws.
    static func of(_ plan: Plan) -> [CycleSquare] {
        let places: [(dayIndex: Int?, weekday: Weekday?)]
        switch plan.schedule {
        case .rotation:
            places = plan.cycleDays.map { ($0, nil) }
        case .weekday:
            places = Weekday.allCases.map { weekday in (plan.days.firstIndex { $0.weekday == weekday }, weekday) }
        }
        return places.enumerated().map { offset, place in
            CycleSquare(id: offset, colour: place.dayIndex.map { DayColour.of(dayIndex: $0) },
                        name: place.dayIndex.map { plan.days[$0].name } ?? "Rest",
                        weekday: place.weekday, dayIndex: place.dayIndex)
        }
    }
}

extension RepeatBlock {
    /// D78 (v1.9, §4.3): the repeat block as squares, where D59's chips were — the day's colour,
    /// its name beneath — a rotation's with the entry Next up would start marked, a weekday
    /// plan's Monday to Sunday with none, as since v1.1; and today's entry outlined (D86).
    static func squares(_ plan: Plan, today: Date = Date(), calendar: Calendar = .current) -> [CycleSquare] {
        var squares = CycleSquare.of(plan)
        switch plan.schedule {
        case .rotation:
            let now = PlanSchedule.nextInPattern(plan, today: today, calendar: calendar)?.cycleIndex
            let todays = PlanSchedule.entry(plan, on: today, today: today, calendar: calendar)?.cycleIndex
            for index in squares.indices {
                squares[index].isNow = index == now
                squares[index].isToday = index == todays
            }
        case .weekday:
            let todays = Weekday(today, calendar: calendar)
            for index in squares.indices { squares[index].isToday = squares[index].weekday == todays }
        }
        return squares
    }
}

/// D78 (v1.9, §4.3): the plan's page lists the whole cycle again as rows, repeats included (the
/// owner's 16) — a day, closed until tapped, or a rest with nothing to open — so the view opens
/// what it is handed. The same day twice is two rows opening the same exercises.
enum PlanPage {
    /// The cycle's squares as rows (`CycleSquare.of`), then every day the cycle never reaches, in
    /// the plan's order, so nothing the page could do before is out of reach (the owner's 30).
    static func rows(_ plan: Plan) -> [CycleSquare] {
        var rows = CycleSquare.of(plan)
        let reached = Set(rows.compactMap(\.dayIndex))
        for index in plan.days.indices where !reached.contains(index) {
            rows.append(CycleSquare(id: rows.count, colour: DayColour.of(dayIndex: index),
                                    name: plan.days[index].name, dayIndex: index))
        }
        return rows
    }
}

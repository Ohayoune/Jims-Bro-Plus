import Foundation

/// SPEC §6.44 (D70, v1.8): the week as a strip. Seven small squares under the day's name — the
/// next seven days, today first — each in its day's colour (§6.41) and grey for a rest day,
/// drawn from the same projection the calendar draws (D37: Today and the grid can never
/// disagree). A tap on a square is what **Another day** was: the card shows that day, and the
/// button says *when*, so nobody has to count squares.
///
/// Nothing here is stored. The strip is a function of the plan, the sessions and the date; the
/// square the view is showing is the view's own value and dies with the process.
enum WeekStrip {
    /// Seven: a week, whatever the plan's cycle length — the page dots under a carousel.
    static let count = 7

    /// One square. `dayIndex` and `dayName` are nil on a rest day, or a day the plan says
    /// nothing about; `colour` is the day's — or, on today's square after today's workout,
    /// that workout's, as the calendar draws it.
    struct Square: Equatable {
        /// Days from today: 0 is today, 1 tomorrow.
        var offset: Int
        var dayIndex: Int? = nil
        var dayName: String? = nil
        var colour: DayColour? = nil
        /// "Today", "Tomorrow", then the weekday in full — the words the button uses.
        var when: String
        // D72/D74 (v1.9, §6.46): the swap's marks. Q2 draws them.
        /// A date whose slot is not the pattern's carries a dot under the square, in the
        /// pattern's colour — grey when the pattern said rest (`original` nil).
        var hasDot = false
        var original: DayColour? = nil
        /// A borrowed or own day (D76): outlined, not filled.
        var outline = false
        /// The question the date carries: pulsing while it asks, faint once answered.
        var ring: Ring = .none
        /// The swap on this date, if one was written; `PlanLibrary.question(for:now:)` reads it.
        var swapId: UUID? = nil

        /// A grey square: nothing to start on this day.
        var isRest: Bool { dayName == nil }
        /// What VoiceOver reads for the square: "Today, Push", "Tomorrow, rest" — and
        /// "Wednesday, Push, question" while the ring asks.
        var spoken: String {
            "\(when), \(dayName ?? "rest")" + (ring == .asking ? ", question" : "")
        }
    }

    /// The yellow ring of a question (D74): none, pulsing while unanswered, faint once answered.
    enum Ring: Equatable { case none, asking, answered }

    /// The seven squares, today first. A weekday plan's come from its days' weekdays and a
    /// rotation's from the anchored projection — both by way of `CalendarProjection`, so the
    /// strip is the grid's own row of days. With no plan, or a plan with no day to schedule,
    /// seven grey squares.
    static func days(plan: Plan?, sessions: [Session], swaps: [DaySwap], today: Date,
                     calendar: Calendar = .current) -> [Square] {
        let run = CalendarProjection.next(days: count, from: today, activePlan: plan,
                                          sessions: sessions, swaps: swaps, today: today,
                                          calendar: calendar)
        return (0..<count).map { offset in
            let entry = run[safe: offset]?.entry ?? .none
            var square = Square(offset: offset,
                                when: when(offset: offset,
                                           weekday: weekday(offset: offset, today: today, calendar: calendar)))
            square.colour = plan.flatMap { entry.dayColour(plans: [$0]) }
            switch entry {
            case let .projected(_, dayIndex):
                square.dayIndex = dayIndex
                square.dayName = plan?.days[safe: dayIndex]?.name
            case let .completed(sessions):
                // Today's square once today's workout is done: the calendar labels the day
                // with the workout, and so does the strip. The day's index is found as its
                // colour is (§6.41), by name in the plan as it is now.
                guard let session = sessions.first else { break }
                square.dayName = session.dayName
                square.dayIndex = plan?.days.firstIndex { normalized($0.name) == normalized(session.dayName) }
            case let .own(day):
                // D76: a day written just for this date — named, outlined, in no plan.
                square.dayName = day.name
                square.outline = true
            case .rest, .none:
                break
            }
            // D72 (v1.9, §6.46): the marks of a swap, from the same slots the squares are.
            if let plan,
               let date = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: today)) {
                let base = PlanSchedule.base(plan, on: date, today: today, calendar: calendar)
                let slot = PlanSchedule.slot(plan, on: date, swaps: swaps, today: today, calendar: calendar)
                if let swap = PlanSchedule.swap(plan, on: date, swaps: swaps, calendar: calendar) {
                    square.swapId = swap.id
                    if swap.isQuestion { square.ring = swap.answered ? .answered : .asking }
                    if slot != base {
                        square.hasDot = true
                        if case let .day(index) = base { square.original = DayColour.of(dayIndex: index) }
                    }
                }
                if case .borrowed = slot { square.outline = true }
            }
            return square
        }
    }

    /// The button's words for a square: "Start Today's Push", "Start Tomorrow's Pull", "Start
    /// Friday's Legs" (D70's words, `HomeStart.startTitle`) — and for a grey square "No
    /// exercise Today" / "Tomorrow" / "Friday", the button that does nothing (D71).
    static func buttonTitle(dayName: String?, offset: Int, weekday: Weekday?) -> String {
        guard let dayName else { return "No exercise \(when(offset: offset, weekday: weekday))" }
        return HomeStart.startTitle(dayName: dayName, daysAway: offset, weekday: weekday)
    }

    /// "Today", "Tomorrow", then the weekday in full: the strip never reaches a day a weekday
    /// would misname (D55 — past six days a weekday names this week's).
    static func when(offset: Int, weekday: Weekday?) -> String {
        switch offset {
        case 0: return "Today"
        case 1: return "Tomorrow"
        default: return weekday.map(WeekdayText.full) ?? "in \(offset) days"
        }
    }

    /// The weekday `offset` days from today, in the calendar's own zone.
    static func weekday(offset: Int, today: Date, calendar: Calendar = .current) -> Weekday? {
        guard let date = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: today))
        else { return nil }
        let value = calendar.component(.weekday, from: date)
        return Weekday.allCases.first { $0.calendarValue == value }
    }
}

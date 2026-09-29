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
        /// D74 (v1.9, §6.48): the dot in words — "was Push", or "was rest" when the pattern
        /// said rest — for the long press's callout and VoiceOver. Nil without a dot.
        var was: String? = nil
        /// D76 (v1.9, §6.50): the plan whose day the square is — the active plan's, or for a
        /// borrowed day the plan it came from. Nil on a rest day and on an own day.
        var planId: UUID? = nil
        /// D76: a day written just for this date, in no plan; the card starts it as it is.
        var own: Day? = nil

        /// A grey square: nothing to start on this day.
        var isRest: Bool { dayName == nil }
        /// D74: what a long press on the square does.
        var hold: Hold { ring != .none ? .question : (hasDot ? .was : .tap) }
        /// What VoiceOver reads for the square: "Today, Push", "Tomorrow, rest" — and
        /// "Wednesday, Push, question" while the ring asks.
        var spoken: String {
            "\(when), \(dayName ?? "rest")" + (ring == .asking ? ", question" : "")
        }
    }

    /// The yellow ring of a question (D74): none, pulsing while unanswered, faint once answered.
    enum Ring: Equatable { case none, asking, answered }

    /// D74 (v1.9, §6.48): a long press reopens a ringed square's question, shows what a dotted
    /// square's day was, and is a tap anywhere else — never a double tap, which fights the
    /// single tap and VoiceOver's activate gesture.
    enum Hold: Equatable { case question, was, tap }

    /// The seven squares, today first. A weekday plan's come from its days' weekdays and a
    /// rotation's from the anchored projection — both by way of `CalendarProjection`, so the
    /// strip is the grid's own row of days. With no plan, or a plan with no day to schedule,
    /// seven grey squares.
    ///
    /// D76 (v1.9, §6.50): `plans` are every plan a borrowed day can come from — the library's;
    /// the active plan is counted among them whether or not it is passed.
    static func days(plan: Plan?, plans: [Plan] = [], sessions: [Session], swaps: [DaySwap], today: Date,
                     calendar: Calendar = .current) -> [Square] {
        let known = plan.map { active in plans.contains { $0.id == active.id } ? plans : plans + [active] } ?? []
        let run = CalendarProjection.next(days: count, from: today, activePlan: plan, plans: known,
                                          sessions: sessions, swaps: swaps, today: today,
                                          calendar: calendar)
        return (0..<count).map { offset in
            let entry = run[safe: offset]?.entry ?? .none
            var square = Square(offset: offset,
                                when: when(offset: offset,
                                           weekday: weekday(offset: offset, today: today, calendar: calendar)))
            square.colour = entry.dayColour(plans: known)
            switch entry {
            case let .projected(planId, dayIndex):
                // D76: a borrowed day is named, as it is coloured, by the plan it came from.
                square.dayIndex = dayIndex
                square.planId = planId
                square.dayName = known.first { $0.id == planId }?.days[safe: dayIndex]?.name
            case let .completed(sessions):
                // Today's square once today's workout is done: the calendar labels the day
                // with the workout, and so does the strip. The day's index is found as its
                // colour is (§6.41), by name in its plan as it is now.
                guard let session = sessions.first else { break }
                let owner = known.first { $0.id == session.planId } ?? plan
                square.dayName = session.dayName
                square.planId = owner?.id
                square.dayIndex = owner?.dayIndex(named: session.dayName)
            case let .own(day):
                // D76: a day written just for this date — named, outlined, in no plan.
                square.dayName = day.name
                square.outline = true
                square.own = day
            case .rest, .none:
                break
            }
            // D72 (v1.9, §6.46): the marks of a swap, from the same slots the squares are.
            var isDone = false
            if case .completed = entry { isDone = true }
            if let plan,
               let date = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: today)) {
                let base = PlanSchedule.base(plan, on: date, today: today, calendar: calendar)
                let slot = PlanSchedule.slot(plan, on: date, swaps: swaps, today: today, calendar: calendar)
                if let swap = PlanSchedule.swap(plan, on: date, swaps: swaps, calendar: calendar) {
                    square.swapId = swap.id
                    // D74 (§6.48): a date whose workout is done asks nothing — no answer could
                    // change it — so its ring goes; its dot stays, which is still true.
                    if swap.isQuestion, !isDone { square.ring = swap.answered ? .answered : .asking }
                    if slot != base {
                        square.hasDot = true
                        if case let .day(index) = base {
                            square.original = DayColour.of(dayIndex: index)
                            square.was = plan.days[safe: index].map { "was \($0.name)" }
                        } else {
                            square.was = "was rest"
                        }
                    }
                }
                // D76 (§6.50): a borrowed or own day is outlined, done or not.
                switch slot {
                case .borrowed, .own: square.outline = true
                case .day, .rest, .none: break
                }
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

    /// The start of the day `offset` days from today — the date a square is — in the calendar's
    /// own zone. D76: the date Change *day*'s exercises changes.
    static func date(offset: Int, today: Date, calendar: Calendar = .current) -> Date? {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: today))
    }

    /// The weekday `offset` days from today, in the calendar's own zone.
    static func weekday(offset: Int, today: Date, calendar: Calendar = .current) -> Weekday? {
        guard let date = date(offset: offset, today: today, calendar: calendar) else { return nil }
        return Weekday(date, calendar: calendar)
    }
}

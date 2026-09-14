import Foundation

/// `rest` is a scheduled rest day (a `.rest` cycle entry, or a weekday with no Day); `none` is a day
/// the active plan says nothing about — beyond the projection horizon, in the past, or with no plan.
/// `own` (D76, v1.9) is a day written just for that date by a swap (§6.46): planned, in no plan.
enum DayEntry: Equatable {
    case completed([Session]), projected(planId: UUID, dayIndex: Int), rest, none, own(Day)
}
struct CalendarDay: Equatable { var date: Date; var entry: DayEntry }

/// D65 (v1.7, §6.41): a calendar day's colour — a planned day's is its day's; a finished day's
/// is its first workout's, the one its label names. A rest day, or a day the plan says nothing
/// about, has none.
extension DayEntry {
    func dayColour(plans: [Plan]) -> DayColour? {
        switch self {
        case let .completed(sessions): return sessions.first.flatMap { DayColour.of(session: $0, plans: plans) }
        case let .projected(_, dayIndex): return DayColour.of(dayIndex: dayIndex)
        // An own day is in no plan's day list, so it has no colour: drawn in ink (§6.46).
        case .rest, .none, .own: return nil
        }
    }
}

extension DayColour {
    /// D65 (v1.7, §6.41): a workout's colour is its day's, in its plan as the plan is now —
    /// found by the plan's id and the day's name, as the calendar finds its label. None when
    /// the plan is gone or no longer has the day: nothing is stored, so nothing else says.
    static func of(session: Session, plans: [Plan]) -> DayColour? {
        guard let plan = plans.first(where: { $0.id == session.planId }),
              let index = plan.days.firstIndex(where: { normalized($0.name) == normalized(session.dayName) })
        else { return nil }
        return of(dayIndex: index)
    }

    /// D75 (v1.9, §6.49): a plan's cycle as colours — a square per entry, its day's colour and
    /// nil for rest — for the ···'s Change plan and, from Q6 (D78), the Plans list. A rotation's
    /// is its repeat block as written, from its first entry rather than from today: the plan's
    /// shape, where the strip is this week. A weekday plan's is Monday to Sunday, as Plan detail
    /// lays it out, a weekday with no day nil. An entry pointing at a day the plan no longer
    /// has is nil, as the projection draws it (§6.12).
    static func cycle(of plan: Plan) -> [DayColour?] {
        switch plan.schedule {
        case .rotation:
            return plan.cycle.map { entry in
                guard case let .day(index) = entry, plan.days.indices.contains(index) else { return nil }
                return of(dayIndex: index)
            }
        case .weekday:
            return Weekday.allCases.map { weekday in
                plan.days.firstIndex { $0.weekday == weekday }.map { of(dayIndex: $0) }
            }
        }
    }
}

/// SPEC §4.1 (D38, v1.2): what a calendar cell says. v1.1 drew every day as a dot of the same
/// size — filled, outlined or grey — so a month of training looked like a month of anything
/// else, and "the spacing between exercises is not perfectly clear" was the owner's way of
/// saying the pattern could not be read off the grid. A cell now names its day and a rest day
/// is drawn as a visible gap rather than as another dot.
enum CalendarText {
    /// The short label under the number: the day's name, cut to what fits a 44 pt cell.
    static func label(_ entry: DayEntry, plans: [Plan], sessions: [Session] = []) -> String? {
        switch entry {
        case let .completed(sessions):
            guard let session = sessions.first else { return nil }
            let plan = plans.first { $0.id == session.planId }
            return short(session.dayName, among: plan?.days.map(\.name) ?? [])
        case let .projected(planId, dayIndex):
            guard let plan = plans.first(where: { $0.id == planId }),
                  let day = plan.days[safe: dayIndex] else { return nil }
            return short(day.name, among: plan.days.map(\.name))
        case let .own(day):
            return short(day.name)
        case .rest, .none:
            return nil
        }
    }

    /// "Push" from "Push", "Upper" from "Upper Body", "Leg…" from "Legs and Core".
    static func short(_ name: String) -> String {
        first(of: name).count <= 5 ? first(of: name) : String(first(of: name).prefix(4)) + "…"
    }

    /// D55 (v1.6): a label that tells the plan's days apart. The first word cut every name to
    /// its beginning, so Full Body A and Full Body B were both "Full…" and Upper A and Upper B
    /// both "Uppe…". Now: the first word when this is the only day of the plan that starts
    /// with it; else the initials of every word ("FBA" / "FBB", "UA" / "LB", "D1" / "D2");
    /// else the day's number in the plan. A name the plan does not hold keeps the plain rule.
    static func short(_ name: String, among names: [String]) -> String {
        guard names.count > 1,
              let index = names.firstIndex(where: { normalized($0) == normalized(name) }) else {
            return short(name)
        }
        let mine = first(of: name).lowercased()
        if names.filter({ first(of: $0).lowercased() == mine }).count == 1 { return short(name) }
        let letters = initials(of: name)
        if !letters.isEmpty, names.filter({ initials(of: $0) == letters }).count == 1 { return letters }
        return String(index + 1)
    }

    private static func first(of name: String) -> String {
        name.split(separator: " ").first.map(String.init) ?? name
    }

    /// "FBA" for "Full Body A", "D1" for "Day 1"; at most five characters, like the first word.
    private static func initials(of name: String) -> String {
        String(name.split(separator: " ").compactMap { $0.first }.map { String($0).uppercased() }.joined().prefix(5))
    }

    /// What VoiceOver reads for a cell, since the visual language is dots and four-letter labels.
    static func spoken(_ day: CalendarDay, plans: [Plan], calendar: Calendar = .current) -> String {
        let date = day.date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        switch day.entry {
        case let .completed(sessions):
            let names = sessions.map(\.dayName).joined(separator: ", ")
            return "\(date). Done: \(names)"
        case .projected:
            let name = label(day.entry, plans: plans) ?? "a workout"
            return "\(date). Planned: \(name)"
        case let .own(own):
            return "\(date). Planned: \(own.name)"
        case .rest: return "\(date). Rest day"
        case .none: return date
        }
    }

    /// SPEC §4.10 (D63, v1.7): the one line under the grid for a tapped day. A finished day's
    /// line is the way into it (D39) and carries the sessions it opens; a planned or rest day's
    /// is text and opens nothing — the calendar is History's now and a workout starts on Today,
    /// so v1.1's **Start this** on today's line is gone. "planned", where v1.1 said
    /// "projected": the word VoiceOver already read. A day the plan says nothing about has no line.
    static func line(_ day: CalendarDay, plans: [Plan], calendar: Calendar = .current) -> DayLine? {
        let style = Date.FormatStyle(locale: calendar.locale ?? .autoupdatingCurrent,
                                     calendar: calendar, timeZone: calendar.timeZone)
        let stamp = day.date.formatted(style.weekday(.abbreviated).day())
        switch day.entry {
        case let .completed(sessions):
            guard let session = sessions.first else { return nil }
            let length = HomeActivity.duration(SessionStats.duration(session))
            return DayLine(text: "\(stamp) · \(session.dayName) · \(length)", sessions: sessions)
        case let .projected(planId, dayIndex):
            guard let name = plans.first(where: { $0.id == planId })?.days[safe: dayIndex]?.name
            else { return nil }
            return DayLine(text: "\(stamp) · \(name) · planned", sessions: [])
        case let .own(own):
            return DayLine(text: "\(stamp) · \(own.name) · planned", sessions: [])
        case .rest:
            return DayLine(text: "\(stamp) · Rest day", sessions: [])
        case .none:
            return nil
        }
    }
}

/// A tapped day's line and the finished workouts it opens — none for a planned or a rest day,
/// whose line is text, not a button (D63).
struct DayLine: Equatable { var text: String; var sessions: [Session] }

enum CalendarProjection {
    /// D72 (v1.9, §6.46): `swaps` has no default on any of the three, so no caller can forget
    /// them and the compiler is the pin (TQ12).
    static func entries(month: Date, activePlan: Plan?, sessions: [Session], swaps: [DaySwap],
                        today: Date, calendar: Calendar = .current) -> [CalendarDay] {
        guard let monthInterval = calendar.dateInterval(of:.month,for:month), let days = calendar.range(of:.day,in:.month,for:month) else { return [] }
        let startToday = calendar.startOfDay(for:today)
        let completed = Dictionary(grouping:sessions.filter { $0.endedAt != nil }, by: { calendar.startOfDay(for:$0.startedAt) })
        return days.compactMap { number in
            guard let date = calendar.date(byAdding:.day,value:number-1,to:monthInterval.start) else { return nil }
            let offset = calendar.dateComponents([.day],from:startToday,to:date).day ?? 0
            if offset <= 0, let sessions = completed[date], !sessions.isEmpty { return CalendarDay(date:date,entry:.completed(sessions.sorted { $0.startedAt < $1.startedAt })) }
            guard offset >= 0 && offset <= PlanSchedule.horizonDays, let plan = activePlan else { return CalendarDay(date:date,entry:.none) }
            // Today is painted too — Home says "Next up · Pull" for today, and the grid has
            // to agree. The exception is the anchor day itself when something *was*
            // completed on it: that day is done, not planned. A plan that has completed
            // nothing has no such day, so its pattern starts today.
            // D37 (v1.2): projected from the plan's anchor date, so the pattern is nailed to
            // the calendar. v1.1 counted forward from *today*, which meant a missed workout
            // slid every later day by one — and by one more for each further day missed.
            // A rest-free cycle is painted for the whole horizon now: with an anchor it is
            // a real repeating pattern rather than a guess about tomorrow.
            if plan.schedule == .rotation, PlanSchedule.position(plan) != nil,
               date <= PlanSchedule.anchorDay(plan, today: today, calendar: calendar) {
                return CalendarDay(date: date, entry: .none)
            }
            // D72 (v1.9, §6.46): one slot per date — the weekday's day, the anchored cycle's
            // entry, or the swap written over it — read from the same function Today's card
            // and the missed rule read.
            let entry: DayEntry
            switch PlanSchedule.slot(plan, on: date, swaps: swaps, today: today, calendar: calendar) {
            case let .day(d): entry = .projected(planId: plan.id, dayIndex: d)
            case .rest: entry = .rest
            case let .own(day): entry = .own(day)
            // Q4 (D76) hands the projection the other plans; until then a borrowed day is a
            // day the grid cannot name.
            case .borrowed: entry = .none
            case .none: entry = .none
            }
            return CalendarDay(date:date,entry:entry)
        }
    }
    /// SPEC §6.44 (D70, v1.8): a run of `count` days from `start`, for Today's week strip — the
    /// same entries as `entries(month:)`, across a month boundary, so the strip and the grid can
    /// never disagree (D37). `today` is the calendar's today, as for `entries`; the run usually
    /// starts there.
    static func next(days count: Int, from start: Date, activePlan: Plan?, sessions: [Session],
                     swaps: [DaySwap], today: Date, calendar: Calendar = .current) -> [CalendarDay] {
        let first = calendar.startOfDay(for: start)
        guard count > 0,
              let last = calendar.date(byAdding: .day, value: count - 1, to: first) else { return [] }
        var all = entries(month: first, activePlan: activePlan, sessions: sessions, swaps: swaps,
                          today: today, calendar: calendar)
        if !calendar.isDate(first, equalTo: last, toGranularity: .month) {
            all += entries(month: last, activePlan: activePlan, sessions: sessions, swaps: swaps,
                           today: today, calendar: calendar)
        }
        return (0..<count).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: first) else { return nil }
            return all.first { calendar.isDate($0.date, inSameDayAs: day) }
                ?? CalendarDay(date: day, entry: .none)
        }
    }

    /// SPEC §4.10 (D18, v1.1): the seven days of the calendar week containing `date`, so the
    /// strip and the week's line under it describe the same days — Home's until v1.7, History's
    /// since (D63). Same entries as `entries(month:)`.
    static func week(containing date: Date, activePlan: Plan?, sessions: [Session], swaps: [DaySwap],
                     today: Date, calendar: Calendar = .current) -> [CalendarDay] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return [] }
        let month = entries(month: interval.start, activePlan: activePlan, sessions: sessions,
                            swaps: swaps, today: today, calendar: calendar)
        // A week straddling a month boundary needs both months' entries.
        let next = calendar.date(byAdding: .day, value: 7, to: interval.start).map {
            entries(month: $0, activePlan: activePlan, sessions: sessions, swaps: swaps,
                    today: today, calendar: calendar)
        } ?? []
        let all = month + next
        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: interval.start) else { return nil }
            return all.first { calendar.isDate($0.date, inSameDayAs: day) }
                ?? CalendarDay(date: day, entry: .none)
        }
    }
}

import Foundation

/// `rest` is a scheduled rest day (a `.rest` cycle entry, or a weekday with no Day); `none` is a day
/// the active plan says nothing about — beyond the projection horizon, in the past, or with no plan.
enum DayEntry: Equatable { case completed([Session]), projected(planId: UUID, dayIndex: Int), rest, none }
struct CalendarDay: Equatable { var date: Date; var entry: DayEntry }

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
            return sessions.first.map { short($0.dayName) }
        case let .projected(planId, dayIndex):
            guard let plan = plans.first(where: { $0.id == planId }),
                  let day = plan.days[safe: dayIndex] else { return nil }
            return short(day.name)
        case .rest, .none:
            return nil
        }
    }

    /// "Push" from "Push", "Upper" from "Upper Body", "Leg…" from "Legs and Core".
    static func short(_ name: String) -> String {
        let first = name.split(separator: " ").first.map(String.init) ?? name
        return first.count <= 5 ? first : String(first.prefix(4)) + "…"
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
        case .rest: return "\(date). Rest day"
        case .none: return date
        }
    }
}
enum CalendarProjection {
    static func entries(month: Date, activePlan: Plan?, sessions: [Session], today: Date, calendar: Calendar = .current) -> [CalendarDay] {
        guard let monthInterval = calendar.dateInterval(of:.month,for:month), let days = calendar.range(of:.day,in:.month,for:month) else { return [] }
        let startToday = calendar.startOfDay(for:today)
        let completed = Dictionary(grouping:sessions.filter { $0.endedAt != nil }, by: { calendar.startOfDay(for:$0.startedAt) })
        return days.compactMap { number in
            guard let date = calendar.date(byAdding:.day,value:number-1,to:monthInterval.start) else { return nil }
            let offset = calendar.dateComponents([.day],from:startToday,to:date).day ?? 0
            if offset <= 0, let sessions = completed[date], !sessions.isEmpty { return CalendarDay(date:date,entry:.completed(sessions.sorted { $0.startedAt < $1.startedAt })) }
            guard offset >= 0 && offset <= 62, let plan = activePlan else { return CalendarDay(date:date,entry:.none) }
            var entry: DayEntry = .none
            if plan.schedule == .weekday {
                // A weekday plan names every training day, so the remaining weekdays are rest days.
                if let d = plan.days.firstIndex(where: { $0.weekday?.calendarValue == calendar.component(.weekday,from:date) }) {
                    entry = .projected(planId:plan.id,dayIndex:d)
                } else { entry = .rest }
            } else if !plan.cycle.isEmpty,
                      PlanSchedule.position(plan) == nil
                        || date > PlanSchedule.anchorDay(plan, today: today, calendar: calendar) {
                // Today is painted too — Home says "Next up · Pull" for today, and the grid has
                // to agree. The exception is the anchor day itself when something *was*
                // completed on it: that day is done, not planned. A plan that has completed
                // nothing has no such day, so its pattern starts today.
                // D37 (v1.2): projected from the plan's anchor date, so the pattern is nailed to
                // the calendar. v1.1 counted forward from *today*, which meant a missed workout
                // slid every later day by one — and by one more for each further day missed.
                // A rest-free cycle is painted for the whole horizon now: with an anchor it is
                // a real repeating pattern rather than a guess about tomorrow.
                switch PlanSchedule.entry(plan, on: date, today: today, calendar: calendar)?.entry {
                case let .day(d) where plan.days.indices.contains(d):
                    entry = .projected(planId:plan.id,dayIndex:d)
                case .rest: entry = .rest
                // A cycle entry pointing at a day that no longer exists is broken, not a rest day.
                default: entry = .none
                }
            }
            return CalendarDay(date:date,entry:entry)
        }
    }
    /// SPEC §4.1 (D18, v1.1): the seven days of the calendar week containing `date`, so Home's
    /// strip and its "this week" line describe the same days. Same entries as `entries(month:)`.
    static func week(containing date: Date, activePlan: Plan?, sessions: [Session], today: Date,
                     calendar: Calendar = .current) -> [CalendarDay] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return [] }
        let month = entries(month: interval.start, activePlan: activePlan, sessions: sessions,
                            today: today, calendar: calendar)
        // A week straddling a month boundary needs both months' entries.
        let next = calendar.date(byAdding: .day, value: 7, to: interval.start).map {
            entries(month: $0, activePlan: activePlan, sessions: sessions, today: today,
                    calendar: calendar)
        } ?? []
        let all = month + next
        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: interval.start) else { return nil }
            return all.first { calendar.isDate($0.date, inSameDayAs: day) }
                ?? CalendarDay(date: day, entry: .none)
        }
    }
}

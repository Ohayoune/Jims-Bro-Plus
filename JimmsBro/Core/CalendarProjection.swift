import Foundation

/// `rest` is a scheduled rest day (a `.rest` cycle entry, or a weekday with no Day); `none` is a day
/// the active plan says nothing about — beyond the projection horizon, in the past, or with no plan.
enum DayEntry: Equatable { case completed([Session]), projected(planId: UUID, dayIndex: Int), rest, none }
struct CalendarDay: Equatable { var date: Date; var entry: DayEntry }
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
            } else if offset > 0 && !plan.cycle.isEmpty {
                if plan.cycle.contains(.rest) {
                    let position = plan.cyclePosition.flatMap { plan.cycle.indices.contains($0) ? $0 : nil } ?? -1
                    let index = (position + offset) % plan.cycle.count
                    switch plan.cycle[index] {
                    case let .day(d) where plan.days.indices.contains(d): entry = .projected(planId:plan.id,dayIndex:d)
                    case .rest: entry = .rest
                    // A cycle entry pointing at a day that no longer exists is broken, not a rest day.
                    default: entry = .none
                    }
                } else if offset == 1, let next = PlanSchedule.next(plan)?.dayIndex {
                    // A rest-free cycle would paint every day, so only tomorrow is projected
                    // and the rest of the month stays blank rather than becoming rest days.
                    entry = .projected(planId:plan.id,dayIndex:next)
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

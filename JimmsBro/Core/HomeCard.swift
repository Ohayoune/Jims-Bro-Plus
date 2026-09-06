import Foundation

/// The Home start card of SPEC §4.1, resolved without any view code so the card's wording
/// and its Start target are testable.
enum StartCard: Equatable {
    case noPlan
    case inProgress(dayName: String, elapsed: TimeInterval)
    /// Rotation: the next `.day` entry in the cycle.
    case nextUp(planId: UUID, dayIndex: Int, dayName: String)
    /// Weekday plan, and today has a day.
    case today(planId: UUID, dayIndex: Int, dayName: String)
    /// Weekday plan, nothing today: name the next day that has one.
    case restDay(planId: UUID, dayIndex: Int, dayName: String, weekday: Weekday?, daysAway: Int)
    /// A plan exists but no day can be resolved from it (an empty cycle, say).
    case nothingScheduled

    static func current(library: PlanLibrary, now: Date = Date(), calendar: Calendar = .current) -> StartCard {
        if let engine = library.engine, engine.phase != .completed {
            return .inProgress(dayName: engine.session.dayName, elapsed: engine.elapsed(now: now))
        }
        guard let plan = library.activePlan else { return .noPlan }
        if plan.schedule == .weekday {
            guard let (dayIndex, daysAway) = PlanSchedule.weekday(plan, today: now, calendar: calendar),
                  let day = plan.days[safe: dayIndex] else { return .nothingScheduled }
            return daysAway == 0
                ? .today(planId: plan.id, dayIndex: dayIndex, dayName: day.name)
                : .restDay(planId: plan.id, dayIndex: dayIndex, dayName: day.name,
                           weekday: day.weekday, daysAway: daysAway)
        }
        guard let next = PlanSchedule.next(plan), let day = plan.days[safe: next.dayIndex] else {
            return .nothingScheduled
        }
        return .nextUp(planId: plan.id, dayIndex: next.dayIndex, dayName: day.name)
    }

    /// The day this card's primary button would start, if any.
    var target: (planId: UUID, dayIndex: Int)? {
        switch self {
        case let .nextUp(planId, dayIndex, _), let .today(planId, dayIndex, _),
             let .restDay(planId, dayIndex, _, _, _):
            return (planId, dayIndex)
        case .noPlan, .inProgress, .nothingScheduled:
            return nil
        }
    }

    /// The one line above the button. SPEC §4.1 spells each of these out.
    var title: String {
        switch self {
        case .noPlan: return "No plan yet"
        case let .inProgress(dayName, elapsed):
            return "\(dayName) in progress · \(Int(elapsed) / 60) min"
        case let .nextUp(_, _, dayName): return "Next up · \(dayName)"
        case let .today(_, _, dayName): return "Today · \(dayName)"
        case let .restDay(_, _, dayName, weekday, _):
            guard let weekday else { return "Rest day · next \(dayName)" }
            return "Rest day · next \(dayName), \(WeekdayText.short(weekday))"
        case .nothingScheduled: return "Nothing scheduled"
        }
    }

    var buttonTitle: String? {
        switch self {
        case .noPlan: return "Import"
        case .inProgress: return "Resume"
        case .nextUp, .today, .restDay: return "Start"
        case .nothingScheduled: return nil
        }
    }
}

enum WeekdayText {
    static func short(_ weekday: Weekday) -> String {
        switch weekday {
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        case .sunday: return "Sun"
        }
    }
    static func full(_ weekday: Weekday) -> String { weekday.rawValue.capitalized }
}

/// The chips under Plan detail's repeat block (SPEC §4.3).
enum RepeatBlock {
    static func chips(_ plan: Plan) -> [String] {
        plan.cycle.map { entry in
            guard case let .day(index) = entry, let day = plan.days[safe: index] else { return "Rest" }
            return day.name
        }
    }
    static func caption(_ plan: Plan) -> String? {
        guard !plan.cycle.isEmpty else { return nil }
        return plan.schedule == .weekday ? "Every week" : "repeats every \(plan.cycle.count) days"
    }
    /// The highlighted chip: the entry Next up would start, not the last completed one.
    static func highlighted(_ plan: Plan) -> Int? {
        plan.schedule == .weekday ? nil : PlanSchedule.next(plan)?.cycleIndex
    }
}

/// SPEC §4.1 (D18, revised v1.1): Home leads with the workout. The start card names the day and
/// the plan, previews the exercises, and its button says what it will do. Resolved here, without
/// view code, so the wording per schedule state is a unit test (O63) rather than a screenshot.
struct HomeStart: Equatable {
    /// The day, big: "Push", "Rest day", "No plan yet".
    var title: String
    /// "Push Pull Legs · 5 exercises · 48 min last time" — each fragment only when it has data.
    var subtitle: String?
    /// The day's first few exercise names, so Start is never blind.
    var exercises: [String]
    /// The exercises not listed, e.g. 2 for "and 2 more".
    var more: Int
    /// "Start Push", "Resume Push · 23 min", "Start Pull early", "Add plan".
    var buttonTitle: String?
    /// The day the button would start, and that Preview would open.
    var planId: UUID?
    var dayIndex: Int?
    var isInProgress: Bool
    /// No plan at all: Home offers the two onboarding imports instead of a preview.
    var isEmpty: Bool

    static let previewLimit = 5

    static func current(library: PlanLibrary, now: Date = Date(), calendar: Calendar = .current) -> HomeStart {
        let card = StartCard.current(library: library, now: now, calendar: calendar)
        var start = HomeStart(title: card.title, exercises: [], more: 0,
                              isInProgress: false, isEmpty: false)

        switch card {
        case .noPlan:
            start.title = "No plan yet"
            start.subtitle = "Get one from a chatbot, or try the sample."
            start.buttonTitle = "Add plan"
            start.isEmpty = true
            return start

        case let .inProgress(dayName, elapsed):
            start.title = dayName
            start.subtitle = "In progress"
            start.buttonTitle = "Resume \(dayName) · \(Int(elapsed) / 60) min"
            start.isInProgress = true
            return start

        case .nothingScheduled:
            start.title = "Nothing scheduled"
            start.subtitle = "This plan has no day to start. Open it in Plans to check its repeat block."
            return start

        case let .nextUp(planId, dayIndex, dayName), let .today(planId, dayIndex, dayName):
            start.title = dayName
            start.buttonTitle = "Start \(dayName)"
            start.planId = planId
            start.dayIndex = dayIndex

        case let .restDay(planId, dayIndex, dayName, weekday, _):
            // The day itself is the headline even on a rest day: the button starts it early.
            start.title = "Rest day"
            start.buttonTitle = "Start \(dayName) early"
            start.planId = planId
            start.dayIndex = dayIndex
            let when = weekday.map { ", \(WeekdayText.short($0))" } ?? ""
            start.subtitle = "\(dayName) is next\(when)"
        }

        guard let plan = library.plans.first(where: { $0.id == start.planId }),
              let index = start.dayIndex, let day = plan.days[safe: index] else { return start }
        let names = day.exercises.map(\.name)
        start.exercises = Array(names.prefix(previewLimit))
        start.more = max(0, names.count - previewLimit)

        var fragments: [String] = []
        if start.subtitle == nil { fragments.append(plan.name) }
        if !day.exercises.isEmpty {
            fragments.append("\(day.exercises.count) exercise\(day.exercises.count == 1 ? "" : "s")")
        }
        if let last = lastDuration(dayName: day.name, sessions: library.sessions) {
            fragments.append("\(last) min last time")
        }
        // A rest day already used the subtitle to say what is next; the rest hangs off that.
        start.subtitle = ([start.subtitle].compactMap { $0 } + fragments).joined(separator: " · ")
        if start.subtitle?.isEmpty == true { start.subtitle = nil }
        return start
    }

    /// Whole minutes of the most recent completed session of this day name.
    private static func lastDuration(dayName: String, sessions: [Session]) -> Int? {
        let matching = sessions
            .filter { $0.endedAt != nil && normalized($0.dayName) == normalized(dayName) }
            .max { $0.startedAt < $1.startedAt }
        guard let matching else { return nil }
        let minutes = Int(SessionStats.duration(matching)) / 60
        return minutes > 0 ? minutes : nil
    }
}

/// SPEC §4.1 (D18, v1.1): the one activity line that replaced the tap-to-cycle sparkline.
/// "This week" is the calendar week containing today, so the words and the week strip above it
/// describe the same seven days.
enum HomeActivity {
    static func line(sessions: [Session], now: Date = Date(), calendar: Calendar = .current) -> String {
        let week = sessions.filter { session in
            session.endedAt != nil
                && calendar.isDate(session.startedAt, equalTo: now, toGranularity: .weekOfYear)
        }
        guard !week.isEmpty else { return "No workouts yet this week" }
        let seconds = week.reduce(0.0) { $0 + SessionStats.duration($1) }
        return "\(week.count) workout\(week.count == 1 ? "" : "s") this week · \(duration(seconds))"
    }

    /// "48 min", "1 h 32 min", "2 h".
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds) / 60)
        guard minutes >= 60 else { return "\(minutes) min" }
        let remainder = minutes % 60
        return remainder == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(remainder) min"
    }
}

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
    /// D76 (v1.9, §6.50): a day written just for a date, which no plan holds — started as it
    /// is, as the active plan's session under its own name.
    case own(planId: UUID, day: Day, daysAway: Int, weekday: Weekday?)

    static func current(library: PlanLibrary, now: Date = Date(), calendar: Calendar = .current) -> StartCard {
        if let engine = library.engine, engine.phase != .completed {
            return .inProgress(dayName: engine.session.dayName, elapsed: engine.elapsed(now: now))
        }
        guard let plan = library.activePlan else { return .noPlan }
        // D37 (v1.2): the same anchored projection the calendar draws, so "Next up" and the
        // ring on the grid can never disagree — which is half of why v1.1 felt clunky. D72
        // (v1.9, §6.46): with the swaps read, on both schedules, so a swapped day is the card's
        // as it is the strip's.
        guard let next = PlanSchedule.next(plan, today: now, swaps: library.swaps, calendar: calendar)
        else { return .nothingScheduled }
        // And it says *when*, which v1.1 never did for a rotation: the card read "Next up ·
        // Push" whether Push was today or three rest days away, while the grid drew it on a
        // day you had to count to.
        let daysAway = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                               to: next.date).day ?? 0
        let weekday = Weekday(next.date, calendar: calendar)
        // D76 (v1.9, §6.50): a borrowed day is its own plan's day, started as that plan's; a
        // day written just for the date is in no plan, and has a case of its own.
        let target: (planId: UUID, dayIndex: Int, day: Day)
        switch next.slot {
        case let .day(index):
            guard let found = plan.days[safe: index] else { return .nothingScheduled }
            target = (plan.id, index, found)
        case let .borrowed(otherId, name):
            guard let found = library.borrowed(planId: otherId, name: name) else { return .nothingScheduled }
            target = found
        case let .own(own):
            return .own(planId: plan.id, day: own, daysAway: daysAway, weekday: weekday)
        case .rest, .none:
            return .nothingScheduled
        }
        guard daysAway > 0 else {
            return plan.schedule == .weekday
                ? .today(planId: target.planId, dayIndex: target.dayIndex, dayName: target.day.name)
                : .nextUp(planId: target.planId, dayIndex: target.dayIndex, dayName: target.day.name)
        }
        return .restDay(planId: target.planId, dayIndex: target.dayIndex, dayName: target.day.name,
                        weekday: weekday, daysAway: daysAway)
    }

    /// The day the schedule points at, if any — today's, or on a rest day the next. Since v1.8
    /// (D71) Today's button starts nothing on a rest day (`HomeStart` has no target there); the
    /// screenshot runs' `startFromCard` still reach the next workout through this.
    var target: (planId: UUID, dayIndex: Int)? {
        switch self {
        case let .nextUp(planId, dayIndex, _), let .today(planId, dayIndex, _),
             let .restDay(planId, dayIndex, _, _, _):
            return (planId, dayIndex)
        // D76: an own day has no index in any plan; `PlanLibrary.startOwnDay` starts it.
        case .noPlan, .inProgress, .nothingScheduled, .own:
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
        case let .own(_, day, daysAway, weekday):
            guard daysAway > 0 else { return "Today · \(day.name)" }
            guard let weekday else { return "Rest day · next \(day.name)" }
            return "Rest day · next \(day.name), \(WeekdayText.short(weekday))"
        }
    }

    var buttonTitle: String? {
        switch self {
        case .noPlan: return "Import"
        case .inProgress: return "Resume"
        case .nextUp, .today, .restDay, .own: return "Start"
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

/// D96 (v1.12 L3): a month's name. The app speaks English whatever the phone's language (§2,
/// "English only"), so the names are a fixed list, as `WeekdayText`'s are — where a formatter in
/// the phone's language put "17. Sept." or "Freitag" beside English words.
enum MonthText {
    private static let names = ["January", "February", "March", "April", "May", "June", "July",
                                "August", "September", "October", "November", "December"]
    /// "September": the month `date` falls in, in `calendar`'s zone.
    static func full(_ date: Date, calendar: Calendar) -> String {
        names[safe: calendar.component(.month, from: date) - 1] ?? ""
    }
    /// "Sep".
    static func short(_ date: Date, calendar: Calendar) -> String { String(full(date, calendar: calendar).prefix(3)) }
}

/// Plan detail's repeat block (SPEC §4.3): its caption, and its squares (`RepeatBlock.squares`).
enum RepeatBlock {
    static func caption(_ plan: Plan) -> String? {
        guard !plan.cycle.isEmpty else { return nil }
        return plan.schedule == .weekday ? "Every week" : "repeats every \(plan.cycle.count) days"
    }
    /// The highlighted chip: the entry Next up would start, not the last completed one.
    static func highlighted(_ plan: Plan, today: Date, calendar: Calendar = .current) -> Int? {
        plan.schedule == .weekday ? nil : PlanSchedule.nextInPattern(plan, today: today, calendar: calendar)?.cycleIndex
    }
}

/// SPEC §4.1 (D18, revised v1.1; D61, v1.7; D69, v1.8): Today is the day's card and nothing
/// else. The card names the day, lists its exercises with their sets, carries at most one
/// message, and its button says what it will do and when. Resolved here, without view code, so
/// the wording per schedule state is a unit test (O63) rather than a screenshot — and since
/// v1.7 the one message and the ··· items are chosen here too (T1, T2): the view stops deciding
/// either. Since v1.8 (D69) a day's card carries no sentence: every fact on it is also a mark —
/// a colour, a clock, a block per set — and the view draws what it is handed. And since D70 the
/// week is a strip of seven squares under the name, resolved here from the calendar's own
/// projection (`WeekStrip`), and a tapped square's card is resolved here too (`showing:`).
struct HomeStart: Equatable {
    /// The day, big: "Push", "No plan yet".
    var title: String
    /// D69 (v1.8): the one sentence under the title on the two cards that are not a day of the
    /// plan — the empty card's, whose words D57 chose for a stranger, and Nothing scheduled's.
    /// A day's card has none: v1.7's subtitle ("Push Pull Legs · 5 exercises · 48 min last
    /// time · step 3 of 8") became the clock, the blocks and the ···'s step line — which D75
    /// (v1.9) took out again: where a progression is, is History's Progression row's.
    var sentence: String?
    /// D69 (v1.8): the day's first few exercises, each with its sets, so Start is never blind.
    var rows: [PreviewRow]
    /// The exercises not listed, e.g. 2 for "and 2 more".
    var more: Int
    /// D69 (v1.8): the last finished workout of this day, for the meta row's clock — a fact
    /// about last time, never a forecast (D55). Nil with none, or with one under a minute.
    var lastDuration: TimeInterval?
    /// D69 (v1.8): how long the open session has run; the clock says "so far" instead.
    var elapsed: TimeInterval?
    /// "Start Today's Push" (D70's words, `startTitle`), "Resume Push · 23 min", "Choose a plan".
    var buttonTitle: String?
    /// The day the button would start: a plan's day by its index — since D76 (v1.9) the plan a
    /// borrowed day came from — or `ownDay`, a day written just for the date, on `planId`.
    var planId: UUID?
    var dayIndex: Int?
    var ownDay: Day?
    /// D76 (v1.9, §6.50): the square before the name is outlined, not filled — a borrowed day in
    /// its own plan's colour, an own day in ink: *not from this plan*.
    var isOutlined = false
    /// D65 (v1.7, §6.41): the colour of the day the card names, for the square before its
    /// name — the day's own on a workout or rest day, the running session's while one is open.
    /// Nil on the empty card, when nothing is scheduled, and for a session whose day is in no
    /// plan.
    var dayColour: DayColour?
    var isInProgress: Bool
    /// No plan at all: Today offers the built-in picker and the practice workout instead.
    var isEmpty: Bool
    /// D37 (v1.2): the training day the schedule put before today that never happened, said
    /// plainly rather than resolved behind your back. "Push was due Tuesday."
    var missed: MissedWorkout?
    /// D72 (v1.9, §6.46): the question the shown square's date carries, if it carries one —
    /// Q2's block under the strip.
    var question: SwapQuestion?
    /// D74 (v1.9, §6.48): the question's block stands where the rows would be — while the
    /// question asks, or once a long press reopened it — on a day's card, never on the card of
    /// an open session (the owner's 11).
    var showsQuestion = false
    /// D44 (v1.3): the plan's progression has run its course, so Today offers the next one.
    var progressionFinished = false
    /// D61 (v1.7): the one message line, chosen by priority — the missed workout, then the
    /// progression that has run its course, then notifications off — and never two at once.
    var message: Message?
    /// D61 (v1.7): the ··· items, in order. Empty means no ··· at all.
    var alternatives: [Alternative] = []
    /// D61 (v1.7): the exercise block is the preview, and this is what VoiceOver reads for it:
    /// "Exercises: …, and 2 more". D75 (v1.9, the owner's 13): the preview and nothing more —
    /// until then the block was a tappable row that opened the day in Plan detail, and the
    /// label ended "Opens Push"; the ··· is the way to the day now.
    var exerciseLabel: String?
    /// D61 (v1.7): the empty card's one quiet link, under the sentence.
    var link: String?
    /// D70 (v1.8, §6.44): the week as a strip — seven squares, today first, from the calendar's
    /// own projection. Empty on the empty card, which has no week to show.
    var strip: [WeekStrip.Square] = []
    /// D70 (v1.8): the square drawn larger — the day the card shows. 0 is today; the view's
    /// value, clamped to the strip, and never stored.
    var shownOffset = 0
    /// D71 (v1.8, §6.45): the card is a rest day's — a grey square, "Rest", the moon where the
    /// clock would be, the z's where the rows would be, and a disabled button. A tapped grey
    /// square's card (S2), and since S3 today's: on a rest day, and for the rest of a day whose
    /// workout is done.
    var isRest = false
    /// D69/D70/D71 (v1.8): the mark before the button's words — play on Start and Resume, a moon
    /// on the disabled "No exercise …", a check on the disabled "Done Today". None on Choose a
    /// plan, which opens a picker.
    var buttonMark: Mark?

    enum Mark: Equatable { case play, moon, check }

    /// The moon's button and the check's do nothing; every other button does.
    var buttonEnabled: Bool { buttonMark != .moon && buttonMark != .check }

    static let restTitle = "Rest"
    /// D71 (v1.8, §6.45, the owner's reading of 2026-09-13): the rest card's button once a
    /// workout was finished today, where "No exercise Today" would not be true.
    static let doneTitle = "Done Today"

    static let previewLimit = 5
    static let chooseButton = "Choose a plan"
    static let practiceLink = "Try a short practice workout"
    static let emptySentence = "Choose a built-in plan to start today, or have a chatbot write yours."

    /// D69 (v1.8): one exercise on the card — its name, and its sets drawn as blocks. A drop
    /// set is one block (a set is a set). `logged` is nil until a session is open, and then the
    /// engine's count of this exercise's logged sets, whose blocks fill.
    struct PreviewRow: Equatable {
        var name: String
        var sets: Int
        var logged: Int? = nil
    }

    /// D69 (v1.8): the meta row's clock — the minutes in ink, then the two grey words that say
    /// which minutes they are.
    struct Clock: Equatable {
        var minutes: String
        var caption: String
    }

    /// "23 min" *so far* while a session is open; otherwise "39 min" *last time*, when there
    /// was a last time. Nil means no clock at all.
    var clock: Clock? {
        if let elapsed { return Clock(minutes: "\(Int(elapsed) / 60) min", caption: "so far") }
        guard let lastDuration else { return nil }
        return Clock(minutes: "\(Int(lastDuration) / 60) min", caption: "last time")
    }

    /// D70 (v1.8): the button names *when*, so nobody has to count — "Start Today's Push",
    /// "Start Tomorrow's Pull", "Start Friday's Legs". Past six days a weekday would name this
    /// week's, which is not the day meant (D55), so the button says the day alone.
    static func startTitle(dayName: String, daysAway: Int, weekday: Weekday?) -> String {
        switch daysAway {
        case 0: return "Start Today's \(dayName)"
        case 1: return "Start Tomorrow's \(dayName)"
        case 2...6:
            if let weekday { return "Start \(WeekdayText.full(weekday))'s \(dayName)" }
        default: break
        }
        return "Start \(dayName)"
    }

    /// D76 (v1.9, §6.50): an own day's button. A nameless own day is called "Wednesday's own
    /// day", which already says when — "Start Wednesday's Wednesday's own day" would say it
    /// twice — so its button is "Start Wednesday's own day"; a named one says when, as every
    /// day does.
    static func ownStartTitle(_ day: Day, daysAway: Int, weekday: Weekday?) -> String {
        day.name.hasSuffix(DayChoices.ownSuffix)
            ? "Start \(day.name)" : startTitle(dayName: day.name, daysAway: daysAway, weekday: weekday)
    }

    /// A workout the schedule expected on a day that has no session on it.
    struct MissedWorkout: Equatable {
        /// The day's place in its plan; nil for an own day (D76), which `own` carries.
        var dayIndex: Int?
        var dayName: String
        var date: Date
        /// "Push was due Monday" — said, not silently rescheduled.
        var text: String
        /// D76 (v1.9, §6.50): the plan whose day it is — nil for the active plan's, a borrowed
        /// day's own plan otherwise — and a day written just for the date, which Do it now
        /// starts as it is.
        var planId: UUID? = nil
        var own: Day? = nil
    }

    /// D61 (v1.7): at most one of these is on the card. Each reads as it read in v1.6, with
    /// the actions it had; nothing joins this list without a decision.
    enum Message: Equatable {
        /// D37: "Push was due Monday" · Do it now · Dismiss.
        case missed(MissedWorkout)
        /// D44: "Your progression has run its course." · Plan the next one.
        case progressionFinished
        /// D57: notifications were declined, so alerts only sound while the app is open.
        case notificationsOff

        var text: String {
            switch self {
            case let .missed(missed): return missed.text
            case .progressionFinished: return "Your progression has run its course."
            case .notificationsOff:
                return "Notifications are off, so alerts only sound while the app is open."
            }
        }

        /// The message's own buttons, in order.
        var actions: [String] {
            switch self {
            case .missed: return ["Do it now", "Dismiss"]
            case .progressionFinished: return ["Plan the next one"]
            case .notificationsOff: return []
            }
        }
    }

    /// D61 (v1.7): the day's alternatives, which live in Today's ··· and nowhere else. D70
    /// (v1.8): Another day left — the strip is the way to another day, and its chooser is gone
    /// (§6.44). D75 (v1.9, §6.49): two items that speak in squares, each carrying what its
    /// symbol draws; Plan a progression left for History's Progression row (D67).
    enum Alternative: Hashable {
        /// The Plans list. Its symbol is the active plan's cycle, a square per entry in its
        /// day's colour and grey for rest (`DayColour.cycle(of:)`, drawn by `CycleSymbol`).
        case changePlan(cycle: [DayColour?])
        /// D75/D76 (v1.9): the shown day's exercises, for that date alone, with that day's
        /// square as its symbol — grey for rest, outlined for a borrowed or own day as the strip
        /// draws it. D85 (v1.10, §6.58): named after the day, "Change Push", "Change Rest".
        /// *(v1.9: by the strip's when, "Change Wednesday's exercises".)*
        case changeExercises(dayName: String, colour: DayColour?, outlined: Bool)
        /// D56: while a session is open, with its alert.
        case discardWorkout

        var title: String {
            switch self {
            case .changePlan: return "Change plan"
            case let .changeExercises(dayName, _, _): return DayChoices.title(dayName: dayName)
            case .discardWorkout: return "Discard workout"
            }
        }
    }

    /// - Parameters:
    ///   - notificationsOff: the permission was declined this run (D57), the lowest message.
    ///   - missedDismissed: Dismiss was tapped on the missed workout this run (D37), so the
    ///     next message in the order takes the line.
    ///   - showing: D70 (v1.8): the strip's square the view is showing — 0, today, unless one
    ///     was tapped. Clamped to the strip; with no plan there is no strip.
    ///   - reopened: D74 (v1.9): a long press on the shown square reopened its answered
    ///     question, so the block stands again with the current choice marked. The view's value,
    ///     as `showing` is, and never stored.
    static func current(library: PlanLibrary, now: Date = Date(), calendar: Calendar = .current,
                        notificationsOff: Bool = false, missedDismissed: Bool = false,
                        showing offset: Int = 0, reopened: Bool = false) -> HomeStart {
        let card = StartCard.current(library: library, now: now, calendar: calendar)
        var start = HomeStart(title: card.title, rows: [], more: 0,
                              isInProgress: false, isEmpty: false)
        let running = library.engine.map { $0.phase != .completed } ?? false

        // D70 (v1.8, §6.44): the strip is drawn from the first plan, from the same projection
        // the calendar draws, and every square of it is live — a deliberate exception to
        // §6.40's table, recorded there.
        if let plan = library.activePlan {
            start.strip = WeekStrip.days(plan: plan, plans: library.plans, sessions: library.sessions,
                                         swaps: library.swaps, today: now, calendar: calendar)
        }
        start.shownOffset = start.strip.isEmpty ? 0 : min(max(offset, 0), start.strip.count - 1)
        // D72/D74 (v1.9, §6.46, §6.48): the question the shown square's date carries, and
        // whether its block stands where the rows would — while it asks, or once reopened.
        if let id = start.strip[safe: start.shownOffset]?.swapId,
           let question = library.question(for: id, now: now) {
            start.question = question
            start.showsQuestion = !question.answered || reopened
        }

        // D37 (v1.2): the training day the schedule put before today that never happened, said
        // plainly rather than resolved behind your back. "Push was due Tuesday." About the plan,
        // not the day shown, so it is read whatever the square.
        if let plan = library.activePlan, plan.schedule == .rotation, library.engine == nil,
           let missed = PlanSchedule.missed(plan, sessions: library.sessions, swaps: library.swaps,
                                            today: now, calendar: calendar) {
            let name = WeekdayText.full(Weekday(missed.date, calendar: calendar))
            var workout = MissedWorkout(dayIndex: missed.dayIndex, dayName: missed.name,
                                        date: missed.date, text: "\(missed.name) was due \(name)")
            // D76 (v1.9, §6.50): Do it now starts a borrowed day as its own plan's, and a day
            // written just for the date as it is.
            switch missed.slot {
            case let .borrowed(otherId, dayName):
                if let found = library.borrowed(planId: otherId, name: dayName) {
                    workout.planId = found.planId
                    workout.dayIndex = found.dayIndex
                }
            case let .own(day):
                workout.own = day
            case .day, .rest, .none:
                break
            }
            start.missed = workout
        }

        if start.shownOffset > 0, let plan = library.activePlan,
           let square = start.strip[safe: start.shownOffset] {
            // D70 (v1.8): a tapped square — the card shows that day, and the button says when,
            // so nobody has to count squares. What Another day did from the ···, without the
            // chooser: the tap is the choice.
            let weekday = WeekStrip.weekday(offset: square.offset, today: now, calendar: calendar)
            start.buttonTitle = WeekStrip.buttonTitle(dayName: square.dayName, offset: square.offset,
                                                      weekday: weekday)
            if let own = square.own {
                // D76 (v1.9, §6.50): a day written just for this date — its name, its rows, a
                // square outlined in ink, and a button that starts it as it is.
                start.title = own.name
                start.buttonTitle = ownStartTitle(own, daysAway: square.offset, weekday: weekday)
                start.buttonMark = .play
                start.planId = plan.id
                start.ownDay = own
            } else {
                // D76: a borrowed day's plan is the one it came from.
                guard let index = square.dayIndex,
                      let owner = library.plans.first(where: { $0.id == (square.planId ?? plan.id) }),
                      let day = owner.days[safe: index] else {
                    // D71 (v1.8): a grey square's card says rest — the same card as today's.
                    return rest(start, doneToday: false, library: library, now: now, calendar: calendar,
                                notificationsOff: notificationsOff, missedDismissed: missedDismissed)
                }
                start.title = day.name
                start.buttonMark = .play
                start.planId = owner.id
                start.dayIndex = index
            }
        } else {
            switch card {
            case .noPlan:
                start.title = "No plan yet"
                // D46 (v1.4): the built-in picker took the sample's place. D61 (v1.7): two
                // choices where there were three — the button opens the picker, and the chatbot
                // and paste routes are one tap back inside it, where D57 already sends the
                // reader.
                start.sentence = emptySentence
                start.buttonTitle = chooseButton
                start.link = practiceLink
                start.isEmpty = true
                return start

            case let .inProgress(dayName, elapsed):
                start.title = dayName
                start.buttonTitle = "Resume \(dayName) · \(Int(elapsed) / 60) min"
                start.buttonMark = .play
                start.isInProgress = true
                // D74 (v1.9): what Today shows while a session is open is untouched (the owner's
                // 11) — the question waits on its square until the workout is over.
                start.showsQuestion = false
                // D69 (v1.8): the clock says "so far", and the blocks fill as sets are logged —
                // the card shows progress without a fraction, in the same zones as on any other
                // day.
                start.elapsed = elapsed
                if let session = library.engine?.session {
                    start.dayColour = DayColour.of(session: session, plans: library.plans)
                    preview(&start, rows: rows(of: session))
                }
                start.alternatives = alternatives(library: library, changing: nil, running: true)
                start.message = message(for: start, notificationsOff: notificationsOff,
                                        missedDismissed: missedDismissed)
                return start

            case .nothingScheduled:
                start.title = "Nothing scheduled"
                start.sentence = "This plan has no day to start. Open it in Plans to check its repeat block."
                // D70 (v1.8): seven grey squares and the disabled button; the ··· still offers
                // Change plan, the way to a plan with a day in it — and, with no day to change,
                // nothing else (D75).
                start.buttonTitle = WeekStrip.buttonTitle(dayName: nil, offset: 0, weekday: nil)
                start.buttonMark = .moon
                start.alternatives = alternatives(library: library, changing: nil, running: running)
                start.message = message(for: start, notificationsOff: notificationsOff,
                                        missedDismissed: missedDismissed)
                return start

            case let .nextUp(planId, dayIndex, dayName), let .today(planId, dayIndex, dayName):
                // D71 (v1.8, the owner's reading): once a workout was finished today, today says
                // so on every plan — a weekday plan's own day keeps its day after the workout,
                // and would otherwise offer the same workout again.
                if library.sessions.finished(on: now, calendar: calendar) {
                    return rest(start, doneToday: true, library: library, now: now, calendar: calendar,
                                notificationsOff: notificationsOff, missedDismissed: missedDismissed)
                }
                start.title = dayName
                start.buttonTitle = startTitle(dayName: dayName, daysAway: 0, weekday: nil)
                start.buttonMark = .play
                start.planId = planId
                start.dayIndex = dayIndex

            case let .own(planId, day, daysAway, _):
                // D76 (v1.9, §6.50): today's own day is today's card, as a plan's day is; one
                // on a later date leaves today a rest day (D71), one tap away on the strip.
                let done = library.sessions.finished(on: now, calendar: calendar)
                if daysAway > 0 || done {
                    return rest(start, doneToday: done, library: library, now: now, calendar: calendar,
                                notificationsOff: notificationsOff, missedDismissed: missedDismissed)
                }
                start.title = day.name
                start.buttonTitle = ownStartTitle(day, daysAway: 0, weekday: nil)
                start.buttonMark = .play
                start.planId = planId
                start.ownDay = day

            case .restDay:
                // D71 (v1.8, §6.45) reverses D57 on Today: a rest day says rest. From v1.6 the
                // card headlined the next workout ("Lower", **Start Lower**), because "Rest day"
                // was schedule-speak to someone standing in a gym; the strip is why the reversal
                // is safe — the next workout is one tap away on a square in its colour, whose
                // button says **Start Tomorrow's Lower**. `StartCard.restDay` keeps its payload;
                // the card just no longer starts it. A rotation re-anchors on the day its
                // workout is done, so the rest of that day lands here too — and then the button
                // says **Done Today** under a check, which is true (the owner's reading).
                return rest(start, doneToday: library.sessions.finished(on: now, calendar: calendar),
                            library: library, now: now, calendar: calendar,
                            notificationsOff: notificationsOff, missedDismissed: missedDismissed)
            }
        }

        guard let plan = library.plans.first(where: { $0.id == start.planId }),
              let day = start.ownDay ?? start.dayIndex.flatMap({ plan.days[safe: $0] }) else { return start }
        // D76 (v1.9, §6.50): an own day is in no plan's list, so it has no colour; it and a
        // borrowed day are outlined, as their squares on the strip are.
        start.dayColour = start.ownDay == nil ? start.dayIndex.map(DayColour.of(dayIndex:)) : nil
        start.isOutlined = start.strip[safe: start.shownOffset]?.outline ?? false
        // D69 (v1.8): a set is a block, and a drop set is one set — its drops are inside it.
        preview(&start, rows: day.exercises.map { PreviewRow(name: $0.name, sets: $0.sets.count) })
        start.lastDuration = lastDuration(dayName: day.name, sessions: library.sessions)
        // D44 (v1.3): when the progression has run its course, the message line offers the next
        // one — nothing else moves. D75 (v1.9, §6.49): where it is — "Step 3 of 8" (D53), "Week
        // 3 of 8" — is History's Progression row's, and so is D50's offer to plan one; Today's
        // ··· carries neither. The active plan's alone: a borrowed day's plan is not the one
        // whose next progression the message would plan (D76).
        if plan.id == library.activePlanId, let progression = plan.progression,
           progression.currentStep(dayName: day.name, on: now, calendar: calendar) == nil,
           progression.isFinished(on: now, calendar: calendar) {
            start.progressionFinished = true
        }
        // D61 (v1.7): the alternatives, in the order the ··· lists them (D75, §6.49): Change
        // plan, and Change *day* for the day shown — or Discard while a session is
        // open, reached here from a tapped square (D70).
        start.alternatives = alternatives(library: library, changing: start.strip[safe: start.shownOffset],
                                          running: running)
        start.message = message(for: start, notificationsOff: notificationsOff,
                                missedDismissed: missedDismissed)
        return start
    }

    /// D75 (v1.9, §6.49): the ··· items in their order — **Change plan**, its symbol the active
    /// plan's cycle, and **Change *day*** (D85) for the shown square's date, its symbol that
    /// day's square. While a session is open the menu is v1.8's, Change plan and Discard workout
    /// (D56) last, because nothing about a day changes from Today mid-workout (the owner's 11); a
    /// card with no day to change — Nothing scheduled, or today once its workout is done — has
    /// Change plan alone. No ··· at all until there is a plan (§6.40).
    private static func alternatives(library: PlanLibrary, changing square: WeekStrip.Square?,
                                     running: Bool) -> [Alternative] {
        guard Gates.changePlan(plans: library.plans) else { return [] }
        let changePlan = Alternative.changePlan(cycle: library.activePlan.map(DayColour.cycle(of:)) ?? [])
        if running { return [changePlan, .discardWorkout] }
        guard let square else { return [changePlan] }
        return [changePlan, .changeExercises(dayName: square.dayName ?? restTitle, colour: square.colour,
                                             outlined: square.outline)]
    }

    /// D71 (v1.8, §6.45): the card of a day with nothing to start, today's or a tapped grey
    /// square's — a grey square and "Rest", no rows, no clock and no target, and a button that
    /// does nothing: "No exercise Today" / "Tomorrow" / "Thursday" under a moon, or "Done Today"
    /// under a check once a workout was finished today. The ··· offers the date's exercises to
    /// change — a rest day can take a workout for that date (D75, D76) — but not once today's
    /// workout is done, when no change could be true; and the message is the plan's, not the
    /// day's (§6.44): a missed workout still speaks, and so does a progression that has run its
    /// course.
    private static func rest(_ card: HomeStart, doneToday: Bool, library: PlanLibrary, now: Date,
                             calendar: Calendar, notificationsOff: Bool,
                             missedDismissed: Bool) -> HomeStart {
        var start = card
        start.title = restTitle
        start.isRest = true
        let weekday = WeekStrip.weekday(offset: start.shownOffset, today: now, calendar: calendar)
        start.buttonTitle = doneToday
            ? doneTitle : WeekStrip.buttonTitle(dayName: nil, offset: start.shownOffset, weekday: weekday)
        start.buttonMark = doneToday ? .check : .moon
        start.progressionFinished = library.activePlan?.progression?.isFinished(on: now, calendar: calendar) ?? false
        start.alternatives = alternatives(library: library,
                                          changing: doneToday ? nil : start.strip[safe: start.shownOffset],
                                          running: library.engine.map { $0.phase != .completed } ?? false)
        start.message = message(for: start, notificationsOff: notificationsOff,
                                missedDismissed: missedDismissed)
        return start
    }

    /// The first five rows, the count of the rest, and what VoiceOver reads for the block — the
    /// preview and nothing more since D75, so the label no longer ends "Opens Push".
    private static func preview(_ start: inout HomeStart, rows: [PreviewRow]) {
        start.rows = Array(rows.prefix(previewLimit))
        start.more = max(0, rows.count - previewLimit)
        guard !start.rows.isEmpty else { return }
        var label = "Exercises: " + start.rows.map(\.name).joined(separator: ", ")
        if start.more > 0 { label += ", and \(start.more) more" }
        start.exerciseLabel = label
    }

    /// D61 (v1.7): one message, by priority. The missed workout first — it is the only one
    /// with a date on it — unless it was dismissed this run; then the progression that has run
    /// its course; then notifications off. Never two.
    private static func message(for start: HomeStart, notificationsOff: Bool,
                                missedDismissed: Bool) -> Message? {
        if let missed = start.missed, !missedDismissed { return .missed(missed) }
        if start.progressionFinished { return .progressionFinished }
        if notificationsOff { return .notificationsOff }
        return nil
    }

    /// D69 (v1.8): the open session's exercises with the engine's own count — a set is its
    /// first step, so a drop set is one, and it fills once that step is logged. Counted from
    /// the steps rather than the targets, so an exercise changed mid-workout (D42) shows the
    /// sets it actually has.
    private static func rows(of session: Session) -> [PreviewRow] {
        session.exercises.indices.map { index in
            let sets = session.steps.filter { $0.exerciseIndex == index && $0.dropIndex == 0 }
            return PreviewRow(name: session.exercises[index].name, sets: sets.count,
                              logged: sets.filter { $0.status == .logged }.count)
        }
    }

    /// The most recent completed session of this day name, if it lasted a minute or more.
    private static func lastDuration(dayName: String, sessions: [Session]) -> TimeInterval? {
        let matching = sessions
            .filter { $0.endedAt != nil && normalized($0.dayName) == normalized(dayName) }
            .max { $0.startedAt < $1.startedAt }
        guard let matching else { return nil }
        let duration = SessionStats.duration(matching)
        return duration >= 60 ? duration : nil
    }
}

/// SPEC §4.10 (D18, v1.1): the one activity line that replaced the tap-to-cycle sparkline — on
/// Home until v1.7, under History's calendar since (D63), where the name stayed. "This week" is
/// the calendar week containing today, so the words and the week strip above them describe the
/// same seven days.
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

/// D57 (v1.6): the Summary's one line about what comes next, from the same schedule the
/// calendar draws — read after the rotation has advanced, so "next" is never the day just done.
enum SummaryText {
    static func next(after session: Session, library: PlanLibrary, now: Date = Date(),
                     calendar: Calendar = .current) -> String? {
        guard let planId = session.planId,
              let plan = library.plans.first(where: { $0.id == planId }) else { return nil }
        let today = calendar.startOfDay(for: now)
        // The first day after today, on either schedule, swaps read (D72): today's is the one
        // just done, whether the pattern expected it or a swap now records it.
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
              let next = PlanSchedule.firstDay(plan, from: tomorrow, swaps: library.swaps,
                                               today: now, calendar: calendar),
              let name = next.slot.name(in: plan) else { return nil }
        let found = (name: name, date: next.date)
        let days = calendar.dateComponents([.day], from: today,
                                           to: calendar.startOfDay(for: found.date)).day ?? 0
        let when: String
        switch days {
        case 1: when = "tomorrow"
        // In English, in the calendar's own zone (D96, v1.12 L3): "Friday", "on 17 Sep".
        case 2...6: when = WeekdayText.full(Weekday(found.date, calendar: calendar))
        default:
            when = "on \(calendar.component(.day, from: found.date)) \(MonthText.short(found.date, calendar: calendar))"
        }
        return "Next: \(found.name), \(when)"
    }
}

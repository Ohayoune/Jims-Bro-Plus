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
        // D37 (v1.2): the same anchored projection the calendar draws, so "Next up" and the
        // ring on the grid can never disagree — which is half of why v1.1 felt clunky.
        guard let next = PlanSchedule.next(plan, today: now, calendar: calendar),
              let day = plan.days[safe: next.dayIndex] else {
            return .nothingScheduled
        }
        // And it says *when*, which v1.1 never did for a rotation: the card read "Next up ·
        // Push" whether Push was today or three rest days away, while the grid drew it on a
        // day you had to count to.
        let daysAway = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                               to: next.date).day ?? 0
        guard daysAway > 0 else {
            return .nextUp(planId: plan.id, dayIndex: next.dayIndex, dayName: day.name)
        }
        let weekday = Weekday.allCases.first { $0.calendarValue == calendar.component(.weekday, from: next.date) }
        return .restDay(planId: plan.id, dayIndex: next.dayIndex, dayName: day.name,
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
    /// time · step 3 of 8") became the clock, the blocks and the ···'s step line.
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
    /// D69 (v1.8): "Step 3 of 8" (D53) or "Week 3 of 8" (D44) — the one fragment of v1.7's
    /// subtitle with no mark to sit beside, so it is a line in the ···, not on the card. Only
    /// while the plan carries a progression that is still running.
    var stepLine: String?
    /// "Start Today's Push" (D70's words, `startTitle`), "Resume Push · 23 min", "Choose a plan".
    var buttonTitle: String?
    /// The day the button would start, and that Preview would open.
    var planId: UUID?
    var dayIndex: Int?
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
    /// D44 (v1.3): the plan's progression has run its course, so Today offers the next one.
    var progressionFinished = false
    /// D50 (v1.5): the quiet link to plan one — only when the plan has no progression and
    /// every exercise on this day has a logged session to plan from. "Not too obvious".
    var offersProgression = false
    /// D61 (v1.7): the one message line, chosen by priority — the missed workout, then the
    /// progression that has run its course, then notifications off — and never two at once.
    var message: Message?
    /// D61 (v1.7): the ··· items, in order. Empty means no ··· at all.
    var alternatives: [Alternative] = []
    /// D61 (v1.7): the exercise block is the preview — one tappable row that opens the day in
    /// Plan detail. This is what VoiceOver reads for it: "Exercises: …, and 2 more. Opens Push".
    var exerciseLabel: String?
    /// D61 (v1.7): the plan the exercise block opens. The card's `planId` while a day is ready;
    /// the running session's plan while one is in progress (Resume still goes to the session).
    var previewPlanId: UUID?
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

    /// A workout the schedule expected on a day that has no session on it.
    struct MissedWorkout: Equatable {
        var dayIndex: Int
        var dayName: String
        var date: Date
        /// "Push was due Monday" — said, not silently rescheduled.
        var text: String
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
    /// (§6.44).
    enum Alternative: Hashable {
        /// The Plans list.
        case changePlan
        /// D50: while the plan has none and every exercise on the day has history.
        case planProgression
        /// D56: while a session is open, with its alert.
        case discardWorkout

        var title: String {
            switch self {
            case .changePlan: return "Change plan"
            case .planProgression: return PromptText.planProgression
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
    static func current(library: PlanLibrary, now: Date = Date(), calendar: Calendar = .current,
                        notificationsOff: Bool = false, missedDismissed: Bool = false,
                        showing offset: Int = 0) -> HomeStart {
        let card = StartCard.current(library: library, now: now, calendar: calendar)
        var start = HomeStart(title: card.title, rows: [], more: 0,
                              isInProgress: false, isEmpty: false)
        let running = library.engine.map { $0.phase != .completed } ?? false

        // D70 (v1.8, §6.44): the strip is drawn from the first plan, from the same projection
        // the calendar draws, and every square of it is live — a deliberate exception to
        // §6.40's table, recorded there.
        if let plan = library.activePlan {
            start.strip = WeekStrip.days(plan: plan, sessions: library.sessions, today: now,
                                         calendar: calendar)
        }
        start.shownOffset = start.strip.isEmpty ? 0 : min(max(offset, 0), start.strip.count - 1)

        // D37 (v1.2): the training day the schedule put before today that never happened, said
        // plainly rather than resolved behind your back. "Push was due Tuesday." About the plan,
        // not the day shown, so it is read whatever the square.
        if let plan = library.activePlan, plan.schedule == .rotation, library.engine == nil,
           let missed = PlanSchedule.missed(plan, sessions: library.sessions, today: now,
                                            calendar: calendar),
           let day = plan.days[safe: missed.dayIndex] {
            let weekday = calendar.component(.weekday, from: missed.date)
            let name = calendar.weekdaySymbols[safe: weekday - 1] ?? "then"
            start.missed = MissedWorkout(dayIndex: missed.dayIndex, dayName: day.name,
                                         date: missed.date,
                                         text: "\(day.name) was due \(name)")
        }

        if start.shownOffset > 0, let plan = library.activePlan,
           let square = start.strip[safe: start.shownOffset] {
            // D70 (v1.8): a tapped square — the card shows that day, and the button says when,
            // so nobody has to count squares. What Another day did from the ···, without the
            // chooser: the tap is the choice.
            let weekday = WeekStrip.weekday(offset: square.offset, today: now, calendar: calendar)
            start.buttonTitle = WeekStrip.buttonTitle(dayName: square.dayName, offset: square.offset,
                                                      weekday: weekday)
            guard let index = square.dayIndex, let day = plan.days[safe: index] else {
                // D71 (v1.8): a grey square's card says rest — the same card as today's.
                return rest(start, doneToday: false, library: library, now: now, calendar: calendar,
                            notificationsOff: notificationsOff, missedDismissed: missedDismissed)
            }
            start.title = day.name
            start.buttonMark = .play
            start.planId = plan.id
            start.dayIndex = index
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
                // D69 (v1.8): the clock says "so far", and the blocks fill as sets are logged —
                // the card shows progress without a fraction, in the same zones as on any other
                // day.
                start.elapsed = elapsed
                if let session = library.engine?.session {
                    start.previewPlanId = library.plans.first { $0.id == session.planId }?.id
                    start.dayColour = DayColour.of(session: session, plans: library.plans)
                    preview(&start, rows: rows(of: session), dayName: dayName)
                }
                start.alternatives = alternatives(plans: library.plans, offersProgression: false,
                                                  running: true)
                start.message = message(for: start, notificationsOff: notificationsOff,
                                        missedDismissed: missedDismissed)
                return start

            case .nothingScheduled:
                start.title = "Nothing scheduled"
                start.sentence = "This plan has no day to start. Open it in Plans to check its repeat block."
                // D70 (v1.8): seven grey squares and the disabled button; the ··· still offers
                // Change plan, the way to a plan with a day in it.
                start.buttonTitle = WeekStrip.buttonTitle(dayName: nil, offset: 0, weekday: nil)
                start.buttonMark = .moon
                start.alternatives = alternatives(plans: library.plans, offersProgression: false,
                                                  running: running)
                start.message = message(for: start, notificationsOff: notificationsOff,
                                        missedDismissed: missedDismissed)
                return start

            case let .nextUp(planId, dayIndex, dayName), let .today(planId, dayIndex, dayName):
                // D71 (v1.8, the owner's reading): once a workout was finished today, today says
                // so on every plan — a weekday plan's own day keeps its day after the workout,
                // and would otherwise offer the same workout again.
                if trainedToday(library.sessions, now: now, calendar: calendar) {
                    return rest(start, doneToday: true, library: library, now: now, calendar: calendar,
                                notificationsOff: notificationsOff, missedDismissed: missedDismissed)
                }
                start.title = dayName
                start.buttonTitle = startTitle(dayName: dayName, daysAway: 0, weekday: nil)
                start.buttonMark = .play
                start.planId = planId
                start.dayIndex = dayIndex

            case .restDay:
                // D71 (v1.8, §6.45) reverses D57 on Today: a rest day says rest. From v1.6 the
                // card headlined the next workout ("Lower", **Start Lower**), because "Rest day"
                // was schedule-speak to someone standing in a gym; the strip is why the reversal
                // is safe — the next workout is one tap away on a square in its colour, whose
                // button says **Start Tomorrow's Lower**. `StartCard.restDay` keeps its payload;
                // the card just no longer starts it. A rotation re-anchors on the day its
                // workout is done, so the rest of that day lands here too — and then the button
                // says **Done Today** under a check, which is true (the owner's reading).
                return rest(start, doneToday: trainedToday(library.sessions, now: now, calendar: calendar),
                            library: library, now: now, calendar: calendar,
                            notificationsOff: notificationsOff, missedDismissed: missedDismissed)
            }
        }

        guard let plan = library.plans.first(where: { $0.id == start.planId }),
              let index = start.dayIndex, let day = plan.days[safe: index] else { return start }
        start.previewPlanId = plan.id
        start.dayColour = DayColour.of(dayIndex: index)
        // D69 (v1.8): a set is a block, and a drop set is one set — its drops are inside it.
        preview(&start, rows: day.exercises.map { PreviewRow(name: $0.name, sets: $0.sets.count) },
                dayName: day.name)
        start.lastDuration = lastDuration(dayName: day.name, sessions: library.sessions)
        // D44 (v1.3): where the progression is; and when it has run out, one line offering the
        // next — nothing else moves. D69 (v1.8): the where is the ···'s line, not the card's.
        if let progression = plan.progression {
            // D53 (v1.5): "Step 3 of 8" in performance mode — the lowest step among the day's
            // exercises still climbing — and "Week 3 of 8" in calendar mode.
            if let index = progression.currentStep(dayName: day.name, on: now, calendar: calendar) {
                start.stepLine = "\(ProgressionText.word(progression.mode)) \(index + 1) of \(progression.weeks)"
            } else if progression.isFinished(on: now, calendar: calendar) {
                start.progressionFinished = true
            }
        } else {
            // D50 (v1.5): the link appears only once there is something to plan from — a
            // logged session of every exercise on the day — and never shouts. A row of §6.40.
            start.offersProgression = Gates.planProgression(plan: plan, dayIndex: index,
                                                            sessions: library.sessions)
        }
        // D61 (v1.7): the alternatives, in the order the ··· lists them, each earned (D64,
        // §6.40): Change plan when there is a plan list, Plan a progression while D50 offers it,
        // and Discard while a session is open — reached here from a tapped square (D70).
        // Another day left with the strip (D70, §6.44).
        start.alternatives = alternatives(plans: library.plans, offersProgression: start.offersProgression,
                                          running: running)
        start.message = message(for: start, notificationsOff: notificationsOff,
                                missedDismissed: missedDismissed)
        return start
    }

    /// The ··· items in their order: Change plan (D64), Plan a progression (D50) and, while a
    /// session is open, Discard workout (D56) — last, and never the only item, since Change
    /// plan is there wherever there is a plan.
    private static func alternatives(plans: [Plan], offersProgression: Bool,
                                     running: Bool) -> [Alternative] {
        (Gates.changePlan(plans: plans) ? [.changePlan] : [])
            + (offersProgression ? [.planProgression] : [])
            + (running ? [.discardWorkout] : [])
    }

    /// D71 (v1.8, §6.45): the card of a day with nothing to start, today's or a tapped grey
    /// square's — a grey square and "Rest", no rows, no clock and no target, and a button that
    /// does nothing: "No exercise Today" / "Tomorrow" / "Thursday" under a moon, or "Done Today"
    /// under a check once a workout was finished today. The ··· has no day to plan a progression
    /// for, and the message is the plan's, not the day's (§6.44): a missed workout still speaks,
    /// and so does a progression that has run its course.
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
        start.alternatives = alternatives(plans: library.plans, offersProgression: false,
                                          running: library.engine.map { $0.phase != .completed } ?? false)
        start.message = message(for: start, notificationsOff: notificationsOff,
                                missedDismissed: missedDismissed)
        return start
    }

    /// A workout was finished today — the calendar's own test for a done day, so "Done Today"
    /// is said exactly when today's square carries a workout (§6.44).
    private static func trainedToday(_ sessions: [Session], now: Date, calendar: Calendar) -> Bool {
        sessions.contains { $0.endedAt != nil && calendar.isDate($0.startedAt, inSameDayAs: now) }
    }

    /// The first five rows, the count of the rest, and what VoiceOver reads for the block.
    private static func preview(_ start: inout HomeStart, rows: [PreviewRow], dayName: String) {
        start.rows = Array(rows.prefix(previewLimit))
        start.more = max(0, rows.count - previewLimit)
        guard !start.rows.isEmpty else { return }
        var label = "Exercises: " + start.rows.map(\.name).joined(separator: ", ")
        if start.more > 0 { label += ", and \(start.more) more" }
        if start.previewPlanId != nil { label += ". Opens \(dayName)" }
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
        var found: (name: String, date: Date)?
        if plan.schedule == .weekday {
            // The next weekday after today that has a day; today's is the one just done.
            let current = calendar.component(.weekday, from: now)
            for offset in 1...7 {
                let weekday = (current - 1 + offset) % 7 + 1
                if let day = plan.days.first(where: { $0.weekday?.calendarValue == weekday }),
                   let date = calendar.date(byAdding: .day, value: offset, to: today) {
                    found = (day.name, date)
                    break
                }
            }
        } else if let next = PlanSchedule.next(plan, today: now, calendar: calendar),
                  let day = plan.days[safe: next.dayIndex], next.date > today {
            found = (day.name, next.date)
        }
        guard let found else { return nil }
        let days = calendar.dateComponents([.day], from: today,
                                           to: calendar.startOfDay(for: found.date)).day ?? 0
        let when: String
        switch days {
        case 1: when = "tomorrow"
        case 2...6: when = formatted(found.date, template: "EEEE", calendar: calendar)
        default: when = "on " + formatted(found.date, template: "d MMM", calendar: calendar)
        }
        return "Next: \(found.name), \(when)"
    }

    /// "Friday" or "17 Sep", in the calendar's own zone and locale — `weekdaySymbols` on a
    /// calendar without a locale is not reliably the full name.
    private static func formatted(_ date: Date, template: String, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        // A calendar built from an identifier carries a nameless "fixed" locale that formats
        // "EEEE" as "Fri"; the device's current locale is the one that says "Friday".
        formatter.locale = calendar.locale.flatMap { $0.identifier.isEmpty ? nil : $0 } ?? .current
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}

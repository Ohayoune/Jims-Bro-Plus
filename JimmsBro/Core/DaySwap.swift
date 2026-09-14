import Foundation

/// SPEC §6.46 (D72, v1.9): **a day swapped, not a plan changed.**
///
/// v1.8 re-anchored a rotation the moment any workout finished (D37): do Wednesday's Legs on
/// Monday and tomorrow became whatever follows Legs, and the whole week slid. The owner called
/// that *changing the plan*. A swap is an override on two dates instead — today, and the day
/// whose workout was taken — with the pattern untouched: not the cycle, not `cyclePosition`,
/// not `cycleAnchor`. The taken day carries a **question** until it is answered, and is history
/// once its date is past.
///
/// One swap per date per plan. A day is named, not indexed (§6.9), so a plan whose days are
/// reordered keeps its swaps, and a renamed day loses its swap the way it loses its colour
/// (§6.41): a `.day` whose name is gone projects `.none`, as a dead cycle entry does (§6.12).
struct DaySwap: Codable, Equatable, Identifiable {
    /// What a date says. `.borrowed` and `.own` are written by Q4's picker (D76); `.slide` is
    /// D73's answer — no override, the re-anchored pattern decides.
    enum Slot: Equatable {
        case rest
        /// A day of the active plan, by normalised name (§6.9).
        case day(name: String)
        /// A day of another plan (D76).
        case borrowed(planId: UUID, name: String)
        /// A day written just for this date (D76).
        case own(Day)
        /// D73: the pattern carries on from the workout that was done.
        case slide
    }

    var id = UUID()
    /// The active plan when it was written.
    var planId: UUID
    /// The start of the local day it is about.
    var date: Date
    /// What the pattern said for that date: `.rest` or `.day`.
    var original: Slot
    /// What the date is now.
    var replacement: Slot
    /// The date whose off-day workout raised the question; nil when written from the picker.
    var askedOn: Date? = nil
    /// False while the ring pulses; true once an answer was chosen (the ring goes faint).
    var answered: Bool
    /// The position and anchor a slide replaced, so leaving the slide puts them back.
    var slideUndo: SlideUndo? = nil

    enum CodingKeys: String, CodingKey {
        case id, planId, date, original, replacement, askedOn, answered, slideUndo
    }

    /// A question, as opposed to today's own record of what happened.
    var isQuestion: Bool { askedOn != nil }
}

/// D73: what a slide replaced in the plan, kept so that choosing otherwise restores it.
struct SlideUndo: Codable, Equatable {
    var cyclePosition: Int?
    var cycleAnchor: Date?
}

/// On disk a slot is `{ "kind": "day", "name": "Legs" }` — a kind and the fields that kind
/// needs — rather than the synthesized `{ "day": { "name": … } }`, so `swaps.json` reads as
/// what it is, and an unknown kind is a corrupt file, not a silent rest day (§8.3).
extension DaySwap.Slot: Codable {
    private enum CodingKeys: String, CodingKey { case kind, name, planId, day }
    private enum Kind: String, Codable { case rest, day, borrowed, own, slide }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .rest: self = .rest
        case .day: self = .day(name: try container.decode(String.self, forKey: .name))
        case .borrowed:
            self = .borrowed(planId: try container.decode(UUID.self, forKey: .planId),
                             name: try container.decode(String.self, forKey: .name))
        case .own: self = .own(try container.decode(Day.self, forKey: .day))
        case .slide: self = .slide
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .rest: try container.encode(Kind.rest, forKey: .kind)
        case let .day(name):
            try container.encode(Kind.day, forKey: .kind)
            try container.encode(name, forKey: .name)
        case let .borrowed(planId, name):
            try container.encode(Kind.borrowed, forKey: .kind)
            try container.encode(planId, forKey: .planId)
            try container.encode(name, forKey: .name)
        case let .own(day):
            try container.encode(Kind.own, forKey: .kind)
            try container.encode(day, forKey: .day)
        case .slide: try container.encode(Kind.slide, forKey: .kind)
        }
    }
}

/// What a date is once the pattern and the swaps have both spoken (§6.46). `.none` is a date
/// the plan says nothing about: an empty cycle, a dead entry, a swap naming a day that left.
enum DaySlot: Equatable {
    case day(Int)
    case rest
    case own(Day)
    case borrowed(planId: UUID, name: String)
    case none

    /// The name the slot answers to — for matching a finished workout (§6.9) and for naming a
    /// missed day — or nil for rest and nothing.
    func name(in plan: Plan) -> String? {
        switch self {
        case let .day(index): return plan.days[safe: index]?.name
        case let .own(day): return day.name
        case let .borrowed(_, name): return name
        case .rest, .none: return nil
        }
    }

    /// Whether a workout named `dayName` is this slot's.
    func matches(_ dayName: String, in plan: Plan) -> Bool {
        name(in: plan).map { normalized($0) == normalized(dayName) } ?? false
    }

    /// The slot's colour (§6.41): a plan day's, by its place in the list; nil — grey — for rest
    /// and nothing, and for an own day, which is in no plan (D76). A borrowed day's colour is
    /// its own plan's, which the projection finds among the plans (§6.50); here it has none.
    var colour: DayColour? {
        if case let .day(index) = self { return DayColour.of(dayIndex: index) }
        return nil
    }
}

extension PlanSchedule {
    /// How far ahead the calendar paints, and the swap search looks (§6.12): two months.
    static let horizonDays = 62

    /// The pattern's own slot for a date, with no swap applied: a weekday plan's day for that
    /// weekday, or the anchored cycle's entry (D37). This is *base* in §6.46's three cases.
    static func base(_ plan: Plan, on date: Date, today: Date,
                     calendar: Calendar = .current) -> DaySlot {
        if plan.schedule == .weekday {
            let weekday = calendar.component(.weekday, from: date)
            if let index = plan.days.firstIndex(where: { $0.weekday?.calendarValue == weekday }) {
                return .day(index)
            }
            // A weekday plan names every training day, so the remaining weekdays are rest days.
            return .rest
        }
        switch entry(plan, on: date, today: today, calendar: calendar)?.entry {
        case let .day(index) where plan.days.indices.contains(index): return .day(index)
        case .rest: return .rest
        // A cycle entry pointing at a day that no longer exists is broken, not a rest day.
        default: return .none
        }
    }

    /// The plan's swap for a date, if one was written.
    static func swap(_ plan: Plan, on date: Date, swaps: [DaySwap],
                     calendar: Calendar = .current) -> DaySwap? {
        swaps.first { $0.planId == plan.id && calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// The projected slot for a date: the pattern's, unless a swap for this plan says
    /// otherwise. This is *slot* in §6.46's three cases, and what the calendar, the strip,
    /// Today's card and the missed rule all read — so none of them can disagree about a
    /// swapped day.
    static func slot(_ plan: Plan, on date: Date, swaps: [DaySwap], today: Date,
                     calendar: Calendar = .current) -> DaySlot {
        let base = base(plan, on: date, today: today, calendar: calendar)
        guard let swap = swap(plan, on: date, swaps: swaps, calendar: calendar) else { return base }
        return resolve(swap.replacement, in: plan, base: base)
    }

    /// A swap's slot as the projection reads it. `.day` by name, so a renamed day projects
    /// `.none`; `.slide` is the pattern, which the slide already re-anchored (D73).
    static func resolve(_ slot: DaySwap.Slot, in plan: Plan, base: DaySlot) -> DaySlot {
        switch slot {
        case .rest: return .rest
        case let .day(name):
            return plan.days.firstIndex { normalized($0.name) == normalized(name) }.map(DaySlot.day) ?? .none
        case let .borrowed(planId, name): return .borrowed(planId: planId, name: name)
        case let .own(day): return .own(day)
        case .slide: return base
        }
    }

    /// The first date at or after `start`, within the horizon, whose slot is a day to train —
    /// the pattern's or a swap's. `today` is the calendar's today, for the anchor (D37).
    static func firstDay(_ plan: Plan, from start: Date, swaps: [DaySwap], today: Date,
                         calendar: Calendar = .current) -> (date: Date, slot: DaySlot)? {
        let first = calendar.startOfDay(for: start)
        for offset in 0...horizonDays {
            guard let date = calendar.date(byAdding: .day, value: offset, to: first) else { continue }
            let slot = slot(plan, on: date, swaps: swaps, today: today, calendar: calendar)
            switch slot {
            case .rest, .none: continue
            case .day, .own, .borrowed: return (date, slot)
            }
        }
        return nil
    }

    /// The next day to train at or after `today`, swaps read (§6.46) — what Today's card and
    /// the Summary's "Next:" line show, from the same slots the strip and the grid draw. The
    /// anchor day is the day that was *done*, so for an anchored rotation the search starts
    /// after it (as `nextInPattern` does); a weekday plan's starts today.
    static func next(_ plan: Plan, today: Date, swaps: [DaySwap],
                     calendar: Calendar = .current) -> (date: Date, slot: DaySlot)? {
        var start = calendar.startOfDay(for: today)
        if plan.schedule == .rotation, position(plan) != nil,
           let after = calendar.date(byAdding: .day, value: 1,
                                     to: anchorDay(plan, today: today, calendar: calendar)) {
            start = max(start, after)
        }
        return firstDay(plan, from: start, swaps: swaps, today: today, calendar: calendar)
    }
}

/// D37, read with swaps (§6.46): the training day the projection put before today that has no
/// completed session on it. `dayIndex` is nil for an own or borrowed day (D76), which is named
/// by its own name; Today's card finds what Do it now starts (§6.50).
struct MissedDay: Equatable {
    var date: Date
    var slot: DaySlot
    var dayIndex: Int?
    var name: String
}

/// SPEC §6.46: the question a taken day carries — Wednesday's Legs was done on Monday; what is
/// Wednesday now? Core data for the block on Today (D74, §6.48): the heading, the options in
/// order with their squares, which is the default, what was chosen, and Slide's row.
struct SwapQuestion: Equatable {
    enum Kind: Equatable { case rest, todays, keep, slide }
    struct Option: Equatable {
        var kind: Kind
        var slot: DaySwap.Slot
        /// "Rest", the day's name, or "Slide" — the word beneath the option's square.
        var title: String
        /// The option completion wrote when it raised the question (today's day, or rest).
        var isDefault: Bool
        /// D74 (v1.9): the option's square — the day's colour (§6.41); nil is rest's grey.
        var colour: DayColour? = nil
        /// D74: what the date says now, marked with a check.
        var isChosen = false
    }

    /// D74 (v1.9): Slide's row beneath the squares — the date and the two after it as Slide
    /// would make them, so the choice is seen before it is made.
    struct SlidePreview: Equatable {
        /// Three squares; nil is grey, a rest day.
        var colours: [DayColour?]
        /// What VoiceOver reads for the row: "Slide: Push, Pull, Legs".
        var spoken: String
    }

    var swapId: UUID
    var date: Date
    /// The day whose workout was taken — what the pattern said for the date.
    var originalName: String
    /// D74: "Wednesday's Legs is done. Make Wednesday:"
    var heading: String
    var options: [Option]
    var chosen: DaySwap.Slot
    var answered: Bool
    /// D74: on rotations only, as Slide is (D73).
    var slide: SlidePreview?

    /// The options drawn as large squares with their word beneath: every one but Slide, which
    /// is its own row.
    var squares: [Option] { options.filter { $0.kind != .slide } }
    /// Slide's option, for its row's check and its answer.
    var slideOption: Option? { options.first { $0.kind == .slide } }
}

extension PlanLibrary {
    /// SPEC §6.46: what a finished workout does to the pattern and the swaps. For a session of
    /// plan P on date *d* with day *X*, with *base* the pattern's slot for *d* and *slot* the
    /// projected one:
    /// 1. *X* is *base* → the pattern re-anchors (D37, `PlanSchedule.advance`): a refresh of
    ///    the anchor that changes nothing on the grid.
    /// 2. *X* is *slot* but not *base* → nothing moves, nothing is written: it is what the date said.
    /// 3. otherwise → *d* is written (unless *base* was done on *d* already, in which case *d*
    ///    keeps what it has), and the next date whose slot is *X* is written with today's option
    ///    and a question.
    /// A rotation with nothing completed has no pattern on the calendar yet (D55): its first
    /// workout anchors it, whatever the day. A session of another plan writes nothing (the
    /// owner's 8), and `completeSession` never gets here for a discarded one.
    mutating func settle(_ completed: Session) {
        guard let planId = completed.planId,
              let index = plans.firstIndex(where: { $0.id == planId }) else { return }
        let plan = plans[index]
        let date = calendar.startOfDay(for: completed.startedAt)
        let done = completed.dayName
        // D76 (v1.9, §6.50): a day the active plan borrowed from this one was that date's, by
        // the picker — it moves neither plan and writes nothing.
        if isBorrowed(completed) { return }
        let base = PlanSchedule.base(plan, on: date, today: date, calendar: calendar)
        let slot = PlanSchedule.slot(plan, on: date, swaps: swaps, today: date, calendar: calendar)
        if base.matches(done, in: plan) {
            // Case 1: the pattern re-anchors to the day, at the entry it projected for it — a
            // refresh that changes nothing on the grid, even when the cycle holds the day
            // twice (`advance` would find the *next* matching entry and shift the week).
            if plan.schedule == .rotation,
               let (cycleIndex, _) = PlanSchedule.entry(plan, on: date, today: date, calendar: calendar) {
                plans[index].cyclePosition = cycleIndex
                plans[index].cycleAnchor = date
            }
            return
        }
        if plan.schedule == .rotation, plan.cycleAnchor == nil {
            // Nothing completed yet: the first workout anchors the pattern, whatever the day.
            PlanSchedule.advance(&plans[index], completedDayName: done, on: completed.startedAt,
                                 calendar: calendar)
            return
        }
        if slot.matches(done, in: plan) { return }
        guard planId == activePlanId,
              let dayIndex = plan.days.firstIndex(where: { normalized($0.name) == normalized(done) })
        else { return }
        let dayName = plan.days[dayIndex].name

        // Today's own day already done today: today's colour is taken, so the date keeps what
        // it has and the question's default is rest (the owner's 8).
        let baseDoneToday = base.name(in: plan).map { name in
            sessions.contains {
                $0.id != completed.id && $0.planId == planId && $0.endedAt != nil
                    && calendar.isDate($0.startedAt, inSameDayAs: date)
                    && normalized($0.dayName) == normalized(name)
            }
        } ?? false
        let original: DaySwap.Slot
        var todaysOption: DaySwap.Slot = .rest
        switch base {
        case let .day(index):
            original = .day(name: plan.days[index].name)
            if !baseDoneToday { todaysOption = original }
        // A pattern that said nothing for the date offered nothing to do on it.
        case .rest, .none, .own, .borrowed:
            original = .rest
        }
        if !baseDoneToday {
            write(DaySwap(planId: planId, date: date, original: original,
                          replacement: .day(name: dayName), askedOn: nil, answered: true))
        }
        // The day whose workout was taken: the next date within the horizon projecting X.
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: date),
              let taken = PlanSchedule.firstDate(plan, from: tomorrow, swaps: swaps, today: date,
                                                 calendar: calendar, where: { $0 == .day(dayIndex) })
        else { return }
        write(DaySwap(planId: planId, date: taken, original: .day(name: dayName),
                      replacement: todaysOption, askedOn: date, answered: false))
    }

    /// One swap per date per plan: writing a date that has one replaces it, and a replacement
    /// equal to the original is no override at all, so it deletes it.
    mutating func write(_ swap: DaySwap) {
        swaps.removeAll { $0.planId == swap.planId && calendar.isDate($0.date, inSameDayAs: swap.date) }
        guard swap.replacement != swap.original else { return }
        swaps.append(swap)
    }

    /// D76 (v1.9, §6.50): whether a finished session of another plan is a day the active plan
    /// borrowed — on the session's own date, or on a date in the week before it whose missed
    /// day Do it now started late (the missed rule's own week).
    func isBorrowed(_ session: Session) -> Bool {
        guard let active = activePlan, let planId = session.planId, planId != active.id else { return false }
        let day = calendar.startOfDay(for: session.startedAt)
        guard let weekBefore = calendar.date(byAdding: .day, value: -7, to: day) else { return false }
        return swaps.contains { swap in
            guard swap.planId == active.id, swap.date >= weekBefore, swap.date <= day,
                  case let .borrowed(id, name) = swap.replacement else { return false }
            return id == planId && normalized(name) == normalized(session.dayName)
        }
    }

    /// §6.46: answering the question sets the taken date's slot. D73: `.slide` is D37's
    /// re-anchor, applied now rather than when the workout finished — the pattern carries on
    /// from the day that was done — and remembers what it replaced; leaving a slide restores
    /// it first. The swap stays, answered, so the ring goes faint and the question can be
    /// reopened until its date is past.
    mutating func answer(swap id: UUID, with slot: DaySwap.Slot) {
        guard let i = swaps.firstIndex(where: { $0.id == id }),
              let p = plans.firstIndex(where: { $0.id == swaps[i].planId }) else { return }
        if swaps[i].replacement == .slide, slot != .slide, let undo = swaps[i].slideUndo {
            plans[p].cyclePosition = undo.cyclePosition
            plans[p].cycleAnchor = undo.cycleAnchor
            swaps[i].slideUndo = nil
        }
        if slot == .slide, swaps[i].replacement != .slide {
            // Rotations only: a weekday plan's days are pinned to weekdays, and nothing slides.
            guard plans[p].schedule == .rotation, let askedOn = swaps[i].askedOn,
                  case let .day(name) = swaps[i].original else { return }
            swaps[i].slideUndo = SlideUndo(cyclePosition: plans[p].cyclePosition,
                                           cycleAnchor: plans[p].cycleAnchor)
            PlanSchedule.advance(&plans[p], completedDayName: name, on: askedOn, calendar: calendar)
        }
        swaps[i].replacement = slot
        swaps[i].answered = true
    }

    /// The question a swap carries, or nil for a swap that is not one (today's own record),
    /// whose date is past, or — D74 (v1.9, §6.48) — whose date has a finished workout on it:
    /// the day is done, and no answer could change it (the calendar's own test for a done day).
    /// The options, in order: Rest; today's day (unless today was a rest day, when it *is*
    /// Rest, or today's own day was done first, when today's colour is taken); keep; and Slide
    /// on rotations. Each carries its square's colour and whether it is what the date says now;
    /// the heading names the date by its weekday, and Slide's row previews what it would make.
    func question(for id: UUID, now: Date) -> SwapQuestion? {
        guard let swap = swaps.first(where: { $0.id == id }), let askedOn = swap.askedOn,
              let plan = plans.first(where: { $0.id == swap.planId }),
              case let .day(originalName) = swap.original,
              swap.date >= calendar.startOfDay(for: now),
              !sessions.contains(where: {
                  $0.endedAt != nil && calendar.isDate($0.startedAt, inSameDayAs: swap.date)
              }) else { return nil }
        var options: [SwapQuestion.Option] = []
        // Today's day as the pattern said when the question was asked — before a slide (D73)
        // moved the anchor — so a reopened question offers what it first offered (D74).
        var pattern = plan
        if let undo = swap.slideUndo {
            pattern.cyclePosition = undo.cyclePosition
            pattern.cycleAnchor = undo.cycleAnchor
        }
        let base = PlanSchedule.base(pattern, on: askedOn, today: askedOn, calendar: calendar)
        var todays: String?
        if case let .day(index) = base, let name = plan.days[safe: index]?.name {
            let doneOnAskedOn = sessions.contains {
                $0.planId == plan.id && $0.endedAt != nil
                    && calendar.isDate($0.startedAt, inSameDayAs: askedOn)
                    && normalized($0.dayName) == normalized(name)
            }
            if !doneOnAskedOn { todays = name }
        }
        options.append(.init(kind: .rest, slot: .rest, title: "Rest", isDefault: todays == nil))
        if let todays {
            options.append(.init(kind: .todays, slot: .day(name: todays), title: todays, isDefault: true))
        }
        options.append(.init(kind: .keep, slot: .day(name: originalName), title: originalName,
                             isDefault: false))
        if plan.schedule == .rotation {
            options.append(.init(kind: .slide, slot: .slide, title: "Slide", isDefault: false))
        }
        // D74: each option's square — the day's colour by name, grey for rest — and the check
        // on what the date says now.
        for index in options.indices {
            options[index].colour = PlanSchedule.resolve(options[index].slot, in: plan, base: .none).colour
            options[index].isChosen = options[index].slot == swap.replacement
        }
        // By its weekday even when the date is today or tomorrow: it is that day's Legs that
        // was done, earlier, and the strip never reaches a day a weekday would misname (D55).
        let weekday = calendar.component(.weekday, from: swap.date)
        let day = Weekday.allCases.first { $0.calendarValue == weekday }.map(WeekdayText.full) ?? "That day"
        return SwapQuestion(swapId: swap.id, date: swap.date, originalName: originalName,
                            heading: "\(day)'s \(originalName) is done. Make \(day):",
                            options: options, chosen: swap.replacement, answered: swap.answered,
                            slide: plan.schedule == .rotation ? slidePreview(of: swap, now: now) : nil)
    }

    /// D74 (v1.9, §6.48): Slide's row — the date and the two after it, read from the projection
    /// exactly as answering Slide would leave it, on a copy of the library, so the preview and
    /// the answer cannot disagree. Once slid, it is the pattern as it is.
    private func slidePreview(of swap: DaySwap, now: Date) -> SwapQuestion.SlidePreview? {
        var slid = self
        slid.answer(swap: swap.id, with: .slide)
        guard let plan = slid.plans.first(where: { $0.id == swap.planId }) else { return nil }
        let slots = (0..<3).compactMap { offset -> DaySlot? in
            calendar.date(byAdding: .day, value: offset, to: swap.date).map {
                PlanSchedule.slot(plan, on: $0, swaps: slid.swaps, today: now, calendar: calendar)
            }
        }
        return SwapQuestion.SlidePreview(
            colours: slots.map(\.colour),
            spoken: "Slide: " + slots.map { $0.name(in: plan) ?? "rest" }.joined(separator: ", "))
    }
}

extension PlanSchedule {
    /// The first date at or after `start`, within the horizon, whose projected slot satisfies
    /// `test` — how completion finds the day whose workout was taken.
    static func firstDate(_ plan: Plan, from start: Date, swaps: [DaySwap], today: Date,
                          calendar: Calendar = .current, where test: (DaySlot) -> Bool) -> Date? {
        let first = calendar.startOfDay(for: start)
        for offset in 0..<horizonDays {
            guard let date = calendar.date(byAdding: .day, value: offset, to: first) else { continue }
            if test(slot(plan, on: date, swaps: swaps, today: today, calendar: calendar)) { return date }
        }
        return nil
    }
}

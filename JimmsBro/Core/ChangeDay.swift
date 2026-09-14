import Foundation

/// SPEC §6.50 (D76, v1.9): **change a day's exercises** — for one date, the plan unchanged.
///
/// Today's ··· pushes a picker for the date the card shows: this plan's days first, under its
/// name; then every other plan's days under theirs; and last, a day written just for that date.
/// A tap writes the date's swap (§6.46), answered and asked by nobody, and the pattern's own day
/// removes it. Three kinds, and on the strip three marks: a day of this plan filled in its
/// colour, a day of another plan outlined in *its* plan's colour, and a day written for the date
/// outlined in ink — the outline says *not from this plan*, the colour still says *which day*.
struct DayChoices: Equatable {
    /// One day to choose: a square and a name.
    struct Row: Equatable {
        var name: String
        /// Its colour in its own plan, by its place there (§6.41).
        var colour: DayColour?
        /// A day of another plan is outlined in its colour, as the strip will draw it.
        var outlined: Bool
        /// What a tap writes for the date.
        var slot: DaySwap.Slot
        /// What the date is now, marked with a check.
        var isChosen: Bool
    }

    /// A plan's days under its name — "Push Pull Legs · this plan" first, then each other plan.
    struct Section: Equatable {
        var title: String
        var rows: [Row]
    }

    var date: Date
    /// "Change Wednesday's exercises" — the ···'s own words for the item (§6.49).
    var title: String
    /// "For Wednesday 16 September only. The plan does not change."
    var line: String
    var sections: [Section]
    /// The last row: "Write a day just for Wednesday".
    var ownTitle: String
    /// The date's own day, when it has one — checked on the last row, and what the sheet opens
    /// with.
    var own: Day?
    /// The name a nameless own day takes: "Wednesday's own day".
    var ownName: String
    /// The JSON sheet for the last row (§6.19, D77): "A day just for Wednesday", "For Wednesday
    /// 16 September. Not saved to Push Pull Legs.", the date's own day or the example, and Save
    /// reading "Use for Wednesday".
    var point: JSONPoint

    /// A nameless own day's name ends so, and already says when (`HomeStart.ownStartTitle`).
    static let ownSuffix = "'s own day"
    /// The app speaks English whatever the phone's language, and so does the date line.
    static let months = ["January", "February", "March", "April", "May", "June", "July",
                         "August", "September", "October", "November", "December"]
}

extension PlanLibrary {
    /// The picker for `date` (§6.50): the active plan's days, then every other plan that has
    /// days, in the Plans list's order, and the own-day row. The words say *when* as the strip's
    /// button does — Today, Tomorrow, the weekday — and the line names the date in full. Nil
    /// with no plan.
    func dayChoices(for date: Date, now: Date) -> DayChoices? {
        guard let plan = activePlan else { return nil }
        let day = calendar.startOfDay(for: date)
        let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: day).day ?? 0
        let weekdayValue = calendar.component(.weekday, from: day)
        let weekday = Weekday.allCases.first { $0.calendarValue == weekdayValue }
        let when = WeekStrip.when(offset: offset, weekday: weekday)
        let weekdayName = weekday.map(WeekdayText.full) ?? when
        let month = DayChoices.months[safe: calendar.component(.month, from: day) - 1] ?? ""
        let fullDate = "\(weekdayName) \(calendar.component(.day, from: day)) \(month)"
        let slot = PlanSchedule.slot(plan, on: day, swaps: swaps, today: now, calendar: calendar)

        func section(_ source: Plan, title: String) -> DayChoices.Section {
            let borrowed = source.id != plan.id
            return DayChoices.Section(title: title, rows: source.days.enumerated().map { index, choice in
                let written: DaySwap.Slot = borrowed
                    ? .borrowed(planId: source.id, name: choice.name) : .day(name: choice.name)
                return DayChoices.Row(name: choice.name, colour: DayColour.of(dayIndex: index),
                                      outlined: borrowed, slot: written,
                                      isChosen: PlanSchedule.resolve(written, in: plan, base: .none) == slot)
            })
        }
        var sections = [section(plan, title: "\(plan.name) · this plan")]
        sections += plans.filter { $0.id != plan.id && !$0.days.isEmpty }.map { section($0, title: $0.name) }
        var own: Day?
        if case let .own(written) = slot { own = written }
        let ownName = weekdayName + DayChoices.ownSuffix
        return DayChoices(
            date: day,
            title: "Change \(when)'s exercises",
            line: "For \(fullDate) only. The plan does not change.",
            sections: sections,
            ownTitle: "Write a day just for \(when)",
            own: own,
            ownName: ownName,
            point: .ownDay(when: when, date: fullDate, name: ownName, plan: plan, own: own))
    }

    /// A tap in the picker (§6.50): the date becomes `slot`, for that date alone. A date that
    /// carries a question is answered (§6.46) — the question stays, answered, and leaving a
    /// slide puts the anchor back; any other date is written as a swap asked by nobody, and a
    /// choice equal to the pattern's own day removes it (`write`). Nothing in the plan moves.
    mutating func choose(_ slot: DaySwap.Slot, for date: Date, now: Date) {
        guard let plan = activePlan else { return }
        let day = calendar.startOfDay(for: date)
        if let asked = PlanSchedule.swap(plan, on: day, swaps: swaps, calendar: calendar), asked.isQuestion {
            answer(swap: asked.id, with: slot)
            return
        }
        let base = PlanSchedule.base(plan, on: day, today: now, calendar: calendar)
        let original: DaySwap.Slot = base.name(in: plan).map { .day(name: $0) } ?? .rest
        write(DaySwap(planId: plan.id, date: day, original: original, replacement: slot,
                      askedOn: nil, answered: true))
    }

    /// D76: a borrowed day found in the plan it came from — the plan's id, the day's place there
    /// and the day — or nil when that plan, or that day, is gone.
    func borrowed(planId: UUID, name: String) -> (planId: UUID, dayIndex: Int, day: Day)? {
        guard let source = plans.first(where: { $0.id == planId }),
              let index = source.days.firstIndex(where: { normalized($0.name) == normalized(name) })
        else { return nil }
        return (planId, index, source.days[index])
    }

    /// D76 (v1.9, §6.50): a day written just for a date, read as generously as any fragment
    /// (D43) — fences, prose around it, a plan holding one day — and checked by the importer as
    /// that day alone, in the plan's units, so a day the app would refuse to import is refused
    /// here with the same sentence. A nameless day is called `name`; more than one is refused.
    /// The day never joins a plan: the swap holds it.
    static func ownDay(_ text: String, named name: String, units: WeightUnit, settings: Settings,
                       now: Date) -> (day: Day?, issues: [Issue]) {
        let read = PlanEdit.fragment(text, as: .days)
        guard let values = read.values else { return (nil, read.issues) }
        guard values.count == 1, var object = values[0].object else {
            return (nil, read.issues + [Issue(severity: .error, code: "E_EDIT_INVALID", path: "",
                                              message: "Paste one day here; it is for this date alone.")])
        }
        if (object["name"]?.string ?? "").trimmed.isEmpty { object["name"] = .string(name) }
        // A date is not a weekday: the day is that date's, whatever a weekday plan would say.
        object["weekday"] = nil
        let tree = RawJSON.object(["schemaVersion": .number(1), "name": .string(name),
                                   "units": .string(units.rawValue), "schedule": .string("rotation"),
                                   "days": .array([.object(object)])])
        let trial = PlanImport.run(PlanDrafting.render(tree), settings: settings, now: now)
        guard var day = trial.plan?.days.first else {
            // The paths are the day's own — "exercises[0].reps" — not the trial plan's.
            let errors = (read.issues + trial.issues).filter { $0.severity == .error }.map { issue -> Issue in
                var moved = issue
                if moved.path.hasPrefix("days[0].") {
                    moved.path = String(moved.path.dropFirst("days[0].".count))
                } else if moved.path == "days[0]" {
                    moved.path = ""
                }
                return moved
            }
            return (nil, errors)
        }
        day.weekday = nil
        return (day, [])
    }
}

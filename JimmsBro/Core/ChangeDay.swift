import Foundation

/// SPEC §6.50 (D76, v1.9) and §6.58 (D85, v1.10): **Change *day*** — a day's exercises for one
/// date, the plan unchanged.
///
/// Today's ··· pushes a picker for the date the card shows, named after the day it changes —
/// *Change Push*. This plan's days are one joined strip of tiles under its name; every other
/// plan's days a strip of outlined tiles under theirs; and last one dashed tile, **Custom**, a
/// day written just for that date. A tap marks a tile and the button confirms (`ChangeDayText`),
/// writing the date's swap (§6.46), answered and asked by nobody; the pattern's own day removes
/// it. Under the strips, the date's exercises as they stand open the JSON sheet pre-filled with
/// the day. Three kinds, and on the strip three marks: a day of this plan filled in its colour,
/// a day of another plan outlined in *its* plan's colour, and a day written for the date
/// outlined in ink — the outline says *not from this plan*, the colour still says *which day*.
struct DayChoices: Equatable {
    /// A day as a square draws it: its name, its colour, and whether it is outlined.
    struct Face: Equatable {
        var name: String
        /// Its colour in its own plan, by its place there (§6.41); nil (grey, or ink when
        /// outlined) for rest and for a day written for the date.
        var colour: DayColour?
        /// A day of another plan, or a day written for the date (D76).
        var outlined: Bool
    }

    /// One day to choose: a tile in a strip.
    struct Tile: Equatable {
        var face: Face
        /// What the button writes for the date once this tile is marked.
        var slot: DaySwap.Slot
        /// What the date is now — the tile says *when* beneath its name.
        var isChosen: Bool

        var name: String { face.name }
        var colour: DayColour? { face.colour }
        var outlined: Bool { face.outlined }
    }

    /// A plan's days as one joined strip under its name — this plan first, then each other plan.
    struct Strip: Equatable {
        var title: String
        var tiles: [Tile]
    }

    /// What a tap marks: a day's tile, or Custom.
    enum Mark: Equatable {
        case day(DaySwap.Slot)
        case custom
    }

    /// D85: the date's exercises as they stand, under the strips — the day's square and name,
    /// its exercises with their set blocks — opening the JSON sheet pre-filled with the day.
    struct Exercises: Equatable {
        var face: Face
        var rows: [HomeStart.PreviewRow]
        /// The sheet: the day's own JSON, and Save reading "Use for Wednesday".
        var point: JSONPoint
    }

    var date: Date
    /// The day the date is now: "Push", a borrowed "Lower", an own day's name, or "Rest".
    var day: Face
    /// "Change Push" — the ···'s own words for the item (§6.49).
    var title: String
    /// "Today", "Tomorrow", the weekday: the strip's word for the date, beneath the chosen tile.
    var when: String
    /// "For Wednesday 16 September only. The plan does not change."
    var line: String
    var strips: [Strip]
    /// The date's own day, when it has one — Custom is then the chosen tile, and its sheet
    /// opens on it.
    var own: Day?
    /// The name a nameless own day takes: "Wednesday's own day".
    var ownName: String
    /// Custom's JSON sheet (§6.19, D77): "A day just for Wednesday", "For Wednesday 16
    /// September. Not saved to Push Pull Legs.", the date's own day or the example, and Save
    /// reading "Use for Wednesday".
    var point: JSONPoint
    /// Nil on a rest date: there are no exercises to change.
    var exercises: Exercises?

    /// The dashed tile's name.
    static let customTitle = "Custom"
    /// A nameless own day's name ends so, and already says when (`HomeStart.ownStartTitle`).
    static let ownSuffix = "'s own day"
    /// The app speaks English whatever the phone's language, and so does the date line.
    static let months = ["January", "February", "March", "April", "May", "June", "July",
                         "August", "September", "October", "November", "December"]

    /// "Change Push": the ··· item and the picker's title, after the day the date is now (D85).
    static func title(dayName: String) -> String { "Change \(dayName)" }
}

/// D85 (v1.10, §6.58): the picker's one button, which says what it will do. A tap marks; only
/// the button writes.
enum ChangeDayText {
    struct Confirm: Equatable {
        /// "Change Push" while nothing is marked, "Push → Pull" for a day, "Write a day for
        /// Wednesday" for Custom — and what VoiceOver reads.
        var title: String
        /// For a day, the two squares the button draws either side of its arrow.
        var from: DayChoices.Face?
        var to: DayChoices.Face?
        var isEnabled: Bool
        /// What the button writes; nil for Custom, which opens the sheet, and while disabled.
        var slot: DaySwap.Slot?
        /// Custom: the button opens the JSON sheet, whose Save writes.
        var opensSheet: Bool
    }

    /// The button for `marked`. Nothing marked — or the tile the date already is, which would
    /// change nothing — is the disabled *Change Push*; a tile no longer in the picker counts as
    /// nothing marked.
    static func confirm(_ choices: DayChoices, marked: DayChoices.Mark?) -> Confirm {
        let idle = Confirm(title: choices.title, from: nil, to: nil, isEnabled: false, slot: nil,
                           opensSheet: false)
        switch marked {
        case nil:
            return idle
        case .custom:
            return Confirm(title: "Write a day for \(choices.when)", from: nil, to: nil, isEnabled: true,
                           slot: nil, opensSheet: true)
        case let .day(slot):
            guard let tile = choices.strips.flatMap(\.tiles).first(where: { $0.slot == slot }),
                  !tile.isChosen else { return idle }
            return Confirm(title: "\(choices.day.name) → \(tile.name)", from: choices.day, to: tile.face,
                           isEnabled: true, slot: slot, opensSheet: false)
        }
    }
}

extension PlanLibrary {
    /// The picker for `date` (§6.50, §6.58): the active plan's days, then every other plan that
    /// has days, in the Plans list's order, Custom, and the date's exercises. The words say
    /// *when* as the strip's button does — Today, Tomorrow, the weekday — and the line names
    /// the date in full. Nil with no plan.
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

        func strip(_ source: Plan) -> DayChoices.Strip {
            let borrowed = source.id != plan.id
            return DayChoices.Strip(title: source.name, tiles: source.days.enumerated().map { index, choice in
                let written: DaySwap.Slot = borrowed
                    ? .borrowed(planId: source.id, name: choice.name) : .day(name: choice.name)
                return DayChoices.Tile(face: .init(name: choice.name, colour: DayColour.of(dayIndex: index),
                                                   outlined: borrowed),
                                       slot: written,
                                       isChosen: PlanSchedule.resolve(written, in: plan, base: .none) == slot)
            })
        }
        var strips = [strip(plan)]
        strips += plans.filter { $0.id != plan.id && !$0.days.isEmpty }.map(strip)

        // The day the date is now, as its square draws it, and its exercises as they stand.
        var face = DayChoices.Face(name: HomeStart.restTitle, colour: nil, outlined: false)
        var current: Day?
        var own: Day?
        switch slot {
        case let .day(index):
            if let found = plan.days[safe: index] {
                current = found
                face = .init(name: found.name, colour: DayColour.of(dayIndex: index), outlined: false)
            }
        case let .borrowed(planId, name):
            if let found = borrowed(planId: planId, name: name) {
                current = found.day
                face = .init(name: found.day.name, colour: DayColour.of(dayIndex: found.dayIndex), outlined: true)
            }
        case let .own(written):
            own = written
            current = written
            face = .init(name: written.name, colour: nil, outlined: true)
        case .rest, .none:
            break
        }
        let ownName = weekdayName + DayChoices.ownSuffix
        let exercises = current.map { shown in
            DayChoices.Exercises(
                face: face,
                rows: shown.exercises.map { HomeStart.PreviewRow(name: $0.name, sets: $0.sets.count) },
                point: .ownDay(when: when, date: fullDate, name: ownName, plan: plan, own: shown))
        }
        return DayChoices(
            date: day,
            day: face,
            title: DayChoices.title(dayName: face.name),
            when: when,
            line: "For \(fullDate) only. The plan does not change.",
            strips: strips,
            own: own,
            ownName: ownName,
            point: .ownDay(when: when, date: fullDate, name: ownName, plan: plan, own: own),
            exercises: exercises)
    }

    /// The picker's button (§6.50, D85): the date becomes `slot`, for that date alone. A date that
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

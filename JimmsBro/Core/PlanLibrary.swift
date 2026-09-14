import Foundation

enum LibraryError: Error, Equatable { case sessionInProgress, invalidDay, planNotFound }
enum ConflictChoice { case replace, keepBoth, cancel }
enum SessionSwitch { case finish, discard }
struct PlanLibrary {
    var plans: [Plan] = []
    var activePlanId: UUID?
    var sessions: [Session] = []
    var engine: SessionEngine?
    var settings = Settings()
    var activePlan: Plan? { plans.first { $0.id == activePlanId } }
    func conflict(for plan: Plan) -> Plan? { plans.first { normalized($0.name) == normalized(plan.name) } }
    @discardableResult mutating func save(_ imported: Plan, conflict choice: ConflictChoice = .cancel, makeActive: Bool = false) -> UUID? {
        var incoming = imported
        incoming.name = incoming.name.trimmed
        if let existing = conflict(for: imported), let index = plans.firstIndex(where: { $0.id == existing.id }) {
            switch choice {
            case .cancel: return nil
            case .replace:
                incoming.id = existing.id
                incoming.cyclePosition = PlanSchedule.positionAfterReplacement(old: existing, new: incoming)
                plans[index] = incoming
            case .keepBoth:
                let base = incoming.name; var n = 2
                while plans.contains(where: { normalized($0.name) == normalized(incoming.name) }) { incoming.name = "\(base) (\(n))"; n += 1 }
                if plans.contains(where: { $0.id == incoming.id }) { incoming.id = UUID() }
                plans.append(incoming)
            }
        } else { plans.append(incoming) }
        if activePlanId == nil || makeActive { activePlanId = incoming.id }
        return incoming.id
    }
    /// Plan detail's explicit **Replace** (D25/v1.1, SPEC §4.3): replaces `id` outright, keeping
    /// its id and cycle position mapping, regardless of what the incoming plan's name matches.
    /// Unlike `save`'s name-based conflict handling, the intent here is already explicit.
    @discardableResult mutating func replace(_ id: UUID, with imported: Plan) -> UUID? {
        guard let index = plans.firstIndex(where: { $0.id == id }) else { return nil }
        var incoming = imported
        incoming.name = incoming.name.trimmed
        incoming.id = id
        incoming.cyclePosition = PlanSchedule.positionAfterReplacement(old: plans[index], new: incoming)
        // v1.3: the anchor (D37) belongs to the position, so it stays with it — replacing the
        // plan's text is not a reason for the calendar to move.
        incoming.cycleAnchor = incoming.cyclePosition == nil ? nil : plans[index].cycleAnchor
        plans[index] = incoming
        return id
    }
    mutating func deletePlan(_ id: UUID) {
        plans.removeAll { $0.id == id }
        if activePlanId == id { activePlanId = plans.count == 1 ? plans.first?.id : nil }
    }
    @discardableResult mutating func startDay(planId: UUID, dayIndex: Int, now: Date, switching: SessionSwitch? = nil) throws -> [Effect] {
        guard let plan = plans.first(where: { $0.id == planId }) else { throw LibraryError.planNotFound }
        guard let session = Session.start(plan:plan,dayIndex:dayIndex,now:now), !session.steps.isEmpty else { throw LibraryError.invalidDay }
        var effects: [Effect] = []
        if engine != nil {
            guard let switching else { throw LibraryError.sessionInProgress }
            switch switching {
            case .finish:
                effects += engine?.apply(.finish, now:now) ?? []
                completeSession()
            case .discard: effects += discardSession()
            }
        }
        let started = SessionEngine(session:session,settings:settings,history:sessions,now:now)
        engine = started
        // Carries the warm-up's notification (D32) as well as the save.
        effects += started.initialEffects
        return effects
    }
    @discardableResult mutating func apply(_ event: Event, now: Date) -> [Effect] {
        let effects = engine?.apply(event,now:now) ?? []
        if effects.contains(.sessionCompleted) { completeSession() }
        return effects
    }
    mutating func completeSession() {
        guard let e = engine, e.phase == .completed else { return }
        if e.loggedCount > 0 {
            let completed = e.session
            if !sessions.contains(where: { $0.id == completed.id }) { sessions.append(completed) }
            if let index = plans.firstIndex(where: { $0.id == completed.planId }) {
                PlanSchedule.advance(&plans[index], completedDayName: completed.dayName,
                                     on: completed.startedAt)
                // D53 (v1.5): steps you earn — each exercise that was at its step moves on or
                // tries again. Only here, when the workout completes; editing history later
                // never moves a step.
                if plans[index].progression != nil {
                    ProgressionSteps.advance(&plans[index].progression!, after: completed)
                }
            }
        }
        engine = nil
    }
    @discardableResult mutating func discardSession() -> [Effect] {
        engine = nil
        return AlertIdentifier.all.map { .cancelNotification(id:$0) } + [.persist]
    }
    mutating func editSession(_ id: UUID, step: Int, result: SetResult, now: Date) {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        var edit = SessionEngine(active:ActiveSession(session:sessions[i],phase:.completed),settings:settings)
        edit.apply(.editSet(step:step,result:result),now:now)
        sessions[i] = edit.session
    }
    /// SPEC §4.5 (v1.1): renaming an exercise is a history-editing task, so it lives in Session
    /// detail rather than in the mid-workout menu. Reuses the engine's own rule (trimmed, capped,
    /// never blank) so a name entered here and one entered mid-session cannot diverge.
    mutating func renameExercise(_ id: UUID, exerciseIndex: Int, name: String) {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        var edit = SessionEngine(active:ActiveSession(session:sessions[i],phase:.completed),settings:settings)
        edit.apply(.renameExercise(exerciseIndex:exerciseIndex,name:name),now:sessions[i].startedAt)
        sessions[i] = edit.session
    }
    mutating func deleteSession(_ id: UUID) { sessions.removeAll { $0.id == id } }
}
/// SPEC §6.12 (D37, v1.2): a rotation is projected from an **anchor date**, not from "today
/// plus an offset".
///
/// v1.1 computed a day's cycle entry as `(cyclePosition + daysFromToday) % cycle.count`, and
/// `cyclePosition` only ever moved when a session completed. Miss a workout and the whole month
/// slid forward by a day — and by another for each further day missed. The owner's words: "if
/// one day of the week is messed up then it compounds."
///
/// With an anchor, the pattern is nailed to the calendar. Missing a day changes nothing about
/// what any other day says; the pattern only moves when you *finish* a workout, which re-anchors
/// deliberately, once, on the day you actually did it.
enum PlanSchedule {
    /// The position the plan actually holds, or nil when nothing has been completed yet (a
    /// position out of range is nothing, not zero — it describes a cycle that no longer exists).
    static func position(_ plan: Plan) -> Int? {
        plan.cyclePosition.flatMap { plan.cycle.indices.contains($0) ? $0 : nil }
    }

    /// The day `cyclePosition` describes. A plan that predates anchors (or has completed
    /// nothing) is anchored to today, which reproduces v1.1's reading exactly — the difference
    /// is that from the first completed workout the anchor is written down, and stops moving.
    static func anchorDay(_ plan: Plan, today: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: plan.cycleAnchor ?? today)
    }

    /// The cycle entry a rotation lands on for `date`, or nil when the plan has no cycle.
    static func entry(_ plan: Plan, on date: Date, today: Date = Date(),
                      calendar: Calendar = .current) -> (cycleIndex: Int, entry: CycleEntry)? {
        guard !plan.cycle.isEmpty else { return nil }
        let anchor = anchorDay(plan, today: today, calendar: calendar)
        let days = calendar.dateComponents([.day], from: anchor,
                                           to: calendar.startOfDay(for: date)).day ?? 0
        let count = plan.cycle.count
        // Swift's % keeps the sign of the dividend, and dates before the anchor are ordinary.
        let index = ((position(plan) ?? 0) + days) % count
        return ((index + count) % count, plan.cycle[(index + count) % count])
    }

    /// The next training day at or after `today`, by the anchored projection. Home and the
    /// calendar both read this, so "Next up" and the ring on the grid can never disagree.
    static func next(_ plan: Plan, today: Date, calendar: Calendar = .current)
        -> (cycleIndex: Int, dayIndex: Int, date: Date)? {
        guard !plan.cycle.isEmpty else { return nil }
        // The anchor day is the day that was *done*, so the search starts after it. With nothing
        // completed there is nothing to be after, and it starts today.
        let start: Date
        if position(plan) != nil,
           let after = calendar.date(byAdding: .day, value: 1,
                                     to: anchorDay(plan, today: today, calendar: calendar)) {
            start = max(calendar.startOfDay(for: today), after)
        } else {
            start = calendar.startOfDay(for: today)
        }
        // One full cycle is enough: a cycle with no day in it has none anywhere.
        for offset in 0..<max(plan.cycle.count, 1) {
            guard let date = calendar.date(byAdding: .day, value: offset, to: start),
                  let (index, entry) = entry(plan, on: date, today: today, calendar: calendar),
                  case let .day(day) = entry, plan.days.indices.contains(day) else { continue }
            return (index, day, date)
        }
        return nil
    }

    /// The v1.1 signature, kept for the callers that only want "which day is next" and have no
    /// date to hand. It answers for today.
    static func next(_ plan: Plan) -> (cycleIndex: Int, dayIndex: Int)? {
        next(plan, today: Date()).map { ($0.cycleIndex, $0.dayIndex) }
    }

    /// A training day the projection put **before** today that has no completed session on it —
    /// the workout that was missed. Only the most recent one, and only within a week: a plan you
    /// came back to after a fortnight is not a missed Tuesday, it is a fresh start.
    ///
    /// D55 (v1.6): only a day the plan actually expected. A plan with nothing completed has no
    /// anchor and projected its pattern backwards over days before it existed — "Full Body B
    /// was due Sunday", three minutes after a fresh install — and a completion re-anchors the
    /// pattern over days that were already lived through ("Pull was due Tuesday" after a day
    /// run out of order). A missed day is therefore after the plan's import day and after its
    /// anchor, the day of its most recent completed workout; with nothing completed, nothing
    /// was missed.
    static func missed(_ plan: Plan, sessions: [Session], today: Date,
                       calendar: Calendar = .current) -> (dayIndex: Int, date: Date)? {
        guard !plan.cycle.isEmpty, let anchor = plan.cycleAnchor else { return nil }
        let anchorDay = calendar.startOfDay(for: anchor)
        let importDay = calendar.startOfDay(for: plan.importedAt)
        let done = Set(sessions.filter { $0.endedAt != nil }
            .map { calendar.startOfDay(for: $0.startedAt) })
        for offset in 1...7 {
            guard let date = calendar.date(byAdding: .day, value: -offset,
                                           to: calendar.startOfDay(for: today)) else { continue }
            guard date > anchorDay, date >= importDay else { return nil }   // before the plan expected anything
            guard !done.contains(date) else { return nil }   // you trained; nothing was missed
            guard let (_, entry) = entry(plan, on: date, today: today, calendar: calendar),
                  case let .day(day) = entry, plan.days.indices.contains(day) else { continue }
            return (day, date)
        }
        return nil
    }

    /// Completing a workout re-anchors the rotation to the day it was done. That is the one
    /// moment the pattern is allowed to move, and it moves once, deliberately.
    static func advance(_ plan: inout Plan, completedDayName: String, on date: Date = Date(),
                        calendar: Calendar = .current) {
        guard plan.schedule == .rotation, !plan.cycle.isEmpty,
              let day = plan.days.firstIndex(where: { normalized($0.name) == normalized(completedDayName) })
        else { return }
        let start = plan.cyclePosition.map { ($0 >= 0 && $0 < plan.cycle.count) ? ($0 + 1) % plan.cycle.count : 0 } ?? 0
        for offset in 0..<plan.cycle.count {
            let i = (start + offset) % plan.cycle.count
            if plan.cycle[i] == .day(day) {
                plan.cyclePosition = i
                plan.cycleAnchor = calendar.startOfDay(for: date)
                return
            }
        }
    }

    /// D37 (v1.2): a plan imported before anchors existed has a position — "the last cycle
    /// entry completed" — but no date to hang it on. The app knows that date: it is the day of
    /// the most recent completed session of this plan. Anchoring there makes the calendar say
    /// what actually happened, rather than what v1.1 inferred from an offset.
    ///
    /// With no completed session to point at, the anchor is today, which reproduces v1.1's
    /// reading exactly. Returns true when it changed something.
    @discardableResult
    static func anchorIfNeeded(_ plan: inout Plan, lastCompleted: Date? = nil, today: Date,
                               calendar: Calendar = .current) -> Bool {
        guard plan.schedule == .rotation, !plan.cycle.isEmpty, plan.cycleAnchor == nil,
              position(plan) != nil else { return false }
        plan.cycleAnchor = calendar.startOfDay(for: lastCompleted ?? today)
        return true
    }
    static func positionAfterReplacement(old: Plan, new: Plan) -> Int? {
        guard let oldPosition = old.cyclePosition, case let .day(d)? = old.cycle[safe:oldPosition], let oldDay = old.days[safe:d] else { return nil }
        return new.cycle.firstIndex { entry in
            guard case let .day(index) = entry, let newDay = new.days[safe:index] else { return false }
            return normalized(newDay.name) == normalized(oldDay.name)
        }
    }
    static func weekday(_ plan: Plan, today: Date, calendar: Calendar = .current) -> (dayIndex: Int, daysAway: Int)? {
        let current = calendar.component(.weekday,from:today)
        for offset in 0..<7 {
            let weekday = (current - 1 + offset) % 7 + 1
            if let index = plan.days.firstIndex(where: { $0.weekday?.calendarValue == weekday }) { return (index, offset) }
        }
        return nil
    }
}

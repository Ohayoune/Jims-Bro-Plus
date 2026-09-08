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
            if let index = plans.firstIndex(where: { $0.id == completed.planId }) { PlanSchedule.advance(&plans[index], completedDayName:completed.dayName) }
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
enum PlanSchedule {
    static func next(_ plan: Plan) -> (cycleIndex: Int, dayIndex: Int)? {
        guard !plan.cycle.isEmpty else { return nil }
        let start = plan.cyclePosition.map { ($0 >= 0 && $0 < plan.cycle.count) ? ($0 + 1) % plan.cycle.count : 0 } ?? 0
        for offset in 0..<plan.cycle.count {
            let i = (start + offset) % plan.cycle.count
            if case let .day(d) = plan.cycle[i], plan.days.indices.contains(d) { return (i,d) }
        }
        return nil
    }
    static func advance(_ plan: inout Plan, completedDayName: String) {
        guard plan.schedule == .rotation, !plan.cycle.isEmpty, let day = plan.days.firstIndex(where: { normalized($0.name) == normalized(completedDayName) }) else { return }
        let start = plan.cyclePosition.map { ($0 >= 0 && $0 < plan.cycle.count) ? ($0 + 1) % plan.cycle.count : 0 } ?? 0
        for offset in 0..<plan.cycle.count {
            let i = (start + offset) % plan.cycle.count
            if plan.cycle[i] == .day(day) { plan.cyclePosition = i; return }
        }
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

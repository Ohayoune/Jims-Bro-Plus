import Foundation

/// The session half of `AppModel`: starting, running and finishing a workout, and turning the
/// engine's effects into notifications, alerts and disk writes. No view code, so it is testable.
extension AppModel {
    var engine: SessionEngine? { library.engine }
    var session: Session? { library.engine?.session }
    var phase: Phase? { library.engine?.phase }
    var hasActiveSession: Bool { library.engine != nil }

    /// The step the workout is on, whatever the phase — the step a rest leads to while one runs.
    var currentStep: Int? { library.engine?.active.currentStep }
    /// The status strip's block-just-finished state (D14, SPEC §4.7), if one is showing.
    var blockDone: BlockDone? { library.engine?.active.blockDone }
    /// Whether the most recently logged-or-skipped step can still be undone (D23).
    var canUndo: Bool { library.engine?.canUndo ?? false }
    /// The step `undoLog` would act on, when `canUndo` is true.
    var undoStep: Int? { library.engine?.active.lastCompletedStep }

    /// D28 (v1.1): whether "Do later" would move anything — this block still has pending sets,
    /// and there is something else pending to move it behind. Deferring the only exercise left
    /// would be a no-op, so the menu item isn't offered.
    func canDefer(exerciseIndex: Int) -> Bool {
        guard let session, phase != .completed,
              let any = session.steps.first(where: { $0.exerciseIndex == exerciseIndex })
        else { return false }
        let block = any.blockIndex
        return session.steps.contains { $0.blockIndex == block && $0.status == .pending }
            && session.steps.contains { $0.blockIndex != block && $0.status == .pending }
    }

    /// D42 (v1.3): Change exercise is offered whenever the exercise still has a set to do —
    /// there is nothing to change about one that is finished.
    func canSubstitute(exerciseIndex: Int) -> Bool {
        guard let session, phase != .completed else { return false }
        return session.steps.contains { $0.exerciseIndex == exerciseIndex && $0.status == .pending }
    }

    /// D23 (v1.1): the status strip's Undo. Captures what the step held before undoing it, so
    /// the inputs come back carrying the values that were just removed (O52).
    func undoLast(now: Date = Date()) async {
        guard canUndo, let step = undoStep else { return }
        restoredInputs = session?.steps[safe: step]?.result
        await apply(.undoLog(step: step), now: now)
    }

    /// Read once by the inputs when they reload; a second read gets a normal prefill.
    func takeRestoredInputs() -> SetResult? {
        defer { restoredInputs = nil }
        return restoredInputs
    }

    // MARK: - Starting

    /// Starts a day. Throws `LibraryError.sessionInProgress` when one is already running and no
    /// choice was given, which is what raises the switch-day popup (D17).
    func startDay(planId: UUID, dayIndex: Int, switching: SessionSwitch? = nil,
                  now: Date = Date()) async throws {
        // Throws before anything changes when a session is running and no choice was given.
        let effects = try library.startDay(planId: planId, dayIndex: dayIndex, now: now, switching: switching)
        await began(effects, now: now)
    }

    /// D76 (v1.9, §6.50): a day written just for a date, started as the plan's session under
    /// its own name — refused like any start while a session is open, which raises the popup.
    func startOwnDay(_ day: Day, on planId: UUID, switching: SessionSwitch? = nil,
                     now: Date = Date()) async throws {
        let effects = try library.startOwnDay(day, on: planId, now: now, switching: switching)
        await began(effects, now: now)
    }

    /// What every start does once the engine exists.
    private func began(_ effects: [Effect], now: Date) async {
        // Finishing as part of a switch goes straight into the new workout, with no Summary.
        justCompleted = nil
        // D48 (v1.4): the workout exists now; the cover opens on this, not on the awaits below.
        startedWorkouts += 1
        // D57 (v1.6): the notification permission is asked for at the first Log set or Start
        // timer (`apply`), not here over the first card (SPEC §5.3).
        // The effects carry `.sessionCompleted` for a finished switch and a final `.persist`
        // for the new session, in that order, so running them is all the persistence needed.
        await run(effects)
        await persistPlans()
        await refreshActivity(now: now)
    }

    /// The day the schedule points at: Today's Start on a workout day. On a rest day Today's
    /// button starts nothing since v1.8 (D71), but this still reaches the next workout — the
    /// screenshot runs (`-uiScreen workout`) call it, on whatever day they run.
    func startFromCard(now: Date = Date(), switching: SessionSwitch? = nil) async throws {
        guard let target = startCard(now: now).target else { return }
        try await startDay(planId: target.planId, dayIndex: target.dayIndex, switching: switching, now: now)
    }

    // MARK: - Running

    @discardableResult
    func apply(_ event: Event, now: Date = Date()) async -> [Effect] {
        guard library.engine != nil else { return [] }
        let known = Set(library.sessions.map(\.id))
        let effects = library.apply(event, now: now)
        // Completing clears the engine, so hold the finished session for the Summary.
        if let finished = library.sessions.first(where: { !known.contains($0.id) }) {
            justCompleted = finished
        }
        // D57 (v1.6): the permission is asked for at the first moment an alert is about to
        // matter — the first set logged or timer started, whose rest or end the alert will
        // announce — rather than at Start, over the first card (SPEC §5.3). Awaited here so
        // the notification this event schedules lands after the answer; the strip is already
        // counting, because `library.apply` mutated before the first await (D48).
        // D64 (v1.7): the line on Today that reports a refusal is earned here (§6.40).
        if !askedForNotifications, event.asksForAlerts {
            let allowed = await requestNotificationAuthorization()
            showNotificationBanner = Gates.notificationsOff(askedAtLogSet: true, allowed: allowed)
        }
        await run(effects)
        await refreshActivity(now: now)
        return effects
    }

    /// The user tapped Done on the Summary.
    func dismissSummary() { justCompleted = nil }

    /// Called on every timer tick and on foreground entry. `replayMissed` is false when the app
    /// was in the background: the notification already covered those moments (SPEC §6.4).
    func tick(now: Date = Date(), replayMissed: Bool = true) async {
        guard var engine = library.engine else { return }
        var changed = false

        let beeps = engine.beepDue(now: now, replayMissed: replayMissed)
        if !beeps.isEmpty || engine.active != library.engine?.active { changed = true }
        library.engine = engine
        for beep in beeps { alerts.play(beep, sound: settings.sound, vibration: settings.vibration) }

        if case let .resting(rest) = engine.phase, now >= rest.endsAt {
            await apply(.restElapsed, now: now)
            return
        }
        if case let .working(index) = engine.phase, engine.active.timerRunning,
           case let .duration(seconds)? = session?.target(at: index)?.work,
           let started = session?.steps[safe: index]?.startedAt,
           now >= started.addingTimeInterval(Double(seconds)) {
            await apply(.timerElapsed(step: index), now: now)
            return
        }
        if changed {
            do { try await persistActiveSession() } catch { saveFailure = .activeSessionWrite }
        }
        await refreshActivity(now: now)
    }

    // MARK: - Finishing

    /// Sets that were never logged or skipped, for the Finish confirmation (O11).
    var pendingStepCount: Int {
        session?.steps.filter { $0.status == .pending }.count ?? 0
    }
    var loggedStepCount: Int { session.map(SessionStats.loggedCount) ?? 0 }

    func finish(now: Date = Date()) async {
        await apply(.finish, now: now)
        await persistCompletedSessions()
    }

    /// O12: finishing with nothing logged discards instead of saving.
    func discardSession() async {
        justCompleted = nil
        let effects = library.discardSession()
        await run(effects)
        await tryClearActiveSession()
        await refreshActivity()
    }

    /// D24 (v1.1): a session is marked persisted only once its write actually succeeds, and
    /// `active-session.json` is cleared only once every completed session from it is confirmed
    /// on disk — stopping partway keeps the file so nothing already in memory is lost.
    private func persistCompletedSessions() async {
        for session in library.sessions where !persistedSessionIds.contains(session.id) {
            guard await trySaveSession(session) else { return }
        }
        await tryClearActiveSession()
        await persistPlans()
        // D72 (v1.9): a finished workout on an unexpected day is a swap, not a moved plan.
        await persistSwaps()
    }

    func persistActiveSession() async throws {
        guard let active = library.engine?.active else {
            try await store.clearActiveSession()
            return
        }
        try await store.save(activeSession: active)
    }

    // MARK: - Effects

    private func run(_ effects: [Effect]) async {
        // A completing batch always carries both `.sessionCompleted` and a trailing `.persist`.
        // `persistCompletedSessions` owns the active-session file's fate then (D24) — the
        // engine is already nil by this point, so `.persist`'s generic fallback would otherwise
        // clear the file regardless of whether the session's own write actually succeeded.
        let completing = effects.contains(.sessionCompleted)
        for effect in effects {
            switch effect {
            case let .scheduleNotification(id, date, body):
                await scheduler.schedule(AlertRouting.request(id: id, at: date, body: body))
            case let .cancelNotification(id):
                await scheduler.cancel(ids: [id])
            case let .playAlert(beep):
                alerts.play(beep, sound: settings.sound, vibration: settings.vibration)
            case let .playFeedback(kind):
                alerts.play(feedback: kind, vibration: settings.vibration)
            case .persist:
                guard !completing else { continue }
                do { try await persistActiveSession() } catch { saveFailure = .activeSessionWrite }
            case .sessionCompleted:
                await persistCompletedSessions()
            }
        }
    }

    // MARK: - Live Activity (D40, v1.2)

    /// Pushes the current state to the Lock Screen and the Dynamic Island, or ends the activity
    /// when there is no workout to show. Called after every event and on every tick; a state
    /// that has not changed is not pushed, so a per-second tick does not wake the system
    /// sixty times a minute.
    ///
    /// D60 (v1.6): `force` is the launch. A fresh process has shown nothing and has no workout,
    /// so `nil == nil` would return here and never ask for the end — which is precisely the
    /// case where an activity left over from the last run is still on the Lock Screen.
    func refreshActivity(now: Date = Date(), force: Bool = false) async {
        let state = library.engine.map(\.active)
            .flatMap { WorkoutActivityState.of($0, now: now, wording: settings.wording, plans: library.plans) }
        guard force || state != shownActivity else { return }
        shownActivity = state
        if let state {
            await activities.show(state)
        } else {
            await activities.end()
        }
    }

    func requestNotificationAuthorization() async -> Bool {
        guard !askedForNotifications else { return notificationsAllowed }
        askedForNotifications = true
        notificationsAllowed = await scheduler.requestAuthorization()
        return notificationsAllowed
    }

    /// Everything the app may have scheduled, cancelled together when a session ends or is left.
    func cancelAllAlerts() async { await scheduler.cancel(ids: AlertIdentifier.all) }
}

private extension Event {
    /// The events after which an alert would fire: a rest's end, or a timed set's beeps.
    var asksForAlerts: Bool {
        switch self {
        case .logSet, .startTimer: return true
        default: return false
        }
    }
}

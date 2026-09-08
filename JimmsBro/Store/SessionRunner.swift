import Foundation

/// The session half of `AppModel`: starting, running and finishing a workout, and turning the
/// engine's effects into notifications, alerts and disk writes. No view code, so it is testable.
extension AppModel {
    var engine: SessionEngine? { library.engine }
    var session: Session? { library.engine?.session }
    var phase: Phase? { library.engine?.phase }
    var hasActiveSession: Bool { library.engine != nil }

    /// The step the workout is on, whatever the phase. A block-just-finished status strip
    /// (`blockDone`) overlays `.working`, so it needs no case of its own here.
    var currentStep: Int? {
        switch library.engine?.phase {
        case let .working(index): return index
        case let .resting(state): return state.nextStep
        case .completed, nil: return nil
        }
    }
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
        // Finishing as part of a switch goes straight into the new workout, with no Summary.
        justCompleted = nil
        // Asking does not block the first set from appearing; the prompt sits over the card
        // and the banner appears afterwards if permission was refused (SPEC §5.3).
        if !askedForNotifications {
            Task { [weak self] in
                guard let self else { return }
                if await !self.requestNotificationAuthorization() { self.showNotificationBanner = true }
            }
        }
        // The effects carry `.sessionCompleted` for a finished switch and a final `.persist`
        // for the new session, in that order, so running them is all the persistence needed.
        await run(effects)
        await persistPlans()
        await refreshActivity(now: now)
    }

    /// The Home card's Start button target.
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
    func refreshActivity(now: Date = Date()) async {
        let state = library.engine.map(\.active).flatMap { WorkoutActivityState.of($0, now: now) }
        guard state != shownActivity else { return }
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

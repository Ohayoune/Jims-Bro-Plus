import SwiftUI

/// SPEC §4.1 (D61, v1.7; D69, D70, v1.8): Today is the day's card and nothing else — the same
/// five zones on every day of the plan: the day's colour and name, the meta row (the week as a
/// strip at its left, a clock and the minutes at its right), the exercises with their sets as
/// blocks (which are the preview), at most one message, and Start in the bottom slot. No words
/// without a cue: every line of words sits beside a mark that says the same. A tap on the strip
/// shows that day (§6.44); the day's other alternatives live in one ··· and nowhere else.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    /// Opens Add plan — on the built-in picker when the empty card asks (D46, v1.4).
    @Binding var addPlan: AddPlanRequest?
    @Binding var showWorkout: Bool
    /// D62 (v1.7): Plans is not a tab. ··· → Change plan pushes the list here, and the list
    /// pushes a plan's detail onto the same stack.
    @State private var path = NavigationPath()
    /// D62 (v1.7): the gear, top-left, pushes Settings — the same place as on History.
    @State private var showingSettings = false

    @State private var showDiscardConfirm = false
    @State private var previewing: PlanRoute?
    /// D70 (v1.8, §6.44): the strip's square the card shows — 0, today, until one is tapped.
    /// Not stored: put down and picked up again the phone shows the tapped day; a relaunch
    /// shows today; a started workout resets it (the tap was the choice, and it was taken).
    @State private var shownOffset = 0
    /// D17 (O36): a day started from the strip while a session is open — the switch popup's
    /// target, as on Plan detail. Today never needed the popup before the strip: its only
    /// mid-session button was Resume.
    @State private var switching: PlanRoute?
    /// D50 (v1.5): the plan whose progression the ··· item opens — and, since D67 (v1.7),
    /// **Plan the next one**.
    @State private var planningProgression: PlanRoute?
    /// D37 (v1.2): the missed-workout notice is dismissible for this run of the app. It is not
    /// persisted: it costs one tap to clear and re-earning it means missing another day.
    @State private var dismissedMissed = false

    var body: some View {
        // Core chooses the one message and the ··· items (D61); this view only draws them.
        let card = HomeStart.current(library: model.library,
                                     notificationsOff: model.showNotificationBanner,
                                     missedDismissed: dismissedMissed, showing: shownOffset)
        NavigationStack(path: $path) {
            VStack(alignment: .leading, spacing: 14) {
                // D65 (v1.7): the day's colour is a square before its name, never the name
                // itself — headers are ink (D59). D69 (v1.8): the square stands as tall as the
                // title's capitals, so the colour is read before the word.
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    // D71 (v1.8): a rest day's square is grey, and still there.
                    if card.dayColour != nil || card.isRest {
                        DaySquare(colour: card.dayColour, size: 24, relativeTo: .largeTitle)
                    }
                    Text(card.title)
                        .font(.largeTitle.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !card.strip.isEmpty || card.clock != nil || card.isRest { metaRow(card) }
                if let sentence = card.sentence {
                    Text(sentence)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if card.isRest {
                    // D71 (v1.8, §6.45): where the rows would be, the system's z's in the
                    // accent, centred in the card's empty half — the one blue thing above a
                    // button that does nothing, and it says *do something*: tap the strip. A
                    // mark, not words, so VoiceOver skips it; the title already said Rest. The
                    // message still speaks beneath it (a missed workout's Do it now).
                    Image(systemName: "zzz")
                        .font(.system(size: 60))
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityHidden(true)
                    if let message = card.message {
                        messageLine(message, card: card)
                    }
                } else {
                    // U13's rule, applied to Today: when Dynamic Type makes the card taller than
                    // the screen, the exercise list is what scrolls; the name, the clock and
                    // Start hold. On an ordinary day nothing scrolls.
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            exerciseBlock(card)
                            if let message = card.message {
                                messageLine(message, card: card)
                            }
                            if card.isEmpty, let link = card.link {
                                // D46 (v1.4): the practice workout, the one quiet link under the
                                // sentence; the picker is the button below (D61).
                                Button(link) { Task { await model.importPracticePlan() } }
                                    .font(.footnote)
                                    .buttonStyle(.bordered)
                                    .buttonBorderShape(.capsule)
                                    .controlSize(.small)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // D61 (v1.7): the only place the day's alternatives live. No ··· at all until
                // there is a plan to have alternatives for. D69 (v1.8): drawn lighter than the
                // title, and holding the progression's step as a line that is not a control.
                if !card.alternatives.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            ForEach(card.alternatives, id: \.self) { alternative in
                                alternativeButton(alternative, card: card)
                            }
                            if let step = card.stepLine {
                                Section { Button(step) {}.disabled(true) }
                            }
                        } label: {
                            QuietGlyph(systemName: "ellipsis")
                        }
                        .accessibilityLabel("More")
                    }
                    .quietBackground()
                }
            }
            // D59 (v1.6): Start in the slot every other screen keeps for its primary button —
            // under the thumb, above the tab bar.
            // D69 (v1.8): the play mark says the button starts something; the empty card's opens
            // a picker, and has none.
            // D70 (v1.8): Core says which mark — play, or the moon on the button that does
            // nothing — and whether the button is enabled.
            .bottomAction(if: card.buttonTitle != nil) {
                PrimaryButton(title: card.buttonTitle ?? "", systemImage: mark(card.buttonMark),
                              enabled: card.buttonEnabled) { act(card) }
            }
            // D56 (v1.6): a confirmation reached from a menu is an alert with two named
            // buttons, never a dialog — from a menu anchor a dialog can draw as a popover and
            // drop its cancel-role button.
            .alert("Discard this workout?", isPresented: $showDiscardConfirm) {
                Button("Discard", role: .destructive) { Task { await model.discardSession() } }
                Button("Keep going", role: .cancel) {}
            }
            // D17 (O36): starting a day from the strip mid-session asks rather than switching
            // silently — the same alert, with the same three answers, as Plan detail's.
            .alert(switchPrompt, isPresented: Binding(get: { switching != nil },
                                                      set: { if !$0 { switching = nil } })) {
                Button("Keep going", role: .cancel) { switching = nil }
                Button("Finish and start") { switchDay(.finish) }
                Button("Discard and start", role: .destructive) { switchDay(.discard) }
            }
            // D70 (v1.8): a workout started from anywhere — the strip, Do it now, Plan detail —
            // takes the tapped day with it; Today shows today behind the cover and after it.
            .onChange(of: model.startedWorkouts) { _, _ in shownOffset = 0 }
            .sheet(item: $previewing) { route in
                NavigationStack { PlanDetailView(planId: route.id, showWorkout: $showWorkout) }
                    .environment(model)
            }
            .sheet(item: $planningProgression) { route in
                ProgressionView(planId: route.id).environment(model)
            }
            // D62 (v1.7): Settings from the gear, top-left, as on History; Plans from ··· →
            // Change plan, pushed onto this stack.
            .settingsGear($showingSettings)
            .navigationDestination(for: TodayRoute.self) { route in
                switch route {
                case .plans: PlansView(addPlan: $addPlan, showWorkout: $showWorkout)
                }
            }
        }
        .task {
            #if DEBUG
            // Debug-only: Plans and Settings stopped being tabs in T2 (D62), so the screenshot
            // runs that ask for them land here and push the screen. On the stack rather than on
            // its root, so going back does not run this again.
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: "-uiScreen"),
                  let name = arguments[safe: index + 1], path.isEmpty, !showingSettings else { return }
            if name == "settings" { showingSettings = true }
            guard name == "plans" else { return }
            path.append(TodayRoute.plans)
            // The store loads asynchronously, and a plan's destination is declared by the list,
            // so the list goes on first.
            guard arguments.contains("-uiPlanDetail") else { return }
            await model.waitUntilLoaded()
            try? await Task.sleep(for: .milliseconds(300))
            if let first = model.plans.first { path.append(first.id) }
            #endif
        }
    }

    /// D69/D70 (v1.8): the meta row — the week as a strip at its left end (§6.44), and at its
    /// right a clock, the minutes in ink, then the two grey words that say which minutes: "39
    /// min last time", "23 min so far". On a rest day's card a moon stands where the clock
    /// would (D71), and no minutes.
    private func metaRow(_ card: HomeStart) -> some View {
        HStack(alignment: .center, spacing: 8) {
            if !card.strip.isEmpty {
                WeekStripView(squares: card.strip, shown: card.shownOffset) { shownOffset = $0 }
            }
            Spacer(minLength: 0)
            if card.isRest {
                // Hidden from VoiceOver since S3: the title reads "Rest" first (TS16).
                Image(systemName: "moon.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            } else if let clock = card.clock {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                    Text(clock.minutes)
                    Text(clock.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .font(.subheadline)
    }

    /// The SF Symbol for Core's mark: the play mark on Start and Resume, the moon and the check
    /// on the buttons that do nothing (D71), none on Choose a plan.
    private func mark(_ mark: HomeStart.Mark?) -> String? {
        switch mark {
        case .play: return "play.fill"
        case .moon: return "moon.fill"
        case .check: return "checkmark"
        case nil: return nil
        }
    }

    /// D17: the switch popup's words, as Plan detail says them.
    private var switchPrompt: String {
        guard let session = model.session else { return "Switch workout?" }
        let logged = SessionStats.loggedCount(session)
        return "You're in the middle of \(session.dayName) (\(logged) of \(session.steps.count) sets). "
            + "Switching workouts mid-session isn't recommended."
    }

    /// P5: Start is never blind — the day's exercises are named before you tap it. D61
    /// (v1.7): the block is the preview, one tappable row that opens the day in Plan detail.
    /// D69 (v1.8): the names at body size in ink, each with its sets as blocks at the right
    /// edge; the chevron went — the list is the thing to tap.
    @ViewBuilder private func exerciseBlock(_ card: HomeStart) -> some View {
        if !card.rows.isEmpty {
            if let planId = card.previewPlanId {
                Button {
                    previewing = PlanRoute(id: planId, dayIndex: card.dayIndex ?? 0)
                } label: {
                    exerciseRows(card)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(card.exerciseLabel ?? "")
            } else {
                exerciseRows(card)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(card.exerciseLabel ?? "")
            }
        }
    }

    private func exerciseRows(_ card: HomeStart) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(card.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 12) {
                    Text(row.name)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    SetBlocks(sets: row.sets, logged: row.logged ?? 0, colour: card.dayColour)
                }
            }
            if card.more > 0 {
                Text("and \(card.more) more").foregroundStyle(.secondary)
            }
        }
        .font(.body)
    }

    /// D61 (v1.7): at most one message line, with its own actions — the missed workout (D37),
    /// the progression that has run its course (D44), or notifications off (D57). Each reads
    /// as it read in v1.6; Core chose which.
    private func messageLine(_ message: HomeStart.Message, card: HomeStart) -> some View {
        HStack(spacing: 12) {
            Text(message.text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            switch message {
            case let .missed(missed):
                // An own or borrowed day (D76) is named but not started here until Q4 says how.
                if let dayIndex = missed.dayIndex {
                    Button("Do it now") {
                        if let plan = model.activePlan {
                            start(planId: plan.id, dayIndex: dayIndex)
                        }
                    }
                    .font(.footnote.weight(.medium))
                }
                Button("Dismiss") { dismissedMissed = true }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .progressionFinished:
                // D67 (v1.7): straight to the Progression screen — Plan detail no longer has
                // the row that led there. The active plan's, as Do it now's is: a rest card
                // (D71) has no day to carry it.
                Button("Plan the next one") {
                    if let plan = model.activePlan {
                        planningProgression = PlanRoute(id: plan.id, dayIndex: card.dayIndex ?? 0)
                    }
                }
                .font(.footnote.weight(.medium))
            case .notificationsOff:
                EmptyView()
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .accessibilityElement(children: .contain)
    }

    /// The ··· items, in Core's order. Nothing in the menu is itself a confirmation.
    @ViewBuilder private func alternativeButton(_ alternative: HomeStart.Alternative,
                                                card: HomeStart) -> some View {
        switch alternative {
        case .changePlan:
            Button(alternative.title) { path.append(TodayRoute.plans) }
        case .planProgression:
            Button(alternative.title) {
                if let planId = card.planId {
                    planningProgression = PlanRoute(id: planId, dayIndex: card.dayIndex ?? 0)
                }
            }
        case .discardWorkout:
            Button(alternative.title, role: .destructive) { showDiscardConfirm = true }
        }
    }

    private func act(_ card: HomeStart) {
        // D61 (v1.7): the empty card's button opens Add plan on the built-in picker (D46).
        if card.isEmpty { addPlan = .builtIns; return }
        if card.isInProgress { showWorkout = true; return }
        guard let planId = card.planId, let dayIndex = card.dayIndex else { return }
        start(planId: planId, dayIndex: dayIndex)
    }

    /// D48 (v1.4): the cover opens on `startedWorkouts`, the moment the engine exists; this
    /// task carries on telling the system behind it. D70 (v1.8): a day started from the strip
    /// while a session is open is refused before anything changes, and that raises the popup.
    private func start(planId: UUID, dayIndex: Int, switching choice: SessionSwitch? = nil) {
        Task {
            do {
                try await model.startDay(planId: planId, dayIndex: dayIndex, switching: choice)
            } catch LibraryError.sessionInProgress {
                switching = PlanRoute(id: planId, dayIndex: dayIndex)
            } catch {
                switching = nil
            }
        }
    }

    private func switchDay(_ choice: SessionSwitch) {
        guard let route = switching else { return }
        switching = nil
        start(planId: route.id, dayIndex: route.dayIndex, switching: choice)
    }
}

/// D70 (v1.8, §6.44): the week as a strip — seven squares, today first, each a button that
/// shows its day. The shown square is larger and at full strength; the others at half, as the
/// set blocks are; a rest day's is grey. Colour is never the only cue: the size says which is
/// shown, the button under the card says the day in words, and VoiceOver reads each square as
/// its day, the shown one as selected. The squares are the size of page dots and the tap area
/// is the row's height — the plan's centimetre.
private struct WeekStripView: View {
    let squares: [WeekStrip.Square]
    let shown: Int
    let onTap: (Int) -> Void
    @ScaledMetric(relativeTo: .subheadline) private var small: CGFloat = 10
    @ScaledMetric(relativeTo: .subheadline) private var large: CGFloat = 14
    @ScaledMetric(relativeTo: .subheadline) private var cell: CGFloat = 20

    var body: some View {
        HStack(spacing: 0) {
            ForEach(squares, id: \.offset) { square in
                let isShown = square.offset == shown
                let side = isShown ? large : small
                Button { onTap(square.offset) } label: {
                    RoundedRectangle(cornerRadius: side / 4, style: .continuous)
                        .fill(fill(square, shown: isShown))
                        .frame(width: side, height: side)
                        .frame(width: cell, height: cell + 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(square.spoken)
                .accessibilityAddTraits(isShown ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Seven days")
    }

    private func fill(_ square: WeekStrip.Square, shown: Bool) -> Color {
        guard let colour = square.colour else { return Color.secondary.opacity(shown ? 0.55 : 0.3) }
        return colour.color.opacity(shown ? 1 : 0.5)
    }
}

/// Identifies the plan a Plan detail sheet opens.
private struct PlanRoute: Identifiable {
    let id: UUID
    let dayIndex: Int
}

/// D62 (v1.7): what Today's stack pushes. A plan's detail follows the list as its `UUID`,
/// with the destination declared by the list itself.
private enum TodayRoute: Hashable {
    /// ··· → Change plan: the Plans list, which was a tab until T2.
    case plans
}

/// D69 (v1.8): an exercise's sets as small blocks at the row's right edge — four blocks, four
/// sets — in the day's colour at half strength, each filling to full once logged, so the card
/// shows progress without a fraction. Grey for a session whose day is in no plan, as the square
/// is. The block's spoken label names the exercises; the blocks are hidden from VoiceOver.
private struct SetBlocks: View {
    let sets: Int
    let logged: Int
    let colour: DayColour?
    @ScaledMetric(relativeTo: .body) private var width: CGFloat = 7
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 14

    var body: some View {
        let fill = colour?.color ?? Color.secondary
        HStack(spacing: width / 2) {
            ForEach(0..<sets, id: \.self) { index in
                RoundedRectangle(cornerRadius: width / 3, style: .continuous)
                    .fill(fill.opacity(index < logged ? 1 : 0.5))
                    .frame(width: width, height: height)
            }
        }
        .accessibilityHidden(true)
    }
}

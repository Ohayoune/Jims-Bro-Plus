import SwiftUI

/// SPEC §4.1 (D61, v1.7): Today is the day's card and nothing else — the same five zones on
/// every day of the plan: the day's name, one subtitle, the exercise names (which are the
/// preview), at most one message, and Start in the bottom slot. The day's alternatives live in
/// one ··· and nowhere else. The calendar and the week's line leave for History (D63, T3).
struct HomeView: View {
    @Environment(AppModel.self) private var model
    /// Opens Add plan — on the built-in picker when the empty card asks (D46, v1.4).
    @Binding var addPlan: AddPlanRequest?
    @Binding var showWorkout: Bool
    /// ··· → Change plan: the Plans list. A tab switch until T2 pushes the list from here.
    var changePlan: () -> Void

    @State private var showDiscardConfirm = false
    @State private var previewing: PlanRoute?
    @State private var choosingDay = false
    /// D50 (v1.5): the plan whose progression the ··· item opens.
    @State private var planningProgression: PlanRoute?
    /// D37 (v1.2): the missed-workout notice is dismissible for this run of the app. It is not
    /// persisted: it costs one tap to clear and re-earning it means missing another day.
    @State private var dismissedMissed = false

    var body: some View {
        // Core chooses the one message and the ··· items (D61); this view only draws them.
        let card = HomeStart.current(library: model.library,
                                     notificationsOff: model.showNotificationBanner,
                                     missedDismissed: dismissedMissed)
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text(card.title)
                    .font(.largeTitle.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle = card.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // U13's rule, applied to Today: when Dynamic Type makes the card taller than
                // the screen, the exercise list is what scrolls; the name, the subtitle and
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
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // D61 (v1.7): the only place the day's alternatives live. No ··· at all until
                // there is a plan to have alternatives for.
                if !card.alternatives.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            ForEach(card.alternatives, id: \.self) { alternative in
                                alternativeButton(alternative, card: card)
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("More")
                    }
                }
            }
            // D59 (v1.6): Start in the slot every other screen keeps for its primary button —
            // under the thumb, above the tab bar.
            .bottomAction(if: card.buttonTitle != nil) {
                PrimaryButton(title: card.buttonTitle ?? "") { act(card) }
            }
            // D56 (v1.6): a confirmation reached from a menu is an alert with two named
            // buttons, never a dialog — from a menu anchor a dialog can draw as a popover and
            // drop its cancel-role button.
            .alert("Discard this workout?", isPresented: $showDiscardConfirm) {
                Button("Discard", role: .destructive) { Task { await model.discardSession() } }
                Button("Keep going", role: .cancel) {}
            }
            .confirmationDialog("Which day?", isPresented: $choosingDay, titleVisibility: .visible) {
                if let plan = model.activePlan {
                    ForEach(Array(plan.days.enumerated()), id: \.offset) { index, day in
                        Button(day.name) { start(planId: plan.id, dayIndex: index) }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(item: $previewing) { route in
                NavigationStack { PlanDetailView(planId: route.id, showWorkout: $showWorkout) }
                    .environment(model)
            }
            .sheet(item: $planningProgression) { route in
                ProgressionView(planId: route.id).environment(model)
            }
        }
    }

    /// P5: Start is never blind — the day's exercises are named before you tap it. D61
    /// (v1.7): the block is the preview; the Preview button went. One tappable row with a
    /// trailing chevron that opens the day in Plan detail.
    @ViewBuilder private func exerciseBlock(_ card: HomeStart) -> some View {
        if !card.exercises.isEmpty {
            if let planId = card.previewPlanId {
                Button {
                    previewing = PlanRoute(id: planId, dayIndex: card.dayIndex ?? 0)
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        exerciseNames(card)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(card.exerciseLabel ?? "")
            } else {
                exerciseNames(card)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(card.exerciseLabel ?? "")
            }
        }
    }

    private func exerciseNames(_ card: HomeStart) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(card.exercises.enumerated()), id: \.offset) { _, name in
                Text(name).font(.footnote).foregroundStyle(.secondary)
            }
            if card.more > 0 {
                Text("and \(card.more) more").font(.footnote).foregroundStyle(.tertiary)
            }
        }
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
                Button("Do it now") {
                    if let plan = model.activePlan {
                        start(planId: plan.id, dayIndex: missed.dayIndex)
                    }
                }
                .font(.footnote.weight(.medium))
                Button("Dismiss") { dismissedMissed = true }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .progressionFinished:
                Button("Plan the next one") {
                    if let planId = card.planId {
                        previewing = PlanRoute(id: planId, dayIndex: card.dayIndex ?? 0)
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
        case .anotherDay:
            Button(alternative.title) { choosingDay = true }
        case .changePlan:
            Button(alternative.title, action: changePlan)
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
    /// task carries on telling the system behind it.
    private func start(planId: UUID, dayIndex: Int) {
        Task { try? await model.startDay(planId: planId, dayIndex: dayIndex) }
    }
}

/// Identifies the plan a Plan detail sheet opens.
private struct PlanRoute: Identifiable {
    let id: UUID
    let dayIndex: Int
}

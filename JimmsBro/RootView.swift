import SwiftUI
import UIKit

/// Why Add plan is opening: the ordinary sheet, or — for the screenshot hook alone — a draft
/// part-way through. An item rather than a Bool and a flag, because a sheet's content closure
/// runs with the state it captured before the tap that presented it — a flag set in the same
/// tap arrived at the sheet as false — while an item is handed to the closure as it is.
/// (v1.4–v1.10 had a `.builtIns` case for the pushed picker; D90 put the built-in plans on the
/// Add plan screen itself, so every door opens the same screen and the case went in N6.)
enum AddPlanRequest: Identifiable, Equatable {
    case plan
    /// D52 (v1.5): a plan being built day by day, for the screenshot hook.
    case draft
    var id: Self { self }
}

struct RootView: View {
    @State private var model: AppModel
    @State private var addPlan: AddPlanRequest?
    @State private var showWorkout = false
    @State private var tab: AppTab = .today
    /// D47 (v1.4): the intro's primary action was tapped, so Add plan opens on the picker
    /// once the cover is down — presenting a sheet while a cover is dismissing loses one.
    @State private var introChosePlan = false

    init(model: AppModel) { _model = State(initialValue: model) }

    var body: some View {
        // D62 (v1.7): two tabs, Today · History — `AppTab`, in its order and nothing else, so
        // the bar is the list a test holds to SPEC §4.0 (T7). Plans is Today's ··· → Change
        // plan; Settings is the gear on both tabs (`settingsGear`).
        TabView(selection: $tab) {
            ForEach(AppTab.allCases, id: \.self) { item in
                screen(item)
                    .tabItem { Label(item.title, systemImage: item.symbol) }
                    .tag(item)
            }
        }
        // D47 (v1.4): the introduction, over the tabs, on a launch with no plans where it has
        // not been dismissed (SPEC §5.1). `introDue` is the model's, so dismissing is a
        // setting change and the cover follows it.
        .fullScreenCover(isPresented: Binding(
            get: { model.introDue },
            set: { if !$0 { Task { await model.markIntroSeen() } } }),
                         onDismiss: {
            if introChosePlan {
                introChosePlan = false
                addPlan = .plan
            }
        }) {
            IntroductionView(purpose: .firstRun,
                             choosePlan: { introChosePlan = true; Task { await model.markIntroSeen() } },
                             dismiss: { Task { await model.markIntroSeen() } })
        }
        .onAppear(perform: applyScreenshotArguments)
        .environment(model)
        .task { if !model.loaded { await model.load() } }
        .sheet(item: $addPlan) { request in
            ImportView(opening: request).environment(model)
        }
        .fullScreenCover(isPresented: $showWorkout) {
            NavigationStack { WorkoutView() }
                .environment(model)
                // SPEC §4.11: the screen stays awake during a workout unless the setting is off.
                .persistentSystemOverlays(.hidden)
        }
        .onChange(of: showWorkout) { _, showing in
            UIApplication.shared.isIdleTimerDisabled = showing && model.settings.keepAwake
        }
        // D48 (v1.4): a workout that has just been started opens at once. The views that start
        // one no longer wait for `startDay` — the notification, the Live Activity and the disk
        // write — before presenting; the count changes the moment the engine exists.
        .onChange(of: model.startedWorkouts) { _, _ in showWorkout = true }
        .onChange(of: model.hasActiveSession) { _, running in
            // Keep the cover up while the Summary is still on screen.
            if !running && model.justCompleted == nil { showWorkout = false }
        }
        .problemAlert("A data file couldn't be read and was set aside", message: Binding(
            get: { model.showCorruptAlert ? model.corruptFiles.joined(separator: "\n") : nil },
            set: { if $0 == nil { model.dismissCorruptAlert() } }))
        // D24 (v1.1): a failed write says so and offers Retry, rather than a silent try?.
        // Only while the workout cover is down — the cover is presented over this view, so an
        // alert attached here cannot be seen (and cancels the cover's own presentation) while
        // it is up. `WorkoutView` carries the same alert for that case.
        .saveFailureAlert(model: model, enabled: !showWorkout)
    }

    /// Debug-only navigation hook so screenshot runs can open a screen directly.
    /// Compiled out of release builds; it does nothing without the launch argument.
    private func applyScreenshotArguments() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        // Screenshot runs would otherwise be covered by the system's permission alert.
        if arguments.contains("-uiNoAsk") { model.askedForNotifications = true }
        guard let index = arguments.firstIndex(of: "-uiScreen"),
              let name = arguments[safe: index + 1] else { return }
        if name == "import" {
            // v1.5: `-uiDraft` opens a draft part-way through (D52). `-uiBuiltIns` (v1.4) is
            // taken and ignored: since D90 the built-in plans are a row on this same screen.
            addPlan = arguments.contains("-uiDraft") ? .draft : .plan
        } else if name == "workout" {
            // The screenshot run starts the card's day, optionally logs some sets to reach a
            // later phase, and opens the workout.
            Task {
                await model.waitUntilLoaded()
                if !model.hasActiveSession { try? await model.startFromCard() }
                showWorkout = true
                if let index = arguments.firstIndex(of: "-uiAdvance"),
                   let count = arguments[safe: index + 1].flatMap(Int.init) {
                    // v1.2: `-uiSkipWaits` skips the waits *inside* an exercise — the warm-up
                    // and the rests between sets — and deliberately never skips the walk between
                    // exercises, so a run of N sets ends on that countdown, which is a state
                    // worth screenshotting.
                    let skippable: Set<RestKind> = [.warmUp, .betweenSets]
                    @MainActor func skipWaitIfAsked() async {
                        guard arguments.contains("-uiSkipWaits"),
                              case let .resting(rest)? = model.phase,
                              skippable.contains(rest.kind) else { return }
                        await model.apply(.skipRest)
                    }
                    for _ in 0..<count {
                        // A session now opens in a warm-up (D32), so the loop has to be able to
                        // step out of a break before it can log anything at all.
                        await skipWaitIfAsked()
                        guard case let .working(step)? = model.phase else { break }
                        let target = model.session?.target(at: step)
                        if target?.work.isTimed == true {
                            await model.apply(.startTimer(step: step))
                            // Fixed durations end with Done; only open ones take Stop.
                            if case .duration = target?.work {
                                await model.apply(.timerDone(step: step))
                            } else {
                                await model.apply(.stopTimer(step: step))
                            }
                        } else {
                            await model.apply(.logSet(step: step, result: .reps(count: 8, weight: target?.weight)))
                        }
                        // Step past rests (and, separately, block-done banners) so the count
                        // means "sets logged" rather than "events".
                        await skipWaitIfAsked()
                        if arguments.contains("-uiSkipDone"), model.blockDone != nil {
                            await model.apply(.dismissBlockDone)
                        }
                    }
                }
            }
        } else if let requested = AppTab(rawValue: name)
                    ?? (["home", "plans", "settings"].contains(name) ? .today : nil) {
            // `home` is kept for the scripts written before T1 renamed the tab; `plans` and
            // `settings` stopped being tabs in T2 (D62) and land on Today, which pushes them.
            tab = requested
        }
        #endif
    }

    /// Each tab's screen. D61 (v1.7): Home became Today — one card.
    @ViewBuilder private func screen(_ tab: AppTab) -> some View {
        switch tab {
        case .today: HomeView(addPlan: $addPlan, showWorkout: $showWorkout)
        case .history: HistoryView()
        }
    }
}

extension View {
    /// F3 (2026-09-24): a screen holding edits keeps them until you say otherwise. While `dirty`
    /// the swipe that closes its sheet does nothing, and its way out — Cancel, or a pushed
    /// screen's back — asks first, in an alert with two named buttons (§4.0, D56). Until F3 every
    /// sheet but Add plan's draft dropped its edits without a word.
    func discardGuard(_ dirty: Bool, asking: Binding<Bool>, discard: @escaping () -> Void) -> some View {
        interactiveDismissDisabled(dirty)
            .alert("Discard changes?", isPresented: asking) {
                Button("Discard", role: .destructive, action: discard)
                Button("Keep editing", role: .cancel) {}
            }
    }

    /// D24 (v1.1): the save-failure alert, attached wherever the user can actually see it.
    /// Saves fail most often mid-workout, which is exactly when the workout cover is over
    /// `RootView`, so the alert has to be presented from whichever view is on top.
    func saveFailureAlert(model: AppModel, enabled: Bool) -> some View {
        // Captured here, synchronously, while the alert is still up. Presenting the alert
        // clears `saveFailure` on dismissal, and Retry's own `Task` runs after that — so a
        // Retry that read the property from inside the Task always found nil (v1.2).
        let failure = model.saveFailure
        return alert(failure?.message ?? "",
                     isPresented: Binding(
                        get: { enabled && model.saveFailure != nil },
                        // Only a dismissal clears the failure. Without the `enabled` guard here,
                        // the copy that is switched off would clear it the moment the other one
                        // took over.
                        set: { if !$0 && enabled { model.saveFailure = nil } })) {
            Button("Retry") { Task { await model.retrySaveFailure(failure) } }
            Button("Later", role: .cancel) {}
        }
    }
}

extension View {
    /// D62 (v1.7): Settings is not a tab. The same gear, in the same place — top-left — on
    /// Today and on History pushes it (P1: zones do not move). Pushed rather than presented, so
    /// what Settings presents, and the introduction that Delete all data makes due again,
    /// present over the tabs as they did when Settings was one.
    /// D69 (v1.8): drawn as a `QuietGlyph`, lighter than the title under it.
    func settingsGear(_ isPresented: Binding<Bool>) -> some View {
        toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { isPresented.wrappedValue = true } label: {
                    QuietGlyph(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
            .quietBackground()
        }
        .navigationDestination(isPresented: isPresented) { SettingsView() }
    }
}

/// D69 (v1.8): a toolbar control drawn lighter than the title under it — a grey glyph in a
/// hairline circle, where iOS 26 fills a circle of glass. Today's gear and ···, and History's
/// gear, which is the same one (P1: zones do not move).
struct QuietGlyph: View {
    let systemName: String
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 32
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Image(systemName: systemName)
            .font(.body)
            .foregroundStyle(.secondary)
            .frame(width: side, height: side)
            .overlay(Circle().strokeBorder(Color(.separator), lineWidth: 1 / displayScale))
            .contentShape(Circle())
    }
}

extension ToolbarContent {
    /// D69 (v1.8): no shared glass behind a `QuietGlyph` — its own circle is the button's edge.
    @ToolbarContentBuilder func quietBackground() -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

extension Color {
    /// SPEC §4.0 (v1.1): one colour reserved for "this already happened" — a logged set, a
    /// personal record. The accent means "you can act on this"; using it for both made a
    /// finished row look like a control. System green, so it adapts to dark mode on its own.
    static let done = Color.green
}

/// SPEC §4.0 (v1.1): the one grouped container. Screens built from a `List` get this look from
/// `.insetGrouped`; the workout screen cannot be a List without giving up its fixed zones (D22),
/// so it uses this instead and ends up speaking the same visual language.
struct InsetGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .padding(.vertical, 4)
            .padding(.horizontal, 12)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

extension View {
    /// SPEC §4.0 (v1.1): the bottom-anchored primary action, with a bar behind it so scrolling
    /// content passes under it instead of showing through it. One definition, so the button sits
    /// at the same height with the same padding on every screen that has one.
    /// D56 (v1.6): `if shown` is false → no inset at all. The padding and the bar used to be
    /// applied even when the content was empty, which drew a small white rectangle at the
    /// bottom of Add plan and Progression before anything had been pasted.
    func bottomAction<Content: View>(if shown: Bool = true,
                                     @ViewBuilder _ content: () -> Content) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            if shown {
                content()
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    .background(.bar)
            }
        }
    }
}

/// D30 (v1.1): a personal record, in the colour reserved for "this happened" (§4.0).
struct PRBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.done.opacity(0.18), in: Capsule())
            .foregroundStyle(Color.done)
            .accessibilityLabel("Personal record, " + text.replacingOccurrences(of: "PR ", with: ""))
    }
}

/// SPEC §4.0 (v1.1, O78): a row that shows it was pressed. `.plain` keeps a row looking like a
/// row, but leaves a tap with no acknowledgement at all.
struct PressableRow: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.secondary.opacity(0.12) : .clear)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// SPEC §4.0: one primary action per screen, full width, accent colour.
struct PrimaryButton: View {
    let title: String
    /// D69 (v1.8): a mark before the words, so the button says what it does before it is read —
    /// the play mark on Today's Start and Resume.
    var systemImage: String? = nil
    var enabled = true
    /// D79 (v1.10, §6.52): ink rather than the accent — the Workout screen's, where blue is
    /// reserved for the current set. Black in light, white in dark, its label the background.
    var ink = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .frame(maxWidth: .infinity)
            .modifier(Ink(label: ink && enabled))
        }
        .buttonStyle(.borderedProminent)
        .modifier(Ink(fill: ink))
        .controlSize(.large)
        .disabled(!enabled)
    }

    /// Leaves an accent button exactly as it was: nothing is applied unless the button is ink.
    private struct Ink: ViewModifier {
        var label = false
        var fill = false

        func body(content: Content) -> some View {
            if label {
                content.foregroundStyle(Color(.systemBackground))
            } else if fill {
                content.tint(.primary)
            } else {
                content
            }
        }
    }
}

/// D59 (v1.6): a row that wraps. The repeat block's chips and Home's small buttons used to
/// scroll off the right edge with nothing on screen to say so; nobody needs them on one line.
struct WrapLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + lineSpacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: width == .infinity ? widest : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX; y += rowHeight + lineSpacing; rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

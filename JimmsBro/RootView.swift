import SwiftUI
import UIKit

/// The four tabs of SPEC §4.0. Home carries no navigation chrome of its own.
/// Why Add plan is opening: the ordinary sheet, or the sheet with the built-in picker already
/// on it (D46, v1.4). An item rather than a Bool and a flag, because a sheet's content closure
/// runs with the state it captured before the tap that presented it — a flag set in the same
/// tap arrived at the sheet as false — while an item is handed to the closure as it is.
enum AddPlanRequest: Identifiable, Equatable {
    case plan, builtIns
    var id: Self { self }
}

struct RootView: View {
    enum Tab: String { case home, plans, history, settings }

    @State private var model: AppModel
    @State private var addPlan: AddPlanRequest?
    @State private var showWorkout = false
    @State private var tab: Tab = .home

    init(model: AppModel) { _model = State(initialValue: model) }

    var body: some View {
        TabView(selection: $tab) {
            HomeView(addPlan: $addPlan, showWorkout: $showWorkout)
                .tabItem { Label("Home", systemImage: "house") }
                .tag(Tab.home)
            PlansView(addPlan: $addPlan, showWorkout: $showWorkout)
                .tabItem { Label("Plans", systemImage: "list.bullet") }
                .tag(Tab.plans)
            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(Tab.history)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .onAppear(perform: applyScreenshotArguments)
        .environment(model)
        .task { if !model.loaded { await model.load() } }
        .sheet(item: $addPlan) { request in
            ImportView(openBuiltIns: request == .builtIns).environment(model)
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
        .alert("A data file couldn't be read and was set aside",
               isPresented: Binding(get: { model.showCorruptAlert },
                                    set: { if !$0 { model.dismissCorruptAlert() } })) {
            Button("OK", role: .cancel) { model.dismissCorruptAlert() }
        } message: {
            Text(model.corruptFiles.joined(separator: "\n"))
        }
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
            // v1.4: `-uiBuiltIns` opens Add plan on the built-in picker (D46).
            addPlan = arguments.contains("-uiBuiltIns") ? .builtIns : .plan
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
        } else if let requested = Tab(rawValue: name) {
            tab = requested
        }
        #endif
    }
}

extension View {
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
    func bottomAction<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            content()
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(.bar)
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
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!enabled)
    }
}

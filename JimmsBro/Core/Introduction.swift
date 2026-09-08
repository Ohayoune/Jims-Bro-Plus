import Foundation

/// D47 (v1.4): one page of the introduction — a symbol, a line, a paragraph.
struct IntroPage: Equatable {
    let symbol: String
    let title: String
    let body: String
}

/// D47 (v1.4): the introduction, said once. The app's premise is a loop nobody has seen
/// before — a plan, Start, log the set, the rest runs itself, the app remembers — and the first
/// screen a stranger used to see was "No plan yet". The pages are data here rather than text in
/// a view, so what the app claims about itself is a test: every control a page names must
/// exist by exactly that name (Y13), and a rename that leaves the intro behind goes red.
enum Introduction {
    static let pages: [IntroPage] = [
        IntroPage(
            symbol: "figure.strengthtraining.traditional",
            title: "A plan, then Start",
            body: "Jimm's Bro+ runs your workout for you. Pick a plan, tap Start, and the app "
                + "walks you through the day one set at a time: the exercise, the target, and "
                + "the weight you lifted last time."),
        IntroPage(
            symbol: "timer",
            title: "Log the set, rest, repeat",
            body: "Type what you did and tap Log set. The rest timer starts on its own and "
                + "counts down on the Lock Screen and in the Dynamic Island; when it ends, the "
                + "next set is up. A hold gets a countdown of its own."),
        IntroPage(
            symbol: "chart.line.uptrend.xyaxis",
            title: "It remembers",
            body: "Every set is kept. Next time the weight is already filled in, and when you "
                + "hit the top of your rep range the app tells you to add weight. History holds "
                + "every workout, your records, and a chart for each exercise."),
        IntroPage(
            symbol: "text.bubble",
            title: "Your plan, your way",
            body: "Start with a built-in plan, or have a chatbot write one from your own "
                + "description: Add plan's Create with a chatbot copies the prompt, and its "
                + "reply pastes straight back in. Later, Progression asks the chatbot to plan "
                + "your next weeks from what you actually lifted."),
    ]

    /// The controls the pages name. Each must exist by exactly this name somewhere in the
    /// app, which is what pins the copy to the screens (Y13).
    static let namedControls = [
        "Start", "Log set", "Add plan", "Create with a chatbot", "History", "Progression",
        "built-in plan",
    ]

    /// The primary action on a first launch: dismisses the intro and opens Add plan on the
    /// built-in picker. From Settings the same screen ends on `done` instead.
    static let choosePlan = "Choose a plan"
    static let notNow = "Not now"
    static let done = "Done"

    /// SPEC §5.1: the introduction is due on a launch where the store holds no plans and it
    /// has not been dismissed. Never over a phone that already has plans — that phone gets
    /// the row in Settings, not a cover.
    static func isDue(plans: [Plan], settings: Settings) -> Bool {
        plans.isEmpty && !settings.introSeen
    }
}

import ActivityKit
import SwiftUI
import WidgetKit

/// SPEC §6.17 (D40, v1.2): the timer on the Lock Screen and in the Dynamic Island.
///
/// Every countdown is drawn with `Text(timerInterval:)`, which the **system** ticks — the app
/// does not have to be awake, and does not have to push an update every second. That is the
/// same rule as §6.4's Date-based rest timer, one layer out.
///
/// D41 (v1.3): the compact Island is the timer and one symbol, nothing else, at a fixed width.
/// `Text(timerInterval:)` reserves room for the widest string it might ever draw, so it is
/// given a range that never reaches an hour (`WorkoutActivityState.timerRange`), told not to
/// show hours, and boxed to the width of "59:59" in its font.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            lockScreen(context.state)
                .padding(12)
                .activityBackgroundTint(Color(.systemBackground).opacity(0.7))
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        if let colour = context.state.dayColour { DaySquare(colour: colour, size: 8) }
                        Text(context.state.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(context.state.isBreak ? Color.accentColor : .primary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    timer(context.state)
                        .font(.title3.monospacedDigit())
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        progress(context.state)
                    }
                }
            } compactLeading: {
                // D65 (v1.7): besides the timer this form has room for a colour and nothing
                // else, so the figure takes the day's while working; a break keeps its own.
                Image(systemName: context.state.isBreak ? "hourglass" : "figure.strengthtraining.traditional")
                    .font(.caption)
                    .foregroundStyle(context.state.isBreak ? Color.accentColor
                                     : (context.state.dayColour?.color ?? .primary))
            } compactTrailing: {
                compactTimer(context.state, width: 42, font: .caption)
            } minimal: {
                compactTimer(context.state, width: 36, font: .caption2)
            }
            .keylineTint(context.state.isBreak ? .accentColor : .green)
        }
    }

    @ViewBuilder private func lockScreen(_ state: WorkoutActivityState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                // D65 (v1.7): the day's square, as it leads the workout header in the app.
                if let colour = state.dayColour { DaySquare(colour: colour) }
                Text(state.title)
                    .font(.headline)
                    .foregroundStyle(state.isBreak ? Color.accentColor : .primary)
                    .lineLimit(1)
                Spacer(minLength: 12)
                timer(state)
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            Text(state.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            progress(state)
        }
    }

    /// A countdown to `endsAt`, a count-up from `startedAt`, or the plain progress when
    /// nothing is running — the three states `WorkoutActivityState` can be in.
    @ViewBuilder private func timer(_ state: WorkoutActivityState) -> some View {
        if let range = state.timerRange() {
            Text(timerInterval: range, countsDown: state.timerCountsDown, showsHours: false)
                .multilineTextAlignment(.trailing)
        } else {
            Text("\(state.done)/\(state.total)")
        }
    }

    /// The compact and minimal Island: the same timer, boxed. The box is what keeps the
    /// Island narrow — without it the text claims the width of the longest string it could
    /// ever show, whatever it is showing now.
    @ViewBuilder private func compactTimer(_ state: WorkoutActivityState, width: CGFloat,
                                          font: Font) -> some View {
        if let range = state.timerRange() {
            Text(timerInterval: range, countsDown: state.timerCountsDown, showsHours: false)
                .font(font.monospacedDigit())
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: width)
                .foregroundStyle(state.isBreak ? Color.accentColor : .primary)
        } else {
            Text("\(state.done)/\(state.total)")
                .font(font.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: width)
        }
    }

    /// D79 (v1.10, §6.52): the bar takes the Workout screen's states — done in the day's colour,
    /// in a break as while working, over the grey of the sets ahead.
    private func progress(_ state: WorkoutActivityState) -> some View {
        ProgressView(value: state.total > 0 ? Double(state.done) / Double(state.total) : 0)
            .tint(MarkState.done.color(day: state.dayColour))
    }
}

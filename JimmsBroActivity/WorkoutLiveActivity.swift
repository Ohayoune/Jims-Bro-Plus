import ActivityKit
import SwiftUI
import WidgetKit

/// SPEC §6.17 (D40, v1.2): the timer on the Lock Screen and in the Dynamic Island.
///
/// Every countdown is drawn with `Text(timerInterval:)`, which the **system** ticks — the app
/// does not have to be awake, and does not have to push an update every second. That is the
/// same rule as §6.4's Date-based rest timer, one layer out.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            lockScreen(context.state)
                .padding(16)
                .activityBackgroundTint(Color(.systemBackground).opacity(0.7))
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(context.state.isBreak ? Color.accentColor : .primary)
                        .lineLimit(1)
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
                Image(systemName: context.state.isBreak ? "hourglass" : "figure.strengthtraining.traditional")
                    .foregroundStyle(context.state.isBreak ? Color.accentColor : .primary)
            } compactTrailing: {
                timer(context.state).font(.caption.monospacedDigit())
            } minimal: {
                timer(context.state).font(.caption2.monospacedDigit())
            }
            .keylineTint(context.state.isBreak ? .accentColor : .green)
        }
    }

    @ViewBuilder private func lockScreen(_ state: WorkoutActivityState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(state.title)
                    .font(.headline)
                    .foregroundStyle(state.isBreak ? Color.accentColor : .primary)
                Spacer(minLength: 12)
                timer(state)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            Text(state.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            progress(state)
        }
    }

    /// A countdown to `endsAt`, a count-up from `startedAt`, or the plain progress when
    /// nothing is running — the three states `WorkoutActivityState` can be in.
    @ViewBuilder private func timer(_ state: WorkoutActivityState) -> some View {
        if let endsAt = state.endsAt {
            Text(timerInterval: Date()...max(endsAt, Date().addingTimeInterval(1)),
                 countsDown: true)
                .multilineTextAlignment(.trailing)
        } else if let startedAt = state.startedAt {
            Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
                .multilineTextAlignment(.trailing)
        } else {
            Text("\(state.done)/\(state.total)")
        }
    }

    private func progress(_ state: WorkoutActivityState) -> some View {
        ProgressView(value: state.total > 0 ? Double(state.done) / Double(state.total) : 0)
            .tint(state.isBreak ? Color.accentColor : .green)
    }
}

import ActivityKit
import SwiftUI
import WidgetKit

struct RestLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Repos")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(context.state.exercise)
                        .font(.headline)
                        .lineLimit(2)
                    if !context.state.detail.isEmpty {
                        Text(context.state.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Countdown(end: context.state.endsAt)
                    .font(.largeTitle.weight(.bold).width(.expanded))
            }
            .padding(16)
            .activityBackgroundTint(nil)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Repos", systemImage: "timer")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(end: context.state.endsAt)
                        .font(.title3.weight(.bold).width(.expanded))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.exercise).lineLimit(1)
                        Spacer()
                        Text(context.state.detail).foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(.orange)
            } compactTrailing: {
                Countdown(end: context.state.endsAt)
                    .frame(maxWidth: 48)
                    .foregroundStyle(.orange)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(.orange)
            }
        }
    }
}

private struct Countdown: View {
    let end: Date

    var body: some View {
        Text(timerInterval: Date.now...max(end, .now), countsDown: true)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
    }
}

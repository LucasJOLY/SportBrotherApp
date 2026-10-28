import ActivityKit
import SwiftUI
import WidgetKit

@main
struct RepasJOLYWidgets: WidgetBundle {
    var body: some Widget {
        CookingLiveActivity()
    }
}

struct CookingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CookingActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .padding(16)
                .activityBackgroundTint(nil)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Cuisson", systemImage: "flame.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ElapsedText(state: context.state)
                        .font(.title3.weight(.bold).width(.expanded))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.attributes.recipeTitle).lineLimit(1)
                        Spacer()
                        if let end = context.state.stepTimerEnd, end > .now {
                            Label {
                                Text(timerInterval: Date.now...end, countsDown: true).monospacedDigit()
                            } icon: {
                                Image(systemName: "timer")
                            }
                            .foregroundStyle(.orange)
                        }
                    }
                    .font(.subheadline)
                }
            } compactLeading: {
                Image(systemName: "flame.fill").foregroundStyle(.orange)
            } compactTrailing: {
                if let end = context.state.stepTimerEnd, end > .now {
                    Text(timerInterval: Date.now...end, countsDown: true)
                        .monospacedDigit()
                        .frame(maxWidth: 48)
                        .foregroundStyle(.orange)
                } else {
                    ElapsedText(state: context.state).frame(maxWidth: 52)
                }
            } minimal: {
                Image(systemName: context.state.stepTimerEnd != nil ? "timer" : "flame.fill")
                    .foregroundStyle(.orange)
            }
        }
    }
}

private struct ElapsedText: View {
    let state: CookingActivityAttributes.ContentState

    var body: some View {
        Group {
            if state.isPaused {
                Text(Duration.seconds(state.pausedElapsed).formatted(.time(pattern: .minuteSecond)))
            } else {
                Text(state.elapsedAnchor, style: .timer)
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
    }
}

private struct LockScreenView: View {
    let attributes: CookingActivityAttributes
    let state: CookingActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(attributes.recipeTitle)
                    .font(.headline)
                    .lineLimit(2)
                Text(state.isPaused ? "En pause · \(state.stepLabel)" : state.stepLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let end = state.stepTimerEnd, end > .now {
                    Label {
                        Text(timerInterval: Date.now...end, countsDown: true).monospacedDigit()
                    } icon: {
                        Image(systemName: "timer")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                }
            }
            Spacer()
            ElapsedText(state: state)
                .font(.title.weight(.bold).width(.expanded))
                .opacity(state.isPaused ? 0.5 : 1)
        }
    }
}

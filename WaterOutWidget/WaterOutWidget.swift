import ActivityKit
import SwiftUI
import WidgetKit

@main
struct WaterOutWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PlaybackActivity.self) { context in
            HStack(spacing: 14) {
                Image(systemName: "waveform")
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.t("app.title")).font(.headline)
                    Text(L.t("activity.open")).font(.caption)
                }
                Spacer()
                countdown(context)
            }
            .padding()
            .activityBackgroundTint(Color(red: 0.88, green: 0.95, blue: 0.94))
            .foregroundStyle(Color(red: 0.06, green: 0.15, blue: 0.21))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Label(L.t("app.title"), systemImage: "waveform") }
                DynamicIslandExpandedRegion(.trailing) { countdown(context) }
                DynamicIslandExpandedRegion(.bottom) { Text(L.t("activity.open")).font(.caption) }
            } compactLeading: {
                Image(systemName: "waveform")
            } compactTrailing: {
                countdown(context)
            } minimal: {
                Image(systemName: "waveform")
            }
        }
    }

    private func countdown(_ context: ActivityViewContext<PlaybackActivity>) -> some View {
        Text(timerInterval: context.state.start...context.state.end, countsDown: true)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .frame(width: 48)
    }
}

import ActivityKit
import SwiftUI
import WidgetKit

struct PlanetFocusCountdownLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PlanetFocusCountdownAttributes.self) { context in
            VStack(alignment: .leading, spacing: 6) {
                Text("Planet Focus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PlanetFocusLiveActivityPalette.paleBlue)
                Text(context.attributes.storyTitle)
                    .font(.headline)
                    .lineLimit(1)
                CountdownText(endDate: context.state.scheduledEndAt, font: .title2)
            }
            .padding()
            .activityBackgroundTint(PlanetFocusLiveActivityPalette.ink)
            .activitySystemActionForegroundColor(PlanetFocusLiveActivityPalette.paleBlue)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("PF").font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CountdownText(endDate: context.state.scheduledEndAt)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.storyTitle).lineLimit(1)
                }
            } compactLeading: {
                Text("PF")
            } compactTrailing: {
                CountdownText(endDate: context.state.scheduledEndAt)
            } minimal: {
                CountdownText(endDate: context.state.scheduledEndAt)
            }
            .keylineTint(PlanetFocusLiveActivityPalette.warmYellow)
        }
    }
}

private struct CountdownText: View {
    let endDate: Date
    var font: Font = .body

    var body: some View {
        // Take one snapshot so the end cannot pass between the comparison and
        // creation of SwiftUI's closed timer range.
        let now = Date.now
        if let interval = PlanetFocusCountdownDisplay.timerInterval(endingAt: endDate, now: now) {
            Text(timerInterval: interval, countsDown: true)
                .font(font.monospacedDigit())
                .foregroundStyle(PlanetFocusLiveActivityPalette.warmYellow)
                .accessibilityLabel("Remaining focus time")
        } else {
            Text("0:00")
                .font(font.monospacedDigit())
                .foregroundStyle(PlanetFocusLiveActivityPalette.warmYellow)
                .accessibilityLabel("Remaining focus time, zero")
        }
    }
}

@main
struct PlanetFocusLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        PlanetFocusCountdownLiveActivity()
    }
}

private enum PlanetFocusLiveActivityPalette {
    static let ink = Color(red: 10 / 255, green: 17 / 255, blue: 36 / 255)
    static let paleBlue = Color(red: 174 / 255, green: 199 / 255, blue: 251 / 255)
    static let warmYellow = Color(red: 247 / 255, green: 163 / 255, blue: 55 / 255)
}

import ActivityKit
import SwiftUI
import WidgetKit

/// Виджетная часть Live Activity (тест 17): экран блокировки и Dynamic Island.
/// Запуск/обновление/завершение активности выполняет приложение (ExtLiveActivityProbe).
struct ScarletProbeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ScarletProbeActivityAttributes.self) { context in
            // Экран блокировки / баннер.
            LockScreenView(
                title: context.attributes.title,
                message: context.state.message,
                endTime: context.state.endTime
            )
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.4))
            .activitySystemActionForegroundColor(Color.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.title, systemImage: "timer")
                        .font(.caption)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CountdownText(endTime: context.state.endTime)
                        .font(.caption.monospacedDigit())
                        .frame(maxWidth: 64)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.message)
                        .font(.caption2)
                }
            } compactLeading: {
                Image(systemName: "timer")
            } compactTrailing: {
                CountdownText(endTime: context.state.endTime)
                    .font(.caption2.monospacedDigit())
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "timer")
            }
        }
    }
}

/// Текст обратного отсчёта с защитой диапазона (lowerBound <= upperBound),
/// чтобы не упасть, если endTime уже в прошлом.
private struct CountdownText: View {
    let endTime: Date

    var body: some View {
        let now = Date.now
        let range = min(now, endTime)...max(now, endTime)
        return Text(timerInterval: range, countsDown: true)
    }
}

private struct LockScreenView: View {
    let title: String
    let message: String
    let endTime: Date

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "timer")
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.caption)
            }
            Spacer(minLength: 0)
            CountdownText(endTime: endTime)
                .font(.title3.monospacedDigit())
        }
    }
}

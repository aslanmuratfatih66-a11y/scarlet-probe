import SwiftUI
import WidgetKit

/// Запись таймлайна: текст и время последнего обновления, прочитанные из App Group.
struct ScarletProbeWidgetEntry: TimelineEntry, Sendable {
    let date: Date
    let text: String
    let lastUpdate: Date?
}

/// TimelineProvider: читает данные из App Group на каждый запрос.
struct ScarletProbeWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScarletProbeWidgetEntry {
        ScarletProbeWidgetEntry(date: Date(), text: "ScarletProbe", lastUpdate: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (ScarletProbeWidgetEntry) -> Void) {
        completion(Self.currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScarletProbeWidgetEntry>) -> Void) {
        // Данные обновляются приложением через WidgetCenter.reloadAllTimelines(),
        // поэтому собственного расписания не нужно.
        let timeline = Timeline(entries: [Self.currentEntry()], policy: .never)
        completion(timeline)
    }

    private static func currentEntry() -> ScarletProbeWidgetEntry {
        ScarletProbeWidgetEntry(
            date: Date(),
            text: WidgetBridge.currentText() ?? "нет данных",
            lastUpdate: WidgetBridge.currentDate()
        )
    }
}

/// Представление виджета.
struct ScarletProbeWidgetView: View {
    let entry: ScarletProbeWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ScarletProbe")
                .font(.headline)
            Text(entry.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Spacer(minLength: 0)
            if let lastUpdate = entry.lastUpdate {
                Text("Обновлено: \(lastUpdate.formatted(date: .omitted, time: .standard))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text("App Group пуст")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// WidgetKit-виджет (StaticConfiguration) — тест 16.
struct ScarletProbeWidget: Widget {
    let kind = "ScarletProbeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ScarletProbeWidgetProvider()) { entry in
            ScarletProbeWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("ScarletProbe")
        .description("Проверка WidgetKit и App Group после сайдлоада.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

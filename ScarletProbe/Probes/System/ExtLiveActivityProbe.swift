import SwiftUI
@preconcurrency import ActivityKit

/// Тест 17: Live Activity (ActivityKit) — запуск, обновление, завершение.
@MainActor
@Observable
final class ExtLiveActivityProbe: ProbeTest {
    let id = 17
    let title = "Live Activity"
    var timeout: Duration { .seconds(30) }

    /// Текущая активность (для ручного обновления/завершения на экране теста).
    private var activity: Activity<ScarletProbeActivityAttributes>?
    var activityID: String?
    var statusLines: [String] = []

    var detailView: AnyView? { AnyView(ExtLiveActivityDetailView(probe: self)) }

    func run() async -> ProbeResult {
        var lines: [String] = []

        let enabled = ActivityAuthorizationInfo().areActivitiesEnabled
        lines.append("areActivitiesEnabled: \(enabled)")
        lines.append("Info.plist приложения: NSSupportsLiveActivities = true (подтверждено брифом — присутствует).")

        guard enabled else {
            lines.append("Live Activities выключены (Настройки → ScarletProbe → Live-активности) или не поддерживаются устройством — запуск невозможен.")
            statusLines = lines
            return .fail(lines.joined(separator: "\n"))
        }

        // Завершаем предыдущую активность, если она осталась.
        await endIfRunning()

        let end = Date.now.addingTimeInterval(5 * 60)
        let attributes = ScarletProbeActivityAttributes(title: "ScarletProbe")
        let startState = ScarletProbeActivityAttributes.ContentState(endTime: end, message: "Таймер запущен")
        do {
            let started = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: startState, staleDate: nil),
                pushType: nil
            )
            activity = started
            activityID = started.id
            lines.append("Activity.request: OK, id=\(started.id)")
            log("Live Activity запущена: \(started.id)")
        } catch {
            lines.append("Activity.request: ошибка\n\(ProbeLogger.describe(error))")
            statusLines = lines
            return .fail(lines.joined(separator: "\n"))
        }

        // Обновление через 2 секунды.
        try? await Task.sleep(for: .seconds(2))
        if let activity {
            let updated = ScarletProbeActivityAttributes.ContentState(endTime: end, message: "Обновлено из приложения")
            await activity.update(ActivityContent(state: updated, staleDate: nil))
            lines.append("Activity.update: OK")
            log("Live Activity обновлена")
        }

        // Завершение через 3 секунды.
        try? await Task.sleep(for: .seconds(3))
        if let activity {
            let final = ScarletProbeActivityAttributes.ContentState(endTime: Date.now, message: "Завершено")
            await activity.end(ActivityContent(state: final, staleDate: nil), dismissalPolicy: .immediate)
            lines.append("Activity.end: OK (dismissalPolicy .immediate)")
            log("Live Activity завершена")
            self.activity = nil
        }

        lines.append("Полный цикл запуск → обновление → завершение выполнен. Повторить вручную можно на экране теста.")
        statusLines = lines
        return .ok(lines.joined(separator: "\n"))
    }

    // MARK: - Ручное управление с экрана теста

    var isRunning: Bool { activity != nil }

    func manualStart() async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            statusLines.append("Запуск невозможен: areActivitiesEnabled == false.")
            return
        }
        await endIfRunning()
        let end = Date.now.addingTimeInterval(5 * 60)
        let state = ScarletProbeActivityAttributes.ContentState(endTime: end, message: "Таймер запущен (вручную)")
        do {
            let started = try Activity.request(
                attributes: ScarletProbeActivityAttributes(title: "ScarletProbe"),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            activity = started
            activityID = started.id
            statusLines.append("Запущено вручную: id=\(started.id)")
        } catch {
            statusLines.append("Ошибка ручного запуска:\n\(ProbeLogger.describe(error))")
        }
    }

    func manualUpdate() async {
        guard let activity else {
            statusLines.append("Обновление невозможно: активность не запущена.")
            return
        }
        let end = Date.now.addingTimeInterval(5 * 60)
        let state = ScarletProbeActivityAttributes.ContentState(endTime: end, message: "Обновлено вручную \(Date.now.formatted(date: .omitted, time: .standard))")
        await activity.update(ActivityContent(state: state, staleDate: nil))
        statusLines.append("Обновлено вручную.")
    }

    func manualEnd() async {
        guard let activity else {
            statusLines.append("Завершение невозможно: активность не запущена.")
            return
        }
        let state = ScarletProbeActivityAttributes.ContentState(endTime: Date.now, message: "Завершено вручную")
        await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
        self.activity = nil
        statusLines.append("Завершено вручную.")
    }

    private func endIfRunning() async {
        guard let activity else { return }
        let state = ScarletProbeActivityAttributes.ContentState(endTime: Date.now, message: "Сброс")
        await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
        self.activity = nil
    }
}

/// Экран теста 17: ручное управление Live Activity и журнал статусов.
private struct ExtLiveActivityDetailView: View {
    let probe: ExtLiveActivityProbe

    var body: some View {
        List {
            Section("Статус") {
                Text("areActivitiesEnabled: \(ActivityAuthorizationInfo().areActivitiesEnabled ? "да" : "нет")")
                    .font(.footnote.monospaced())
                Text("Активна сейчас: \(probe.isRunning ? "да" : "нет")")
                    .font(.footnote.monospaced())
                if let id = probe.activityID {
                    Text("id: \(id)")
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
            Section("Управление") {
                Button("Запустить") { Task { await probe.manualStart() } }
                Button("Обновить") { Task { await probe.manualUpdate() } }
                Button("Завершить", role: .destructive) { Task { await probe.manualEnd() } }
            }
            Section("Журнал") {
                if probe.statusLines.isEmpty {
                    Text("Пусто").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(probe.statusLines.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
            }
        }
    }
}

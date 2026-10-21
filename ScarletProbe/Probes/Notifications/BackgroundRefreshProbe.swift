import SwiftUI
@preconcurrency import BackgroundTasks

/// Тест 10. Фоновое обновление через BGTaskScheduler (BGAppRefreshTask).
///
/// Обработчик регистрируется в AppDelegate до окончания запуска
/// (`BackgroundRefreshProbe.registerHandler()`). При срабатывании пишет время
/// в UserDefaults.standard; история показывается в detailView.
@MainActor
final class BackgroundRefreshProbe: ProbeTest {
    let id = 10
    let title = "Фоновое обновление (BGAppRefresh)"

    nonisolated static let taskID = "com.local.scarletprobe.refresh"
    nonisolated static let historyKey = "scarlet.bgrefresh.history"

    /// Регистрация обработчика. ДОЛЖНА вызываться из
    /// `application(_:didFinishLaunchingWithOptions:)` до возврата.
    nonisolated static func registerHandler() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            let iso = ISO8601DateFormatter().string(from: Date())
            var history = UserDefaults.standard.stringArray(forKey: historyKey) ?? []
            history.append(iso)
            UserDefaults.standard.set(history, forKey: historyKey)

            // Планируем следующее обновление, чтобы история продолжала расти.
            BackgroundRefreshProbe.submitRequest()
            task.setTaskCompleted(success: true)

            Task { @MainActor in
                ProbeLogger.shared.log("BGAppRefreshTask сработал: \(iso)", testID: 10)
            }
        }
    }

    nonisolated static func submitRequest() {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            let text = ProbeLogger.describe(error)
            Task { @MainActor in
                ProbeLogger.shared.log("BGTaskScheduler.submit ошибка: \(text)", testID: 10)
            }
        }
    }

    nonisolated static func history() -> [String] {
        UserDefaults.standard.stringArray(forKey: historyKey) ?? []
    }

    func run() async -> ProbeResult {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            return .fail(
                "Не удалось отправить BGAppRefreshTaskRequest. Проверьте: обработчик зарегистрирован в AppDelegate (BackgroundRefreshProbe.registerHandler()) и идентификатор есть в BGTaskSchedulerPermittedIdentifiers.",
                error: error
            )
        }

        let history = Self.history()
        var details = """
        BGAppRefreshTaskRequest отправлен (earliestBeginDate ≈ через 15 минут).
        Идентификатор: \(Self.taskID)
        Реальный запуск планирует система (в фоне, обычно при зарядке/Wi-Fi), точное время не гарантировано.
        История запусков обработчика: \(history.count)
        """
        if history.isEmpty {
            details += "\n  (пока пусто — обработчик ещё не срабатывал; историю смотрите на экране «Открыть»)"
        } else {
            details += "\n" + history.suffix(10).map { "  " + $0 }.joined(separator: "\n")
        }
        return .ok(details)
    }

    var detailView: AnyView? { AnyView(BackgroundRefreshDetailView(probe: self)) }
}

private struct BackgroundRefreshDetailView: View {
    let probe: BackgroundRefreshProbe
    @State private var history: [String] = []

    var body: some View {
        List {
            Section("История запусков BGAppRefreshTask (\(history.count))") {
                if history.isEmpty {
                    Text("Пока пусто. Система запускает фоновое обновление сама, когда сочтёт нужным.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(history.enumerated().reversed()), id: \.offset) { _, item in
                    Text(item).font(.footnote.monospaced())
                }
            }
            Section {
                Button("Запланировать сейчас") {
                    BackgroundRefreshProbe.submitRequest()
                }
                Button("Обновить") {
                    history = BackgroundRefreshProbe.history()
                }
                Button("Очистить историю", role: .destructive) {
                    UserDefaults.standard.removeObject(forKey: BackgroundRefreshProbe.historyKey)
                    history = []
                }
            }
        }
        .task { history = BackgroundRefreshProbe.history() }
    }
}

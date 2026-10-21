import AppIntents
import Foundation

/// Ключи UserDefaults, через которые perform() сообщает приложению о срабатывании.
enum AppIntentBridge {
    static let runCountKey = "markTaskRunCount"
    static let lastRunKey = "markTaskLastRun"
}

/// AppIntent «Отметить задачу» (тест 18).
///
/// Живёт в основном приложении (Extensions/AppIntents компилируется в app-таргет),
/// а не в отдельном App Intents Extension — этого достаточно, чтобы команда была видна
/// в приложении «Команды» и Spotlight.
struct MarkTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Отметить задачу"
    static let description: IntentDescription? = IntentDescription("Отмечает тестовую задачу как выполненную в ScarletProbe.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let defaults = UserDefaults.standard
        let count = defaults.integer(forKey: AppIntentBridge.runCountKey) + 1
        defaults.set(count, forKey: AppIntentBridge.runCountKey)
        defaults.set(Date.now.timeIntervalSince1970, forKey: AppIntentBridge.lastRunKey)
        return .result(dialog: "Задача отмечена. Всего раз: \(count).")
    }
}

/// Делает intent доступным в «Командах»/Spotlight без отдельного расширения.
struct ScarletProbeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: MarkTaskIntent(),
            phrases: [
                "Отметить задачу в \(.applicationName)",
                "\(.applicationName) отметить задачу"
            ],
            shortTitle: "Отметить задачу",
            systemImageName: "checkmark.circle"
        )
    }
}

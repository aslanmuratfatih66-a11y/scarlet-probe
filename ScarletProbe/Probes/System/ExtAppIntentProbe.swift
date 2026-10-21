import SwiftUI
import AppIntents

/// Тест 18: App Intents / Команды.
@MainActor
@Observable
final class ExtAppIntentProbe: ProbeTest {
    let id = 18
    let title = "App Intents / Команды"

    var detailView: AnyView? { AnyView(ExtAppIntentDetailView(probe: self)) }

    func run() async -> ProbeResult {
        var lines: [String] = []
        lines.append("AppIntent «Отметить задачу» (MarkTaskIntent) зарегистрирован в основном приложении.")
        lines.append("AppShortcutsProvider (ScarletProbeShortcuts) добавлен — команда должна появиться в приложении «Команды» и Spotlight без отдельного App Intents Extension.")
        lines.append("Отдельный App Intents Extension не требуется: intent в основном приложении уже виден в «Командах».")

        // Просим систему обновить параметры команд.
        ScarletProbeShortcuts.updateAppShortcutParameters()
        lines.append("Вызван ScarletProbeShortcuts.updateAppShortcutParameters().")

        let defaults = UserDefaults.standard
        let count = defaults.integer(forKey: AppIntentBridge.runCountKey)
        lines.append("Счётчик срабатываний perform(): \(count)")
        if let ts = defaults.object(forKey: AppIntentBridge.lastRunKey) as? Double {
            let date = Date(timeIntervalSince1970: ts)
            lines.append("Последнее срабатывание: \(date.formatted(date: .abbreviated, time: .standard))")
        } else {
            lines.append("Последнее срабатывание: ещё не вызывался.")
        }
        lines.append("Ручная проверка: откройте «Команды» → найдите «Отметить задачу» (или Spotlight-поиск), выполните и перезапустите тест — счётчик должен вырасти.")
        log("AppIntent проверен, счётчик=\(count)")

        let details = lines.joined(separator: "\n")
        return count > 0 ? .ok(details) : .partial(details)
    }
}

/// Экран теста 18: статус флага и прямой вызов intent для проверки perform().
private struct ExtAppIntentDetailView: View {
    let probe: ExtAppIntentProbe
    @State private var count = 0
    @State private var lastRun = "—"
    @State private var message = ""

    var body: some View {
        List {
            Section("Состояние") {
                Text("Срабатываний perform(): \(count)")
                    .font(.footnote.monospaced())
                Text("Последнее: \(lastRun)")
                    .font(.footnote.monospaced())
            }
            Section("Проверка") {
                Button("Выполнить intent сейчас (локально)") {
                    Task {
                        do {
                            _ = try await MarkTaskIntent().perform()
                            message = "perform() выполнен."
                        } catch {
                            message = "Ошибка perform():\n\(ProbeLogger.describe(error))"
                        }
                        reload()
                    }
                }
                Button("Обновить экран") { reload() }
                if !message.isEmpty {
                    Text(message).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
            Section("Команды") {
                Text("Откройте приложение «Команды» → поиск «Отметить задачу». Команда регистрируется через AppShortcutsProvider; отдельное расширение не нужно.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { reload() }
    }

    private func reload() {
        let defaults = UserDefaults.standard
        count = defaults.integer(forKey: AppIntentBridge.runCountKey)
        if let ts = defaults.object(forKey: AppIntentBridge.lastRunKey) as? Double {
            lastRun = Date(timeIntervalSince1970: ts).formatted(date: .abbreviated, time: .standard)
        } else {
            lastRun = "—"
        }
    }
}

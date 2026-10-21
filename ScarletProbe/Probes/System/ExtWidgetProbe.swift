import SwiftUI
import WidgetKit

/// Тест 16: WidgetKit-виджет + передача данных через App Group.
@MainActor
@Observable
final class ExtWidgetProbe: ProbeTest {
    let id = 16
    let title = "Виджет"

    var lastSavedText: String?
    var lastSavedDate: Date?

    var detailView: AnyView? { AnyView(ExtWidgetDetailView(probe: self)) }

    func run() async -> ProbeResult {
        var lines: [String] = []

        let appGroupOK = AppGroup.defaults != nil
        lines.append("App Group (\(AppGroup.identifier)): \(appGroupOK ? "доступен" : "НЕ доступен — UserDefaults(suiteName:) вернул nil (подпись срезала App Group)")")

        // Записываем текущие данные для виджета.
        let now = Date.now
        let text = "ScarletProbe · \(now.formatted(date: .abbreviated, time: .standard))"
        let saved = WidgetBridge.save(text: text, date: now)
        if saved {
            lastSavedText = text
            lastSavedDate = now
            lines.append("Записано в App Group: \(text)")
            lines.append("Чтение назад: \(WidgetBridge.currentText() ?? "nil")")
        } else {
            lines.append("Запись в App Group не выполнена (defaults == nil). Виджет покажет «нет данных».")
        }

        // Просим систему перечитать таймлайны.
        WidgetCenter.shared.reloadAllTimelines()
        lines.append("Вызван WidgetCenter.shared.reloadAllTimelines().")

        // Проверяем, установлен ли уже виджет.
        var installedFound = false
        do {
            let infos = try await WidgetCenter.shared.getCurrentConfigurations()
            if infos.isEmpty {
                lines.append("getCurrentConfigurations: установленных виджетов не найдено.")
            } else {
                installedFound = true
                let kinds = infos.map { $0.kind }.joined(separator: ", ")
                lines.append("getCurrentConfigurations: установлено виджетов \(infos.count) (\(kinds)).")
            }
        } catch {
            lines.append("getCurrentConfigurations: ошибка\n\(ProbeLogger.describe(error))")
        }

        lines.append("Добавьте виджет «ScarletProbe» на домашний экран/экран блокировки и отметьте вручную, появился ли он и видны ли данные.")
        log("Виджет: App Group \(appGroupOK ? "доступен" : "nil"), reloadAllTimelines вызван")

        let details = lines.joined(separator: "\n")
        if appGroupOK && installedFound {
            return .ok(details)
        }
        return .partial(details)
    }
}

/// Экран теста 16: текущее сохранённое значение App Group и повторная запись.
private struct ExtWidgetDetailView: View {
    let probe: ExtWidgetProbe
    @State private var currentText: String = ""
    @State private var currentDate: String = ""
    @State private var appGroupAvailable = false

    var body: some View {
        List {
            Section("App Group") {
                Text(appGroupAvailable ? "Доступен: \(AppGroup.identifier)" : "НЕ доступен (nil)")
                    .font(.footnote.monospaced())
                    .foregroundStyle(appGroupAvailable ? .primary : .red)
            }
            Section("Текущее значение в App Group") {
                Text("widgetText: \(currentText)")
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                Text("widgetLastUpdate: \(currentDate)")
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
            }
            Section {
                Button("Записать новое значение и перечитать виджеты") {
                    let now = Date.now
                    WidgetBridge.save(text: "ScarletProbe · \(now.formatted(date: .abbreviated, time: .standard))", date: now)
                    WidgetCenter.shared.reloadAllTimelines()
                    reload()
                }
                Button("Обновить экран") { reload() }
            }
            Section("Ручная проверка") {
                Text("Долгое нажатие на домашнем экране → «+» → найдите «ScarletProbe» → добавьте виджет. Отметьте в отчёте, появился ли он и видны ли данные.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { reload() }
    }

    private func reload() {
        appGroupAvailable = AppGroup.defaults != nil
        currentText = WidgetBridge.currentText() ?? "нет данных"
        if let date = WidgetBridge.currentDate() {
            currentDate = date.formatted(date: .abbreviated, time: .standard)
        } else {
            currentDate = "—"
        }
    }
}

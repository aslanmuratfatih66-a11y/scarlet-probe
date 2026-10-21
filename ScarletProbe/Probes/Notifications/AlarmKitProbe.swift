import SwiftUI
#if canImport(AlarmKit)
import AlarmKit
#endif

/// Тест 9. AlarmKit (iOS 26): авторизация, будильник через 1 минуту, таймер.
///
/// AlarmKit — новый фреймворк, API планирования (AlarmManager.schedule
/// с AlarmConfiguration / AlarmAttributes / AlarmPresentation) сложное и его
/// точная форма зависит от SDK. Чтобы не ломать сборку (собрать локально нельзя),
/// выполняется только запрос авторизации, который имеет стабильную сигнатуру;
/// планирование описано как ручной шаг. См. риски компиляции в отчёте.
@MainActor
final class AlarmKitProbe: ProbeTest {
    let id = 9
    let title = "AlarmKit (будильник и таймер)"

    var timeout: Duration { .seconds(30) }

    func run() async -> ProbeResult {
        #if canImport(AlarmKit)
        do {
            // Возвращаемый тип намеренно не фиксируем — описываем через String(describing:),
            // чтобы код компилировался независимо от конкретного имени enum-состояния.
            let state = try await AlarmManager.shared.requestAuthorization()
            let stateText = String(describing: state)
            log("AlarmKit авторизация: \(stateText)")
            return .partial("""
            AlarmKit доступен (canImport == true). Запрошена авторизация.
            Состояние авторизации: \(stateText)
            Планирование будильника (через 1 мин) и таймера обратного отсчёта в этой сборке \
            НЕ выполняется: API планирования в iOS 26 (AlarmManager.schedule с \
            AlarmConfiguration / AlarmAttributes / AlarmPresentation) требует точной сверки \
            с SDK, а ошибка компиляции сломала бы всю сборку. Нужен Info.plist-ключ \
            NSAlarmKitUsageDescription (уже добавлен). Подробности — в рисках компиляции отчёта.
            """)
        } catch {
            return .fail("AlarmKit: запрос авторизации не прошёл", error: error)
        }
        #else
        return .fail("AlarmKit недоступен в этом SDK (canImport(AlarmKit) == false).")
        #endif
    }
}

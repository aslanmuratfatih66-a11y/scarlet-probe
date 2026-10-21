import ActivityKit
import Foundation

/// Атрибуты Live Activity (тест 17).
///
/// Лежит в Extensions/Shared, поэтому компилируется и в приложение (запуск/обновление/
/// завершение через ActivityKit), и в виджет-расширение (отрисовка экрана блокировки
/// и Dynamic Island через ActivityConfiguration).
///
/// `ContentState` обязан быть `Codable & Hashable`; `Sendable` добавлен для Swift 6.
struct ScarletProbeActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        /// Момент окончания таймера обратного отсчёта.
        var endTime: Date
        /// Короткий текст статуса, обновляется из приложения.
        var message: String
    }

    /// Неизменяемый заголовок активности.
    var title: String
}

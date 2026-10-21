import Foundation

/// Передача данных между приложением и виджет-расширением через App Group (тест 16).
///
/// Лежит в Extensions/Shared → компилируется в оба таргета. Если App Group срезан
/// подписью (`AppGroup.defaults == nil`), все операции тихо становятся no-op, а чтение
/// возвращает `nil` — виджет в этом случае показывает «нет данных».
enum WidgetBridge {
    static let textKey = "widgetText"
    static let lastUpdateKey = "widgetLastUpdate"

    /// Записывает текст и время последнего обновления в App Group.
    /// Возвращает `true`, если App Group доступен и запись выполнена.
    @discardableResult
    static func save(text: String, date: Date) -> Bool {
        guard let defaults = AppGroup.defaults else { return false }
        defaults.set(text, forKey: textKey)
        defaults.set(date, forKey: lastUpdateKey)
        return true
    }

    static func currentText() -> String? {
        AppGroup.defaults?.string(forKey: textKey)
    }

    static func currentDate() -> Date? {
        AppGroup.defaults?.object(forKey: lastUpdateKey) as? Date
    }
}

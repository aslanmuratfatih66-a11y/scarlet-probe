import Foundation
import Observation

/// События уровня приложения, которые нужны отдельным тестам.
/// AppDelegate и `onOpenURL` пишут сюда, тесты читают.
@MainActor
@Observable
final class AppHooks {
    static let shared = AppHooks()
    private init() {}

    /// Последняя ссылка `scarletprobe://…`, открытая в приложении (тест 19).
    var lastOpenedURL: URL?
    /// Показать алерт об открытии ссылки.
    var showURLAlert = false
}

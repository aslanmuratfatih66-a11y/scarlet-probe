import SwiftUI

/// Общий протокол для всех тестов.
///
/// Тесты — `@MainActor final class`, чтобы хранить состояние (делегаты, счётчики)
/// между запусками. `run()` не должен бросать: все ошибки превращаются в `ProbeResult`.
@MainActor
protocol ProbeTest: AnyObject, Sendable {
    /// Номер теста из спецификации (1…19).
    var id: Int { get }
    var title: String { get }
    /// Сколько секунд раннер ждёт `run()`, прежде чем записать «таймаут».
    var timeout: Duration { get }
    func run() async -> ProbeResult
    /// Необязательный экран теста (карта, сканер, PhotosPicker, история запусков).
    /// Открывается из строки списка кнопкой «Открыть».
    var detailView: AnyView? { get }
}

extension ProbeTest {
    var timeout: Duration { .seconds(60) }
    var detailView: AnyView? { nil }

    /// Короткая запись в общий лог от имени теста.
    func log(_ message: String) {
        ProbeLogger.shared.log(message, testID: id)
    }
}

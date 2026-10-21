import Foundation

/// Реестр тестов: каждый тест добавляется одной строкой.
@MainActor
enum ProbeRegistry {
    static let all: [any ProbeTest] = [
        // Тесты регистрируются здесь, по одной строке, в порядке номеров.
    ]
}

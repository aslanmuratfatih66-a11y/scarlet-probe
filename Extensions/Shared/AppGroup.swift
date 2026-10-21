import Foundation

/// Общие константы приложения и расширений.
enum AppGroup {
    static let identifier = "group.com.local.scarletprobe"

    /// `nil`, если App Group не выдан подписью (ожидаемо при переподписи).
    static var defaults: UserDefaults? { UserDefaults(suiteName: identifier) }

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}

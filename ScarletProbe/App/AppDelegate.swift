import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        ProbeLogger.shared.log("Запуск приложения")
        // Хуки тестов, которым нужна регистрация до окончания запуска, добавляются здесь.
        return true
    }
}

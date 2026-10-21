import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        ProbeLogger.shared.log("Запуск приложения")
        // Обработчик BGAppRefreshTask (тест 10) обязан регистрироваться до конца запуска.
        BackgroundRefreshProbe.registerHandler()
        return true
    }

    // Колбэки remote push (тест 8) пересылаются в брокер.
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        RemotePushBroker.shared.didRegister(tokenData: deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: any Error
    ) {
        RemotePushBroker.shared.didFail(error: error)
    }
}

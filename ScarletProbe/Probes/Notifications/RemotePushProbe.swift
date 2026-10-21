import SwiftUI
import UIKit
@preconcurrency import UserNotifications

/// Синглтон-брокер для APNs-регистрации. Колбэки приходят в AppDelegate
/// (`didRegisterForRemoteNotificationsWithDeviceToken` /
/// `didFailToRegisterForRemoteNotificationsWithError`) и пересылаются сюда.
@MainActor
@Observable
final class RemotePushBroker {
    static let shared = RemotePushBroker()
    private init() {}

    private var continuation: CheckedContinuation<String, any Error>?
    private(set) var lastToken: String?
    private(set) var lastError: String?

    enum PushError: LocalizedError {
        case alreadyWaiting
        case timedOut

        var errorDescription: String? {
            switch self {
            case .alreadyWaiting: "Регистрация APNs уже выполняется."
            case .timedOut: "APNs не ответил за отведённое время (нет колбэка от системы)."
            }
        }
    }

    /// Запускает `registerForRemoteNotifications()` и ждёт токен или ошибку.
    func register(timeout: Duration = .seconds(25)) async -> Result<String, any Error> {
        guard continuation == nil else { return .failure(PushError.alreadyWaiting) }

        let timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: timeout)
            if self.continuation != nil {
                self.didFail(error: PushError.timedOut)
            }
        }

        do {
            let token = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, any Error>) in
                self.continuation = cont
                UIApplication.shared.registerForRemoteNotifications()
            }
            timeoutTask.cancel()
            return .success(token)
        } catch {
            timeoutTask.cancel()
            return .failure(error)
        }
    }

    /// Вызывается из AppDelegate при успешной регистрации.
    func didRegister(tokenData: Data) {
        let hex = tokenData.map { String(format: "%02x", $0) }.joined()
        lastToken = hex
        lastError = nil
        ProbeLogger.shared.log("APNs device token получен (\(tokenData.count) байт)", testID: 8)
        let cont = continuation
        continuation = nil
        cont?.resume(returning: hex)
    }

    /// Вызывается из AppDelegate при ошибке регистрации.
    func didFail(error: any Error) {
        lastError = ProbeLogger.describe(error)
        ProbeLogger.shared.log("APNs регистрация не прошла: \(lastError ?? "")", testID: 8)
        let cont = continuation
        continuation = nil
        cont?.resume(throwing: error)
    }
}

/// Тест 8. Remote push: регистрация в APNs, device token или полная ошибка.
@MainActor
final class RemotePushProbe: ProbeTest {
    let id = 8
    let title = "Remote push (APNs)"

    var timeout: Duration { .seconds(30) }

    func run() async -> ProbeResult {
        // Для push нужна авторизация уведомлений — переиспользуем центр.
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            log("Авторизация уведомлений для push: granted=\(granted)")
        } catch {
            log("Запрос разрешения уведомлений не прошёл: \(ProbeLogger.describe(error))")
        }

        let result = await RemotePushBroker.shared.register()
        switch result {
        case .success(let token):
            return .ok("""
            Получен APNs device token (hex):
            \(token)
            Длина: \(token.count / 2) байт
            """)
        case .failure(let error):
            return .fail(
                "registerForRemoteNotifications вернул ошибку. На симуляторе без push, без сети или без корректного aps-environment это ожидаемо.",
                error: error
            )
        }
    }
}

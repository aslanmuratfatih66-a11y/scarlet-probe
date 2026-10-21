import SwiftUI
@preconcurrency import UserNotifications

/// Тест 1. Локальные уведомления: авторизация, категория с action-кнопками,
/// разовое уведомление, повторяющееся (с отменой) и уведомление с кнопками.
@MainActor
final class NotificationsProbe: ProbeTest {
    let id = 1
    let title = "Локальные уведомления"

    static let categoryID = "SCARLET_ACTIONS"
    static let actionDoneID = "SCARLET_DONE"
    static let actionSnoozeID = "SCARLET_SNOOZE"
    static let onceID = "scarlet.local.once"
    static let repeatingID = "scarlet.local.repeating"
    static let withActionsID = "scarlet.local.actions"

    /// Лёгкое Sendable-описание запланированного уведомления для detailView.
    struct PendingInfo: Identifiable, Sendable {
        let id: String
        let body: String
        let repeats: Bool
    }

    func run() async -> ProbeResult {
        let center = UNUserNotificationCenter.current()

        // Категория с кнопками «Готово» / «Отложить».
        let done = UNNotificationAction(identifier: Self.actionDoneID, title: "Готово", options: [])
        let snooze = UNNotificationAction(identifier: Self.actionSnoozeID, title: "Отложить", options: [])
        let category = UNNotificationCategory(
            identifier: Self.categoryID,
            actions: [done, snooze],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])

        // Запрос разрешения.
        let granted: Bool
        do {
            granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return .fail("Запрос разрешения на уведомления завершился ошибкой", error: error)
        }

        let settings = await center.notificationSettings()
        let statusText = Self.authString(settings.authorizationStatus)
        log("Авторизация уведомлений: \(statusText) (granted=\(granted))")

        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
            || settings.authorizationStatus == .ephemeral else {
            return .fail("Нет разрешения на уведомления. Статус: \(statusText).")
        }

        var scheduled: [String] = []
        var failures: [String] = []

        // Разовое через 5 секунд.
        if await add(center: center, id: Self.onceID, title: "ScarletProbe",
                     body: "Разовое уведомление через 5 секунд.",
                     seconds: 5, repeats: false, category: nil) {
            scheduled.append("разовое через 5 с")
        } else {
            failures.append("разовое")
        }

        // Повторяющееся каждые 60 секунд (минимально допустимый интервал).
        if await add(center: center, id: Self.repeatingID, title: "ScarletProbe (повтор)",
                     body: "Повторяется каждые 60 секунд. Отмена — на экране теста.",
                     seconds: 60, repeats: true, category: nil) {
            scheduled.append("повторяющееся каждые 60 с")
        } else {
            failures.append("повторяющееся")
        }

        // Уведомление с кнопками через 8 секунд.
        if await add(center: center, id: Self.withActionsID, title: "ScarletProbe — кнопки",
                     body: "Проверка action-кнопок «Готово» / «Отложить».",
                     seconds: 8, repeats: false, category: Self.categoryID) {
            scheduled.append("с кнопками через 8 с")
        } else {
            failures.append("с кнопками")
        }

        let pending = await Self.pendingInfos()
        var details = """
        Статус авторизации: \(statusText)
        Запланировано: \(scheduled.isEmpty ? "ничего" : scheduled.joined(separator: ", "))
        Ожидают доставки: \(pending.count)
        Категория с кнопками: \(Self.categoryID) (Готово/Отложить)
        Повторяющееся можно отменить на экране «Открыть».
        """
        if !failures.isEmpty {
            details += "\nНе удалось запланировать: \(failures.joined(separator: ", "))"
        }

        if !failures.isEmpty {
            return .partial(details)
        }
        if settings.authorizationStatus == .provisional {
            return .partial(details + "\nВыдано временное (provisional) разрешение.")
        }
        return .ok(details)
    }

    private func add(center: UNUserNotificationCenter, id: String, title: String,
                     body: String, seconds: TimeInterval, repeats: Bool,
                     category: String?) async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let category { content.categoryIdentifier = category }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: repeats)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        do {
            try await center.add(request)
            return true
        } catch {
            log("Не удалось запланировать \(id): \(ProbeLogger.describe(error))")
            return false
        }
    }

    // MARK: - detailView helpers

    func loadPending() async -> [PendingInfo] {
        await Self.pendingInfos()
    }

    /// Async-обёртка над `getPendingNotificationRequests(completionHandler:)`: в этом SDK
    /// async-вариант не синтезируется (параметр не Sendable), поэтому мапим в Sendable-тип
    /// `PendingInfo` прямо в completion-блоке и только его переносим через continuation.
    nonisolated static func pendingInfos() async -> [PendingInfo] {
        await withCheckedContinuation { (continuation: CheckedContinuation<[PendingInfo], Never>) in
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                let infos = requests.map { request -> PendingInfo in
                    let repeats = (request.trigger as? UNTimeIntervalNotificationTrigger)?.repeats ?? false
                    return PendingInfo(id: request.identifier, body: request.content.body, repeats: repeats)
                }
                continuation.resume(returning: infos)
            }
        }
    }

    func cancelRepeating() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.repeatingID])
        log("Отменено повторяющееся уведомление (\(Self.repeatingID))")
    }

    static func authString(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "не определён"
        case .denied: "запрещено"
        case .authorized: "разрешено"
        case .provisional: "временно (provisional)"
        case .ephemeral: "ephemeral"
        @unknown default: "неизвестно (\(status.rawValue))"
        }
    }

    var detailView: AnyView? { AnyView(NotificationsDetailView(probe: self)) }
}

private struct NotificationsDetailView: View {
    let probe: NotificationsProbe
    @State private var pending: [NotificationsProbe.PendingInfo] = []

    var body: some View {
        List {
            Section("Запланированные уведомления (\(pending.count))") {
                if pending.isEmpty {
                    Text("Нет запланированных уведомлений.")
                        .foregroundStyle(.secondary)
                }
                ForEach(pending) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.id).font(.caption.monospaced())
                        Text(item.body).font(.footnote)
                        if item.repeats {
                            Text("повторяется").font(.caption2).foregroundStyle(.orange)
                        }
                    }
                }
            }
            Section {
                Button("Отменить повторяющееся", role: .destructive) {
                    probe.cancelRepeating()
                    Task { pending = await probe.loadPending() }
                }
                Button("Обновить список") {
                    Task { pending = await probe.loadPending() }
                }
            }
        }
        .task { pending = await probe.loadPending() }
    }
}

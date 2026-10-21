import SwiftUI
@preconcurrency import HealthKit

/// Тест 3 «HealthKit»: доступность, запрос авторизации (шаги/калории/вес),
/// чтение шагов за сегодня, запись тестового веса. Любая ошибка логируется
/// полностью (HealthKit часто режется переподписью — это и проверяем).
@MainActor
final class HealthKitProbe: ProbeTest {
    let id = 3
    let title = "HealthKit"

    func run() async -> ProbeResult {
        guard HKHealthStore.isHealthDataAvailable() else {
            return .fail("HealthKit недоступен на устройстве (isHealthDataAvailable == false).")
        }

        let store = HKHealthStore()
        let stepType = HKQuantityType(.stepCount)
        let energyType = HKQuantityType(.activeEnergyBurned)
        let massType = HKQuantityType(.bodyMass)

        var lines: [String] = ["HealthKit доступен (isHealthDataAvailable == true)."]
        var readOK = false
        var writeOK = false
        var authFailed = false

        // 1. Авторизация: читаем шаги/калории/вес, пишем вес.
        do {
            try await store.requestAuthorization(
                toShare: [massType],
                read: [stepType, energyType, massType]
            )
            lines.append("Запрос авторизации выполнен без ошибки.")
            lines.append("Статус записи (bodyMass): \(Self.describe(store.authorizationStatus(for: massType)))")
            lines.append("Примечание: статус чтения HealthKit скрывает по приватности (всегда notDetermined).")
        } catch {
            authFailed = true
            let description = ProbeLogger.describe(error)
            log("HealthKit: ошибка авторизации — \(description)")
            lines.append("ОШИБКА авторизации:")
            lines.append(description)
        }

        // 2. Чтение шагов за сегодня (пробуем даже если авторизация упала).
        let start = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now, options: .strictStartDate)
        let readOutcome = await readStepSum(store: store, type: stepType, predicate: predicate)
        switch readOutcome {
        case .value(let steps):
            readOK = true
            lines.append("Шаги за сегодня (HealthKit): \(Int(steps))")
        case .empty:
            readOK = true
            lines.append("Шаги за сегодня (HealthKit): нет данных за период (сумма пустая).")
        case .failure(let description):
            lines.append("ОШИБКА чтения шагов:")
            lines.append(description)
        }

        // 3. Запись тестового веса 70 кг.
        let quantity = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: 70)
        let sample = HKQuantitySample(type: massType, quantity: quantity, start: .now, end: .now)
        do {
            try await store.save(sample)
            writeOK = true
            lines.append("Запись веса 70 кг: успешно.")
        } catch {
            let description = ProbeLogger.describe(error)
            log("HealthKit: ошибка записи веса — \(description)")
            lines.append("ОШИБКА записи веса:")
            lines.append(description)
        }

        let details = lines.joined(separator: "\n")
        if authFailed {
            return .fail(details)
        }
        if readOK && writeOK {
            return .ok(details)
        }
        return .partial(details)
    }

    // MARK: - Чтение суммы шагов

    private enum ReadOutcome: Sendable {
        case value(Double)
        case empty
        case failure(String)
    }

    private func readStepSum(
        store: HKHealthStore,
        type: HKQuantityType,
        predicate: NSPredicate
    ) async -> ReadOutcome {
        await withCheckedContinuation { (continuation: CheckedContinuation<ReadOutcome, Never>) in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error {
                    continuation.resume(returning: .failure(ProbeLogger.describe(error)))
                } else if let sum = statistics?.sumQuantity() {
                    continuation.resume(returning: .value(sum.doubleValue(for: .count())))
                } else {
                    continuation.resume(returning: .empty)
                }
            }
            store.execute(query)
        }
    }

    // MARK: - Описание статуса

    static func describe(_ status: HKAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "notDetermined (не спрашивали)"
        case .sharingDenied: "sharingDenied (запись запрещена)"
        case .sharingAuthorized: "sharingAuthorized (запись разрешена)"
        @unknown default: "неизвестно (\(status.rawValue))"
        }
    }
}

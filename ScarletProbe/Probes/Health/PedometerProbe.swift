import Foundation
import Observation
import SwiftUI
@preconcurrency import CoreMotion

/// Тест 2: шаги через CoreMotion (CMPedometer).
@MainActor
@Observable
final class PedometerProbe: ProbeTest {
    let id = 2
    let title = "Шаги CoreMotion"
    var timeout: Duration { .seconds(90) }

    /// Снимок данных шагомера: только Sendable-значения, извлечённые из CMPedometerData.
    struct Snapshot: Sendable {
        let steps: Int
        let distanceMeters: Double?
        let floorsAscended: Int?
        let start: Date
        let end: Date
    }

    /// Итог запроса/обновления: данные либо полное описание ошибки.
    enum Outcome: Sendable {
        case data(Snapshot)
        case failure(domain: String, code: Int, description: String)
        case empty
    }

    // Живое состояние для экрана теста.
    private(set) var isLive = false
    private(set) var liveSteps: Int?
    private(set) var liveDistance: Double?
    private(set) var liveUpdatesCount = 0
    private(set) var lastLiveUpdate: Date?
    private(set) var lastError: String?

    private let pedometer = CMPedometer()

    init() {}

    var detailView: AnyView? { AnyView(PedometerDetailView(probe: self)) }

    // MARK: - Запуск теста

    func run() async -> ProbeResult {
        var lines: [String] = []
        let stepsAvailable = CMPedometer.isStepCountingAvailable()
        lines.append("isStepCountingAvailable: \(stepsAvailable)")
        lines.append("isDistanceAvailable: \(CMPedometer.isDistanceAvailable())")
        lines.append("isFloorCountingAvailable: \(CMPedometer.isFloorCountingAvailable())")
        let statusBefore = CMPedometer.authorizationStatus()
        lines.append("authorizationStatus (до): \(Self.describe(statusBefore))")
        log(lines.joined(separator: "; "))

        guard stepsAvailable else {
            lines.append("Подсчёт шагов на этом устройстве недоступен.")
            return .fail(lines.joined(separator: "\n"))
        }
        if statusBefore == .denied || statusBefore == .restricted {
            lines.append("Доступ к «Движению и фитнесу» запрещён. Включите: Настройки → Конфиденциальность → Движение и фитнес.")
            return .fail(lines.joined(separator: "\n"))
        }

        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let outcome = await queryToday(from: startOfDay, to: now)
        lines.append("authorizationStatus (после): \(Self.describe(CMPedometer.authorizationStatus()))")

        switch outcome {
        case .failure(let domain, let code, let description):
            lines.append("Ошибка queryPedometerData:")
            lines.append("domain=\(domain)")
            lines.append("code=\(code) (\(Self.hint(domain: domain, code: code)))")
            lines.append("description=\(description)")
            return .fail(lines.joined(separator: "\n"))
        case .empty:
            lines.append("queryPedometerData вернул nil без ошибки.")
            return .partial(lines.joined(separator: "\n"))
        case .data(let snapshot):
            lines.append("Шагов за сегодня: \(snapshot.steps)")
            if let distance = snapshot.distanceMeters {
                lines.append(String(format: "Дистанция: %.0f м", distance))
            }
            if let floors = snapshot.floorsAscended {
                lines.append("Этажей вверх: \(floors)")
            }
            liveSteps = snapshot.steps
            liveDistance = snapshot.distanceMeters
        }

        // Живое обновление: запускаем и ждём немного, пришла ли хоть одна порция.
        startLive()
        try? await Task.sleep(for: .seconds(3))
        if let lastError {
            lines.append("Живое обновление: ошибка\n\(lastError)")
            return .partial(lines.joined(separator: "\n"))
        }
        if liveUpdatesCount > 0 {
            lines.append("Живое обновление: работает, получено обновлений: \(liveUpdatesCount)")
        } else {
            lines.append("Живое обновление: запущено, обновлений пока нет (приходят только при ходьбе). Откройте экран теста и пройдитесь.")
        }
        return .ok(lines.joined(separator: "\n"))
    }

    // MARK: - Запрос за период

    private func queryToday(from start: Date, to end: Date) async -> Outcome {
        await withCheckedContinuation { (continuation: CheckedContinuation<Outcome, Never>) in
            // Обработчик вызывается на фоновой очереди CoreMotion, поэтому он @Sendable
            // и не изолирован на MainActor. Не-Sendable CMPedometerData сразу превращаем в числа.
            pedometer.queryPedometerData(from: start, to: end) { @Sendable data, error in
                continuation.resume(returning: Self.outcome(data: data, error: error))
            }
        }
    }

    // MARK: - Живые обновления

    func startLive() {
        guard !isLive else { return }
        guard CMPedometer.isStepCountingAvailable() else {
            lastError = "Подсчёт шагов недоступен."
            return
        }
        isLive = true
        lastError = nil
        let startOfDay = Calendar.current.startOfDay(for: Date())
        log("CMPedometer.startUpdates(from: начало дня)")
        pedometer.startUpdates(from: startOfDay) { @Sendable [weak self] data, error in
            let outcome = PedometerProbe.outcome(data: data, error: error)
            guard let self else { return }
            Task { @MainActor in
                self.apply(outcome)
            }
        }
    }

    func stopLive() {
        guard isLive else { return }
        pedometer.stopUpdates()
        isLive = false
        log("CMPedometer.stopUpdates()")
    }

    private func apply(_ outcome: Outcome) {
        switch outcome {
        case .data(let snapshot):
            liveSteps = snapshot.steps
            liveDistance = snapshot.distanceMeters
            liveUpdatesCount += 1
            lastLiveUpdate = Date()
        case .failure(let domain, let code, let description):
            let text = "domain=\(domain)\ncode=\(code) (\(Self.hint(domain: domain, code: code)))\ndescription=\(description)"
            lastError = text
            log("Ошибка живого обновления шагов:\n\(text)")
        case .empty:
            break
        }
    }

    // MARK: - Вспомогательное (без изоляции)

    nonisolated private static func outcome(data: CMPedometerData?, error: (any Error)?) -> Outcome {
        if let error {
            let ns = error as NSError
            return .failure(domain: ns.domain, code: ns.code, description: ns.localizedDescription)
        }
        guard let data else { return .empty }
        return .data(Snapshot(
            steps: data.numberOfSteps.intValue,
            distanceMeters: data.distance?.doubleValue,
            floorsAscended: data.floorsAscended?.intValue,
            start: data.startDate,
            end: data.endDate
        ))
    }

    nonisolated private static func hint(domain: String, code: Int) -> String {
        guard domain == CMErrorDomain else { return "см. описание" }
        switch code {
        case 103: return "CMErrorUnknown"
        case 104: return "CMErrorMotionActivityNotAvailable — недоступно на устройстве"
        case 105: return "CMErrorMotionActivityNotAuthorized — нет разрешения «Движение и фитнес»"
        case 106: return "CMErrorMotionActivityNotEntitled — нет entitlement"
        case 107: return "CMErrorInvalidParameter"
        case 108: return "CMErrorInvalidAction"
        case 109: return "CMErrorNotAvailable"
        case 110: return "CMErrorNotEntitled"
        case 111: return "CMErrorNotAuthorized"
        default: return "код CoreMotion \(code)"
        }
    }

    nonisolated static func describe(_ status: CMAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorized: return "authorized"
        @unknown default: return "unknown(\(status.rawValue))"
        }
    }
}

// MARK: - Экран теста

private struct PedometerDetailView: View {
    let probe: PedometerProbe

    var body: some View {
        List {
            Section("Сегодня") {
                LabeledContent("Шаги", value: probe.liveSteps.map { "\($0)" } ?? "—")
                LabeledContent("Дистанция", value: probe.liveDistance.map { String(format: "%.0f м", $0) } ?? "—")
                LabeledContent("Обновлений получено", value: "\(probe.liveUpdatesCount)")
                LabeledContent("Последнее обновление", value: probe.lastLiveUpdate.map {
                    $0.formatted(date: .omitted, time: .standard)
                } ?? "—")
                LabeledContent("Разрешение", value: PedometerProbe.describe(CMPedometer.authorizationStatus()))
            }
            Section {
                if probe.isLive {
                    Button("Остановить обновления", role: .destructive) { probe.stopLive() }
                } else {
                    Button("Запустить живые обновления") { probe.startLive() }
                }
            } footer: {
                Text("Обновления приходят примерно раз в несколько секунд во время ходьбы.")
            }
            if let error = probe.lastError {
                Section("Ошибка") {
                    Text(error)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }
            }
        }
    }
}

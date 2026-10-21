import SwiftUI
import UIKit
@preconcurrency import CoreLocation

/// Тест 4 «Геолокация»: When In Use → Always, фоновые обновления, подсчёт
/// точек (всего и полученных в фоне), последняя координата.
///
/// Делегат `CLLocationManagerDelegate` вынесен в отдельный `final class`
/// с `nonisolated`-методами. Из делегата наружу передаются только Sendable-значения
/// через `@Sendable`-замыкания, которые прыгают на главный актор.
@MainActor
@Observable
final class LocationProbe: ProbeTest {
    let id = 4
    let title = "Геолокация (фон)"

    private(set) var authStatus: CLAuthorizationStatus
    private(set) var totalPoints = 0
    private(set) var backgroundPoints = 0
    private(set) var lastCoordinate: String = "—"
    private(set) var isUpdating = false
    private(set) var lastError: String?

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var delegate: LocationDelegate?

    init() {
        authStatus = manager.authorizationStatus
        let delegate = LocationDelegate(
            onLocations: { [weak self] count, lat, lon in
                Task { @MainActor in self?.didReceive(count: count, lat: lat, lon: lon) }
            },
            onAuth: { [weak self] raw in
                Task { @MainActor in self?.didChangeAuth(raw: raw) }
            },
            onError: { [weak self] description in
                Task { @MainActor in self?.didFail(description) }
            }
        )
        self.delegate = delegate
        manager.delegate = delegate
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func run() async -> ProbeResult {
        let status = manager.authorizationStatus
        authStatus = status
        log("Статус геолокации: \(Self.describe(status))")

        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            return .partial("""
            Запрошен доступ «При использовании». Разрешите его, затем запустите тест ещё раз,
            чтобы запросить «Всегда» и начать сбор точек.
            Текущий статус: \(Self.describe(status))
            """)
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
            startUpdates()
            return .partial("""
            Есть «При использовании», запрошен «Всегда». Обновления запущены.
            Сверните приложение, чтобы проверить фоновые точки (см. «Открыть»).
            Статус: \(Self.describe(status)), точек всего: \(totalPoints), в фоне: \(backgroundPoints)
            """)
        case .authorizedAlways:
            startUpdates()
            return .ok("""
            Доступ «Всегда» выдан. Обновления запущены (фон разрешён).
            Сверните приложение и подождите — точки в фоне считаются отдельно (см. «Открыть»).
            Точек всего: \(totalPoints), в фоне: \(backgroundPoints)
            """)
        case .denied:
            return .fail("Геолокация запрещена пользователем: \(Self.describe(status)).")
        case .restricted:
            return .fail("Геолокация ограничена системой: \(Self.describe(status)).")
        @unknown default:
            return .fail("Неизвестный статус авторизации: \(status.rawValue).")
        }
    }

    var detailView: AnyView? { AnyView(LocationDetailView(probe: self)) }

    // MARK: - Управление обновлениями

    func startUpdates() {
        guard !isUpdating else { return }
        // UIBackgroundModes/location есть в Info.plist (не срезается переподписью),
        // поэтому выставление флага безопасно.
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.startUpdatingLocation()
        isUpdating = true
        log("Геолокация: startUpdatingLocation, allowsBackgroundLocationUpdates = true")
    }

    func stopUpdates() {
        guard isUpdating else { return }
        manager.stopUpdatingLocation()
        isUpdating = false
        log("Геолокация: обновления остановлены.")
    }

    // MARK: - Приём из делегата (на MainActor)

    private func didReceive(count: Int, lat: Double, lon: Double) {
        totalPoints += count
        if UIApplication.shared.applicationState == .background {
            backgroundPoints += count
        }
        if lat.isFinite && lon.isFinite {
            lastCoordinate = String(format: "%.5f, %.5f", lat, lon)
        }
    }

    private func didChangeAuth(raw: Int32) {
        let status = CLAuthorizationStatus(rawValue: raw) ?? manager.authorizationStatus
        authStatus = status
        log("Геолокация: статус изменён на \(Self.describe(status))")
    }

    private func didFail(_ description: String) {
        lastError = description
        log("Геолокация: ошибка — \(description)")
    }

    // MARK: - Описание статуса

    static func describe(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "notDetermined (не спрашивали)"
        case .restricted: "restricted (ограничено)"
        case .denied: "denied (запрещено)"
        case .authorizedAlways: "authorizedAlways (всегда)"
        case .authorizedWhenInUse: "authorizedWhenInUse (при использовании)"
        @unknown default: "неизвестно (\(status.rawValue))"
        }
    }
}

/// Делегат CoreLocation: `nonisolated`-методы извлекают Sendable-значения
/// и передают их наружу через `@Sendable`-замыкания. Делегат неизменяемый
/// после инициализации, поэтому безопасно `Sendable`.
private final class LocationDelegate: NSObject, CLLocationManagerDelegate, Sendable {
    let onLocations: @Sendable (Int, Double, Double) -> Void
    let onAuth: @Sendable (Int32) -> Void
    let onError: @Sendable (String) -> Void

    init(
        onLocations: @escaping @Sendable (Int, Double, Double) -> Void,
        onAuth: @escaping @Sendable (Int32) -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) {
        self.onLocations = onLocations
        self.onAuth = onAuth
        self.onError = onError
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let count = locations.count
        let last = locations.last
        onLocations(count, last?.coordinate.latitude ?? .nan, last?.coordinate.longitude ?? .nan)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onAuth(manager.authorizationStatus.rawValue)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        onError(ProbeLogger.describe(error))
    }
}

private struct LocationDetailView: View {
    let probe: LocationProbe

    var body: some View {
        List {
            Section("Авторизация") {
                Text(LocationProbe.describe(probe.authStatus))
                    .font(.footnote.monospaced())
            }
            Section("Точки") {
                row("Всего получено", "\(probe.totalPoints)")
                row("В фоне", "\(probe.backgroundPoints)")
                row("Последняя координата", probe.lastCoordinate)
                row("Обновления", probe.isUpdating ? "активны" : "остановлены")
            }
            if let error = probe.lastError {
                Section("Последняя ошибка") {
                    Text(error).font(.footnote.monospaced()).foregroundStyle(.red)
                }
            }
            Section {
                Button(probe.isUpdating ? "Остановить" : "Запустить обновления") {
                    if probe.isUpdating { probe.stopUpdates() } else { probe.startUpdates() }
                }
            } footer: {
                Text("Сверните приложение на 10–30 секунд и пройдитесь — счётчик «В фоне» должен расти, если фоновая геолокация работает.")
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary).font(.footnote.monospaced())
        }
    }
}

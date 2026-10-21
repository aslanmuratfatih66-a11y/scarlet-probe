import SwiftUI
@preconcurrency import MapKit
@preconcurrency import CoreLocation

/// Тест 5 «MapKit»: текущая точка → точка в 1 км на север, пеший маршрут через
/// MKDirections, карта с полилинией, расстояние и число шагов маршрута.
@MainActor
@Observable
final class MapRouteProbe: ProbeTest {
    let id = 5
    let title = "MapKit (маршрут)"

    private(set) var route: MKRoute?
    private(set) var sourceCoord: CLLocationCoordinate2D?
    private(set) var destCoord: CLLocationCoordinate2D?

    @ObservationIgnored private let authManager = CLLocationManager()

    /// Маршрут может ждать первую геоточку — даём больше времени, чем 60 с по умолчанию.
    var timeout: Duration { .seconds(45) }

    func run() async -> ProbeResult {
        let status = authManager.authorizationStatus
        log("MapKit: статус геолокации \(LocationProbe.describe(status))")

        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            if status == .notDetermined {
                authManager.requestWhenInUseAuthorization()
            }
            return .partial("""
            Нет доступа к геопозиции (статус \(LocationProbe.describe(status))).
            Выдайте доступ в тесте 4 «Геолокация», затем запустите этот тест снова.
            """)
        }

        guard let current = await firstLocation() else {
            return .partial("Не удалось получить текущую геопозицию за отведённое время.")
        }

        // Точка в 1 км строго на север (1° широты ≈ 111.32 км).
        let destination = CLLocationCoordinate2D(
            latitude: current.coordinate.latitude + (1000.0 / 111_320.0),
            longitude: current.coordinate.longitude
        )

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: current.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .walking

        let directions = MKDirections(request: request)
        do {
            let response = try await directions.calculate()
            guard let route = response.routes.first else {
                return .partial("MKDirections не вернул ни одного маршрута (response.routes пуст).")
            }
            self.sourceCoord = current.coordinate
            self.destCoord = destination
            self.route = route

            let firstInstruction = route.steps.first(where: { !$0.instructions.isEmpty })?.instructions ?? "нет текстовых инструкций"
            log("MapKit: маршрут \(Int(route.distance)) м, шагов \(route.steps.count)")
            return .ok("""
            Расстояние маршрута: \(Int(route.distance)) м
            Шагов маршрута: \(route.steps.count)
            Первая инструкция: \(firstInstruction)
            Карта с маршрутом — в «Открыть».
            """)
        } catch {
            return .fail("MKDirections: не удалось построить пеший маршрут", error: error)
        }
    }

    var detailView: AnyView? { AnyView(MapRouteDetailView(probe: self)) }

    // MARK: - Текущая геопозиция

    private func firstLocation() async -> CLLocation? {
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if let location = update.location {
                    return location
                }
            }
        } catch {
            log("MapKit: ошибка получения геопозиции — \(ProbeLogger.describe(error))")
        }
        return nil
    }
}

private struct MapRouteDetailView: View {
    let probe: MapRouteProbe

    var body: some View {
        Group {
            if let route = probe.route, let source = probe.sourceCoord, let dest = probe.destCoord {
                Map(initialPosition: .region(region(source: source, dest: dest))) {
                    Marker("Старт", coordinate: source)
                    Marker("Финиш", coordinate: dest)
                    MapPolyline(route.polyline)
                        .stroke(.blue, lineWidth: 5)
                }
                .safeAreaInset(edge: .bottom) {
                    Text("Расстояние: \(Int(route.distance)) м · шагов: \(route.steps.count)")
                        .font(.footnote)
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(.bar)
                }
            } else {
                ContentUnavailableView(
                    "Маршрут не построен",
                    systemImage: "map",
                    description: Text("Сначала запустите тест. Нужен доступ к геопозиции.")
                )
            }
        }
    }

    private func region(source: CLLocationCoordinate2D, dest: CLLocationCoordinate2D) -> MKCoordinateRegion {
        let center = CLLocationCoordinate2D(
            latitude: (source.latitude + dest.latitude) / 2,
            longitude: (source.longitude + dest.longitude) / 2
        )
        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
    }
}

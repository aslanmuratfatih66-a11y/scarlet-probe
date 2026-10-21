import SwiftUI
import VisionKit
import Vision

/// Тест 12: сканер штрихкодов через VisionKit `DataScannerViewController` (EAN-13/EAN-8).
@MainActor
@Observable
final class BarcodeScannerProbe: ProbeTest {
    let id = 12
    let title = "Сканер штрихкодов"
    var timeout: Duration { .seconds(120) }

    /// Последний распознанный код и его символика (для отчёта и экрана теста).
    var lastCode: String?
    var lastSymbology: String?

    var detailView: AnyView? { AnyView(BarcodeScannerView(probe: self)) }

    func run() async -> ProbeResult {
        var lines: [String] = []

        let supported = DataScannerViewController.isSupported
        lines.append("DataScannerViewController.isSupported: \(supported)")

        if supported {
            // isAvailable — свойство экземпляра (камера, разрешение, не в многозадачном режиме).
            let scanner = DataScannerViewController(
                recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8])]
            )
            lines.append("isAvailable: \(scanner.isAvailable)")
        } else {
            lines.append("isAvailable: пропущено (устройство не поддерживается)")
        }

        if let code = lastCode {
            let sym = lastSymbology.map { " (\($0))" } ?? ""
            lines.append("Последний распознанный код: \(code)\(sym)")
        } else {
            lines.append("Код ещё не распознан. Откройте экран теста («Открыть») и наведите камеру на штрихкод EAN-13/EAN-8.")
        }

        if !supported {
            lines.append("Устройство не поддерживает DataScanner: нужен процессор с нейромодулем (A12 Bionic и новее).")
            return .partial(lines.joined(separator: "\n"))
        }
        if lastCode != nil {
            return .ok(lines.joined(separator: "\n"))
        }
        return .partial(lines.joined(separator: "\n"))
    }
}

private struct BarcodeScannerView: View {
    let probe: BarcodeScannerProbe
    @State private var startError: String?

    var body: some View {
        VStack(spacing: 0) {
            if DataScannerViewController.isSupported {
                DataScannerRepresentable(probe: probe, startError: $startError)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            } else {
                ContentUnavailableView(
                    "DataScanner не поддерживается",
                    systemImage: "barcode.viewfinder",
                    description: Text("Устройству нужен нейромодуль (A12 Bionic и новее).")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            VStack(alignment: .leading, spacing: 6) {
                if let error = startError {
                    Text("Ошибка запуска сканера:\n\(error)")
                        .font(.footnote.monospaced())
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                if let code = probe.lastCode {
                    Text("Код: \(code)")
                        .font(.headline.monospaced())
                        .textSelection(.enabled)
                    if let sym = probe.lastSymbology {
                        Text("Символика: \(sym)")
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Наведите камеру на штрихкод EAN-13 (например, на упаковке товара).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("Сканер штрихкодов")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Обёртка над `DataScannerViewController` с делегатом в `@MainActor`-координаторе.
private struct DataScannerRepresentable: UIViewControllerRepresentable {
    let probe: BarcodeScannerProbe
    @Binding var startError: String?

    func makeCoordinator() -> Coordinator { Coordinator(probe: probe) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        guard !context.coordinator.started else { return }
        guard scanner.isAvailable else { return }
        do {
            try scanner.startScanning()
            context.coordinator.started = true
        } catch {
            let description = ProbeLogger.describe(error)
            probe.log("DataScanner.startScanning ошибка:\n\(description)")
            Task { @MainActor in startError = description }
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let probe: BarcodeScannerProbe
        var started = false

        init(probe: BarcodeScannerProbe) { self.probe = probe }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            handle(addedItems)
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didTapOn item: RecognizedItem
        ) {
            handle([item])
        }

        private func handle(_ items: [RecognizedItem]) {
            for item in items {
                if case let .barcode(barcode) = item {
                    let value = barcode.payloadStringValue ?? "(пустой payload)"
                    let symbology = barcode.observation.symbology.rawValue
                    probe.lastCode = value
                    probe.lastSymbology = symbology
                    probe.log("Штрихкод распознан: \(value) [\(symbology)]")
                }
            }
        }
    }
}

import Foundation

/// Тест 13: сеть. HTTPS GET на example.com и HTTP GET на домен из ATS-исключения (neverssl.com).
@MainActor
@Observable
final class NetworkProbe: ProbeTest {
    let id = 13
    let title = "Сеть (HTTPS/HTTP)"
    var timeout: Duration { .seconds(45) }

    func run() async -> ProbeResult {
        var lines: [String] = []

        let httpsOK = await check(
            urlString: "https://example.com",
            label: "HTTPS",
            into: &lines
        )
        let httpOK = await check(
            urlString: "http://neverssl.com",
            label: "HTTP (ATS-исключение)",
            into: &lines
        )

        lines.append("")
        lines.append("HTTP на neverssl.com проверяет, пропускает ли подпись/ATS незащищённые соединения.")

        switch (httpsOK, httpOK) {
        case (true, true):
            return .ok(lines.joined(separator: "\n"))
        case (true, false):
            lines.append("HTTPS работает, но HTTP заблокирован (ATS-исключение не применилось после переподписи).")
            return .partial(lines.joined(separator: "\n"))
        case (false, true):
            return .partial(lines.joined(separator: "\n"))
        default:
            return .fail(lines.joined(separator: "\n"))
        }
    }

    /// Выполняет GET, пишет строку в лог и возвращает true при статусе 2xx/3xx.
    private func check(urlString: String, label: String, into lines: inout [String]) async -> Bool {
        guard let url = URL(string: urlString) else {
            lines.append("\(label) \(urlString): неверный URL")
            return false
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse else {
                lines.append("\(label) \(urlString): ответ без HTTPURLResponse (\(data.count) байт)")
                return false
            }
            let ok = (200..<400).contains(http.statusCode)
            lines.append("\(label) \(urlString): статус \(http.statusCode), \(data.count) байт")
            log("\(label) \(urlString) → \(http.statusCode)")
            return ok
        } catch {
            let description = ProbeLogger.describe(error)
            lines.append("\(label) \(urlString): ошибка\n\(description)")
            log("\(label) \(urlString) ошибка:\n\(description)")
            return false
        }
    }
}

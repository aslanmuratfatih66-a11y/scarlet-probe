import Foundation

/// Итог одного запуска теста.
enum ProbeStatus: String, Sendable, Codable {
    case notRun
    case running
    case ok
    case partial
    case fail

    var emoji: String {
        switch self {
        case .notRun: "⏺"
        case .running: "⏳"
        case .ok: "✅"
        case .partial: "⚠️"
        case .fail: "❌"
        }
    }

    var label: String {
        switch self {
        case .notRun: "не запускался"
        case .running: "выполняется"
        case .ok: "работает"
        case .partial: "частично"
        case .fail: "не работает"
        }
    }
}

struct ProbeResult: Sendable {
    var status: ProbeStatus
    var details: String
    var finishedAt: Date = .now

    static let notRun = ProbeResult(status: .notRun, details: "")
    static let running = ProbeResult(status: .running, details: "Выполняется…")

    static func ok(_ details: String) -> ProbeResult { .init(status: .ok, details: details) }
    static func partial(_ details: String) -> ProbeResult { .init(status: .partial, details: details) }
    static func fail(_ details: String) -> ProbeResult { .init(status: .fail, details: details) }

    /// Провал с полным описанием ошибки (domain, code, description, userInfo).
    static func fail(_ context: String, error: any Error) -> ProbeResult {
        .init(status: .fail, details: "\(context)\n\(ProbeLogger.describe(error))")
    }
}

import Foundation
import Observation

@MainActor
@Observable
final class ProbeLogger {
    static let shared = ProbeLogger()

    struct Entry: Identifiable, Sendable {
        let id = UUID()
        let date: Date
        let testID: Int?
        let message: String
    }

    private(set) var entries: [Entry] = []

    private init() {}

    func log(_ message: String, testID: Int? = nil) {
        entries.append(Entry(date: .now, testID: testID, message: message))
        let prefix = testID.map { "[#\($0)] " } ?? ""
        print("[ScarletProbe] \(prefix)\(message)")
    }

    func clear() { entries.removeAll() }

    var text: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return entries.map { entry in
            let prefix = entry.testID.map { "[#\($0)] " } ?? ""
            return "\(formatter.string(from: entry.date)) \(prefix)\(entry.message)"
        }.joined(separator: "\n")
    }

    /// Полное описание ошибки: domain, code, description, userInfo и underlying errors.
    nonisolated static func describe(_ error: any Error) -> String {
        let ns = error as NSError
        var lines = [
            "domain=\(ns.domain)",
            "code=\(ns.code)",
            "description=\(ns.localizedDescription)",
        ]
        if let reason = ns.localizedFailureReason { lines.append("reason=\(reason)") }
        if let suggestion = ns.localizedRecoverySuggestion { lines.append("suggestion=\(suggestion)") }
        let swiftDescription = String(describing: error)
        if swiftDescription != ns.localizedDescription { lines.append("swift=\(swiftDescription)") }
        let extraInfo = ns.userInfo.filter {
            $0.key != NSUnderlyingErrorKey && $0.key != NSLocalizedDescriptionKey
        }
        if !extraInfo.isEmpty { lines.append("userInfo=\(extraInfo)") }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? any Error {
            lines.append("underlying: " + describe(underlying).replacingOccurrences(of: "\n", with: "; "))
        }
        return lines.joined(separator: "\n")
    }
}

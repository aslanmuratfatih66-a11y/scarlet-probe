import Foundation
import Observation

/// Состояние экрана: результаты тестов, запуск по одному и всех сразу, отчёт.
@MainActor
@Observable
final class ProbeStore {
    let tests: [any ProbeTest]
    private(set) var results: [Int: ProbeResult] = [:]
    private(set) var isRunningAll = false

    init(tests: [any ProbeTest] = ProbeRegistry.all) {
        self.tests = tests
    }

    func result(for test: any ProbeTest) -> ProbeResult {
        results[test.id] ?? .notRun
    }

    func run(_ test: any ProbeTest) async {
        guard results[test.id]?.status != .running else { return }
        results[test.id] = .running
        ProbeLogger.shared.log("Старт: \(test.title)", testID: test.id)
        let result = await Self.runIsolated(test)
        results[test.id] = result
        ProbeLogger.shared.log(
            "Итог: \(result.status.emoji) \(result.status.label)\n\(result.details)",
            testID: test.id
        )
    }

    func runAll() async {
        guard !isRunningAll else { return }
        isRunningAll = true
        defer { isRunningAll = false }
        for test in tests {
            await run(test)
        }
    }

    /// Запускает тест в отдельной задаче и ждёт не дольше `timeout`.
    /// Если тест завис (делегат не ответил), раннер идёт дальше с ⚠️.
    private static func runIsolated(_ test: any ProbeTest) async -> ProbeResult {
        let timeout = test.timeout
        return await withCheckedContinuation { continuation in
            let gate = ResumeOnce(continuation)
            let work = Task { @MainActor in
                gate.resume(with: await test.run())
            }
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                if gate.resume(with: .partial("Таймаут: тест не завершился за \(timeout.components.seconds) с. Возможно, ждёт действия пользователя или системного ответа.")) {
                    work.cancel()
                }
            }
        }
    }

    var reportText: String {
        var lines: [String] = []
        lines.append("ScarletProbe — отчёт")
        lines.append(DeviceInfo.summary)
        lines.append("")
        lines.append("=== Результаты ===")
        for test in tests {
            let result = result(for: test)
            lines.append("\(test.id). \(test.title): \(result.status.emoji) \(result.status.label)")
            if !result.details.isEmpty {
                lines.append(result.details.split(separator: "\n", omittingEmptySubsequences: false)
                    .map { "    " + $0 }.joined(separator: "\n"))
            }
        }
        lines.append("")
        lines.append("=== Подпись и профиль ===")
        lines.append(DeviceInfo.provisioningSummary)
        lines.append("")
        lines.append("=== Полный лог ===")
        lines.append(ProbeLogger.shared.text)
        return lines.joined(separator: "\n")
    }
}

/// Гарантирует, что continuation будет возобновлён ровно один раз.
@MainActor
private final class ResumeOnce {
    private var continuation: CheckedContinuation<ProbeResult, Never>?

    init(_ continuation: CheckedContinuation<ProbeResult, Never>) {
        self.continuation = continuation
    }

    @discardableResult
    func resume(with result: ProbeResult) -> Bool {
        guard let continuation else { return false }
        self.continuation = nil
        continuation.resume(returning: result)
        return true
    }
}

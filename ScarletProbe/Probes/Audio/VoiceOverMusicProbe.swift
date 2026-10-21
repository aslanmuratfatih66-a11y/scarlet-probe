import Foundation
import Observation
import SwiftUI
import UIKit
@preconcurrency import AVFoundation

/// Тест 6. Голос поверх музыки: `.playback` + `.duckOthers` + `.mixWithOthers`,
/// фраза по-русски и по-турецки, повтор через 10 с для проверки в фоне.
@MainActor
@Observable
final class VoiceOverMusicProbe: ProbeTest {
    let id = 6
    let title = "Голос поверх музыки"
    var timeout: Duration { .seconds(90) }

    static let russianPhrase = "Поверни налево и ускорься"
    static let turkishPhrase = "Sola dön ve hızlan"
    private static let historyKey = "probe.audio.voice.backgroundAttempts"
    private static let historyLimit = 30

    /// История фоновых попыток, новые сверху. Хранится в UserDefaults.
    private(set) var attempts: [String] = []
    private(set) var statusLine = "Ещё не запускался"
    private(set) var isSpeaking = false
    private(set) var isScheduled = false

    /// Синтезатор держится сильной ссылкой, иначе речь обрывается.
    private let synthesizer = AVSpeechSynthesizer()
    private let delegateProxy = SpeechSynthesizerDelegateProxy()
    @ObservationIgnored private var finishContinuation: CheckedContinuation<SpeakOutcome, Never>?
    @ObservationIgnored private var currentUtteranceID: ObjectIdentifier?
    @ObservationIgnored private var stateAtSpeechStart: String?
    @ObservationIgnored private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    @ObservationIgnored private var scheduledTask: Task<Void, Never>?

    init() {
        attempts = UserDefaults.standard.stringArray(forKey: Self.historyKey) ?? []
        synthesizer.delegate = delegateProxy
        delegateProxy.owner = self
    }

    var detailView: AnyView? { AnyView(VoiceOverMusicDetailView(probe: self)) }

    // MARK: - Запуск

    func run() async -> ProbeResult {
        var lines: [String] = []
        let voices = Self.voiceLines()
        let hasRussian = AVSpeechSynthesisVoice(language: "ru-RU") != nil
        let hasTurkish = AVSpeechSynthesisVoice(language: "tr-TR") != nil

        let report = await performSequence(context: "передний план")
        lines.append(contentsOf: report.lines)

        if report.sessionFailed {
            lines.append("")
            lines.append("Голоса ru/tr (\(voices.count)):")
            lines.append(contentsOf: voices.map { "  " + $0 })
            return ProbeResult(status: .fail, details: lines.joined(separator: "\n"))
        }

        scheduleBackgroundAttempt()
        lines.append("")
        lines.append("⏱ Фоновая проверка запланирована через 10 с — сверните приложение сейчас. Результат будет в логе и на экране «Открыть».")
        if let last = attempts.first {
            lines.append("Предыдущая фоновая попытка: \(last)")
        }
        lines.append("Приглушение музыки (duck) программно не проверить — слушайте: музыка должна стать тише на время фразы и вернуть громкость после.")
        lines.append("")
        lines.append("Голоса ru/tr (\(voices.count)):")
        lines.append(contentsOf: voices.isEmpty ? ["  нет ни одного голоса ru/tr"] : voices.map { "  " + $0 })

        let allSpoken = report.russian == .finished && report.turkish == .finished
        let status: ProbeStatus = (allSpoken && hasRussian && hasTurkish) ? .ok : .partial
        if !hasRussian { lines.append("⚠️ Голос ru-RU не найден — использован голос по умолчанию.") }
        if !hasTurkish { lines.append("⚠️ Голос tr-TR не найден — использован голос по умолчанию.") }
        return ProbeResult(status: status, details: lines.joined(separator: "\n"))
    }

    /// Кнопка «Сказать сейчас».
    func speakNow() async {
        let report = await performSequence(context: "по кнопке")
        for line in report.lines { log(line) }
    }

    func clearAttempts() {
        attempts = []
        UserDefaults.standard.removeObject(forKey: Self.historyKey)
    }

    // MARK: - Фоновая проверка

    func scheduleBackgroundAttempt(delay: Duration = .seconds(10)) {
        scheduledTask?.cancel()
        beginBackgroundTaskIfNeeded()
        isScheduled = true
        statusLine = "Через 10 с прозвучит фраза — сверните приложение"
        log("Фоновая проверка запланирована через 10 с — сверните приложение")
        scheduledTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return // заменено новым расписанием, фоновую задачу оно переиспользует
            }
            await self?.performBackgroundAttempt()
        }
    }

    private func performBackgroundAttempt() async {
        isScheduled = false
        let stateBefore = Self.describe(UIApplication.shared.applicationState)
        let remaining = UIApplication.shared.backgroundTimeRemaining
        let remainingText = remaining > 1_000_000 ? "∞ (передний план)" : String(format: "%.1f с", remaining)
        log("Фоновая попытка: состояние приложения \(stateBefore), backgroundTimeRemaining \(remainingText)")

        let report = await performSequence(context: "отложенная, 10 с")
        for line in report.lines { log(line) }

        let verdict: String
        if report.sessionFailed {
            verdict = "❌ аудиосессия не активировалась"
        } else if report.russian == .finished {
            if report.russianStateAtStart == "background" {
                verdict = "✅ фраза прозвучала в фоне"
            } else {
                verdict = "⚠️ фраза прозвучала, но приложение не было в фоне (\(report.russianStateAtStart ?? "?")) — сверните приложение"
            }
        } else {
            verdict = "❌ фраза не прозвучала (\(report.russian?.label ?? "не запускалась"))"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM HH:mm:ss"
        var entry = "\(formatter.string(from: .now)) \(verdict); состояние до: \(stateBefore), при речи: \(report.russianStateAtStart ?? "?"); фон. время: \(remainingText)"
        if let error = report.sessionErrorShort { entry += "; ошибка: \(error)" }
        appendAttempt(entry)
        log("Итог фоновой попытки: \(entry)")
        statusLine = verdict
        endBackgroundTask()
    }

    private func appendAttempt(_ entry: String) {
        attempts.insert(entry, at: 0)
        if attempts.count > Self.historyLimit {
            attempts = Array(attempts.prefix(Self.historyLimit))
        }
        UserDefaults.standard.set(attempts, forKey: Self.historyKey)
    }

    private func beginBackgroundTaskIfNeeded() {
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "ScarletProbe.voice") { [weak self] in
            MainActor.assumeIsolated {
                self?.log("Фоновое время истекло до фразы (expirationHandler)")
                self?.endBackgroundTask()
            }
        }
        if backgroundTaskID == .invalid {
            log("beginBackgroundTask вернул .invalid — фоновое время не выдано")
        }
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    // MARK: - Последовательность: сессия → ru → tr → деактивация

    private struct SequenceReport {
        var lines: [String] = []
        var sessionFailed = false
        var sessionErrorShort: String?
        var russian: SpeakOutcome?
        var turkish: SpeakOutcome?
        var russianStateAtStart: String?
    }

    private func performSequence(context: String) async -> SequenceReport {
        var report = SequenceReport()
        // Не пересекаемся с тестом 15: он тоже перенастраивает AVAudioSession.
        let ticket = await AudioSessionGate.shared.acquire("Тест 6: голос", maxWait: .seconds(20))
        defer { AudioSessionGate.shared.release(ticket) }
        if let note = ticket.note { report.lines.append(note) }

        isSpeaking = true
        defer { isSpeaking = false }
        statusLine = "Говорю (\(context))…"
        report.lines.append("Контекст: \(context), состояние приложения: \(Self.describe(UIApplication.shared.applicationState))")

        let session = AVAudioSession.sharedInstance()
        report.lines.append("isOtherAudioPlaying (до): \(session.isOtherAudioPlaying)")
        report.lines.append("secondaryAudioShouldBeSilencedHint (до): \(session.secondaryAudioShouldBeSilencedHint)")

        do {
            try session.setCategory(
                .playback,
                mode: .voicePrompt,
                options: [.duckOthers, .mixWithOthers, .interruptSpokenAudioAndMixWithOthers]
            )
            report.lines.append("setCategory(.playback, .voicePrompt, [duckOthers, mixWithOthers, interruptSpokenAudioAndMixWithOthers]): OK")
        } catch {
            report.sessionFailed = true
            report.sessionErrorShort = Self.short(error)
            report.lines.append("❌ setCategory: \(ProbeLogger.describe(error))")
            statusLine = "❌ setCategory: \(Self.short(error))"
            return report
        }
        do {
            try session.setActive(true)
            report.lines.append("setActive(true): OK")
        } catch {
            report.sessionFailed = true
            report.sessionErrorShort = Self.short(error)
            report.lines.append("❌ setActive(true): \(ProbeLogger.describe(error))")
            statusLine = "❌ setActive: \(Self.short(error))"
            return report
        }
        let outputs = session.currentRoute.outputs.map { $0.portName }.joined(separator: ", ")
        report.lines.append("Категория: \(session.category.rawValue), режим: \(session.mode.rawValue), выход: \(outputs)")

        let ru = await speak(Self.russianPhrase, language: "ru-RU")
        report.russian = ru.outcome
        report.russianStateAtStart = ru.stateAtStart
        report.lines.append("ru-RU «\(Self.russianPhrase)»: \(ru.summary)")

        let tr = await speak(Self.turkishPhrase, language: "tr-TR")
        report.turkish = tr.outcome
        report.lines.append("tr-TR «\(Self.turkishPhrase)»: \(tr.summary)")

        report.lines.append("isOtherAudioPlaying (после речи): \(session.isOtherAudioPlaying)")
        // Вернуть громкость музыке: деактивация с уведомлением остальных.
        let deactivation = await deactivate(session)
        report.lines.append("setActive(false, .notifyOthersOnDeactivation): \(deactivation)")

        let ok = ru.outcome == .finished && tr.outcome == .finished
        statusLine = ok
            ? "✅ Обе фразы произнесены (\(context), состояние: \(ru.stateAtStart))"
            : "⚠️ ru: \(ru.outcome.label), tr: \(tr.outcome.label)"
        return report
    }

    private func deactivate(_ session: AVAudioSession) async -> String {
        var lastError = ""
        for attempt in 1...3 {
            do {
                try session.setActive(false, options: .notifyOthersOnDeactivation)
                return attempt == 1 ? "OK" : "OK (с попытки \(attempt))"
            } catch {
                lastError = ProbeLogger.describe(error).replacingOccurrences(of: "\n", with: "; ")
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
        return "ошибка: \(lastError)"
    }

    // MARK: - Речь

    enum SpeakOutcome: Equatable, Sendable {
        case finished
        case cancelled
        case timedOut

        var label: String {
            switch self {
            case .finished: "произнесено"
            case .cancelled: "отменено"
            case .timedOut: "таймаут 20 с (делегат didFinish не пришёл)"
            }
        }
    }

    private struct SpeakReport {
        let outcome: SpeakOutcome
        let stateAtStart: String
        let stateAtEnd: String
        let voice: String
        let seconds: Double

        var summary: String {
            "\(outcome.label); голос: \(voice); состояние при начале речи: \(stateAtStart), в конце: \(stateAtEnd); \(String(format: "%.1f", seconds)) с"
        }
    }

    /// Говорит фразу и ждёт `didFinish` (не дольше 20 с).
    private func speak(_ text: String, language: String) async -> SpeakReport {
        // Если что-то ещё звучит — прерываем, чтобы делегат не перепутал фразы.
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        resolveCurrent(.cancelled)

        let utterance = AVSpeechUtterance(string: text)
        let voice = AVSpeechSynthesisVoice(language: language)
        utterance.voice = voice
        let voiceText = voice.map { "\($0.name) [\($0.identifier)]" } ?? "нет \(language), голос по умолчанию"
        let utteranceID = ObjectIdentifier(utterance)
        currentUtteranceID = utteranceID
        stateAtSpeechStart = nil
        let requestedState = Self.describe(UIApplication.shared.applicationState)
        let started = Date()

        let outcome = await withCheckedContinuation { (continuation: CheckedContinuation<SpeakOutcome, Never>) in
            finishContinuation = continuation
            synthesizer.speak(utterance)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(20))
                guard let self, self.currentUtteranceID == utteranceID else { return }
                self.resolveCurrent(.timedOut)
                self.synthesizer.stopSpeaking(at: .immediate)
            }
        }
        currentUtteranceID = nil
        return SpeakReport(
            outcome: outcome,
            stateAtStart: stateAtSpeechStart ?? requestedState,
            stateAtEnd: Self.describe(UIApplication.shared.applicationState),
            voice: voiceText,
            seconds: Date().timeIntervalSince(started)
        )
    }

    private func resolveCurrent(_ outcome: SpeakOutcome) {
        guard let continuation = finishContinuation else { return }
        finishContinuation = nil
        continuation.resume(returning: outcome)
    }

    /// Вызывается прокси-делегатом на главном акторе.
    fileprivate func synthesizerEvent(_ event: SpeechSynthesizerDelegateProxy.Event, utteranceID: ObjectIdentifier) {
        guard utteranceID == currentUtteranceID else { return }
        switch event {
        case .started:
            stateAtSpeechStart = Self.describe(UIApplication.shared.applicationState)
        case .finished:
            resolveCurrent(.finished)
        case .cancelled:
            resolveCurrent(.cancelled)
        }
    }

    // MARK: - Справочные данные

    static func voiceLines() -> [String] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("ru") || $0.language.hasPrefix("tr") }
            .sorted { ($0.language, $0.name) < ($1.language, $1.name) }
            .map { "\($0.language) · \($0.name) · \(describe($0.quality)) · \($0.identifier)" }
    }

    static func describe(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .default: "default"
        case .enhanced: "enhanced"
        case .premium: "premium"
        @unknown default: "quality(\(quality.rawValue))"
        }
    }

    static func describe(_ state: UIApplication.State) -> String {
        switch state {
        case .active: "active"
        case .inactive: "inactive"
        case .background: "background"
        @unknown default: "state(\(state.rawValue))"
        }
    }

    private static func short(_ error: any Error) -> String {
        let ns = error as NSError
        return "\(ns.domain) \(ns.code): \(ns.localizedDescription)"
    }
}

/// Делегат синтезатора. Колбэки могут прийти не на главном потоке,
/// поэтому на главный актор переносим только Sendable-данные (ObjectIdentifier, событие).
final class SpeechSynthesizerDelegateProxy: NSObject, AVSpeechSynthesizerDelegate {
    enum Event: Sendable {
        case started
        case finished
        case cancelled
    }

    weak var owner: VoiceOverMusicProbe?

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        forward(.started, utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        forward(.finished, utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        forward(.cancelled, utterance)
    }

    private nonisolated func forward(_ event: Event, _ utterance: AVSpeechUtterance) {
        let utteranceID = ObjectIdentifier(utterance)
        let owner = self.owner
        Task { @MainActor in
            owner?.synthesizerEvent(event, utteranceID: utteranceID)
        }
    }
}

private struct VoiceOverMusicDetailView: View {
    let probe: VoiceOverMusicProbe
    @State private var voices: [String] = []

    var body: some View {
        List {
            Section("Проверка") {
                Text(probe.statusLine)
                    .font(.footnote)
                Button("Сказать сейчас") {
                    Task { await probe.speakNow() }
                }
                .disabled(probe.isSpeaking)
                Button(probe.isScheduled ? "Запланировано… (сверните)" : "Сказать через 10 с (сверните)") {
                    probe.scheduleBackgroundAttempt()
                }
                Text("Включите музыку (Apple Music, YouTube и т.п.), нажмите кнопку и сразу сверните приложение. Через 10 с фраза должна прозвучать поверх приглушённой музыки.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Фоновые попытки (\(probe.attempts.count))") {
                if probe.attempts.isEmpty {
                    Text("Пока нет").foregroundStyle(.secondary)
                } else {
                    ForEach(probe.attempts.indices, id: \.self) { index in
                        Text(probe.attempts[index])
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    Button("Очистить историю", role: .destructive) {
                        probe.clearAttempts()
                    }
                }
            }
            Section("Голоса ru / tr (\(voices.count))") {
                if voices.isEmpty {
                    Text("Нет голосов ru/tr").foregroundStyle(.secondary)
                } else {
                    ForEach(voices, id: \.self) { line in
                        Text(line)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .onAppear { voices = VoiceOverMusicProbe.voiceLines() }
    }
}

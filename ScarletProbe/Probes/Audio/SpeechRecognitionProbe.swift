import Foundation
import SwiftUI
@preconcurrency import AVFoundation
@preconcurrency import Speech

/// Тест 15. Микрофон + SFSpeechRecognizer ru-RU: 5 секунд речи → текст.
@MainActor
@Observable
final class SpeechRecognitionProbe: ProbeTest {
    let id = 15
    let title = "Микрофон и распознавание речи"
    /// Ожидание двух системных запросов + 5 с записи + до 10 с на финальный результат.
    var timeout: Duration { .seconds(50) }

    private static let recordSeconds = 5
    private static let finalResultTimeout: Duration = .seconds(10)

    /// Живой распознанный текст и флаг записи — для экрана теста.
    private(set) var liveText = ""
    private(set) var isRunning = false

    var detailView: AnyView? { AnyView(SpeechRecognitionDetailView(probe: self)) }

    func run() async -> ProbeResult {
        isRunning = true
        liveText = ""
        defer { isRunning = false }
        var lines: [String] = []

        // 1. Разрешение на распознавание речи.
        let speechBefore = SFSpeechRecognizer.authorizationStatus()
        lines.append("Распознавание речи (до): \(Self.describe(speechBefore))")
        var speechStatus = speechBefore
        if speechBefore == .notDetermined {
            speechStatus = await Self.requestSpeechAuthorization()
            lines.append("Распознавание речи (после запроса): \(Self.describe(speechStatus))")
        }

        // 2. Разрешение на микрофон.
        let micBefore = Self.microphoneStatus()
        lines.append("Микрофон (до): \(micBefore)")
        var micGranted = micBefore == "granted"
        if micBefore == "undetermined" {
            micGranted = await Self.requestMicrophone()
            lines.append("Микрофон (после запроса): \(micGranted ? "granted" : "denied")")
        }

        // 3. Распознаватель ru-RU.
        let locale = Locale(identifier: "ru-RU")
        let supported = SFSpeechRecognizer.supportedLocales().contains { $0.identifier == "ru-RU" || $0.identifier == "ru_RU" }
        lines.append("ru-RU в supportedLocales: \(supported)")
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            lines.append("SFSpeechRecognizer(locale: ru-RU) вернул nil.")
            return .fail(lines.joined(separator: "\n"))
        }
        lines.append("isAvailable: \(recognizer.isAvailable)")
        lines.append("supportsOnDeviceRecognition: \(recognizer.supportsOnDeviceRecognition)")

        guard speechStatus == .authorized else {
            lines.append("Нет разрешения на распознавание речи — запись не выполнялась. Настройки → ScarletProbe → Распознавание речи.")
            return .fail(lines.joined(separator: "\n"))
        }
        guard micGranted else {
            lines.append("Нет доступа к микрофону — запись не выполнялась. Настройки → ScarletProbe → Микрофон.")
            return .fail(lines.joined(separator: "\n"))
        }
        guard recognizer.isAvailable else {
            lines.append("Распознаватель недоступен (нет сети и нет on-device модели?).")
            return .fail(lines.joined(separator: "\n"))
        }

        // 4. Запись и распознавание.
        let ticket = await AudioSessionGate.shared.acquire("Тест 15: распознавание", maxWait: .seconds(10))
        defer { AudioSessionGate.shared.release(ticket) }
        if let note = ticket.note { lines.append(note) }
        return await recognize(with: recognizer, lines: lines)
    }

    private func recognize(with recognizer: SFSpeechRecognizer, lines initialLines: [String]) async -> ProbeResult {
        var lines = initialLines
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            lines.append("Аудиосессия (.record, .measurement) не активировалась:")
            lines.append(ProbeLogger.describe(error))
            return .fail(lines.joined(separator: "\n"))
        }
        lines.append("Аудиосессия: .record / .measurement, вход: \(session.currentRoute.inputs.map { $0.portName }.joined(separator: ", ")), isInputAvailable: \(session.isInputAvailable)")

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        lines.append("Формат входа: \(format.sampleRate) Гц, каналов: \(format.channelCount)")
        guard format.sampleRate > 0, format.channelCount > 0 else {
            lines.append("Микрофон отдаёт пустой формат — запись невозможна.")
            await Self.deactivate(session, lines: &lines)
            return .fail(lines.joined(separator: "\n"))
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        let box = RecognitionRequestBox(request)
        let collector = RecognitionCollector()

        let task = recognizer.recognitionTask(
            with: request,
            resultHandler: Self.makeResultHandler(collector) { [weak self] text in
                self?.liveText = text
            }
        )
        Self.installTap(on: input, format: format, box: box)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            task.cancel()
            lines.append("AVAudioEngine.start() не удался:")
            lines.append(ProbeLogger.describe(error))
            await Self.deactivate(session, lines: &lines)
            return .fail(lines.joined(separator: "\n"))
        }

        log("🎙 Говорите \(Self.recordSeconds) секунд…")
        try? await Task.sleep(for: .seconds(Self.recordSeconds))

        engine.stop()
        input.removeTap(onBus: 0)
        request.endAudio()
        let buffers = box.bufferCount
        lines.append("Записано буферов: \(buffers)")

        let finished = await collector.waitForFinish(timeout: Self.finalResultTimeout)
        if !finished {
            task.cancel()
            lines.append("Финальный результат не пришёл за \(Self.finalResultTimeout.components.seconds) с — задача отменена.")
        }
        await Self.deactivate(session, lines: &lines)

        let snapshot = collector.snapshot()
        lines.append("Промежуточных результатов: \(snapshot.partialCount)")
        if let finalText = snapshot.finalText, !finalText.isEmpty {
            lines.append("Распознано (финал): «\(finalText)»")
            return .ok(lines.joined(separator: "\n"))
        }
        if !snapshot.latestText.isEmpty {
            lines.append("Распознано (промежуточно): «\(snapshot.latestText)»")
        }
        if let error = snapshot.error {
            lines.append("Ошибка распознавания:")
            lines.append(ProbeLogger.describe(error))
            if let hint = Self.hint(for: error) { lines.append("Подсказка: \(hint)") }
        }

        if buffers == 0 {
            lines.append("Микрофон не дал ни одного буфера.")
            return .fail(lines.joined(separator: "\n"))
        }
        if !snapshot.latestText.isEmpty {
            return .partial(lines.joined(separator: "\n"))
        }
        if let error = snapshot.error {
            let ns = error as NSError
            if ns.domain == "kAFAssistantErrorDomain" && (ns.code == 1110 || ns.code == 203) {
                lines.append("Конвейер работает, но речь не обнаружена — говорите во время записи и запустите снова.")
                return .partial(lines.joined(separator: "\n"))
            }
            return .fail(lines.joined(separator: "\n"))
        }
        lines.append("Текст не получен (речь не распознана).")
        return .partial(lines.joined(separator: "\n"))
    }

    // MARK: - Помощники вне главного актора

    /// Tap-блок вызывается на аудио-потоке реального времени. Создаём его в nonisolated
    /// контексте, чтобы Swift 6 не сделал его @MainActor (иначе — краш проверки изоляции).
    nonisolated private static func installTap(on node: AVAudioInputNode, format: AVAudioFormat, box: RecognitionRequestBox) {
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in
            box.append(buffer)
        }
    }

    /// Обработчик результатов распознавания: из не-Sendable результата сразу достаём строки.
    /// `live` вызывается на главном акторе для обновления живого текста на экране теста.
    nonisolated private static func makeResultHandler(
        _ collector: RecognitionCollector,
        live: @escaping @Sendable @MainActor (String) -> Void
    ) -> @Sendable (SFSpeechRecognitionResult?, (any Error)?) -> Void {
        { result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            collector.handle(text: text, isFinal: isFinal, failure: error)
            if let text {
                Task { @MainActor in live(text) }
            }
        }
    }

    nonisolated private static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { @Sendable status in
                continuation.resume(returning: status)
            }
        }
    }

    nonisolated private static func requestMicrophone() async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { @Sendable granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private static func microphoneStatus() -> String {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: "granted"
        case .denied: "denied"
        case .undetermined: "undetermined"
        @unknown default: "unknown"
        }
    }

    private static func deactivate(_ session: AVAudioSession, lines: inout [String]) async {
        for attempt in 1...3 {
            do {
                try session.setActive(false, options: .notifyOthersOnDeactivation)
                lines.append("Аудиосессия деактивирована" + (attempt > 1 ? " (с попытки \(attempt))" : ""))
                return
            } catch {
                if attempt == 3 {
                    lines.append("setActive(false) не удался: " + ProbeLogger.describe(error).replacingOccurrences(of: "\n", with: "; "))
                } else {
                    try? await Task.sleep(for: .milliseconds(300))
                }
            }
        }
    }

    nonisolated static func describe(_ status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "notDetermined"
        case .denied: "denied"
        case .restricted: "restricted"
        case .authorized: "authorized"
        @unknown default: "unknown(\(status.rawValue))"
        }
    }

    /// Примерные расшифровки частых кодов kAFAssistantErrorDomain (официально не документированы).
    nonisolated private static func hint(for error: any Error) -> String? {
        let ns = error as NSError
        guard ns.domain == "kAFAssistantErrorDomain" else { return nil }
        switch ns.code {
        case 203: return "203 — речь не распознана / Retry (часто, если молчали)."
        case 209, 216: return "\(ns.code) — сеанс распознавания прерван/отменён."
        case 301: return "301 — запрос отменён."
        case 1101: return "1101 — внутренняя ошибка сервиса (часто безвредна)."
        case 1107: return "1107 — сбой связи с сервисом распознавания."
        case 1110: return "1110 — речь не обнаружена."
        case 1700: return "1700 — нет авторизации/доступа к сервису (возможно, из-за подписи)."
        default: return nil
        }
    }
}

/// Контейнер для `SFSpeechAudioBufferRecognitionRequest`, который нужно передать в tap-блок
/// аудио-потока. `@unchecked Sendable` безопасен, потому что:
/// - из аудио-потока вызывается только `append(_:)`, а Apple документирует добавление буферов
///   из tap-блока как штатный сценарий (так сделано в официальном примере SpokenWord);
/// - `endAudio()` вызывается с главного актора только ПОСЛЕ `engine.stop()` и `removeTap`,
///   то есть когда tap-блок уже не вызывается;
/// - счётчик буферов защищён замком.
final class RecognitionRequestBox: @unchecked Sendable {
    private let request: SFSpeechAudioBufferRecognitionRequest
    private let lock = NSLock()
    private var count = 0

    init(_ request: SFSpeechAudioBufferRecognitionRequest) {
        self.request = request
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        request.append(buffer)
        lock.lock()
        count += 1
        lock.unlock()
    }

    var bufferCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

/// Собирает результаты распознавания с любого потока. Всё состояние — под замком.
final class RecognitionCollector: @unchecked Sendable {
    struct Snapshot {
        let latestText: String
        let finalText: String?
        let partialCount: Int
        let error: (any Error)?
    }

    private let lock = NSLock()
    private var latestText = ""
    private var finalText: String?
    private var partialCount = 0
    private var error: (any Error)?
    private var done = false
    private var waiter: CheckedContinuation<Void, Never>?

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    func handle(text: String?, isFinal: Bool, failure: (any Error)?) {
        let toResume: CheckedContinuation<Void, Never>? = locked {
            if let text {
                latestText = text
                partialCount += 1
            }
            if isFinal {
                finalText = text ?? latestText
            }
            if let failure, error == nil {
                error = failure
            }
            guard (isFinal || failure != nil), !done else { return nil }
            done = true
            let pending = waiter
            waiter = nil
            return pending
        }
        toResume?.resume()
    }

    /// Ждёт финальный результат или ошибку. Возвращает false, если вышел таймаут.
    func waitForFinish(timeout: Duration) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let alreadyDone: Bool = locked {
                if done { return true }
                waiter = continuation
                return false
            }
            if alreadyDone {
                continuation.resume()
                return
            }
            Task {
                try? await Task.sleep(for: timeout)
                self.fireTimeout()
            }
        }
        return locked { done }
    }

    private func fireTimeout() {
        let pending: CheckedContinuation<Void, Never>? = locked {
            let pending = waiter
            waiter = nil
            return pending
        }
        pending?.resume()
    }

    func snapshot() -> Snapshot {
        locked {
            Snapshot(latestText: latestText, finalText: finalText, partialCount: partialCount, error: error)
        }
    }
}

/// Экран теста 15: запись 5 секунд и живой распознанный текст.
private struct SpeechRecognitionDetailView: View {
    let probe: SpeechRecognitionProbe
    @State private var lastResult: String = ""

    var body: some View {
        List {
            Section {
                Button {
                    Task {
                        let result = await probe.run()
                        lastResult = "\(result.status.emoji) \(result.status.label)\n\n\(result.details)"
                    }
                } label: {
                    Label(probe.isRunning ? "Идёт запись…" : "Записать 5 секунд", systemImage: "mic")
                }
                .disabled(probe.isRunning)
                Text("Нажмите и говорите по-русски 5 секунд. Текст появляется ниже по мере распознавания.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Живой текст") {
                Text(probe.liveText.isEmpty ? "—" : probe.liveText)
                    .font(.callout)
                    .textSelection(.enabled)
            }

            if !lastResult.isEmpty {
                Section("Итог последнего запуска") {
                    Text(lastResult)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }
            }
        }
    }
}

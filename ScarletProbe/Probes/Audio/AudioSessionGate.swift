import Foundation

/// Очередь на аудиосессию: тесты 6 (голос поверх музыки) и 15 (распознавание речи)
/// не должны одновременно перенастраивать `AVAudioSession`. Каждый берёт «билет»,
/// ставит свою категорию явно и отпускает билет, когда закончил.
///
/// Если владелец не отпустил сессию за `maxWait`, ожидающий забирает её принудительно
/// (это пишется в лог), чтобы тест не завис навсегда.
@MainActor
final class AudioSessionGate {
    static let shared = AudioSessionGate()
    private init() {}

    struct Ticket: Sendable {
        let id: UUID
        /// Пришлось ждать другой тест.
        let waitedFor: String?
        /// Ожидание закончилось по таймауту, сессия забрана принудительно.
        let forced: Bool

        var note: String? {
            guard let waitedFor else { return nil }
            return forced
                ? "Аудиосессия была занята («\(waitedFor)»), забрана принудительно по таймауту."
                : "Аудиосессия была занята («\(waitedFor)»), дождались освобождения."
        }
    }

    private struct Waiter {
        let id: UUID
        let owner: String
        let continuation: CheckedContinuation<Bool, Never>
    }

    private var currentID: UUID?
    private var currentOwner: String?
    private var waiters: [Waiter] = []

    func acquire(_ owner: String, maxWait: Duration) async -> Ticket {
        guard currentID != nil else {
            let id = UUID()
            currentID = id
            currentOwner = owner
            return Ticket(id: id, waitedFor: nil, forced: false)
        }
        let busyOwner = currentOwner ?? "другой тест"
        let waiterID = UUID()
        let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            waiters.append(Waiter(id: waiterID, owner: owner, continuation: continuation))
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: maxWait)
                self?.expire(waiterID)
            }
        }
        if !granted {
            // Принудительно: release() прежнего владельца теперь будет проигнорирован.
            currentID = waiterID
            currentOwner = owner
        }
        return Ticket(id: waiterID, waitedFor: busyOwner, forced: !granted)
    }

    func release(_ ticket: Ticket) {
        guard currentID == ticket.id else { return }
        if waiters.isEmpty {
            currentID = nil
            currentOwner = nil
        } else {
            let next = waiters.removeFirst()
            currentID = next.id
            currentOwner = next.owner
            next.continuation.resume(returning: true)
        }
    }

    private func expire(_ waiterID: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == waiterID }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(returning: false)
    }
}

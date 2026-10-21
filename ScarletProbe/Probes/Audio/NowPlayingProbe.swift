import Foundation
@preconcurrency import MediaPlayer

/// Тест 7. Что сейчас играет в Apple Music (systemMusicPlayer).
@MainActor
final class NowPlayingProbe: ProbeTest {
    let id = 7
    let title = "Now Playing Apple Music"
    var timeout: Duration { .seconds(90) }

    func run() async -> ProbeResult {
        var lines: [String] = []

        let before = MPMediaLibrary.authorizationStatus()
        lines.append("Авторизация медиатеки (до): \(Self.describe(before))")
        var status = before
        if before == .notDetermined {
            log("Запрашиваю доступ к медиатеке…")
            status = await Self.requestAuthorization()
            lines.append("Авторизация медиатеки (после запроса): \(Self.describe(status))")
        }

        switch status {
        case .authorized:
            break
        case .denied:
            lines.append("Доступ запрещён. Включите: Настройки → ScarletProbe → Медиа и Apple Music.")
            return .fail(lines.joined(separator: "\n"))
        case .restricted:
            lines.append("Доступ ограничен (Экранное время / MDM).")
            return .fail(lines.joined(separator: "\n"))
        case .notDetermined:
            lines.append("Статус остался notDetermined: системный запрос не показался или был закрыт. Возможно, подпись срезала доступ.")
            return .fail(lines.joined(separator: "\n"))
        @unknown default:
            lines.append("Неизвестный статус авторизации.")
            return .fail(lines.joined(separator: "\n"))
        }

        // MPMusicPlayerController — только на главном потоке (мы на MainActor).
        let player = MPMusicPlayerController.systemMusicPlayer
        let state = player.playbackState
        lines.append("playbackState: \(Self.describe(state))")

        guard let item = player.nowPlayingItem else {
            lines.append("nowPlayingItem = nil.")
            lines.append("Включите музыку в Apple Music и запустите снова.")
            return .partial(lines.joined(separator: "\n"))
        }

        lines.append("Название: \(item.title ?? "—")")
        lines.append("Артист: \(item.artist ?? "—")")
        lines.append("Альбом: \(item.albumTitle ?? "—")")
        lines.append(String(format: "Длительность: %.0f с, позиция: %.0f с", item.playbackDuration, player.currentPlaybackTime))
        lines.append("persistentID: \(item.persistentID), playbackStoreID: \(item.playbackStoreID.isEmpty ? "—" : item.playbackStoreID)")
        log("nowPlayingItem: «\(item.title ?? "—")» — \(item.artist ?? "—")")

        let hasMetadata = (item.title?.isEmpty == false) || (item.artist?.isEmpty == false)
        if !hasMetadata {
            lines.append("Трек есть, но без названия и артиста.")
            return .partial(lines.joined(separator: "\n"))
        }
        return .ok(lines.joined(separator: "\n"))
    }

    /// Колбэк `requestAuthorization` приходит на произвольном потоке. Замыкание явно @Sendable
    /// и создаётся вне главного актора — иначе Swift 6 сделает его @MainActor и упадёт
    /// на проверке изоляции при вызове из фонового потока.
    nonisolated private static func requestAuthorization() async -> MPMediaLibraryAuthorizationStatus {
        await withCheckedContinuation { (continuation: CheckedContinuation<MPMediaLibraryAuthorizationStatus, Never>) in
            MPMediaLibrary.requestAuthorization { @Sendable status in
                continuation.resume(returning: status)
            }
        }
    }

    nonisolated static func describe(_ status: MPMediaLibraryAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "notDetermined"
        case .denied: "denied"
        case .restricted: "restricted"
        case .authorized: "authorized"
        @unknown default: "unknown(\(status.rawValue))"
        }
    }

    nonisolated static func describe(_ state: MPMusicPlaybackState) -> String {
        switch state {
        case .stopped: "stopped"
        case .playing: "playing"
        case .paused: "paused"
        case .interrupted: "interrupted"
        case .seekingForward: "seekingForward"
        case .seekingBackward: "seekingBackward"
        @unknown default: "unknown(\(state.rawValue))"
        }
    }
}

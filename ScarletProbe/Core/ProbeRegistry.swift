import Foundation

/// Реестр тестов: каждый тест добавляется одной строкой, по порядку номеров.
@MainActor
enum ProbeRegistry {
    static let all: [any ProbeTest] = [
        NotificationsProbe(),       // 1  Локальные уведомления
        PedometerProbe(),           // 2  Шаги CoreMotion
        HealthKitProbe(),           // 3  HealthKit
        LocationProbe(),            // 4  Геолокация (фон)
        MapRouteProbe(),            // 5  MapKit маршрут
        VoiceOverMusicProbe(),      // 6  Голос поверх музыки
        NowPlayingProbe(),          // 7  Now Playing Apple Music
        RemotePushProbe(),          // 8  Remote push
        AlarmKitProbe(),            // 9  AlarmKit
        BackgroundRefreshProbe(),   // 10 Фоновое обновление
        CameraPhotoProbe(),         // 11 Камера и фото
        BarcodeScannerProbe(),      // 12 Сканер штрихкодов
        NetworkProbe(),             // 13 Сеть (HTTPS/HTTP)
        KeychainProbe(),            // 14 Keychain
        SpeechRecognitionProbe(),   // 15 Микрофон и распознавание речи
        ExtWidgetProbe(),           // 16 Виджет
        ExtLiveActivityProbe(),     // 17 Live Activity
        ExtAppIntentProbe(),        // 18 App Intents / Команды
        URLSchemeProbe(),           // 19 URL-схема
    ]
}

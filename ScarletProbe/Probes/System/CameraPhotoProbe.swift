import SwiftUI
import UIKit
@preconcurrency import PhotosUI
@preconcurrency import Photos
@preconcurrency import AVFoundation

/// Общие помощники для тестов папки System (камера, сканер).
@MainActor
enum SystemProbeFormat {
    static func camera(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "не запрашивался (notDetermined)"
        case .restricted: return "ограничен (restricted)"
        case .denied: return "запрещён (denied)"
        case .authorized: return "разрешён (authorized)"
        @unknown default: return "неизвестно (\(status.rawValue))"
        }
    }

    static func photos(_ status: PHAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "не запрашивался (notDetermined)"
        case .restricted: return "ограничен (restricted)"
        case .denied: return "запрещён (denied)"
        case .authorized: return "полный доступ (authorized)"
        case .limited: return "ограниченный доступ (limited)"
        @unknown default: return "неизвестно (\(status.rawValue))"
        }
    }

    static func bytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}

/// Тест 11: доступ к камере, PhotosPicker, сохранение фото в Documents.
@MainActor
@Observable
final class CameraPhotoProbe: ProbeTest {
    let id = 11
    let title = "Камера и фото"
    var timeout: Duration { .seconds(90) }

    static let photoPrefix = "probe-photo-"

    /// Последнее сохранённое фото (для экрана теста).
    var lastSavedPath: String?
    var lastSavedSize: Int?
    var lastImage: UIImage?
    var lastMessage: String?

    var detailView: AnyView? { AnyView(CameraPhotoView(probe: self)) }

    func run() async -> ProbeResult {
        var lines: [String] = []

        // 1. Камера
        let before = AVCaptureDevice.authorizationStatus(for: .video)
        lines.append("Камера (до запроса): \(SystemProbeFormat.camera(before))")
        var cameraGranted = before == .authorized
        if before == .notDetermined {
            cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
            let after = AVCaptureDevice.authorizationStatus(for: .video)
            lines.append("Камера (после запроса): \(SystemProbeFormat.camera(after)), requestAccess=\(cameraGranted)")
        }
        let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        if let backCamera {
            lines.append("Задняя камера: есть (\(backCamera.localizedName))")
        } else {
            lines.append("Задняя камера: не найдена")
        }
        let cameraOK = cameraGranted && backCamera != nil

        // 2. Фото
        let photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        lines.append("Фото (readWrite): \(SystemProbeFormat.photos(photoStatus))")
        let addStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        lines.append("Фото (addOnly): \(SystemProbeFormat.photos(addStatus))")

        // 3. Запись тестового файла в Documents
        var documentsOK = false
        let testURL = URL.documentsDirectory.appending(path: "probe-write-test.txt")
        do {
            let payload = Data("ScarletProbe \(Date.now)".utf8)
            try payload.write(to: testURL, options: .atomic)
            let readBack = try Data(contentsOf: testURL)
            documentsOK = readBack == payload
            try FileManager.default.removeItem(at: testURL)
            lines.append("Запись в Documents: \(documentsOK ? "OK" : "прочитано не то, что записано") (\(URL.documentsDirectory.path(percentEncoded: false)))")
        } catch {
            let description = ProbeLogger.describe(error)
            log("Ошибка записи в Documents:\n\(description)")
            lines.append("Запись в Documents: ошибка\n\(description)")
        }

        // 4. Сохранённые фото
        let saved = savedPhotos()
        lines.append("Сохранено фото в Documents: \(saved.count)")
        if let last = saved.last {
            lines.append("Последнее: \(last.lastPathComponent)")
        }

        if !documentsOK {
            return .fail(lines.joined(separator: "\n"))
        }
        if !cameraOK {
            lines.append("Камера недоступна: проверьте Настройки → ScarletProbe → Камера.")
            return saved.isEmpty ? .fail(lines.joined(separator: "\n")) : .partial(lines.joined(separator: "\n"))
        }
        if saved.isEmpty {
            lines.append("Откройте экран теста («Открыть») и выберите фото через PhotosPicker или снимите камерой.")
            return .partial(lines.joined(separator: "\n"))
        }
        return .ok(lines.joined(separator: "\n"))
    }

    /// Фото, которые тест уже сохранял в Documents, по возрастанию имени (времени).
    func savedPhotos() -> [URL] {
        do {
            let all = try FileManager.default.contentsOfDirectory(
                at: URL.documentsDirectory,
                includingPropertiesForKeys: nil
            )
            return all
                .filter { $0.lastPathComponent.hasPrefix(Self.photoPrefix) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            log("Не удалось прочитать Documents:\n\(ProbeLogger.describe(error))")
            return []
        }
    }

    /// Сохраняет изображение в Documents как JPEG (или исходные байты, если не удалось перекодировать).
    func savePhoto(data: Data, source: String) {
        let image = UIImage(data: data)
        let jpeg = image?.jpegData(compressionQuality: 0.9) ?? data
        let timestamp = Int(Date.now.timeIntervalSince1970 * 1000)
        let url = URL.documentsDirectory.appending(path: "\(Self.photoPrefix)\(timestamp).jpg")
        do {
            try jpeg.write(to: url, options: .atomic)
            lastImage = image
            lastSavedPath = url.path(percentEncoded: false)
            lastSavedSize = jpeg.count
            lastMessage = "Сохранено (\(source)): \(SystemProbeFormat.bytes(jpeg.count))"
            log("Фото сохранено (\(source)): \(url.path(percentEncoded: false)), \(jpeg.count) байт")
        } catch {
            let description = ProbeLogger.describe(error)
            lastMessage = "Ошибка сохранения:\n\(description)"
            log("Ошибка сохранения фото (\(source)):\n\(description)")
        }
    }

    func loadPicked(_ item: PhotosPickerItem) async {
        lastMessage = "Загрузка…"
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                lastMessage = "PhotosPicker вернул пустые данные (nil)."
                log("PhotosPicker: loadTransferable вернул nil")
                return
            }
            log("PhotosPicker: получено \(data.count) байт")
            savePhoto(data: data, source: "PhotosPicker")
        } catch {
            let description = ProbeLogger.describe(error)
            lastMessage = "Ошибка загрузки из PhotosPicker:\n\(description)"
            log("PhotosPicker: ошибка loadTransferable:\n\(description)")
        }
    }
}

private struct CameraPhotoView: View {
    let probe: CameraPhotoProbe
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var savedCount = 0

    private var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        List {
            Section("Выбор фото") {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Выбрать фото (PhotosPicker)", systemImage: "photo.on.rectangle")
                }
                Button {
                    showCamera = true
                } label: {
                    Label("Снять камерой", systemImage: "camera")
                }
                .disabled(!cameraAvailable)
                if !cameraAvailable {
                    Text("UIImagePickerController: камера недоступна (sourceType .camera).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Результат") {
                if let message = probe.lastMessage {
                    Text(message).font(.footnote.monospaced()).textSelection(.enabled)
                }
                if let path = probe.lastSavedPath {
                    Text(path).font(.caption.monospaced()).textSelection(.enabled)
                }
                if let size = probe.lastSavedSize {
                    Text("Размер: \(SystemProbeFormat.bytes(size))")
                }
                if let image = probe.lastImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 300)
                }
                Text("Всего сохранено фото в Documents: \(savedCount)")
            }
        }
        .onAppear { savedCount = probe.savedPhotos().count }
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await probe.loadPicked(newItem)
                savedCount = probe.savedPhotos().count
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureView { data in
                showCamera = false
                if let data {
                    probe.savePhoto(data: data, source: "камера")
                    savedCount = probe.savedPhotos().count
                } else {
                    probe.lastMessage = "Съёмка отменена."
                }
            }
            .ignoresSafeArea()
        }
    }
}

/// Съёмка через UIImagePickerController(sourceType: .camera).
private struct CameraCaptureView: UIViewControllerRepresentable {
    let onFinish: @MainActor (Data?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: @MainActor (Data?) -> Void

        init(onFinish: @escaping @MainActor (Data?) -> Void) {
            self.onFinish = onFinish
        }

        nonisolated func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            // Достаём Sendable-данные до перехода на MainActor, чтобы не передавать словарь info.
            let image = info[.originalImage] as? UIImage
            let data: Data? = image?.jpegData(compressionQuality: 0.9)
            MainActor.assumeIsolated {
                if data == nil {
                    ProbeLogger.shared.log("Камера: изображение не получено (originalImage отсутствует)", testID: 11)
                }
                onFinish(data)
            }
        }

        nonisolated func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            MainActor.assumeIsolated {
                onFinish(nil)
            }
        }
    }
}

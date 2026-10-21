import Foundation
import Security

/// Тест 14: Keychain. Запись/чтение/удаление строки через Security (kSecClassGenericPassword).
/// При переподписи чужим сертификатом keychain-access-group меняется, и доступ часто ломается —
/// логируем полный OSStatus каждого шага.
@MainActor
final class KeychainProbe: ProbeTest {
    let id = 14
    let title = "Keychain"

    private let service = "com.local.scarletprobe.test"
    private let account = "probe-account"

    func run() async -> ProbeResult {
        var lines: [String] = []
        let secret = "ScarletProbe-\(Int(Date.now.timeIntervalSince1970))"

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        // Предварительная очистка (на случай остатков от прошлого запуска), статус не оцениваем.
        SecItemDelete(baseQuery as CFDictionary)

        // 1. Запись
        var addQuery = baseQuery
        addQuery[kSecValueData as String] = Data(secret.utf8)
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        lines.append("SecItemAdd: \(statusText(addStatus))")

        // 2. Чтение
        var readQuery = baseQuery
        readQuery[kSecReturnData as String] = true
        readQuery[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let readStatus = SecItemCopyMatching(readQuery as CFDictionary, &item)
        lines.append("SecItemCopyMatching: \(statusText(readStatus))")

        var matched = false
        if readStatus == errSecSuccess,
           let data = item as? Data,
           let read = String(data: data, encoding: .utf8) {
            matched = (read == secret)
            lines.append("Прочитано: \"\(read)\" (ожидалось \"\(secret)\"), совпадает: \(matched)")
        } else {
            lines.append("Прочитать строку не удалось.")
        }

        // 3. Удаление
        let deleteStatus = SecItemDelete(baseQuery as CFDictionary)
        lines.append("SecItemDelete: \(statusText(deleteStatus))")

        let allOK = addStatus == errSecSuccess
            && readStatus == errSecSuccess
            && matched
            && deleteStatus == errSecSuccess
        if allOK {
            return .ok(lines.joined(separator: "\n"))
        }
        return .fail(lines.joined(separator: "\n"))
    }

    /// OSStatus + расшифровка через SecCopyErrorMessageString, если доступна.
    private func statusText(_ status: OSStatus) -> String {
        if status == errSecSuccess { return "OK (0)" }
        if let message = SecCopyErrorMessageString(status, nil) {
            return "\(status) — \(message as String)"
        }
        return "\(status)"
    }
}

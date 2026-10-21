import Foundation
import UIKit

@MainActor
enum DeviceInfo {
    static var summary: String {
        let device = UIDevice.current
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateStyle = .long
        formatter.timeStyle = .medium
        return """
        Дата: \(formatter.string(from: .now))
        iOS: \(device.systemName) \(device.systemVersion)
        Модель: \(device.model) (\(modelIdentifier))
        Bundle ID: \(bundle.bundleIdentifier ?? "?")
        Версия приложения: \(version) (\(build))
        """
    }

    /// Идентификатор железа, например iPhone17,1.
    static var modelIdentifier: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    /// Что выдал подписывающий профиль (embedded.mobileprovision): команда, срок, entitlements.
    static var provisioningSummary: String {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") else {
            return "embedded.mobileprovision не найден (сборка без профиля или профиль удалён)."
        }
        guard let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
        else {
            return "embedded.mobileprovision есть, но plist внутри не найден."
        }
        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            return "embedded.mobileprovision: не удалось разобрать plist."
        }
        var lines: [String] = []
        if let name = plist["Name"] { lines.append("Профиль: \(name)") }
        if let team = plist["TeamName"] { lines.append("Команда: \(team)") }
        if let teamIDs = plist["TeamIdentifier"] as? [String] { lines.append("Team ID: \(teamIDs.joined(separator: ", "))") }
        if let expires = plist["ExpirationDate"] { lines.append("Истекает: \(expires)") }
        if let devices = plist["ProvisionedDevices"] as? [String] { lines.append("Устройств в профиле: \(devices.count)") }
        if plist["ProvisionsAllDevices"] as? Bool == true { lines.append("Enterprise: ProvisionsAllDevices = true") }
        if let entitlements = plist["Entitlements"] as? [String: Any] {
            lines.append("Entitlements профиля:")
            for key in entitlements.keys.sorted() {
                lines.append("  \(key) = \(entitlements[key].map { String(describing: $0) } ?? "nil")")
            }
        }
        return lines.joined(separator: "\n")
    }
}

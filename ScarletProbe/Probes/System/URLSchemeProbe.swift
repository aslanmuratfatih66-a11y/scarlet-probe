import SwiftUI
import UIKit

/// Тест 19: URL-схема. Показывает зарегистрированные схемы из Info.plist и последнюю открытую ссылку.
/// Приём ссылки обрабатывается в `ScarletProbeApp.onOpenURL` → `AppHooks.shared.lastOpenedURL`.
@MainActor
final class URLSchemeProbe: ProbeTest {
    let id = 19
    let title = "URL-схема"

    var detailView: AnyView? { AnyView(URLSchemeView(probe: self)) }

    /// Схемы из CFBundleURLTypes (Info.plist).
    func registeredSchemes() -> [String] {
        guard let types = Bundle.main.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]] else {
            return []
        }
        return types.flatMap { ($0["CFBundleURLSchemes"] as? [String]) ?? [] }
    }

    func run() async -> ProbeResult {
        var lines: [String] = []
        let schemes = registeredSchemes()
        lines.append("Зарегистрированные схемы: \(schemes.isEmpty ? "нет" : schemes.joined(separator: ", "))")

        let hasScheme = schemes.contains("scarletprobe")
        lines.append("scarletprobe://: \(hasScheme ? "зарегистрирована" : "НЕ найдена в Info.plist")")

        if let url = AppHooks.shared.lastOpenedURL {
            lines.append("Последняя открытая ссылка: \(url.absoluteString)")
        } else {
            lines.append("Ссылок ещё не приходило.")
            lines.append("Откройте scarletprobe://test из Safari или Заметок (например, из deep link в ntfy), либо на экране теста нажмите «Открыть scarletprobe://selftest».")
        }

        if !hasScheme {
            return .fail(lines.joined(separator: "\n"))
        }
        if AppHooks.shared.lastOpenedURL == nil {
            return .partial(lines.joined(separator: "\n"))
        }
        return .ok(lines.joined(separator: "\n"))
    }
}

private struct URLSchemeView: View {
    let probe: URLSchemeProbe
    @State private var hooks = AppHooks.shared
    @State private var openResult: String?

    var body: some View {
        List {
            Section("Схемы из Info.plist (CFBundleURLTypes)") {
                let schemes = probe.registeredSchemes()
                if schemes.isEmpty {
                    Text("CFBundleURLTypes пуст").foregroundStyle(.secondary)
                } else {
                    ForEach(schemes, id: \.self) { scheme in
                        Text("\(scheme)://").font(.body.monospaced())
                    }
                }
            }

            Section("Самопроверка") {
                Button {
                    runSelfTest()
                } label: {
                    Label("Открыть scarletprobe://selftest", systemImage: "arrow.up.forward.app")
                }
                if let openResult {
                    Text(openResult).font(.footnote.monospaced()).textSelection(.enabled)
                }
                Text("После открытия приложение свернётся и вновь откроется по ссылке — должен появиться алерт.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Последняя открытая ссылка") {
                if let url = hooks.lastOpenedURL {
                    Text(url.absoluteString)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                } else {
                    Text("Ссылок ещё не приходило. Откройте scarletprobe://test из Safari или Заметок.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("URL-схема")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func runSelfTest() {
        guard let url = URL(string: "scarletprobe://selftest") else {
            openResult = "Не удалось собрать URL scarletprobe://selftest"
            return
        }
        let canOpen = UIApplication.shared.canOpenURL(url)
        Task {
            let success = await UIApplication.shared.open(url)
            openResult = "canOpenURL=\(canOpen), open success=\(success)"
            probe.log("Самопроверка scarletprobe://selftest: canOpen=\(canOpen), open=\(success)")
        }
    }
}

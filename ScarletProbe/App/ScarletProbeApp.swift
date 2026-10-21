import SwiftUI

@main
struct ScarletProbeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = ProbeStore()
    @State private var hooks = AppHooks.shared

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .onOpenURL { url in
                    ProbeLogger.shared.log("Открыта ссылка: \(url.absoluteString)")
                    hooks.lastOpenedURL = url
                    hooks.showURLAlert = true
                }
                .alert("Открыта ссылка", isPresented: $hooks.showURLAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(hooks.lastOpenedURL?.absoluteString ?? "")
                }
        }
    }
}

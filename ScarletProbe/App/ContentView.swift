import SwiftUI

struct ContentView: View {
    let store: ProbeStore

    var body: some View {
        NavigationStack {
            List(store.tests, id: \.id) { test in
                ProbeRow(test: test, result: store.result(for: test)) {
                    Task { await store.run(test) }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("ScarletProbe")
            .safeAreaInset(edge: .bottom) {
                BottomBar(store: store)
            }
        }
    }
}

private struct ProbeRow: View {
    let test: any ProbeTest
    let result: ProbeResult
    let onRun: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(test.id). \(test.title)")
                    .font(.headline)
                Spacer()
                Text(result.status.emoji)
                    .font(.title3)
                    .accessibilityLabel(result.status.label)
            }
            if !result.details.isEmpty {
                Text(result.details)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            HStack {
                Button(result.status == .running ? "Выполняется…" : "Запустить", action: onRun)
                    .buttonStyle(.borderedProminent)
                    .disabled(result.status == .running)
                if let detail = test.detailView {
                    NavigationLink("Открыть") {
                        detail.navigationTitle(test.title)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct BottomBar: View {
    let store: ProbeStore

    var body: some View {
        HStack(spacing: 12) {
            Button {
                Task { await store.runAll() }
            } label: {
                Label(store.isRunningAll ? "Выполняется…" : "Запустить все", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.isRunningAll)

            ShareLink(item: store.reportText) {
                Label("Экспорт лога", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
        .padding()
        .background(.bar)
    }
}

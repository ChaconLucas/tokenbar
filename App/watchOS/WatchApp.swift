import SwiftUI
import WidgetKit
import WatchConnectivity

@MainActor
final class WatchModel: NSObject, ObservableObject, WCSessionDelegate {
    @Published var snapshot = SharedStore.loadSnapshot() ?? .empty
    @Published var pairing = SharedStore.loadPairing()
    @Published var error: String?

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    /// Só com servidor: sem ele, quem traz os números é o iPhone.
    func refresh() async {
        guard let p = pairing, p.server != nil else { return }
        do {
            let s = try await API.fetch(p)
            snapshot = s
            SharedStore.saveSnapshot(s)
            error = nil
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// O iPhone manda o link de pareamento; vazio quer dizer que desapareou.
    private func apply(_ ctx: [String: Any]) {
        let p = (ctx["pairing"] as? String).flatMap(URL.init(string:)).flatMap(Pairing.init(link:))
        pairing = p
        SharedStore.savePairing(p)
        if p == nil {
            snapshot = .empty
            SharedStore.saveSnapshot(.empty)
        } else if let data = ctx["snapshot"] as? Data,
                  let s = try? JSONCoding.decoder.decode(UsageSnapshot.self, from: data),
                  s.updatedAt >= snapshot.updatedAt {
            // Números que o iPhone já buscou (Wi-Fi ou servidor).
            snapshot = s
            SharedStore.saveSnapshot(s)
            error = nil
        }
        WidgetCenter.shared.reloadAllTimelines()
        if p?.server != nil { Task { await refresh() } }
    }

    nonisolated func session(_ s: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let ctx = s.receivedApplicationContext
        if !ctx.isEmpty { Task { @MainActor in self.apply(ctx) } }
    }

    nonisolated func session(_ s: WCSession, didReceiveApplicationContext ctx: [String: Any]) {
        Task { @MainActor in self.apply(ctx) }
    }
}

@main
struct TokenBarWatchApp: App {
    @StateObject private var model = WatchModel()

    var body: some Scene {
        WindowGroup {
            WatchRootView().environmentObject(model)
        }
    }
}

struct WatchRootView: View {
    @EnvironmentObject var model: WatchModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if model.pairing == nil {
                    Text("Pareie no app TokenBar do iPhone.").font(.footnote).foregroundStyle(.secondary)
                }
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    DisplayStack(snapshot: model.snapshot, visible: Prefs.visible, windowChoice: Prefs.window,
                                 now: ctx.date, compact: true, spacing: 8)
                }
                if let e = model.error { Text(e).font(.footnote).foregroundStyle(.red) }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("TokenBar")
        .task {
            while !Task.isCancelled {
                await model.refresh()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }
}

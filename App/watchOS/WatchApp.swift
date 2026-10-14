import SwiftUI
import WidgetKit
import WatchConnectivity

@MainActor
final class WatchModel: NSObject, ObservableObject, WCSessionDelegate {
    @Published var snapshot = SharedStore.loadSnapshot() ?? .empty
    @Published var pairing = SharedStore.loadPairing()
    @Published var error: String?
    @Published var theme = Prefs.theme

    override init() {
        super.init()
        #if DEBUG
        // -TBPairLink tokenbar://pair?... pareia ao abrir (simulador sem iPhone).
        if let s = UserDefaults.standard.string(forKey: "TBPairLink"), let u = URL(string: s), let p = Pairing(link: u) {
            pairing = p
            SharedStore.savePairing(p)
        }
        if let a = UserDefaults.standard.string(forKey: "TBAgent") { TB.defaults.set(a, forKey: "watchAgent") }
        #endif
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
        // Cores escolhidas no iPhone.
        if let data = ctx["theme"] as? Data, let t = try? JSONDecoder().decode(Theme.self, from: data) {
            theme = t
            Prefs.theme = t
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
    /// "all", "claude" ou "codex".
    @State private var agent = TB.defaults.string(forKey: "watchAgent") ?? "all"
    @State private var windowChoice = Prefs.window == "long" ? "long" : "short"

    var body: some View {
        let theme = model.theme
        ScrollView {
            VStack(spacing: 6) {
                keys(theme)
                if model.pairing == nil {
                    Text("Pareie no app TokenBar do iPhone.").font(.footnote).foregroundStyle(.secondary)
                }
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    VStack(spacing: 6) {
                        ForEach(panels, id: \.key) { item in
                            WatchPanel(provider: model.snapshot.provider(item.id), providerID: item.id,
                                       window: item.window, now: ctx.date, theme: theme)
                                .onTapGesture { if agent == "all" { toggleWindow() } }
                        }
                    }
                }
                if let e = model.error { Text(e).font(.footnote).foregroundStyle(.red) }
            }
            .padding(.horizontal, 2)
        }
        .task {
            while !Task.isCancelled {
                await model.refresh()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    /// Todas as IAs na janela escolhida; ou uma IA só com o 5H e o 7D dela.
    private var panels: [(key: String, id: String, window: UsageWindow?)] {
        if agent == "all" {
            return Prefs.allProviders.map { id in
                (id, id, Prefs.pickFrom(model.snapshot.provider(id), windowChoice))
            }
        }
        let ws = model.snapshot.provider(agent)?.windows ?? []
        if ws.isEmpty { return [(agent, agent, nil)] }
        return ws.map { ("\(agent)-\($0.id)", agent, $0) }
    }

    private func keys(_ theme: Theme) -> some View {
        HStack(spacing: 4) {
            let label = agent == "all" ? "TODOS" : UsageStyle.shortName(agent)
            let color = agent == "all" ? Color.white : theme.base(agent)
            DotKey(text: label, on: true, color: color, dot: 1.6, round: theme.roundDots) {
                let order = ["all"] + Prefs.allProviders
                agent = order[((order.firstIndex(of: agent) ?? 0) + 1) % order.count]
                TB.defaults.set(agent, forKey: "watchAgent")
            }
            if agent == "all" {
                DotKey(text: windowChoice == "long" ? "7D" : "5H", on: true, color: theme.timer.color,
                       dot: 1.6, round: theme.roundDots, action: toggleWindow)
            }
            // O canto direito é do relógio do sistema.
            Spacer(minLength: 0)
        }
    }

    private func toggleWindow() {
        windowChoice = windowChoice == "long" ? "short" : "long"
        Prefs.window = windowChoice
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// Um painel do relógio: nome e reset pequenos em cima; janela e % grande embaixo; o fundo enche com o gasto.
struct WatchPanel: View {
    var provider: ProviderUsage?
    var providerID: String
    var window: UsageWindow?
    var now: Date
    var theme: Theme

    static let cols = 64, rows = 27

    var body: some View {
        let p = window?.used(at: now) ?? 0
        let level = theme.fill(providerID, percent: p)
        GeometryReader { geo in
            DotCanvas(bitmap: bitmap(p), dot: geo.size.width / CGFloat(Self.cols),
                      textColor: theme.text.color, fieldColor: level.opacity(0.62), offColor: level.opacity(0.10),
                      round: theme.roundDots)
                .shadow(color: level.opacity(0.35 * theme.glow), radius: 3 * theme.glow)
        }
        .aspectRatio(CGFloat(Self.cols) / CGFloat(Self.rows), contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("\(UsageStyle.shortName(providerID)) \(UsageStyle.percent(p))")
    }

    private func bitmap(_ p: Double) -> DotBitmap {
        let cols = Self.cols, rows = Self.rows
        var b = DotBitmap(cols: cols, rows: rows)
        let filled = Int((min(max(p, 0), 100) / 100 * Double(cols)).rounded())
        for x in 0..<filled { for y in 0..<rows { b.set(x, y, 1) } }

        b.draw(UsageStyle.shortName(providerID), x: 2, y: 2)
        let t = timeText
        b.draw(t, x: cols - 2 - DotFont.width(t), y: 2, value: 3)

        if let window {
            b.draw(window.label.uppercased(), x: 2, y: 17)
            let big = "\(min(Int(p.rounded()), 999))%"
            b.draw(big, x: cols - 2 - DotFont.width(big, scale: 2), y: 11, scale: 2)
        } else {
            b.drawCentered("SEM DADOS", y: 15)
        }
        return b
    }

    private var timeText: String {
        guard let w = window, let r = w.resetsAt else { return "" }
        if w.didReset(at: now) { return "OK" }
        let s = max(0, Int(r.timeIntervalSince(now)))
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        // Só os dias quando falta mais de um: cabe ao lado do nome sem encostar.
        return d > 0 ? "\(d)D" : "\(h):" + String(format: "%02d", m)
    }
}

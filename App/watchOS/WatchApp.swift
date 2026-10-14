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
    @State private var crown = 0.0

    var body: some View {
        let theme = model.theme
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                // Cada painel recebe a sua parte exata da altura livre: juntos ocupam a tela toda.
                GeometryReader { geo in
                    let items = panels
                    let gap: CGFloat = 6
                    let h = max(40, (geo.size.height - gap * CGFloat(items.count - 1)) / CGFloat(max(items.count, 1)))
                    VStack(spacing: gap) {
                        ForEach(items, id: \.key) { item in
                            WatchPanel(window: item.window, title: item.title, sub: item.sub, providerID: item.id,
                                       now: ctx.date, theme: theme)
                                .frame(height: h)
                                .onTapGesture { if agent == "all" { toggleWindow() } }
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if model.pairing == nil {
                            Text("Pareie no app TokenBar do iPhone.").font(.footnote).foregroundStyle(.secondary)
                        } else if let e = model.error {
                            Text(e).font(.footnote).foregroundStyle(.red)
                        }
                    }
                }
                .ignoresSafeArea(edges: .bottom)
            }
            // Coroa digital: girar troca TODOS → CLAUDE → CODEX.
            .focusable()
            .digitalCrownRotation($crown, from: 0, through: 1000, by: 1, sensitivity: .low,
                                  isContinuous: true, isHapticFeedbackEnabled: true)
            .onChange(of: crown) { _, v in
                let order = ["all"] + Prefs.allProviders
                let next = order[Int(v.rounded()) % order.count]
                if next != agent { agent = next; TB.defaults.set(agent, forKey: "watchAgent") }
            }
            // As teclas ficam na barra de cima, ao lado da hora: os painéis ganham a tela toda.
            .toolbar { ToolbarItem(placement: .topBarLeading) { keys(theme) } }
        }
        .task {
            while !Task.isCancelled {
                await model.refresh()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    /// Todas as IAs na janela escolhida (título = nome); ou uma IA só com o 5H e o 7D dela (título = janela).
    private var panels: [(key: String, id: String, window: UsageWindow?, title: String, sub: String?)] {
        if agent == "all" {
            return Prefs.allProviders.map { id in
                let w = Prefs.pickFrom(model.snapshot.provider(id), windowChoice)
                return (id, id, w, UsageStyle.shortName(id), w?.label.uppercased())
            }
        }
        let ws = model.snapshot.provider(agent)?.windows ?? []
        if ws.isEmpty { return [(agent, agent, nil, UsageStyle.shortName(agent), nil)] }
        return ws.map { ("\(agent)-\($0.id)", agent, $0, $0.label.uppercased(), nil) }
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
        }
    }

    private func toggleWindow() {
        windowChoice = windowChoice == "long" ? "short" : "long"
        Prefs.window = windowChoice
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// Um painel do relógio: título e reset pequenos em cima; % grande embaixo; o fundo enche com o gasto.
struct WatchPanel: View {
    var window: UsageWindow?
    var title: String
    var sub: String?
    var providerID: String
    var now: Date
    var theme: Theme

    static let cols = 64, rows = 22

    var body: some View {
        let p = window?.used(at: now) ?? 0
        let level = theme.fill(providerID, percent: p)
        GeometryReader { geo in
            // Estica até a altura disponível: mais linhas de pontos, conteúdo distribuído.
            let h = geo.size.height.isFinite ? geo.size.height : 0   // altura infinita em algumas medições
            // O ponto cabe na largura e na altura mínima; nunca transborda para o painel de baixo.
            let dot = max(1, min(geo.size.width / CGFloat(Self.cols), h > 0 ? h / CGFloat(Self.rows) : .infinity))
            let rows = min(200, max(Self.rows, Int(h / dot)))
            DotCanvas(bitmap: bitmap(p, rows: rows), dot: dot,
                      textColor: theme.text.color, fieldColor: level.opacity(0.62), offColor: level.opacity(0.10),
                      round: theme.roundDots)
                .shadow(color: level.opacity(0.35 * theme.glow), radius: 3 * theme.glow)
        }

        .accessibilityElement()
        .accessibilityLabel("\(title) \(UsageStyle.percent(p))")
    }

    private func bitmap(_ p: Double, rows: Int) -> DotBitmap {
        let cols = Self.cols
        var b = DotBitmap(cols: cols, rows: rows)
        let filled = Int((min(max(p, 0), 100) / 100 * Double(cols)).rounded())
        for x in 0..<filled { for y in 0..<rows { b.set(x, y, 1) } }

        b.draw(title, x: 2, y: 2)
        if window != nil {
            // Tempo embaixo à esquerda (apagado): nunca encosta no nome nem na %.
            b.draw(timeText, x: 2, y: rows - 9, value: 3)
            let big = "\(min(Int(p.rounded()), 999))%"
            // % grande à direita, centrada na altura que sobra abaixo do título.
            let scale = rows >= 34 ? 3 : 2
            let bigW = DotFont.width(big, scale: scale)
            let bigScale = bigW + 22 <= cols ? scale : 2
            b.draw(big, x: cols - 2 - DotFont.width(big, scale: bigScale),
                   y: 9 + max(0, (rows - 11 - 7 * bigScale) / 2), scale: bigScale)
        } else {
            b.drawCentered("SEM DADOS", y: rows / 2 - 3)
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

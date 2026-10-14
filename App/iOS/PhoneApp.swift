import SwiftUI
import WidgetKit
import WatchConnectivity

@MainActor
final class PhoneModel: NSObject, ObservableObject, WCSessionDelegate {
    @Published var snapshot = SharedStore.loadSnapshot() ?? .empty
    @Published var pairing = SharedStore.loadPairing()
    @Published var error: String?
    @Published var loading = false
    @Published var source: Source = .none

    enum Source { case none, lan, server }

    override init() {
        super.init()
        #if DEBUG
        // -TBPairLink tokenbar://pair?... pareia ao abrir (simulador, capturas de tela).
        if let s = UserDefaults.standard.string(forKey: "TBPairLink"), let u = URL(string: s), let p = Pairing(link: u) {
            pairing = p
            SharedStore.savePairing(p)
        }
        if let w = UserDefaults.standard.string(forKey: "TBWindow") { Prefs.window = w }
        #endif
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func pair(with url: URL) {
        guard url.host == "pair" else { return }   // tokenbar://open vem do widget: só abre o app
        guard let p = Pairing(link: url) else {
            error = "Link de pareamento inválido"
            return
        }
        pairing = p
        SharedStore.savePairing(p)
        sendPairingToWatch()
        Task { await refresh() }
    }

    func unpair() {
        pairing = nil
        SharedStore.savePairing(nil)
        snapshot = .empty
        SharedStore.saveSnapshot(.empty)
        sendPairingToWatch()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Wi-Fi local primeiro (direto do Mac); o servidor, se houver, em paralelo. Fica o número mais novo.
    func refresh() async {
        guard let p = pairing else { return }
        loading = true
        defer { loading = false }
        async let lan: UsageSnapshot? = try? LANClient.fetch(p)
        async let remote: Result<UsageSnapshot, Error>? = p.server == nil ? nil : await Self.result { try await API.fetch(p) }
        let (l, r) = await (lan, remote)
        let candidates = [l, try? r?.get()].compactMap { $0 }
        guard let best = candidates.max(by: { $0.updatedAt < $1.updatedAt }) else {
            // Nenhum caminho respondeu: mantém o último número e diz o porquê.
            if case .failure(let e)? = r { error = e.localizedDescription }
            else { error = LANClient.Failure.notFound.errorDescription }
            return
        }
        snapshot = best
        source = l.map { $0.updatedAt >= best.updatedAt } == true ? .lan : .server
        SharedStore.saveSnapshot(best)
        error = nil
        WidgetCenter.shared.reloadAllTimelines()
        sendToWatch()
    }

    private static func result<T>(_ f: () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await f()) } catch { return .failure(error) }
    }

    // MARK: Watch

    /// O relógio recebe a chave e os números prontos: funciona mesmo sem servidor.
    func sendToWatch() {
        guard WCSession.default.activationState == .activated else { return }
        var ctx: [String: Any] = [:]
        if let p = pairing { ctx["pairing"] = p.link.absoluteString }
        if let data = try? JSONCoding.encoder.encode(snapshot) { ctx["snapshot"] = data }
        try? WCSession.default.updateApplicationContext(ctx)
    }

    func sendPairingToWatch() { sendToWatch() }

    nonisolated func session(_ s: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.sendPairingToWatch() }
    }
    nonisolated func sessionDidBecomeInactive(_ s: WCSession) {}
    nonisolated func sessionDidDeactivate(_ s: WCSession) { WCSession.default.activate() }
}

@main
struct TokenBarPhoneApp: App {
    @StateObject private var model = PhoneModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            PhoneRootView()
                .environmentObject(model)
                .onOpenURL { model.pair(with: $0) }
                .onChange(of: phase) { _, p in
                    if p == .active { Task { await model.refresh() } }
                }
        }
    }
}

/// O celular vira o aparelho: deitado, tela cheia, tela sempre acesa.
struct PhoneRootView: View {
    @EnvironmentObject var model: PhoneModel
    @State private var visible = Prefs.visible
    @State private var windowChoice = Prefs.window
    @State private var showDetails = false
    @State private var theme = Prefs.theme

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()
            GeometryReader { geo in
                let side = max(geo.safeAreaInsets.leading, geo.safeAreaInsets.trailing)
                BusyDevice(snapshot: model.snapshot, visible: $visible, windowChoice: $windowChoice, theme: theme,
                           editableTheme: $theme, onMore: { showDetails = true }, fullBleed: true, sideSafeInset: side)
                    .ignoresSafeArea()
            }

            if let hint {
                Button { showDetails = true } label: {
                    Text(hint)
                        .font(Arcade.label(10)).tracking(1)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(.white.opacity(0.12)))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 10)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .sheet(isPresented: $showDetails) { PhoneDetails(theme: $theme).environmentObject(model) }
        .onChange(of: theme) { _, t in Prefs.theme = t; WidgetCenter.shared.reloadAllTimelines() }
        .onChange(of: visible) { _, v in Prefs.visible = v; WidgetCenter.shared.reloadAllTimelines() }
        .onChange(of: windowChoice) { _, v in Prefs.window = v; WidgetCenter.shared.reloadAllTimelines() }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .task {
            while !Task.isCancelled {
                await model.refresh()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    /// Aviso curto por cima do display quando falta algo; toca para resolver.
    /// Só erros: a falta de pareamento ou de dados o próprio letreiro de pontos já diz.
    private var hint: String? {
        guard model.pairing != nil, let e = model.error else { return nil }
        return e.uppercased()
    }
}

/// Ajustes e detalhes: fora do aparelho, numa folha.
struct PhoneDetails: View {
    @EnvironmentObject var model: PhoneModel
    @Binding var theme: Theme
    @Environment(\.dismiss) private var dismiss
    @State private var pasted = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if model.pairing == nil {
                    SectionTitle(text: "PAREAR COM O MAC")
                    ArcadePanel {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("No Mac, abra o TokenBar em Editar → Mais ajustes e aponte a câmera do iPhone para o QR.")
                                .font(.callout).foregroundStyle(Arcade.dim)
                            TextField("", text: $pasted, prompt: Text("ou cole o link tokenbar://…").foregroundStyle(Arcade.dim))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(Arcade.label(12))
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 8).fill(.black))
                            Button("PAREAR") {
                                if let u = URL(string: pasted) { model.pair(with: u); dismiss() }
                            }
                            .buttonStyle(ArcadeButtonStyle())
                            .disabled(pasted.isEmpty)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                SectionTitle(text: "DETALHES")
                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    VStack(spacing: 12) {
                        ForEach(model.snapshot.providers) { p in
                            ArcadePanel { ProviderCard(provider: p, now: ctx.date) }
                        }
                    }
                }
                if model.snapshot.updatedAt > .distantPast {
                    Text("MAC ENVIOU \(model.snapshot.updatedAt, style: .relative) ATRÁS")
                        .font(Arcade.label(9)).foregroundStyle(Arcade.dim)
                }
                if model.pairing != nil {
                    Button("DESPAREAR") { model.unpair(); dismiss() }
                        .buttonStyle(ArcadeButtonStyle(tint: Arcade.red))
                        .padding(.top, 8)
                }
            }
            .padding(16)
        }
        .background(ArcadeBackground())
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
    }
}

import SwiftUI
import WidgetKit
import CoreImage.CIFilterBuiltins

@MainActor
final class MacModel: ObservableObject {
    @Published var snapshot = SharedStore.loadSnapshot() ?? .empty
    @Published var serverText = SharedStore.loadPairing()?.server?.absoluteString ?? ""
    /// Sempre existe: a chave é criada na primeira abertura (o Wi-Fi local já funciona sem servidor).
    @Published var pairing: Pairing = MacModel.loadOrCreatePairing()
    @Published var lastPush: Date?
    @Published var pushError: String?
    @Published var claudeConnected = ClaudeHook.isInstalled
    @Published var claudeError: String?
    /// Ler o Claude pelo login (painel do VS Code). Desligado até a pessoa ligar.
    @Published var claudeLogin = UserDefaults.standard.bool(forKey: "claudeLogin") {
        didSet {
            UserDefaults.standard.set(claudeLogin, forKey: "claudeLogin")
            lastAccountFetch = nil
            if !claudeLogin { accountClaude = nil; claudeLoginError = nil }
            refresh()
        }
    }
    @Published var claudeLoginError: String?
    /// GitHub Copilot pela API do GitHub (usa o token do gh). Desligado até a pessoa ligar.
    @Published var copilotOn = UserDefaults.standard.bool(forKey: "copilotOn") {
        didSet {
            UserDefaults.standard.set(copilotOn, forKey: "copilotOn")
            lastCopilotFetch = nil
            if !copilotOn { copilot = nil; copilotError = nil }
            refresh()
        }
    }
    @Published var copilotError: String?
    /// Cursor pelo login do editor. Desligado até a pessoa ligar.
    @Published var cursorOn = UserDefaults.standard.bool(forKey: "cursorOn") {
        didSet {
            UserDefaults.standard.set(cursorOn, forKey: "cursorOn")
            forget(.cursor)
            refresh()
        }
    }
    /// IAs de chave de API: ligadas quando há chave no Keychain.
    @Published var connectorKeyed = Set(Connector.allCases.filter { $0.needsKey && ConnectorKeys.get($0.id) != nil }.map(\.id))
    @Published var connectorErrors: [String: String] = [:]
    private var connectorUsage: [String: ProviderUsage] = [:]
    private var connectorFetched: [String: Date] = [:]
    private var copilot: ProviderUsage?
    private var lastCopilotFetch: Date?
    private var accountClaude: ProviderUsage?
    private var lastAccountFetch: Date?
    @Published var visible = Prefs.visible {
        didSet { Prefs.visible = visible; WidgetCenter.shared.reloadAllTimelines() }
    }
    @Published var theme = Prefs.theme {
        didSet { Prefs.theme = theme; WidgetCenter.shared.reloadAllTimelines() }
    }
    @Published var windowChoice = Prefs.window {
        didSet { Prefs.window = windowChoice; WidgetCenter.shared.reloadAllTimelines() }
    }
    /// Ilha no notch: ligada por padrão nos Macs com notch.
    /// Onde a % aparece: "bar" (barra de menu), "notch" (ilha; a barra vira só um anel) ou "both".
    @Published var showIn = UserDefaults.standard.string(forKey: "showIn") ?? (NotchIsland.screenHasNotch ? "notch" : "bar") {
        didSet {
            UserDefaults.standard.set(showIn, forKey: "showIn")
            NotchIsland.shared.setEnabled(notchIsland)
        }
    }
    var notchIsland: Bool { showIn != "bar" }

    /// API local (http://localhost:41777/v1/usage). Ligada por padrão.
    @Published var apiEnabled = UserDefaults.standard.object(forKey: "localAPI") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(apiEnabled, forKey: "localAPI")
            LocalAPI.shared.setEnabled(apiEnabled)
        }
    }
    @Published var apiPort: UInt16?
    @Published var apiFailed = false

    private var timer: Timer?
    private var lastPushed: UsageSnapshot?
    let lan = LANServer()

    private static func loadOrCreatePairing() -> Pairing {
        if let p = SharedStore.loadPairing() { return p }
        let p = Pairing(server: nil, token: Pairing.newToken())
        SharedStore.savePairing(p)
        return p
    }

    init() {
        LocalAPI.shared.onState = { [weak self] port, failed in
            self?.apiPort = port
            self?.apiFailed = failed
        }
        refresh()
        LocalAPI.shared.setEnabled(apiEnabled)
        #if DEBUG
        // -TBWebhookTest YES: manda um evento "test" ao abrir (teste sem clicar).
        if UserDefaults.standard.bool(forKey: "TBWebhookTest") { Webhooks.shared.sendTest(snapshot: snapshot) }
        #endif
        Updater.shared.start()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor in self.refresh() }
        }
    }

    func refresh() {
        var fresh = Collector.collect()
        // Duas fontes do Claude: fica a mais nova (a statusline no terminal, o login no painel do VS Code).
        if let acc = accountClaude {
            if let i = fresh.providers.firstIndex(where: { $0.id == "claude" }) {
                if acc.observedAt > fresh.providers[i].observedAt { fresh.providers[i] = acc }
            } else {
                fresh.providers.insert(acc, at: 0)
            }
        }
        // Copilot logo depois das IAs da casa (Claude, Codex).
        if copilotOn, let c = copilot {
            fresh.providers.insert(c, at: fresh.providers.firstIndex { $0.id != "claude" && $0.id != "codex" } ?? fresh.providers.count)
        }
        if copilotOn, lastCopilotFetch.map({ Date.now.timeIntervalSince($0) > 300 }) ?? true {
            lastCopilotFetch = .now
            Task { await fetchCopilot() }
        }
        // Cursor, GLM, MiniMax, Kimi, OpenRouter, Droid: uma chamada a cada 5 min por IA; entre elas, o último número bom.
        for c in Connector.allCases where isOn(c) {
            fresh.providers.removeAll { $0.id == c.id }   // um arquivo em providers/ com o mesmo id repetiria
            if let u = connectorUsage[c.id] { fresh.providers.append(u) }
            if connectorFetched[c.id].map({ Date.now.timeIntervalSince($0) > 300 }) ?? true {
                connectorFetched[c.id] = .now
                Task { await fetchConnector(c) }
            }
        }
        // Pergunta à Anthropic no máximo a cada 5 minutos.
        if claudeLogin, lastAccountFetch.map({ Date.now.timeIntervalSince($0) > 300 }) ?? true {
            lastAccountFetch = .now
            Task { await fetchAccount() }
        }
        let changed = fresh.providers != snapshot.providers
        snapshot = fresh
        SharedStore.saveSnapshot(fresh)
        Collector.writeSnapshotFile(fresh)
        if changed {
            WidgetCenter.shared.reloadAllTimelines()
            if #available(iOS 18.0, macOS 26.0, *) { ControlCenter.shared.reloadAllControls() }
        }
        claudeConnected = ClaudeHook.isInstalled
        lan.publish(fresh, pairing: pairing)
        LocalAPI.shared.update(fresh)
        Webhooks.shared.check(fresh)
        Task { await push(force: false) }
    }

    /// Manda quando muda; fora isso, um sinal de vida a cada 10 min (o servidor gratuito tem cota de escrita).
    func push(force: Bool) async {
        let p = pairing
        guard p.server != nil, !snapshot.providers.isEmpty else { return }
        let stale = lastPush.map { Date.now.timeIntervalSince($0) > 600 } ?? true
        guard force || stale || lastPushed?.providers != snapshot.providers else { return }
        do {
            try await API.push(snapshot, p)
            lastPushed = snapshot
            lastPush = .now
            pushError = nil
        } catch {
            pushError = error.localizedDescription
        }
    }

    /// Campo vazio desliga o servidor (fica só o Wi-Fi local).
    func saveServer() {
        let trimmed = serverText.trimmingCharacters(in: .whitespacesAndNewlines)
        var url: URL?
        if !trimmed.isEmpty {
            guard let u = URL(string: trimmed), u.scheme?.hasPrefix("http") == true else {
                pushError = Lang.t("Endereço inválido")
                return
            }
            url = u
        }
        pushError = nil
        lastPush = nil
        let p = Pairing(server: url, token: pairing.token)
        pairing = p
        SharedStore.savePairing(p)
        Task { await push(force: true) }
    }

    private func fetchAccount() async {
        do {
            accountClaude = try await ClaudeAccount.fetch()
            claudeLoginError = nil
            refresh()
        } catch {
            claudeLoginError = error.localizedDescription
        }
    }

    /// Falhou: fica o último número bom e o erro aparece nos Ajustes.
    private func fetchCopilot() async {
        do {
            let got = try await Copilot.fetch()
            guard copilotOn else { return }
            copilot = got
            copilotError = nil
            refresh()
        } catch {
            if copilotOn { copilotError = error.localizedDescription }
        }
    }

    func isOn(_ c: Connector) -> Bool { c.needsKey ? connectorKeyed.contains(c.id) : cursorOn }

    /// Guarda (ou apaga, com nil) a chave e já tenta uma leitura. Droid com o campo vazio usa ~/.factory/.env.
    func setKey(_ c: Connector, _ key: String?) {
        var k = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        if k?.isEmpty == true { k = c == .factory ? Connector.factoryEnvKey() : nil }
        if key != nil, k == nil { connectorErrors[c.id] = Connector.Failure.noKey.localizedDescription; return }
        ConnectorKeys.set(c.id, k)
        if k == nil { connectorKeyed.remove(c.id) } else { connectorKeyed.insert(c.id) }
        forget(c)
        refresh()
    }

    private func forget(_ c: Connector) {
        connectorUsage[c.id] = nil
        connectorFetched[c.id] = nil
        connectorErrors[c.id] = nil
    }

    /// Falhou: fica o último número bom e o erro aparece nos Ajustes.
    private func fetchConnector(_ c: Connector) async {
        let key = c.needsKey ? ConnectorKeys.get(c.id) : nil
        do {
            let got = try await c.fetch(key: key)
            guard isOn(c) else { return }
            connectorUsage[c.id] = got
            connectorErrors[c.id] = nil
            refresh()
        } catch {
            if isOn(c) { connectorErrors[c.id] = error.localizedDescription }
        }
    }

    func disconnectClaude() {
        do {
            try ClaudeHook.uninstall()
            claudeError = nil
        } catch {
            claudeError = error.localizedDescription
        }
        refresh()
    }

    /// Chave nova: todo celular/relógio pareado perde o acesso até escanear o QR de novo.
    func resetPairing() {
        let p = Pairing(server: pairing.server, token: Pairing.newToken())
        pairing = p
        SharedStore.savePairing(p)
        lastPush = nil
        refresh()
    }

    func connectClaude() {
        do {
            try ClaudeHook.install()
            claudeConnected = true
            claudeError = nil
        } catch {
            claudeError = error.localizedDescription
        }
    }

    /// Mini barras de LED da barra de menu (refeitas quando muda o número, a IA visível ou a cor).
    var menuImage: NSImage {
        showIn == "notch"
            ? MenuBarImage.ring(snapshot: snapshot, visible: visible, windowChoice: windowChoice, theme: theme)
            : MenuBarImage.make(snapshot: snapshot, visible: visible, windowChoice: windowChoice, theme: theme)
    }

    /// Texto curto: "C 32% · X 54%".
    var menuTitle: String {
        let parts = snapshot.providers.filter { visible.contains($0.id) }.compactMap { p -> String? in
            guard let w = Prefs.pick(p) else { return nil }
            return "\(UsageStyle.abbr(p.id)) \(UsageStyle.percent(w.used()))"
        }
        return parts.isEmpty ? "TokenBar" : parts.joined(separator: " · ")
    }
}

/// Clicar no ícone do Dock sem janela aberta traz a janela de volta.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var openMain: (() -> Void)?

    /// ⌘H (Esconder) fecha o aparelho e o flutuante: senão, abrir o resumo da barra traz tudo de volta.
    func applicationDidHide(_ notification: Notification) {
        for w in NSApp.windows where w.identifier?.rawValue.hasPrefix("main") == true { w.close() }
        Task { @MainActor in MiniPanel.shared.close() }
        NSApp.unhideWithoutActivation()
    }

    /// Toque no controle da Central de Controle: abre o flutuante.
    func applicationDidBecomeActive(_ notification: Notification) {
        guard let target = TB.defaults.string(forKey: "openRequest") else { return }
        TB.defaults.removeObject(forKey: "openRequest")
        if target == "main" { openMain?() } else { openMini?() }
    }
    var openMini: (() -> Void)?

    private var termSignal: DispatchSourceSignal?

    /// `kill` (SIGTERM) também sai pelo caminho normal, para o api.json não ficar para trás.
    func applicationDidFinishLaunching(_ notification: Notification) {
        signal(SIGTERM, SIG_IGN)
        let s = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        s.setEventHandler { NSApp.terminate(nil) }
        s.resume()
        termSignal = s
    }

    /// Sai do app: a API local para e o ~/.tokenbar/api.json some.
    func applicationWillTerminate(_ notification: Notification) {
        LocalAPI.shared.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { openMain?() }
        return true
    }
}

@main
struct TokenBarMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = MacModel()

    var body: some Scene {
        // A janela é o aparelho: sem moldura, arrastável, sempre na frente.
        Window("TokenBar", id: "main") {
            DeviceWindow().environmentObject(model)
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        .defaultSize(width: 620, height: 226)

        Window(Lang.t("Ajustes do TokenBar"), id: "settings") {
            SettingsView().environmentObject(model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        Window(Lang.t("Primeiros passos"), id: "setup") {
            SetupGuide().environmentObject(model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuContent().environmentObject(model)
        } label: {
            MenuLabel(image: model.menuImage, delegate: delegate, model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

/// O rótulo da barra de menu existe desde o lançamento: daqui a janela abre ao iniciar.
struct MenuLabel: View {
    @MainActor static var launched = false
    var image: NSImage
    var delegate: AppDelegate
    var model: MacModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: image)
            .onAppear {
                delegate.openMain = { openWindow(id: "main"); NSApp.activate() }
                delegate.openMini = { MiniPanel.shared.show(model: model, openMain: { openWindow(id: "main"); NSApp.activate() }) }
                // Só na abertura do app: o rótulo da barra reaparece a cada clique, e isso não pode reabrir janela.
                guard !MenuLabel.launched else { return }
                MenuLabel.launched = true
                NotchIsland.shared.openSettings = { openWindow(id: "settings"); NSApp.activate() }
                NotchIsland.shared.start(model: model, openMain: { openWindow(id: "main"); NSApp.activate() })
                // Abre um só: o flutuante, se era ele que estava aberto; senão, o aparelho grande.
                if UserDefaults.standard.bool(forKey: "miniOpen") || UserDefaults.standard.bool(forKey: "TBMini") {
                    MiniPanel.shared.show(model: model, openMain: { openWindow(id: "main"); NSApp.activate() })
                    DispatchQueue.main.async {
                        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true }?.close()
                    }
                } else {
                    delegate.openMain?()
                }
                #if DEBUG
                // -TBMenuPreview YES: o resumo da barra numa janela (capturas de tela sem clicar na barra).
                if UserDefaults.standard.bool(forKey: "TBMenuPreview") {
                    let w = NSWindow(contentRect: NSRect(x: 200, y: 300, width: 424, height: 240),
                                     styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
                    w.title = "MenuPreview"
                    w.titlebarAppearsTransparent = true
                    w.contentView = NSHostingView(rootView: MenuContent().environmentObject(model))
                    w.makeKeyAndOrderFront(nil)
                }
                // -TBOpenSettings YES: abre os Ajustes direto (capturas de tela).
                if UserDefaults.standard.bool(forKey: "TBOpenSettings") {
                    DispatchQueue.main.async { openWindow(id: "settings") }
                }
                #endif
                // Primeira vez: o guia abre junto, por cima do aparelho.
                if !UserDefaults.standard.bool(forKey: "setupDone") {
                    DispatchQueue.main.async { openWindow(id: "setup"); NSApp.activate() }
                }
            }
    }
}

struct MenuContent: View {
    @EnvironmentObject var model: MacModel
    @ObservedObject private var updater = Updater.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 12) {
            // O aparelho precisa de altura fixa: dentro do menu ele não tem de onde tirar o tamanho.
            BusyDevice(snapshot: model.snapshot, visible: $model.visible, windowChoice: $model.windowChoice,
                       theme: model.theme, liquidGlass: true)
                .frame(width: 400, height: 150)
            if #available(macOS 26.0, *) {
                glassRow
            } else {
                classicRow
            }
            if let e = updater.error { Text(e).font(.caption).foregroundStyle(Arcade.red) }
        }
        .padding(12)
        .frame(width: 424)
        .modifier(MenuBackground())
        .environment(\.colorScheme, .dark)
    }

    private func openMain() { openWindow(id: "main"); NSApp.activate() }
    private func openMini() { MiniPanel.shared.show(model: model, openMain: { openWindow(id: "main"); NSApp.activate() }) }

    /// Bolhas de vidro líquido: perto umas das outras, se fundem e deformam ao passar e apertar.
    @available(macOS 26.0, *)
    private var glassRow: some View {
        HStack(spacing: 8) {
            GlassEffectContainer(spacing: 14) {
                HStack(spacing: 6) {
                    bubble("rectangle.inset.filled", Lang.t("Aparelho"), action: openMain)
                    bubble("pip", "Mini", action: openMini)
                    bubble("gearshape", Lang.t("Ajustes")) { openWindow(id: "settings"); NSApp.activate() }
                    bubble("questionmark", Lang.t("Guia: primeiros passos")) { openWindow(id: "setup"); NSApp.activate() }
                }
            }
            Spacer(minLength: 0)
            if let v = updater.available {
                Button { updater.install() } label: {
                    Label(updater.busy ? Lang.t("Atualizando…") : v, systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.glassProminent)
                .tint(.green)
                .controlSize(.large)
                .disabled(updater.busy)
                .help(Lang.f("Atualizar para a versão %@", v))
            }
            GlassEffectContainer(spacing: 14) {
                HStack(spacing: 6) {
                    bubble("arrow.clockwise", Lang.t("Atualizar")) { model.refresh() }
                    bubble("power", Lang.t("Sair do TokenBar")) { NSApp.terminate(nil) }
                }
            }
        }
    }

    @available(macOS 26.0, *)
    private func bubble(_ icon: String, _ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 40, height: 40)
                .contentShape(Circle())
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
    }

    /// Antes do macOS 26: os botões de fliperama.
    private var classicRow: some View {
        HStack(spacing: 6) {
            Button(Lang.t("Aparelho"), action: openMain).buttonStyle(ArcadeButtonStyle())
            Button("Mini", action: openMini).buttonStyle(ArcadeButtonStyle())
            Button(Lang.t("Ajustes")) { openWindow(id: "settings"); NSApp.activate() }.buttonStyle(ArcadeButtonStyle())
            Spacer(minLength: 4)
            if let v = updater.available {
                Button(v) { updater.install() }.buttonStyle(ArcadeButtonStyle(tint: Arcade.green)).disabled(updater.busy)
            }
            Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(ArcadeButtonStyle())
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.buttonStyle(ArcadeButtonStyle())
        }
    }
}

/// Fundo do resumo: o vidro do próprio menu (macOS 26) ou preto nos anteriores.
private struct MenuBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) { content } else { content.background(Color.black) }
    }
}


/// A janela principal: só o aparelho. Botão direito abre as opções; ⌘+ e ⌘− mudam o tamanho.
struct DeviceWindow: View {
    @EnvironmentObject var model: MacModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage("deviceWidth") private var width: Double = 620
    @State private var fullScreen = false
    @AppStorage("alwaysOnTop") private var alwaysOnTop = false

    private static let aspect = 2.75

    var body: some View {
        let screen = NSScreen.main?.frame.size ?? CGSize(width: 1440, height: 900)
        let size = fullScreen ? screen : CGSize(width: width, height: width / Self.aspect)
        BusyDevice(snapshot: model.snapshot, visible: $model.visible, windowChoice: $model.windowChoice,
                   theme: model.theme, editableTheme: $model.theme, onMore: openSettings,
                   swapKey: ("FLUTUAR", {
                       MiniPanel.shared.show(model: model, openMain: { openWindow(id: "main"); NSApp.activate() })
                       dismissWindow(id: "main")
                   }),
                   windowControls: (minimize: { mainWindow?.miniaturize(nil) }, close: { dismissWindow(id: "main") }))
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .bottom) { claudeHint.padding(.bottom, 14) }
        .environment(\.colorScheme, .dark)
            .contextMenu {
                Button(Lang.t("Ajustes…"), action: openSettings)
                Button(Lang.t("Primeiros passos…")) { openWindow(id: "setup"); NSApp.activate() }
                Button(Lang.t("Atualizar agora")) { model.refresh() }
                Divider()
                Button(Lang.t("Maior")) { resize(1.15) }.keyboardShortcut("+")
                Button(Lang.t("Menor")) { resize(1 / 1.15) }.keyboardShortcut("-")
                Button(Lang.t("Abrir Mini (flutuante)")) { MiniPanel.shared.show(model: model, openMain: { openWindow(id: "main"); NSApp.activate() }) }
                Toggle(Lang.t("Flutuar (sempre na frente, em todas as mesas)"), isOn: $alwaysOnTop)
                Button(fullScreen ? Lang.t("Sair da tela cheia") : Lang.t("Tela cheia")) { toggleFullScreen() }.keyboardShortcut("f", modifiers: [.command, .control])
                Divider()
                Button(Lang.t("Fechar aparelho")) { dismissWindow(id: "main") }
                Button(Lang.t("Sair do TokenBar")) { NSApp.terminate(nil) }
            }
            .onAppear { applyLevel() }
            .onChange(of: alwaysOnTop) { applyLevel() }
            .background {
                // Atalhos funcionam mesmo sem abrir o menu.
                Group {
                    Button("") { resize(1.15) }.keyboardShortcut("+")
                    Button("") { resize(1.15) }.keyboardShortcut("=")
                    Button("") { resize(1 / 1.15) }.keyboardShortcut("-")
                    Button("") { toggleFullScreen() }.keyboardShortcut("f", modifiers: [.command, .control])
                    Button("") { if fullScreen { toggleFullScreen() } }.keyboardShortcut(.escape, modifiers: [])
                }
                .opacity(0)
            }
    }

    private func openSettings() {
        openWindow(id: "settings")
        NSApp.activate()
    }

    @AppStorage("hintClaudeOff") private var hintOff = false

    /// Claude instalado mas sem números (o painel do VS Code não roda a statusline): oferece ler pelo login.
    @ViewBuilder private var claudeHint: some View {
        let installed = FileManager.default.fileExists(atPath: Collector.home.appending(path: ".claude").path)
        if installed, !hintOff, model.snapshot.provider("claude") == nil {
            HStack(spacing: 10) {
                Text(model.claudeLogin ? (model.claudeLoginError ?? Lang.t("Lendo pelo login…")) : Lang.t("Claude sem números. Usa no painel do VS Code?"))
                    .font(.system(size: 12)).foregroundStyle(.white).lineLimit(1)
                if !model.claudeLogin {
                    Button(Lang.t("LIGAR")) { model.claudeLogin = true }.buttonStyle(ArcadeButtonStyle(tint: Art.claude))
                }
                Button { hintOff = true } label: { Image(systemName: "xmark").foregroundStyle(.white.opacity(0.5)) }.buttonStyle(.plain)
            }
            .padding(.leading, 14).padding(.trailing, 10).padding(.vertical, 6)
            .background(Capsule().fill(.black.opacity(0.92)).overlay(Capsule().strokeBorder(Art.claude.opacity(0.5))))
        }
    }

    private var mainWindow: NSWindow? { NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true } }

    /// Janela normal por padrão; "Sempre na frente" é escolha da pessoa.
    private func applyLevel() {
        DispatchQueue.main.async {
            // Flutuar = sempre na frente + vai junto para todas as mesas (e por cima de apps em tela cheia).
            guard let w = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true }) else { return }
            w.level = alwaysOnTop ? .floating : .normal
            // Arrastar o display troca de IA; a janela não pode ir junto (senão o arrasto mede zero).
            w.isMovableByWindowBackground = false
            w.isMovable = true
            w.collectionBehavior = alwaysOnTop ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.managed]
            w.hidesOnDeactivate = false
            // Sem moldura, mas minimizável pela tecla —.
            w.styleMask.insert(.miniaturizable)
        }
    }

    private func resize(_ factor: Double) {
        guard !fullScreen else { return }
        width = min(max(width * factor, 360), 2400)
    }

    private func toggleFullScreen() {
        fullScreen.toggle()
        // A janela segue o tamanho do conteúdo; em tela cheia ela também vai para o canto.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let win = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true }),
                  let screen = win.screen ?? NSScreen.main else { return }
            if fullScreen {
                win.setFrameOrigin(screen.frame.origin)
                win.level = .screenSaver
            } else {
                win.center()
                applyLevel()
            }
        }
    }
}


struct QRCode: View {
    var text: String

    var body: some View {
        if let image = Self.make(text) {
            Image(nsImage: image).interpolation(.none).resizable().scaledToFit()
        }
    }

    static func make(_ text: String) -> NSImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage?.transformed(by: .init(scaleX: 10, y: 10)) else { return nil }
        let rep = NSCIImageRep(ciImage: out)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }
}


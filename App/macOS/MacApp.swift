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
        refresh()
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
        // Pergunta à Anthropic no máximo a cada 5 minutos.
        if claudeLogin, lastAccountFetch.map({ Date.now.timeIntervalSince($0) > 300 }) ?? true {
            lastAccountFetch = .now
            Task { await fetchAccount() }
        }
        let changed = fresh.providers != snapshot.providers
        snapshot = fresh
        SharedStore.saveSnapshot(fresh)
        if changed {
            WidgetCenter.shared.reloadAllTimelines()
            if #available(iOS 18.0, macOS 26.0, *) { ControlCenter.shared.reloadAllControls() }
        }
        claudeConnected = ClaudeHook.isInstalled
        lan.publish(fresh, pairing: pairing)
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
        MenuBarImage.make(snapshot: snapshot, visible: visible, windowChoice: windowChoice, theme: theme)
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
            MacMainView().environmentObject(model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 520, height: 760)

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
                // Abre um só: o flutuante, se era ele que estava aberto; senão, o aparelho grande.
                if UserDefaults.standard.bool(forKey: "miniOpen") || UserDefaults.standard.bool(forKey: "TBMini") {
                    MiniPanel.shared.show(model: model, openMain: { openWindow(id: "main"); NSApp.activate() })
                    DispatchQueue.main.async {
                        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true }?.close()
                    }
                } else {
                    delegate.openMain?()
                }
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
        VStack(spacing: 10) {
            if let v = updater.available {
                menuButton(updater.busy ? Lang.t("Atualizando…") : Lang.f("Atualizar para a versão %@", v), "arrow.down.circle") { updater.install() }
                    .disabled(updater.busy)
                if let e = updater.error { Text(e).font(.caption).foregroundStyle(Arcade.red) }
            }
            // O aparelho precisa de altura fixa: dentro do menu ele não tem de onde tirar o tamanho.
            BusyDevice(snapshot: model.snapshot, visible: $model.visible, windowChoice: $model.windowChoice,
                       theme: model.theme, liquidGlass: true)
                .frame(width: 400, height: 150)
            HStack(spacing: 6) {
                menuButton(Lang.t("Aparelho"), "rectangle.inset.filled") { openWindow(id: "main"); NSApp.activate() }
                menuButton("Mini", "pip") { MiniPanel.shared.show(model: model, openMain: { openWindow(id: "main"); NSApp.activate() }) }
                menuButton(Lang.t("Ajustes"), "gearshape") { openWindow(id: "settings"); NSApp.activate() }
                Spacer(minLength: 4)
                menuButton(nil, "questionmark") { openWindow(id: "setup"); NSApp.activate() }.help(Lang.t("Guia: primeiros passos"))
                menuButton(nil, "arrow.clockwise") { model.refresh() }.help(Lang.t("Atualizar"))
                menuButton(nil, "power") { NSApp.terminate(nil) }.help(Lang.t("Sair do TokenBar"))
            }
        }
        .padding(12)
        .frame(width: 424)
        .modifier(MenuBackground())
        .environment(\.colorScheme, .dark)
    }

    /// Botão de vidro do sistema (macOS 26); antes disso, o botão de fliperama.
    @ViewBuilder
    private func menuButton(_ title: String?, _ icon: String, action: @escaping () -> Void) -> some View {
        let label = Group {
            if let title { Label(title, systemImage: icon) } else { Image(systemName: icon) }
        }
        if #available(macOS 26.0, *) {
            Button(action: action) { label.padding(.horizontal, 2) }
                .buttonStyle(.glass)
                .controlSize(.large)
        } else {
            Button(action: action) { label }.buttonStyle(ArcadeButtonStyle())
        }
    }
}

/// Fundo do resumo: o vidro do próprio menu (macOS 26) ou preto nos anteriores.
private struct MenuBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) { content } else { content.background(Color.black) }
    }
}

struct UsageList: View {
    var snapshot: UsageSnapshot

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            VStack(alignment: .leading, spacing: 12) {
                if snapshot.providers.isEmpty {
                    ArcadePanel {
                        Text(Lang.t("SEM SINAL. CONECTE O CLAUDE CODE OU USE O CODEX UMA VEZ."))
                            .font(Arcade.label(11)).foregroundStyle(Arcade.dim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                ForEach(snapshot.providers) { p in
                    ArcadePanel { ProviderCard(provider: p, now: ctx.date) }
                }
            }
        }
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
                   }))
            .frame(width: size.width, height: size.height)
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

struct MacMainView: View {
    @EnvironmentObject var model: MacModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("TOKENBAR").font(Arcade.digits(22)).tracking(4).foregroundStyle(.white)
                        .shadow(color: Arcade.cyan.opacity(0.6), radius: 8)
                    Spacer()
                    Text("1UP").font(Arcade.label(11)).foregroundStyle(Arcade.amber)
                        .shadow(color: Arcade.amber, radius: 4)
                }
                LangPicker()
                Button(Lang.t("PRIMEIROS PASSOS: CONECTAR TUDO")) { openWindow(id: "setup") }
                    .buttonStyle(ArcadeButtonStyle(tint: Arcade.amber))
                VersionRow()
                SectionTitle(text: Lang.t("APARÊNCIA"))
                ArcadePanel {
                    ThemeEditor(theme: $model.theme).frame(maxWidth: .infinity, alignment: .leading)
                }

                SectionTitle(text: Lang.t("DETALHES"))
                UsageList(snapshot: model.snapshot)

                SectionTitle(text: "CLAUDE CODE")
                ArcadePanel {
                    VStack(alignment: .leading, spacing: 8) {
                        if model.claudeConnected {
                            Label(Lang.t("CONECTADO PELA STATUSLINE"), systemImage: "checkmark.circle.fill")
                                .font(Arcade.label(11)).foregroundStyle(Arcade.green)
                            Text(Lang.t("Os números chegam enquanto alguma sessão do Claude Code estiver aberta."))
                                .font(.caption).foregroundStyle(Arcade.dim)
                        } else {
                            Text(Lang.t("O Claude Code só entrega os limites para a statusline. O TokenBar passa a ler essa cópia e mantém a sua statusline atual."))
                                .font(.caption).foregroundStyle(Arcade.dim)
                            Button(Lang.t("CONECTAR CLAUDE CODE")) { model.connectClaude() }.buttonStyle(ArcadeButtonStyle())
                        }
                        if let e = model.claudeError { Text(e).foregroundStyle(Arcade.red).font(.caption) }
                        Divider().overlay(.white.opacity(0.1))
                        Toggle(Lang.t("Ler pelo login do Claude Code (para quem usa o painel do VS Code)"), isOn: $model.claudeLogin)
                            .font(.caption).foregroundStyle(.white)
                        Text(Lang.t("Usa a chave que o Claude Code já guardou; ela só vai para a Anthropic e não sai deste Mac. Na primeira vez, o macOS pergunta: responda Permitir sempre."))
                            .font(.caption2).foregroundStyle(Arcade.dim)
                        if let e = model.claudeLoginError { Text(e).foregroundStyle(Arcade.red).font(.caption) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                SectionTitle(text: Lang.t("CELULAR E RELÓGIO"))
                ArcadePanel {
                    let p = model.pairing
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 14) {
                            QRCode(text: p.link.absoluteString)
                                .frame(width: 140, height: 140)
                                .padding(6).background(.white, in: RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 8) {
                                Text(Lang.t("Aponte a câmera do iPhone para o código. O Watch recebe pelo iPhone."))
                                    .font(.caption).foregroundStyle(.white)
                                Text(p.server == nil
                                     ? Lang.t("Modo Wi-Fi: o iPhone lê direto deste Mac quando estão na mesma rede.")
                                     : Lang.t("Wi-Fi + servidor: na mesma rede lê direto; fora dela, pelo servidor."))
                                    .font(.caption2).foregroundStyle(Arcade.dim)
                                Button(Lang.t("COPIAR LINK")) {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(p.link.absoluteString, forType: .string)
                                }
                                .buttonStyle(ArcadeButtonStyle())
                            }
                        }
                        Text(Lang.t("Quem tem o código vê os seus números. Não publique."))
                            .font(.caption2).foregroundStyle(Arcade.dim)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                SectionTitle(text: Lang.t("RELÓGIO SEM CELULAR (WEAR OS)"))
                ArcadePanel {
                    TimelineView(.periodic(from: .now, by: 5)) { _ in
                        HStack(spacing: 16) {
                            Text(model.lan.currentCode())
                                .font(Arcade.digits(30)).tracking(6).foregroundStyle(.white)
                            Text(Lang.t("No relógio, abra o TokenBar e digite este código (mesmo Wi-Fi). Vale uma vez e troca a cada 10 min."))
                                .font(.caption).foregroundStyle(Arcade.dim)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                SectionTitle(text: Lang.t("SERVIDOR (OPCIONAL)"))
                ArcadePanel {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(Lang.t("Para ver fora de casa. Suba o seu (grátis, Cloudflare): veja o README. Deixe vazio para usar só o Wi-Fi."))
                            .font(.caption).foregroundStyle(Arcade.dim)
                        TextField("", text: $model.serverText, prompt: Text(Lang.t("https://tokenbar.sua-conta.workers.dev")).foregroundStyle(Arcade.dim))
                            .textFieldStyle(.plain)
                            .font(Arcade.label(12))
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 6).fill(.black).overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.1))))
                        HStack {
                            Button(Lang.t("SALVAR")) { model.saveServer() }.buttonStyle(ArcadeButtonStyle())
                            if let t = model.lastPush {
                                (Lang.isEN ? Text("SENT \(t, style: .relative) AGO") : Text("ENVIADO \(t, style: .relative) ATRÁS")).font(Arcade.label(9)).foregroundStyle(Arcade.dim)
                            }
                        }
                        if let e = model.pushError { Text(e).font(.caption2).foregroundStyle(Arcade.red) }
                        Text(Lang.t("Mudou o servidor? Escaneie o QR de novo no iPhone."))
                            .font(.caption2).foregroundStyle(Arcade.dim)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(18)
            .padding(.top, 14)
        }
        .scrollIndicators(.never)
        .background(ArcadeBackground())
        .environment(\.colorScheme, .dark)
        .environment(\.locale, Lang.locale)
        .frame(minWidth: 460, minHeight: 500)
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

/// Versão instalada e, se houver, o botão da nova.
struct VersionRow: View {
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        HStack(spacing: 10) {
            Text(Lang.f("VERSÃO %@", Updater.current)).font(Arcade.label(10)).foregroundStyle(Arcade.dim)
            if let v = updater.available {
                Button(updater.busy ? Lang.t("ATUALIZANDO…") : Lang.f("ATUALIZAR PARA %@", v)) { updater.install() }
                    .buttonStyle(ArcadeButtonStyle(tint: Arcade.green)).disabled(updater.busy)
            } else {
                Button(Lang.t("BUSCAR ATUALIZAÇÃO")) { Task { await updater.check() } }
                    .buttonStyle(ArcadeButtonStyle(tint: Arcade.dim))
            }
            if let e = updater.error { Text(e).font(.caption2).foregroundStyle(Arcade.red) }
        }
    }
}

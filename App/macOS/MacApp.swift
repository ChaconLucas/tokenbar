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
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor in self.refresh() }
        }
    }

    func refresh() {
        let fresh = Collector.collect()
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
                pushError = "Endereço inválido"
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

        Window("Ajustes do TokenBar", id: "settings") {
            MacMainView().environmentObject(model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 520, height: 760)

        Window("Primeiros passos", id: "setup") {
            SetupGuide().environmentObject(model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 560, height: 780)

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
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 10) {
            // O aparelho precisa de altura fixa: dentro do menu ele não tem de onde tirar o tamanho.
            BusyDevice(snapshot: model.snapshot, visible: $model.visible, windowChoice: $model.windowChoice,
                       theme: model.theme, liquidGlass: true)
                .frame(width: 400, height: 150)
            HStack(spacing: 6) {
                menuButton("Aparelho", "rectangle.inset.filled") { openWindow(id: "main"); NSApp.activate() }
                menuButton("Mini", "pip") { MiniPanel.shared.show(model: model, openMain: { openWindow(id: "main"); NSApp.activate() }) }
                menuButton("Ajustes", "gearshape") { openWindow(id: "settings"); NSApp.activate() }
                Spacer(minLength: 4)
                menuButton(nil, "questionmark") { openWindow(id: "setup"); NSApp.activate() }.help("Guia: primeiros passos")
                menuButton(nil, "arrow.clockwise") { model.refresh() }.help("Atualizar")
                menuButton(nil, "power") { NSApp.terminate(nil) }.help("Sair do TokenBar")
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
                        Text("SEM SINAL. CONECTE O CLAUDE CODE OU USE O CODEX UMA VEZ.")
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
                Button("Ajustes…", action: openSettings)
                Button("Primeiros passos…") { openWindow(id: "setup"); NSApp.activate() }
                Button("Atualizar agora") { model.refresh() }
                Divider()
                Button("Maior") { resize(1.15) }.keyboardShortcut("+")
                Button("Menor") { resize(1 / 1.15) }.keyboardShortcut("-")
                Button("Abrir Mini (flutuante)") { MiniPanel.shared.show(model: model, openMain: { openWindow(id: "main"); NSApp.activate() }) }
                Toggle("Flutuar (sempre na frente, em todas as mesas)", isOn: $alwaysOnTop)
                Button(fullScreen ? "Sair da tela cheia" : "Tela cheia") { toggleFullScreen() }.keyboardShortcut("f", modifiers: [.command, .control])
                Divider()
                Button("Fechar aparelho") { dismissWindow(id: "main") }
                Button("Sair do TokenBar") { NSApp.terminate(nil) }
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
                Button("PRIMEIROS PASSOS: CONECTAR TUDO") { openWindow(id: "setup") }
                    .buttonStyle(ArcadeButtonStyle(tint: Arcade.amber))
                SectionTitle(text: "APARÊNCIA")
                ArcadePanel {
                    ThemeEditor(theme: $model.theme).frame(maxWidth: .infinity, alignment: .leading)
                }

                SectionTitle(text: "DETALHES")
                UsageList(snapshot: model.snapshot)

                SectionTitle(text: "CLAUDE CODE")
                ArcadePanel {
                    VStack(alignment: .leading, spacing: 8) {
                        if model.claudeConnected {
                            Label("CONECTADO PELA STATUSLINE", systemImage: "checkmark.circle.fill")
                                .font(Arcade.label(11)).foregroundStyle(Arcade.green)
                            Text("Os números chegam enquanto alguma sessão do Claude Code estiver aberta.")
                                .font(.caption).foregroundStyle(Arcade.dim)
                        } else {
                            Text("O Claude Code só entrega os limites para a statusline. O TokenBar passa a ler essa cópia e mantém a sua statusline atual.")
                                .font(.caption).foregroundStyle(Arcade.dim)
                            Button("CONECTAR CLAUDE CODE") { model.connectClaude() }.buttonStyle(ArcadeButtonStyle())
                        }
                        if let e = model.claudeError { Text(e).foregroundStyle(Arcade.red).font(.caption) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                SectionTitle(text: "CELULAR E RELÓGIO")
                ArcadePanel {
                    let p = model.pairing
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 14) {
                            QRCode(text: p.link.absoluteString)
                                .frame(width: 140, height: 140)
                                .padding(6).background(.white, in: RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Aponte a câmera do iPhone para o código. O Watch recebe pelo iPhone.")
                                    .font(.caption).foregroundStyle(.white)
                                Text(p.server == nil
                                     ? "Modo Wi-Fi: o iPhone lê direto deste Mac quando estão na mesma rede."
                                     : "Wi-Fi + servidor: na mesma rede lê direto; fora dela, pelo servidor.")
                                    .font(.caption2).foregroundStyle(Arcade.dim)
                                Button("COPIAR LINK") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(p.link.absoluteString, forType: .string)
                                }
                                .buttonStyle(ArcadeButtonStyle())
                            }
                        }
                        Text("Quem tem o código vê os seus números. Não publique.")
                            .font(.caption2).foregroundStyle(Arcade.dim)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                SectionTitle(text: "RELÓGIO SEM CELULAR (WEAR OS)")
                ArcadePanel {
                    TimelineView(.periodic(from: .now, by: 5)) { _ in
                        HStack(spacing: 16) {
                            Text(model.lan.currentCode())
                                .font(Arcade.digits(30)).tracking(6).foregroundStyle(.white)
                            Text("No relógio, abra o TokenBar e digite este código (mesmo Wi-Fi). Vale uma vez e troca a cada 10 min.")
                                .font(.caption).foregroundStyle(Arcade.dim)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                SectionTitle(text: "SERVIDOR (OPCIONAL)")
                ArcadePanel {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Para ver fora de casa. Suba o seu (grátis, Cloudflare): veja o README. Deixe vazio para usar só o Wi-Fi.")
                            .font(.caption).foregroundStyle(Arcade.dim)
                        TextField("", text: $model.serverText, prompt: Text("https://tokenbar.sua-conta.workers.dev").foregroundStyle(Arcade.dim))
                            .textFieldStyle(.plain)
                            .font(Arcade.label(12))
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 6).fill(.black).overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.1))))
                        HStack {
                            Button("SALVAR") { model.saveServer() }.buttonStyle(ArcadeButtonStyle())
                            if let t = model.lastPush {
                                Text("ENVIADO \(t, style: .relative) ATRÁS").font(Arcade.label(9)).foregroundStyle(Arcade.dim)
                            }
                        }
                        if let e = model.pushError { Text(e).font(.caption2).foregroundStyle(Arcade.red) }
                        Text("Mudou o servidor? Escaneie o QR de novo no iPhone.")
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

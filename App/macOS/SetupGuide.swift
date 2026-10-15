import SwiftUI

/// Primeiros passos: um passo por tela, com uma animação mostrando o gesto.
/// Cada passo fica verde sozinho quando acontece; PULAR fecha, e o ? da barra de menu reabre.
struct SetupGuide: View {
    @EnvironmentObject var model: MacModel
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage("setupDone") private var setupDone = false
    @AppStorage("setupDevice") private var device = Device.android.rawValue
    @AppStorage("skipClaude") private var skipClaude = false
    @AppStorage("skipCodex") private var skipCodex = false
    @State private var page = 0
    @State private var androidStep = 0
    @State private var lastClient: Date?

    enum Device: String, CaseIterable {
        case android, wear, iphone, watch, none
        var title: String {
            switch self {
            case .android: "ANDROID"
            case .wear: "WEAR OS"
            case .iphone: "IPHONE"
            case .watch: "APPLE WATCH"
            case .none: Lang.t("NENHUM")
            }
        }
        /// Linha miúda embaixo do nome: o que a pessoa precisa saber antes de escolher.
        var note: String {
            switch self {
            case .android: Lang.t("baixa o app")
            case .wear: Lang.t("código no relógio")
            case .iphone, .watch: Lang.t("precisa de Xcode")
            case .none: Lang.t("só neste Mac")
            }
        }
    }

    static let apkURL = "https://github.com/ChaconLucas/tokenbar/releases/latest/download/TokenBar-Android.apk"
    static let installURL = URL(string: "https://github.com/ChaconLucas/tokenbar/blob/main/INSTALL.md")!
    private let pages = 4

    private var hasClaude: Bool { model.snapshot.providers.contains { $0.id == "claude" } }
    private var hasCodex: Bool { model.snapshot.providers.contains { $0.id == "codex" } }
    private var phoneConnected: Bool { lastClient.map { Date.now.timeIntervalSince($0) < 120 } ?? false }
    private var choice: Device { Device(rawValue: device) ?? .android }

    private func done(_ p: Int) -> Bool {
        switch p {
        case 0: hasClaude || skipClaude
        case 1: hasCodex || skipCodex
        case 2: phoneConnected || choice == .none
        default: false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(Lang.t("PRIMEIROS PASSOS")).font(Arcade.label(11)).tracking(3).foregroundStyle(Arcade.dim)
                Spacer()
                // Antes de ler: quem não fala português troca aqui, já na primeira tela.
                if page == 0 { LangToggle() }
                Button(Lang.t("PULAR")) { finish() }.buttonStyle(ArcadeButtonStyle(tint: Arcade.dim))
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 18).padding(.top, 30)

            Group {
                switch page {
                case 0: claude
                case 1: codex
                case 2: phone
                default: ready
                }
            }
            .id(page)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 24)

            footer
        }
        .background(ArcadeBackground())
        .environment(\.colorScheme, .dark)
        .environment(\.locale, Lang.locale)
        .frame(width: 560, height: 640)
        .onAppear {
            #if DEBUG
            // -TBSetupPage N -TBSetupDevice android: abre direto numa tela (capturas de tela).
            page = UserDefaults.standard.integer(forKey: "TBSetupPage")
            if let d = UserDefaults.standard.string(forKey: "TBSetupDevice") { device = d }
            #endif
        }
        .task {
            // Enquanto o guia está aberto, olha mais vezes: o passo fica verde logo que acontece.
            while !Task.isCancelled {
                lastClient = model.lan.lastClient
                if !(hasClaude && hasCodex) { model.refresh() }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    // MARK: Telas

    private var claude: some View {
        slide(art: TerminalArt(command: Lang.t("oi"), color: Art.claude, fill: 0.62),
              title: "CLAUDE CODE",
              text: Lang.t("Conecte uma vez. Depois, é só usar o Claude Code normalmente.")) {
            if hasClaude {
                chip(Lang.t("Recebendo os números"), ok: true)
            } else if model.claudeConnected {
                chip(Lang.t("Conectado. Mande uma mensagem no Claude Code…"), ok: false)
            } else {
                Button(Lang.t("CONECTAR CLAUDE CODE")) { model.connectClaude() }
                    .buttonStyle(ArcadeButtonStyle(tint: Art.claude)).controlSize(.large)
                if skipClaude { chip(Lang.t("Pulado"), ok: true) } else { tiny(Lang.t("NÃO USO")) { skipClaude = true } }
            }
            if let e = model.claudeError { Text(e).font(.caption).foregroundStyle(Arcade.red) }
            // O painel do VS Code não roda a statusline: aí os números vêm pelo login.
            if model.claudeLogin {
                if let e = model.claudeLoginError { Text(e).font(.caption).foregroundStyle(Arcade.red) }
                tiny(Lang.t("LENDO PELO LOGIN (VS CODE) · DESLIGAR")) { model.claudeLogin = false }
            } else if !hasClaude {
                tiny(Lang.t("USA O CLAUDE NO PAINEL DO VS CODE? TOQUE AQUI")) { model.claudeLogin = true }
            }
        }
    }

    private var codex: some View {
        slide(art: TerminalArt(command: "codex", color: Art.codex, fill: 0.38),
              title: "CODEX",
              text: Lang.t("Nada a configurar: use o Codex e os limites aparecem.")) {
            if hasCodex {
                chip(Lang.t("Recebendo os números"), ok: true)
            } else if skipCodex {
                chip(Lang.t("Pulado"), ok: true)
            } else {
                chip(Lang.t("Esperando a primeira resposta do Codex…"), ok: false)
                tiny(Lang.t("NÃO USO")) { skipCodex = true }
            }
        }
    }

    private var phone: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                ForEach(Device.allCases, id: \.self) { d in
                    Button { device = d.rawValue; androidStep = 0 } label: {
                        VStack(spacing: 2) {
                            Text(d.title)
                            Text(d.note).font(.system(size: 8)).tracking(0).opacity(0.75)
                        }
                    }
                    .buttonStyle(ArcadeButtonStyle(tint: d == choice ? Arcade.amber : Arcade.dim))
                }
            }
            .padding(.top, 10)
            switch choice {
            case .android:
                let download = androidStep == 0
                slide(art: ScanArt { QRCode(text: download ? Self.apkURL : model.pairing.link.absoluteString) },
                      title: download ? Lang.t("1 · BAIXE O APP") : Lang.t("2 · PAREIE"),
                      text: download ? Lang.t("Aponte a câmera do celular e instale o arquivo.") : Lang.t("No app, toque em ESCANEAR QR.")) {
                    if download {
                        chip(Lang.t("Instalou? Toque em AVANÇAR para parear."), ok: false)
                    } else {
                        connection
                    }
                }
            case .iphone:
                slide(art: ScanArt { QRCode(text: model.pairing.link.absoluteString) },
                      title: "IPHONE",
                      text: Lang.t("Precisa do app instalado pelo Xcode. Depois: ESCANEAR QR no app.")) {
                    connection
                    Link(Lang.t("O app de iPhone é instalado pelo Xcode: ver como"), destination: Self.installURL)
                        .font(.caption).foregroundStyle(Arcade.cyan)
                }
            case .wear:
                TimelineView(.periodic(from: .now, by: 5)) { _ in
                    let code = model.lan.currentCode()
                    slide(art: WatchCodeArt(code: code),
                          title: code,
                          text: Lang.t("Digite este código no relógio. Com celular Android, ele recebe sozinho.")) {
                        connection
                    }
                }
            case .watch:
                slide(art: ScanArt { QRCode(text: model.pairing.link.absoluteString) },
                      title: "APPLE WATCH",
                      text: Lang.t("Vem junto com o app do iPhone (Xcode): pareie o iPhone e pronto.")) {
                    connection
                }
            case .none:
                slide(art: MenuBarArt(), title: Lang.t("SEM CELULAR"), text: Lang.t("Tudo certo: os números ficam na barra de menu deste Mac.")) {
                    chip(Lang.t("Pronto"), ok: true)
                }
            }
        }
    }

    private var ready: some View {
        slide(art: MenuBarArt(),
              title: Lang.t("PRONTO"),
              text: Lang.t("Clique nas barrinhas da barra de menu. Arraste o display para trocar de IA.")) {
            HStack(spacing: 6) {
                hint(Lang.t("? = ver de novo"))
                hint(Lang.t("Mini = sempre na frente"))
                hint(Lang.t("Widgets: botão direito na mesa"))
            }
        }
    }

    /// Verde quando um aparelho leu este Mac nos últimos 2 minutos.
    @ViewBuilder private var connection: some View {
        if phoneConnected {
            chip(Lang.t("Aparelho conectado"), ok: true)
        } else {
            chip(Lang.t("Esperando o aparelho (mesmo Wi-Fi)…"), ok: false)
        }
    }

    private var footer: some View {
        HStack {
            Button(Lang.t("VOLTAR")) { go(-1) }.buttonStyle(ArcadeButtonStyle(tint: Arcade.dim))
                .opacity(page == 0 ? 0 : 1).disabled(page == 0)
                .keyboardShortcut(.leftArrow, modifiers: [])
            Spacer()
            HStack(spacing: 8) {
                ForEach(0..<pages, id: \.self) { i in
                    Circle()
                        .fill(done(i) ? Arcade.green : (i == page ? .white : .white.opacity(0.2)))
                        .frame(width: i == page ? 9 : 7, height: i == page ? 9 : 7)
                        .onTapGesture { withAnimation(.easeOut(duration: 0.25)) { page = i } }
                }
            }
            Spacer()
            let last = page == pages - 1
            Button(last ? Lang.t("COMEÇAR") : Lang.t("AVANÇAR")) { last ? finish() : go(1) }
                .buttonStyle(ArcadeButtonStyle(tint: done(page) || last ? Arcade.green : Arcade.cyan))
                .keyboardShortcut(.rightArrow, modifiers: [])
        }
        .padding(18)
    }

    // MARK: Peças

    private func slide<A: View, C: View>(art: A, title: String, text: String, @ViewBuilder action: () -> C) -> some View {
        VStack(spacing: 14) {
            ArtFrame { art }
                .frame(maxWidth: .infinity).frame(height: 250)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.03)))
            Text(title).font(Arcade.digits(24)).tracking(4).foregroundStyle(.white)
                .shadow(color: Arcade.cyan.opacity(0.5), radius: 8)
            Text(text).font(.callout).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
            VStack(spacing: 8) { action() }
            Spacer(minLength: 0)
        }
        .padding(.top, 10)
    }

    private func chip(_ s: String, ok: Bool) -> some View {
        Label(s, systemImage: ok ? "checkmark.circle.fill" : "hourglass")
            .font(Arcade.label(11)).foregroundStyle(ok ? Arcade.green : .white.opacity(0.8))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill((ok ? Arcade.green : .white).opacity(0.1)))
    }

    private func hint(_ s: String) -> some View {
        Text(s).font(.caption2).foregroundStyle(Arcade.dim)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().strokeBorder(.white.opacity(0.15)))
    }

    private func tiny(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(title, action: action).buttonStyle(.plain).font(Arcade.label(9)).foregroundStyle(Arcade.dim)
    }

    /// No Android, o passo do celular tem duas partes (baixar, depois parear): AVANÇAR passa por elas.
    private func go(_ step: Int) {
        withAnimation(.easeOut(duration: 0.25)) {
            if page == 2 && choice == .android {
                if step > 0 && androidStep == 0 { androidStep = 1; return }
                if step < 0 && androidStep == 1 { androidStep = 0; return }
            }
            page = min(max(page + step, 0), pages - 1)
            if page == 2 { androidStep = step > 0 ? 0 : 1 }
        }
    }

    private func finish() {
        setupDone = true
        dismissWindow(id: "setup")
    }
}

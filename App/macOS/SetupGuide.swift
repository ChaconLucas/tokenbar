import SwiftUI

/// Primeiros passos: leva a pessoa do zero ao celular conectado. Cada passo fica verde sozinho
/// quando acontece (os números do Claude chegam, o celular lê o Mac pela primeira vez…).
struct SetupGuide: View {
    @EnvironmentObject var model: MacModel
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage("setupDone") private var setupDone = false
    @AppStorage("setupDevice") private var device = Device.android.rawValue
    @AppStorage("skipClaude") private var skipClaude = false
    @AppStorage("skipCodex") private var skipCodex = false
    @State private var lastClient: Date?

    enum Device: String, CaseIterable {
        case android, wear, iphone, watch, none
        var title: String {
            switch self {
            case .android: "ANDROID"
            case .wear: "WEAR OS"
            case .iphone: "IPHONE"
            case .watch: "APPLE WATCH"
            case .none: "SÓ NO MAC"
            }
        }
    }

    static let apkURL = "https://github.com/ChaconLucas/tokenbar/releases/latest/download/TokenBar-Android.apk"
    static let installURL = URL(string: "https://github.com/ChaconLucas/tokenbar/blob/main/INSTALL.md")!

    private var hasClaude: Bool { model.snapshot.providers.contains { $0.id == "claude" } }
    private var hasCodex: Bool { model.snapshot.providers.contains { $0.id == "codex" } }
    private var phoneConnected: Bool { lastClient.map { Date.now.timeIntervalSince($0) < 120 } ?? false }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("PRIMEIROS PASSOS").font(Arcade.digits(22)).tracking(4).foregroundStyle(.white)
                    .shadow(color: Arcade.cyan.opacity(0.6), radius: 8)
                Text("Quatro passos. Cada um fica verde sozinho quando der certo.")
                    .font(.caption).foregroundStyle(Arcade.dim)

                step(1, "CLAUDE CODE", done: hasClaude || skipClaude) { claude }
                step(2, "CODEX", done: hasCodex || skipCodex) { codex }
                step(3, "CELULAR E RELÓGIO", done: phoneConnected || device == Device.none.rawValue) { phone }
                step(4, "PRONTO", done: false) { tips }
            }
            .padding(18)
            .padding(.top, 14)
        }
        .scrollIndicators(.never)
        .background(ArcadeBackground())
        .environment(\.colorScheme, .dark)
        .frame(minWidth: 480, minHeight: 520)
        // Enquanto o guia está aberto, olha mais vezes: o passo fica verde logo que acontece.
        .task {
            while !Task.isCancelled {
                lastClient = model.lan.lastClient
                if !(hasClaude && hasCodex) { model.refresh() }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    // MARK: Passos

    @ViewBuilder private var claude: some View {
        if hasClaude {
            ok("Recebendo os números do Claude Code.")
        } else if model.claudeConnected {
            wait("Conectado. Mande qualquer mensagem numa sessão do Claude Code para os números chegarem.")
        } else {
            note("O Claude Code só entrega os limites para a statusline. O TokenBar guarda uma cópia e mantém a statusline que você já tem (com backup do settings.json).")
            HStack {
                Button("CONECTAR CLAUDE CODE") { model.connectClaude() }.buttonStyle(ArcadeButtonStyle())
                skip("NÃO USO") { skipClaude = true }
            }
        }
        if let e = model.claudeError { Text(e).font(.caption).foregroundStyle(Arcade.red) }
    }

    @ViewBuilder private var codex: some View {
        if hasCodex {
            ok("Recebendo os números do Codex.")
        } else {
            wait("Nada a configurar: use o Codex uma vez e os limites chegam com a primeira resposta.")
            skip("NÃO USO") { skipCodex = true }
        }
        note("Outras IAs: qualquer uma aparece com um arquivo em ~/.tokenbar/providers (veja docs/providers.md no GitHub).")
    }

    @ViewBuilder private var phone: some View {
        let choice = Device(rawValue: device) ?? .android
        HStack(spacing: 6) {
            ForEach(Device.allCases, id: \.self) { d in
                Button(d.title) { device = d.rawValue }
                    .buttonStyle(ArcadeButtonStyle(tint: d == choice ? Arcade.amber : Arcade.dim))
            }
        }
        switch choice {
        case .android:
            HStack(alignment: .top, spacing: 14) {
                qr(Self.apkURL, "1. BAIXE O APP", "Aponte a câmera do celular. Abra o arquivo e permita instalar; se o Play Protect avisar, Instalar assim mesmo.")
                qr(model.pairing.link.absoluteString, "2. PAREIE", "No app, toque em ESCANEAR QR e aponte para este código.")
            }
            connection
        case .wear:
            note("Com um celular Android pareado, o relógio recebe os números sozinho. Sem celular: instale o TokenBar-WearOS.apk (veja o guia de instalação) e digite no relógio:")
            TimelineView(.periodic(from: .now, by: 5)) { _ in
                Text(model.lan.currentCode()).font(Arcade.digits(30)).tracking(6).foregroundStyle(.white)
            }
            note("O código vale uma vez e troca a cada 10 minutos.")
            Link("ABRIR GUIA DE INSTALAÇÃO", destination: Self.installURL).font(Arcade.label(10)).foregroundStyle(Arcade.cyan)
            connection
        case .iphone:
            note("O app de iPhone ainda não está na App Store: ele é instalado pelo Xcode num Mac (o guia de instalação explica, ou peça para a sua IA).")
            Link("ABRIR GUIA DE INSTALAÇÃO", destination: Self.installURL).font(Arcade.label(10)).foregroundStyle(Arcade.cyan)
            qr(model.pairing.link.absoluteString, "PAREIE", "Com o app instalado, aponte a câmera do iPhone → Abrir no TokenBar → permita Rede Local.")
            connection
        case .watch:
            note("O app do relógio vem junto com o do iPhone. Pareie o iPhone (escolha IPHONE acima) e o relógio recebe sozinho.")
        case .none:
            ok("Tudo certo: o TokenBar fica na barra de menu.")
        }
    }

    /// Verde quando um aparelho leu este Mac nos últimos 2 minutos.
    @ViewBuilder private var connection: some View {
        if phoneConnected {
            ok("Aparelho conectado.")
        } else {
            wait("Esperando o aparelho… Ele precisa estar no mesmo Wi-Fi que este Mac.")
            note("Se o macOS perguntar sobre conexões de entrada, responda Permitir: é assim que o celular lê o Mac.")
        }
    }

    @ViewBuilder private var tips: some View {
        VStack(alignment: .leading, spacing: 4) {
            note("• Clique nas barrinhas da barra de menu para o resumo; Mini abre o flutuante, sempre na frente.")
            note("• Arraste o display para o lado para trocar de IA. Botão direito no aparelho: tamanho e tela cheia.")
            note("• Widgets: botão direito na mesa → Editar Widgets → TokenBar. Central de Controle: Editar → TokenBar.")
            note("• Este guia volta pelo botão Guia da barra de menu ou em Ajustes.")
        }
        Button("COMEÇAR") {
            setupDone = true
            dismissWindow(id: "setup")
        }
        .buttonStyle(ArcadeButtonStyle(tint: Arcade.green))
    }

    // MARK: Peças

    private func step<C: View>(_ n: Int, _ title: String, done: Bool, @ViewBuilder content: () -> C) -> some View {
        ArcadePanel {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(done ? "✓" : "\(n)")
                        .font(Arcade.label(12)).foregroundStyle(.black)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(done ? Arcade.green : Arcade.amber))
                    Text(title).font(Arcade.label(12)).tracking(2).foregroundStyle(.white)
                }
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func qr(_ text: String, _ title: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Arcade.label(10)).tracking(2).foregroundStyle(Arcade.amber)
            QRCode(text: text).frame(width: 130, height: 130)
                .padding(6).background(.white, in: RoundedRectangle(cornerRadius: 8))
            Text(caption).font(.caption2).foregroundStyle(Arcade.dim).frame(width: 142, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func ok(_ s: String) -> some View {
        Label(s, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(Arcade.green)
    }
    private func wait(_ s: String) -> some View {
        Label(s, systemImage: "hourglass").font(.caption).foregroundStyle(.white)
    }
    private func note(_ s: String) -> some View {
        Text(s).font(.caption).foregroundStyle(Arcade.dim).fixedSize(horizontal: false, vertical: true)
    }
    private func skip(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(title, action: action).buttonStyle(ArcadeButtonStyle(tint: Arcade.dim))
    }
}

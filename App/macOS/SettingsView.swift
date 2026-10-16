import SwiftUI

/// Ajustes com a cara do aparelho: abas em teclas de LED, uma linha por opção, explicação no ⓘ.
struct SettingsView: View {
    @EnvironmentObject var model: MacModel
    @ObservedObject private var updater = Updater.shared
    @Environment(\.openWindow) private var openWindow
    @AppStorage("settingsTab") private var tab = "general"
    @State private var lastClient: Date?
    @State private var confirmReset = false
    @State private var editingKey: String?
    @State private var keyText = ""
    @ObservedObject private var webhooks = Webhooks.shared
    @AppStorage(Webhooks.urlKey) private var webhookURL = ""
    @AppStorage("webhook80") private var hook80 = true
    @AppStorage("webhook95") private var hook95 = true
    @AppStorage("webhookReset") private var hookReset = true

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                LEDChoice(options: [("general", Lang.t("GERAL")), ("ais", Lang.t("IAS")),
                                    ("devices", Lang.t("APARELHOS")), ("server", Lang.t("SERVIDOR"))],
                          selection: $tab, dot: 1.7)
                Spacer()
                DotKey(text: Lang.t("GUIA"), on: false, color: Arcade.amber, dot: 1.7) { openWindow(id: "setup"); NSApp.activate() }
                    .help(Lang.t("Primeiros passos"))
            }
            .padding(.top, 30)

            ScrollView {
                Group {
                    switch tab {
                    case "ais": ais
                    case "devices": devices
                    case "server": server
                    default: general
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollIndicators(.never)

            footer
        }
        .padding(.horizontal, 20).padding(.bottom, 14)
        .frame(width: 520, height: 560)
        .background(Color(red: 0.02, green: 0.02, blue: 0.03))
        .environment(\.colorScheme, .dark)
        .environment(\.locale, Lang.locale)
        .task {
            while !Task.isCancelled {
                lastClient = model.lan.lastClient
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    // MARK: Abas

    private var general: some View {
        LEDGroup {
            LEDRow(label: "IDIOMA · LANGUAGE") {
                LEDChoice(options: [("auto", "AUTO"), ("pt", "PT"), ("en", "EN")],
                          selection: Binding(get: { LangStore.shared.lang }, set: { LangStore.shared.lang = $0 }),
                          color: Arcade.amber)
            }
            LEDRow(label: Lang.t("MOSTRAR A %"), info: Lang.t("Onde ver os números. NOTCH: uma pílula preta em volta da câmera (passe o mouse para abrir) e, na barra, só um anel pequeno. BARRA: as barrinhas com a % na barra de menu.")) {
                LEDChoice(options: [("bar", Lang.t("BARRA")), ("notch", "NOTCH"), ("both", Lang.t("OS DOIS"))], selection: $model.showIn)
            }
            LEDRow(label: "CLAUDE") { LEDSwatches(value: $model.theme.claude) }
            LEDRow(label: "CODEX") { LEDSwatches(value: $model.theme.codex) }
            LEDRow(label: Lang.t("TEXTO")) { LEDSwatches(value: $model.theme.text) }
            LEDRow(label: Lang.t("CONTADOR")) { LEDSwatches(value: $model.theme.timer) }
            LEDRow(label: Lang.t("COR PELO USO"), info: Lang.t("Em vez da cor da IA, o display fica verde, amarelo e vermelho conforme o gasto.")) {
                LEDSwitch(isOn: $model.theme.levelColors)
            }
            LEDRow(label: Lang.t("VERMELHO A PARTIR DE 85%")) {
                LEDSwitch(isOn: $model.theme.warnRed, color: Arcade.red)
                    .disabled(model.theme.levelColors).opacity(model.theme.levelColors ? 0.4 : 1)
            }
            LEDRow(label: Lang.t("PONTOS")) {
                LEDChoice(options: [(true, Lang.t("REDONDOS")), (false, Lang.t("QUADRADOS"))], selection: $model.theme.roundDots)
            }
            LEDRow(label: Lang.t("BRILHO")) { LEDDots(value: $model.theme.glow, range: 0...2) }
            LEDRow(label: Lang.t("PADRÃO")) {
                DotKey(text: Lang.t("RESTAURAR"), on: false, color: .white, dot: 1.5) { model.theme = .standard }
            }
        }
    }

    private var ais: some View {
        VStack(spacing: 14) {
            LEDGroup {
                LEDRow(label: "CLAUDE CODE", info: Lang.t("O Claude Code só entrega os limites para a statusline do terminal. O TokenBar guarda uma cópia e mantém a statusline que você já tem (com backup do settings.json).")) {
                    if model.claudeConnected {
                        status("claude")
                        DotKey(text: Lang.t("DESCONECTAR"), on: false, color: .white, dot: 1.3) { model.disconnectClaude() }
                    } else {
                        DotKey(text: Lang.t("CONECTAR"), on: true, color: Art.claude, dot: 1.5) { model.connectClaude() }
                    }
                }
                LEDRow(label: Lang.t("PAINEL DO VS CODE"), info: Lang.t("No painel do VS Code a statusline não roda. Ligado, o TokenBar lê os limites pelo login que o Claude Code já guardou (a chave só vai para a Anthropic e não sai deste Mac). Na primeira vez, o macOS pergunta: responda Permitir sempre.")) {
                    LEDSwitch(isOn: $model.claudeLogin)
                }
                if let e = model.claudeLoginError ?? model.claudeError {
                    Text(e).font(.caption).foregroundStyle(Arcade.red).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                }
                LEDRow(label: "CODEX", info: Lang.t("Nada a configurar: o Codex grava os limites a cada resposta, pelo terminal, pelo VS Code ou pelo app.")) {
                    status("codex")
                }
            }
            let others = model.snapshot.providers.filter { !["claude", "codex", "copilot"].contains($0.id) && Connector(rawValue: $0.id) == nil }
            LEDGroup {
                LEDRow(label: "GITHUB COPILOT", info: Lang.t("Lê a cota mensal de premium requests usando o login do GitHub CLI (gh) ou do Copilot. O token só vai para o GitHub.")) {
                    if model.copilotOn { status("copilot") }
                    LEDSwitch(isOn: $model.copilotOn)
                }
                if model.copilotOn, let e = model.copilotError {
                    Text(e).font(.caption).foregroundStyle(Arcade.red).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                }
            }
            LEDGroup {
                ForEach(Connector.allCases) { c in connectorRow(c) }
            }
            LEDGroup {
                ForEach(others) { p in
                    LEDRow(label: p.name.uppercased()) { status(p.id) }
                }
                LEDRow(label: Lang.t("OUTRAS IAS"), info: Lang.t("Qualquer IA aparece com um arquivo JSON em ~/.tokenbar/providers (formato em docs/providers.md no GitHub).")) {
                    DotKey(text: Lang.t("ABRIR PASTA"), on: false, color: .white, dot: 1.5) {
                        let dir = Collector.providersDir
                        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(dir)
                    }
                }
            }
        }
    }

    private var devices: some View {
        let connected = lastClient.map { Date.now.timeIntervalSince($0) < 120 } ?? false
        return VStack(spacing: 14) {
            LEDGroup {
                HStack(alignment: .top, spacing: 18) {
                    QRCode(text: model.pairing.link.absoluteString)
                        .frame(width: 132, height: 132)
                        .padding(7).background(.white, in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 10) {
                        LEDText(text: Lang.t("CELULAR"), color: Arcade.cyan, dot: 2)
                        Text(Lang.t("Câmera no QR → Abrir no TokenBar. Mesmo Wi-Fi."))
                            .font(.callout).foregroundStyle(.white.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
                        if connected {
                            LEDStatus(kind: .ok, text: Lang.t("CONECTADO"))
                        } else if let t = lastClient {
                            LEDStatus(kind: .wait, text: Lang.f("VISTO %@", ago(t)))
                        } else {
                            LEDStatus(kind: .wait, text: Lang.t("ESPERANDO O CELULAR"))
                        }
                        HStack(spacing: 6) {
                            DotKey(text: Lang.t("COPIAR LINK"), on: false, color: .white, dot: 1.4) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(model.pairing.link.absoluteString, forType: .string)
                            }
                            InfoTip(text: Lang.t("Quem tem o código vê os seus números. Não publique."))
                        }
                        DotKey(text: Lang.t("DESCONECTAR APARELHOS"), on: true, color: Arcade.red, dot: 1.3) { confirmReset = true }
                            .confirmationDialog(Lang.t("Desconectar todos os celulares e relógios? Eles vão precisar escanear o QR de novo."),
                                                isPresented: $confirmReset) {
                                Button(Lang.t("DESCONECTAR"), role: .destructive) { model.resetPairing() }
                            }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 12)
            }
            LEDGroup {
                LEDRow(label: Lang.t("WEAR OS SEM CELULAR"), info: Lang.t("No relógio, abra o TokenBar e digite este código (mesmo Wi-Fi). Vale uma vez e troca a cada 10 min.")) {
                    TimelineView(.periodic(from: .now, by: 5)) { _ in
                        LEDText(text: model.lan.currentCode(), color: .white, dot: 2.2)
                    }
                }
                LEDRow(label: Lang.t("APPLE WATCH")) {
                    Text(Lang.t("vem pelo iPhone")).font(.caption).foregroundStyle(.white.opacity(0.5))
                }
                LEDRow(label: Lang.t("GUIA")) {
                    DotKey(text: Lang.t("PRIMEIROS PASSOS"), on: true, color: Arcade.amber, dot: 1.4) {
                        openWindow(id: "setup"); NSApp.activate()
                    }
                }
            }
        }
    }

    private var server: some View {
        VStack(spacing: 14) {
            cloud
            localAPI
            webhook
        }
    }

    private var localAPI: some View {
        LEDGroup {
            LEDRow(label: Lang.t("API LOCAL"), info: Lang.t("Outros apps e scripts neste Mac leem os números em http://localhost:41777/v1/usage. Só este computador acessa.")) {
                if model.apiEnabled {
                    if let p = model.apiPort {
                        LEDStatus(kind: .ok, text: "localhost:\(p)")
                    } else if model.apiFailed {
                        LEDStatus(kind: .error, text: Lang.t("PORTA OCUPADA"))
                    } else {
                        LEDStatus(kind: .wait, text: Lang.t("LIGANDO"))
                    }
                }
                LEDSwitch(isOn: $model.apiEnabled)
            }
        }
    }

    private var webhook: some View {
        LEDGroup {
            LEDRow(label: "WEBHOOK", info: Lang.t("Avisa um endereço quando uma IA passa de 80% ou 95% e quando o limite reseta. Slack e Discord recebem uma frase; outros endereços, o JSON completo.")) {
                DotKey(text: Lang.t("TESTAR"), on: true, color: Arcade.cyan, dot: 1.4) {
                    webhooks.sendTest(snapshot: model.snapshot)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                TextField("", text: $webhookURL, prompt: Text("https://hooks.slack.com/services/…").foregroundStyle(.white.opacity(0.3)))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.black).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.12))))
                if let e = webhooks.lastError {
                    LEDStatus(kind: .error, text: Lang.f("ÚLTIMO ENVIO: %@", e.uppercased()))
                } else if let t = webhooks.lastOK {
                    LEDStatus(kind: .ok, text: Lang.f("ÚLTIMO ENVIO: %@", ago(t)))
                } else {
                    LEDStatus(kind: .off, text: Lang.t("NENHUM ENVIO AINDA"))
                }
            }
            .padding(.vertical, 8)
            LEDRow(label: Lang.t("AVISAR EM")) {
                HStack(spacing: 8) {
                    hookLabel("80%"); LEDSwitch(isOn: $hook80, color: Arcade.amber)
                    hookLabel("95%"); LEDSwitch(isOn: $hook95, color: Arcade.red)
                    hookLabel("RESET"); LEDSwitch(isOn: $hookReset)
                }
            }
        }
    }

    private func hookLabel(_ s: String) -> some View {
        Text(s).font(Arcade.label(10)).tracking(1).foregroundStyle(.white.opacity(0.6)).padding(.leading, 4)
    }

    private var cloud: some View {
        LEDGroup {
            LEDRow(label: Lang.t("ENDEREÇO"), info: Lang.t("Opcional, para ver os números fora de casa. Suba o seu, grátis, na Cloudflare (veja o README). Vazio = só Wi-Fi. Mudou? Escaneie o QR de novo no celular.")) {
                EmptyView()
            }
            TextField("", text: $model.serverText, prompt: Text("https://tokenbar.sua-conta.workers.dev").foregroundStyle(.white.opacity(0.3)))
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(.black).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.12))))
                .padding(.vertical, 8)
            LEDRow(label: Lang.t("ESTADO")) {
                HStack(spacing: 10) {
                    if let e = model.pushError {
                        LEDStatus(kind: .error, text: e.uppercased())
                    } else if let t = model.lastPush {
                        LEDStatus(kind: .ok, text: Lang.f("ENVIADO %@", ago(t)))
                    } else {
                        LEDStatus(kind: .off, text: model.pairing.server == nil ? Lang.t("SÓ WI-FI") : Lang.t("ESPERANDO"))
                    }
                    DotKey(text: Lang.t("SALVAR"), on: true, color: Arcade.cyan, dot: 1.4) { model.saveServer() }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(Lang.f("VERSÃO %@", Updater.current)).font(Arcade.label(10)).tracking(2).foregroundStyle(.white.opacity(0.4))
            Spacer()
            if let e = updater.error { Text(e).font(.caption2).foregroundStyle(Arcade.red).lineLimit(1) }
            if let v = updater.available {
                DotKey(text: updater.busy ? Lang.t("ATUALIZANDO") : Lang.f("ATUALIZAR PARA %@", v), on: true, color: Arcade.green, dot: 1.4) {
                    updater.install()
                }
            } else {
                LEDStatus(kind: .ok, text: Lang.t("EM DIA"))
            }
        }
    }

    // MARK: Peças

    /// "HÁ 2 MIN" / "2 MIN AGO", no idioma escolhido.
    private func ago(_ d: Date) -> String {
        d.formatted(Date.RelativeFormatStyle(presentation: .named, locale: Lang.locale)).uppercased()
    }

    /// Cursor: liga e desliga. As outras: botão CHAVE abre o campo; com chave, mostra o estado e REMOVER.
    @ViewBuilder
    private func connectorRow(_ c: Connector) -> some View {
        VStack(spacing: 0) {
            LEDRow(label: c.title, info: c.info) {
                if !c.needsKey {
                    if model.cursorOn { status(c.id) }
                    LEDSwitch(isOn: $model.cursorOn)
                } else if model.isOn(c) {
                    status(c.id)
                    DotKey(text: Lang.t("REMOVER"), on: false, color: .white, dot: 1.3) { model.setKey(c, nil) }
                } else {
                    DotKey(text: Lang.t("CHAVE"), on: editingKey == c.id, color: Arcade.cyan, dot: 1.4) {
                        editingKey = editingKey == c.id ? nil : c.id
                        keyText = ""
                    }
                }
            }
            if editingKey == c.id, !model.isOn(c) {
                HStack(spacing: 8) {
                    SecureField("", text: $keyText, prompt: Text(c == .factory ? Lang.t("vazio = usar ~/.factory/.env") : Lang.t("cole a chave de API")).foregroundStyle(.white.opacity(0.3)))
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.black).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.12))))
                        .onSubmit { saveKey(c) }
                    DotKey(text: Lang.t("SALVAR"), on: true, color: Arcade.cyan, dot: 1.4) { saveKey(c) }
                }
                .padding(.vertical, 8)
            }
            if let e = model.connectorErrors[c.id] {
                Text(e).font(.caption).foregroundStyle(Arcade.red).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            }
        }
    }

    private func saveKey(_ c: Connector) {
        model.setKey(c, keyText)
        keyText = ""
        if model.isOn(c) { editingKey = nil }
    }

    /// Estado de uma IA: recebendo (com há quanto tempo) ou esperando.
    @ViewBuilder
    private func status(_ id: String) -> some View {
        if let p = model.snapshot.provider(id) {
            let age = Date.now.timeIntervalSince(p.observedAt)
            LEDStatus(kind: age < 3600 ? .ok : .wait,
                      text: Lang.f("LIDO %@", ago(p.observedAt)))
        } else {
            LEDStatus(kind: .wait, text: Lang.t("ESPERANDO"))
        }
    }
}

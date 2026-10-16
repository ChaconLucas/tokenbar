import Foundation
import Observation
import WidgetKit

/// Idioma do app: o texto em português é a chave; o inglês sai do mapa `en`. Chave sem tradução = português.
/// A escolha ("auto" | "pt" | "en") mora no App Group: widgets, controles e relógio leem a mesma.
enum Lang {
    static let key = "lang"

    /// "pt" ou "en": o que está valendo agora.
    static var current: String { resolve(pref) }
    static var isEN: Bool { current == "en" }

    /// A escolha da pessoa. No app vem do LangStore (observável: a tela que leu redesenha ao trocar);
    /// nos widgets e controles (outro processo) vem direto do App Group, lido a cada desenho.
    static var pref: String {
        isExtension ? (TB.defaults.string(forKey: key) ?? "auto") : LangStore.shared.lang
    }

    /// "auto" segue o idioma do aparelho: português se for pt, senão inglês.
    static func resolve(_ pref: String) -> String {
        switch pref {
        case "pt", "en": return pref
        default: return (Locale.preferredLanguages.first ?? "en").lowercased().hasPrefix("pt") ? "pt" : "en"
        }
    }

    /// Para datas e horas formatadas ("SEX 16:40", "há 5 min").
    static var locale: Locale { Locale(identifier: isEN ? "en_US" : "pt_BR") }

    static func t(_ pt: String) -> String {
        guard isEN else { return pt }
        if let s = en[pt] { return s }
        #if DEBUG
        missing(pt)
        #endif
        return pt
    }

    /// Texto com valores: `Lang.f("Atualizar para a versão %@", v)`; o formato é a chave.
    static func f(_ pt: String, _ args: CVarArg...) -> String {
        String(format: t(pt), locale: locale, arguments: args)
    }

    private static let isExtension = Bundle.main.bundlePath.hasSuffix(".appex")

    #if DEBUG
    private static let lock = NSLock()
    nonisolated(unsafe) private static var reported = Set<String>()
    private static func missing(_ pt: String) {
        // Números e siglas sem letra minúscula/acentuada (ex.: "123456", "5H") não precisam de tradução.
        guard pt.rangeOfCharacter(from: .letters) != nil else { return }
        lock.lock(); defer { lock.unlock() }
        if reported.insert(pt).inserted { print("[Lang] sem tradução: \"\(pt)\"") }
    }
    #endif

    // MARK: - Português → inglês

    static let en: [String: String] = [
        // Ajustes em LED e guia
        "O APP VENCE EM %d DIAS · TOQUE": "APP EXPIRES IN %d DAYS · TAP",
        "VERSÃO %@ DISPONÍVEL · TOQUE": "VERSION %@ AVAILABLE · TAP",
        "ATUALIZAÇÃO": "UPDATE",
        "Versão instalada: %@": "Installed version: %@",
        "Nova versão: %@": "New version: %@",
        "Vence em %d dias (conta gratuita da Apple).": "Expires in %d days (free Apple account).",
        "Para atualizar ou renovar: conecte o iPhone ao Mac e rode no Terminal (ou peça para a sua IA):": "To update or renew: connect the iPhone to the Mac and run in Terminal (or ask your AI):",
        "COPIAR COMANDO": "COPY COMMAND",
        "O TokenBar vence amanhã": "TokenBar expires tomorrow",
        "Conecte o iPhone ao Mac e rode o comando de instalação de novo para renovar.": "Connect the iPhone to the Mac and run the install command again to renew.",
        "MOSTRAR A %": "SHOW THE %",
        "BARRA": "MENU BAR",
        "OS DOIS": "BOTH",
        "AJUSTES": "SETTINGS",
        "Onde ver os números. NOTCH: uma pílula preta em volta da câmera (passe o mouse para abrir) e, na barra, só um anel pequeno. BARRA: as barrinhas com a % na barra de menu.": "Where to see the numbers. NOTCH: a black pill around the camera (hover to open) and just a small ring in the menu bar. MENU BAR: the little bars with the % in the menu bar.",
        "LIGAR": "TURN ON",
        "Lendo pelo login…": "Reading from the login…",
        "Claude sem números. Usa no painel do VS Code?": "No Claude numbers. Using the VS Code panel?",
        "Minimizar": "Minimize",
        "DESCONECTAR": "DISCONNECT",
        "DESCONECTAR APARELHOS": "DISCONNECT DEVICES",
        "Desconectar todos os celulares e relógios? Eles vão precisar escanear o QR de novo.": "Disconnect all phones and watches? They will need to scan the QR again.",
        "GERAL": "GENERAL",
        "IAS": "AIS",
        "APARELHOS": "DEVICES",
        "SERVIDOR": "SERVER",
        "GUIA": "GUIDE",
        "COR PELO USO": "COLOR BY USAGE",
        "Em vez da cor da IA, o display fica verde, amarelo e vermelho conforme o gasto.": "Instead of each AI's color, the display turns green, yellow and red as usage grows.",
        "VERMELHO A PARTIR DE 85%": "RED FROM 85%",
        "REDONDOS": "ROUND",
        "QUADRADOS": "SQUARE",
        "PADRÃO": "DEFAULTS",
        "RESTAURAR": "RESTORE",
        "O Claude Code só entrega os limites para a statusline do terminal. O TokenBar guarda uma cópia e mantém a statusline que você já tem (com backup do settings.json).": "Claude Code only shares its limits with the terminal statusline. TokenBar keeps a copy and keeps your current statusline (settings.json is backed up).",
        "CONECTAR": "CONNECT",
        "PAINEL DO VS CODE": "VS CODE PANEL",
        "No painel do VS Code a statusline não roda. Ligado, o TokenBar lê os limites pelo login que o Claude Code já guardou (a chave só vai para a Anthropic e não sai deste Mac). Na primeira vez, o macOS pergunta: responda Permitir sempre.": "The statusline doesn't run in the VS Code panel. When on, TokenBar reads the limits using the login Claude Code already saved (the key only goes to Anthropic and never leaves this Mac). The first time, macOS asks: choose Always Allow.",
        "Nada a configurar: o Codex grava os limites a cada resposta, pelo terminal, pelo VS Code ou pelo app.": "Nothing to set up: Codex saves its limits with every reply, from the terminal, VS Code or the app.",
        "OUTRAS IAS": "OTHER AIS",
        "Qualquer IA aparece com um arquivo JSON em ~/.tokenbar/providers (formato em docs/providers.md no GitHub).": "Any AI shows up with a JSON file in ~/.tokenbar/providers (format in docs/providers.md on GitHub).",
        "ABRIR PASTA": "OPEN FOLDER",
        "CELULAR": "PHONE",
        "Câmera no QR → Abrir no TokenBar. Mesmo Wi-Fi.": "Camera on the QR → Open in TokenBar. Same Wi-Fi.",
        "CONECTADO": "CONNECTED",
        "VISTO %@": "SEEN %@",
        "ESPERANDO O CELULAR": "WAITING FOR THE PHONE",
        "WEAR OS SEM CELULAR": "WEAR OS WITHOUT PHONE",
        "APPLE WATCH": "APPLE WATCH",
        "vem pelo iPhone": "comes with the iPhone",
        "ENDEREÇO": "ADDRESS",
        "Opcional, para ver os números fora de casa. Suba o seu, grátis, na Cloudflare (veja o README). Vazio = só Wi-Fi. Mudou? Escaneie o QR de novo no celular.": "Optional, to see your numbers away from home. Deploy your own for free on Cloudflare (see the README). Empty = Wi-Fi only. Changed it? Scan the QR again on the phone.",
        "ESTADO": "STATUS",
        "ENVIADO %@": "SENT %@",
        "SÓ WI-FI": "WI-FI ONLY",
        "ESPERANDO": "WAITING",
        "ATUALIZANDO": "UPDATING",
        "EM DIA": "UP TO DATE",
        "LIDO %@": "READ %@",
        "CLAUDE": "CLAUDE",
        // Nomes próprios (iguais nos dois idiomas)
        "TokenBar": "TokenBar",
        "Claude": "Claude",
        "Codex": "Codex",

        // Mac: barra de menu, janela do aparelho e Ajustes
        "Ajustes do TokenBar": "TokenBar Settings",
        "Primeiros passos": "Getting started",
        "Primeiros passos…": "Getting started…",
        "Atualizando…": "Updating…",
        "Atualizar para a versão %@": "Update to version %@",
        "Aparelho": "Device",
        "Ajustes": "Settings",
        "Ajustes…": "Settings…",
        "Guia: primeiros passos": "Guide: getting started",
        "Atualizar": "Refresh",
        "Atualizar agora": "Refresh now",
        "Sair do TokenBar": "Quit TokenBar",
        "SEM SINAL. CONECTE O CLAUDE CODE OU USE O CODEX UMA VEZ.": "NO SIGNAL. CONNECT CLAUDE CODE OR USE CODEX ONCE.",
        "Maior": "Bigger",
        "Menor": "Smaller",
        "Abrir Mini (flutuante)": "Open Mini (floating)",
        "Flutuar (sempre na frente, em todas as mesas)": "Float (always on top, on every desktop)",
        "Sair da tela cheia": "Exit full screen",
        "Tela cheia": "Full screen",
        "Fechar aparelho": "Close device",
        "PRIMEIROS PASSOS: CONECTAR TUDO": "GETTING STARTED: CONNECT EVERYTHING",
        "APARÊNCIA": "APPEARANCE",
        "DETALHES": "DETAILS",
        "CONECTADO PELA STATUSLINE": "CONNECTED THROUGH THE STATUSLINE",
        "Os números chegam enquanto alguma sessão do Claude Code estiver aberta.": "Numbers arrive while any Claude Code session is open.",
        "O Claude Code só entrega os limites para a statusline. O TokenBar passa a ler essa cópia e mantém a sua statusline atual.": "Claude Code only hands its limits to the statusline. TokenBar reads that copy and keeps your current statusline.",
        "CONECTAR CLAUDE CODE": "CONNECT CLAUDE CODE",
        "Ler pelo login do Claude Code (para quem usa o painel do VS Code)": "Read through the Claude Code login (if you use the VS Code panel)",
        "Usa a chave que o Claude Code já guardou; ela só vai para a Anthropic e não sai deste Mac. Na primeira vez, o macOS pergunta: responda Permitir sempre.": "Uses the key Claude Code already saved; it only goes to Anthropic and never leaves this Mac otherwise. The first time, macOS asks: answer Always Allow.",
        "CELULAR E RELÓGIO": "PHONE & WATCH",
        "Aponte a câmera do iPhone para o código. O Watch recebe pelo iPhone.": "Point the iPhone camera at the code. The Watch gets it through the iPhone.",
        "Modo Wi-Fi: o iPhone lê direto deste Mac quando estão na mesma rede.": "Wi-Fi mode: the iPhone reads straight from this Mac on the same network.",
        "Wi-Fi + servidor: na mesma rede lê direto; fora dela, pelo servidor.": "Wi-Fi + server: on the same network it reads directly; away, through the server.",
        "COPIAR LINK": "COPY LINK",
        "Quem tem o código vê os seus números. Não publique.": "Anyone with the code sees your numbers. Don't share it publicly.",
        "RELÓGIO SEM CELULAR (WEAR OS)": "WATCH WITHOUT A PHONE (WEAR OS)",
        "No relógio, abra o TokenBar e digite este código (mesmo Wi-Fi). Vale uma vez e troca a cada 10 min.": "On the watch, open TokenBar and enter this code (same Wi-Fi). It works once and changes every 10 min.",
        "SERVIDOR (OPCIONAL)": "SERVER (OPTIONAL)",
        "Para ver fora de casa. Suba o seu (grátis, Cloudflare): veja o README. Deixe vazio para usar só o Wi-Fi.": "To check away from home. Deploy your own (free, Cloudflare): see the README. Leave empty to use Wi-Fi only.",
        "https://tokenbar.sua-conta.workers.dev": "https://tokenbar.your-account.workers.dev",
        "SALVAR": "SAVE",
        "Mudou o servidor? Escaneie o QR de novo no iPhone.": "Changed the server? Scan the QR again on the iPhone.",
        "Endereço inválido": "Invalid address",
        "VERSÃO %@": "VERSION %@",
        "ATUALIZANDO…": "UPDATING…",
        "ATUALIZAR PARA %@": "UPDATE TO %@",
        "BUSCAR ATUALIZAÇÃO": "CHECK FOR UPDATE",
        "Fechar": "Close",
        "Voltar ao aparelho grande": "Back to the big device",
        "Fechar Mini": "Close Mini",

        // Mac: guia de primeiros passos
        "PRIMEIROS PASSOS": "GETTING STARTED",
        "PULAR": "SKIP",
        "VOLTAR": "BACK",
        "AVANÇAR": "NEXT",
        "COMEÇAR": "START",
        "NENHUM": "NONE",
        "baixa o app": "get the app",
        "código no relógio": "code on the watch",
        "precisa de Xcode": "needs Xcode",
        "só neste Mac": "this Mac only",
        "oi": "hi",
        "Conecte uma vez. Depois, é só usar o Claude Code normalmente.": "Connect once. Then just use Claude Code as usual.",
        "Recebendo os números": "Receiving the numbers",
        "Conectado. Mande uma mensagem no Claude Code…": "Connected. Send a message in Claude Code…",
        "Pulado": "Skipped",
        "NÃO USO": "I DON'T USE IT",
        "LENDO PELO LOGIN (VS CODE) · DESLIGAR": "READING THROUGH THE LOGIN (VS CODE) · TURN OFF",
        "USA O CLAUDE NO PAINEL DO VS CODE? TOQUE AQUI": "USE CLAUDE IN THE VS CODE PANEL? CLICK HERE",
        "Nada a configurar: use o Codex e os limites aparecem.": "Nothing to set up: use Codex and the limits show up.",
        "Esperando a primeira resposta do Codex…": "Waiting for the first Codex reply…",
        "1 · BAIXE O APP": "1 · GET THE APP",
        "2 · PAREIE": "2 · PAIR",
        "Aponte a câmera do celular e instale o arquivo.": "Point the phone camera here and install the file.",
        "No app, toque em ESCANEAR QR.": "In the app, tap SCAN QR.",
        "Instalou? Toque em AVANÇAR para parear.": "Installed? Click NEXT to pair.",
        "Precisa do app instalado pelo Xcode. Depois: ESCANEAR QR no app.": "Needs the app installed through Xcode. Then: SCAN QR in the app.",
        "O app de iPhone é instalado pelo Xcode: ver como": "The iPhone app is installed through Xcode: see how",
        "Digite este código no relógio. Com celular Android, ele recebe sozinho.": "Enter this code on the watch. With an Android phone, it gets it on its own.",
        "Vem junto com o app do iPhone (Xcode): pareie o iPhone e pronto.": "Comes with the iPhone app (Xcode): pair the iPhone and you're done.",
        "SEM CELULAR": "NO PHONE",
        "Tudo certo: os números ficam na barra de menu deste Mac.": "All set: the numbers live in this Mac's menu bar.",
        "Pronto": "Done",
        "PRONTO": "DONE",
        "Clique nas barrinhas da barra de menu. Arraste o display para trocar de IA.": "Click the little bars in the menu bar. Drag the display to switch AI.",
        "? = ver de novo": "? = see this again",
        "Mini = sempre na frente": "Mini = always on top",
        "Widgets: botão direito na mesa": "Widgets: right-click the desktop",
        "Aparelho conectado": "Device connected",
        "Esperando o aparelho (mesmo Wi-Fi)…": "Waiting for the device (same Wi-Fi)…",

        // Mac: erros
        "O pacote baixado não tem o TokenBar.app.": "The downloaded package has no TokenBar.app.",
        "A assinatura da atualização não confere. Nada foi trocado.": "The update's signature doesn't match. Nothing was replaced.",
        "Não consegui ler a assinatura deste app.": "Couldn't read this app's signature.",
        "Este app não tem assinatura de time; atualize pelo comando do README.": "This app has no team signature; update with the README command.",
        "Falhou: %@": "Failed: %@",
        "Não achei o login do Claude Code neste Mac (ou o acesso às Chaves foi negado).": "Couldn't find the Claude Code login on this Mac (or Keychain access was denied).",
        "Login do Claude expirado: abra o Claude Code uma vez.": "Claude login expired: open Claude Code once.",
        "A Anthropic respondeu %d.": "Anthropic responded %d.",
        "Resposta inesperada da Anthropic.": "Unexpected response from Anthropic.",
        "Não consegui editar o settings.json com segurança": "Couldn't edit settings.json safely",

        // Erros de rede (iPhone, relógio)
        "Servidor respondeu %d": "Server responded %d",
        "Nenhum dado enviado ainda pelo Mac": "The Mac hasn't sent any data yet",
        "Sem servidor configurado": "No server configured",
        "Mac não encontrado no Wi-Fi": "Mac not found on Wi-Fi",
        "O Mac recusou a chave (pareie de novo)": "The Mac rejected the key (pair again)",
        "Resposta inválida do Mac": "Invalid response from the Mac",
        "Link de pareamento inválido": "Invalid pairing link",

        // Aparelho (letreiro de LED e teclas): curto, só letras A–Z, números e % : . - / +
        "SEM DADOS": "NO DATA",
        "RESETOU": "RESET DONE",
        "NOVO": "NEW",
        "EDITAR": "EDIT",
        "TODOS": "ALL",
        "Destacar: janelinha flutuante, sempre na frente": "Pop out: small floating window, always on top",

        // Aparência
        "TEXTO": "TEXT",
        "TEMPO": "TIME",
        "CONTADOR": "TIMER",
        "PONTOS": "DOTS",
        "Pontos": "Dots",
        "Redondos": "Round",
        "Quadrados": "Square",
        "BRILHO": "GLOW",
        "Vermelho a partir de 85%": "Red from 85%",
        "Cor pelo uso (verde → vermelho)": "Color by usage (green → red)",
        "Cor muda com o uso (verde → amarelo → vermelho)": "Color follows usage (green → yellow → red)",
        "Restaurar padrão": "Restore defaults",
        "RESTAURAR PADRÃO": "RESTORE DEFAULTS",
        "Mais ajustes…": "More settings…",
        "Formato dos pontos": "Dot shape",
        "Outra cor": "Other color",

        // Detalhes
        "AO VIVO": "LIVE",
        "HÁ %d MIN": "%d MIN AGO",
        "HÁ %d H": "%d H AGO",
        "HÁ %d D": "%d D AGO",

        // Avisos
        "Quase no limite.": "Almost at the limit.",
        "Passou de %d%% do limite.": "Over %d%% of the limit.",
        "%@ liberado": "%@ available again",
        "O limite resetou.": "The limit has reset.",

        // iPhone
        "TOQUE PARA CONECTAR AO COMPUTADOR": "TAP TO CONNECT TO THE COMPUTER",
        "Ainda não está conectado ao computador.": "Not connected to the computer yet.",
        "VER COMO CONECTAR": "SEE HOW TO CONNECT",
        "OU COLE O LINK": "OR PASTE THE LINK",
        "PAREAR": "PAIR",
        "NÃO CONSEGUI LER O COMPUTADOR": "COULDN'T READ THE COMPUTER",
        "O TOKENBAR ESTÁ ABERTO?": "IS TOKENBAR OPEN?",
        "O computador precisa estar ligado, com o TokenBar aberto.": "The computer must be on, with TokenBar open.",
        "MESMO WI-FI?": "SAME WI-FI?",
        "Sem o servidor opcional, o iPhone só lê o computador na mesma rede.": "Without the optional server, the iPhone only reads the computer on the same network.",
        "REDE LOCAL LIGADA?": "LOCAL NETWORK ON?",
        "Ajustes → Privacidade e Segurança → Rede Local → TokenBar.": "Settings → Privacy & Security → Local Network → TokenBar.",
        "FIREWALL": "FIREWALL",
        "No Mac, permita conexões de entrada para o TokenBar.": "On the Mac, allow incoming connections for TokenBar.",
        "AINDA NÃO?": "STILL NOTHING?",
        "Toque em DESPAREAR lá embaixo e escaneie o QR de novo.": "Tap UNPAIR at the bottom and scan the QR again.",
        "TENTAR DE NOVO": "TRY AGAIN",
        "VER TUTORIAL": "SEE TUTORIAL",
        "DESPAREAR": "UNPAIR",

        // iPhone: guia
        "PRIMEIROS PASSOS  %d/%d": "GETTING STARTED  %d/%d",
        "FECHAR": "CLOSE",
        "INSTALE NO COMPUTADOR": "INSTALL ON THE COMPUTER",
        "ABRA O GUIA NELE": "OPEN ITS GUIDE",
        "ESCANEIE O QR": "SCAN THE QR",
        "MESMO WI-FI": "SAME WI-FI",
        "Mac, Windows ou Linux: é o computador que lê os limites das IAs.": "Mac, Windows or Linux: the computer reads your AI limits.",
        "No TokenBar do computador: Primeiros passos → Celular e relógio → IPHONE.": "In TokenBar on the computer: Getting started → Phone & watch → IPHONE.",
        "Aponte o iPhone para o QR que aparece no computador.": "Point the iPhone at the QR shown on the computer.",
        "iPhone e computador na mesma rede. Quando pedir, permita a Rede Local.": "iPhone and computer on the same network. When asked, allow Local Network.",
        "ABRIR O SITE": "OPEN THE SITE",
        "ESCANEAR QR": "SCAN QR",
        "Use a Câmera do iPhone e toque em Abrir no TokenBar.": "Use the iPhone Camera and tap Open in TokenBar.",
        "ou cole o link": "or paste the link",
        "ENTENDI": "GOT IT",

        // Apple Watch
        "1. Instale o TokenBar no computador.\n2. Pareie o iPhone: Câmera → QR do computador.\n3. O relógio recebe sozinho.": "1. Install TokenBar on the computer.\n2. Pair the iPhone: Camera → the computer's QR.\n3. The watch gets it on its own.",

        // Widgets e Central de Controle
        "Personalizado": "Custom",
        "Escolha a IA e a janela (segure o widget → Editar).": "Choose the AI and the window (hold the widget → Edit).",
        "Claude · 5h e 7d": "Claude · 5h and 7d",
        "Codex · 5h e 7d": "Codex · 5h and 7d",
        "Todas · 5h": "All · 5h",
        "Todas · 7d": "All · 7d",
        "Todas · 5h e 7d": "All · 5h and 7d",
        "Claude · 5h": "Claude · 5h",
        "Codex · 5h": "Codex · 5h",
        "As duas janelas do Claude Code.": "Both Claude Code windows.",
        "As duas janelas do Codex.": "Both Codex windows.",
        "Todas as IAs, janela de 5 horas.": "All AIs, 5-hour window.",
        "Todas as IAs, as duas janelas.": "All AIs, both windows.",
        "Sem dados ainda": "No data yet",
        "Abra o TokenBar para parear": "Open TokenBar to pair",
        "Sem dados": "No data",
        "abra o TokenBar": "open TokenBar",
        "Quanto já foi gasto de cada IA.": "How much of each AI you've used.",
        "Uso do Claude Code.": "Claude Code usage.",
        "Uso do Codex.": "Codex usage.",
        "Flutuante": "Floating",
        "TokenBar flutuante": "TokenBar floating",
        "Abre o TokenBar pequeno, sempre na frente.": "Opens the small TokenBar, always on top.",
        "TokenBar aparelho": "TokenBar device",
        "Abre o aparelho grande.": "Opens the big device.",
        // GitHub Copilot (Mac)
        "Lê a cota mensal de premium requests usando o login do GitHub CLI (gh) ou do Copilot. O token só vai para o GitHub.": "Reads the monthly premium-request quota using the GitHub CLI (gh) or Copilot login. The token only goes to GitHub.",
        "Não achei o login do GitHub (gh auth login) nem do Copilot neste computador.": "Couldn't find a GitHub (gh auth login) or Copilot login on this computer.",
        "Login do GitHub expirado: rode gh auth login.": "GitHub login expired: run gh auth login.",
        "O GitHub respondeu %d.": "GitHub responded %d.",
        "Lê o uso do mês do plano usando o login que o Cursor já guardou neste computador. O token só vai para cursor.com.": "Reads the plan's monthly usage using the login Cursor already saved on this computer. The token only goes to cursor.com.",
        "Coding Plan do GLM: limites de 5 horas e da semana. Crie uma chave de API em z.ai (ou open.bigmodel.cn) e cole aqui. A chave só vai para a Z.ai.": "GLM Coding Plan: 5-hour and weekly limits. Create an API key at z.ai (or open.bigmodel.cn) and paste it here. The key only goes to Z.ai.",
        "Coding Plan da MiniMax: janela atual e semana. Cole a chave do Coding Plan (sk-cp-…). A chave só vai para a MiniMax.": "MiniMax Coding Plan: current window and week. Paste your Coding Plan key (sk-cp-…). The key only goes to MiniMax.",
        "Kimi Code: limites de 5 horas e da semana. Crie uma chave no console do Kimi Code e cole aqui. A chave só vai para a Kimi.": "Kimi Code: 5-hour and weekly limits. Create a key in the Kimi Code console and paste it here. The key only goes to Kimi.",
        "Quanto do limite da chave (ou dos créditos) já foi gasto. Cole uma chave de openrouter.ai/keys. A chave só vai para o OpenRouter.": "How much of the key's limit (or of your credits) is spent. Paste a key from openrouter.ai/keys. The key only goes to OpenRouter.",
        "Limites de 5 horas e da semana do Droid. Cole a chave de app.factory.ai/settings/api-keys (ou deixe em ~/.factory/.env). A chave só vai para a Factory.": "Droid's 5-hour and weekly limits. Paste a key from app.factory.ai/settings/api-keys (or keep it in ~/.factory/.env). The key only goes to Factory.",
        "Não achei o login do Cursor neste computador: abra o Cursor e entre na conta.": "Couldn't find a Cursor login on this computer: open Cursor and sign in.",
        "Login do Cursor expirado: abra o Cursor uma vez.": "Cursor login expired: open Cursor once.",
        "Falta a chave de API.": "The API key is missing.",
        "%@ recusou a chave.": "%@ rejected the key.",
        "%@ respondeu %d.": "%@ responded %d.",
        "Resposta inesperada de %@.": "Unexpected response from %@.",
        "Sem conexão com %@.": "Can't reach %@.",
        "REMOVER": "REMOVE",
        "CHAVE": "KEY",
        "vazio = usar ~/.factory/.env": "empty = use ~/.factory/.env",
        "cole a chave de API": "paste the API key",
        "Resposta inesperada do GitHub.": "Unexpected response from GitHub.",
        // Atividade ao Vivo (iPhone)
        "DYNAMIC ISLAND / TELA BLOQUEADA": "DYNAMIC ISLAND / LOCK SCREEN",
        "MOSTRAR O USO": "SHOW USAGE",
        "As Atividades ao Vivo estão desligadas nos Ajustes do iPhone (Ajustes → TokenBar).": "Live Activities are turned off in iPhone Settings (Settings → TokenBar).",
        "Aparece depois de conectar ao computador.": "Shows up after you connect to the computer.",
        "A % de cada IA e a contagem até zerar, sem abrir o app.": "Each AI's % and the countdown to reset, without opening the app.",
        "IA": "AI",
        "JANELA": "WINDOW",
        "TODAS": "ALL",
        "AMBAS": "BOTH",
        "Trocar a IA": "Switch AI",
        "Trocar a janela": "Switch window",
        // Ilha no notch (Mac)
        "ILHA NO NOTCH": "NOTCH ISLAND",
        "Uma pílula preta em volta da câmera com a % de cada IA; passe o mouse para abrir.": "A black pill around the camera with each AI's %; hover to open it.",
        "Abrir o aparelho": "Open the device",
        // API local e webhook (Mac)
        "API LOCAL": "LOCAL API",
        "Outros apps e scripts neste Mac leem os números em http://localhost:41777/v1/usage. Só este computador acessa.": "Other apps and scripts on this Mac read the numbers at http://localhost:41777/v1/usage. Only this computer has access.",
        "PORTA OCUPADA": "PORT BUSY",
        "LIGANDO": "STARTING",
        "Avisa um endereço quando uma IA passa de 80% ou 95% e quando o limite reseta. Slack e Discord recebem uma frase; outros endereços, o JSON completo.": "Pings a URL when an AI passes 80% or 95% and when the limit resets. Slack and Discord get a sentence; other URLs get the full JSON.",
        "TESTAR": "TEST",
        "ÚLTIMO ENVIO: %@": "LAST SENT: %@",
        "NENHUM ENVIO AINDA": "NOTHING SENT YET",
        "AVISAR EM": "NOTIFY AT",
        "%@ %@ passou de %d%% (%d%%). Reseta em %@.": "%@ %@ passed %d%% (%d%%). Resets in %@.",
        "%@ %@ passou de %d%% (%d%%).": "%@ %@ passed %d%% (%d%%).",
        "%@ %@ resetou: voltou a 0%%.": "%@ %@ reset: back to 0%%.",
        "Teste do TokenBar: o webhook está funcionando.": "TokenBar test: the webhook is working.",
    ]
}

/// A escolha de idioma, observável: toda tela que chamou `Lang.t` redesenha na hora quando muda.
@Observable
final class LangStore {
    static let shared = LangStore()

    /// "auto" | "pt" | "en".
    var lang: String {
        didSet {
            guard lang != oldValue else { return }
            TB.defaults.set(lang, forKey: Lang.key)
            WidgetCenter.shared.reloadAllTimelines()
            #if !os(watchOS)
            if #available(iOS 18.0, macOS 26.0, *) { ControlCenter.shared.reloadAllControls() }
            #endif
        }
    }

    private init() {
        var value = TB.defaults.string(forKey: Lang.key) ?? "auto"
        #if DEBUG
        // -lang en / -lang pt: abre já no idioma (capturas de tela), sem gravar a escolha.
        if let arg = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)[Lang.key] as? String {
            value = arg
        }
        #endif
        lang = ["auto", "pt", "en"].contains(value) ? value : "auto"
    }
}

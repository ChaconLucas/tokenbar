// Idioma da interface. O português é a chave: t("Sair") → "Quit" em inglês; sem tradução, fica o português.
// No HTML: data-t troca o conteúdo do elemento; data-t-attr="title placeholder" troca esses atributos.

const EN = {
  // ajustes
  "AJUSTES": "SETTINGS",
  "FECHAR": "CLOSE",
  "PRIMEIROS PASSOS": "GETTING STARTED",
  "CONECTAR CLAUDE CODE": "CONNECT CLAUDE CODE",
  "DESCONECTAR": "DISCONNECT",
  "LIGAR": "TURN ON",
  "Lendo pelo login…": "Reading from the login…",
  "Claude sem números. Usa no painel do VS Code?": "No Claude numbers. Using the VS Code panel?",
  "DESCONECTAR APARELHOS": "DISCONNECT DEVICES",
  "Desconectar todos os celulares e relógios? Eles vão precisar escanear o QR de novo.": "Disconnect all phones and watches? They will need to scan the QR again.",
  "Minimizar": "Minimize",
  "Fechar (continua na bandeja; Sair no ícone)": "Close (keeps running in the tray; Quit from the icon)",
  "Ler pelo login do Claude Code (para quem usa o painel do VS Code)": "Read from the Claude Code login (for the VS Code panel)",
  "Usa a chave que o Claude Code já guardou; ela não sai deste computador.": "Uses the key Claude Code already saved; it never leaves this computer.",
  "CELULAR E RELÓGIO": "PHONE & WATCH",
  "Aponte a câmera do celular para o código (app TokenBar → Escanear QR).": "Point your phone's camera at the code (TokenBar app → Scan QR).",
  "COPIAR LINK": "COPY LINK",
  "Quem tem o código vê os seus números. Não publique.": "Anyone with this code sees your numbers. Keep it private.",
  "RELÓGIO SEM CELULAR (WEAR OS)": "WATCH WITHOUT A PHONE (WEAR OS)",
  "digite no relógio (mesmo Wi-Fi). Vale uma vez e troca a cada 10 min.": "type it on the watch (same Wi-Fi). Works once and changes every 10 min.",
  "SERVIDOR (OPCIONAL)": "SERVER (OPTIONAL)",
  "Para ver fora de casa. Deixe vazio para usar só o Wi-Fi.": "To check away from home. Leave empty to use Wi-Fi only.",
  "https://tokenbar.sua-conta.workers.dev": "https://tokenbar.your-account.workers.dev",
  "SALVAR": "SAVE",
  "OUTRAS IAS": "OTHER AIS",
  "Ler a cota do GitHub Copilot": "Read the GitHub Copilot quota",
  "Lê a cota mensal de premium requests usando o login do GitHub CLI (gh) ou do Copilot. O token só vai para o GitHub.":
    "Reads the monthly premium-request quota using the GitHub CLI (gh) or Copilot login. The token only goes to GitHub.",
  "O Windsurf aparece sozinho quando está instalado.": "Windsurf shows up on its own when it's installed.",
  "Qualquer IA aparece aqui ao gravar um arquivo em <code>~/.tokenbar/providers/</code> (veja docs/providers.md no GitHub).":
    "Any AI shows up here when it writes a file to <code>~/.tokenbar/providers/</code> (see docs/providers.md on GitHub).",
  "VERSÃO": "VERSION",
  "BUSCAR ATUALIZAÇÃO": "CHECK FOR UPDATES",
  "Conectado pela statusline. Os números chegam enquanto alguma sessão do Claude Code estiver aberta.":
    "Connected through the statusline. Numbers arrive while a Claude Code session is open.",
  "O Claude Code só entrega os limites para a statusline. O TokenBar lê essa cópia e mantém a sua statusline atual.":
    "Claude Code only shares its limits with the statusline. TokenBar reads that copy and keeps your current statusline.",
  "Erro ao enviar: {0}": "Couldn't send: {0}",
  "Erro: {0}": "Error: {0}",
  "Salvo. Escaneie o QR de novo no celular.": "Saved. Scan the QR again on your phone.",
  "ATUALIZAR PARA {0}": "UPDATE TO {0}",
  "Atualizar para {0}": "Update to {0}",
  "Baixando…": "Downloading…",
  "Buscando…": "Checking…",
  "Versão {0} disponível.": "Version {0} available.",
  "Já está na versão mais nova.": "You're on the latest version.",
  // teclas do aparelho
  "Voltar ao aparelho grande": "Back to the full device",
  "Fechar": "Close",
  "Flutuante: pequeno, sempre na frente": "Floating: small, always on top",
  "Primeiros passos": "Getting started",
  "Ajustes": "Settings",
  "BAIXANDO": "UPDATING",
  "ERRO": "ERROR",
  "ATUALIZAR": "UPDATE",
  "SEM DADOS": "NO DATA",
  // guia
  "PULAR": "SKIP",
  "Pular (Esc)": "Skip (Esc)",
  "› oi": "› hi",
  "● Oi! Em que posso ajudar?": "● Hi! How can I help?",
  "◇ limites": "◇ limits",
  "› Olá! O que vamos fazer?": "› Hi! What are we building?",
  "Conecte e mande um “oi” no Claude Code.": "Connect, then say “hi” in Claude Code.",
  "✓ CONECTADO": "✓ CONNECTED",
  "Não uso": "I don't use it",
  "USO NO PAINEL DO VS CODE": "I USE THE VS CODE PANEL",
  "Use o Codex uma vez. Os números chegam sozinhos.": "Use Codex once. The numbers arrive on their own.",
  "Outras IAs: docs/providers.md": "Other AIs: docs/providers.md",
  "CELULAR": "PHONE & WATCH",
  "Escolha o aparelho e aponte a câmera.": "Pick your device and point the camera.",
  "baixa o app": "get the app",
  "código no relógio": "code on the watch",
  "precisa de Xcode": "needs Xcode",
  "NENHUM": "NONE",
  "só neste PC": "this PC only",
  "<b>1</b> BAIXAR O APP": "<b>1</b> GET THE APP",
  "<b>2</b> PAREAR · ESCANEAR QR no app": "<b>2</b> PAIR · SCAN QR in the app",
  "Instalou? Toque em AVANÇAR para parear.": "Installed? Tap NEXT to pair.",
  "PAREAR": "PAIR",
  "Precisa do app instalado pelo Xcode (veja INSTALL.md).": "Needs the app installed with Xcode (see INSTALL.md).",
  "Digite no relógio.": "Type it on the watch.",
  "Vem com o app do iPhone.": "Comes with the iPhone app.",
  "Sem celular: os números ficam neste computador.": "No phone: the numbers stay on this computer.",
  "Se pedir permissão de rede/firewall, permita.": "If asked for network/firewall access, allow it.",
  "PRONTO": "ALL SET",
  "✓ Tudo certo": "✓ Done",
  "O TokenBar fica na bandeja, sempre à mão.": "TokenBar lives in the tray, always at hand.",
  "<b>◎</b> Clique no anel = aparelho": "<b>◎</b> Click the ring = device",
  "<b>⇆</b> Arraste = troca de IA": "<b>⇆</b> Drag = switch AI",
  "<b>?</b> = ver de novo": "<b>?</b> = show again",
  "← VOLTAR": "← BACK",
  "AVANÇAR →": "NEXT →",
  "COMEÇAR": "START",
  "✓ Recebendo números": "✓ Receiving numbers",
  "Pulado": "Skipped",
  "Esperando o “oi”…": "Waiting for your “hi”…",
  "Esperando…": "Waiting…",
  "Lendo pelo login ✓": "Reading via login ✓",
  "✓ Só neste computador": "✓ This computer only",
  "Escolha um aparelho": "Pick a device",
  "✓ Relógio conectado": "✓ Watch connected",
  "Esperando o relógio… (mesmo Wi-Fi)": "Waiting for the watch… (same Wi-Fi)",
  "✓ Celular conectado": "✓ Phone connected",
  "Esperando o celular… (mesmo Wi-Fi)": "Waiting for the phone… (same Wi-Fi)",
};

let lang = /^pt/i.test(navigator.language || "") ? "pt" : "en";
/** Chaves sem tradução vistas em inglês (para conferir). */
export const missing = new Set();

export const getLang = () => lang;
export function setLang(l) {
  lang = l === "en" ? "en" : "pt";
  document.documentElement.lang = lang === "en" ? "en" : "pt-BR";
}
export function t(pt) {
  if (lang !== "en") return pt;
  if (pt in EN) return EN[pt];
  missing.add(pt); return pt;
}
/** f("Versão {0} disponível.", v) */
export const f = (fmt, ...args) => t(fmt).replace(/\{(\d+)\}/g, (_, i) => args[i]);

/** Reescreve o HTML marcado. O texto original (português) fica guardado no próprio elemento. */
export function applyLang(root = document) {
  root.querySelectorAll("[data-t]").forEach((el) => {
    if (el._pt == null) el._pt = el.innerHTML.trim();
    const v = t(el._pt);
    if (el.innerHTML !== v) el.innerHTML = v;
  });
  root.querySelectorAll("[data-t-attr]").forEach((el) => {
    el._ptAttr ||= {};
    for (const a of el.dataset.tAttr.split(" ")) {
      if (!(a in el._ptAttr)) el._ptAttr[a] = el.getAttribute(a) || "";
      el.setAttribute(a, t(el._ptAttr[a]));
    }
  });
}

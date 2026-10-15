// English by default; Portuguese when VS Code runs in pt / pt-BR.
const PT: Record<string, string> = {
  "No AI usage data yet": "Ainda sem dados de uso das IAs",
  "Install the TokenBar app, or use Claude Code / Codex once, so the limits show up here.":
    "Instale o app TokenBar, ou use o Claude Code / Codex uma vez, para os limites aparecerem aqui.",
  "resets in {0}": "zera em {0}",
  "reset": "zerou",
  "no reset time": "sem horário de reset",
  "read {0} ago": "lido há {0}",
  "read just now": "lido agora",
  "Source: TokenBar app": "Fonte: app TokenBar",
  "Source: local files": "Fonte: arquivos locais",
  "Click: switch window ({0})": "Clique: trocar janela ({0})",
  "Show details": "Ver detalhes",
  "Open TokenBar app": "Abrir app TokenBar",
  "Window": "Janela",
  "both": "ambas",
  "NO DATA": "SEM DADOS",
  "TokenBar — AI usage": "TokenBar — uso das IAs",
};

let pt = false;
export function setLanguage(lang: string) { pt = lang.toLowerCase().startsWith("pt"); }
export function t(key: string, ...args: string[]) {
  const s = (pt && PT[key]) || key;
  return args.reduce((acc, a, i) => acc.replace(`{${i}}`, a), s);
}

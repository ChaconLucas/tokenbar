import * as vscode from "vscode";
import * as fs from "fs";
import * as path from "path";
import * as os from "os";
import { execFile } from "child_process";
import {
  Snapshot, Provider, UsageWindow, collect, usedNow, colorOf, abbrOf,
  tokenbarDir, providersDir, recentCodexFiles,
} from "./data";
import { t, setLanguage } from "./i18n";

type WindowChoice = "5h" | "7d" | "both";
type StatusStyle = "dots" | "compact";
const REPO = "https://github.com/ChaconLucas/tokenbar";
const WARN_AT = 85;
const ERROR_AT = 95;
const REFRESH_MS = 30_000;
const PRIORITY = 100;
const VIEW_ID = "tokenbar.usage";
const CONTAINER_CMD = "workbench.view.extension.tokenbar";

/** Status bar items, keyed by provider id ("" = the single compact / empty item). */
const items = new Map<string, vscode.StatusBarItem>();
let snapshot: Snapshot | undefined;
let usageView: UsageViewProvider | undefined;
const watchers = new Map<string, fs.FSWatcher>();
let debounce: NodeJS.Timeout | undefined;
let refreshing = false;

const cfg = () => vscode.workspace.getConfiguration("tokenbar");
const windowChoice = (): WindowChoice => {
  const v = cfg().get<string>("window", "5h");
  return v === "7d" || v === "both" ? v : "5h";
};
const statusStyle = (): StatusStyle => (cfg().get<string>("statusStyle", "dots") === "compact" ? "compact" : "dots");

function visibleProviders(): Provider[] {
  const all = snapshot?.providers ?? [];
  const only = cfg().get<string[]>("providers", []).filter(Boolean);
  return only.length ? all.filter((p) => only.includes(p.id)) : all;
}

/** First window = the short one (5h), second = the long one (7d). */
const shortW = (p: Provider) => p.windows[0];
const longW = (p: Provider) => p.windows[1];
/** The windows the status bar shows for one AI under the current choice. */
const shownWindows = (p: Provider, choice: WindowChoice): (UsageWindow | undefined)[] =>
  choice === "7d" ? [longW(p) ?? shortW(p)] : choice === "both" && longW(p) ? [shortW(p), longW(p)] : [shortW(p)];

function duration(sec: number): string {
  const s = Math.max(0, Math.floor(sec));
  const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60);
  if (d > 0) return `${d}d ${h}h`;
  if (h > 0) return `${h}h ${m}m`;
  return `${Math.max(m, s > 0 ? 1 : 0)}m`;
}

/** Compact countdown for the status bar: "4:12" under a day, "5d" beyond. */
function countdown(w: UsageWindow | undefined, now = Date.now() / 1000): string | undefined {
  if (!w?.resetsAt || w.resetsAt <= now) return undefined;
  const s = Math.floor(w.resetsAt - now);
  if (s >= 86400) return `${Math.floor(s / 86400)}d`;
  return `${Math.floor(s / 3600)}:${String(Math.floor((s % 3600) / 60)).padStart(2, "0")}`;
}

function resetText(w: UsageWindow, now: number): string {
  if (w.resetsAt === undefined) return t("no reset time");
  if (w.resetsAt <= now) return t("reset");
  return t("resets in {0}", duration(w.resetsAt - now));
}

const pct = (w: UsageWindow | undefined) => `${Math.round(usedNow(w))}%`;

/** "●●●○○○○○○○": lit dots = used. Any usage lights at least one dot. */
function dots(used: number, n: number): string {
  const lit = used <= 0 ? 0 : Math.min(n, Math.max(1, Math.round((used / 100) * n)));
  return "●".repeat(lit) + "○".repeat(n - lit);
}

function getItem(key: string, priority: number, name: string): vscode.StatusBarItem {
  let it = items.get(key);
  if (!it) {
    it = vscode.window.createStatusBarItem(key ? `tokenbar.status.${key}` : "tokenbar.status", vscode.StatusBarAlignment.Right, priority);
    it.command = "tokenbar.toggleWindow";
    items.set(key, it);
  }
  it.name = name;
  return it;
}

function dropItemsExcept(keep: Set<string>) {
  for (const [k, it] of items) if (!keep.has(k)) { it.dispose(); items.delete(k); }
}

const heat = (used: number) =>
  used >= ERROR_AT ? new vscode.ThemeColor("statusBarItem.errorBackground")
  : used >= WARN_AT ? new vscode.ThemeColor("statusBarItem.warningBackground")
  : undefined;

function render() {
  const providers = visibleProviders();
  const choice = windowChoice();
  postToView();

  if (!providers.length) {
    dropItemsExcept(new Set([""]));
    const it = getItem("", PRIORITY, "TokenBar");
    it.text = "$(pulse) TokenBar";
    it.color = undefined;
    it.backgroundColor = undefined;
    it.tooltip = new vscode.MarkdownString(`**${t("No AI usage data yet")}**\n\n${t("Install the TokenBar app, or use Claude Code / Codex once, so the limits show up here.")}`);
    it.show();
    return;
  }

  const tip = tooltip(providers, choice);

  if (statusStyle() === "compact") {
    dropItemsExcept(new Set([""]));
    const it = getItem("", PRIORITY, "TokenBar");
    const parts = providers.map((p) => {
      const s = shortW(p), l = longW(p);
      if (choice === "7d") return `${abbrOf(p)} ${pct(l ?? s)}`;
      if (choice === "both" && l) return `${abbrOf(p)} ${Math.round(usedNow(s))}/${pct(l)}`;
      return `${abbrOf(p)} ${pct(s)}`;
    });
    it.text = `$(pulse) ${parts.join(" · ")}`;
    it.color = undefined;
    const hot = Math.max(...providers.flatMap((p) => p.windows.map((w) => usedNow(w))));
    it.backgroundColor = hot >= WARN_AT ? new vscode.ThemeColor("statusBarItem.warningBackground") : undefined;
    it.tooltip = tip;
    it.show();
    return;
  }

  // "dots": one item per AI, in the AI's color, grouped on the right in the providers' order.
  dropItemsExcept(new Set(providers.map((p) => p.id)));
  providers.forEach((p, i) => {
    const it = getItem(p.id, PRIORITY - i * 0.001, `TokenBar — ${p.name}`);
    const ws = shownWindows(p, choice);
    let text: string;
    if (ws.length > 1) {
      text = `${abbrOf(p)} ${ws.map((w) => `${dots(usedNow(w), 5)} ${Math.round(usedNow(w))}`).join(" · ")}`;
    } else {
      const w = ws[0];
      const cd = countdown(w);
      text = `${abbrOf(p)} ${dots(usedNow(w), 10)} ${pct(w)}${cd ? ` · ${cd}` : ""}`;
    }
    it.text = text;
    it.color = colorOf(p);
    it.backgroundColor = heat(Math.max(0, ...ws.map((w) => usedNow(w))));
    it.tooltip = tip;
    it.accessibilityInformation = {
      label: `${p.name}: ${ws.map((w) => `${w?.label || w?.id || ""} ${pct(w)}`).join(", ")}`,
    };
    it.show();
  });
}

function tooltip(providers: Provider[], choice: WindowChoice): vscode.MarkdownString {
  const now = Date.now() / 1000;
  const md = new vscode.MarkdownString("", true);
  md.isTrusted = { enabledCommands: ["tokenbar.showDetails", "tokenbar.openApp", "tokenbar.toggleWindow"] };
  md.supportHtml = true;
  md.appendMarkdown(`**${t("TokenBar — AI usage")}**\n\n`);
  for (const p of providers) {
    const age = p.observedAt ? now - p.observedAt : undefined;
    const read = age === undefined ? "" : age < 60 ? t("read just now") : t("read {0} ago", duration(age));
    md.appendMarkdown(`<span style="color:${colorOf(p)};">$(circle-filled)</span> **${escapeMd(p.name)}**`);
    if (read) md.appendMarkdown(` — _${read}_`);
    md.appendMarkdown("\n\n");
    for (const w of p.windows) {
      const warn = usedNow(w, now) >= WARN_AT ? " $(warning)" : "";
      md.appendMarkdown(`&nbsp;&nbsp;\`${escapeMd(w.label || w.id)}\` **${pct(w)}**${warn} · ${resetText(w, now)}\n\n`);
    }
  }
  const src = snapshot?.source === "snapshot" ? t("Source: TokenBar app") : t("Source: local files");
  const label = choice === "both" ? t("both") : choice;
  md.appendMarkdown(`---\n\n_${src}_ · ${t("Click: switch window ({0})", label)}\n\n`);
  md.appendMarkdown(`[$(graph) ${t("Show details")}](command:tokenbar.showDetails) · [$(link-external) ${t("Open TokenBar app")}](command:tokenbar.openApp)`);
  return md;
}

const escapeMd = (s: string) => s.replace(/[\\`*_{}[\]()#+\-.!|<>]/g, "\\$&");

// MARK: Refresh

async function refresh() {
  if (refreshing) return;
  refreshing = true;
  try {
    snapshot = await collect();
    await ensureWatchers();
  } catch {
    // keep the last good snapshot
  } finally {
    refreshing = false;
  }
  render();
}

function scheduleRefresh() {
  clearTimeout(debounce);
  debounce = setTimeout(refresh, 1000);
}

function watch(target: string) {
  if (watchers.has(target) || !fs.existsSync(target)) return;
  try {
    const w = fs.watch(target, { persistent: false }, scheduleRefresh);
    w.on("error", () => { w.close(); watchers.delete(target); });
    watchers.set(target, w);
  } catch { /* not watchable: the 30 s timer covers it */ }
}

/** Watches ~/.tokenbar, its providers folder and the newest Codex session (re-targeted as sessions change). */
let codexWatched: string | undefined;
async function ensureWatchers() {
  watch(tokenbarDir());
  watch(providersDir());
  if (snapshot?.source === "snapshot") return;
  const newest = (await recentCodexFiles(1))[0];
  if (newest !== codexWatched) {
    if (codexWatched) { watchers.get(codexWatched)?.close(); watchers.delete(codexWatched); }
    codexWatched = newest;
    if (newest) watch(newest);
  }
}

// MARK: Commands

async function setWindow(choice: WindowChoice) {
  await cfg().update("window", choice, vscode.ConfigurationTarget.Global);
}

async function toggleWindow() {
  const order: WindowChoice[] = ["5h", "7d", "both"];
  await setWindow(order[(order.indexOf(windowChoice()) + 1) % order.length]);
}

/** Shows / hides one AI (the `tokenbar.providers` setting); at least one stays visible. */
async function toggleProvider(id: string) {
  const all = (snapshot?.providers ?? []).map((p) => p.id);
  if (!all.includes(id)) return;
  const only = cfg().get<string[]>("providers", []).filter(Boolean);
  const current = only.length ? only : all;
  const next = current.includes(id) ? current.filter((x) => x !== id) : [...current, id];
  if (!all.some((x) => next.includes(x))) return;
  const value = all.every((x) => next.includes(x)) && next.every((x) => all.includes(x)) ? [] : next;
  await cfg().update("providers", value, vscode.ConfigurationTarget.Global);
}

function openApp() {
  const fallback = () => vscode.env.openExternal(vscode.Uri.parse(REPO));
  const candidates: string[] =
    process.platform === "darwin" ? ["/Applications/TokenBar.app", path.join(os.homedir(), "Applications", "TokenBar.app")]
    : process.platform === "win32" ? [
        path.join(process.env.LOCALAPPDATA ?? "", "TokenBar", "TokenBar.exe"),
        path.join(process.env.ProgramFiles ?? "C:\\Program Files", "TokenBar", "TokenBar.exe"),
      ]
    : ["/usr/bin/tokenbar", "/usr/local/bin/tokenbar", path.join(os.homedir(), ".local", "bin", "tokenbar")];
  const app = candidates.find((c) => c && fs.existsSync(c));
  if (!app) return fallback();
  const [cmd, args] = process.platform === "darwin" ? ["open", [app]] : [app, []];
  try {
    const child = execFile(cmd, args as string[], (err) => { if (err) fallback(); });
    child.unref();
  } catch { fallback(); }
}

async function showDetails() {
  try { await vscode.commands.executeCommand(`${VIEW_ID}.focus`); }
  catch { await vscode.commands.executeCommand(CONTAINER_CMD); }
}

// MARK: Usage view (Activity Bar → TokenBar → Usage)

class UsageViewProvider implements vscode.WebviewViewProvider {
  view?: vscode.WebviewView;
  constructor(private readonly media: vscode.Uri) {}

  resolveWebviewView(view: vscode.WebviewView) {
    this.view = view;
    const webview = view.webview;
    webview.options = { enableScripts: true, localResourceRoots: [this.media] };
    const uri = (f: string) => webview.asWebviewUri(vscode.Uri.joinPath(this.media, f)).toString();
    const nonce = [...Array(32)].map(() => Math.floor(Math.random() * 36).toString(36)).join("");
    const csp = `default-src 'none'; img-src ${webview.cspSource}; style-src ${webview.cspSource}; script-src 'nonce-${nonce}';`;
    webview.html = `<!doctype html>
<html><head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="${csp}">
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="stylesheet" href="${uri("panel.css")}">
<title>TokenBar</title></head>
<body><main id="root"></main>
<script nonce="${nonce}" src="${uri("glyphs.js")}"></script>
<script nonce="${nonce}" src="${uri("led.js")}"></script>
<script nonce="${nonce}" src="${uri("panel.js")}"></script>
</body></html>`;
    webview.onDidReceiveMessage((m) => {
      if (m?.type === "ready") postToView();
      if (m?.type === "openApp") openApp();
      if (m?.type === "refresh") refresh();
      if (m?.type === "setWindow" && ["5h", "7d", "both"].includes(m.choice)) setWindow(m.choice);
      if (m?.type === "toggleProvider" && typeof m.id === "string") toggleProvider(m.id);
    });
    view.onDidChangeVisibility(() => { if (view.visible) postToView(); });
    view.onDidDispose(() => { if (this.view === view) this.view = undefined; });
  }
}

function postToView() {
  const view = usageView?.view;
  if (!view) return;
  const visible = new Set(visibleProviders().map((p) => p.id));
  const providers = (snapshot?.providers ?? []).map((p) => ({
    id: p.id, name: p.name, abbr: abbrOf(p), color: colorOf(p), windows: p.windows,
    observedAt: p.observedAt, on: visible.has(p.id),
  }));
  view.webview.postMessage({
    type: "snapshot",
    providers,
    choice: windowChoice(),
    source: snapshot?.source,
    strings: {
      noData: t("NO DATA"), empty: t("No AI usage data yet"), openApp: t("Open TokenBar app"),
      hint: t("Install the TokenBar app, or use Claude Code / Codex once, so the limits show up here."),
      window: t("Switch window (5h / 7d / both)"), toggleAi: t("Show / hide {0}"),
    },
  });
}

// MARK: Lifecycle

export function activate(ctx: vscode.ExtensionContext) {
  setLanguage(vscode.env.language);
  const first = getItem("", PRIORITY, "TokenBar");
  first.text = "$(pulse) TokenBar";
  first.show();

  usageView = new UsageViewProvider(vscode.Uri.joinPath(ctx.extensionUri, "media"));
  ctx.subscriptions.push(
    vscode.window.registerWebviewViewProvider(VIEW_ID, usageView),
    vscode.commands.registerCommand("tokenbar.toggleWindow", toggleWindow),
    vscode.commands.registerCommand("tokenbar.showDetails", showDetails),
    vscode.commands.registerCommand("tokenbar.openApp", openApp),
    vscode.commands.registerCommand("tokenbar.refresh", refresh),
    vscode.workspace.onDidChangeConfiguration((e) => { if (e.affectsConfiguration("tokenbar")) render(); }),
    { dispose: () => { items.forEach((it) => it.dispose()); items.clear(); } },
    { dispose: () => { watchers.forEach((w) => w.close()); watchers.clear(); clearTimeout(debounce); } },
  );

  const timer = setInterval(refresh, REFRESH_MS); // also keeps the countdown text current
  ctx.subscriptions.push({ dispose: () => clearInterval(timer) });
  refresh();
}

export function deactivate() {}

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
const REPO = "https://github.com/ChaconLucas/tokenbar";
const WARN_AT = 85;
const REFRESH_MS = 30_000;

let item: vscode.StatusBarItem;
let snapshot: Snapshot | undefined;
let panel: vscode.WebviewPanel | undefined;
const watchers = new Map<string, fs.FSWatcher>();
let debounce: NodeJS.Timeout | undefined;
let refreshing = false;

const cfg = () => vscode.workspace.getConfiguration("tokenbar");
const windowChoice = (): WindowChoice => {
  const v = cfg().get<string>("window", "5h");
  return v === "7d" || v === "both" ? v : "5h";
};

function visibleProviders(): Provider[] {
  const all = snapshot?.providers ?? [];
  const only = cfg().get<string[]>("providers", []).filter(Boolean);
  return only.length ? all.filter((p) => only.includes(p.id)) : all;
}

/** First window = the short one (5h), second = the long one (7d). */
const shortW = (p: Provider) => p.windows[0];
const longW = (p: Provider) => p.windows[1];

function duration(sec: number): string {
  const s = Math.max(0, Math.floor(sec));
  const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60);
  if (d > 0) return `${d}d ${h}h`;
  if (h > 0) return `${h}h ${m}m`;
  return `${Math.max(m, s > 0 ? 1 : 0)}m`;
}

function resetText(w: UsageWindow, now: number): string {
  if (w.resetsAt === undefined) return t("no reset time");
  if (w.resetsAt <= now) return t("reset");
  return t("resets in {0}", duration(w.resetsAt - now));
}

const pct = (w: UsageWindow | undefined) => `${Math.round(usedNow(w))}%`;

function render() {
  const providers = visibleProviders();
  const choice = windowChoice();
  if (!providers.length) {
    item.text = "$(pulse) TokenBar";
    item.backgroundColor = undefined;
    item.tooltip = new vscode.MarkdownString(`**${t("No AI usage data yet")}**\n\n${t("Install the TokenBar app, or use Claude Code / Codex once, so the limits show up here.")}`);
    item.show();
    return;
  }

  const parts = providers.map((p) => {
    const s = shortW(p), l = longW(p);
    if (choice === "7d") return `${abbrOf(p)} ${pct(l ?? s)}`;
    if (choice === "both" && l) return `${abbrOf(p)} ${Math.round(usedNow(s))}/${pct(l)}`;
    return `${abbrOf(p)} ${pct(s)}`;
  });
  item.text = `$(pulse) ${parts.join(" · ")}`;

  const hot = providers.some((p) => p.windows.some((w) => usedNow(w) >= WARN_AT));
  item.backgroundColor = hot ? new vscode.ThemeColor("statusBarItem.warningBackground") : undefined;
  item.tooltip = tooltip(providers, choice);
  item.show();
  postToPanel();
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

async function toggleWindow() {
  const order: WindowChoice[] = ["5h", "7d", "both"];
  const next = order[(order.indexOf(windowChoice()) + 1) % order.length];
  await cfg().update("window", next, vscode.ConfigurationTarget.Global);
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

function showDetails(ctx: vscode.ExtensionContext) {
  if (panel) { panel.reveal(); return; }
  const media = vscode.Uri.joinPath(ctx.extensionUri, "media");
  panel = vscode.window.createWebviewPanel("tokenbar.details", "TokenBar", vscode.ViewColumn.Active, {
    enableScripts: true,
    localResourceRoots: [media],
  });
  panel.iconPath = vscode.Uri.joinPath(media, "icon.png");
  const uri = (f: string) => panel!.webview.asWebviewUri(vscode.Uri.joinPath(media, f)).toString();
  const nonce = [...Array(32)].map(() => Math.floor(Math.random() * 36).toString(36)).join("");
  const csp = `default-src 'none'; img-src ${panel.webview.cspSource}; style-src ${panel.webview.cspSource} 'unsafe-inline'; script-src 'nonce-${nonce}';`;
  panel.webview.html = `<!doctype html>
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
  panel.webview.onDidReceiveMessage((m) => {
    if (m?.type === "ready") postToPanel();
    if (m?.type === "openApp") openApp();
  });
  panel.onDidDispose(() => { panel = undefined; });
}

function postToPanel() {
  if (!panel) return;
  const providers = visibleProviders().map((p) => ({
    id: p.id, name: p.name, color: colorOf(p), windows: p.windows, observedAt: p.observedAt,
  }));
  panel.webview.postMessage({
    type: "snapshot",
    providers,
    source: snapshot?.source,
    strings: { noData: t("NO DATA"), empty: t("No AI usage data yet"), openApp: t("Open TokenBar app") },
  });
}

// MARK: Lifecycle

export function activate(ctx: vscode.ExtensionContext) {
  setLanguage(vscode.env.language);
  item = vscode.window.createStatusBarItem("tokenbar.status", vscode.StatusBarAlignment.Right, 100);
  item.name = "TokenBar";
  item.command = "tokenbar.toggleWindow";
  item.text = "$(pulse) TokenBar";
  item.show();

  ctx.subscriptions.push(
    item,
    vscode.commands.registerCommand("tokenbar.toggleWindow", toggleWindow),
    vscode.commands.registerCommand("tokenbar.showDetails", () => showDetails(ctx)),
    vscode.commands.registerCommand("tokenbar.openApp", openApp),
    vscode.commands.registerCommand("tokenbar.refresh", refresh),
    vscode.workspace.onDidChangeConfiguration((e) => { if (e.affectsConfiguration("tokenbar")) render(); }),
    { dispose: () => { watchers.forEach((w) => w.close()); watchers.clear(); clearTimeout(debounce); } },
  );

  const timer = setInterval(refresh, REFRESH_MS); // also keeps the countdown text current
  ctx.subscriptions.push({ dispose: () => clearInterval(timer) });
  refresh();
}

export function deactivate() {}

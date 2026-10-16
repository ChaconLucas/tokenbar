#!/usr/bin/env node
// tokenbar — AI usage limits (Claude Code, Codex, Copilot, Windsurf, any AI) in the terminal.
// Zero dependencies, Node >= 18. Docs: docs/api.md
import { VERSION, loadUsage, findProvider, findWindow, duration, fmtPct, abbrOf, summaryLine } from "./lib/data.mjs";

const HELP = `tokenbar ${VERSION} — AI usage limits in your terminal

Usage:
  tokenbar                     one line per AI: 5h and 7d bars, %, time to reset
  tokenbar --json              JSON in the /v1/usage shape (+ "source")
  tokenbar --prompt [--color]  ultra short, for shell prompts: CL 28% CX 0%
  tokenbar get <id> [5h|7d] [--field usedNow|usedPercent|resetsInSeconds|resetsAt|windowMinutes]
                               prints one number (default field: usedNow, default window: the first)
  tokenbar watch [--interval <s>]
                               refreshes every 5 s (Ctrl+C to quit)
  tokenbar --version | help

Options:
  --window <5h|7d|label>       window used by --prompt (default: the first, usually 5h)
  --color / --no-color         force colors on/off (NO_COLOR is respected)
  --no-api                     skip the local API, read the files directly

<id> is the provider id (claude, codex, copilot, windsurf, or any id in ~/.tokenbar/providers),
its 2-letter code (CL, CX…) or its name.

Data: TokenBar app local API (127.0.0.1:41777) → ~/.tokenbar/snapshot.json → Claude/Codex files.
Exit codes: 0 ok · 1 usage error / empty field · 2 no data or unknown provider/window.
`;

// MARK: arguments

const argv = process.argv.slice(2);
const flags = new Set();
const opts = {};
const pos = [];
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === "--field" || a === "--window" || a === "--interval") opts[a.slice(2)] = argv[++i];
  else if (a.startsWith("--") && a.includes("=")) { const [k, v] = a.slice(2).split("="); opts[k] = v; }
  else if (a.startsWith("-")) flags.add(a);
  else pos.push(a);
}

const NO_COLOR = "NO_COLOR" in process.env && process.env.NO_COLOR !== "";
const wantColor = (dflt) => (flags.has("--no-color") ? false : flags.has("--color") ? true : NO_COLOR ? false : dflt);

// MARK: rendering

const rgb = (hex) => { const n = parseInt(hex.slice(1), 16); return [(n >> 16) & 255, (n >> 8) & 255, n & 255]; };
const paint = (on, hex, s) => (on && s ? `\x1b[38;2;${rgb(hex).join(";")}m${s}\x1b[0m` : s);
const dim = (on, s) => (on ? `\x1b[2m${s}\x1b[0m` : s);
const bold = (on, s) => (on ? `\x1b[1m${s}\x1b[0m` : s);

function bar(pct, color, on) {
  const filled = Math.max(0, Math.min(10, Math.round(pct / 10)));
  return paint(on, color, "●".repeat(filled)) + dim(on, "○".repeat(10 - filled));
}

function ago(t) {
  if (!t) return "";
  return `${duration(Date.now() / 1000 - t)} ago`;
}

function pretty(usage, on) {
  if (!usage.providers.length) return noDataText();
  const nameW = Math.max(...usage.providers.map((p) => p.name.length));
  const lines = usage.providers.map((p) => {
    const cells = p.windows.slice(0, 2).map((w) => {
      const reset = w.resetsInSeconds === null ? "" : w.resetsInSeconds === 0 ? "reset" : `↻ ${duration(w.resetsInSeconds)}`;
      return `${dim(on, (w.label || w.id).padStart(3))} ${bar(w.usedNow, p.color, on)} ${bold(on, fmtPct(w.usedNow).padStart(4))}  ${dim(on, reset.padEnd(9))}`;
    });
    return `${paint(on, p.color, "■")} ${p.name.padEnd(nameW)}  ${cells.join("  ").trimEnd()}`;
  });
  const src = { api: "TokenBar app", snapshot: "snapshot.json", direct: "Claude/Codex files", "stale-snapshot": "old snapshot.json" }[usage.source] || usage.source;
  lines.push(dim(on, `from ${src} · updated ${ago(usage.updatedAt)}`));
  return lines.join("\n");
}

function noDataText() {
  return "No AI usage found. Is the TokenBar app running? Or use Claude Code / Codex once (see docs/api.md).";
}

function prompt(usage, on) {
  return usage.providers
    .map((p) => {
      const w = findWindow(p, opts.window);
      return w ? paint(on, p.color, `${abbrOf(p)} ${fmtPct(w.usedNow)}`) : "";
    })
    .filter(Boolean)
    .join(" ");
}

// MARK: commands

async function main() {
  const cmd = pos[0];
  if (flags.has("--version") || flags.has("-v") || cmd === "version") return void console.log(VERSION);
  if (flags.has("--help") || flags.has("-h") || cmd === "help") return void process.stdout.write(HELP);

  const load = () => loadUsage({ skipApi: flags.has("--no-api") });

  if (cmd === "watch") return watch(load);

  if (cmd === "get") {
    const [, id, win] = pos;
    if (!id) { console.error("usage: tokenbar get <id> [5h|7d] [--field usedNow|resetsInSeconds]"); return 1; }
    const usage = await load();
    const p = findProvider(usage, id);
    if (!p) { console.error(`tokenbar: no data for "${id}"${usage.providers.length ? ` (have: ${usage.providers.map((x) => x.id).join(", ")})` : ""}`); return 2; }
    const w = findWindow(p, win || opts.window);
    if (!w) { console.error(`tokenbar: ${p.id} has no window "${win}" (have: ${p.windows.map((x) => x.label || x.id).join(", ")})`); return 2; }
    const field = opts.field || "usedNow";
    if (!(field in w)) { console.error(`tokenbar: unknown field "${field}" (use ${Object.keys(w).join(", ")})`); return 1; }
    const v = w[field];
    if (v === null || v === undefined) return 1;
    console.log(typeof v === "number" ? String(Math.round(v * 100) / 100) : String(v));
    return 0;
  }

  if (cmd) { console.error(`tokenbar: unknown command "${cmd}"\n`); process.stderr.write(HELP); return 1; }

  const usage = await load();
  if (flags.has("--json")) {
    console.log(JSON.stringify(usage, null, 2));
    return usage.providers.length ? 0 : 2;
  }
  if (flags.has("--prompt")) {
    const s = prompt(usage, wantColor(false));
    if (s) console.log(s);
    return s ? 0 : 2;
  }
  if (!usage.providers.length) { console.error(noDataText()); return 2; }
  const on = wantColor(process.stdout.isTTY);
  console.log(on ? pretty(usage, true) : usage.providers.map(summaryLine).join("\n"));
  return 0;
}

async function watch(load) {
  const every = Math.max(1, Number(opts.interval) || 5) * 1000;
  const tty = process.stdout.isTTY;
  const on = wantColor(tty);
  const restore = () => { if (tty) process.stdout.write("\x1b[?25h"); process.exit(0); };
  process.on("SIGINT", restore);
  process.on("SIGTERM", restore);
  if (tty) process.stdout.write("\x1b[?25l");
  for (;;) {
    const usage = await load();
    const body = pretty(usage, on);
    process.stdout.write((tty ? "\x1b[H\x1b[2J" : "") + body + "\n" + dim(on, `refreshing every ${every / 1000}s · Ctrl+C to quit`) + "\n");
    await new Promise((r) => setTimeout(r, every));
  }
}

main().then((code) => { process.exitCode = code ?? 0; }, (err) => { console.error(`tokenbar: ${err?.message || err}`); process.exitCode = 1; });

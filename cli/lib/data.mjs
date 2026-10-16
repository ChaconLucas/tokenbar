// TokenBar data loader shared by the CLI (tokenbar.mjs) and the MCP server (mcp.mjs).
// Zero dependencies, Node >= 18. Reads only local things; never sends anything anywhere.
//
// Source order:
//  1. Local API of the running TokenBar app: http://127.0.0.1:<port>/v1/usage
//     (port from ~/.tokenbar/api.json, default 41777; skipped when api.json names a dead pid;
//     /v1/health must answer "app":"TokenBar" before the port is trusted; 1.5 s timeout).
//  2. ~/.tokenbar/snapshot.json, written by the apps every 30 s (ignored when older than 10 min).
//  3. Direct read, as the apps do: Claude statusline copy (~/.tokenbar/claude.json), newest Codex
//     session log (~/.codex/sessions/**/*.jsonl) and ~/.tokenbar/providers/*.json.
//     If that finds nothing, a stale snapshot is still better than nothing.
// Mirrors vscode/src/data.ts.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import http from "node:http";

export const VERSION = "0.5.3";
export const DEFAULT_PORT = 41777;
const API_TIMEOUT_MS = 1500;
const SNAPSHOT_MAX_AGE = 10 * 60;
const CODEX_SCAN_FILES = 20;

// os.homedir() is %USERPROFILE% on Windows and $HOME elsewhere.
export const home = () => (process.platform === "win32" && process.env.USERPROFILE) || os.homedir();
export const tokenbarDir = () => process.env.TOKENBAR_DIR || path.join(home(), ".tokenbar");
export const apiFile = () => path.join(tokenbarDir(), "api.json");
export const snapshotFile = () => path.join(tokenbarDir(), "snapshot.json");
export const claudeFile = () => path.join(tokenbarDir(), "claude.json");
export const providersDir = () => path.join(tokenbarDir(), "providers");
export const codexDir = () => path.join(process.env.CODEX_HOME || path.join(home(), ".codex"), "sessions");

export const nowSec = () => Date.now() / 1000;

function num(v) {
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string" && v.trim() !== "" && Number.isFinite(Number(v))) return Number(v);
  return undefined;
}
const obj = (v) => (v && typeof v === "object" && !Array.isArray(v) ? v : undefined);

async function readJson(file) {
  try { return JSON.parse(await fs.promises.readFile(file, "utf8")); } catch { return undefined; }
}
async function mtime(file) {
  try { return (await fs.promises.stat(file)).mtimeMs / 1000; } catch { return undefined; }
}

export function labelFor(minutes) {
  if (minutes === undefined || minutes === null) return undefined;
  const m = Math.round(minutes);
  if (m % 1440 === 0) return `${m / 1440}d`;
  if (m % 60 === 0) return `${m / 60}h`;
  return `${m}m`;
}

// MARK: colors and short names (same table as the apps)

const KNOWN = {
  claude: { abbr: "CL", color: "#9e5cff" },
  codex: { abbr: "CX", color: "#ee29c2" },
  copilot: { abbr: "CP", color: "#3fb950" },
  windsurf: { abbr: "WS", color: "#14b8a6" },
};
const EXTRA = ["#ff9e33", "#59d973", "#ffd940", "#6699ff", "#ff73a6"];
const hash = (s) => [...s].reduce((h, c) => (h * 33 + c.charCodeAt(0)) | 0, 5381);

export const colorOf = (p) =>
  KNOWN[p.id]?.color || (typeof p.color === "string" && /^#[0-9a-f]{6}$/i.test(p.color) ? p.color : EXTRA[Math.abs(hash(p.id)) % EXTRA.length]);
export const abbrOf = (p) => KNOWN[p.id]?.abbr || String(p.name || p.id).toUpperCase().replace(/\s/g, "").slice(0, 2);

// MARK: normalization to the /v1/usage shape

/** After the reset time passes, the window is back to 0%. */
export const usedNowOf = (w, t = nowSec()) =>
  !w ? 0 : w.resetsAt !== undefined && w.resetsAt !== null && w.resetsAt <= t ? 0 : w.usedPercent;

function parseWindow(w, i) {
  const o = obj(w);
  const pct = num(o?.usedPercent);
  if (!o || pct === undefined) return undefined;
  const minutes = num(o.windowMinutes);
  return {
    id: typeof o.id === "string" ? o.id : `w${i}`,
    label: typeof o.label === "string" && o.label ? o.label : labelFor(minutes) ?? "",
    usedPercent: pct,
    resetsAt: num(o.resetsAt) ?? null,
    windowMinutes: minutes ?? null,
  };
}

function parseProvider(p) {
  const o = obj(p);
  if (!o || typeof o.id !== "string" || !o.id) return undefined;
  const windows = (Array.isArray(o.windows) ? o.windows : []).map(parseWindow).filter(Boolean);
  if (!windows.length) return undefined;
  return {
    id: o.id,
    name: typeof o.name === "string" && o.name ? o.name : o.id,
    color: typeof o.color === "string" ? o.color : null,
    observedAt: num(o.observedAt) ?? null,
    windows,
  };
}

/** Fills color, usedNow and resetsInSeconds (the /v1/usage shape), relative to `t`. */
export function finish(p, t = nowSec()) {
  return {
    id: p.id,
    name: p.name,
    color: colorOf(p),
    observedAt: p.observedAt ?? null,
    windows: p.windows.map((w) => {
      const resetsAt = w.resetsAt ?? null;
      return {
        id: w.id,
        label: w.label,
        usedPercent: w.usedPercent,
        usedNow: usedNowOf(w, t),
        resetsAt,
        resetsInSeconds: resetsAt === null ? null : Math.max(0, Math.round(resetsAt - t)),
        windowMinutes: w.windowMinutes ?? null,
      };
    }),
  };
}

// MARK: 1. Local API

function alive(pid) {
  try { process.kill(pid, 0); return true; } catch (e) { return e?.code === "EPERM"; }
}

/** Port of the running app, or undefined when api.json says it stopped (its pid is gone). */
export async function apiPort() {
  const info = obj(await readJson(apiFile()));
  if (!info) return DEFAULT_PORT; // no file: still try the default port (health check guards it)
  const pid = num(info.pid);
  if (pid && !alive(pid)) return undefined;
  const port = num(info.port);
  return port && port > 0 && port < 65536 ? port : DEFAULT_PORT;
}

/** GET on the local API. Resolves to the parsed JSON, or undefined (app not running, timeout, 404…). */
export async function apiGet(pathname, port) {
  port ??= await apiPort();
  return new Promise((resolve) => {
    const req = http.get(
      { host: "127.0.0.1", port, path: pathname, headers: { Host: `127.0.0.1:${port}`, Accept: "application/json" }, timeout: API_TIMEOUT_MS },
      (res) => {
        if (res.statusCode !== 200) { res.resume(); return resolve(undefined); }
        let body = "";
        res.setEncoding("utf8");
        res.on("data", (c) => { body += c; if (body.length > 4e6) req.destroy(); });
        res.on("end", () => { try { resolve(JSON.parse(body)); } catch { resolve(undefined); } });
      },
    );
    req.on("timeout", () => req.destroy());
    req.on("error", () => resolve(undefined));
  });
}

export async function readApi() {
  const port = await apiPort();
  if (!port) return undefined;
  // Another program may own the port: trust it only if it says it's TokenBar.
  if (obj(await apiGet("/v1/health", port))?.app !== "TokenBar") return undefined;
  const root = obj(await apiGet("/v1/usage", port));
  if (!root || !Array.isArray(root.providers)) return undefined;
  return {
    updatedAt: num(root.updatedAt) ?? nowSec(),
    providers: root.providers.map(parseProvider).filter(Boolean),
    source: "api",
  };
}

// MARK: 2. snapshot.json

export async function readSnapshot({ allowStale = false } = {}) {
  const file = snapshotFile();
  const root = obj(await readJson(file));
  if (!root || !Array.isArray(root.providers)) return undefined;
  const updatedAt = num(root.updatedAt) ?? (await mtime(file)) ?? 0;
  if (!allowStale && nowSec() - updatedAt > SNAPSHOT_MAX_AGE) return undefined;
  return { updatedAt, providers: root.providers.map(parseProvider).filter(Boolean), source: "snapshot" };
}

// MARK: 3a. Claude Code (statusline copy)

export async function readClaude() {
  const file = claudeFile();
  const limits = obj(obj(await readJson(file))?.rate_limits);
  if (!limits) return undefined;
  // A window that just reset disappears from the JSON: keep it at 0 so 5h and 7d never swap places.
  const windows = [];
  let found = false;
  for (const [key, label, minutes] of [["five_hour", "5h", 300], ["seven_day", "7d", 10080]]) {
    const w = obj(limits[key]);
    const pct = num(w?.used_percentage);
    if (!w || pct === undefined) { windows.push({ id: key, label, usedPercent: 0, resetsAt: null, windowMinutes: minutes }); continue; }
    found = true;
    windows.push({ id: key, label, usedPercent: pct, resetsAt: num(w.resets_at) ?? null, windowMinutes: minutes });
  }
  if (!found) return undefined;
  return { id: "claude", name: "Claude Code", color: null, windows, observedAt: (await mtime(file)) ?? null };
}

// MARK: 3b. Codex (session logs)

async function children(dir) {
  try { return (await fs.promises.readdir(dir)).sort().reverse().map((n) => path.join(dir, n)); } catch { return []; }
}

/** Walks the newest YYYY/MM/DD folders first, without scanning the whole history. */
async function recentCodexFiles(limit = CODEX_SCAN_FILES) {
  const found = [];
  outer: for (const year of await children(codexDir())) {
    for (const month of await children(year)) {
      for (const day of await children(month)) {
        found.push(...(await children(day)).filter((f) => f.endsWith(".jsonl")));
        if (found.length >= limit * 3) break outer;
      }
    }
  }
  const withTime = await Promise.all(found.map(async (f) => ({ f, t: (await mtime(f)) ?? 0 })));
  return withTime.sort((a, b) => b.t - a.t).slice(0, limit).map((x) => x.f);
}

function rateLimitEvent(line) {
  if (!line.includes('"rate_limits"')) return undefined;
  try {
    const o = JSON.parse(line);
    if (o?.type !== "event_msg" || o?.payload?.type !== "token_count") return undefined;
    return obj(o.payload.rate_limits);
  } catch { return undefined; }
}

/** Reads only the end of the file (long sessions reach tens of MB); grows the chunk up to 8 MB. */
async function lastRateLimits(file) {
  let fh;
  try {
    fh = await fs.promises.open(file, "r");
    const size = (await fh.stat()).size;
    let chunk = 256 * 1024;
    for (;;) {
      const start = Math.max(0, size - chunk);
      const buf = Buffer.alloc(size - start);
      await fh.read(buf, 0, buf.length, start);
      let lines = buf.toString("utf8").split("\n").filter((l) => l.length);
      if (start > 0) lines = lines.slice(1); // first line may be cut
      for (let i = lines.length - 1; i >= 0; i--) {
        const hit = rateLimitEvent(lines[i]);
        if (hit) return hit;
      }
      if (start === 0 || chunk >= 8 * 1024 * 1024) return undefined;
      chunk *= 4;
    }
  } catch { return undefined; } finally { await fh?.close(); }
}

export async function readCodex() {
  for (const file of await recentCodexFiles()) {
    const limits = await lastRateLimits(file);
    if (!limits) continue;
    const modified = (await mtime(file)) ?? nowSec();
    const windows = [];
    for (const key of ["primary", "secondary"]) {
      const w = obj(limits[key]);
      const pct = num(w?.used_percent);
      if (!w || pct === undefined) continue;
      const minutes = num(w.window_minutes);
      // New versions send `resets_at` (epoch); old ones `resets_in_seconds`, relative to the file's write time.
      const at = num(w.resets_at);
      const rel = num(w.resets_in_seconds);
      windows.push({
        id: key, label: labelFor(minutes) ?? key, usedPercent: pct,
        resetsAt: at ?? (rel !== undefined ? modified + rel : null), windowMinutes: minutes ?? null,
      });
    }
    if (!windows.length) continue;
    return { id: "codex", name: "Codex", color: null, windows, observedAt: modified };
  }
  return undefined;
}

// MARK: 3c. Other AIs (~/.tokenbar/providers/*.json, format in docs/providers.md)

const RESERVED = new Set(["claude", "codex", "copilot", "windsurf"]);

export async function readExtra() {
  let names = [];
  try { names = (await fs.promises.readdir(providersDir())).filter((n) => n.endsWith(".json")).sort(); } catch { return []; }
  const out = [];
  for (const n of names) {
    const file = path.join(providersDir(), n);
    const p = parseProvider(await readJson(file));
    if (!p || RESERVED.has(p.id)) continue;
    p.windows = p.windows.slice(0, 2);
    p.observedAt ??= (await mtime(file)) ?? null;
    out.push(p);
  }
  return out;
}

export async function readDirect() {
  const [claude, codex, extra] = await Promise.all([readClaude(), readCodex(), readExtra()]);
  return { updatedAt: nowSec(), providers: [claude, codex].filter(Boolean).concat(extra), source: "direct" };
}

// MARK: entry point

/**
 * Loads usage in the /v1/usage shape plus `source` ("api" | "snapshot" | "direct" | "stale-snapshot" | "none").
 * `providers` is empty when nothing was found.
 */
export async function loadUsage({ skipApi = false } = {}) {
  let raw = (!skipApi && (await readApi())) || (await readSnapshot());
  if (!raw) {
    raw = await readDirect();
    if (!raw.providers.length) {
      const stale = await readSnapshot({ allowStale: true });
      raw = stale?.providers.length ? { ...stale, source: "stale-snapshot" } : { ...raw, source: "none" };
    }
  }
  const t = nowSec();
  return { updatedAt: raw.updatedAt, providers: raw.providers.map((p) => finish(p, t)), source: raw.source };
}

// MARK: lookups

/** Finds a provider by id, short name (CL, CX…) or name, case-insensitive. */
export function findProvider(usage, query) {
  if (!query) return undefined;
  const q = String(query).toLowerCase();
  const ps = usage.providers;
  return ps.find((p) => p.id.toLowerCase() === q)
    || ps.find((p) => abbrOf(p).toLowerCase() === q)
    || ps.find((p) => p.name.toLowerCase() === q)
    || ps.find((p) => p.name.toLowerCase().startsWith(q) || p.id.toLowerCase().startsWith(q));
}

/**
 * Finds a window by label ("5h", "7d", "1d"…) or id ("five_hour", "primary"…).
 * "5h"/"short" fall back to the first window and "7d"/"long" to the second, so they also work
 * for AIs whose windows are e.g. 1d/30d. No query = the first window.
 */
export function findWindow(provider, query) {
  const ws = provider?.windows || [];
  if (!query) return ws[0];
  const q = String(query).toLowerCase();
  return ws.find((w) => w.label.toLowerCase() === q)
    || ws.find((w) => w.id.toLowerCase() === q)
    || (["5h", "short", "first", "1"].includes(q) ? ws[0] : undefined)
    || (["7d", "long", "second", "2"].includes(q) ? ws[1] : undefined);
}

// MARK: human text

/** 4h 39m · 37m · 4d 19h · 42s */
export function duration(seconds) {
  if (seconds === null || seconds === undefined) return "unknown";
  const s = Math.max(0, Math.round(seconds));
  if (s < 60) return `${s}s`;
  const m = Math.floor(s / 60);
  if (m < 60) return `${m}m`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h ${String(m % 60).padStart(2, "0")}m`;
  return `${Math.floor(h / 24)}d ${h % 24}h`;
}

export const fmtPct = (n) => `${Math.round(n)}%`;

/** One line per AI, plain text (used by MCP and as the no-color CLI output). */
export function summaryLine(p) {
  const parts = p.windows.map((w) => {
    const reset = w.resetsInSeconds === null ? "" : w.resetsInSeconds === 0 ? " (just reset)" : ` (resets in ${duration(w.resetsInSeconds)})`;
    return `${w.label || w.id} ${fmtPct(w.usedNow)}${reset}`;
  });
  return `${p.name}: ${parts.join(", ")}`;
}

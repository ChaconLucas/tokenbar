// Data layer: reads local files only (no network). No `vscode` import, so it can be tested with plain Node.
//
// Order:
//  1. ~/.tokenbar/snapshot.json — merged snapshot written by the TokenBar desktop apps every 30 s.
//  2. Fallback (app not installed / not running): read the sources directly, mirroring
//     App/macOS/Collector.swift — Claude statusline copy, Codex session logs, ~/.tokenbar/providers/*.json.
import * as fs from "fs";
import * as os from "os";
import * as path from "path";

export interface UsageWindow {
  id: string;
  label: string;
  usedPercent: number;
  resetsAt?: number; // unix seconds
  windowMinutes?: number;
}

export interface Provider {
  id: string;
  name: string;
  windows: UsageWindow[];
  observedAt?: number; // unix seconds
  color?: string | null;
}

export interface Snapshot {
  providers: Provider[];
  updatedAt: number; // unix seconds
  source: "snapshot" | "direct";
}

/** A snapshot older than this means the desktop app stopped writing it: read the sources directly. */
const SNAPSHOT_MAX_AGE = 10 * 60;
const CODEX_SCAN_FILES = 20;

export const home = () => os.homedir(); // %USERPROFILE% on Windows
export const tokenbarDir = () => path.join(home(), ".tokenbar");
export const snapshotFile = () => path.join(tokenbarDir(), "snapshot.json");
export const claudeFile = () => path.join(tokenbarDir(), "claude.json");
export const providersDir = () => path.join(tokenbarDir(), "providers");
export const codexDir = () => path.join(home(), ".codex", "sessions");

const nowSec = () => Date.now() / 1000;

function num(v: unknown): number | undefined {
  if (typeof v === "number" && isFinite(v)) return v;
  if (typeof v === "string" && v.trim() !== "" && isFinite(Number(v))) return Number(v);
  return undefined;
}
const obj = (v: unknown): Record<string, any> | undefined =>
  v && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, any>) : undefined;

async function readJson(file: string): Promise<any | undefined> {
  try { return JSON.parse(await fs.promises.readFile(file, "utf8")); } catch { return undefined; }
}
async function mtime(file: string): Promise<number | undefined> {
  try { return (await fs.promises.stat(file)).mtimeMs / 1000; } catch { return undefined; }
}

function labelFor(minutes?: number): string | undefined {
  if (minutes === undefined) return undefined;
  const m = Math.round(minutes);
  if (m % 1440 === 0) return `${m / 1440}d`;
  if (m % 60 === 0) return `${m / 60}h`;
  return `${m}m`;
}

/** Parses one window in the TokenBar format ({usedPercent, label, resetsAt, windowMinutes}). */
function parseWindow(w: unknown, i: number): UsageWindow | undefined {
  const o = obj(w);
  const pct = num(o?.usedPercent);
  if (!o || pct === undefined) return undefined;
  const minutes = num(o.windowMinutes);
  return {
    id: typeof o.id === "string" ? o.id : `w${i}`,
    label: typeof o.label === "string" && o.label ? o.label : labelFor(minutes) ?? "",
    usedPercent: pct,
    resetsAt: num(o.resetsAt),
    windowMinutes: minutes,
  };
}

function parseProvider(p: unknown): Provider | undefined {
  const o = obj(p);
  if (!o || typeof o.id !== "string" || !o.id) return undefined;
  const windows = (Array.isArray(o.windows) ? o.windows : [])
    .map(parseWindow).filter((w): w is UsageWindow => !!w);
  if (!windows.length) return undefined;
  return {
    id: o.id,
    name: typeof o.name === "string" && o.name ? o.name : o.id,
    windows,
    observedAt: num(o.observedAt),
    color: typeof o.color === "string" ? o.color : null,
  };
}

// MARK: 1. snapshot.json

export async function readSnapshot(): Promise<Snapshot | undefined> {
  const file = snapshotFile();
  const root = obj(await readJson(file));
  if (!root || !Array.isArray(root.providers)) return undefined;
  const updatedAt = num(root.updatedAt) ?? (await mtime(file)) ?? 0;
  if (nowSec() - updatedAt > SNAPSHOT_MAX_AGE) return undefined;
  const providers = root.providers.map(parseProvider).filter((p: Provider | undefined): p is Provider => !!p);
  return { providers, updatedAt, source: "snapshot" };
}

// MARK: 2a. Claude Code (statusline copy)

export async function readClaude(): Promise<Provider | undefined> {
  const file = claudeFile();
  const limits = obj(obj(await readJson(file))?.rate_limits);
  if (!limits) return undefined;
  const windows: UsageWindow[] = [];
  for (const [key, label, minutes] of [["five_hour", "5h", 300], ["seven_day", "7d", 10080]] as const) {
    const w = obj(limits[key]);
    const pct = num(w?.used_percentage);
    if (!w || pct === undefined) continue;
    windows.push({ id: key, label, usedPercent: pct, resetsAt: num(w.resets_at), windowMinutes: minutes });
  }
  if (!windows.length) return undefined;
  return { id: "claude", name: "Claude Code", windows, observedAt: await mtime(file) };
}

// MARK: 2b. Codex (session logs)

async function children(dir: string): Promise<string[]> {
  try { return (await fs.promises.readdir(dir)).sort().reverse().map((n) => path.join(dir, n)); } catch { return []; }
}

/** Walks the newest YYYY/MM/DD folders first, without scanning the whole history. */
export async function recentCodexFiles(limit = CODEX_SCAN_FILES): Promise<string[]> {
  const found: string[] = [];
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

function isRateLimitEvent(line: string): Record<string, any> | undefined {
  if (!line.includes('"rate_limits"')) return undefined;
  try {
    const o = JSON.parse(line);
    if (o?.type !== "event_msg" || o?.payload?.type !== "token_count") return undefined;
    return obj(o.payload.rate_limits);
  } catch { return undefined; }
}

/** Reads only the end of the file (long sessions reach tens of MB); grows the chunk up to 8 MB. */
async function lastRateLimits(file: string): Promise<Record<string, any> | undefined> {
  let fh: fs.promises.FileHandle | undefined;
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
        const hit = isRateLimitEvent(lines[i]);
        if (hit) return hit;
      }
      if (start === 0 || chunk >= 8 * 1024 * 1024) return undefined;
      chunk *= 4;
    }
  } catch { return undefined; } finally { await fh?.close(); }
}

export async function readCodex(): Promise<Provider | undefined> {
  for (const file of await recentCodexFiles()) {
    const limits = await lastRateLimits(file);
    if (!limits) continue;
    const modified = (await mtime(file)) ?? nowSec();
    const windows: UsageWindow[] = [];
    for (const key of ["primary", "secondary"]) {
      const w = obj(limits[key]);
      const pct = num(w?.used_percent);
      if (!w || pct === undefined) continue;
      const minutes = num(w.window_minutes);
      // New versions send `resets_at` (epoch); old ones `resets_in_seconds`, relative to when the file was written.
      const at = num(w.resets_at);
      const rel = num(w.resets_in_seconds);
      windows.push({
        id: key, label: labelFor(minutes) ?? key, usedPercent: pct,
        resetsAt: at ?? (rel !== undefined ? modified + rel : undefined), windowMinutes: minutes,
      });
    }
    if (!windows.length) continue;
    return { id: "codex", name: "Codex", windows, observedAt: modified };
  }
  return undefined;
}

// MARK: 2c. Other AIs (~/.tokenbar/providers/*.json, format in docs/providers.md)

export async function readExtra(): Promise<Provider[]> {
  let names: string[] = [];
  try { names = (await fs.promises.readdir(providersDir())).filter((n) => n.endsWith(".json")).sort(); } catch { return []; }
  const out: Provider[] = [];
  for (const n of names) {
    const file = path.join(providersDir(), n);
    const p = parseProvider(await readJson(file));
    if (!p || p.id === "claude" || p.id === "codex") continue;
    p.windows = p.windows.slice(0, 2);
    p.observedAt ??= await mtime(file);
    out.push(p);
  }
  return out;
}

export async function readDirect(): Promise<Snapshot> {
  const [claude, codex, extra] = await Promise.all([readClaude(), readCodex(), readExtra()]);
  const providers = [claude, codex].filter((p): p is Provider => !!p).concat(extra);
  return { providers, updatedAt: nowSec(), source: "direct" };
}

export async function collect(): Promise<Snapshot> {
  return (await readSnapshot()) ?? (await readDirect());
}

// MARK: Helpers shared by the UI

const KNOWN: Record<string, { abbr: string; color: string }> = {
  claude: { abbr: "CL", color: "#9e5cff" },
  codex: { abbr: "CX", color: "#ee29c2" },
};
const EXTRA = ["#ff9e33", "#59d973", "#ffd940", "#6699ff", "#ff73a6"];
const hash = (s: string) => [...s].reduce((h, c) => (h * 33 + c.charCodeAt(0)) | 0, 5381);

export const colorOf = (p: Provider) =>
  KNOWN[p.id]?.color || (p.color && /^#[0-9a-f]{6}$/i.test(p.color) ? p.color : EXTRA[Math.abs(hash(p.id)) % EXTRA.length]);
export const abbrOf = (p: Provider) => KNOWN[p.id]?.abbr || p.name.toUpperCase().replace(/\s/g, "").slice(0, 2);

/** After the reset time passes, the window is back to 0%. */
export const usedNow = (w: UsageWindow | undefined, t = nowSec()) =>
  !w ? 0 : w.resetsAt !== undefined && w.resetsAt <= t ? 0 : w.usedPercent;

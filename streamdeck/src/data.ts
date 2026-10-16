// TokenBar data loader for the Stream Deck plugin. Port of cli/lib/data.mjs (keep them in sync).
// Reads only local things; never sends anything anywhere.
//
// Source order:
//  1. Local API of the running TokenBar app: http://127.0.0.1:<port>/v1/usage
//     (port from ~/.tokenbar/api.json, default 41777; skipped when api.json names a dead pid;
//     /v1/health must answer "app":"TokenBar" before the port is trusted; 1.5 s timeout).
//  2. ~/.tokenbar/snapshot.json, written by the apps every 30 s (ignored when older than 10 min).
//  3. Direct read, as the apps do: Claude statusline copy (~/.tokenbar/claude.json), newest Codex
//     session log (~/.codex/sessions/**/*.jsonl) and ~/.tokenbar/providers/*.json.
//     If that finds nothing, a stale snapshot is still better than nothing.
import fs from "node:fs";
import http from "node:http";
import os from "node:os";
import path from "node:path";

export const DEFAULT_PORT = 41777;
const API_TIMEOUT_MS = 1500;
const SNAPSHOT_MAX_AGE = 10 * 60;
const CODEX_SCAN_FILES = 20;

export type Source = "api" | "snapshot" | "direct" | "stale-snapshot" | "none";

export interface Window {
	id: string;
	label: string;
	usedPercent: number;
	/** 0 once the reset time has passed. */
	usedNow: number;
	resetsAt: number | null;
	resetsInSeconds: number | null;
	windowMinutes: number | null;
}

export interface Provider {
	id: string;
	name: string;
	color: string;
	observedAt: number | null;
	windows: Window[];
}

export interface Usage {
	updatedAt: number;
	providers: Provider[];
	source: Source;
}

interface RawWindow {
	id: string;
	label: string;
	usedPercent: number;
	resetsAt: number | null;
	windowMinutes: number | null;
}

interface RawProvider {
	id: string;
	name: string;
	color: string | null;
	observedAt: number | null;
	windows: RawWindow[];
}

interface Raw {
	updatedAt: number;
	providers: RawProvider[];
	source: Source;
}

type Obj = Record<string, unknown>;

// os.homedir() is %USERPROFILE% on Windows and $HOME elsewhere.
const home = () => (process.platform === "win32" && process.env.USERPROFILE) || os.homedir();
const tokenbarDir = () => process.env.TOKENBAR_DIR || path.join(home(), ".tokenbar");
const apiFile = () => path.join(tokenbarDir(), "api.json");
const snapshotFile = () => path.join(tokenbarDir(), "snapshot.json");
const claudeFile = () => path.join(tokenbarDir(), "claude.json");
const providersDir = () => path.join(tokenbarDir(), "providers");
const codexDir = () => path.join(process.env.CODEX_HOME || path.join(home(), ".codex"), "sessions");

export const nowSec = () => Date.now() / 1000;

function num(v: unknown): number | undefined {
	if (typeof v === "number" && Number.isFinite(v)) return v;
	if (typeof v === "string" && v.trim() !== "" && Number.isFinite(Number(v))) return Number(v);
	return undefined;
}
const obj = (v: unknown): Obj | undefined => (v && typeof v === "object" && !Array.isArray(v) ? (v as Obj) : undefined);

async function readJson(file: string): Promise<unknown> {
	try {
		return JSON.parse(await fs.promises.readFile(file, "utf8"));
	} catch {
		return undefined;
	}
}
async function mtime(file: string): Promise<number | undefined> {
	try {
		return (await fs.promises.stat(file)).mtimeMs / 1000;
	} catch {
		return undefined;
	}
}

export function labelFor(minutes: number | null | undefined): string | undefined {
	if (minutes === undefined || minutes === null) return undefined;
	const m = Math.round(minutes);
	if (m % 1440 === 0) return `${m / 1440}d`;
	if (m % 60 === 0) return `${m / 60}h`;
	return `${m}m`;
}

// MARK: colors and short names (same table as the apps)

const KNOWN: Record<string, { abbr: string; color: string }> = {
	claude: { abbr: "CL", color: "#9e5cff" },
	codex: { abbr: "CX", color: "#ee29c2" },
	copilot: { abbr: "CP", color: "#3fb950" },
	windsurf: { abbr: "WS", color: "#14b8a6" },
};
const EXTRA = ["#ff9e33", "#59d973", "#ffd940", "#6699ff", "#ff73a6"];
const hash = (s: string) => [...s].reduce((h, c) => (h * 33 + c.charCodeAt(0)) | 0, 5381);

export const colorOf = (p: { id: string; color?: string | null }) =>
	KNOWN[p.id]?.color ||
	(typeof p.color === "string" && /^#[0-9a-f]{6}$/i.test(p.color) ? p.color : EXTRA[Math.abs(hash(p.id)) % EXTRA.length]);
export const abbrOf = (p: { id: string; name?: string }) =>
	KNOWN[p.id]?.abbr || String(p.name || p.id).toUpperCase().replace(/\s/g, "").slice(0, 2);

// MARK: normalization to the /v1/usage shape

/** After the reset time passes, the window is back to 0%. */
export const usedNowOf = (w: { usedPercent: number; resetsAt: number | null } | undefined, t = nowSec()) =>
	!w ? 0 : w.resetsAt !== undefined && w.resetsAt !== null && w.resetsAt <= t ? 0 : w.usedPercent;

function parseWindow(w: unknown, i: number): RawWindow | undefined {
	const o = obj(w);
	const pct = num(o?.usedPercent);
	if (!o || pct === undefined) return undefined;
	const minutes = num(o.windowMinutes);
	return {
		id: typeof o.id === "string" ? o.id : `w${i}`,
		label: typeof o.label === "string" && o.label ? o.label : (labelFor(minutes) ?? ""),
		usedPercent: pct,
		resetsAt: num(o.resetsAt) ?? null,
		windowMinutes: minutes ?? null,
	};
}

function parseProvider(p: unknown): RawProvider | undefined {
	const o = obj(p);
	if (!o || typeof o.id !== "string" || !o.id) return undefined;
	const windows = (Array.isArray(o.windows) ? o.windows : []).map(parseWindow).filter((w): w is RawWindow => !!w);
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
export function finish(p: RawProvider, t = nowSec()): Provider {
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

function alive(pid: number): boolean {
	try {
		process.kill(pid, 0);
		return true;
	} catch (e) {
		return (e as NodeJS.ErrnoException)?.code === "EPERM";
	}
}

/** Port of the running app, or undefined when api.json says it stopped (its pid is gone). */
async function apiPort(): Promise<number | undefined> {
	const info = obj(await readJson(apiFile()));
	if (!info) return DEFAULT_PORT; // no file: still try the default port (health check guards it)
	const pid = num(info.pid);
	if (pid && !alive(pid)) return undefined;
	const port = num(info.port);
	return port && port > 0 && port < 65536 ? port : DEFAULT_PORT;
}

/** GET on the local API. Resolves to the parsed JSON, or undefined (app not running, timeout, 404…). */
function apiGet(pathname: string, port: number): Promise<unknown> {
	return new Promise((resolve) => {
		const req = http.get(
			{
				host: "127.0.0.1",
				port,
				path: pathname,
				headers: { Host: `127.0.0.1:${port}`, Accept: "application/json" },
				timeout: API_TIMEOUT_MS,
			},
			(res) => {
				if (res.statusCode !== 200) {
					res.resume();
					return resolve(undefined);
				}
				let body = "";
				res.setEncoding("utf8");
				res.on("data", (c) => {
					body += c;
					if (body.length > 4e6) req.destroy();
				});
				res.on("end", () => {
					try {
						resolve(JSON.parse(body));
					} catch {
						resolve(undefined);
					}
				});
			},
		);
		req.on("timeout", () => req.destroy());
		req.on("error", () => resolve(undefined));
	});
}

async function readApi(): Promise<Raw | undefined> {
	const port = await apiPort();
	if (!port) return undefined;
	// Another program may own the port: trust it only if it says it's TokenBar.
	if (obj(await apiGet("/v1/health", port))?.app !== "TokenBar") return undefined;
	const root = obj(await apiGet("/v1/usage", port));
	if (!root || !Array.isArray(root.providers)) return undefined;
	return {
		updatedAt: num(root.updatedAt) ?? nowSec(),
		providers: root.providers.map(parseProvider).filter((p): p is RawProvider => !!p),
		source: "api",
	};
}

// MARK: 2. snapshot.json

async function readSnapshot({ allowStale = false } = {}): Promise<Raw | undefined> {
	const file = snapshotFile();
	const root = obj(await readJson(file));
	if (!root || !Array.isArray(root.providers)) return undefined;
	const updatedAt = num(root.updatedAt) ?? (await mtime(file)) ?? 0;
	if (!allowStale && nowSec() - updatedAt > SNAPSHOT_MAX_AGE) return undefined;
	return { updatedAt, providers: root.providers.map(parseProvider).filter((p): p is RawProvider => !!p), source: "snapshot" };
}

// MARK: 3a. Claude Code (statusline copy)

async function readClaude(): Promise<RawProvider | undefined> {
	const file = claudeFile();
	const limits = obj(obj(await readJson(file))?.rate_limits);
	if (!limits) return undefined;
	// A window that just reset disappears from the JSON: keep it at 0 so 5h and 7d never swap places.
	const windows: RawWindow[] = [];
	let found = false;
	for (const [key, label, minutes] of [
		["five_hour", "5h", 300],
		["seven_day", "7d", 10080],
	] as const) {
		const w = obj(limits[key]);
		const pct = num(w?.used_percentage);
		if (!w || pct === undefined) {
			windows.push({ id: key, label, usedPercent: 0, resetsAt: null, windowMinutes: minutes });
			continue;
		}
		found = true;
		windows.push({ id: key, label, usedPercent: pct, resetsAt: num(w.resets_at) ?? null, windowMinutes: minutes });
	}
	if (!found) return undefined;
	return { id: "claude", name: "Claude Code", color: null, windows, observedAt: (await mtime(file)) ?? null };
}

// MARK: 3b. Codex (session logs)

async function children(dir: string): Promise<string[]> {
	try {
		return (await fs.promises.readdir(dir))
			.sort()
			.reverse()
			.map((n) => path.join(dir, n));
	} catch {
		return [];
	}
}

/** Walks the newest YYYY/MM/DD folders first, without scanning the whole history. */
async function recentCodexFiles(limit = CODEX_SCAN_FILES): Promise<string[]> {
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
	return withTime
		.sort((a, b) => b.t - a.t)
		.slice(0, limit)
		.map((x) => x.f);
}

function rateLimitEvent(line: string): Obj | undefined {
	if (!line.includes('"rate_limits"')) return undefined;
	try {
		const o = JSON.parse(line);
		if (o?.type !== "event_msg" || o?.payload?.type !== "token_count") return undefined;
		return obj(o.payload.rate_limits);
	} catch {
		return undefined;
	}
}

/** Reads only the end of the file (long sessions reach tens of MB); grows the chunk up to 8 MB. */
async function lastRateLimits(file: string): Promise<Obj | undefined> {
	let fh: fs.promises.FileHandle | undefined;
	try {
		fh = await fs.promises.open(file, "r");
		const size = (await fh.stat()).size;
		let chunk = 256 * 1024;
		for (;;) {
			const start = Math.max(0, size - chunk);
			const buf = Buffer.alloc(size - start);
			await fh.read(buf, 0, buf.length, start);
			let lines = buf
				.toString("utf8")
				.split("\n")
				.filter((l) => l.length);
			if (start > 0) lines = lines.slice(1); // first line may be cut
			for (let i = lines.length - 1; i >= 0; i--) {
				const hit = rateLimitEvent(lines[i]);
				if (hit) return hit;
			}
			if (start === 0 || chunk >= 8 * 1024 * 1024) return undefined;
			chunk *= 4;
		}
	} catch {
		return undefined;
	} finally {
		await fh?.close();
	}
}

async function readCodex(): Promise<RawProvider | undefined> {
	for (const file of await recentCodexFiles()) {
		const limits = await lastRateLimits(file);
		if (!limits) continue;
		const modified = (await mtime(file)) ?? nowSec();
		const windows: RawWindow[] = [];
		for (const key of ["primary", "secondary"]) {
			const w = obj(limits[key]);
			const pct = num(w?.used_percent);
			if (!w || pct === undefined) continue;
			const minutes = num(w.window_minutes);
			// New versions send `resets_at` (epoch); old ones `resets_in_seconds`, relative to the file's write time.
			const at = num(w.resets_at);
			const rel = num(w.resets_in_seconds);
			windows.push({
				id: key,
				label: labelFor(minutes) ?? key,
				usedPercent: pct,
				resetsAt: at ?? (rel !== undefined ? modified + rel : null),
				windowMinutes: minutes ?? null,
			});
		}
		if (!windows.length) continue;
		return { id: "codex", name: "Codex", color: null, windows, observedAt: modified };
	}
	return undefined;
}

// MARK: 3c. Other AIs (~/.tokenbar/providers/*.json, format in docs/providers.md)

const RESERVED = new Set(["claude", "codex", "copilot", "windsurf"]);

async function readExtra(): Promise<RawProvider[]> {
	let names: string[] = [];
	try {
		names = (await fs.promises.readdir(providersDir())).filter((n) => n.endsWith(".json")).sort();
	} catch {
		return [];
	}
	const out: RawProvider[] = [];
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

async function readDirect(): Promise<Raw> {
	const [claude, codex, extra] = await Promise.all([readClaude(), readCodex(), readExtra()]);
	return {
		updatedAt: nowSec(),
		providers: [claude, codex].filter((p): p is RawProvider => !!p).concat(extra),
		source: "direct",
	};
}

// MARK: entry point

/** Reads usage (resetsAt is absolute, so `usageAt` can recompute the countdown every minute without reloading). */
export async function loadRaw(): Promise<Raw> {
	let raw = (await readApi()) || (await readSnapshot());
	if (!raw) {
		raw = await readDirect();
		if (!raw.providers.length) {
			const stale = await readSnapshot({ allowStale: true });
			raw = stale?.providers.length ? { ...stale, source: "stale-snapshot" } : { ...raw, source: "none" };
		}
	}
	return raw;
}

/** The /v1/usage shape, with usedNow and resetsInSeconds computed for `t`. */
export function usageAt(raw: Raw, t = nowSec()): Usage {
	return { updatedAt: raw.updatedAt, providers: raw.providers.map((p) => finish(p, t)), source: raw.source };
}

export type { Raw };

// MARK: lookups

/** "5h"/"short" → first window, "7d"/"long" → second, so 1d/30d AIs work too. Exact label/id wins. */
export function findWindow(provider: Provider | undefined, query: string | undefined): Window | undefined {
	const ws = provider?.windows || [];
	if (!query) return ws[0];
	const q = String(query).toLowerCase();
	return (
		ws.find((w) => w.label.toLowerCase() === q) ||
		ws.find((w) => w.id.toLowerCase() === q) ||
		(["5h", "short", "first", "1"].includes(q) ? ws[0] : undefined) ||
		(["7d", "long", "second", "2"].includes(q) ? ws[1] : undefined)
	);
}

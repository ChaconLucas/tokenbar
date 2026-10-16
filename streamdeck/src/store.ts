// One loader for every key: reads usage every 30 s (and when a key appears, if the data is older
// than a few seconds) and re-renders every minute so the countdowns tick without reloading.
import { abbrOf, colorOf, findWindow, loadRaw, nowSec, usageAt, type Provider, type Raw, type Usage } from "./data";
import type { KeyModel } from "./render";

const REFRESH_MS = 30_000;
const FRESH_MS = 5_000;

export type Settings = {
	/** provider id: claude, codex, copilot, windsurf, or any id from ~/.tokenbar/providers */
	provider?: string;
	/** "5h" (first window) or "7d" (second) */
	window?: string;
};

type Listener = () => void;

class Store {
	private raw: Raw | undefined;
	private loadedAt = 0;
	private inflight: Promise<void> | undefined;
	private listeners = new Set<Listener>();
	private started = false;

	get usage(): Usage | undefined {
		return this.raw && usageAt(this.raw, nowSec());
	}

	subscribe(fn: Listener): void {
		this.listeners.add(fn);
		this.start();
	}

	/** Reloads unless the data is fresh (or `force`). Listeners run after every load. */
	refresh(force = false): Promise<void> {
		if (!force && this.raw && Date.now() - this.loadedAt < FRESH_MS) return Promise.resolve();
		this.inflight ??= loadRaw()
			.then((raw) => {
				this.raw = raw;
				this.loadedAt = Date.now();
			})
			.catch(() => undefined)
			.finally(() => {
				this.inflight = undefined;
				this.emit();
			});
		return this.inflight;
	}

	private emit(): void {
		for (const fn of this.listeners) fn();
	}

	private start(): void {
		if (this.started) return;
		this.started = true;
		setInterval(() => void this.refresh(true), REFRESH_MS);
		// Tick on the minute so "4:12" turns into "4:11" when the clock does.
		const tick = () => {
			this.emit();
			setTimeout(tick, 60_000 - (Date.now() % 60_000) + 50);
		};
		setTimeout(tick, 60_000 - (Date.now() % 60_000) + 50);
	}
}

export const store = new Store();

/** The provider a key shows: the one in its settings, else the first one TokenBar has. */
export function pickProvider(usage: Usage | undefined, settings: Settings): Provider | undefined {
	const ps = usage?.providers ?? [];
	return settings.provider ? ps.find((p) => p.id === settings.provider) : ps[0];
}

export const windowOf = (settings: Settings) => (settings.window === "7d" ? "7d" : "5h");

/** What a key draws for these settings right now. */
export function modelFor(settings: Settings): KeyModel & { provider?: Provider } {
	const usage = store.usage;
	const p = pickProvider(usage, settings);
	const wanted = windowOf(settings);
	const w = findWindow(p, wanted);
	const id = p?.id ?? settings.provider;
	return {
		provider: p,
		abbr: p ? abbrOf(p) : id ? abbrOf({ id }) : "AI",
		window: (w?.label || wanted).toUpperCase(),
		color: p?.color ?? (id ? colorOf({ id }) : "#9e5cff"),
		pct: w ? w.usedNow : null,
		resetsInSeconds: w?.resetsInSeconds ?? null,
		remaining: w && w.windowMinutes && w.resetsInSeconds !== null ? w.resetsInSeconds / (w.windowMinutes * 60) : null,
		status: usage ? (usage.source === "none" ? "OFF" : "NO DATA") : "...",
	};
}

const KNOWN_NAMES: Record<string, string> = { claude: "Claude Code", codex: "Codex", copilot: "GitHub Copilot", windsurf: "Windsurf" };

/** Items for the property inspector's AI dropdown: what TokenBar sees now, then the built-in AIs. */
export function providerItems(): { label: string; value: string }[] {
	const seen = (store.usage?.providers ?? []).map((p) => ({ label: p.name, value: p.id }));
	const rest = Object.entries(KNOWN_NAMES)
		.filter(([id]) => !seen.some((s) => s.value === id))
		.map(([value, label]) => ({ label: `${label} (no data yet)`, value }));
	return [...seen, ...rest];
}

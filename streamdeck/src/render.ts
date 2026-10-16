// Key images in the TokenBar LED look: everything is a dot on black, so the same scene renders to
// SVG (sent to Stream Deck with setImage) and to PNG (scripts/images.mjs, no native deps).
// Self-contained on purpose: no imports, so Node can run it directly (type stripping) from scripts/.

export interface Dot {
	x: number;
	y: number;
	r: number;
	c: string;
}

export interface Scene {
	size: number;
	/** undefined = transparent */
	bg?: string;
	dots: Dot[];
}

export const RED = "#ff3b30";
export const WHITE = "#f4f4f4";
export const GRAY = "#8c8c8c";
export const DIM = "#262626";
export const WARN_AT = 85;

// 5x7 dot-matrix font (classic HD44780 shapes). Variable width: each row string is one glyph row.
const FONT: Record<string, string[]> = {
	"0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
	"1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
	"2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
	"3": ["11111", "00010", "00100", "00010", "00001", "10001", "01110"],
	"4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
	"5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
	"6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
	"7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
	"8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
	"9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
	A: ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
	B: ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
	C: ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
	D: ["11100", "10010", "10001", "10001", "10001", "10010", "11100"],
	E: ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
	F: ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
	G: ["01110", "10001", "10000", "10111", "10001", "10001", "01111"],
	H: ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
	I: ["111", "010", "010", "010", "010", "010", "111"],
	J: ["00111", "00010", "00010", "00010", "00010", "10010", "01100"],
	K: ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
	L: ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
	M: ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
	N: ["10001", "10001", "11001", "10101", "10011", "10001", "10001"],
	O: ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
	P: ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
	Q: ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
	R: ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
	S: ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
	T: ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
	U: ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
	V: ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
	W: ["10001", "10001", "10001", "10101", "10101", "10101", "01010"],
	X: ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
	Y: ["10001", "10001", "10001", "01010", "00100", "00100", "00100"],
	Z: ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
	"%": ["11000", "11001", "00010", "00100", "01000", "10011", "00011"],
	":": ["0", "1", "1", "0", "1", "1", "0"],
	".": ["0", "0", "0", "0", "0", "0", "1"],
	"-": ["0000", "0000", "0000", "1111", "0000", "0000", "0000"],
	"?": ["01110", "10001", "00001", "00010", "00100", "00000", "00100"],
	" ": ["00", "00", "00", "00", "00", "00", "00"],
};

const glyph = (ch: string) => FONT[ch] ?? FONT[ch.toUpperCase()] ?? FONT["?"];

/** Width of `text` in dot columns (1 empty column between glyphs). */
export function textCols(text: string): number {
	const chars = [...text];
	return chars.reduce((n, ch) => n + glyph(ch)[0].length, 0) + Math.max(0, chars.length - 1);
}

/** Largest pitch (px per dot) at which `text` fits in `width`, capped at `max`. */
export function fitPitch(text: string, width: number, max: number): number {
	return Math.min(max, width / textCols(text));
}

/** Dots of `text`, centered on `cx`, top row at `top`. */
export function textDots(text: string, cx: number, top: number, pitch: number, c: string, fill = 0.44): Dot[] {
	const dots: Dot[] = [];
	let col = -textCols(text) / 2;
	const r = pitch * fill;
	for (const ch of text) {
		const g = glyph(ch);
		g.forEach((row, y) =>
			[...row].forEach((bit, x) => {
				if (bit === "1") dots.push({ x: cx + (col + x + 0.5) * pitch, y: top + (y + 0.5) * pitch, r, c });
			}),
		);
		col += g[0].length + 1;
	}
	return dots;
}

/** `n` dots in a row from x0 to x1 (centers), the first `lit` in `on`, the rest in DIM. */
export function barDots(x0: number, x1: number, y: number, n: number, lit: number, r: number, on: string): Dot[] {
	const step = (x1 - x0) / (n - 1);
	return Array.from({ length: n }, (_, i) => ({ x: x0 + i * step, y, r, c: i < lit ? on : DIM }));
}

/** `n` dots on a circle, clockwise from 12 o'clock, the first `lit` in `on`. */
export function ringDots(cx: number, cy: number, radius: number, n: number, lit: number, r: number, on: string): Dot[] {
	return Array.from({ length: n }, (_, i) => {
		const a = (i / n) * 2 * Math.PI - Math.PI / 2;
		return { x: cx + radius * Math.cos(a), y: cy + radius * Math.sin(a), r, c: i < lit ? on : DIM };
	});
}

const round = (n: number) => Math.round(n * 100) / 100;

export function toSvg(scene: Scene): string {
	const s = scene.size;
	const byColor = new Map<string, Dot[]>();
	for (const d of scene.dots) byColor.set(d.c, [...(byColor.get(d.c) ?? []), d]);
	const groups = [...byColor]
		.map(([c, ds]) => `<g fill="${c}">${ds.map((d) => `<circle cx="${round(d.x)}" cy="${round(d.y)}" r="${round(d.r)}"/>`).join("")}</g>`)
		.join("");
	const bg = scene.bg ? `<rect width="${s}" height="${s}" fill="${scene.bg}"/>` : "";
	return `<svg xmlns="http://www.w3.org/2000/svg" width="${s}" height="${s}" viewBox="0 0 ${s} ${s}">${bg}${groups}</svg>`;
}

export const svgDataUrl = (scene: Scene) => `data:image/svg+xml;base64,${Buffer.from(toSvg(scene)).toString("base64")}`;

// MARK: time text

/** Usage key: "37M" · "4:12" · "5D". Countdown key (long): "37M" · "4:12" · "5D3H". */
export function countdownText(seconds: number | null | undefined, long = false): string {
	if (seconds === null || seconds === undefined || seconds <= 0) return "--"; // 0 = reset passed, next one unknown
	const m = Math.ceil(Math.max(0, seconds) / 60);
	if (m < 60) return `${m}M`;
	const h = Math.floor(m / 60);
	if (h < 24) return `${h}:${String(m % 60).padStart(2, "0")}`;
	const d = Math.floor(h / 24);
	return long && h % 24 ? `${d}D${h % 24}H` : `${d}D`;
}

// MARK: keys (144 x 144; Stream Deck scales down for 72/96 px keys)

export interface KeyModel {
	/** "CL", "CX"… */
	abbr: string;
	/** "5H", "7D"… */
	window: string;
	color: string;
	/** null = no data (app not running and nothing on disk) */
	pct: number | null;
	resetsInSeconds: number | null;
	/** fraction of the window still to go, 0…1 (countdown ring) */
	remaining?: number | null;
	/** bottom text when there is no data (default "OFF") */
	status?: string;
}

const S = 144;

/** "AI usage" key: label, big %, 12-dot bar, countdown. */
export function usageKey(m: KeyModel): Scene {
	const off = m.pct === null;
	const pct = off ? 0 : Math.max(0, Math.min(100, Math.round(m.pct!)));
	const hot = !off && pct >= WARN_AT;
	const main = off ? GRAY : hot ? RED : WHITE;
	const bar = hot ? RED : m.color;
	const label = `${m.abbr} ${m.window}`.trim();
	const big = off ? "--" : `${pct}%`;
	const bigPitch = fitPitch(big, 128, 6);
	const dots = [
		...textDots(label, S / 2, 9, fitPitch(label, 124, 4), m.color),
		...textDots(big, S / 2, 66 - (7 * bigPitch) / 2, bigPitch, main),
		...barDots(14, 130, 102, 12, off ? 0 : Math.round((pct / 100) * 12), 4.3, bar),
		...(() => {
			const t = off ? (m.status ?? "OFF") : countdownText(m.resetsInSeconds);
			return textDots(t, S / 2, 114, fitPitch(t, 124, 3.6), GRAY);
		})(),
	];
	return { size: S, bg: "#000000", dots };
}

/** "Reset countdown" key: big time to reset inside a ring that drains as the window runs out. */
export function countdownKey(m: KeyModel): Scene {
	const off = m.pct === null || m.resetsInSeconds === null;
	const hot = !off && (m.pct ?? 0) >= WARN_AT;
	const n = 24;
	const lit = off ? 0 : Math.round(Math.max(0, Math.min(1, m.remaining ?? 0)) * n);
	const time = off ? "--" : countdownText(m.resetsInSeconds, true);
	const label = `${m.abbr} ${m.window}`.trim();
	const pitch = fitPitch(time, 92, 5);
	const dots = [
		...ringDots(S / 2, S / 2, 63, n, lit, 4, hot ? RED : m.color),
		...textDots(label, S / 2, 36, fitPitch(label, 80, 3.4), m.color),
		...textDots(time, S / 2, 78 - (7 * pitch) / 2, pitch, off ? GRAY : WHITE),
		...(() => {
			const t = off ? (m.status ?? "OFF") : `${Math.round(m.pct ?? 0)}%`;
			return textDots(t, S / 2, 96, fitPitch(t, 72, 3), hot ? RED : GRAY);
		})(),
	];
	return { size: S, bg: "#000000", dots };
}

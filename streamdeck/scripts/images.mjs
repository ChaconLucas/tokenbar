// Generates the plugin's static PNGs (no native deps): action-list and category icons in white
// dots on transparent (as Elgato asks), default key images in the LED look, and the marketplace
// icon from the app icon (macOS `sips`). Usage: npm run images
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";
import { countdownKey, ringDots, usageKey } from "../src/render.ts";

const root = path.resolve(import.meta.dirname, "..", "com.chaconlucas.tokenbar.sdPlugin", "imgs");
const appIcon = path.resolve(import.meta.dirname, "..", "..", "desktop", "src-tauri", "icons", "icon.png"); // 512 px

// MARK: rasterizer (4x4 supersampling; dots never overlap, so "last one wins" is enough)

const hex = (c) => {
	const m = /^#([0-9a-f]{6})([0-9a-f]{2})?$/i.exec(c);
	if (!m) throw new Error(`color ${c}`);
	const n = parseInt(m[1], 16);
	return [n >> 16, (n >> 8) & 255, n & 255, m[2] ? parseInt(m[2], 16) : 255];
};

function rasterize(scene, px) {
	const k = px / scene.size, SS = 4, W = px * SS;
	const sub = new Int32Array(W * W).fill(-1);
	const colors = scene.dots.map((d) => hex(d.c));
	scene.dots.forEach((d, i) => {
		const cx = d.x * k * SS, cy = d.y * k * SS, r = d.r * k * SS;
		for (let y = Math.max(0, Math.floor(cy - r)); y <= Math.min(W - 1, Math.ceil(cy + r)); y++)
			for (let x = Math.max(0, Math.floor(cx - r)); x <= Math.min(W - 1, Math.ceil(cx + r)); x++)
				if ((x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r * r) sub[y * W + x] = i;
	});
	const bg = scene.bg ? hex(scene.bg) : [0, 0, 0, 0];
	const out = Buffer.alloc(px * px * 4);
	for (let y = 0; y < px; y++)
		for (let x = 0; x < px; x++) {
			let r = 0, g = 0, b = 0, a = 0;
			for (let sy = 0; sy < SS; sy++)
				for (let sx = 0; sx < SS; sx++) {
					const i = sub[(y * SS + sy) * W + x * SS + sx];
					const c = i < 0 ? bg : colors[i];
					const al = c[3] / 255;
					r += c[0] * al; g += c[1] * al; b += c[2] * al; a += al;
				}
			const o = (y * px + x) * 4;
			out[o + 3] = Math.round((a / (SS * SS)) * 255);
			if (a > 0) { out[o] = Math.round(r / a); out[o + 1] = Math.round(g / a); out[o + 2] = Math.round(b / a); }
		}
	return png(px, px, out);
}

const crcTable = Array.from({ length: 256 }, (_, n) => {
	let c = n;
	for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
	return c >>> 0;
});
const crc32 = (buf) => {
	let c = 0xffffffff;
	for (const byte of buf) c = crcTable[(c ^ byte) & 255] ^ (c >>> 8);
	return (c ^ 0xffffffff) >>> 0;
};
const chunk = (type, data) => {
	const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
	const td = Buffer.concat([Buffer.from(type), data]);
	const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
	return Buffer.concat([len, td, crc]);
};
function png(w, h, rgba) {
	const ihdr = Buffer.alloc(13);
	ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 6;
	const raw = Buffer.alloc((w * 4 + 1) * h);
	for (let y = 0; y < h; y++) rgba.copy(raw, y * (w * 4 + 1) + 1, y * w * 4, (y + 1) * w * 4);
	return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", zlib.deflateSync(raw, { level: 9 })), chunk("IEND", Buffer.alloc(0))]);
}

// MARK: icons (designed on a 40 px grid, white dots, faint = 35% white)

const W = "#ffffff", F = "#ffffff59";

/** The dotted "%" of the app icon: two 2x2 clusters and a diagonal. */
const percent = (cx, cy, s) => {
	const d = [];
	const r = 1.55 * s;
	for (const [qx, qy] of [[-1, -1], [1, 1]])
		for (const [ox, oy] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) d.push({ x: cx + qx * 5.6 * s + ox * 1.9 * s, y: cy + qy * 5.6 * s + oy * 1.9 * s, r, c: W });
	for (let i = -2; i <= 2; i++) d.push({ x: cx - i * 2.9 * s, y: cy + i * 2.9 * s, r: 1.45 * s, c: W });
	return d;
};

const icons = {
	// Category / plugin list: ring (most of it lit, as the app icon) around the dotted %.
	"plugin/category-icon": { size: 40, dots: [...ringDots(20, 20, 17, 16, 11, 1.7, W).map((d) => ({ ...d, c: d.c === W ? W : F })), ...percent(20, 20, 0.85)] },
	// "AI usage": the dotted % over a dot bar, 3 of 5 lit.
	"actions/usage/icon": {
		size: 40,
		dots: [...percent(20, 15, 1.05), ...Array.from({ length: 5 }, (_, i) => ({ x: 6 + i * 7, y: 35, r: 2.6, c: i < 3 ? W : F }))],
	},
	// "Reset countdown": draining ring with a clock hand.
	"actions/countdown/icon": {
		size: 40,
		dots: [
			...ringDots(20, 20, 16.5, 12, 8, 2.4, W).map((d) => ({ ...d, c: d.c === W ? W : F })),
			{ x: 20, y: 20, r: 2.4, c: W }, { x: 20, y: 14.2, r: 1.9, c: W }, { x: 20, y: 9, r: 1.9, c: W }, { x: 24.6, y: 22.6, r: 1.9, c: W },
		],
	},
};

const keys = {
	"actions/usage/key": usageKey({ abbr: "AI", window: "", color: "#9e5cff", pct: null, resetsInSeconds: null, status: "" }),
	"actions/countdown/key": countdownKey({ abbr: "AI", window: "", color: "#9e5cff", pct: null, resetsInSeconds: null, status: "" }),
};

const write = (name, px, buf) => {
	const file = path.join(root, `${name}${px.suffix}.png`);
	fs.mkdirSync(path.dirname(file), { recursive: true });
	fs.writeFileSync(file, buf);
	console.log(path.relative(process.cwd(), file));
};

for (const [name, scene] of Object.entries(icons)) {
	const base = name.startsWith("plugin/") ? 28 : 20;
	write(name, { suffix: "" }, rasterize(scene, base));
	write(name, { suffix: "@2x" }, rasterize(scene, base * 2));
}
for (const [name, scene] of Object.entries(keys)) {
	write(name, { suffix: "" }, rasterize(scene, 72));
	write(name, { suffix: "@2x" }, rasterize(scene, 144));
}

// Marketplace / plugin icon: the app icon, 288 and 512 px.
if (process.platform === "darwin" && fs.existsSync(appIcon)) {
	fs.copyFileSync(appIcon, path.join(root, "plugin", "marketplace@2x.png"));
	execFileSync("sips", ["-z", "288", "288", appIcon, "--out", path.join(root, "plugin", "marketplace.png")], { stdio: "ignore" });
	console.log("plugin/marketplace.png, plugin/marketplace@2x.png (from the app icon)");
}

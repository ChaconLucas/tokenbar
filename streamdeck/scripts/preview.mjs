// Renders sample keys to SVG and (with Google Chrome, if present) to 144x144 PNG for review.
// Usage: node scripts/preview.mjs [outDir]
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { countdownKey, toSvg, usageKey } from "../src/render.ts";

const out = path.resolve(process.argv[2] || "preview");
fs.mkdirSync(out, { recursive: true });

const samples = {
	"usage-claude-28": usageKey({ abbr: "CL", window: "5H", color: "#9e5cff", pct: 28, resetsInSeconds: 4 * 3600 + 12 * 60 }),
	"usage-codex-91": usageKey({ abbr: "CX", window: "5H", color: "#ee29c2", pct: 91, resetsInSeconds: 37 * 60 }),
	"usage-copilot-7d-100": usageKey({ abbr: "CP", window: "7D", color: "#3fb950", pct: 100, resetsInSeconds: 5 * 86400 + 3600 }),
	"usage-no-data": usageKey({ abbr: "WS", window: "5H", color: "#14b8a6", pct: null, resetsInSeconds: null, status: "NO DATA" }),
	"countdown-no-data": countdownKey({ abbr: "WS", window: "5H", color: "#14b8a6", pct: null, resetsInSeconds: null, status: "NO DATA" }),
	"usage-off": usageKey({ abbr: "CL", window: "5H", color: "#9e5cff", pct: null, resetsInSeconds: null }),
	"countdown-claude": countdownKey({ abbr: "CL", window: "5H", color: "#9e5cff", pct: 28, resetsInSeconds: 4 * 3600 + 12 * 60, remaining: 252 / 300 }),
	"countdown-codex-7d": countdownKey({ abbr: "CX", window: "7D", color: "#ee29c2", pct: 91, resetsInSeconds: 2 * 86400 + 5 * 3600, remaining: 53 / 168 }),
};

const chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
for (const [name, scene] of Object.entries(samples)) {
	const svg = path.join(out, `${name}.svg`);
	fs.writeFileSync(svg, toSvg(scene));
	if (!fs.existsSync(chrome)) continue;
	const html = path.join(out, `${name}.html`);
	fs.writeFileSync(html, `<!doctype html><style>html,body{margin:0;background:#000}img{display:block}</style><img src="${name}.svg" width="144" height="144">`);
	execFileSync(chrome, ["--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
		`--user-data-dir=${path.join(out, ".chrome")}`, "--window-size=144,144", `--screenshot=${path.join(out, `${name}.png`)}`,
		`file://${html}`], { stdio: "ignore" });
	fs.rmSync(html);
}
fs.rmSync(path.join(out, ".chrome"), { recursive: true, force: true });
console.log(`wrote ${Object.keys(samples).length} samples to ${out}`);

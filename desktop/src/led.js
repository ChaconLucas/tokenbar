// Display de LED em matriz de pontos — a mesma lógica do app da Apple, desenhada num <canvas>.
import { GLYPHS } from "./glyphs.js";
import { t as tr } from "./i18n.js";

const glyph = (c) => GLYPHS[c.toUpperCase()] || GLYPHS[" "];
export const textWidth = (t, k = 1) =>
  ([...t].reduce((s, c) => s + glyph(c)[0].length, 0) + Math.max(0, t.length - 1)) * k;

/** Grade: 0 apagado, 1 fundo colorido, 2 texto, 3 texto apagado. */
export class Grid {
  constructor(cols, rows) { this.cols = cols; this.rows = rows; this.cells = new Uint8Array(cols * rows); }
  set(x, y, v) { if (x >= 0 && y >= 0 && x < this.cols && y < this.rows) this.cells[y * this.cols + x] = v; }
  fill(frac) { const n = Math.round(Math.min(Math.max(frac, 0), 1) * this.cols); for (let x = 0; x < n; x++) for (let y = 0; y < this.rows; y++) this.set(x, y, 1); }
  draw(text, x, y, k = 1, v = 2) {
    let cx = x;
    for (const ch of text) {
      const g = glyph(ch);
      g.forEach((line, r) => [...line].forEach((p, c) => {
        if (p === "#") for (let sy = 0; sy < k; sy++) for (let sx = 0; sx < k; sx++) this.set(cx + c * k + sx, y + r * k + sy, v);
      }));
      cx += (g[0].length + 1) * k;
    }
  }
  center(text, y, k = 1, v = 2, lo = 0, hi = this.cols) { this.draw(text, lo + Math.max(0, Math.floor((hi - lo - textWidth(text, k)) / 2)), y, k, v); }
}

const rgba = (hex, a) => {
  const n = parseInt(hex.slice(1), 16);
  return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},${a})`;
};

/** Pinta a grade: pontos redondos; o fundo aceso na cor, o texto em branco. */
export function paint(ctx, g, left, top, dot, color, textColor = "#ffffff", glow = true) {
  const size = dot * 0.84;
  const fills = [rgba(color, 0.10), rgba(color, 0.62), textColor, rgba(textColor, 0.72)];
  if (glow) { ctx.shadowColor = rgba(color, 0.45); ctx.shadowBlur = dot * 1.5; }
  for (let y = 0; y < g.rows; y++) for (let x = 0; x < g.cols; x++) {
    ctx.fillStyle = fills[g.cells[y * g.cols + x]];
    ctx.beginPath();
    ctx.arc(left + x * dot + size / 2, top + y * dot + size / 2, size / 2, 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.shadowBlur = 0;
}

export const now = () => Date.now() / 1000;
export const used = (w, t = now()) => (w?.resetsAt && w.resetsAt <= t ? 0 : w?.usedPercent ?? 0);

/** "3:41", "6D8H" (painel largo) ou "6D" (estreito). */
export function timeLeft(w, t = now(), long = true) {
  if (!w?.resetsAt) return "--:--";
  if (w.resetsAt <= t) return "OK";
  const s = Math.max(0, Math.floor(w.resetsAt - t));
  const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60);
  return d > 0 ? (long ? `${d}D${h}H` : `${d}D`) : `${h}:${String(m).padStart(2, "0")}`;
}

const RED = "#ff3838";
export const fillColor = (base, pct) => (pct >= 85 ? RED : base);

/**
 * Uma página do aparelho: para cada janela, um bloco com rótulo + % (o fundo enche até a %)
 * e, ao lado, quanto falta para resetar. Igual ao display do Mac.
 */
export function drawPage(ctx, w, h, windows, base) {
  ctx.clearRect(0, 0, w, h);
  const rows = Math.max(1, windows.length);
  const gapRows = 3;
  const bandRows = 26, gapCols = 3;
  // O ponto sai da altura; as colunas crescem até ocupar a largura (bloco do gasto ~57%).
  const dot = Math.max(1, Math.min(h / (bandRows * rows + gapRows * (rows - 1)), w / 110));
  const totalCols = Math.floor(w / dot);
  const leftCols = Math.max(48, Math.floor((totalCols - gapCols) * 0.57));
  const rightCols = Math.max(40, totalCols - gapCols - leftCols);
  const offX = (w - dot * totalCols) / 2;
  const offY = (h - dot * (bandRows * rows + gapRows * (rows - 1))) / 2;
  windows.forEach((win, i) => {
    const y = offY + i * dot * (bandRows + gapRows);
    const pct = used(win);
    const color = fillColor(base, pct);
    const k = 2;
    const L = new Grid(leftCols, bandRows);
    L.fill(pct / 100);
    if (win) {
      const label = (win.label || "").toUpperCase();
      const big = `${Math.min(Math.round(pct), 999)}%`;
      L.draw(label, 3, Math.floor((bandRows - 7) / 2));
      L.draw(big, leftCols - 3 - textWidth(big, k), Math.floor((bandRows - 7 * k) / 2), k);
    } else {
      L.center(tr("SEM DADOS"), Math.floor((bandRows - 7) / 2));
    }
    paint(ctx, L, offX, y, dot, color);
    const R = new Grid(rightCols, bandRows);
    let t = timeLeft(win, now(), true);
    if (textWidth(t, k) + 4 > rightCols) t = timeLeft(win, now(), false);
    R.center(t, Math.floor((bandRows - 7 * k) / 2), k);
    paint(ctx, R, offX + (leftCols + gapCols) * dot, y, dot, "#ffffff", "#ffffff", false);
  });
}

/** Tecla de LED: o texto em pontos, aceso na cor (ou apagado). */
export function keyCanvas(text, color, on, dot = 1.8) {
  const c = document.createElement("canvas");
  const g = new Grid(textWidth(text), 7);
  g.draw(text, 0, 0);
  const ratio = window.devicePixelRatio || 1;
  c.width = Math.ceil(g.cols * dot * ratio); c.height = Math.ceil(7 * dot * ratio);
  c.style.width = `${g.cols * dot}px`; c.style.height = `${7 * dot}px`;
  const ctx = c.getContext("2d"); ctx.scale(ratio, ratio);
  const size = dot * 0.84;
  ctx.fillStyle = on ? color : "rgba(255,255,255,0.32)";
  for (let y = 0; y < 7; y++) for (let x = 0; x < g.cols; x++) if (g.cells[y * g.cols + x] === 2) {
    ctx.beginPath(); ctx.arc(x * dot + size / 2, y * dot + size / 2, size / 2, 0, Math.PI * 2); ctx.fill();
  }
  return c;
}

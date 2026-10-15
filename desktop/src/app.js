// O aparelho: teclas de LED, display que troca de IA arrastando (ou rolando para o lado), ajustes.
import { drawPage, keyCanvas, Grid, paint } from "./led.js";

const { invoke } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;
const isMini = new URLSearchParams(location.search).has("mini");

const KNOWN = { claude: { name: "CLAUDE", abbr: "CL", color: "#9e5cff" }, codex: { name: "CODEX", abbr: "CX", color: "#ee29c2" } };
const EXTRA = ["#ff9e33", "#59d973", "#ffd940", "#6699ff", "#ff73a6"];
const hash = (s) => [...s].reduce((h, c) => (h * 33 + c.charCodeAt(0)) | 0, 5381);

let snapshot = { providers: [], updatedAt: 0 };
let windowChoice = localStorage.getItem("window") || "both";
let hidden = new Set(JSON.parse(localStorage.getItem("hidden") || "[]"));
let index = 0;

const ids = () => {
  const have = snapshot.providers.map((p) => p.id);
  const known = ["claude", "codex"].filter((k) => !have.length || have.includes(k));
  return [...known, ...have.filter((i) => !KNOWN[i])];
};
const visible = () => { const v = ids().filter((i) => !hidden.has(i)); return v.length ? v : ids(); };
const provider = (id) => snapshot.providers.find((p) => p.id === id);
const color = (id) => KNOWN[id]?.color || provider(id)?.color || EXTRA[Math.abs(hash(id)) % EXTRA.length];
const shortName = (id) => KNOWN[id]?.name || (provider(id)?.name || id).toUpperCase().slice(0, 8);
const abbr = (id) => KNOWN[id]?.abbr || shortName(id).replace(/ /g, "").slice(0, 2);

function pick(p) {
  const ws = p?.windows || [];
  if (windowChoice === "both") return ws.length ? ws.slice(0, 2) : [null];
  return [windowChoice === "long" ? ws[1] || ws[0] : ws[0]];
}

// ---------- teclas ----------
function key(label, col, on, onClick, title) {
  const b = document.createElement("span");
  b.className = "key"; b.title = title || "";
  b.appendChild(keyCanvas(label, col, on, isMini ? 1.5 : 1.8));
  b.onclick = (e) => { e.stopPropagation(); onClick(); };
  return b;
}
function iconKey(icon, title, onClick) {
  const b = document.createElement("span");
  b.className = "key icon"; b.textContent = icon; b.title = title;
  b.onclick = (e) => { e.stopPropagation(); onClick(); };
  return b;
}

function renderKeys() {
  const agents = document.getElementById("agents"); agents.replaceChildren();
  const all = ids();
  for (const id of all) {
    const on = !hidden.has(id);
    agents.appendChild(key(all.length > 2 ? abbr(id) : shortName(id), color(id), on, () => {
      if (on && visible().length > 1) hidden.add(id); else hidden.delete(id);
      localStorage.setItem("hidden", JSON.stringify([...hidden])); index = 0; render();
    }));
  }
  const pages = document.getElementById("pages"); pages.replaceChildren();
  if (visible().length > 1) visible().forEach((id, i) => {
    const d = document.createElement("i");
    if (i === index) { d.className = "on"; d.style.setProperty("--c", color(id)); }
    d.onclick = () => { index = i; render(); };
    pages.appendChild(d);
  });
  const right = document.getElementById("right"); right.replaceChildren();
  right.appendChild(key({ short: "5H", long: "7D", both: "5H 7D" }[windowChoice], "#ffffff", true, () => {
    windowChoice = { short: "long", long: "both", both: "short" }[windowChoice];
    localStorage.setItem("window", windowChoice); render();
  }));
  if (isMini) {
    right.appendChild(iconKey("⤢", "Voltar ao aparelho grande", () => invoke("open_main")));
    right.appendChild(iconKey("✕", "Fechar", () => window.__TAURI__.window.getCurrentWindow().close()));
  } else {
    right.appendChild(iconKey("⧉", "Flutuante: pequeno, sempre na frente", () => invoke("open_mini")));
    right.appendChild(iconKey("?", "Primeiros passos", openGuide));
    right.appendChild(iconKey("⚙", "Ajustes", openSettings));
  }
}

// ---------- display ----------
const canvas = document.getElementById("display");
let drag = 0;
function renderDisplay() {
  const r = canvas.getBoundingClientRect(), ratio = window.devicePixelRatio || 1;
  canvas.width = Math.round(r.width * ratio); canvas.height = Math.round(r.height * ratio);
  const ctx = canvas.getContext("2d");
  ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
  const v = visible(); index = Math.min(index, v.length - 1);
  ctx.clearRect(0, 0, r.width, r.height);
  // A página atual e as vizinhas, deslocadas pelo arrasto.
  for (let i = Math.max(0, index - 1); i <= Math.min(v.length - 1, index + 1); i++) {
    ctx.save();
    ctx.translate((i - index) * r.width + drag, 0);
    drawPage(ctx, r.width, r.height, pick(provider(v[i])), color(v[i]));
    ctx.restore();
  }
}
function render() { renderKeys(); renderDisplay(); }

function go(step) {
  const n = visible().length; if (n < 2) return;
  index = Math.min(Math.max(index + step, 0), n - 1); drag = 0; render();
}

// Arrastar com o mouse/dedo troca de IA (o resto do aparelho move a janela).
const screen = document.getElementById("screen");
let startX = null;
screen.addEventListener("pointerdown", (e) => { startX = e.clientX; screen.setPointerCapture(e.pointerId); });
screen.addEventListener("pointermove", (e) => {
  if (startX === null) return;
  const dx = e.clientX - startX, n = visible().length;
  const edge = (index === 0 && dx > 0) || (index === n - 1 && dx < 0);
  drag = edge ? dx / 3 : dx; renderDisplay();
});
const end = (e) => {
  if (startX === null) return;
  const dx = e.clientX - startX; startX = null;
  if (dx < -40) go(1); else if (dx > 40) go(-1); else { drag = 0; renderDisplay(); }
};
screen.addEventListener("pointerup", end);
screen.addEventListener("pointercancel", end);
// Dois dedos no trackpad / roda lateral: um passo por gesto.
let wheel = 0, wheelLock = 0;
screen.addEventListener("wheel", (e) => {
  if (Math.abs(e.deltaX) < Math.abs(e.deltaY)) return;
  e.preventDefault();
  if (Date.now() < wheelLock) return;
  wheel += e.deltaX;
  if (Math.abs(wheel) > 60) { go(wheel > 0 ? 1 : -1); wheel = 0; wheelLock = Date.now() + 450; }
}, { passive: false });

// ---------- ajustes ----------
const $ = (id) => document.getElementById(id);
async function openSettings() {
  const s = await invoke("status");
  $("claude-state").textContent = s.claudeConnected
    ? "Conectado pela statusline. Os números chegam enquanto alguma sessão do Claude Code estiver aberta."
    : "O Claude Code só entrega os limites para a statusline. O TokenBar lê essa cópia e mantém a sua statusline atual.";
  $("connect-claude").hidden = s.claudeConnected;
  $("qr").innerHTML = s.qrSvg;
  $("code").textContent = s.code;
  $("server").value = s.server || "";
  $("server-msg").textContent = s.pushError ? `Erro ao enviar: ${s.pushError}` : "";
  $("copy-link").onclick = () => navigator.clipboard.writeText(s.link);
  $("settings").hidden = false;
}
$("close-settings").onclick = () => { $("settings").hidden = true; };
$("connect-claude").onclick = async () => {
  try { await invoke("connect_claude"); openSettings(); } catch (e) { $("claude-state").textContent = String(e); }
};
$("save-server").onclick = async () => {
  try { await invoke("set_server", { url: $("server").value }); $("server-msg").textContent = "Salvo. Escaneie o QR de novo no celular."; }
  catch (e) { $("server-msg").textContent = String(e); }
};

// ---------- primeiros passos (carrossel: um passo por tela, desenho animado em cima) ----------
const APK = "https://github.com/ChaconLucas/tokenbar/releases/latest/download/TokenBar-Android.apk";
const store = (k, v) => { try { if (v === undefined) return localStorage.getItem(k); localStorage.setItem(k, v); } catch { return null; } };
const reduced = matchMedia("(prefers-reduced-motion: reduce)");
const LOOP = 4000;   // cada desenho repete a cada 4 s (o mesmo tempo das animações do CSS)
const slides = [...document.querySelectorAll("#guide .slide")];
const dots = slides.map((s, i) => {
  const d = document.createElement("button");
  d.className = "g-dot"; d.title = s.querySelector("h2").textContent; d.onclick = () => goTo(i);
  $("g-dots").appendChild(d); return d;
});
let guideTimer = null, device = store("guideDevice"), cur = 0, t0 = 0, raf = 0, seen = {};

function goTo(i) {
  cur = Math.min(Math.max(i, 0), slides.length - 1);
  slides.forEach((s, j) => { s.classList.toggle("on", j === cur); s.classList.toggle("prev", j < cur); s.inert = j !== cur; });
  dots.forEach((d, j) => d.classList.toggle("on", j === cur));
  $("g-back").style.visibility = cur ? "visible" : "hidden";
  $("g-next").textContent = cur === slides.length - 1 ? "COMEÇAR" : "AVANÇAR →";
  t0 = performance.now(); glow();
}
const glow = () => $("g-next").classList.toggle("glow", slides[cur].classList.contains("done"));
function setDone(key, ok) {
  const i = slides.findIndex((s) => s.dataset.key === key);
  slides[i].classList.toggle("done", ok); dots[i].classList.toggle("done", ok); glow();
}
/** Etiqueta ao vivo; quando acaba de ficar verde, dá um pulso. */
function chip(id, text, ok) {
  const el = $(id), was = el.classList.contains("ok");
  el.textContent = text; el.classList.toggle("ok", !!ok);
  if (ok && !was && seen[id]) { el.classList.remove("pulse"); void el.offsetWidth; el.classList.add("pulse"); }
  seen[id] = true;
}

async function refreshGuide() {
  let s; try { s = await invoke("status"); } catch { return; }
  snapshot = s.snapshot;
  const has = (id) => s.snapshot.providers.some((p) => p.id === id);

  const skip = store("claudeSkip") === "1", claudeOk = has("claude");
  chip("g-claude", claudeOk ? "✓ Recebendo números" : skip ? "Pulado" : s.claudeConnected ? "Esperando o “oi”…" : "Esperando…", claudeOk);
  $("g-connect").hidden = claudeOk || skip || s.claudeConnected;
  $("g-connected").hidden = !(claudeOk || s.claudeConnected);
  $("g-skip").hidden = claudeOk || skip;
  setDone("claude", claudeOk || skip);

  const codexOk = has("codex");
  chip("g-codex", codexOk ? "✓ Recebendo números" : "Esperando…", codexOk);
  setDone("codex", codexOk);

  const live = s.lastClientAgo != null && s.lastClientAgo < 120;
  document.querySelectorAll(".g-pair").forEach((e) => { if (e.dataset.svg !== s.qrSvg) { e.innerHTML = s.qrSvg; e.dataset.svg = s.qrSvg; } });
  $("g-code").textContent = s.code;
  document.querySelector(".w-digits").textContent = s.code;
  if (device === "here") chip("g-phone", "✓ Só neste computador", true);
  else if (!device) chip("g-phone", "Escolha um aparelho", false);
  else if (device === "wear") chip("g-phone", live ? "✓ Relógio conectado" : "Esperando o relógio… (mesmo Wi-Fi)", live);
  else chip("g-phone", live ? "✓ Celular conectado" : "Esperando o celular… (mesmo Wi-Fi)", live);
  setDone("phone", live || device === "here");
}

function showDevice() {
  document.querySelectorAll(".choices button").forEach((b) => b.classList.toggle("on", b.dataset.dev === device));
  document.querySelectorAll("[data-for]").forEach((d) => { d.hidden = d.dataset.for !== device; });
  slides.find((s) => s.dataset.key === "phone").dataset.dev = device || "";
  if (device === "android" && !$("g-apk").innerHTML) invoke("qr", { text: APK }).then((svg) => { $("g-apk").innerHTML = svg; });
}
document.querySelectorAll(".choices button").forEach((b) => b.onclick = () => {
  device = b.dataset.dev; store("guideDevice", device); showDevice(); t0 = performance.now(); refreshGuide();
});

// --- desenhos: o palco tem tamanho fixo (320×180) e escala para caber ---
const fitStage = new ResizeObserver((es) => es.forEach(({ target: a, contentRect: r }) =>
  a.style.setProperty("--s", Math.min(r.width / 320, r.height / 180).toFixed(3))));
document.querySelectorAll(".g-art").forEach((a) => fitStage.observe(a));

const R = 4;   // resolução dos canvas (cabe a escala do palco × tela retina)
function ctxOf(c) {
  if (!c._ctx) { c._w = parseFloat(c.style.width); c._h = parseFloat(c.style.height); c.width = c._w * R; c.height = c._h * R; c._ctx = c.getContext("2d"); }
  const ctx = c._ctx; ctx.setTransform(R, 0, 0, R, 0, 0); ctx.globalAlpha = 1; ctx.clearRect(0, 0, c._w, c._h); return ctx;
}
const clamp01 = (x) => Math.min(Math.max(x, 0), 1);
const ease = (x) => 1 - (1 - clamp01(x)) ** 3;
const fade = (p) => (p > 0.93 ? Math.max(0, (1 - p) / 0.07) : 1);
function bars(ctx, w, h, cols, rows, gap, list) {
  const dot = Math.min(w / cols, h / (rows * list.length + gap * (list.length - 1)));
  const top = (h - dot * (rows * list.length + gap * (list.length - 1))) / 2, left = (w - dot * cols) / 2;
  list.forEach(([color, v], i) => { const g = new Grid(cols, rows); g.fill(v); paint(ctx, g, left, top + i * dot * (rows + gap), dot, color); });
}
const fakeWin = (pct, label, hours) => ({ label, usedPercent: pct, resetsAt: Date.now() / 1000 + hours * 3600 });

const DRAW = {
  bar(c, p) {   // barra de LED que enche com a %
    const ctx = ctxOf(c), pct = +c.dataset.pct, v = ease((p - 0.6) / 0.22) * pct;
    const cols = 26, rows = 11, dot = Math.min(c._w / cols, c._h / rows);
    const g = new Grid(cols, rows); g.fill(v / 100); g.center(`${Math.round(v)}%`, 2);
    ctx.globalAlpha = fade(p); paint(ctx, g, (c._w - cols * dot) / 2, (c._h - rows * dot) / 2, dot, c.dataset.color);
  },
  phone(c, p) {   // a tela do celular acende com os pontos
    const ctx = ctxOf(c); if (p < 0.58) return;
    ctx.globalAlpha = fade(p) * clamp01((p - 0.58) / 0.03);
    const k = ease((p - 0.6) / 0.22);
    bars(ctx, c._w, c._h, 11, 7, 3, [["#9e5cff", 0.42 * k], ["#ee29c2", 0.64 * k]]);
  },
  watch(c, p) {
    const ctx = ctxOf(c); if (p < 0.55) return;
    ctx.globalAlpha = fade(p) * clamp01((p - 0.55) / 0.03);
    const k = ease((p - 0.57) / 0.22);
    bars(ctx, c._w, c._h, 16, 4, 1, [["#9e5cff", 0.42 * k], ["#ee29c2", 0.64 * k]]);
  },
  device(c, p) {   // o aparelho: enche, e o dedo arrasta de CLAUDE para CODEX
    const ctx = ctxOf(c), w = c._w, h = c._h, k = ease((p - 0.36) / 0.16);
    const off = -w * ease((p - 0.6) / 0.18);
    const pages = [[[fakeWin(42 * k, "5H", 3), fakeWin(18 * k, "7D", 100)], "#9e5cff"], [[fakeWin(64, "5H", 2), fakeWin(30, "7D", 80)], "#ee29c2"]];
    pages.forEach(([ws, col], i) => { ctx.save(); ctx.translate(off + i * w, 0); drawPage(ctx, w, h, ws, col); ctx.restore(); });
  },
  qr(c) {   // um QR de enfeite (não é o de verdade)
    if (c._done) return; const ctx = ctxOf(c); c._done = true;
    const n = 21, m = c._w / (n + 2); let seed = 11;
    const rnd = () => ((seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff);
    ctx.fillStyle = "#fff"; ctx.beginPath(); ctx.roundRect(0, 0, c._w, c._h, 6); ctx.fill(); ctx.fillStyle = "#000";
    const finder = (x, y) => {
      for (const [fx, fy] of [[0, 0], [n - 7, 0], [0, n - 7]]) {
        const dx = x - fx, dy = y - fy;
        if (dx >= -1 && dy >= -1 && dx <= 7 && dy <= 7) {
          if (dx < 0 || dy < 0 || dx > 6 || dy > 6) return false;
          const e = Math.min(dx, dy, 6 - dx, 6 - dy); return e !== 1;
        }
      }
      return null;
    };
    for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) {
      const f = finder(x, y); if (f === null ? rnd() < 0.47 : f) ctx.fillRect((x + 1) * m, (y + 1) * m, m + 0.1, m + 0.1);
    }
  },
};
function tick(t) {
  raf = 0; if ($("guide").hidden) return;
  const p = reduced.matches ? 0.9 : (((t - t0) % LOOP) + LOOP) % LOOP / LOOP;
  slides[cur].querySelectorAll("canvas[data-draw]").forEach((c) => { if (c.getClientRects().length) DRAW[c.dataset.draw](c, p); });
  raf = requestAnimationFrame(tick);
}

function openGuide() {
  if (isMini) return;
  $("settings").hidden = true;
  $("guide").hidden = false; seen = {};
  showDevice(); goTo(0); refreshGuide();
  clearInterval(guideTimer); guideTimer = setInterval(refreshGuide, 3000);
  if (!raf) raf = requestAnimationFrame(tick);
}
function closeGuide() {
  $("guide").hidden = true; clearInterval(guideTimer); guideTimer = null;
  cancelAnimationFrame(raf); raf = 0;
  store("guideDone", "1"); render();
}
$("g-pular").onclick = closeGuide;
$("g-back").onclick = () => goTo(cur - 1);
$("g-next").onclick = () => (cur === slides.length - 1 ? closeGuide() : goTo(cur + 1));
$("open-guide").onclick = openGuide;
$("g-connect").onclick = async () => {
  try { await invoke("connect_claude"); refreshGuide(); } catch (e) { chip("g-claude", String(e), false); }
};
$("g-skip").onclick = (e) => { e.preventDefault(); store("claudeSkip", "1"); refreshGuide(); };
document.addEventListener("keydown", (e) => {
  if ($("guide").hidden) return;
  if (e.key === "ArrowRight") goTo(cur + 1);
  else if (e.key === "ArrowLeft") goTo(cur - 1);
  else if (e.key === "Escape") closeGuide();
});

// ---------- dados ----------
listen("snapshot", (e) => { snapshot = e.payload; render(); });
invoke("status").then((s) => { snapshot = s.snapshot; render(); });
if (!isMini) {
  listen("show-guide", openGuide);
  if (store("guideDone") !== "1") openGuide();   // primeira abertura
}
new ResizeObserver(renderDisplay).observe(canvas);
setInterval(renderDisplay, 1000);   // contagem regressiva

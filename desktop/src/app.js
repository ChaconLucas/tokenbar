// O aparelho: teclas de LED, display que troca de IA arrastando (ou rolando para o lado), ajustes.
import { drawPage, keyCanvas } from "./led.js";

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

// ---------- primeiros passos ----------
const APK = "https://github.com/ChaconLucas/tokenbar/releases/latest/download/TokenBar-Android.apk";
const store = (k, v) => { try { if (v === undefined) return localStorage.getItem(k); localStorage.setItem(k, v); } catch { return null; } };
let guideTimer = null, device = store("guideDevice");

function mark(stepId, done) { $(stepId).classList.toggle("done", done); }
function say(el, text, ok) { el.textContent = text; el.classList.toggle("ok", !!ok); }

async function refreshGuide() {
  let s; try { s = await invoke("status"); } catch { return; }
  snapshot = s.snapshot;
  const has = (id) => s.snapshot.providers.some((p) => p.id === id);

  const skip = store("claudeSkip") === "1";
  const claudeOk = has("claude");
  if (claudeOk) say($("g-claude"), "✓ Recebendo os números", true);
  else if (skip) say($("g-claude"), "Pulado.", true);
  else if (s.claudeConnected) say($("g-claude"), "Conectado. Mande qualquer mensagem numa sessão do Claude Code para os números chegarem.");
  else say($("g-claude"), "O Claude Code só entrega os limites para a statusline. O TokenBar guarda uma cópia e mantém a sua statusline.");
  $("g-claude-act").hidden = claudeOk || skip || s.claudeConnected;
  mark("step-claude", claudeOk || skip);

  const codexOk = has("codex");
  say($("g-codex"), codexOk ? "✓ Recebendo os números" : "Use o Codex uma vez: os limites chegam com a primeira resposta.", codexOk);
  mark("step-codex", codexOk);

  const live = s.lastClientAgo != null && s.lastClientAgo < 120;
  document.querySelectorAll(".g-pair").forEach((e) => { if (e.dataset.svg !== s.qrSvg) { e.innerHTML = s.qrSvg; e.dataset.svg = s.qrSvg; } });
  document.querySelectorAll(".g-live").forEach((e) => say(e, live ? "✓ Celular conectado" : "Esperando o celular… (mesmo Wi-Fi)", live));
  $("g-code").textContent = s.code;
  mark("step-phone", live || device === "here");
}

function showDevice() {
  document.querySelectorAll(".choices button").forEach((b) => b.classList.toggle("on", b.dataset.dev === device));
  document.querySelectorAll("[data-for]").forEach((d) => { d.hidden = d.dataset.for !== device; });
  if (device === "android" && !$("g-apk").innerHTML) invoke("qr", { text: APK }).then((svg) => { $("g-apk").innerHTML = svg; });
}
document.querySelectorAll(".choices button").forEach((b) => b.onclick = () => {
  device = b.dataset.dev; store("guideDevice", device); showDevice(); refreshGuide();
});

function openGuide() {
  if (isMini) return;
  $("settings").hidden = true;
  $("guide").hidden = false; $("guide").scrollTop = 0;
  showDevice(); refreshGuide();
  clearInterval(guideTimer); guideTimer = setInterval(refreshGuide, 3000);
}
function closeGuide() {
  $("guide").hidden = true; clearInterval(guideTimer); guideTimer = null;
  store("guideDone", "1"); render();
}
$("close-guide").onclick = closeGuide;
$("g-start").onclick = closeGuide;
$("open-guide").onclick = openGuide;
$("g-connect").onclick = async () => {
  try { await invoke("connect_claude"); refreshGuide(); } catch (e) { say($("g-claude"), String(e)); }
};
$("g-skip").onclick = (e) => { e.preventDefault(); store("claudeSkip", "1"); refreshGuide(); };

// ---------- dados ----------
listen("snapshot", (e) => { snapshot = e.payload; render(); });
invoke("status").then((s) => { snapshot = s.snapshot; render(); });
if (!isMini) {
  listen("show-guide", openGuide);
  if (store("guideDone") !== "1") openGuide();   // primeira abertura
}
new ResizeObserver(renderDisplay).observe(canvas);
setInterval(renderDisplay, 1000);   // contagem regressiva

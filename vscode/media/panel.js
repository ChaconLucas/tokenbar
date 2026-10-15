// Usage view (Activity Bar → TokenBar): the LED device of the TokenBar apps, one display per AI.
// Data comes from the extension ("snapshot" messages); clicks go back as messages.
(function () {
  const vscode = acquireVsCodeApi();
  const LED = window.TokenBarLED;
  const root = document.getElementById("root");
  const ratio = () => window.devicePixelRatio || 1;
  let state = { providers: [], choice: "5h", strings: {} };
  const s = (k) => state.strings[k] || "";
  const narrow = () => root.clientWidth < 330;

  /** Text in dots, lit in a color (or dimmed): the keys and the names on the device. */
  function dotText(text, color, dot, on = true) {
    const g = new LED.Grid(Math.max(1, LED.textWidth(text)), 7);
    g.draw(text, 0, 0);
    const c = document.createElement("canvas");
    const r = ratio();
    c.width = Math.ceil(g.cols * dot * r); c.height = Math.ceil(7 * dot * r);
    c.style.width = g.cols * dot + "px"; c.style.height = 7 * dot + "px";
    const ctx = c.getContext("2d"); ctx.scale(r, r);
    const size = dot * 0.84;
    ctx.fillStyle = on ? color : "rgba(255,255,255,0.28)";
    if (on) { ctx.shadowColor = color; ctx.shadowBlur = dot * 1.2; }
    for (let y = 0; y < 7; y++) for (let x = 0; x < g.cols; x++) if (g.cells[y * g.cols + x] === 2) {
      ctx.beginPath(); ctx.arc(x * dot + size / 2, y * dot + size / 2, size / 2, 0, Math.PI * 2); ctx.fill();
    }
    return c;
  }

  function key(text, color, on, title, onClick) {
    const b = document.createElement("button");
    b.className = "key" + (on ? " on" : "");
    b.title = title; b.setAttribute("aria-label", title);
    b.setAttribute("aria-pressed", String(on));
    if (on) b.style.setProperty("--c", color);
    b.append(dotText(text, color, 1.6, on));
    b.onclick = onClick;
    return b;
  }

  /** The windows a display shows under the current choice (same rule as the status bar). */
  function pick(p) {
    const ws = p.windows || [];
    const lbl = (w) => w && { ...w, label: w.label || w.id };
    if (state.choice === "7d") return [lbl(ws[1] || ws[0]) || null];
    if (state.choice === "both") return ws.length ? ws.slice(0, 2).map(lbl) : [null];
    return [lbl(ws[0]) || null];
  }

  const keyName = (p, many) => (many ? p.abbr : p.name.toUpperCase().replace(/[^A-Z0-9 ]/g, "").slice(0, 8)) || p.abbr;

  function renderKeys(device) {
    const bar = document.createElement("header");
    bar.className = "keys";
    const ais = document.createElement("div");
    ais.className = "ais";
    // Abbreviations ("CL") when there are many AIs or the view is narrow, so the keys stay on one line.
    const many = state.providers.length > 2 || (state.providers.length > 1 && narrow());
    for (const p of state.providers) {
      ais.append(key(keyName(p, many), p.color, p.on, (s("toggleAi") || "{0}").replace("{0}", p.name),
        () => vscode.postMessage({ type: "toggleProvider", id: p.id })));
    }
    const label = { "5h": "5H", "7d": "7D", both: "5H 7D" }[state.choice] || "5H";
    const next = { "5h": "7d", "7d": "both", both: "5h" }[state.choice] || "5h";
    const win = key(label, "#ffffff", true, s("window"), () => {
      state.choice = next; render(); // instant feedback; the extension confirms with a new snapshot
      vscode.postMessage({ type: "setWindow", choice: next });
    });
    win.classList.add("win");
    bar.append(ais, win);
    device.append(bar);
  }

  function display(p, i) {
    const a = document.createElement("article");
    a.className = "ai";
    const name = document.createElement("div");
    name.className = "name";
    name.append(dotText(p.name.toUpperCase().replace(/[^A-Z0-9 .\-+/]/g, "").slice(0, 16) || p.abbr, p.color, 1.4));
    const c = document.createElement("canvas");
    c.className = "display"; c.dataset.i = String(i);
    c.setAttribute("role", "img");
    a.append(name, c);
    return a;
  }

  /** Sizes each canvas to its box (dot ≤ 3 CSS px) and draws it; runs every second for the countdown. */
  function drawDisplays() {
    const shown = state.providers.filter((p) => p.on);
    for (const c of root.querySelectorAll("canvas.display")) {
      const p = shown[Number(c.dataset.i)];
      const ws = p ? pick(p) : [null];
      const rows = ws.length;
      const w = c.parentElement.clientWidth;
      if (!w) continue;
      const dot = Math.min(w / 110, 3);
      const h = Math.round(dot * (26 * rows + 3 * (rows - 1)));
      const r = ratio();
      if (c.style.height !== h + "px") c.style.height = h + "px";
      if (c.width !== Math.round(w * r) || c.height !== Math.round(h * r)) { c.width = Math.round(w * r); c.height = Math.round(h * r); }
      const ctx = c.getContext("2d");
      ctx.setTransform(r, 0, 0, r, 0, 0);
      LED.drawPage(ctx, w, h, ws, p ? p.color : "#9e5cff");
      if (p) c.setAttribute("aria-label", p.name + ": " + ws.map((x) => x ? `${x.label} ${Math.round(LED.used(x))}%` : "").join(", "));
    }
  }

  function render() {
    root.textContent = "";
    const device = document.createElement("section");
    device.className = "device";
    root.append(device);
    if (!state.providers.length) {
      device.classList.add("empty");
      const c = document.createElement("canvas");
      c.className = "display"; c.dataset.i = "0";
      const box = document.createElement("article");
      box.className = "ai"; box.append(c);
      device.append(box);
      const p = document.createElement("p");
      p.className = "hint";
      p.textContent = s("hint") || s("empty");
      const b = document.createElement("button");
      b.className = "cta";
      b.textContent = s("openApp") || "TokenBar";
      b.onclick = () => vscode.postMessage({ type: "openApp" });
      root.append(p, b);
    } else {
      renderKeys(device);
      const grid = document.createElement("div");
      grid.className = "grid";
      state.providers.filter((p) => p.on).forEach((p, i) => grid.append(display(p, i)));
      device.append(grid);
    }
    drawDisplays();
  }

  window.addEventListener("message", (e) => {
    const m = e.data;
    if (m && m.type === "snapshot") {
      state = { providers: m.providers || [], choice: m.choice || "5h", strings: m.strings || {} };
      LED.setText((k) => (k === "SEM DADOS" ? (state.strings.noData || k) : k));
      vscode.setState(state);
      render();
    }
  });

  let last = 0;
  let wasNarrow = narrow();
  new ResizeObserver(() => {
    const w = root.clientWidth;
    if (w === last) return;
    last = w;
    if (narrow() !== wasNarrow) { wasNarrow = narrow(); render(); } else drawDisplays();
  }).observe(root);
  setInterval(drawDisplays, 1000); // countdown
  const saved = vscode.getState();
  if (saved && saved.providers) { state = saved; render(); }
  vscode.postMessage({ type: "ready" });
})();

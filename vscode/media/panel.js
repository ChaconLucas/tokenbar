// Details panel: one LED display per AI (both windows), in the look of the TokenBar device.
(function () {
  const vscode = acquireVsCodeApi();
  const LED = window.TokenBarLED;
  const root = document.getElementById("root");
  let state = { providers: [], strings: {} };

  /** Name in dots, lit in the AI's color (like the keys on the device). */
  function nameCanvas(text, color, dot) {
    const label = text.toUpperCase().slice(0, 14);
    const g = new LED.Grid(LED.textWidth(label), 7);
    g.draw(label, 0, 0);
    const c = document.createElement("canvas");
    const ratio = window.devicePixelRatio || 1;
    c.width = Math.ceil(g.cols * dot * ratio); c.height = Math.ceil(7 * dot * ratio);
    c.style.width = g.cols * dot + "px"; c.style.height = 7 * dot + "px";
    const ctx = c.getContext("2d"); ctx.scale(ratio, ratio);
    const size = dot * 0.84;
    ctx.fillStyle = color;
    for (let y = 0; y < 7; y++) for (let x = 0; x < g.cols; x++) if (g.cells[y * g.cols + x] === 2) {
      ctx.beginPath(); ctx.arc(x * dot + size / 2, y * dot + size / 2, size / 2, 0, Math.PI * 2); ctx.fill();
    }
    return c;
  }

  function drawDisplays() {
    for (const c of root.querySelectorAll("canvas.display")) {
      const p = state.providers[Number(c.dataset.i)];
      if (!p) continue;
      const ratio = window.devicePixelRatio || 1;
      const w = c.clientWidth, h = c.clientHeight;
      if (!w || !h) continue;
      if (c.width !== Math.round(w * ratio)) { c.width = Math.round(w * ratio); c.height = Math.round(h * ratio); }
      const ctx = c.getContext("2d");
      ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
      LED.drawPage(ctx, w, h, p.windows.slice(0, 2).map((w) => ({ ...w, label: w.label || w.id })), p.color);
    }
  }

  function render() {
    root.textContent = "";
    if (!state.providers.length) {
      const empty = document.createElement("section");
      empty.className = "device empty";
      const c = document.createElement("canvas");
      c.className = "display"; c.dataset.i = "0";
      empty.append(c);
      const p = document.createElement("p");
      p.textContent = state.strings.empty || "";
      const a = document.createElement("button");
      a.textContent = state.strings.openApp || "TokenBar";
      a.onclick = () => vscode.postMessage({ type: "openApp" });
      root.append(empty, p, a);
      state.providers = [];
      requestAnimationFrame(() => {
        const ctx = c.getContext("2d"); const r = window.devicePixelRatio || 1;
        c.width = c.clientWidth * r; c.height = c.clientHeight * r; ctx.scale(r, r);
        LED.drawPage(ctx, c.clientWidth, c.clientHeight, [null], "#9e5cff");
      });
      return;
    }
    state.providers.forEach((p, i) => {
      const s = document.createElement("section");
      s.className = "device";
      s.style.setProperty("--accent", p.color);
      const head = document.createElement("header");
      head.append(nameCanvas(p.name, p.color, 2.2));
      const c = document.createElement("canvas");
      c.className = "display"; c.dataset.i = String(i);
      c.style.height = (p.windows.length > 1 ? 150 : 74) + "px";
      s.append(head, c);
      root.append(s);
    });
    requestAnimationFrame(drawDisplays);
  }

  window.addEventListener("message", (e) => {
    const m = e.data;
    if (m && m.type === "snapshot") {
      state = m;
      LED.setText((k) => (k === "SEM DADOS" ? (m.strings.noData || k) : k));
      render();
    }
  });
  new ResizeObserver(drawDisplays).observe(root);
  setInterval(drawDisplays, 1000); // countdown
  vscode.postMessage({ type: "ready" });
})();

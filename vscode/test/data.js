// Prints what the data layer reads on this machine (numbers only, no file dumps).
// Usage: npx tsc -p . && node test/data.js
const d = require("../out/data.js");
(async () => {
  const fmt = (t) => (t ? new Date(t * 1000).toISOString() : "-");
  for (const [label, snap] of [["collect()", await d.collect()], ["readDirect()", await d.readDirect()]]) {
    console.log(`\n== ${label}: source=${snap.source} providers=${snap.providers.length}`);
    for (const p of snap.providers) {
      console.log(`${d.abbrOf(p)} ${p.id} "${p.name}" color=${d.colorOf(p)} observed=${fmt(p.observedAt)}`);
      for (const w of p.windows)
        console.log(`   ${w.label.padEnd(4)} used=${w.usedPercent}% now=${d.usedNow(w)}% resets=${fmt(w.resetsAt)} min=${w.windowMinutes ?? "-"}`);
    }
  }
})();

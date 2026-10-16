#!/usr/bin/env node
// TokenBar UserPromptSubmit hook: warns when a Claude Code usage window is at or above 80%.
// Silent below the threshold, at most one warning every 30 min (state in ~/.tokenbar/plugin-hook.json),
// and never blocks the prompt: any error or a slow read (> 250 ms) just exits 0 with no output.
// TOKENBAR_HOOK_PERCENT overrides the threshold; TOKENBAR_DIR overrides ~/.tokenbar (tests).
import fs from "node:fs";
import path from "node:path";
import { loadUsage, findProvider, duration, fmtPct, tokenbarDir, nowSec } from "../server/lib/data.mjs";

const THRESHOLD = Number(process.env.TOKENBAR_HOOK_PERCENT) || 80;
const QUIET_FOR = 30 * 60;
const BUDGET_MS = 250;

const stateFile = () => path.join(tokenbarDir(), "plugin-hook.json");

function lastShown() {
  try { return Number(JSON.parse(fs.readFileSync(stateFile(), "utf8")).lastShownAt) || 0; } catch { return 0; }
}

async function main() {
  if (nowSec() - lastShown() < QUIET_FOR) return;
  const usage = await Promise.race([loadUsage(), new Promise((r) => setTimeout(r, BUDGET_MS).unref())]);
  const p = usage && findProvider(usage, "claude");
  if (!p) return;
  const w = [...p.windows].sort((a, b) => b.usedNow - a.usedNow)[0];
  if (!w || w.usedNow < THRESHOLD) return;
  const reset = w.resetsInSeconds ? `, resets in ${duration(w.resetsInSeconds)}` : "";
  const msg = `TokenBar: Claude ${w.label || w.id} at ${fmtPct(w.usedNow)}${reset} — consider postponing long tasks.`;
  try {
    fs.mkdirSync(tokenbarDir(), { recursive: true });
    fs.writeFileSync(stateFile(), JSON.stringify({ lastShownAt: Math.round(nowSec()) }) + "\n");
  } catch { /* still warn once */ }
  process.stdout.write(JSON.stringify({
    systemMessage: msg,
    hookSpecificOutput: {
      hookEventName: "UserPromptSubmit",
      additionalContext: `TokenBar: the user's Claude Code ${w.label || w.id} usage window is at ${fmtPct(w.usedNow)}${reset}. Long or expensive work may hit the limit; mention it before starting such work and prefer small steps.`,
    },
  }) + "\n");
}

main().catch(() => {}).finally(() => process.exit(0));

#!/usr/bin/env node
// tokenbar-mcp — MCP server (stdio) that lets AI agents read their own usage limits.
// JSON-RPC 2.0, one message per line (MCP stdio transport). Zero dependencies, Node >= 18.
// stdout carries only protocol messages; logs go to stderr.
//
// Claude Code: claude mcp add tokenbar --scope user -- node ~/.tokenbar/cli/mcp.mjs
import readline from "node:readline";
import { VERSION, loadUsage, findProvider, findWindow, duration, fmtPct, summaryLine } from "./lib/data.mjs";

const PROTOCOL_VERSION = "2025-06-18";
const SUPPORTED = new Set(["2025-06-18", "2025-03-26", "2024-11-05"]);

const WINDOW_SCHEMA = {
  type: "string",
  description: 'Limit window: "5h" (short window, the first) or "7d" (long window, the second). Labels like "1d" or "30d" also work.',
};

const TOOLS = [
  {
    name: "get_usage",
    title: "Get AI usage limits",
    description:
      "Current usage of AI subscription limits (Claude Code, Codex, GitHub Copilot, Windsurf and any AI the user added to TokenBar). " +
      "For each AI: windows (usually 5h and 7d) with usedNow (% used right now, 0 after the reset time), resetsAt (unix s) and resetsInSeconds.",
    inputSchema: {
      type: "object",
      properties: { provider: { type: "string", description: 'Optional provider id: "claude", "codex", "copilot", "windsurf" or another id. Omit for all.' } },
      additionalProperties: false,
    },
    annotations: { readOnlyHint: true, openWorldHint: false },
  },
  {
    name: "time_until_reset",
    title: "Time until a usage limit resets",
    description: "Seconds (and human text) until a provider's usage window resets. Default window: the first (5h).",
    inputSchema: {
      type: "object",
      properties: { provider: { type: "string", description: 'Provider id, e.g. "claude" or "codex".' }, window: WINDOW_SCHEMA },
      required: ["provider"],
      additionalProperties: false,
    },
    annotations: { readOnlyHint: true, openWorldHint: false },
  },
  {
    name: "check_budget",
    title: "Check whether there is usage budget left",
    description:
      "Checks if a provider is below a usage threshold, so you can decide whether to start a long or expensive task now or postpone it until the limit resets. " +
      "Without `window`, checks every window and reports the tightest one. Returns ok, usedNow, resetsInSeconds and advice.",
    inputSchema: {
      type: "object",
      properties: {
        provider: { type: "string", description: 'Provider id, e.g. "claude" or "codex".' },
        max_percent: { type: "number", description: "Budget threshold in percent (default 80). ok = usedNow < max_percent.", minimum: 0, maximum: 1000 },
        window: WINDOW_SCHEMA,
      },
      required: ["provider"],
      additionalProperties: false,
    },
    annotations: { readOnlyHint: true, openWorldHint: false },
  },
];

// MARK: tools

class ToolError extends Error {}

const text = (s) => [{ type: "text", text: s }];
const STALE_AFTER = 30 * 60;

async function needProvider(id) {
  if (!id || typeof id !== "string") throw new ToolError('Missing "provider" (e.g. "claude").');
  const usage = await loadUsage();
  if (!usage.providers.length) throw new ToolError("No usage data: the TokenBar app is not running and no Claude Code/Codex usage files were found.");
  const p = findProvider(usage, id);
  if (!p) throw new ToolError(`Unknown provider "${id}". Available: ${usage.providers.map((x) => x.id).join(", ")}.`);
  return p;
}

function needWindow(p, win) {
  const w = findWindow(p, win);
  if (!w) throw new ToolError(`${p.name} has no window "${win}". Available: ${p.windows.map((x) => x.label || x.id).join(", ")}.`);
  return w;
}

const ageNote = (p) => {
  if (!p.observedAt) return "";
  const age = Date.now() / 1000 - p.observedAt;
  return age > STALE_AFTER ? ` Note: this number was read ${duration(age)} ago and may be outdated (it updates when the AI is used).` : "";
};

const TOOL_IMPL = {
  async get_usage({ provider } = {}) {
    if (provider) {
      const p = await needProvider(provider);
      return { content: text(summaryLine(p) + ageNote(p)), structuredContent: p };
    }
    const usage = await loadUsage();
    const body = usage.providers.length
      ? usage.providers.map(summaryLine).join("\n")
      : "No usage data: the TokenBar app is not running and no Claude Code/Codex usage files were found.";
    return { content: text(body), structuredContent: usage };
  },

  async time_until_reset({ provider, window } = {}) {
    const p = await needProvider(provider);
    const w = needWindow(p, window);
    const s = w.resetsInSeconds;
    const human = s === null ? "unknown (no reset time reported)" : s === 0 ? "already reset" : `in ${duration(s)}`;
    return {
      content: text(`${p.name} ${w.label || w.id} window resets ${human}${w.resetsAt ? ` (${new Date(w.resetsAt * 1000).toISOString()})` : ""}. Used now: ${fmtPct(w.usedNow)}.`),
      structuredContent: { provider: p.id, window: w.label || w.id, seconds: s, resetsAt: w.resetsAt, human, usedNow: w.usedNow },
    };
  },

  async check_budget({ provider, max_percent, window } = {}) {
    const p = await needProvider(provider);
    const max = typeof max_percent === "number" && Number.isFinite(max_percent) ? max_percent : 80;
    // Without a window, the binding one is the most used.
    const w = window ? needWindow(p, window) : [...p.windows].sort((a, b) => b.usedNow - a.usedNow)[0];
    const label = w.label || w.id;
    const ok = w.usedNow < max;
    const when = w.resetsInSeconds === null ? "at an unknown time" : `in ${duration(w.resetsInSeconds)}`;
    const advice = ok
      ? `OK: ${p.name} ${label} window is at ${fmtPct(w.usedNow)} (budget ${max}%, ${Math.round(max - w.usedNow)} points left). Fine to proceed; for a very long task, work in steps and check again.`
      : `Over budget: ${p.name} ${label} window is at ${fmtPct(w.usedNow)} (budget ${max}%). It resets ${when}. Postpone large tasks until then, or keep the work small.`;
    return {
      content: text(advice + ageNote(p)),
      structuredContent: {
        ok, provider: p.id, window: label, maxPercent: max, usedNow: w.usedNow,
        resetsInSeconds: w.resetsInSeconds, resetsAt: w.resetsAt, observedAt: p.observedAt, advice,
        windows: p.windows.map((x) => ({ label: x.label || x.id, usedNow: x.usedNow, resetsInSeconds: x.resetsInSeconds })),
      },
    };
  },
};

// MARK: JSON-RPC

const send = (msg) => process.stdout.write(JSON.stringify(msg) + "\n");
const reply = (id, result) => send({ jsonrpc: "2.0", id, result });
const fail = (id, code, message) => send({ jsonrpc: "2.0", id, error: { code, message } });

async function handle(msg) {
  if (!msg || typeof msg !== "object" || msg.jsonrpc !== "2.0" || typeof msg.method !== "string") {
    if (msg && typeof msg === "object" && ("result" in msg || "error" in msg)) return; // response to us: none expected
    return fail(msg?.id ?? null, -32600, "Invalid Request");
  }
  const { id, method, params } = msg;
  const isNotification = id === undefined;

  switch (method) {
    case "initialize": {
      const asked = params?.protocolVersion;
      return reply(id, {
        protocolVersion: SUPPORTED.has(asked) ? asked : PROTOCOL_VERSION,
        capabilities: { tools: {} },
        serverInfo: { name: "tokenbar", title: "TokenBar", version: VERSION },
        instructions:
          "TokenBar reports the user's AI usage limits (Claude Code, Codex, Copilot, Windsurf…). " +
          "Before starting a long or expensive task, call check_budget for the provider you run on; if ok is false, tell the user and suggest waiting until the reset.",
      });
    }
    case "notifications/initialized":
    case "notifications/cancelled":
      return;
    case "ping":
      return isNotification ? undefined : reply(id, {});
    case "tools/list":
      return reply(id, { tools: TOOLS });
    case "tools/call": {
      const name = params?.name;
      const impl = TOOL_IMPL[name];
      if (!impl) return fail(id, -32602, `Unknown tool: ${name}`);
      try {
        return reply(id, await impl(params?.arguments || {}));
      } catch (e) {
        if (e instanceof ToolError) return reply(id, { content: text(e.message), isError: true });
        console.error("tokenbar-mcp:", e);
        return reply(id, { content: text(`Internal error: ${e?.message || e}`), isError: true });
      }
    }
    default:
      if (isNotification) return;
      return fail(id, -32601, `Method not found: ${method}`);
  }
}

const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
const pending = new Set();
rl.on("line", (line) => {
  if (!line.trim()) return;
  let msg;
  try { msg = JSON.parse(line); } catch { return fail(null, -32700, "Parse error"); }
  const job = (Array.isArray(msg) ? Promise.all(msg.map(handle)) : handle(msg)).catch((e) => console.error("tokenbar-mcp:", e));
  pending.add(job);
  job.finally(() => pending.delete(job));
});
rl.on("close", async () => { await Promise.all(pending); process.exit(0); });

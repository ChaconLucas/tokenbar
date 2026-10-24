// TokenBar — guarda o último retrato de uso de cada pessoa.
// A pessoa é identificada pelo hash do token (o servidor nunca guarda o token em si).
// PUT /v1/usage  (Mac envia)   GET /v1/usage (iPhone/Watch leem)   GET /health
// Sites no navegador só leem (GET, com o token) se estiverem em ALLOWED_ORIGINS: a HomeTown, o escritório virtual,
// mostra o uso de IA de quem colou o próprio token no painel do TokenBar.

const MAX_BODY = 16 * 1024;
const ALLOWED_ORIGINS = ["https://hometown.victormotta.dev.br", "http://localhost:5173"];

export default {
  async fetch(req, env) {
    const url = new URL(req.url);

    if (url.pathname === "/health") return json({ ok: true });
    if (url.pathname !== "/v1/usage") return json({ error: "not_found" }, 404);

    const cors = corsHeaders(req);
    // O navegador pergunta antes (o "preflight"), e só um site da lista recebe o sim.
    if (req.method === "OPTIONS") return new Response(null, { status: cors ? 204 : 403, headers: cors ?? {} });

    const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    if (!/^[A-Za-z0-9_-]{32,128}$/.test(token)) return json({ error: "unauthorized" }, 401, req.method === "GET" ? cors : null);
    const id = await sha256(token);

    if (req.method === "GET") {
      const row = await env.DB.prepare("SELECT body FROM usage WHERE id = ?").bind(id).first();
      if (!row) return json({ error: "no_data" }, 404, cors);
      return new Response(row.body, { headers: { "Content-Type": "application/json", "Cache-Control": "no-store", ...(cors ?? {}) } });
    }

    if (req.method === "PUT") {
      const body = await req.text();
      if (body.length > MAX_BODY) return json({ error: "too_large" }, 413);
      let parsed;
      try { parsed = JSON.parse(body); } catch { return json({ error: "bad_json" }, 400); }
      if (!Array.isArray(parsed.providers)) return json({ error: "bad_shape" }, 400);

      await env.DB.prepare(
        "INSERT INTO usage (id, body, updated_at) VALUES (?1, ?2, ?3) " +
        "ON CONFLICT(id) DO UPDATE SET body = ?2, updated_at = ?3"
      ).bind(id, body, Math.floor(Date.now() / 1000)).run();
      return new Response(null, { status: 204 });
    }

    return json({ error: "method_not_allowed" }, 405);
  },
};

function json(obj, status = 200, cors = null) {
  return new Response(JSON.stringify(obj), { status, headers: { "Content-Type": "application/json", ...(cors ?? {}) } });
}

/** O CORS para um site da lista (só a leitura, com o token no Authorization); para os outros, nada. */
function corsHeaders(req) {
  const origin = req.headers.get("Origin");
  if (!origin || !ALLOWED_ORIGINS.includes(origin)) return null;
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Methods": "GET",
    "Access-Control-Allow-Headers": "Authorization",
    "Access-Control-Max-Age": "600",
    Vary: "Origin",
  };
}

async function sha256(text) {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

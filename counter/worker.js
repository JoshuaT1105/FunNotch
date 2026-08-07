/*
  Download counter for the FunNotch site — a Cloudflare Worker over one KV
  namespace.

  GET  returns { "total": N }
  POST increments and returns the new { "total": N }

  Only needed if the binaries are not on GitHub Releases. If they are, set
  GITHUB_REPO in the site's app.js instead and delete this: GitHub already
  counts completed downloads, exactly, for free, and nobody can inflate it.
*/

// Origins allowed to increment. A counter anyone can POST to from anywhere is
// a counter that means nothing, so reads are open and writes are not.
const ALLOWED_ORIGINS = [
  "https://funnotch.xyz",
  "https://www.funnotch.xyz",
];

const TOTAL_KEY = "downloads";

// One counted click per address per ten minutes. This is not security — it is
// there so a held-down refresh key can't write a number nobody believes.
const REVISIT_SECONDS = 600;

export default {
  async fetch(request, env) {
    const origin = request.headers.get("Origin") || "";
    const trusted = ALLOWED_ORIGINS.includes(origin);

    const cors = {
      "Access-Control-Allow-Origin": trusted ? origin : ALLOWED_ORIGINS[0],
      "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
      "Access-Control-Max-Age": "86400",
      Vary: "Origin",
    };

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors });
    }

    const total = async () => Number(await env.COUNTER.get(TOTAL_KEY)) || 0;

    const reply = (value) =>
      new Response(JSON.stringify({ total: value }), {
        headers: {
          ...cors,
          "Content-Type": "application/json",
          "Cache-Control": "no-store",
        },
      });

    if (request.method !== "POST") return reply(await total());

    if (!trusted) {
      return new Response(JSON.stringify({ error: "origin not allowed" }), {
        status: 403,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    const address = request.headers.get("CF-Connecting-IP") || "";
    const recent = address ? `seen:${address}` : "";

    // Already counted this visitor: hand back the current figure unchanged
    // rather than an error, so the page just shows the right number.
    if (recent && (await env.COUNTER.get(recent))) return reply(await total());

    // Read-add-write, not an atomic increment: KV has no such operation, so
    // two clicks in the same instant can land on the same number and one is
    // lost. For a download count on a marketing page that is a fine trade —
    // if it ever isn't, this wants a Durable Object instead.
    const next = (await total()) + 1;
    await env.COUNTER.put(TOTAL_KEY, String(next));
    if (recent) {
      await env.COUNTER.put(recent, "1", { expirationTtl: REVISIT_SECONDS });
    }

    return reply(next);
  },
};

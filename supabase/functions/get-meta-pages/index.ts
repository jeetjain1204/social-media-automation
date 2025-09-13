import { serve } from "std/http/server.ts";
import "https://deno.land/x/dotenv/load.ts";

/* ─────────── CORS ─────────── */
const CORS = {
  "Access-Control-Allow-Origin":  "*",
  "Access-Control-Allow-Headers": "content-type, authorization, apikey, x-client-info, x-no-cache",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Max-Age":       "86400",
  "Access-Control-Expose-Headers":"x-cache",
  "Vary":                         "Origin, Access-Control-Request-Headers",
} as const;
const JSON_HEADERS = { "Content-Type": "application/json; charset=utf-8", ...CORS } as const;

/* ─────────── ULTRA-LIGHT HELPERS ─────────── */
// OPT: 12s cap to avoid hanging/billed time
function fetchWithTimeout(url: string, init: RequestInit = {}, ms = 12000) {
  const ac = new AbortController();
  const id = setTimeout(() => ac.abort(), ms);
  return fetch(url, { ...init, signal: ac.signal }).finally(() => clearTimeout(id));
}
type Entry = { v: string; exp: number };
const L1 = new Map<string, Entry>();
const l1Get = (k: string) => {
  const e = L1.get(k);
  if (!e) return null;
  if (e.exp < Date.now()) { L1.delete(k); return null; }
  return e.v;
};
const l1Set = (k: string, v: string, ttlSec: number) => L1.set(k, { v, exp: Date.now() + ttlSec * 1000 });
async function sha256Hex(s: string) {
  const h = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return Array.from(new Uint8Array(h)).map(b => b.toString(16).padStart(2,"0")).join("");
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });

  try {
    /* ---- Parse access_token from POST body (original) or GET fallback ---- */
    let accessToken: string | undefined;
    if (req.method === "GET") {
      accessToken = new URL(req.url).searchParams.get("access_token") ?? undefined; // no behavior change for POST users
    } else {
      try {
        const body = await req.json();
        accessToken = body?.access_token;
      } catch { /* ignore */ }
    }

    if (!accessToken) {
      return new Response(JSON.stringify({ error: "missing access_token" }), { status: 400, headers: JSON_HEADERS });
    }

    // OPT: L1 cache per token (5m). Bypass via header or query.
    const urlObj = new URL(req.url);
    const noCache = req.headers.get("x-no-cache") === "1" || urlObj.searchParams.get("noCache") === "1";
    const cacheKey = await sha256Hex(`me/accounts:${accessToken}`);

    if (!noCache) {
      const cached = l1Get(cacheKey);
      if (cached) {
        return new Response(cached, { status: 200, headers: { ...JSON_HEADERS, "x-cache": "L1" } });
      }
    }

    /* ---- FB Graph API ---- */
    const fbUrl =
      "https://graph.facebook.com/v23.0/me/accounts?" +
      new URLSearchParams({
        fields: "id,name,access_token,tasks,instagram_business_account",
        access_token: accessToken,
        limit: "100", // OPT: fetch more in a single call
      });

    const fbResp = await fetchWithTimeout(fbUrl, { headers: { Accept: "application/json" } }, 12000);
    const fbText = await fbResp.text();

    // Map common errors to cheaper, clearer status
    if (!fbResp.ok) {
      let status = fbResp.status;
      try {
        const err = JSON.parse(fbText);
        if (err?.error?.code === 190) status = 401; // invalid/expired token → auth error (saves retries)
      } catch { /* keep original status */ }
      return new Response(JSON.stringify({ error: "graph_api_failure" }), { status, headers: JSON_HEADERS });
    }

    let fbRes: any;
    try { fbRes = JSON.parse(fbText); } catch {
      return new Response(JSON.stringify({ error: "graph_api_failure" }), { status: 502, headers: JSON_HEADERS });
    }

    if (!fbRes?.data) {
      return new Response(JSON.stringify({ error: "graph_api_failure" }), { status: 502, headers: JSON_HEADERS });
    }

    const pages = fbRes.data.map((p: any) => ({
      id:           p.id,
      name:         p.name,
      access_token: p.access_token,
      tasks:        p.tasks,
      ig_user_id:   p.instagram_business_account?.id ?? null,
    }));

    const payload = JSON.stringify({ pages });

    // OPT: cache success for 5 minutes
    if (!noCache) l1Set(cacheKey, payload, 300);

    return new Response(payload, {
      status: 200,
      headers: { ...JSON_HEADERS, "x-cache": noCache ? "BYPASS" : "MISS" },
    });

  } catch (e: any) {
    console.error("get-meta-pages error:", e?.message || String(e));
    return new Response(JSON.stringify({ error: "graph_api_failure" }),
      { status: 502, headers: JSON_HEADERS });
  }
});

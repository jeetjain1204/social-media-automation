// /supabase/functions/meta-token-exchange.ts
import { serve }        from "std/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import "https://deno.land/x/dotenv/load.ts";

/*──────────────── CORS ────────────────*/
const CORS = {
  "Access-Control-Allow-Origin":  "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
  "Access-Control-Max-Age":       "86400",
  "Vary":                         "Origin, Access-Control-Request-Headers",
} as const;
const JSON_HEADERS = { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store", ...CORS } as const;

/*──────────────── utils ────────────────*/
const to32 = (b: Uint8Array) => b.length === 32 ? b : new Uint8Array(b.subarray(0, 32));

async function encrypt(plain: string, secret: string) {
  const iv  = crypto.getRandomValues(new Uint8Array(12));
  const key = await crypto.subtle.importKey(
    "raw", to32(new TextEncoder().encode(secret),), { name: "AES-GCM" }, false, ["encrypt"],
  );
  const buf  = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, new TextEncoder().encode(plain));
  const full = new Uint8Array(iv.length + buf.byteLength);
  full.set(iv);
  full.set(new Uint8Array(buf), iv.length);
  return btoa(String.fromCharCode(...full));
}

function b64UrlToObj(txt: string) {
  try {
    if (txt.length > 2048) return null; // OPT: cap state size to avoid abuse
    const pad = "=".repeat((4 - txt.length % 4) % 4);
    const b64 = txt.replace(/-/g, "+").replace(/_/g, "/") + pad;
    return JSON.parse(atob(b64));
  } catch { return null; }
}

const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status, headers: JSON_HEADERS });

/*──────────────── env ────────────────*/
const {
  SUPABASE_URL,
  SUPABASE_SERVICE_ROLE_KEY,
  META_APP_ID,
  META_APP_SECRET,
  ENCRYPTION_KEY,
} = Deno.env.toObject();

const ENV_OK = !!(SUPABASE_URL && SUPABASE_SERVICE_ROLE_KEY && META_APP_ID && META_APP_SECRET && ENCRYPTION_KEY);

/*──────────────── db ────────────────*/
const db = createClient(
  SUPABASE_URL!,
  SUPABASE_SERVICE_ROLE_KEY!,
  {
    auth:   { persistSession: false },
    global: { headers: {
      apikey:       SUPABASE_SERVICE_ROLE_KEY!,
      Authorization:`Bearer ${SUPABASE_SERVICE_ROLE_KEY!}`,
    } },
  },
);

/*──────────────── net helpers ────────────────*/
// 12s timeout; retry once on network failure only (no retry on HTTP errors)
async function fetchWithTimeout(url: string, init: RequestInit = {}, ms = 12000): Promise<Response> {
  const ac = new AbortController();
  const id = setTimeout(() => ac.abort(), ms);
  try { return await fetch(url, { ...init, signal: ac.signal }); }
  finally { clearTimeout(id); }
}
async function fetchOnceOrRetry(url: string, init: RequestInit = {}): Promise<Response> {
  try {
    return await fetchWithTimeout(url, init);
  } catch (e) {
    // transient network error → one retry with small backoff
    await new Promise(r => setTimeout(r, 200 + Math.floor(Math.random() * 150)));
    return await fetchWithTimeout(url, init);
  }
}

/*──────────────── handler ────────────────*/
serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });

  if (!ENV_OK) {
    console.error("meta-token-exchange: missing env");
    return json({ error: "server_misconfigured" }, 500);
  }

  try {
    const { searchParams } = new URL(req.url);
    const code  = searchParams.get("code");
    const state = searchParams.get("state");
    if (!code || !state) return new Response("Missing code/state", { status: 400, headers: { ...CORS, "Cache-Control": "no-store" } });

    /* decode state = { u: userId, t: 'facebook' | 'instagram' } */
    const st = b64UrlToObj(state);
    if (!st?.u || !st?.t) return new Response("Bad state", { status: 400, headers: { ...CORS, "Cache-Control": "no-store" } });
    const userId = st.u as string;
    const target = st.t as "facebook" | "instagram";

    /* 1️⃣  Exchange code → SHORT-lived user token (enough to list Pages) */
    const tokURL = "https://graph.facebook.com/v23.0/oauth/access_token?" + new URLSearchParams({
      client_id:     META_APP_ID!,
      client_secret: META_APP_SECRET!,
      redirect_uri:  `${SUPABASE_URL}/functions/v1/meta-token-exchange`,
      code,
    });

    const tokRes = await fetchOnceOrRetry(tokURL, { headers: { Accept: "application/json" } });
    const tokText = await tokRes.text();

    if (!tokRes.ok) {
      // Map FB OAuth error → clearer 400
      let status = tokRes.status;
      try {
        const err = JSON.parse(tokText);
        // common codes: 100/134/190 etc.
        if (err?.error?.code === 190) status = 400;
      } catch { /* ignore */ }
      return new Response("token-exchange-failed", { status, headers: { ...CORS, "Cache-Control": "no-store" } });
    }

    let tokBody: any;
    try { tokBody = JSON.parse(tokText); } catch {
      return new Response("token-exchange-failed", { status: 502, headers: { ...CORS, "Cache-Control": "no-store" } });
    }
    if (!tokBody?.access_token) return new Response("token-exchange-failed", { status: 502, headers: { ...CORS, "Cache-Control": "no-store" } });

    /* 2️⃣  Encrypt user token, store nonce row (no Page chosen yet) */
    const nonce  = crypto.randomUUID();
    const cipher = await encrypt(tokBody.access_token as string, ENCRYPTION_KEY!);

    const { error } = await db.from("oauth_nonce").insert({
      nonce,
      user_id: userId,
      encrypted_token: cipher,
      platform: target,
      expires_at: new Date(Date.now() + 10 * 60 * 1e3).toISOString(),
      created_at: new Date().toISOString(),
    }, { returning: "minimal" }); // OPT: cut response payload/egress
    if (error) {
      console.error("Insert nonce error:", error.message || String(error));
      return json({ error: "db_insert_failed" }, 500);
    }

    /* 3️⃣  Send user back to front-end with nonce */
    // Strict, absolute redirect; mark as no-store
    return new Response(null, {
      status: 302,
      headers: {
        Location: `https://app.blobautomation.com/connect/meta?nonce=${encodeURIComponent(nonce)}`,
        "Cache-Control": "no-store",
        ...CORS,
      },
      // alt (local):
      // headers: { Location: `http://localhost:53776/connect/meta?nonce=${encodeURIComponent(nonce)}`, "Cache-Control": "no-store", ...CORS },
    });

  } catch (err: any) {
    console.error("Meta OAuth error:", err?.message || String(err));
    return new Response("Meta OAuth failed", { status: 500, headers: { ...CORS, "Cache-Control": "no-store" } });
  }
});

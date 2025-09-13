import { serve }        from "std/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import "https://deno.land/x/dotenv/load.ts";

const CORS = {
  "Access-Control-Allow-Origin":  "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-no-cache",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Max-Age":       "86400",
  "Vary":                         "Origin, Access-Control-Request-Headers",
} as const;
const JSON_HEADERS = { ...CORS, "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" } as const;
/*──────── helpers ────────*/
/*──────── helpers ────────*/
const to32 = (u: Uint8Array) => (u.length === 32 ? u : u.subarray(0, 32));

// Always produce a real ArrayBuffer
const toAB = (u: Uint8Array): ArrayBuffer => {
  const ab = new ArrayBuffer(u.byteLength);
  new Uint8Array(ab).set(u);
  return ab;
};

const sliceToAB = (view: Uint8Array): ArrayBuffer => {
  const { buffer, byteOffset, byteLength } = view;
  if (buffer instanceof ArrayBuffer) {
    return buffer.slice(byteOffset, byteOffset + byteLength);
  }
  // SharedArrayBuffer path - make a copy
  return toAB(view);
};


async function decrypt(b64: string, secret: string) {
  const all  = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
  const iv   = all.subarray(0, 12);    // 12 bytes for AES-GCM
  const data = all.subarray(12);

  const keyBytes = to32(new TextEncoder().encode(secret));
  const key = await crypto.subtle.importKey(
    "raw",
    sliceToAB(keyBytes),                    // ArrayBuffer, not a view
    { name: "AES-GCM" },
    false,
    ["decrypt"]
  );

  const plainBuf = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: sliceToAB(iv) }, // iv as ArrayBuffer
    key,
    sliceToAB(data)                         // ciphertext+tag as ArrayBuffer
  );

  return new TextDecoder().decode(plainBuf);
}


// 12s timeout; retry once on network failure (never on HTTP errors)
async function fetchWithTimeout(url: string, init: RequestInit = {}, ms = 12000): Promise<Response> {
  const ac = new AbortController();
  const id = setTimeout(() => ac.abort(), ms);
  try { return await fetch(url, { ...init, signal: ac.signal }); }
  finally { clearTimeout(id); }
}
async function fetchOnceOrRetry(url: string, init: RequestInit = {}): Promise<Response> {
  try { return await fetchWithTimeout(url, init); }
  catch { await new Promise(r => setTimeout(r, 200 + Math.floor(Math.random()*150))); return await fetchWithTimeout(url, init); }
}

// Tiny L1 caches keyed by nonce (safe for this one-time flow)
type Entry = { v: string; exp: number };
const tokenL1 = new Map<string, Entry>();
const pagesL1 = new Map<string, Entry>();
const l1Get = (m: Map<string, Entry>, k: string) => { const e = m.get(k); if (!e) return null; if (e.exp < Date.now()) { m.delete(k); return null; } return e.v; };
const l1Set = (m: Map<string, Entry>, k: string, v: string, ttlSec: number) => m.set(k, { v, exp: Date.now() + ttlSec*1000 });

/*──────── env + db ────────*/
const { SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, ENCRYPTION_KEY } = Deno.env.toObject();
const ENV_OK = !!(SUPABASE_URL && SUPABASE_SERVICE_ROLE_KEY && ENCRYPTION_KEY);

const db = createClient(SUPABASE_URL!, SUPABASE_SERVICE_ROLE_KEY!, {
  auth: { persistSession: false },
  global: { headers: { apikey: SUPABASE_SERVICE_ROLE_KEY!, Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY!}` }},
});

/*──────── main handler ────────*/
serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  if (!ENV_OK) return new Response('{"error":"server_misconfigured"}', { status: 500, headers: JSON_HEADERS });

  const { nonce, selectedPage } = await req.json().catch(() => ({}));
  if (!nonce) return new Response('{"error":"missing nonce"}', { status:400, headers: JSON_HEADERS });

  const { data: row, error: rowErr } = await db
    .from("oauth_nonce")
    .select("user_id, platform, encrypted_token")
    .eq("nonce", nonce)
    .maybeSingle();

  if (rowErr || !row) {
    return new Response('{"error":"nonce expired"}', { status:404, headers: JSON_HEADERS });
  }

  // Decrypt user token (L1-cached per nonce for 10 minutes)
  let userToken = l1Get(tokenL1, nonce);
  if (!userToken) {
    try {
      userToken = await decrypt(row.encrypted_token, ENCRYPTION_KEY!);
      l1Set(tokenL1, nonce, userToken, 600);
    } catch {
      return new Response('{"error":"decrypt_failed"}', { status:500, headers: JSON_HEADERS });
    }
  }

  const noCache = req.headers.get("x-no-cache") === "1";

  /* ---------- Phase A: list pages ---------- */
  if (!selectedPage) {
    if (!noCache) {
      const cached = l1Get(pagesL1, nonce);
      if (cached) return new Response(cached, { status: 200, headers: { ...JSON_HEADERS, "x-cache": "L1" } });
    }

    const url =
      `https://graph.facebook.com/v19.0/me/accounts?` +
      new URLSearchParams({
        fields: "id,name,instagram_business_account,connected_instagram_account",
        access_token: userToken!,
        limit: "100",
      });

    const resp = await fetchOnceOrRetry(url, { headers: { Accept: "application/json" } });
    const txt  = await resp.text();

    if (!resp.ok) {
      let status = resp.status;
      try {
        const err = JSON.parse(txt);
        if (err?.error?.code === 190) status = 401; // invalid/expired token
      } catch { /* keep original */ }
      return new Response('{"error":"graph_api_failure"}', { status, headers: JSON_HEADERS });
    }

    let list: any;
    try { list = JSON.parse(txt); } catch { return new Response('{"error":"graph_api_failure"}', { status: 502, headers: JSON_HEADERS }); }

    const pages = (list.data || []).map((p: any) => ({
      page_id:   p.id,
      page_name: p.name,
      ig_user_id: p.instagram_business_account?.id
               ?? p.connected_instagram_account?.id
               ?? null,
    }));

    const payload = JSON.stringify({ platform: row.platform, pages });
    if (!noCache) l1Set(pagesL1, nonce, payload, 60);

    return new Response(payload, {
      status: 200,
      headers: { ...JSON_HEADERS, "x-cache": noCache ? "BYPASS" : "MISS" },
    });
  }

  /* ---------- Phase B: save selection ---------- */
  try {
    const { page_id, page_name, ig_user_id } = selectedPage;
    if (!page_id) throw new Error("bad selectedPage");
    if (row.platform === "instagram" && !ig_user_id) {
      return new Response('{"error":"page has no IG"}', { status:400, headers: JSON_HEADERS });
    }

    // Fetch Page token
    const pgResp = await fetchOnceOrRetry(
      `https://graph.facebook.com/v19.0/${page_id}?fields=access_token&access_token=${encodeURIComponent(userToken!)}`,
      { headers: { Accept: "application/json" } }
    );
    const pgTxt = await pgResp.text();
    if (!pgResp.ok) {
      let status = pgResp.status;
      try {
        const err = JSON.parse(pgTxt);
        if (err?.error?.code === 190) status = 401;
      } catch {}
      return new Response('{"error":"cannot_fetch_page_token"}', { status, headers: JSON_HEADERS });
    }

    let pg: any;
    try { pg = JSON.parse(pgTxt); } catch { return new Response('{"error":"cannot_fetch_page_token"}', { status: 502, headers: JSON_HEADERS }); }
    if (!pg.access_token) return new Response('{"error":"cannot_fetch_page_token"}', { status: 502, headers: JSON_HEADERS });

    // After you computed `pageToken` and before you return {"ok":true}

    const isFacebookFlow = row.platform === "facebook";
    let igUserId = selectedPage?.ig_user_id ?? null;
      
    // If FB flow and IG unknown, resolve via page token
    if (isFacebookFlow && !igUserId) {
      const igResp = await fetchOnceOrRetry(
        `https://graph.facebook.com/v19.0/${page_id}` +
        `?fields=instagram_business_account{id},connected_instagram_account{id}` +
        `&access_token=${encodeURIComponent(pg.access_token)}`,
        { headers: { Accept: "application/json" } }
      );
      const igTxt = await igResp.text();
      if (igResp.ok) {
        try {
          const obj = JSON.parse(igTxt);
          igUserId = obj?.instagram_business_account?.id ?? obj?.connected_instagram_account?.id ?? null;
        } catch {}
      }
    }
    
    // 1) Upsert Facebook row (existing behavior)
    {
      const { error: upErr } = await db.from("social_accounts").upsert({
        user_id:         row.user_id,
        platform:        "facebook",
        ig_user_id:      igUserId ?? null, // harmless to store; useful for UI
        page_id,
        page_name,
        access_token:    pg.access_token,
        connected_at:    new Date().toISOString(),
        needs_reconnect: false,
        is_disconnected: false,
      }, { onConflict: "user_id,platform", returning: "minimal" });
      if (upErr) return new Response(JSON.stringify({ error: upErr.message }), { status: 500, headers: JSON_HEADERS });
    }
    
    // 2) If we have a linked IG, also upsert Instagram row
    if (isFacebookFlow && igUserId) {
      const { error: igErr } = await db.from("social_accounts").upsert({
        user_id:         row.user_id,
        platform:        "instagram",
        ig_user_id:      igUserId,
        page_id,
        page_name,
        access_token:    pg.access_token, // requires IG scopes granted in Fix 1
        connected_at:    new Date().toISOString(),
        needs_reconnect: false,
        is_disconnected: false,
      }, { onConflict: "user_id,platform", returning: "minimal" });
      if (igErr) {
        // Optional: surface a softer warning; FB is connected, IG couldn’t be added
        return new Response(JSON.stringify({ error: "instagram_upsert_failed" }), { status: 207, headers: JSON_HEADERS });
      }
    }
    
    return new Response('{"ok":true}', { status: 200, headers: JSON_HEADERS });


  } catch (err) {
    console.error("save failed:", (err as Error).message || String(err));
    return new Response('{"error":"save failed"}', { status:500, headers: JSON_HEADERS });

  } finally {
    // Always purge the nonce (minimal egress)
    await db.from("oauth_nonce").delete().eq("nonce", nonce);
  }
});

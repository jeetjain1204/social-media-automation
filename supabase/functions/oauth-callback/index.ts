import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.50.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Max-Age": "86400",
};

async function verifyNonce(nonce: string, supabase: any, user_id: string): Promise<boolean> {
  // Also check expiry + already-used (encrypted_token not set yet)
  const { data: row, error } = await supabase
    .from("oauth_nonce")
    .select("nonce, user_id, expires_at, encrypted_token")
    .eq("nonce", nonce)
    .maybeSingle();

  if (error) throw new Error("Nonce lookup failed");
  if (!row) throw new Error("Nonce not found");
  if (row.user_id !== user_id) throw new Error("Nonce user mismatch");

  if (row.encrypted_token) throw new Error("Nonce already used");

  const now = Date.now();
  const exp = row.expires_at ? new Date(row.expires_at).getTime() : 0;
  if (!exp || exp < now) throw new Error("Nonce expired");

  return true;
}

// -------- small utils (no external deps) --------
function tryParseJSON<T>(s: string | null): T | null {
  if (!s) return null;
  try { return JSON.parse(s) as T; } catch { return null; }
}
function b64Decode(s: string) {
  try { return atob(s); } catch { return ""; }
}
function decodeState<T = any>(raw: string | null): T {
  // Accept both raw base64 and over-encoded variants
  const direct = tryParseJSON<T>(b64Decode(raw ?? ""));
  if (direct) return direct;
  const de = raw ? decodeURIComponent(raw) : null;
  const decoded = tryParseJSON<T>(b64Decode(de ?? ""));
  if (decoded) return decoded;
  throw new Error("Invalid state parameter");
}
function sleep(ms: number) { return new Promise(r => setTimeout(r, ms)); }
async function fetchWithTimeout(url: string, init: RequestInit & { timeoutMs?: number } = {}) {
  const { timeoutMs = 8000, signal } = init;
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    return await fetch(url, { ...init, signal: signal ?? ctrl.signal });
  } finally {
    clearTimeout(t);
  }
}
async function fetchJSONWithRetry(url: string, init: RequestInit & { timeoutMs?: number } = {}, retries = 2) {
  let attempt = 0; let lastErr: unknown = null;
  while (attempt <= retries) {
    try {
      const res = await fetchWithTimeout(url, init);
      if (res.status === 429) {
        const ra = Math.min(Number(res.headers.get("Retry-After")) || 1, 5);
        await sleep(ra * 1000);
        attempt++; continue;
      }
      if (!res.ok) {
        const txt = await res.text().catch(() => "");
        throw new Error(`HTTP ${res.status} ${txt.slice(0, 200)}`);
      }
      return await res.json();
    } catch (e) {
      lastErr = e;
      if (attempt >= retries) break;
      const backoff = [300, 700, 1200][Math.min(attempt, 2)];
      await sleep(backoff + Math.floor(Math.random() * 120));
      attempt++;
    }
  }
  throw lastErr ?? new Error("network error");
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  try {
    const url = new URL(req.url);
    const code = url.searchParams.get("code");
    const stateRaw = url.searchParams.get("state");
    const redirectUri = Deno.env.get("LINKEDIN_REDIRECT_URI");

    if (!code) throw new Error("Missing code");
    if (!redirectUri) throw new Error("Missing LinkedIn redirect URI");

    // Robust state parsing (works whether you encoded or not in the auth step)
    const { nonce, user_id } = decodeState<{ nonce: string; user_id: string }>(stateRaw);

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { global: { headers: { Authorization: `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!}` } } },
    );

    const ok = await verifyNonce(nonce, supabase, user_id);
    if (!ok) throw new Error("Invalid OAuth state nonce");

    const clientId = Deno.env.get("LINKEDIN_CLIENT_ID")!;
    const clientSecret = Deno.env.get("LINKEDIN_CLIENT_SECRET")!;
    if (!clientId || !clientSecret) throw new Error("Missing LinkedIn client credentials");

    // Exchange code → token
    const tokenData = await fetchJSONWithRetry(
      "https://www.linkedin.com/oauth/v2/accessToken",
      {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({
          grant_type: "authorization_code",
          code: code,
          redirect_uri: redirectUri,
          client_id: clientId,
          client_secret: clientSecret,
        }),
        timeoutMs: 8000,
      },
      2
    );

    if (!tokenData || typeof tokenData.access_token !== "string") {
      throw new Error("Invalid token response structure");
    }
    const accessToken: string = tokenData.access_token;
    // Do not log tokens to avoid leakage

    // Get userinfo
    const profile = await fetchJSONWithRetry(
      "https://api.linkedin.com/v2/userinfo",
      {
        headers: {
          Authorization: `Bearer ${accessToken}`,
          Accept: "application/json",
        },
        timeoutMs: 8000,
      },
      1
    );

    const sub = profile?.sub;
    if (!sub || typeof sub !== "string") throw new Error("Invalid userinfo response");
    const personUrn = `urn:li:person:${sub}`;

    const vaultKey = Deno.env.get("ENCRYPTION_KEY")!;
    if (!vaultKey) throw new Error("Missing ENCRYPTION_KEY");
    const encryptedAccessToken = await encryptToken(accessToken, vaultKey);

    // Mark nonce as used and store token+URN
    // (Set expires_at to past to prevent reuse; keeps row for frontend retrieval)
    const past = new Date(Date.now() - 1000).toISOString();
    const { error: upErr } = await supabase
      .from("oauth_nonce")
      .update({
        encrypted_token: encryptedAccessToken,
        person_urn: personUrn,
        expires_at: past,
      })
      .eq("nonce", nonce);

    if (upErr) throw new Error("Failed to persist token");

    // 302 back to frontend
    return new Response(null, {
      status: 302,
      headers: {
        Location: `${Deno.env.get("REDIRECT_FRONTEND_URL")}/connect/linkedin?nonce=${encodeURIComponent(nonce)}`,
        "Cache-Control": "no-store",
        ...corsHeaders,
      },
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error("OAuth Callback Error:", msg);
    return new Response(
      JSON.stringify({
        error: "OAuth failed",
        details: Deno.env.get("RAZORPAY_ENV") === "TEST" ? msg : null,
      }),
      { status: 500, headers: { "Content-Type": "application/json", ...corsHeaders } }
    );
  }
});

function toKeyBytes(key: string): Uint8Array {
  const raw = new TextEncoder().encode(key);
  if (raw.length === 32) return raw;
  if (raw.length > 32) return raw.slice(0, 32);
  const padded = new Uint8Array(32);
  padded.set(raw);
  return padded;
}

export async function encryptToken(data: string, key: string): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    toKeyBytes(key),
    { name: "AES-GCM" },
    false,
    ["encrypt"],
  );
  const cipher = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv },
    cryptoKey,
    new TextEncoder().encode(data),
  );
  const combined = new Uint8Array(iv.length + cipher.byteLength);
  combined.set(iv);
  combined.set(new Uint8Array(cipher), iv.length);
  return btoa(String.fromCharCode(...combined));
}

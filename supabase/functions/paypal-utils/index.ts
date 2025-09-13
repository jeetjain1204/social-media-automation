// paypal-utils/index.ts — ULTRA optimized (drop-in, same exports)

type AccessTokenCache = { token: string; expMs: number; baseUrl: string };
let _envCache = new Map<string, string>();
let _tokenCache: AccessTokenCache | null = null;

// ───────────────── env (trim + memoize) ─────────────────
export function env(key: string): string {
  const cached = _envCache.get(key);
  if (cached !== undefined) return cached;
  const raw = Deno.env.get(key);
  const val = (raw ?? "").trim();
  if (!val) throw new Error(`Missing env var: ${key}`);
  _envCache.set(key, val);
  return val;
}

// ───────────────── small net helpers ─────────────────
async function fetchWithTimeout(url: string, init: RequestInit = {}, ms = 12000): Promise<Response> {
  const ac = new AbortController();
  const t = setTimeout(() => ac.abort(), ms);
  try {
    return await fetch(url, { ...init, signal: ac.signal });
  } finally {
    clearTimeout(t);
  }
}

// Safe single retry for transient token-web calls (network/5xx only)
async function fetchOnceOrRetry(url: string, init: RequestInit = {}, ms = 12000): Promise<Response> {
  try {
    const r = await fetchWithTimeout(url, init, ms);
    if (r.ok || (r.status >= 400 && r.status < 500)) return r; // do not retry on 4xx
    // 5xx → retry
    await new Promise(r => setTimeout(r, 200 + Math.floor(Math.random() * 150)));
    return await fetchWithTimeout(url, init, ms);
  } catch {
    // network error → single retry
    await new Promise(r => setTimeout(r, 200 + Math.floor(Math.random() * 150)));
    return await fetchWithTimeout(url, init, ms);
  }
}

// ───────────────── base URL (memoized) ─────────────────
function getBaseUrl(): string {
  const tag = (Deno.env.get("PAYPAL_ENV") || "").trim().toLowerCase() === "live" ? "live" : "sandbox";
  return tag === "live" ? "https://api-m.paypal.com" : "https://api-m.sandbox.paypal.com";
}

// ───────────────── getPayPalAccessToken (L1 cached) ─────────────────
export async function getPayPalAccessToken() {
  const baseUrl = getBaseUrl();

  // Serve from cache if valid for ≥30s more
  const now = Date.now();
  if (_tokenCache && _tokenCache.baseUrl === baseUrl && _tokenCache.expMs - now > 30_000) {
    return { access_token: _tokenCache.token, baseUrl };
  }

  const clientId = env("PAYPAL_CLIENT_ID");
  const secret   = env("PAYPAL_SECRET");
  const creds = btoa(`${clientId}:${secret}`);

  const res = await fetchOnceOrRetry(`${baseUrl}/v1/oauth2/token`, {
    method: "POST",
    headers: {
      Authorization: `Basic ${creds}`,
      "Content-Type": "application/x-www-form-urlencoded",
      Accept: "application/json",
    },
    body: "grant_type=client_credentials",
  });

  if (!res.ok) {
    const txt = await res.text().catch(() => "");
    throw new Error(`PayPal auth failed: ${txt || res.status}`);
  }

  const j = await res.json() as { access_token?: string; expires_in?: number };
  if (!j?.access_token) throw new Error("PayPal auth failed: no token");

  // Cache with buffer (default 8h tokens → cache ~expires_in-60s)
  const expMs = now + Math.max(0, (j.expires_in ?? 3600) - 60) * 1000;
  _tokenCache = { token: j.access_token!, expMs, baseUrl };

  return { access_token: j.access_token!, baseUrl };
}

// ───────────────── verifyWebhookSignature (fast + robust) ─────────────────
export async function verifyWebhookSignature(
  body: string,
  headers: Headers,
): Promise<boolean> {
  // Quick header presence check (avoid token call if obviously incomplete)
  const required = [
    "paypal-auth-algo",
    "paypal-cert-url",
    "paypal-transmission-id",
    "paypal-transmission-sig",
    "paypal-transmission-time",
  ];
  for (const h of required) {
    if (!headers.get(h)) return false;
  }

  let eventObj: any;
  try {
    eventObj = JSON.parse(body);
  } catch {
    return false;
  }

  const { access_token, baseUrl } = await getPayPalAccessToken();

  const res = await fetchOnceOrRetry(`${baseUrl}/v1/notifications/verify-webhook-signature`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${access_token}`,
      "Content-Type": "application/json",
      Accept: "application/json",
    },
    body: JSON.stringify({
      auth_algo:         headers.get("paypal-auth-algo"),
      cert_url:          headers.get("paypal-cert-url"),
      transmission_id:   headers.get("paypal-transmission-id"),
      transmission_sig:  headers.get("paypal-transmission-sig"),
      transmission_time: headers.get("paypal-transmission-time"),
      webhook_id:        env("PAYPAL_WEBHOOK_ID"),
      webhook_event:     eventObj,
    }),
  });

  if (!res.ok) return false;

  const out = await res.json().catch(() => null) as { verification_status?: string } | null;
  return out?.verification_status === "SUCCESS";
}

// ───────────────── safeIso (smart seconds/ms) ─────────────────
export function safeIso(val: unknown): string | null {
  if (val == null) return null;

  // Date object
  if (val instanceof Date) {
    const t = val.getTime();
    if (Number.isFinite(t)) return new Date(t).toISOString();
    return null;
  }

  // Numeric (second vs millisecond auto-detect)
  if (typeof val === "number" && Number.isFinite(val)) {
    // treat values < 10^12 as seconds; otherwise ms
    const ms = val < 1_000_000_000_000 ? val * 1000 : val;
    const d = new Date(ms);
    return Number.isFinite(d.getTime()) ? d.toISOString() : null;
  }

  // String (ISO or RFC 2822 or epoch)
  if (typeof val === "string") {
    const s = val.trim();
    if (!s) return null;
    // numeric string?
    if (/^-?\d+(\.\d+)?$/.test(s)) {
      const num = Number(s);
      if (!Number.isFinite(num)) return null;
      const ms = num < 1_000_000_000_000 ? num * 1000 : num;
      const d = new Date(ms);
      return Number.isFinite(d.getTime()) ? d.toISOString() : null;
    }
    const t = Date.parse(s);
    return Number.isFinite(t) ? new Date(t).toISOString() : null;
  }

  return null;
}

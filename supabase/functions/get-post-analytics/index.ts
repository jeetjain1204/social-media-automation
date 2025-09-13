import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.5';

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-no-cache",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Max-Age": "86400",
};
const JSON_HEADERS = { ...corsHeaders, "content-type": "application/json; charset=utf-8" } as const;

// OPT: fail fast if envs are missing (prevents cold-crash later)
const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error("❌ Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
}

// keep your client exactly as-is
const supabase = createClient(
  SUPABASE_URL!,
  SUPABASE_SERVICE_ROLE_KEY!,
  { global: { headers: { Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY!}` } } },
);

// --------- ultra-light utils (no renames of your vars) ----------
const LINKEDIN_VERSION = '202506';
const RESTLI_VERSION = '2.0.0';

const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: JSON_HEADERS });

// OPT: 12s timeout caps billed time on network stalls
async function fetchWithTimeout(url: string, init: RequestInit = {}, ms = 12000) {
  const ac = new AbortController();
  const t = setTimeout(() => ac.abort(), ms);
  try {
    return await fetch(url, { ...init, signal: ac.signal });
  } finally {
    clearTimeout(t);
  }
}

// OPT: tiny in-isolate cache (L1) — avoids extra decrypts & API hits
type CacheEntry = { exp: number; v: string };
const tokenCache = new Map<string, CacheEntry>();  // key: orgUrn
const statsCache = new Map<string, CacheEntry>();  // key: orgId|postId

function l1Get(map: Map<string, CacheEntry>, key: string): string | null {
  const e = map.get(key);
  if (!e) return null;
  if (e.exp < Date.now()) { map.delete(key); return null; }
  return e.v;
}
function l1Set(map: Map<string, CacheEntry>, key: string, v: string, ttlSec: number) {
  map.set(key, { v, exp: Date.now() + ttlSec * 1000 });
}

// ---------------------------------------------------------------

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  try {
    if (req.method !== 'POST') {
      return json({ error: 'Method not allowed' }, 405);
    }
    if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
      return json({ error: 'Server misconfiguration' }, 500);
    }

    // OPT: body parse once
    const body = await req.json();
    const { orgId, postId } = body;

    // OPT: early validation before any I/O
    if (!orgId || !postId) {
      return json({ error: 'Missing orgId or postId' }, 400);
    }

    const noCache = req.headers.get('x-no-cache') === '1';

    // OPT: L1 cache on final stats payload (60s, override with x-no-cache)
    const statsKey = `${orgId}|${postId}`;
    if (!noCache) {
      const cached = l1Get(statsCache, statsKey);
      if (cached) {
        // add a tiny hint header for observability
        return new Response(cached, { status: 200, headers: { ...JSON_HEADERS, 'x-cache': 'L1' } });
      }
    }

    const orgUrn = `urn:li:organization:${orgId}`;

    // OPT: cache decrypted token per org (10 min)
    const tokenCached = l1Get(tokenCache, orgUrn);
    let accessToken: string;
    if (tokenCached) {
      accessToken = tokenCached;
    } else {
      const { data, error } = await supabase
        .from('social_accounts')
        .select('access_token')
        .eq('platform', 'linkedin')
        .eq('account_type', 'org')
        .eq('author_urn', orgUrn)
        .eq('is_disconnected', false)
        .maybeSingle();

      if (error || !data?.access_token) {
        console.error('❌ Access token not found:', error?.message);
        return json({ error: 'Access token not found' }, 404);
      }

      const encryptionKey = Deno.env.get("ENCRYPTION_KEY");
      if (!encryptionKey) {
        return json({ error: 'Missing encryption key' }, 500);
      }

      accessToken = await decryptToken(data.access_token, encryptionKey);
      l1Set(tokenCache, orgUrn, accessToken, 600); // 10 min
    }

    // OPT: If client already sends a URN, skip the "details" call entirely
    let postUrn: string;
    if (typeof postId === 'string' && postId.startsWith('urn:li:')) {
      postUrn = postId;
    } else {
      // Try share first, then ugc — sequential (saves one extra call vs racing)
      const postDetailsUrl = `https://api.linkedin.com/rest/posts/urn:li:share:${postId}`;
      const commonHeaders = {
        Authorization: `Bearer ${accessToken}`,
        'LinkedIn-Version': LINKEDIN_VERSION,
        'X-Restli-Protocol-Version': RESTLI_VERSION,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };

      const postDetailsRes = await fetchWithTimeout(postDetailsUrl, { method: 'GET', headers: commonHeaders });
      if (postDetailsRes.ok) {
        const postData = await postDetailsRes.json();
        postUrn = postData.id;
      } else {
        const ugcPostDetailsUrl = `https://api.linkedin.com/rest/posts/urn:li:ugcPost:${postId}`;
        const ugcPostRes = await fetchWithTimeout(ugcPostDetailsUrl, { method: 'GET', headers: commonHeaders });
        if (!ugcPostRes.ok) {
          const errorText = await ugcPostRes.text();
          // Propagate 401 specifically to hint token refresh
          const code = ugcPostRes.status === 401 ? 401 : 400;
          console.error('❌ LinkedIn post lookup failed:', postDetailsRes.status, ugcPostRes.status);
          return json({ error: 'Unable to verify post type', details: errorText }, code);
        }
        const ugcPostData = await ugcPostRes.json();
        postUrn = ugcPostData.id;
      }
    }

    let postParam: string;
    if (postUrn.startsWith('urn:li:share:')) {
      postParam = `shares=${encodeURIComponent(postUrn)}`;
    } else if (postUrn.startsWith('urn:li:ugcPost:')) {
      postParam = `ugcPosts=${encodeURIComponent(postUrn)}`;
    } else {
      return json({ error: 'Unrecognized post type' }, 400);
    }

    const query = `q=organizationalEntity&organizationalEntity=${encodeURIComponent(orgUrn)}&${postParam}`;
    const finalUrl = `https://api.linkedin.com/rest/organizationalEntityShareStatistics?${query}`;

    const linkedInRes = await fetchWithTimeout(finalUrl, {
      method: 'GET',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'LinkedIn-Version': LINKEDIN_VERSION,
        'X-Restli-Protocol-Version': RESTLI_VERSION,
        'Accept': 'application/json',
      },
    });

    if (!linkedInRes.ok) {
      const errorText = await linkedInRes.text();
      const code = linkedInRes.status === 401 ? 401 : linkedInRes.status;
      console.error('❌ LinkedIn stats error:', linkedInRes.status);
      return json({ error: 'LinkedIn API error', details: errorText }, code);
    }

    // OPT: single parse on success
    const payload = await linkedInRes.json();
    const elements = payload?.elements ?? [];

    const result = elements.map((item: any) => {
      const stats = item.totalShareStatistics ?? {};
      return {
        views: stats.impressionCount ?? 0,
        likes: stats.likeCount ?? 0,
        shares: stats.shareCount ?? 0,
        comments: stats.commentCount ?? 0,
        engagement: stats.engagement ?? 0,
        uniqueImpressionsCount: stats.uniqueImpressionsCount ?? 0,
      };
    });

    // OPT: cache the final JSON string (60s)
    const serialized = JSON.stringify(result);
    if (!noCache) {
      l1Set(statsCache, statsKey, serialized, 60);
    }
    return new Response(serialized, {
      status: 200,
      headers: { ...JSON_HEADERS, 'x-cache': noCache ? 'BYPASS' : 'MISS' },
    });

  } catch (err: any) {
    // no stack dump to logs; keep it lean
    console.error('❌ Unexpected:', err?.message || String(err));
    return json({ error: 'Unexpected error', details: err?.message || 'unknown' }, 500);
  }
});

// ---------------- your decrypt as-is ----------------
// Clone any view or buffer into a clean ArrayBuffer (never SAB, no offsets)
function toArrayBuffer(src: ArrayBuffer | ArrayBufferView): ArrayBuffer {
  if (src instanceof ArrayBuffer) return src.slice(0); // clone

  const view = src as ArrayBufferView;
  const out = new ArrayBuffer(view.byteLength);
  new Uint8Array(out).set(
    new Uint8Array(view.buffer, view.byteOffset, view.byteLength)
  );
  return out;
}

export async function decryptToken(
  encryptedB64: string,
  key: string,
): Promise<string> {
  // Decode base64 in both browser and Node
  const bytes =
    typeof atob === "function"
      ? Uint8Array.from(atob(encryptedB64), c => c.charCodeAt(0))
      : new Uint8Array(Buffer.from(encryptedB64, "base64"));

  const iv = bytes.slice(0, 12);      // 12-byte GCM IV
  const data = bytes.slice(12);       // ciphertext + tag

  const keyBytes = toKeyBytes(key);   // 32 bytes for AES-256-GCM

  // If running in Node, ensure webcrypto is present
  // globalThis.crypto ??= require("node:crypto").webcrypto;

  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    toArrayBuffer(keyBytes),
    { name: "AES-GCM" },
    false,
    ["decrypt"],
  );

  const plain = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: toArrayBuffer(iv) },
    cryptoKey,
    toArrayBuffer(data),
  );

  return new TextDecoder().decode(plain);
}

// unchanged helper
function toKeyBytes(key: string): Uint8Array {
  const raw = new TextEncoder().encode(key);
  if (raw.length === 32) return raw;
  if (raw.length > 32) return raw.slice(0, 32);
  const padded = new Uint8Array(32);
  padded.set(raw);
  return padded;
}

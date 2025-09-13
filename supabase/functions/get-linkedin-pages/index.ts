import { serve } from "https://deno.land/std@0.219.0/http/server.ts";
import {
  wrapEdgeHandler,
  readJsonSafe,
  ensureIdempotency,
  abortableFetch,
  defaultRetry,
  json,
} from "../_shared/edge-core.ts";
import { createRedisKV } from "../_shared/kv_redis.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, idempotency-key",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Max-Age": "86400",
};

// ---------- Optional KV (Upstash). Falls back to in-memory if not configured ----------
let kv: ReturnType<typeof createRedisKV> | null = null;
try { kv = createRedisKV({ namespace: "li" }); } catch { /* no-op */ }

// ---------- Helpers ----------
async function sha256Hex(s: string) {
  const ab = new TextEncoder().encode(s);
  const h = await crypto.subtle.digest("SHA-256", ab);
  return [...new Uint8Array(h)].map(b => b.toString(16).padStart(2,"0")).join("");
}

function chunk<T>(arr: T[], n: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < arr.length; i += n) out.push(arr.slice(i, i + n));
  return out;
}

function sleep(ms: number) { return new Promise(r => setTimeout(r, ms)); }

async function fetchJsonWithRetry(url: string, init: RequestInit & { timeoutMs?: number } = {}) {
  const policy = defaultRetry; // retries on 429/5xx
  let attempt = 0;
  let lastErr: unknown = null;
  while (attempt <= policy.retries) {
    try {
      const res = await abortableFetch(url, { ...init, timeoutMs: init.timeoutMs ?? 6000 });
      if (res.status === 429) {
        const ra = Number(res.headers.get("Retry-After")) || 1;
        await sleep(Math.min(ra, 5) * 1000);
        attempt++; continue;
      }
      if (!res.ok) {
        const txt = await res.text().catch(() => "");
        throw new Error(`HTTP ${res.status} ${txt?.slice(0,200)}`);
      }
      const data = await res.json();
      return data;
    } catch (err) {
      lastErr = err;
      if (attempt >= policy.retries) break;
      const backoff = policy.backoffMs[Math.min(attempt, policy.backoffMs.length - 1)];
      await sleep(backoff + Math.floor(Math.random() * 120)); // jitter
      attempt++;
    }
  }
  throw lastErr ?? new Error("fetch failed");
}

// Same-instance singleflight per token-hash
const inflight = new Map<string, Promise<Response>>();

// ---------- Main ----------
serve(
  wrapEdgeHandler(async (req) => {
    if (req.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS });
    }

    // Wrap entire op with idempotency (short window). If client sends Idempotency-Key,
    // we’ll replay the same response for transient retries.
    return await ensureIdempotency(
      req,
      async () => {
        try {
          // Safe, bounded JSON parse (64 KB cap)
          const body = await readJsonSafe<{ access_token?: string }>(req, 64 * 1024);
          const access_token = body?.access_token;
          if (!access_token) {
            return json({ error: "Missing access_token" }, 400, { ...CORS });
          }

          // Per-token result cache (10 min). Hash to avoid storing raw tokens.
          const tokenKey = await sha256Hex(access_token);
          const cacheKey = `pages:${tokenKey}`;
          const lockKey  = `lock:${tokenKey}`;

          // L2 cache first
          try {
            const hit = await kv?.get<{ pages: { organizationUrn: string; name: string }[] }>(cacheKey);
            if (hit?.value?.pages) {
              return json({ pages: hit.value.pages }, 200, { ...CORS, "x-cache": "hit" });
            }
          } catch { /* ignore cache errors */ }

          // Same-instance coalescing
          if (inflight.has(cacheKey)) return inflight.get(cacheKey)!;

          // Leader section wrapped in a promise for singleflight
          const leaderPromise = (async (): Promise<Response> => {
            // Try a tiny distributed lock to avoid duplicate LinkedIn calls across workers
            let haveLock = false;
            try { haveLock = !!(await kv?.acquireLock?.(lockKey, 12)); } catch {}

            try {
              // LinkedIn headers
              const headers = {
                Authorization: `Bearer ${access_token}`,
                "X-Restli-Protocol-Version": "2.0.0",
                "LinkedIn-Version": "202505",
                "Accept": "application/json",
              };

              // 1) Collect organization URNs via ACL paging
              const urns = new Set<string>();
              const pageSize = 50;
              const maxLoops = 40; // safety cap (<= 2000 ACL rows)
              for (let start = 0, loop = 0; loop < maxLoops; start += pageSize, loop++) {
                const aclURL =
                  "https://api.linkedin.com/rest/organizationAcls"
                  + "?q=roleAssignee"
                  + "&role=ADMINISTRATOR"
                  + "&state=APPROVED"
                  + `&start=${start}&count=${pageSize}`;

                const aclJson = await fetchJsonWithRetry(aclURL, { headers, timeoutMs: 7000 });
                const elements = Array.isArray(aclJson?.elements) ? aclJson.elements : [];
                for (const e of elements) {
                  if (e && typeof e.organization === "string") urns.add(e.organization);
                }
                if (elements.length < pageSize) break;
              }

              if (urns.size === 0) {
                // Cache negative result briefly (1 minute) to collapse thundering herds
                try { await kv?.set?.(cacheKey, { pages: [] }, 60); } catch {}
                return json({ pages: [] }, 200, { ...CORS, "x-cache": "miss" });
              }

              // 2) Resolve org details in chunks of 20
              const ids = [...urns].map((u) => u.split(":").pop()!).filter(Boolean);
              const pages: { organizationUrn: string; name: string }[] = [];

              for (const group of chunk(ids, 20)) {
                const listParam = group.join(",");
                const orgURL = `https://api.linkedin.com/rest/organizations?ids=List(${listParam})`;
                const orgJson = await fetchJsonWithRetry(orgURL, { headers, timeoutMs: 7000 });

                const results = orgJson?.results ?? {};
                for (const [id, org] of Object.entries<any>(results)) {
                  pages.push({
                    organizationUrn: `urn:li:organization:${id}`,
                    name: org?.localizedName ?? org?.name?.localized?.en_US ?? "Unknown",
                  });
                }
              }

              // Store in cache (10 minutes)
              try { await kv?.set?.(cacheKey, { pages }, 600); } catch {}

              return json({ pages }, 200, { ...CORS, "x-cache": "miss" });
            } finally {
              try { if (haveLock) await kv?.releaseLock?.(lockKey); } catch {}
            }
          })();

          inflight.set(cacheKey, leaderPromise);
          try { return await leaderPromise; }
          finally { inflight.delete(cacheKey); }
        } catch (err) {
          console.error("Pages Fetch Error:", err);
          return json({ error: "Failed to fetch pages" }, 500, { ...CORS });
        }
      },
      // 5-minute replay window is enough; doesn’t leak signed data.
      { ttlSec: 300, mode: "replay", kv: kv ?? undefined },
    );
  })
);

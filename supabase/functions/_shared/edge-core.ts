// deno-lint-ignore-file no-explicit-any
/**
 * Edge Core — safe, logic-neutral wrapper for Supabase Edge Functions (Deno).
 * Adds: Server-Timing, request-id, optional CORS, optional strong ETag/304.
 * Does NOT change your handler's logic or payload.
 */

export type CorsOptions = {
  allowOrigin?: string;   // '*' or exact origin
  allowMethods?: string;  // e.g. 'GET,POST,PUT,PATCH,DELETE,OPTIONS'
  allowHeaders?: string;  // e.g. 'authorization,content-type'
  exposeHeaders?: string; // e.g. 'server-timing,etag,request-id'
  maxAgeSeconds?: number; // preflight cache
  allowCredentials?: boolean;
};

export type WrapperOptions1 = {
  /** Add Server-Timing: edge;dur=… (merged if already present) */
  serverTiming?: boolean;
  /** Compute strong ETag for successful GET text/JSON responses (if not set), reply 304 on match */
  etag?: boolean;
  /** Add CORS headers & handle OPTIONS quickly (off by default) */
  cors?: CorsOptions | false;
  /** Add `Request-Id` header; echoes incoming `x-request-id` or generates one */
  requestId?: boolean;
  /** Security headers that are safe for APIs (no CSP/opinionated caching) */
  hardenHeaders?: boolean;
};

/** Simple, fast request id (base32 of 12 random bytes). */
export function makeRequestId(): string {
  const bytes = new Uint8Array(12);
  crypto.getRandomValues(bytes);
  // base32 without padding; compact and URL-safe
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  let out = "";
  let bits = 0, value = 0;
  for (const b of bytes) {
    value = (value << 8) | b;
    bits += 8;
    while (bits >= 5) {
      out += alphabet[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) out += alphabet[(value << (5 - bits)) & 31];
  return out.slice(0, 20);
}

/** Merge headers without clobbering existing values; append for comma-separated lists. */
function mergeHeaders(base: Headers, extra: Record<string, string | undefined>) {
  for (const [k, v] of Object.entries(extra)) {
    if (!v) continue;
    if (base.has(k)) {
      // For list-like headers, append uniquely
      const existing = base.get(k)!;
      if (k.toLowerCase() === "server-timing" || k.toLowerCase() === "vary") {
        if (!existing.toLowerCase().includes(v.toLowerCase())) {
          base.set(k, `${existing}, ${v}`);
        }
      } else {
        // default: keep existing (don't risk logic change)
        // If you WANT to override, do it in your handler.
      }
    } else {
      base.set(k, v);
    }
  }
}

/** Compute strong ETag = "sha256:<hex>" for small/medium bodies. */
async function computeEtagFromBody(resp: Response): Promise<string | null> {
  try {
    // Only hash if content-type suggests text or json and body size isn't huge.
    const ct = resp.headers.get("content-type")?.toLowerCase() ?? "";
    if (!ct.includes("application/json") && !ct.includes("text/")) return null;
    const clone = resp.clone();
    const buf = await clone.arrayBuffer();
    // Skip hashing very large bodies to avoid memory spikes
    if (buf.byteLength > 1_000_000) return null; // ~1MB safety
    const hash = await crypto.subtle.digest("SHA-256", buf);
    const hex = [...new Uint8Array(hash)].map(b => b.toString(16).padStart(2, "0")).join("");
    return `"sha256:${hex}"`;
  } catch {
    return null;
  }
}

/** Build CORS headers (non-destructive; only fills gaps). */
function buildCorsHeaders(opts: CorsOptions | undefined, req: Request): Record<string, string> {
  if (!opts) return {};
  const origin = req.headers.get("origin") ?? "";
  const allowOrigin =
    opts.allowOrigin && opts.allowOrigin !== "*"
      ? (origin && opts.allowOrigin === origin ? origin : "") // echo only if exact match
      : "*";

  const h: Record<string, string> = {};
  if (allowOrigin) h["Access-Control-Allow-Origin"] = allowOrigin;
  if (opts.allowCredentials) h["Access-Control-Allow-Credentials"] = "true";
  h["Access-Control-Allow-Methods"] = opts.allowMethods ?? "GET,POST,PUT,PATCH,DELETE,OPTIONS";
  h["Access-Control-Allow-Headers"] = opts.allowHeaders ?? "authorization,content-type";
  h["Access-Control-Expose-Headers"] = opts.exposeHeaders ?? "server-timing,etag,request-id";
  if (opts.maxAgeSeconds && opts.maxAgeSeconds > 0) {
    h["Access-Control-Max-Age"] = String(opts.maxAgeSeconds);
  }
  // Ensure caches treat per-origin variants separately when not wildcard
  if (allowOrigin !== "*") {
    h["Vary"] = "Origin";
  }
  return h;
}

/**
 * Wrap your existing `(req) => Response` handler.
 * We never touch your handler's internals or change its payload/logic.
 */
export function wrapEdgeHandler1(
  handler: (req: Request) => Response | Promise<Response>,
  options: WrapperOptions1 = {
    serverTiming: true,
    etag: true,
    cors: false,
    requestId: true,
    hardenHeaders: true,
  },
): (req: Request) => Promise<Response> {
  const opts = { serverTiming: true, etag: true, requestId: true, hardenHeaders: true, ...options };

  return async (req: Request): Promise<Response> => {
    const t0 = performance.now();

    // Fast CORS preflight (doesn't call your handler)
    if (opts.cors && req.method === "OPTIONS") {
      const pre = new Headers();
      mergeHeaders(pre, buildCorsHeaders(opts.cors, req));
      // No body, no caching surprises
      mergeHeaders(pre, { "Content-Length": "0" });
      return new Response(null, { status: 204, headers: pre });
    }

    // Run your handler exactly as-is
    let resp = await handler(req);

    // Build mutable headers from your response
    const headers = new Headers(resp.headers);

    // Add Request-Id
    if (opts.requestId) {
      const incoming = req.headers.get("x-request-id");
      mergeHeaders(headers, { "Request-Id": incoming ?? makeRequestId() });
    }

    // Add Server-Timing basic span
    if (opts.serverTiming) {
      const dur = Math.max(0, performance.now() - t0).toFixed(1);
      mergeHeaders(headers, { "Server-Timing": `edge;dur=${dur}` });
    }

    // Safe security hardening (API-friendly, non-breaking)
    if (opts.hardenHeaders) {
      mergeHeaders(headers, {
        "X-Content-Type-Options": "nosniff",
        "Referrer-Policy": "no-referrer",
        "Cross-Origin-Opener-Policy": "same-origin",
        // Don't set CSP here to avoid breaking existing responses
      });
    }

    // Optional ETag for GET 200/204 if not already set
    if (opts.etag && req.method === "GET" && !headers.has("ETag") && resp.ok && (resp.status === 200 || resp.status === 204)) {
      const etag = await computeEtagFromBody(resp);
      if (etag) {
        const inm = req.headers.get("if-none-match");
        mergeHeaders(headers, { "ETag": etag });
        if (inm && inm === etag) {
          // Return 304, strip body; preserve headers (minus content-specific)
          headers.delete("Content-Length");
          headers.delete("Content-Encoding");
          return new Response(null, { status: 304, headers });
        }
      }
    }

    // Add CORS (non-destructive)
    if (opts.cors) {
      mergeHeaders(headers, buildCorsHeaders(opts.cors, req));
    }

    // Rebuild response with merged headers; body untouched.
    return new Response(resp.body, {
      status: resp.status,
      statusText: resp.statusText,
      headers,
    });
  };
}

// ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

// edge-core.ts
// Web-standard helpers for Supabase Edge/Deno. No Node APIs.
// Adds: correlation IDs, safe JSON, optional rate limit, idempotency,
// ETag/304 on GET, AI cache with distributed singleflight, basic metrics.

export type EdgeHandler = (req: Request, ctx?: Record<string, unknown>) => Promise<Response> | Response;

export interface KVStore {
  get<T = unknown>(key: string): Promise<{ value: T; exp: number } | null>;
  set<T = unknown>(key: string, value: T, ttlSec: number): Promise<void>;
  del?(key: string): Promise<void>;
  acquireLock?(key: string, ttlSec: number): Promise<boolean>;
  releaseLock?(key: string): Promise<void>;
}

class MemoryKV implements KVStore {
  private m = new Map<string, { value: unknown; exp: number }>();
  private locks = new Map<string, number>();
  async get<T>(key: string) {
    const v = this.m.get(key);
    if (!v) return null;
    if (v.exp < Date.now()) { this.m.delete(key); return null; }
    return v as { value: T; exp: number };
  }
  async set<T>(key: string, value: T, ttlSec: number) {
    this.m.set(key, { value, exp: Date.now() + ttlSec * 1000 });
  }
  async del(key: string) { this.m.delete(key); }
  async acquireLock(key: string, ttlSec: number) {
    const now = Date.now();
    const exp = this.locks.get(key);
    if (exp && exp > now) return false;
    this.locks.set(key, now + ttlSec * 1000);
    return true;
  }
  async releaseLock(key: string) { this.locks.delete(key); }
}

export type EdgeCoreConfig = {
  routeName?: string;
  /** Alias accepted for older call sites */
  name?: string;

  requestTimeoutMs: number;
  aiTimeoutMs: number;
  maxRetries: number;
  retryBackoffMs: [number, number, number];

  enableAutoCacheForGET: boolean;
  cacheControl: string;
  etagMaxBytes: number;
  maxJsonBytes: number;

  logMetrics: boolean;

  rateLimit?: { capacity: number; refillPerSec: number };

  idempotency?: { ttlSec: number; mode: "reject" | "replay" };

  ai?: {
    enableCoalescing: boolean;
    cacheTtlSec: number;
    firstByteBudgetMs: number;
    maxPromptChars: number;
    maxOutputTokens: number;
    lockTtlSec?: number;     // distributed lock TTL
    waitForFlightMs?: number;// follower max wait
    pollEveryMs?: number;    // follower poll cadence
  };

  kv?: KVStore;      // for rate limit / idempotency
  aiCache?: KVStore; // for AI cache
  clock?: () => number;
};

export const defaultConfig: EdgeCoreConfig = {
  requestTimeoutMs: 3000,
  aiTimeoutMs: 10000,
  maxRetries: 3,
  retryBackoffMs: [200, 400, 800],
  enableAutoCacheForGET: true,
  cacheControl: "public, s-maxage=60, stale-while-revalidate=86400",
  etagMaxBytes: 128 * 1024,
  maxJsonBytes: 64 * 1024,
  logMetrics: true,
  rateLimit: undefined,
  idempotency: undefined,
  ai: {
    enableCoalescing: true,
    cacheTtlSec: 60 * 60 * 24 * 7,
    firstByteBudgetMs: 300,
    maxPromptChars: 700,
    maxOutputTokens: 120,
    lockTtlSec: 15,
    waitForFlightMs: 12_000,
    pollEveryMs: 150,
  },
  kv: undefined,
  aiCache: undefined,
  clock: () => performance.now(),
};

// Back-compat for projects expecting this name
export type WrapperOptions = EdgeCoreConfig;
export function wrapEdgeHandler(handler: EdgeHandler, cfg: Partial<EdgeCoreConfig> = {}): EdgeHandler {
  const config = materializeConfig(cfg);
  return async (req, ctx) => {
    const t0 = config.clock!();
    const correlationId = getOrMakeCorrelationId(req);

    // ✅ initialize so TS knows it's always assigned
    let res: Response = new Response(null, { status: 500 });

    try {
      if (config.rateLimit) {
        const ok = await tokenBucketConsume(
          config.kv!, rateKey(req),
          config.rateLimit.capacity, config.rateLimit.refillPerSec
        );

        if (!ok) {
          // ✅ assign before returning so `finally` can use `res`
          res = json(
            { error: "Rate limit exceeded" },
            429,
            { "Retry-After": "1", "x-request-id": correlationId }
          );
          return res;
        }
      }

      res = await handler(req, ctx);
      res = withHeader(res, "x-request-id", correlationId);

      if (config.enableAutoCacheForGET && req.method === "GET") {
        if (!res.headers.has("Cache-Control")) {
          res = withHeader(res, "Cache-Control", config.cacheControl);
        }
        res = await withETagIfSmall(req, res, config);
      }
    } catch (err) {
      res = json({ error: "Internal Error" }, 500, { "x-request-id": correlationId });
      log("error", config, { correlationId, route: route(config), err: serializeErr(err) });
    } finally {
      const dur = Math.round(config.clock!() - t0);
      try {
        res = withHeader(res, "Server-Timing", `total;dur=${dur}`);
      } catch {}
      if (config.logMetrics) {
        log("metric", config, {
          type: "http",
          route: route(config),
          status: res.status,
          duration_ms: dur,
          correlationId,
          cache: res.headers.get("x-cache") ?? "miss",
        });
      }
    }

    return res;
  };
}


// ---------- HTTP utils ----------

export function json(data: unknown, status = 200, headers: Record<string, string> = {}) {
  return new Response(JSON.stringify(data), { status, headers: { "Content-Type": "application/json; charset=utf-8", ...headers } });
}

export function withHeader(res: Response, k: string, v: string) {
  const h = new Headers(res.headers); h.set(k, v);
  return new Response(res.body, { status: res.status, statusText: res.statusText, headers: h });
}

async function withETagIfSmall(req: Request, res: Response, cfg: EdgeCoreConfig) {
  if (res.headers.has("ETag")) return res;
  const ct = res.headers.get("Content-Type") || "";
  const likelySmall = /application\/json|text\//i.test(ct);
  if (!likelySmall) return res;
  const ab = await res.clone().arrayBuffer();
  if (ab.byteLength > cfg.etagMaxBytes) return res;
  const etag = await weakETag(ab);
  const inm = req.headers.get("If-None-Match");
  const h = new Headers(res.headers); h.set("ETag", etag);
  if (inm && inm === etag && req.method === "GET" && res.status === 200) {
    return new Response(null, { status: 304, headers: h });
  }
  return new Response(res.body, { status: res.status, headers: h, statusText: res.statusText });
}

async function weakETag(ab: ArrayBuffer) {
  const hash = await crypto.subtle.digest("SHA-256", ab);
  return `W/"${[...new Uint8Array(hash)].map(v=>v.toString(16).padStart(2,"0")).join("")}"`;
}

function getOrMakeCorrelationId(req: Request) {
  return req.headers.get("x-request-id") || crypto.randomUUID();
}

function rateKey(req: Request) {
  const ip = req.headers.get("x-forwarded-for") || "ip:unknown";
  const uid = req.headers.get("x-user-id") || "user:anon";
  return `rl:${uid}:${ip}`;
}

// ---------- Retryable fetch (optional utility) ----------

export type RetryPolicy = { retries: number; backoffMs: number[]; shouldRetry: (res: Response | null, err: unknown) => boolean; };
export const defaultRetry: RetryPolicy = {
  retries: 3,
  backoffMs: [200, 400, 800],
  shouldRetry: (res, err) => {
    if (err) return true;
    if (!res) return true;
    return res.status === 429 || (res.status >= 500 && res.status <= 599);
  },
};

export async function abortableFetch(input: RequestInfo | URL, init: RequestInit & { timeoutMs?: number } = {}) {
  const { timeoutMs = 3000, signal } = init;
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort("timeout"), timeoutMs);
  try { return await fetch(input, { ...init, signal: signal ?? ctrl.signal }); }
  finally { clearTimeout(t); }
}

// ---------- Token bucket ----------

async function tokenBucketConsume(store: KVStore, key: string, capacity: number, refillPerSec: number) {
  const now = Date.now();
  const row = await store.get<{ tokens: number; ts: number }>(`tb:${key}`);
  const last = row?.value ?? { tokens: capacity, ts: now };
  const elapsed = Math.max(0, (now - last.ts) / 1000);
  const tokens = Math.min(capacity, last.tokens + elapsed * refillPerSec);
  if (tokens < 1) { await store.set(`tb:${key}`, { tokens, ts: now }, 60); return false; }
  await store.set(`tb:${key}`, { tokens: tokens - 1, ts: now }, 60);
  return true;
}

// ---------- Idempotency ----------

export async function ensureIdempotency<TRes extends Response>(
  req: Request,
  exec: () => Promise<TRes>,
  opts: { kv?: KVStore; ttlSec: number; mode: "reject" | "replay" } = { ttlSec: 600, mode: "reject" },
): Promise<TRes> {
  const store = opts.kv ?? defaultKV;
  const key = req.headers.get("Idempotency-Key") || (await bodyHashKey(req));
  const hit = await store.get<{ status: number; headers: [string, string][]; body: string }>(`idem:${key}`);
  if (hit) {
    if (opts.mode === "reject") return json({ error: "Duplicate request" }, 409) as TRes;
    return new Response(hit.value.body, { status: hit.value.status, headers: new Headers(hit.value.headers) }) as TRes;
  }
  const res = await exec();
  try {
    const body = await res.clone().text();
    const headers: [string, string][] = []; res.headers.forEach((v,k)=>headers.push([k,v]));
    await store.set(`idem:${key}`, { status: res.status, headers, body }, opts.ttlSec);
  } catch {}
  return res;
}

async function bodyHashKey(req: Request) {
  const text = await req.clone().text();
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return "h:" + [...new Uint8Array(digest)].map(v=>v.toString(16).padStart(2,"0")).join("");
}

// ---------- AI cache with distributed singleflight ----------

const inFlight = new Map<string, Promise<Response>>();

export async function aiCachedCall(
  keyObj: unknown,
  call: () => Promise<Response>,
  cfg: EdgeCoreConfig,
): Promise<Response> {
  const cache = cfg.aiCache ?? defaultKV;
  const ai = cfg.ai!;
  const key = "ai:" + (await stableHash(keyObj));
  const lockKey = key + ":lock";

  // L1: global cache
  const cached = await cache.get<string>(key);
  if (cached) {
    const h = new Headers({ "x-ai-cache": "hit" });
    return new Response(cached.value, { status: 200, headers: h });
  }

  // L0: same-instance singleflight
  if (ai.enableCoalescing && inFlight.has(key)) return inFlight.get(key)!;

  const p = (async () => {
    let leader = false;
    if (cache.acquireLock) leader = await cache.acquireLock(lockKey, ai.lockTtlSec ?? 15);

    if (leader) {
      try {
        const res = await call();
        try {
          const body = await res.clone().text();
          await cache.set(key, body, ai.cacheTtlSec);
        } finally {
          cache.releaseLock && (await cache.releaseLock(lockKey));
        }
        const h = new Headers(res.headers); h.set("x-ai-cache", "miss");
        return new Response(res.body, { status: res.status, headers: h, statusText: res.statusText });
      } catch (err) {
        cache.releaseLock && (await cache.releaseLock(lockKey));
        throw err;
      }
    } else {
      // follower waits for leader
      const until = Date.now() + (ai.waitForFlightMs ?? 12_000);
      const poll = ai.pollEveryMs ?? 150;
      while (Date.now() < until) {
        await delay(poll);
        const c = await cache.get<string>(key);
        if (c) {
          const h = new Headers({ "x-ai-cache": "fill" });
          return new Response(c.value, { status: 200, headers: h });
        }
      }
      // fallback if lock holder failed
      const res = await call();
      const body = await res.clone().text();
      await cache.set(key, body, ai.cacheTtlSec);
      const h = new Headers(res.headers); h.set("x-ai-cache", "miss-fallback");
      return new Response(res.body, { status: res.status, headers: h, statusText: res.statusText });
    }
  })();

  inFlight.set(key, p);
  try { return await p; } finally { inFlight.delete(key); }
}

export function normalizePrompt(s: string, maxChars = 700) {
  let out = s.trim().replace(/\s+/g, " ");
  if (out.length > maxChars) out = out.slice(0, maxChars);
  return out;
}

async function stableHash(obj: unknown) {
  const t = typeof obj === "string" ? obj : JSON.stringify(obj);
  const ab = new TextEncoder().encode(t);
  const h = await crypto.subtle.digest("SHA-256", ab);
  return [...new Uint8Array(h)].map(v=>v.toString(16).padStart(2,"0")).join("");
}

function delay(ms: number) { return new Promise(r=>setTimeout(r, ms)); }

// ---------- Observability / config ----------

function log(level: "metric" | "error" | "info", cfg: EdgeCoreConfig, payload: Record<string, unknown>) {
  console.log(JSON.stringify({ ts: new Date().toISOString(), level, ...payload }));
}
function serializeErr(err: unknown) {
  try { if (err instanceof Error) return { name: err.name, message: err.message, stack: err.stack }; return { message: String(err) }; }
  catch { return { message: "unknown error" }; }
}
const defaultKV: KVStore = new MemoryKV();
function route(cfg: EdgeCoreConfig) { return cfg.routeName ?? cfg.name ?? "-"; }
function materializeConfig(p: Partial<EdgeCoreConfig>): EdgeCoreConfig {
  const base = { ...defaultConfig, ...p };
  return { ...base, kv: p.kv ?? defaultKV, aiCache: p.aiCache ?? defaultKV, ai: { ...defaultConfig.ai!, ...(p.ai ?? {}) } };
}

// ---------- Safe JSON ----------

export async function readJsonSafe<T = unknown>(req: Request, maxBytes = defaultConfig.maxJsonBytes): Promise<T> {
  const ab = await req.arrayBuffer();
  if (ab.byteLength > maxBytes) throw new Error(`Payload too large: ${ab.byteLength}B > ${maxBytes}B`);
  const text = new TextDecoder().decode(ab);
  return JSON.parse(text) as T;
}

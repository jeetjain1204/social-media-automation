import { serve } from "std/http/server.ts";

const ALLOWED_METHODS = "POST, GET, OPTIONS";

function buildCorsHeaders(req: Request) {
  const origin = req.headers.get("origin") || "*";
  const reqHdrs =
    req.headers.get("access-control-request-headers") ||
    "authorization, content-type";
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Methods": ALLOWED_METHODS,
    "Access-Control-Allow-Headers": reqHdrs,
    "Access-Control-Max-Age": "86400",
    "Vary": "Origin, Access-Control-Request-Headers",
  } as const;
}

const json = (data: unknown, status = 200, extra: HeadersInit = {}) =>
  new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      ...extra,
    },
  });

// 12s cap to avoid hanging/billed time
function fetchWithTimeout(
  url: string,
  init: RequestInit = {},
  ms = 12000,
): Promise<Response> {
  const ac = new AbortController();
  const id = setTimeout(() => ac.abort(), ms);
  return fetch(url, { ...init, signal: ac.signal }).finally(() =>
    clearTimeout(id)
  );
}

// L1 cache for userinfo per token (5 min TTL)
type Entry = { v: string; exp: number };
const L1 = new Map<string, Entry>();
const l1Get = (k: string) => {
  const e = L1.get(k);
  if (!e) return null;
  if (e.exp < Date.now()) {
    L1.delete(k);
    return null;
  }
  return e.v;
};
const l1Set = (k: string, v: string, ttlSec: number) =>
  L1.set(k, { v, exp: Date.now() + ttlSec * 1000 });

serve(async (req) => {
  const cors = buildCorsHeaders(req);

  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200, headers: cors });
  }

  try {
    if (req.method !== "POST") {
      return json({ error: "Method not allowed" }, 405, cors);
    }

    // Parse body once
    const { accessToken } = await req.json();

    if (!accessToken) {
      return json({ error: "Missing access token" }, 400, cors);
    }

    // L1 cache hit (skip LinkedIn call)
    const noCache = req.headers.get("x-no-cache") === "1";
    if (!noCache) {
      const cached = l1Get(accessToken);
      if (cached) {
        return new Response(cached, {
          status: 200,
          headers: {
            ...cors,
            "Content-Type": "application/json; charset=utf-8",
            "x-cache": "L1",
          },
        });
      }
    }

    const linkedInRes = await fetchWithTimeout(
      "https://api.linkedin.com/v2/userinfo",
      {
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "X-Restli-Protocol-Version": "2.0.0",
          Accept: "application/json",
        },
      },
      12000,
    );

    // Read once (works for both ok and error)
    const text = await linkedInRes.text();

    if (!linkedInRes.ok) {
      // Pass through LinkedIn error body to help debugging, keep headers lean
      return json(
        { error: "LinkedIn API error", details: text },
        linkedInRes.status,
        cors,
      );
    }

    // Cache successful JSON payload for 5 minutes
    if (!noCache) l1Set(accessToken, text, 300);

    return new Response(text, {
      status: 200,
      headers: {
        ...cors,
        "Content-Type": "application/json; charset=utf-8",
        "x-cache": noCache ? "BYPASS" : "MISS",
      },
    });
  } catch (e: any) {
    // lean logging; no stack spam
    console.error("edge:error", e?.message || String(e));
    // rebuild CORS in case of thrown before initial build (very rare)
    return json(
      { error: "Unexpected error", details: e?.message || "unknown" },
      500,
      buildCorsHeaders(req),
    );
  }
});

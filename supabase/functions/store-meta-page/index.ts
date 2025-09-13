import { serve } from "std/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import "https://deno.land/x/dotenv/load.ts";

const CORS = {
  "Access-Control-Allow-Origin" : "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "content-type, authorization, apikey, x-client-info",
  "Access-Control-Max-Age"      : "86400",
};

// ── Env + DB
const { SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY } = Deno.env.toObject();
const ENV_OK = !!(SUPABASE_URL && SUPABASE_SERVICE_ROLE_KEY);

const db = createClient(
  SUPABASE_URL!,
  SUPABASE_SERVICE_ROLE_KEY!,
  {
    auth:   { persistSession: false },
    global: { headers: {
      apikey:       SUPABASE_SERVICE_ROLE_KEY!,
      Authorization:`Bearer ${SUPABASE_SERVICE_ROLE_KEY!}`,
    }},
  },
);

serve(async (req) => {
  // Pre-flight
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS });
  }

  if (!ENV_OK) {
    return json({ error: "server_misconfigured" }, 500);
  }

  // Only POST is meaningful here (GET would just 415/400 anyway)
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  // Parse body once
  let body: any;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const {
    user_id,
    platform,
    page_id,
    page_name,
    access_token,
    ig_user_id = null,
  } = body ?? {};

  if (
    !user_id      ||
    !page_id      ||
    !page_name    ||
    !access_token ||
    (platform !== "facebook" && platform !== "instagram")
  ) {
    return json({ error: "missing_fields" }, 400);
  }

  try {
    // Single timestamp reuse
    const now = new Date().toISOString();

    // Cheaper upsert: avoid .select() roundtrip/egress
    const { error: upErr } = await db
      .from("social_accounts")
      .upsert(
        {
          user_id: user_id,
          platform: platform,
          ig_user_id,
          page_id,
          page_name,
          access_token: access_token,
          connected_at: now,
          needs_reconnect: false,
          is_disconnected: false,
        },
        { onConflict: "user_id,platform", returning: "minimal" },
      );

    if (upErr) {
      // Log only the message to keep logs lean
      console.error("Upsert failed:", upErr.message || String(upErr));
      return json({ error: upErr.message || "db_upsert_failed" }, 500);
    }

    return json({ status: "ok" }, 201);

  } catch (e: any) {
    console.error("store-meta-page error:", e?.message || String(e));
    return json({ error: "db_insert_failed" }, 500);
  }
});

// ──────────  Helper  ──────────
function json(obj: unknown, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store", ...CORS },
  });
}

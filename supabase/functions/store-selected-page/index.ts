import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "@supabase/supabase-js";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// ---- Safe, bounded JSON parse (64KB) ----
async function readJsonSafe<T>(req: Request, maxBytes = 64 * 1024): Promise<T> {
  const ab = await req.arrayBuffer();
  if (ab.byteLength > maxBytes) throw new Error(`payload too large (${ab.byteLength}B)`);
  const txt = new TextDecoder().decode(ab);
  return JSON.parse(txt) as T;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  try {
    const body = await readJsonSafe<any>(req);
    const { user_id, access_token, /* refresh_token, */ organization_urn, page_name, account_type = "org" } = body;

    if (!user_id || !access_token || !organization_urn) {
      throw new Error("Missing required fields");
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !supabaseServiceRoleKey) {
      throw new Error("Missing Supabase environment variables");
    }

    const supabase = createClient(
      supabaseUrl,
      supabaseServiceRoleKey,
      { global: { headers: { Authorization: `Bearer ${supabaseServiceRoleKey}` } } },
    );

    const encryptionKey = Deno.env.get("ENCRYPTION_KEY");
    if (!encryptionKey) {
      throw new Error("Missing encryption key");
    }

    // --- Enforce URN ownership (same as your logic, but minimal columns) ---
    const { data: existingUrn } = await supabase
      .from("social_accounts")
      .select("author_urn")
      .eq("platform", "linkedin")
      .eq("author_urn", organization_urn)
      .neq("user_id", user_id)
      .maybeSingle();

    if (existingUrn) {
      console.warn(`[Store Page] URN conflict for org: ${organization_urn}`);
      return new Response(JSON.stringify({ error: "urn_conflict" }), {
        status: 409,
        headers: { "Content-Type": "application/json", ...corsHeaders },
      });
    }

    // --- One-shot UPSERT (no read → update/insert double roundtrip) ---
    // onConflict across the natural key (user_id, author_urn)
    const row = {
      user_id,
      platform: "linkedin",
      access_token: access_token, // (kept exactly as you store today)
      author_urn: organization_urn,
      account_type: account_type ?? "org",
      organization_urn: account_type === "org" ? organization_urn : null,
      page_name: page_name ?? null,
      connected_at: new Date().toISOString(),
      needs_reconnect: false,
      is_disconnected: false,
    };

    const { error: upsertErr } = await supabase
      .from("social_accounts")
      .upsert(row, { onConflict: "user_id,author_urn", returning: "minimal" });

    if (upsertErr) {
      // If a unique constraint elsewhere (e.g., platform+author_urn) trips, surface as conflict
      if ((upsertErr as any).code === "23505") {
        return new Response(JSON.stringify({ error: "urn_conflict" }), {
          status: 409,
          headers: { "Content-Type": "application/json", ...corsHeaders },
        });
      }
      throw new Error("Failed to upsert social account");
    }

    // --- Fetch subscription status (minimal select) ---
    const { data: sub } = await supabase
      .from("user_subscription_status")
      .select("is_trial_active, trial_ends_at, is_active_subscriber, plan_started_at")
      .eq("user_id", user_id)
      .maybeSingle();

    const now = Date.now();
    let nextRoute = "/free-trial";

    if (sub) {
      const trialEnds = sub.trial_ends_at ? new Date(sub.trial_ends_at).getTime() : NaN;
      const planStart = sub.plan_started_at ? new Date(sub.plan_started_at).getTime() : NaN;

      const trialActive = sub.is_trial_active === true && Number.isFinite(trialEnds) && now < trialEnds;
      const planActive =
        sub.is_active_subscriber === true &&
        Number.isFinite(planStart) &&
        now < (planStart + 30 * 24 * 60 * 60 * 1000);

      if (trialActive || planActive) nextRoute = "/home";
    }

    return new Response(JSON.stringify({ success: true, nextRoute }), {
      status: 200,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  } catch (err: any) {
    const message = err?.message ?? "Unknown error";
    console.error("Store Page Error:", message);

    const responseBody = {
      error: "Failed to store page",
      details: Deno.env.get("RAZORPAY_ENV") === "TEST" ? message : undefined,
    };

    return new Response(JSON.stringify(responseBody), {
      status: 500,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }
});

// ---- (Kept exactly for parity; not used in this handler) ----
function toKeyBytes(key: string): Uint8Array {
  const raw = new TextEncoder().encode(key);
  if (raw.length === 32) return raw;
  if (raw.length > 32) return raw.slice(0, 32);
  const padded = new Uint8Array(32);
  padded.set(raw);
  return padded;
}

export async function encryptToken(
  data: string,
  key: string,
): Promise<string> {
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

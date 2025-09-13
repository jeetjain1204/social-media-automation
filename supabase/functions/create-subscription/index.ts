import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.50.0";

/* ───────── helpers ───────── */
function ok(data: unknown) {
  return new Response(JSON.stringify({ success: true, data }), {
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Access-Control-Allow-Origin": "*",
      "Cache-Control": "no-store",
    },
  });
}
function err(code: number, msg: string) {
  return new Response(JSON.stringify({ success: false, error: msg }), {
    status: code,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Access-Control-Allow-Origin": "*",
      "Cache-Control": "no-store",
    },
  });
}

// Cap external calls to avoid hanging executions
async function fetchWithTimeout(url: string, init: RequestInit = {}, ms = 12000): Promise<Response> {
  const ac = new AbortController();
  const t = setTimeout(() => ac.abort(), ms);
  try { return await fetch(url, { ...init, signal: ac.signal }); }
  finally { clearTimeout(t); }
}

/* ───────── env + db ───────── */
const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const ENV_OK = !!(SUPABASE_URL && SUPABASE_SERVICE_ROLE_KEY);

const supabase = createClient(
  SUPABASE_URL ?? "",
  SUPABASE_SERVICE_ROLE_KEY ?? "",
  { global: { headers: { Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY ?? ""}` } } },
);

/* ───────── handler ───────── */
serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("OK", {
      status: 200,
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
        "Access-Control-Max-Age": "86400",
      },
    });
  }

  if (!ENV_OK) return err(500, "Server misconfigured");
  if (req.method !== "POST") return err(405, "Method not allowed");

  // Parse and validate input
  let parsed: any;
  try { parsed = await req.json(); } catch { return err(400, "Invalid JSON"); }
  const { user_id, duration } = parsed ?? {};
  if (!user_id) return err(400, "Missing user_id");
  if (!duration || !Number.isInteger(duration) || duration <= 0) return err(400, "Invalid duration");
  if (![1, 3, 6, 12].includes(duration)) return err(400, "duration must be 1, 3, 6 or 12");

  // Lookup user once; reuse email/phone
  const { data: userMeta, error: userErr } = await supabase.auth.admin.getUserById(user_id);
  if (userErr || !userMeta?.user?.email) return err(404, "User not found");
  const email = userMeta.user.email!;
  const phone = userMeta.user.phone ?? "";

  // Razorpay env + secrets
  const razorEnv = Deno.env.get("RAZORPAY_ENV") ?? "TEST";
  const KEY_ID = Deno.env.get(`RAZORPAY_KEY_ID_${razorEnv}`);
  const KEY_SECRET = Deno.env.get(`RAZORPAY_KEY_SECRET_${razorEnv}`);
  if (!KEY_ID || !KEY_SECRET) return err(500, "Razorpay keys missing");

  if (razorEnv === "LIVE" && KEY_ID.startsWith("rzp_test_")) {
    return err(500, "Test key used in live mode");
  }

  // Plans
  const planInfo: Record<number, { id: string | null; maxCycles: number }> = {
    1:  { id: Deno.env.get(`RAZORPAY_PLAN_ID_${razorEnv}_1M`) ?? null,  maxCycles: 300 },
    3:  { id: Deno.env.get(`RAZORPAY_PLAN_ID_${razorEnv}_3M`) ?? null,  maxCycles: 100 },
    6:  { id: Deno.env.get(`RAZORPAY_PLAN_ID_${razorEnv}_6M`) ?? null,  maxCycles: 50 },
    12: { id: Deno.env.get(`RAZORPAY_PLAN_ID_${razorEnv}_12M`) ?? null, maxCycles: 25 },
  };
  const info = planInfo[duration];
  if (!info?.id) return err(500, "Missing plan-id secret");

  // Precompute auth header
  const basicAuth = "Basic " + btoa(`${KEY_ID}:${KEY_SECRET}`);

  // Optional: create/reuse customer (non-fatal if fails)
  let customerId: string | null = null;
  try {
    const cRes = await fetchWithTimeout("https://api.razorpay.com/v1/customers", {
      method: "POST",
      headers: {
        Authorization: basicAuth,
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify({ name: email, email, contact: phone, fail_existing: 0 }),
    });
    if (cRes.ok) {
      const cJson = await cRes.json();
      customerId = cJson?.id ?? null;
    }
  } catch { /* ignore — customer_id is optional */ }

  // Create subscription (WRITE) — do not retry; we send Idempotency-Key
  const subRes = await fetchWithTimeout("https://api.razorpay.com/v1/subscriptions", {
    method: "POST",
    headers: {
      Authorization: basicAuth,
      "Content-Type": "application/json",
      Accept: "application/json",
      "Idempotency-Key": `${user_id}-${info.id}`,
    },
    body: JSON.stringify({
      plan_id: info.id,
      total_count: info.maxCycles,
      ...(customerId && { customer_id: customerId }),
      customer_notify: false,
      notes: {
        supabase_user_id: user_id,
        plan_duration_months: duration,
      },
    }),
  });

  const subText = await subRes.text();
  let subJson: any = null;
  try { subJson = JSON.parse(subText); } catch { /* error handled below */ }

  if (!subRes.ok || !subJson?.short_url || !subJson?.id) {
    console.error("Razorpay error →", subJson || subText);
    return err(500, (subJson?.error?.description as string) || "Subscription link failed");
  }

  // Persist status (lean: returning minimal)
  try {
    await supabase.from("user_subscription_status").upsert({
      user_id,
      billing_provider: "razorpay",
      billing_id: subJson.id,
      plan_name: "Blob Plus",
      plan_duration_months: duration,
      is_active_subscriber: false,
      updated_at: new Date().toISOString(),
    }, { onConflict: "user_id", returning: "minimal" });
  } catch (error) {
    console.error("upsert error:", error);
    // non-fatal for redirect/pay
  }

  return ok({
    subscription_id: subJson.id,
    email,                          // reuse from earlier lookup (no extra admin call)
    contact: phone || "+91XXXXXXXXXX",
  });
});

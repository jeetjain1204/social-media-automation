// supabase/functions/paypal-create-subscription.ts
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getPayPalAccessToken, env } from "../paypal-utils/index.ts";

/* ────────────── CORS ────────────── */
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, apikey, x-client-info",
} as const;
const JSON_HEADERS = { ...cors, "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" } as const;

/* ────────────── Helpers ────────────── */
// OPT: cap external call time (avoid hung executions)
function fetchWithTimeout(url: string, init: RequestInit = {}, ms = 12000) {
  const ac = new AbortController();
  const id = setTimeout(() => ac.abort(), ms);
  return fetch(url, { ...init, signal: ac.signal }).finally(() => clearTimeout(id));
}
const ok = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: JSON_HEADERS });
const err = (status: number, message: string) =>
  new Response(JSON.stringify({ error: message }), { status, headers: JSON_HEADERS });

/* ────────────── DB (top-level, single client) ────────────── */
const supabase = createClient(
  env("SUPABASE_URL"),
  env("SUPABASE_SERVICE_ROLE_KEY"),
  {
    auth: { persistSession: false },
    global: {
      headers: {
        apikey: env("SUPABASE_SERVICE_ROLE_KEY"),
        Authorization: `Bearer ${env("SUPABASE_SERVICE_ROLE_KEY")}`,
      },
    },
  },
);

serve(async (req) => {
  // Preflight
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return new Response("Method Not Allowed", { status: 405, headers: cors });

  // Parse once
  const { userId, duration } = await req.json().catch(() => ({}));

  // Validate inputs (keep names/shape the same)
  if (!userId) return err(400, "Missing userId");
  if (![1, 3, 6, 12].includes(duration)) return err(400, "Invalid duration");

  // OPT: pick env tag once
  const envTag = Deno.env.get("PAYPAL_ENV") === "live" ? "LIVE" : "TEST";

  // Plans from env (same variable names)
  const planMap: Record<number, string | null> = {
    1: env(`PAYPAL_PLAN_ID_${envTag}_1M`),
    3: env(`PAYPAL_PLAN_ID_${envTag}_3M`),
    6: env(`PAYPAL_PLAN_ID_${envTag}_6M`),
    12: env(`PAYPAL_PLAN_ID_${envTag}_12M`),
  };
  const planId = planMap[duration];
  if (!planId) return err(500, "Plan ID missing in env");

  try {
    // OPT: one token call, then idempotent create (PayPal-Request-Id)
    const { access_token, baseUrl } = await getPayPalAccessToken();
    const requestId = `${userId}-${duration}`;

    const subRes = await fetchWithTimeout(`${baseUrl}/v1/billing/subscriptions`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${access_token}`,
        "Content-Type": "application/json",
        "PayPal-Request-Id": requestId, // idempotent create
        Accept: "application/json",
      },
      body: JSON.stringify({
        plan_id: planId,
        custom_id: userId,
        application_context: {
          brand_name: "Blob",
          locale: "en-IN",
          user_action: "SUBSCRIBE_NOW",
          return_url: "https://app.blobautomation.com/payment",
          cancel_url: "https://app.blobautomation.com/payment",
          // return_url: "http://localhost:50368/payment",
          // cancel_url: "http://localhost:50368/payment",
        },
      }),
    });

    // Read body once for both paths
    const subText = await subRes.text();
    if (!subRes.ok) {
      // Pass through PayPal error details if any (kept concise)
      let reason = "PayPal subscription create failed";
      try {
        const j = JSON.parse(subText);
        reason = j?.message || j?.details?.[0]?.issue || reason;
      } catch { /* keep default reason */ }
      return err(subRes.status || 500, reason);
    }

    let sub: any;
    try { sub = JSON.parse(subText); } catch { return err(502, "Invalid PayPal response"); }

    const approveUrl = sub?.links?.find((l: any) => l?.rel === "approve")?.href;
    if (!sub?.id || !approveUrl) return err(502, "Missing approval link");

    // OPT: minimal egress on DB write
    await supabase.from("user_subscription_status").upsert(
      {
        user_id: userId,
        billing_provider: "paypal",
        billing_id: sub.id,
        plan_name: "Blob Plus",
        plan_duration_months: duration,
        status: sub.status,
        is_active_subscriber: false,
        is_trial_active: false,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "user_id", returning: "minimal" },
    );

    return ok({ approveUrl });
  } catch (e: any) {
    // Lean, safe error message
    return err(500, e?.message || "Unexpected error");
  }
});

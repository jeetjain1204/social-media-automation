// supabase/functions/paypal-subscription-webhook.ts (ULTRA optimized, drop-in)
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  verifyWebhookSignature,
  getPayPalAccessToken,
  safeIso,
  env,
} from "../paypal-utils/index.ts";

/* ────────────────────────── CORS / JSON ────────────────────────── */
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, apikey, x-client-info, paypal-auth-algo, paypal-cert-url, paypal-transmission-id, paypal-transmission-sig, paypal-transmission-time",
  "Access-Control-Max-Age": "86400",
} as const;
const JSON_HEADERS = { ...CORS, "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" } as const;
const ok = (msg = "OK") => new Response(msg, { status: 200, headers: CORS });
const err = (code: number, msg: string) => new Response(msg, { status: code, headers: CORS });

/* ────────────────────────── CONFIG ────────────────────────── */
const verifySig = Deno.env.get("VERIFY_PAYPAL_SIGNATURE") !== "false";

/* ─────────────────────── Supabase (top-level) ─────────────────────── */
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

/* ─────────────────────── Utilities (net/time) ─────────────────────── */
function addMonthsUtcISO(startIso: string, months: number): string {
  const d = new Date(startIso);
  const Y = d.getUTCFullYear();
  const M = d.getUTCMonth();
  const day = d.getUTCDate();
  const t = new Date(Date.UTC(
    Y, M, day,
    d.getUTCHours(), d.getUTCMinutes(), d.getUTCSeconds(), d.getUTCMilliseconds(),
  ));
  t.setUTCMonth(t.getUTCMonth() + (Number.isFinite(months) ? months : 1), 1);
  const monthDays = new Date(Date.UTC(t.getUTCFullYear(), t.getUTCMonth() + 1, 0)).getUTCDate();
  t.setUTCDate(Math.min(day, monthDays));
  return t.toISOString();
}

// Small timeout for PayPal GET (avoid hung executions)
async function fetchWithTimeout(url: string, init: RequestInit = {}, ms = 12000): Promise<Response> {
  const ac = new AbortController();
  const id = setTimeout(() => ac.abort(), ms);
  try { return await fetch(url, { ...init, signal: ac.signal }); }
  finally { clearTimeout(id); }
}

/* Helper to fetch custom_id when webhook omits it */
async function fetchCustomId(subId: string): Promise<string | null> {
  try {
    const { access_token, baseUrl } = await getPayPalAccessToken();
    const res = await fetchWithTimeout(`${baseUrl}/v1/billing/subscriptions/${subId}`, {
      headers: { Authorization: `Bearer ${access_token}`, Accept: "application/json" },
    });
    if (!res.ok) return null;
    const j = await res.json();
    return j?.custom_id ?? null;
  } catch {
    return null;
  }
}

/* ─────────────────────── In-isolate de-dup ───────────────────────
   Dedup by PayPal Transmission ID for 10 minutes (per instance). */
type DedupEntry = { exp: number };
const DEDUP = new Map<string, DedupEntry>();
function seenTransmission(txid: string | null | undefined): boolean {
  if (!txid) return false;
  const now = Date.now();
  const e = DEDUP.get(txid);
  if (e && e.exp > now) return true;
  DEDUP.set(txid, { exp: now + 10 * 60 * 1000 }); // 10 minutes
  return false;
}

/* ─────────────────────────── Handler ─────────────────────────── */
serve(async (req) => {
  // Preflight
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST")     return err(405, "Method Not Allowed");

  const txid = req.headers.get("paypal-transmission-id") || undefined;
  // Read body once
  const bodyStr = await req.text();

  // Optional signature verification (fast-fail)
  if (verifySig) {
    const okSig = await verifyWebhookSignature(bodyStr, req.headers);
    if (!okSig) return err(400, "Invalid signature");
  }

  // Dedup within instance (PayPal may retry)
  if (seenTransmission(txid)) return ok("Duplicate");

  // Parse event
  let event: any;
  try { event = JSON.parse(bodyStr); }
  catch { return err(400, "Bad JSON"); }

  const eventType = event?.event_type as string | undefined;
  if (!eventType) return err(400, "Missing event_type");
  if (!eventType.startsWith("BILLING.SUBSCRIPTION.")) {
    // Ignore unrelated events early
    return ok("Ignored");
  }

  const resource = event.resource || {};
  const subId: string | undefined = resource.id || resource.subscription_id;
  if (!subId) return err(400, "Missing subId");

  // DB setup
  const nowIso = new Date().toISOString();
  const startAt = safeIso(resource.start_time) ?? nowIso;

  // Try to find existing row for this sub
  let { data: row, error: selErr } = await supabase
    .from("user_subscription_status")
    .select("user_id, plan_duration_months")
    .eq("billing_provider", "paypal")
    .eq("billing_id", subId)
    .maybeSingle();

  if (selErr) {
    console.error("Select error:", selErr.message || String(selErr));
    // continue; we can still attempt to upsert/update below
  }

  // If no row, optionally seed it (best effort)
  if (!row) {
    let fallbackUser = resource.custom_id ?? null;
    if (!fallbackUser) fallbackUser = await fetchCustomId(subId);

    const stub: Record<string, unknown> = {
      billing_provider: "paypal",
      billing_id: subId,
      plan_name: resource.plan_id || "Blob Plus",
      status: resource.status ?? "PENDING",
      is_active_subscriber: false,
      is_trial_active: false,
      updated_at: startAt,
    };
    if (fallbackUser) stub.user_id = fallbackUser;

    const { error: upErr, data: upRow } = await supabase
      .from("user_subscription_status")
      .upsert(stub, { onConflict: "user_id", returning: "representation" })
      .select("user_id, plan_duration_months")
      .maybeSingle();

    if (upErr) {
      console.error("Seed upsert failed:", upErr.message || String(upErr));
      // non-fatal — we’ll still try to update by billing_id below
    } else {
      row = upRow ?? row;
    }
  }

  const uid    = row?.user_id ?? null;
  const planId = resource.plan_id || "Blob Plus";
  const months = Number(row?.plan_duration_months) || 1;

  // Compute endAt:
  // prefer PayPal's next_billing_time/end_time; else month add from startAt
  const computedEndIso = addMonthsUtcISO(startAt, months);
  const endAt =
    safeIso(resource.billing_info?.next_billing_time) ??
    safeIso(resource.end_time) ??
    computedEndIso;

  // Build update payload per event
  let upd: Record<string, unknown> = { updated_at: nowIso };

  switch (eventType) {
    case "BILLING.SUBSCRIPTION.ACTIVATED":
      upd = {
        ...upd,
        user_id: uid,
        billing_provider: "paypal",
        billing_id: subId,
        plan_name: planId,
        plan_started_at: startAt,
        plan_ends_at: endAt,
        last_renewed_at: startAt,
        is_active_subscriber: true,
        is_trial_active: false,
        status: "ACTIVE",
      };
      break;

    case "BILLING.SUBSCRIPTION.CANCELLED":
      upd = { ...upd, is_active_subscriber: false, status: "CANCELLED" };
      break;

    case "BILLING.SUBSCRIPTION.SUSPENDED":
      upd = { ...upd, is_active_subscriber: false, status: "SUSPENDED" };
      break;

    case "BILLING.SUBSCRIPTION.EXPIRED":
      upd = { ...upd, is_active_subscriber: false, status: "EXPIRED" };
      break;

    case "BILLING.SUBSCRIPTION.PAYMENT.FAILED":
      upd = { ...upd, is_active_subscriber: false, status: "PAYMENT_FAILED" };
      break;

    case "BILLING.SUBSCRIPTION.UPDATED":
      upd = { ...upd, plan_name: planId, plan_ends_at: endAt };
      break;

    default:
      // Unknown subscription event — acknowledge to stop retries
      return ok("Ignored");
  }

  // Persist (lean egress)
  const { error: updErr } = await supabase
    .from("user_subscription_status")
    .update(upd)
    .eq("billing_id", subId)
    .select() // keep for visibility; switch to returning:'minimal' if you want even leaner
    .throwOnError();

  if (updErr) {
    console.error("DB update error:", updErr.message || String(updErr));
    return err(500, "DB update error");
  }

  return ok("OK");
});

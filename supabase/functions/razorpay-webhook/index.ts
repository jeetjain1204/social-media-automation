import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.50.0";
import { encodeHex } from "https://deno.land/std@0.224.0/encoding/hex.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { global: { headers: { Authorization: `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!}` } } },
);

const SECRET_NEW = (Deno.env.get("RAZORPAY_WEBHOOK_SECRET") || "").trim();
const SECRET_OLD = (Deno.env.get("RAZORPAY_OLD_WEBHOOK_SECRET") || "").trim();

const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), {
    status: s,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "access-control-allow-origin": "*",
      "cache-control": "no-store",
    },
  });

/* ────────── utils ────────── */
function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}
async function sha256Hex(txt: string) {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(txt));
  return encodeHex(new Uint8Array(buf));
}
async function validSig(raw: string, header: string, rid?: string): Promise<boolean> {
  if (!header) {
    console.warn("[rzp-webhook]", rid, "signature header missing");
    return false;
  }
  const enc = new TextEncoder();
  const bodyBytes = enc.encode(raw);

  const secrets = [
    { label: "NEW", val: SECRET_NEW },
    { label: "OLD", val: SECRET_OLD },
  ].filter(s => s.val);

  for (const s of secrets) {
    try {
      const key = await crypto.subtle.importKey(
        "raw",
        enc.encode(s.val),
        { name: "HMAC", hash: "SHA-256" },
        false,
        ["sign"],
      );
      const sigBytes = new Uint8Array(await crypto.subtle.sign("HMAC", key, bodyBytes));
      const expected = encodeHex(sigBytes); // lower-case hex
      if (header.length === expected.length &&
          bytesEqual(enc.encode(header), enc.encode(expected))) {
        console.log("[rzp-webhook]", rid, "signature matched:", s.label);
        return true;
      }
    } catch (e) {
      console.error("[rzp-webhook]", rid, "sig calc error for", s.label, ":", (e as Error).message || String(e));
    }
  }
  console.warn("[rzp-webhook]", rid, "signature did not match any secret");
  return false;
}

function addMonthsUtc(ms: number, m: number): Date {
  const d = new Date(ms);
  const Y = d.getUTCFullYear();
  const M = d.getUTCMonth();
  const day = d.getUTCDate();
  const t = new Date(Date.UTC(Y, M, day, d.getUTCHours(), d.getUTCMinutes(), d.getUTCSeconds(), d.getUTCMilliseconds()));
  t.setUTCMonth(t.getUTCMonth() + m, 1);
  const monthDays = new Date(Date.UTC(t.getUTCFullYear(), t.getUTCMonth() + 1, 0)).getUTCDate();
  t.setUTCDate(Math.min(day, monthDays));
  return t;
}

async function getMonths(billingId: number | string) {
  console.log("[rzp-webhook] getMonths billing_id:", billingId);
  const { data, error } = await supabase
    .from("user_subscription_status")
    .select("plan_duration_months")
    .eq("billing_id", billingId)
    .single();
  if (error) console.error("[rzp-webhook] getMonths error:", error.message || String(error));
  const months = data?.plan_duration_months || 1;
  console.log("[rzp-webhook] getMonths ->", months);
  return months;
}

/** Resolve a stable event id:
 * 1) X-Razorpay-Event-Id
 * 2) Request-Id
 * 3) Nested entity id + event + created_at
 * 4) sha256(raw) fallback
 */
async function resolveEventId(req: Request, payload: any, raw: string): Promise<string> {
  const h = req.headers;
  const idHeader = (h.get("x-razorpay-event-id") || h.get("request-id") || "").trim();
  if (idHeader) return idHeader;

  const evt = payload?.event;
  const created = payload?.created_at ?? payload?.payload?.subscription?.entity?.created_at ?? null;

  const subId = payload?.payload?.subscription?.entity?.id;
  if (evt && subId) return `${evt}:${subId}:${created ?? "x"}`;

  const invId = payload?.payload?.invoice?.entity?.id;
  if (evt && invId) return `${evt}:${invId}:${created ?? "x"}`;

  const payId = payload?.payload?.payment?.entity?.id;
  if (evt && payId) return `${evt}:${payId}:${created ?? "x"}`;

  // last resort: hash the body
  return `body:${await sha256Hex(raw)}`;
}

/* ────────── handler ────────── */
serve(async (req) => {
  const rid = crypto.randomUUID();
  const t0 = Date.now();

  if (req.method === "OPTIONS") {
    console.log("[rzp-webhook]", rid, "OPTIONS");
    return new Response(null, {
      status: 204,
      headers: {
        "access-control-allow-origin": "*",
        "access-control-allow-methods": "POST,OPTIONS",
        "access-control-allow-headers": "content-type,x-razorpay-signature",
        "access-control-max-age": "86400",
      },
    });
  }

  console.log("[rzp-webhook]", rid, "method:", req.method);

  if (req.method !== "POST") {
    console.warn("[rzp-webhook]", rid, "non-POST received");
    return json({ error: "method_not_allowed" }, 405);
  }

  const sigHeaderRaw = (req.headers.get("x-razorpay-signature") || "").trim();
  console.log("[rzp-webhook]", rid, "sig present:", sigHeaderRaw ? "yes" : "no", "len:", sigHeaderRaw.length);

  const raw = await req.text();
  console.log("[rzp-webhook]", rid, "body length:", raw.length);

  const sigOk = await validSig(raw, sigHeaderRaw.toLowerCase(), rid);
  console.log("[rzp-webhook]", rid, "signature valid:", sigOk);
  if (!sigOk) return json({ error: "Bad signature" }, 400);

  let payload: any;
  try {
    payload = JSON.parse(raw);
  } catch (e) {
    console.error("[rzp-webhook]", rid, "JSON parse error:", (e as Error).message || String(e));
    return json({ error: "malformed" }, 400);
  }

  const evt = payload?.event as string | undefined;
  if (!evt) return json({ error: "missing_event" }, 400);

  const id = await resolveEventId(req, payload, raw);
  console.log("[rzp-webhook]", rid, "evt:", evt, "resolvedId:", id);

  const nowIso = new Date().toISOString();

  // idempotent store of raw event
  try {
    const { error: upErr } = await supabase.from("webhook_events").upsert(
      { id, event_type: evt, payload, received_at: nowIso },
      { onConflict: "id", returning: "minimal" },
    );
    if (upErr) console.error("[rzp-webhook]", rid, "webhook_events upsert error:", upErr.message || String(upErr));
    else console.log("[rzp-webhook]", rid, "webhook_events upsert ok");
  } catch (e) {
    console.error("[rzp-webhook]", rid, "webhook_events upsert threw:", (e as Error).message || String(e));
  }

  try {
    switch (evt) {
      case "subscription.authenticated": {
        const sub = payload.payload.subscription.entity;
        const uid = sub?.notes?.supabase_user_id;
        console.log("[rzp-webhook]", rid, evt, "uid:", uid);
        if (!uid) return json({ error: "no_user_in_notes" }, 400);

        const { error } = await supabase
          .from("user_subscription_status")
          .update({ updated_at: nowIso })
          .eq("user_id", uid)
          .select();
        if (error) {
          console.error("[rzp-webhook]", rid, evt, "update error:", error.message || String(error));
          return json({ error: "db_update_failed" }, 500);
        }
        break;
      }

      case "subscription.activated": {
        const sub = payload.payload.subscription.entity;
        const uid = sub?.notes?.supabase_user_id;
        if (!uid) return json({ error: "no_user_in_notes" }, 400);

        const months = Number(sub?.notes?.plan_duration_months) || 1;
        const startMs = (sub.start_at as number) * 1000;
        const startIso = new Date(startMs).toISOString();
        const planEnds = addMonthsUtc(startMs, months).toISOString();
        console.log("[rzp-webhook]", rid, evt, { uid, subId: sub.id, months, startMs, planEnds });

        const { error } = await supabase.from("user_subscription_status").upsert({
          user_id: uid,
          billing_id: sub.id,
          billing_provider: "razorpay",
          plan_name: sub.plan_id ?? "Blob Plus",
          plan_started_at: startIso,
          last_renewed_at: startIso,
          plan_ends_at: planEnds,
          plan_duration_months: months,
          is_active_subscriber: true,
          is_trial_active: false,
          updated_at: nowIso,
        }, { onConflict: "user_id", returning: "minimal" });
        if (error) {
          console.error("[rzp-webhook]", rid, evt, "upsert error:", error.message || String(error));
          return json({ error: "db_upsert_failed" }, 500);
        }
        break;
      }

      case "subscription.charged": {
        const sub = payload.payload.subscription.entity;
        const subId = sub.id;
        const months = Number(sub?.notes?.plan_duration_months) || await getMonths(subId);
        const startMs = ((sub.current_start ?? sub.start_at) as number) * 1000;
        const planEnds = addMonthsUtc(startMs, months).toISOString();
        console.log("[rzp-webhook]", rid, evt, { subId, months, startMs, planEnds });

        const { error } = await supabase.from("user_subscription_status")
          .update({
            last_renewed_at: nowIso,
            plan_ends_at: planEnds,
            plan_duration_months: months,
            is_active_subscriber: true,
            updated_at: nowIso,
          })
          .eq("billing_id", subId)
          .select();
        if (error) {
          console.error("[rzp-webhook]", rid, evt, "update error:", error.message || String(error));
          return json({ error: "db_update_failed" }, 500);
        }
        break;
      }

      case "subscription.halted":
      case "subscription.cancelled":
      case "subscription.completed":
      case "subscription.paused": {
        const subId = payload.payload.subscription.entity.id;
        console.log("[rzp-webhook]", rid, evt, { subId });

        const { error } = await supabase.from("user_subscription_status")
          .update({ is_active_subscriber: false, updated_at: nowIso })
          .eq("billing_id", subId)
          .select();
        if (error) {
          console.error("[rzp-webhook]", rid, evt, "update error:", error.message || String(error));
          return json({ error: "db_update_failed" }, 500);
        }
        break;
      }

      case "subscription.resumed":
      case "subscription.pending": {
        const subId = payload.payload.subscription.entity.id;
        console.log("[rzp-webhook]", rid, evt, { subId });

        const { error } = await supabase.from("user_subscription_status")
          .update({ is_active_subscriber: true, updated_at: nowIso })
          .eq("billing_id", subId)
          .select();
        if (error) {
          console.error("[rzp-webhook]", rid, evt, "update error:", error.message || String(error));
          return json({ error: "db_update_failed" }, 500);
        }
        break;
      }

      case "subscription.updated": {
        const sub = payload.payload.subscription.entity;
        const subId = sub.id;
        console.log("[rzp-webhook]", rid, evt, { subId, plan_id: sub.plan_id });

        const { error } = await supabase.from("user_subscription_status")
          .update({ plan_name: sub.plan_id ?? "Blob Plus", updated_at: nowIso })
          .eq("billing_id", subId)
          .select();
        if (error) {
          console.error("[rzp-webhook]", rid, evt, "update error:", error.message || String(error));
          return json({ error: "db_update_failed" }, 500);
        }
        break;
      }

      case "payment.failed":
      case "invoice.payment_failed": {
        const subId =
          payload.payload.subscription?.entity?.id ??
          payload.payload.invoice?.entity?.subscription_id;
        console.log("[rzp-webhook]", rid, evt, { subId });

        if (subId) {
          const { error } = await supabase.from("user_subscription_status")
            .update({ is_active_subscriber: false, updated_at: nowIso })
            .eq("billing_id", subId)
            .select();
          if (error) {
            console.error("[rzp-webhook]", rid, evt, "update error:", error.message || String(error));
            return json({ error: "db_update_failed" }, 500);
          }
        }
        break;
      }

      case "invoice.paid":
      case "invoice.partially_paid": {
        const inv = payload.payload.invoice.entity;
        const subId = inv.subscription_id;
        const months = await getMonths(subId);
        const startMs = ((inv.date ?? inv.issued_at) as number) * 1000;
        const planEnds = addMonthsUtc(startMs, months).toISOString();
        console.log("[rzp-webhook]", rid, evt, { subId, months, startMs, planEnds });

        const { error } = await supabase.from("user_subscription_status")
          .update({
            last_renewed_at: nowIso,
            plan_ends_at: planEnds,
            plan_duration_months: months,
            is_active_subscriber: true,
            updated_at: nowIso,
          })
          .eq("billing_id", subId)
          .select();
        if (error) {
          console.error("[rzp-webhook]", rid, evt, "update error:", error.message || String(error));
          return json({ error: "db_update_failed" }, 500);
        }
        break;
      }

      case "invoice.expired": {
        const subId = payload.payload.invoice.entity.subscription_id;
        console.log("[rzp-webhook]", rid, evt, { subId });

        const { error } = await supabase.from("user_subscription_status")
          .update({ is_active_subscriber: false, updated_at: nowIso })
          .eq("billing_id", subId)
          .select();
        if (error) {
          console.error("[rzp-webhook]", rid, evt, "update error:", error.message || String(error));
          return json({ error: "db_update_failed" }, 500);
        }
        break;
      }

      case "payment.captured":
      case "payment.authorized": {
        const payId = payload.payload.payment?.entity?.id;
        console.log("[rzp-webhook]", rid, evt, { payment_id: payId });
        break;
      }

      default:
        console.warn("[rzp-webhook]", rid, "Unhandled event:", evt);
        break;
    }
  } catch (e) {
    console.error("[rzp-webhook]", rid, "processing error:", (e as Error).message || String(e));
    return json({ error: "processing_failed" }, 500);
  }

  console.log("[rzp-webhook]", rid, "done in", Date.now() - t0, "ms");
  return json({ success: true });
});

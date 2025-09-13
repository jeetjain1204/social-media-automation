import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { crypto } from "https://deno.land/std@0.177.0/crypto/mod.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.50.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Max-Age": "86400",
};

const VALID_SCOPES = [
  "openid",
  "profile",
  "email",
  "w_member_social",
  "r_organization_social",
  "r_organization_admin",
  "w_organization_social",
  // "offline_access",
];

// --- tiny safe JSON (64KB cap), keeps your shape ---
async function readJsonSafe<T>(req: Request, maxBytes = 64 * 1024): Promise<T> {
  const ab = await req.arrayBuffer();
  if (ab.byteLength > maxBytes) {
    throw new Error(`Payload too large (${ab.byteLength}B)`);
  }
  const text = new TextDecoder().decode(ab);
  return JSON.parse(text) as T;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  try {
    // bounded parse
    const { user_id } = await readJsonSafe<{ user_id?: string }>(req);
    if (!user_id || typeof user_id !== "string") {
      throw new Error("Missing or invalid user_id in request body");
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

    // use global crypto (keeps your import)
    const nonce = (globalThis.crypto ?? crypto).randomUUID();

    // 10-min expiry
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();

    // duplicate-safe insert (ignore unique conflict if nonce already exists)
    const { error: nonceInsertError } = await supabase
      .from("oauth_nonce")
      .insert({ nonce, expires_at: expiresAt, user_id });

    if (nonceInsertError) {
      // ignore duplicate key (Postgres 23505) to be idempotent on quick retries
      if ((nonceInsertError as any).code !== "23505") {
        console.error("[OAuth URL] Nonce insert error:", nonceInsertError.message);
        throw new Error("Nonce storage failed");
      }
    }

    const clientId = Deno.env.get("LINKEDIN_CLIENT_ID");
    const redirectUri = Deno.env.get("LINKEDIN_REDIRECT_URI");
    if (!clientId || !redirectUri) {
      throw new Error("Missing LinkedIn environment variables");
    }

    // scopes (your list; validation is redundant but kept)
    const scope = VALID_SCOPES.join(" ");
    const scopeArray = scope.split(" ");
    if (!scopeArray.every((s) => VALID_SCOPES.includes(s))) {
      throw new Error("Invalid OAuth scopes detected");
    }

    // pack state (no double encode; URLSearchParams will escape it)
    const state = btoa(JSON.stringify({ user_id, nonce }));

    const authUrl = new URL("https://www.linkedin.com/oauth/v2/authorization");
    authUrl.searchParams.set("response_type", "code");
    authUrl.searchParams.set("client_id", clientId);
    authUrl.searchParams.set("redirect_uri", redirectUri);
    authUrl.searchParams.set("scope", scope);
    authUrl.searchParams.set("state", state); // ← removed encodeURIComponent()

    return new Response(JSON.stringify({ url: authUrl.toString() }), {
      status: 200,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    console.error("Error generating OAuth URL:", message);

    const responseBody = {
      error: "Failed to generate OAuth URL",
      // keep your TEST reveal behavior
      details: Deno.env.get("RAZORPAY_ENV") === "TEST" ? message : undefined,
    };

    return new Response(JSON.stringify(responseBody), {
      status: 400,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }
});

import { serve } from "https://deno.land/std/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.50.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Max-Age": "86400",
};

// Safe, bounded JSON parse (64 KB cap)
async function readJsonSafe<T>(req: Request, maxBytes = 64 * 1024): Promise<T> {
  const ab = await req.arrayBuffer();
  if (ab.byteLength > maxBytes) throw new Error(`payload too large (${ab.byteLength}B)`);
  const txt = new TextDecoder().decode(ab);
  return JSON.parse(txt) as T;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders });

  try {
    const { nonce } = await readJsonSafe<{ nonce?: string }>(req);
    if (!nonce || typeof nonce !== "string") throw new Error("missing nonce");

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const encryptionKey = Deno.env.get("ENCRYPTION_KEY");

    if (!supabaseUrl || !supabaseServiceRoleKey) throw new Error("missing supabase env");
    if (!encryptionKey) throw new Error("missing encryption key");

    const supabase = createClient(
      supabaseUrl,
      supabaseServiceRoleKey,
      // If you prefer, uncomment to always send Bearer header explicitly:
      // { global: { headers: { Authorization: `Bearer ${supabaseServiceRoleKey}` } } },
    );

    // ⚡ Atomic fetch+delete to avoid race: return deleted row in one call
    const { data, error } = await supabase
      .from("oauth_nonce")
      .delete()
      .eq("nonce", nonce)
      .select("encrypted_token, person_urn")
      .single();

    if (error || !data) throw new Error("nonce not found");

    const token = await decryptToken(data.encrypted_token, encryptionKey);

    // Do NOT log access tokens (keeps costs and risk low)
    // console.log('data.person_urn:', data.person_urn);

    return new Response(JSON.stringify({
      access_token: token,
      person_urn  : data.person_urn,
    }), {
      status: 200,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });

  } catch (err: any) {
    return new Response(JSON.stringify({ error: err?.message ?? "bad request" }), {
      status: 400,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }
});

function toKeyBytes(key: string): Uint8Array {
  const raw = new TextEncoder().encode(key);
  if (raw.length === 32) return raw;
  if (raw.length > 32) return raw.slice(0, 32);
  const padded = new Uint8Array(32);
  padded.set(raw);
  return padded;
}

export async function decryptToken(
  encryptedB64: string,
  key: string,
): Promise<string> {
  // Convert base64 → bytes
  const bytes = Uint8Array.from(atob(encryptedB64), c => c.charCodeAt(0));
  const iv = bytes.subarray(0, 12);
  const data = bytes.subarray(12);

  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    toKeyBytes(key),
    { name: "AES-GCM" },
    false,
    ["decrypt"],
  );

  const plain = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv },
    cryptoKey,
    data,
  );

  return new TextDecoder().decode(plain);
}

// import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
// import { createClient } from "@supabase/supabase-js";
// import { crypto } from "https://deno.land/std@0.177.0/crypto/mod.ts";

// const corsHeaders = {
//   "Access-Control-Allow-Origin": "*",
//   "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
//   "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
//   "Access-Control-Max-Age": "86400",
// };

// async function encryptToken(data: string, key: string): Promise<string> {
//   const encoder = new TextEncoder();
//   const keyData = encoder.encode(key);
//   const iv = crypto.getRandomValues(new Uint8Array(12)); // 96-bit IV for AES-GCM
//   const cryptoKey = await crypto.subtle.importKey(
//     "raw",
//     keyData,
//     { name: "AES-GCM" },
//     false,
//     ["encrypt"]
//   );

//   const encodedData = encoder.encode(data);
//   const encrypted = await crypto.subtle.encrypt(
//     { name: "AES-GCM", iv },
//     cryptoKey,
//     encodedData
//   );

//   const combined = new Uint8Array([...iv, ...new Uint8Array(encrypted)]);
//   return btoa(String.fromCharCode(...combined));
// }

// async function decryptToken(encryptedBase64: string, key: string): Promise<string> {
//   const decoder = new TextDecoder();
//   const keyData = new TextEncoder().encode(key);
//   const combined = Uint8Array.from(atob(encryptedBase64), (c) => c.charCodeAt(0));
//   const iv = combined.slice(0, 12);
//   const encryptedData = combined.slice(12);

//   const cryptoKey = await crypto.subtle.importKey(
//     "raw",
//     keyData,
//     { name: "AES-GCM" },
//     false,
//     ["decrypt"]
//   );

//   const decrypted = await crypto.subtle.decrypt(
//     { name: "AES-GCM", iv },
//     cryptoKey,
//     encryptedData
//   );

//   return decoder.decode(decrypted);
// }

// serve(async (req) => {
//   if (req.method === "OPTIONS") {
//     return new Response(null, { status: 204, headers: corsHeaders });
//   }

//   try {
//     const body = await req.json();
//     const { user_id, author_urn } = body;
//     if (!user_id || !author_urn) {
//       throw new Error("Missing user_id or author_urn");
//     }


//     const supabaseUrl = Deno.env.get("SUPABASE_URL");
//     const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
//     const clientId = Deno.env.get("LINKEDIN_CLIENT_ID");
//     const clientSecret = Deno.env.get("LINKEDIN_CLIENT_SECRET");
//     const encryptionKey = Deno.env.get("ENCRYPTION_KEY");

//     if (!supabaseUrl || !supabaseServiceRoleKey || !clientId || !clientSecret || !encryptionKey) {
//       throw new Error("Missing environment variables");
//     }

//     const supabase = createClient(supabaseUrl, supabaseServiceRoleKey, {
//       global: {
//         headers: {
//           Authorization: `Bearer ${supabaseServiceRoleKey}`,
//           "Content-Type": "application/json",
//         },
//       },
//     });

//     const { data: account } = await supabase
//       .from("social_accounts")
//       .select("*")
//       .eq("user_id", user_id)
//       .eq("author_urn", author_urn)
//       .eq("platform", "linkedin")
//       .maybeSingle();

//     if (!account?.refresh_token) {
//       throw new Error("No refresh token found");
//     }

//     if (account.token_expires_at && new Date(account.token_expires_at) > new Date()) {
//       return new Response(JSON.stringify({ success: true, cached: true }), {
//         status: 200,
//         headers: { "Content-Type": "application/json", ...corsHeaders },
//       });
//     }

//     const decryptedRefreshToken = await decryptToken(account.refresh_token, encryptionKey);


//     const refreshRes = await fetch("https://www.linkedin.com/oauth/v2/accessToken", {
//       method: "POST",
//       headers: { "Content-Type": "application/x-www-form-urlencoded" },
//       body: new URLSearchParams({
//         grant_type: "refresh_token",
//         refresh_token: decryptedRefreshToken,
//         client_id: clientId,
//         client_secret: clientSecret,
//       }),
//     });

//     if (!refreshRes.ok) {
//       const errorData = await refreshRes.json();
//       console.error(`[Refresh] LinkedIn refresh failed: ${JSON.stringify(errorData)}`);
//       throw new Error(`Refresh failed: ${errorData.message || refreshRes.statusText}`);
//     }

//     const newTokenData = await refreshRes.json();
//     if (!newTokenData.access_token || typeof newTokenData.access_token !== "string") {
//       throw new Error("Invalid refresh token response");
//     }

//     const encryptedAccessToken = await encryptToken(newTokenData.access_token, encryptionKey);
//     const encryptedRefreshToken = newTokenData.refresh_token
//       ? await encryptToken(newTokenData.refresh_token, encryptionKey)
//       : account.refresh_token;

//     const { error: updateError } = await supabase
//       .from("social_accounts")
//       .update({
//         access_token: encryptedAccessToken,
//         refresh_token: encryptedRefreshToken,
//         token_expires_at: new Date(Date.now() + (newTokenData.expires_in * 1000)),
//       })
//       .eq("user_id", user_id)
//       .eq("author_urn", author_urn)
//       .eq("platform", "linkedin");


//     if (updateError) {
//       throw new Error(`Update failed: ${updateError.message}`);
//     }

//     return new Response(JSON.stringify({ success: true }), {
//       status: 200,
//       headers: { "Content-Type": "application/json", ...corsHeaders },
//     });
//   } catch (err) {
//     const message = err instanceof Error ? err.message : "Unknown error";
//     console.error("Refresh Error:", message);
//     return new Response(
//       JSON.stringify({
//         error: "Refresh failed",
//         details: Deno.env.get("RAZORPAY_ENV") === "TEST" ? message : null,
//       }),
//       {
//         status: 500,
//         headers: { "Content-Type": "application/json", ...corsHeaders },
//       }
//     );
//   }
// });
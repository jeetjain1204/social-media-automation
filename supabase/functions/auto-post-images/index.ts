import { serve } from "std/http/server.ts";
import { wrapEdgeHandler1 } from "../_shared/edge-core.ts";

/* ─────────────── Tunables (env) ─────────────── */
const T = {
  SB: Number(Deno.env.get("SB_TIMEOUT_MS") ?? 6000),
  EXT: Number(Deno.env.get("EXT_TIMEOUT_MS") ?? 15000),
  UPLOAD: Number(Deno.env.get("UPLOAD_TIMEOUT_MS") ?? 25000),
};
// Keep 1 for identical sequential behavior; raise for faster batches
const CONCURRENCY = Number(Deno.env.get("INSIGHT_AUTOPOST_CONCURRENCY") ?? 1);

/* ─────────────── Helpers ─────────────── */
function withTimeout(init: RequestInit | undefined, ms: number): RequestInit {
  const haveStd = (AbortSignal as any).timeout;
  const signal = haveStd ? (AbortSignal as any).timeout(ms) : (() => {
    const c = new AbortController();
    setTimeout(() => c.abort(), ms);
    return c.signal;
  })();
  return { ...(init ?? {}), signal };
}

async function runPool<TIn, TOut>(
  items: TIn[],
  limit: number,
  task: (item: TIn, idx: number) => Promise<TOut>,
): Promise<TOut[]> {
  if (items.length === 0) return [];
  const results = new Array<TOut>(items.length);
  let i = 0;
  const workers: Promise<void>[] = [];
  const L = Math.max(1, limit);
  for (let w = 0; w < Math.min(L, items.length); w++) {
    workers.push((async function worker() {
      while (true) {
        const idx = i++;
        if (idx >= items.length) break;
        results[idx] = await task(items[idx], idx);
      }
    })());
  }
  await Promise.all(workers);
  return results;
}

function toArrayUrls(single?: string | null, multi?: string[] | null): string[] {
  if (Array.isArray(multi) && multi.length) return multi;
  if (single) return [single];
  return [];
}

/* ─────────────── Constants ─────────────── */
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const DB_HEADERS = {
  apikey: SERVICE_ROLE,
  Authorization: `Bearer ${SERVICE_ROLE}`,
  "Content-Type": "application/json",
};

/* LinkedIn — UGC + Posts API (for carousel) */
const LI_API_V2 = "https://api.linkedin.com/v2";
const LI_REST   = "https://api.linkedin.com/rest";
const LI_VER    = Deno.env.get("LINKEDIN_VERSION") ?? "202507"; // keep fresh
const LI_STD    = { "X-Restli-Protocol-Version": "2.0.0", "Content-Type": "application/json" } as const;
const LI_REST_STD = { ...LI_STD, "LinkedIn-Version": LI_VER };

/* Meta */
const META_GRAPH = "https://graph.facebook.com/v23.0";

/* ─────────────── DB patch helper ─────────────── */
async function patchJob(id: string, patch: Record<string, unknown>) {
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/scheduled_insight_card_posts?id=eq.${id}`,
    withTimeout({ method: "PATCH", headers: { ...DB_HEADERS, Prefer: "return=minimal" }, body: JSON.stringify(patch) }, T.SB),
  );
  if (!res.ok) console.error("PATCH error:", await res.text());
}

/* ─────────────── LinkedIn helpers ─────────────── */
// UGC text-only body
function liTextUGC(author: string, caption: string) {
  return {
    author,
    lifecycleState: "PUBLISHED",
    specificContent: {
      "com.linkedin.ugc.ShareContent": {
        shareCommentary: { text: caption?.slice(0, 2900) ?? "" },
        shareMediaCategory: "NONE",
      },
    },
    visibility: { "com.linkedin.ugc.MemberNetworkVisibility": "PUBLIC" },
  };
}
// UGC single image flow: register via v2 Assets, upload PUT, then UGC post
async function liRegisterImageV2(owner: string, token: string) {
  const reg = await fetch(`${LI_API_V2}/assets?action=registerUpload`, withTimeout({
    method: "POST",
    headers: { ...LI_STD, Authorization: `Bearer ${token}` },
    body: JSON.stringify({
      registerUploadRequest: {
        recipes: ["urn:li:digitalmediaRecipe:feedshare-image"],
        owner,
        serviceRelationships: [{ relationshipType: "OWNER", identifier: "urn:li:userGeneratedContent" }],
      },
    }),
  }, T.EXT));
  if (!reg.ok) throw new Error(await reg.text());
  const v = await reg.json();
  const uploadUrl = v.value.uploadMechanism["com.linkedin.digitalmedia.uploading.MediaUploadHttpRequest"].uploadUrl as string;
  const asset = v.value.asset as string;
  return { uploadUrl, asset };
}
async function httpPutBinary(url: string, bin: ArrayBuffer) {
  const up = await fetch(url, withTimeout({ method: "PUT", headers: { "Content-Type": "application/octet-stream" }, body: bin }, T.UPLOAD));
  if (!up.ok) throw new Error(await up.text());
}
async function liUGCImageShare(token: string, author: string, caption: string, assetUrn: string) {
  const shareRes = await fetch(`${LI_API_V2}/ugcPosts`, withTimeout({
    method: "POST",
    headers: { ...LI_STD, Authorization: `Bearer ${token}` },
    body: JSON.stringify({
      author,
      lifecycleState: "PUBLISHED",
      specificContent: {
        "com.linkedin.ugc.ShareContent": {
          shareCommentary: { text: caption?.slice(0, 2900) ?? "" },
          shareMediaCategory: "IMAGE",
          media: [{ status: "READY", media: assetUrn, title: { text: "Shared via Blob" } }],
        },
      },
      visibility: { "com.linkedin.ugc.MemberNetworkVisibility": "PUBLIC" },
    }),
  }, T.EXT));
  if (!shareRes.ok) throw new Error(await shareRes.text());
  return decodeURIComponent(shareRes.headers.get("x-restli-id") ?? "");
}
// Posts API (REST) carousel: initializeUpload per image → /rest/posts multiImage
async function liInitImageUpload(owner: string, token: string) {
  const r = await fetch(`${LI_REST}/images?action=initializeUpload`, withTimeout({
    method: "POST",
    headers: { ...LI_REST_STD, Authorization: `Bearer ${token}` },
    body: JSON.stringify({ initializeUploadRequest: { owner } }),
  }, T.EXT));
  if (!r.ok) throw new Error(await r.text());
  return (await r.json()).value as { uploadUrl: string; image: string };
}
async function liCreateMultiImagePost(author: string, token: string, caption: string, imageUrns: string[]) {
  const r = await fetch(`${LI_REST}/posts`, withTimeout({
    method: "POST",
    headers: { ...LI_REST_STD, Authorization: `Bearer ${token}` },
    body: JSON.stringify({
      author,
      commentary: caption?.slice(0, 3000) ?? "",
      visibility: "PUBLIC",
      distribution: { feedDistribution: "MAIN_FEED", targetEntities: [], thirdPartyDistributionChannels: [] },
      lifecycleState: "PUBLISHED",
      content: { multiImage: { images: imageUrns.map(id => ({ id })) } },
    }),
  }, T.EXT));
  if (!r.ok) throw new Error(await r.text());
  return decodeURIComponent(r.headers.get("x-restli-id") ?? "");
}

/* ─────────────── Facebook helpers ─────────────── */
async function fbPost(path: string, params: Record<string, any>) {
  const r = await fetch(`${META_GRAPH}${path}`, withTimeout({
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(params),
  }, T.EXT));
  const j = await r.json();
  if (!r.ok) throw new Error(JSON.stringify(j));
  return j;
}

/* ✅ NEW: Form-encoded helper for endpoints that require it (stories/photos) */
async function fbForm(path: string, params: Record<string, string>) {
  const r = await fetch(`${META_GRAPH}${path}`, withTimeout({
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(params),
  }, T.EXT));
  const j = await r.json();
  if (!r.ok) throw new Error(typeof j === "string" ? j : JSON.stringify(j));
  return j;
}

/* ─────────────── Instagram helpers ─────────────── */
/* JSON helper for IG (unchanged) */
async function igPost(path: string, params: Record<string, any>) {
  const r = await fetch(`${META_GRAPH}${path}`, withTimeout({
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(params),
  }, T.EXT));
  const j = await r.json();
  if (!r.ok) throw new Error(JSON.stringify(j));
  return j;
}

/* ✅ NEW: IG helper that uses Authorization header (per docs) */
async function igPostAuth(path: string, token: string, body: Record<string, any>) {
  const r = await fetch(`${META_GRAPH}${path}`, withTimeout({
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${token}`,
    },
    body: JSON.stringify(body),
  }, T.EXT));
  const j = await r.json();
  if (!r.ok) throw new Error(JSON.stringify(j));
  return j;
}


/* ─────────────── Per-job processor ─────────────── */
async function processJob(job: any) {
  const { id, user_id, platform, post_type, caption, image_url, image_urls } = job;
  console.log(`\n▶️  ${platform} | type ${post_type ?? "(legacy)"} | job_id ${id}`);

  // skinny SELECTs: only fields we need per platform
  let selectCols = "*";
  if (platform === "linkedin")  selectCols = "access_token,author_urn";
  if (platform === "facebook")  selectCols = "access_token,page_id";
  if (platform === "instagram") selectCols = "access_token,ig_user_id";

  const acctRes = await fetch(
    `${SUPABASE_URL}/rest/v1/social_accounts?user_id=eq.${user_id}&platform=eq.${platform}&select=${selectCols}`,
    withTimeout({ headers: DB_HEADERS }, T.SB),
  );
  const [acct] = await acctRes.json();
  if (!acct) {
    console.warn(`No ${platform} account linked for user ${user_id}`);
    return;
  }

  try {
    /* ───────── LinkedIn ───────── */
    if (platform === "linkedin") {
      const { access_token, author_urn } = acct as { access_token: string; author_urn: string };
      const urls = toArrayUrls(image_url, image_urls);

      if (post_type === "linkedin_post" || (!post_type && !urls.length)) {
        // text-only via UGC
        const res = await fetch(`${LI_API_V2}/ugcPosts`, withTimeout({
          method: "POST",
          headers: { ...LI_STD, Authorization: `Bearer ${access_token}` },
          body: JSON.stringify(liTextUGC(author_urn, caption ?? ""),),
        }, T.EXT));
        if (!res.ok) throw new Error(await res.text());
        const postUrn = decodeURIComponent(res.headers.get("x-restli-id") ?? "");
        await patchJob(id, { status: "success", linkedin_post_urn: postUrn });
        console.log("✅ LinkedIn text post success");
        return;
      }

      if (post_type === "linkedin_image" || (!post_type && urls.length === 1)) {
        // single image via Assets (v2) + UGC
        const { uploadUrl, asset } = await liRegisterImageV2(author_urn, access_token);
        const bin = await (await fetch(urls[0], withTimeout({}, T.EXT))).arrayBuffer();
        await httpPutBinary(uploadUrl, bin);
        const postUrn = await liUGCImageShare(access_token, author_urn, caption ?? "", asset);
        await patchJob(id, { status: "success", linkedin_asset_urn: asset, linkedin_post_urn: postUrn });
        console.log("✅ LinkedIn image success");
        return;
      }

      if (post_type === "linkedin_carousel" || (urls.length > 1)) {
        // multi-image via REST Posts API (multiImage)
        const imageUrns = await runPool(urls, 3, async (u) => {
          const { uploadUrl, image } = await liInitImageUpload(author_urn, access_token); // image: urn:li:image:...
          const bin = await (await fetch(u, withTimeout({}, T.EXT))).arrayBuffer();
          await httpPutBinary(uploadUrl, bin);
          return image;
        });
        const postUrn = await liCreateMultiImagePost(author_urn, access_token, caption ?? "", imageUrns);
        await patchJob(id, { status: "success", linkedin_post_urn: postUrn });
        console.log("✅ LinkedIn carousel success");
        return;
      }
    }

    /* ───────── Facebook ───────── */
    else if (platform === "facebook") {
      const { access_token, page_id } = acct as { access_token: string; page_id: string };
      const urls = toArrayUrls(image_url, image_urls);

      if (post_type === "facebook_post" || (!post_type && !urls.length)) {
        const { id: post_id } = await fbPost(`/${page_id}/feed`, {
          message: caption ?? "",
          published: true,
          access_token,
        });
        await patchJob(id, { status: "success", facebook_post_id: post_id });
        return;
      }

      if (post_type === "facebook_image" || (!post_type && urls.length === 1)) {
        const { id: photo_id, post_id } = await fbPost(`/${page_id}/photos`, {
          url: urls[0],
          caption: caption ?? "",
          published: true,
          access_token,
        });
        await patchJob(id, { status: "success", facebook_photo_id: photo_id, facebook_post_id: post_id });
        return;
      }

      /* ✅ FIXED: Strict story flow using form-encoded + /photo_stories */
      if (post_type === "facebook_story") {
        // Step 1: upload photo unpublished
        const up = await fbForm(`/${page_id}/photos`, {
          url: urls[0],
          published: "false",
          access_token,
        });
        const photo_id = up.id as string;

        // Step 2: publish photo story
        const story = await fbForm(`/${page_id}/photo_stories`, {
          photo_id,
          access_token,
        });

        const story_post_id = (story.post_id ?? story.id) as string | undefined;

        await patchJob(id, {
          status: "success",
          facebook_photo_id: photo_id,
          facebook_story_id: story_post_id ?? null,
        });
        return;
      }

      if (post_type === "facebook_multi" || urls.length > 1) {
        const photoIds = await runPool(urls, 3, async (u) => {
          const { id } = await fbPost(`/${page_id}/photos`, {
            url: u,
            published: false,
            access_token,
          });
          return id as string;
        });
        const attached_media = photoIds.map(id => ({ media_fbid: id }));
        const { id: post_id } = await fbPost(`/${page_id}/feed`, {
          message: caption ?? "",
          attached_media,
          access_token,
        });
        await patchJob(id, { status: "success", facebook_post_id: post_id });
        return;
      }
    }

    /* ───────── Instagram ───────── */
    else if (platform === "instagram") {
      const { access_token, ig_user_id } = acct as { access_token: string; ig_user_id: string };
      const urls = toArrayUrls(image_url, image_urls);

      /* ✅ FIXED: Story uses media_type=STORIES with Authorization header; no caption */
      if (post_type === "instagram_story") {
        const { id: container } = await igPostAuth(`/${ig_user_id}/media`, access_token, {
          image_url: urls[0],
          media_type: "STORIES",
        });
        const { id: story_media_id } = await igPostAuth(`/${ig_user_id}/media_publish`, access_token, {
          creation_id: container,
        });
        await patchJob(id, { status: "success", instagram_media_id: story_media_id });
        return;
      }

      if (post_type === "instagram_post" || (!post_type && urls.length === 1)) {
        const { id: container } = await igPost(`/${ig_user_id}/media`, {
          image_url: urls[0],
          caption: caption ?? "",
          access_token,
        });
        const { id: media_id } = await igPost(`/${ig_user_id}/media_publish`, {
          creation_id: container,
          access_token,
        });
        await patchJob(id, { status: "success", instagram_media_id: media_id });
        return;
      }

      if (post_type === "instagram_carousel" || urls.length > 1) {
        const childIds = await runPool(urls, 3, async (u) => {
          const { id } = await igPost(`/${ig_user_id}/media`, {
            image_url: u,
            is_carousel_item: true,
            access_token,
          });
          return id as string;
        });
        const { id: parent } = await igPost(`/${ig_user_id}/media`, {
          media_type: "CAROUSEL",
          children: childIds.join(","),
          caption: caption ?? "",
          access_token,
        });
        const { id: media_id } = await igPost(`/${ig_user_id}/media_publish`, {
          creation_id: parent,
          access_token,
        });
        await patchJob(id, { status: "success", instagram_media_id: media_id });
        return;
      }
    }

    else {
      console.warn(`Unknown platform "${platform}"`);
    }
  } catch (err) {
    console.error(`❌ ${platform} ${post_type ?? ""} failed:`, err);
    await patchJob(id, { status: "failed", error: String(err) });
  }
}

/* ─────────────── Entrypoint ─────────────── */
serve(wrapEdgeHandler1(async () => {
  const nowISO = new Date().toISOString();
  const jobsRes = await fetch(
    `${SUPABASE_URL}/rest/v1/scheduled_insight_card_posts?status=in.(scheduled,failed)&scheduled_at=lte.${nowISO}`,
    withTimeout({ headers: DB_HEADERS }, T.SB),
  );
  if (!jobsRes.ok) {
    return new Response(await jobsRes.text(), { status: jobsRes.status, headers: { "content-type": "text/plain" } });
  }
  const jobs: any[] = await jobsRes.json();
  if (!jobs.length) return new Response("No due posts.", { headers: { "content-type": "text/plain" } });

  await runPool(jobs, CONCURRENCY, processJob);

  return new Response("Image autopost run complete", { headers: { "content-type": "text/plain" } });
}, {
  serverTiming: true,
  requestId: true,
  hardenHeaders: true,
  etag: false,
  cors: false,
}));

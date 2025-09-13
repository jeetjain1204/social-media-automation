import { serve } from "std/http/server.ts";
import { wrapEdgeHandler } from "../_shared/edge-core.ts";

/* ─────────────── timeouts & concurrency ─────────────── */
const T = {
  SB: Number(Deno.env.get("SB_TIMEOUT_MS") ?? 6000),          // Supabase REST
  EXT: Number(Deno.env.get("EXT_TIMEOUT_MS") ?? 15000),       // LinkedIn / FB / IG API
  UPLOAD: Number(Deno.env.get("UPLOAD_TIMEOUT_MS") ?? 25000), // Binary PUTs
};
const CONCURRENCY = Number(Deno.env.get("AUTOPOST_CONCURRENCY") ?? 3);

/** Merge RequestInit with a timeout signal (AbortController/AbortSignal.timeout). */
function withTimeout(init: RequestInit | undefined, ms: number): RequestInit {
  const haveStd = (AbortSignal as any).timeout;
  const signal = haveStd ? (AbortSignal as any).timeout(ms) : (() => {
    const c = new AbortController();
    setTimeout(() => c.abort(), ms);
    return c.signal;
  })();
  return { ...(init ?? {}), signal };
}

/** Bounded concurrency pool; preserves original array order in results. */
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

/* ─────────────── constants ─────────────── */
const SB_URL     = Deno.env.get("SUPABASE_URL")!;
const SB_SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SB_HEADERS = {
  apikey: SB_SERVICE,
  Authorization: `Bearer ${SB_SERVICE}`,
  "Content-Type": "application/json",
};

const LI_API  = "https://api.linkedin.com/v2";              // legacy UGC
const LI_HDRS = { "X-Restli-Protocol-Version": "2.0.0", "Content-Type": "application/json" };

const LI_REST  = "https://api.linkedin.com/rest";           // versioned Posts API
const LI_VER   = "202507";
const LI_STD_H = {
  "Content-Type": "application/json",
  "X-Restli-Protocol-Version": "2.0.0",
  "LinkedIn-Version": LI_VER,
};

const FB_GRAPH = "https://graph.facebook.com/v23.0";

/* ─────────────── utils ─────────────── */
const mediaVariant = (urls: string[] | null | undefined) =>
  !urls?.length ? "text" : urls.length === 1 ? "single" : "multi";

async function patchPost(id: string, body: Record<string, unknown>) {
  await fetch(`${SB_URL}/rest/v1/scheduled_posts?id=eq.${id}`, withTimeout({
    method: "PATCH",
    headers: { ...SB_HEADERS, Prefer: "return=minimal" },
    body: JSON.stringify(body),
  }, T.SB));
}

/* ── LinkedIn helper set ───────────────────────────────────────────── */
async function liShare(
  path: string,
  token: string,
  body: Record<string, unknown>,
) {
  const res = await fetch(`${LI_API}${path}`, withTimeout({
    method: "POST",
    headers: { ...LI_HDRS, Authorization: `Bearer ${token}` },
    body: JSON.stringify(body),
  }, T.EXT));
  if (res.status === 401) throw new Error("LinkedIn token expired");
  if (!res.ok) throw new Error(await res.text());
  return res;
}

/* Assets API – single image */
async function liRegisterImage(owner: string, token: string) {
  const reg = await fetch(`${LI_API}/assets?action=registerUpload`, withTimeout({
    method: "POST",
    headers: { ...LI_HDRS, Authorization: `Bearer ${token}` },
    body: JSON.stringify({
      registerUploadRequest: {
        recipes: ["urn:li:digitalmediaRecipe:feedshare-image"],
        owner,
        serviceRelationships: [
          { relationshipType: "OWNER", identifier: "urn:li:userGeneratedContent" },
        ],
      },
    }),
  }, T.EXT));
  if (!reg.ok) throw new Error(await reg.text());
  const v = (await reg.json()).value;
  return { asset: v.asset as string, uploadUrl: v.uploadMechanism["com.linkedin.digitalmedia.uploading.MediaUploadHttpRequest"].uploadUrl as string };
}
async function uploadBinary(url: string, src: string) {
  const bin = await fetch(src, withTimeout({}, T.EXT)).then(r => r.arrayBuffer());
  const up  = await fetch(url, withTimeout({ method: "PUT", body: bin, headers: { "Content-Type": "application/octet-stream" } }, T.UPLOAD));
  if (!up.ok) throw new Error(await up.text());
}
function textShareBody(author: string, text: string) {
  return {
    author,
    lifecycleState: "PUBLISHED",
    specificContent: {
      "com.linkedin.ugc.ShareContent": {
        shareCommentary: { text: text?.slice(0, 2900) },
        shareMediaCategory: "NONE",
      },
    },
    visibility: { "com.linkedin.ugc.MemberNetworkVisibility": "PUBLIC" },
  };
}
function imageShareBody(author: string, text: string, asset: string) {
  return {
    author,
    lifecycleState: "PUBLISHED",
    specificContent: {
      "com.linkedin.ugc.ShareContent": {
        shareCommentary: { text: text?.slice(0, 2900) },
        shareMediaCategory: "IMAGE",
        media: [{ status: "READY", media: asset }],
      },
    },
    visibility: { "com.linkedin.ugc.MemberNetworkVisibility": "PUBLIC" },
  };
}

/* Posts API – multi-image */
async function liImageUpload(owner: string, token: string, src: string): Promise<string> {
  const init = await fetch(`${LI_REST}/images?action=initializeUpload`, withTimeout({
    method: "POST",
    headers: { ...LI_STD_H, Authorization: `Bearer ${token}` },
    body: JSON.stringify({ initializeUploadRequest: { owner } }),
  }, T.EXT));
  if (!init.ok) throw new Error(await init.text());
  const v = (await init.json()).value;
  const bin = await (await fetch(src, withTimeout({}, T.EXT))).arrayBuffer();
  const up  = await fetch(v.uploadUrl, withTimeout({ method: "PUT", headers: { "Content-Type": "application/octet-stream" }, body: bin }, T.UPLOAD));
  if (!up.ok) throw new Error(await up.text());
  return v.image; // urn:li:image:...
}
async function liPostMulti(
  author: string,
  token: string,
  caption: string,
  imgUrns: string[],
) {
  const body = {
    author,
    commentary: caption?.slice(0, 3000) ?? "",
    visibility: "PUBLIC",
    distribution: { feedDistribution: "MAIN_FEED", targetEntities: [], thirdPartyDistributionChannels: [] },
    lifecycleState: "PUBLISHED",
    content: { multiImage: { images: imgUrns.map(id => ({ id })) } },
  };
  const r = await fetch(`${LI_REST}/posts`, withTimeout({
    method: "POST",
    headers: { ...LI_STD_H, Authorization: `Bearer ${token}` },
    body: JSON.stringify(body),
  }, T.EXT));
  if (!r.ok) throw new Error(await r.text());
  return decodeURIComponent(r.headers.get("x-restli-id")!);
}

/* ── FB / IG helper ─────────────────────────────────────────────────── */
async function fbPost(path: string, params: any, token: string) {
  const r = await fetch(`${FB_GRAPH}${path}`, withTimeout({
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ ...params, access_token: token }),
  }, T.EXT));
  const j = await r.json();
  if (!r.ok) throw new Error(JSON.stringify(j));
  return j;
}
const igPost = fbPost;

/* ─────────────── platform handlers ─────────────── */
async function handleLinkedIn(p: any) {
  const [acct] = await fetch(
    `${SB_URL}/rest/v1/social_accounts?user_id=eq.${p.user_id}&platform=eq.linkedin` +
      `&needs_reconnect=is.false&is_disconnected=is.false&select=access_token,author_urn`,
    withTimeout({ headers: SB_HEADERS }, T.SB),
  ).then(r => r.json());

  if (!acct?.access_token || !acct?.author_urn) throw new Error("LinkedIn not connected");

  const token  = acct.access_token as string;
  const author = acct.author_urn   as string;
  const urls   = p.media_urls ?? [];

  /* text-only */
  if (urls.length === 0) {
    await liShare("/ugcPosts", token, textShareBody(author, p.caption));
    return;
  }

  /* single image (UGC) */
  if (urls.length === 1) {
    const { asset, uploadUrl } = await liRegisterImage(author, token);
    await uploadBinary(uploadUrl, urls[0]);
    await liShare("/ugcPosts", token, imageShareBody(author, p.caption, asset));
    return;
  }

  /* multi-image (Posts API) — upload in parallel (order preserved) */
  const urns = await runPool(urls, CONCURRENCY, (u: string) => liImageUpload(author, token, u));
  const postUrn = await liPostMulti(author, token, p.caption, urns);
  await patchPost(p.id, { post_urn: postUrn });
}

async function handleFacebook(p: any) {
  const [acct] = await fetch(
    `${SB_URL}/rest/v1/social_accounts?user_id=eq.${p.user_id}&platform=eq.facebook&select=access_token,page_id`,
    withTimeout({ headers: SB_HEADERS }, T.SB),
  ).then(r => r.json()) as Array<{ access_token?: string; page_id?: string }>;

  if (!acct?.access_token || !acct?.page_id) throw new Error("Facebook not connected");

  const variant = mediaVariant(p.media_urls);
  const page_id = acct.page_id!;
  const token   = acct.access_token!;

  if (variant === "text") {
    const { id } = await fbPost(`/${page_id}/feed`, { message: p.caption, published: true }, token);
    await patchPost(p.id, { post_id: id });
    return;
  }

  if (p.post_type === "facebook_story") {
    const { id: photo_id } = await fbPost(`/${page_id}/photos`, { url: p.media_urls[0], published: false }, token);
    const { id: story_id } = await fbPost(`/${page_id}/photo_stories`, { photo_id }, token);
    await patchPost(p.id, { post_id: story_id });
    return;
  }

  if (variant === "single") {
    const { post_id } = await fbPost(`/${page_id}/photos`,
      { url: p.media_urls[0], caption: p.caption, published: true }, token);
    await patchPost(p.id, { post_id });
    return;
  }

  // multi — upload photos in parallel but keep order for attached_media
  const ids = await runPool<string, string>(p.media_urls, CONCURRENCY, async (url) => {
    const { id } = await fbPost(`/${page_id}/photos`, { url, published: false }, token);
    return id;
  });
  const attached_media = ids.map(id => ({ media_fbid: id }));
  const { id: postId } = await fbPost(`/${page_id}/feed`,
    { message: p.caption, attached_media }, token);
  await patchPost(p.id, { post_id: postId });
}

async function handleInstagram(p: any) {
  if (!p.media_urls?.length) throw new Error("Instagram requires at least one image");

  const [acct] = await fetch(
    `${SB_URL}/rest/v1/social_accounts?user_id=eq.${p.user_id}&platform=eq.instagram&select=access_token,ig_user_id`,
    withTimeout({ headers: SB_HEADERS }, T.SB),
  ).then(r => r.json()) as Array<{ access_token?: string; ig_user_id?: string }>;

  if (!acct?.access_token || !acct?.ig_user_id) throw new Error("Instagram not connected");

  const variant = mediaVariant(p.media_urls);
  const ig_id   = acct.ig_user_id!;
  const token   = acct.access_token!;

  /* story – single image, no caption */
  if (p.post_type === "instagram_story") {
    const { id: container } = await igPost(`/${ig_id}/media`,
      { image_url: p.media_urls[0], media_type: "STORIES" }, token);
    const { id: storyId }  = await igPost(`/${ig_id}/media_publish`,
      { creation_id: container }, token);
    await patchPost(p.id, { post_id: storyId });
    return;
  }

  /* single image post */
  if (variant === "single") {
    const { id: container } = await igPost(`/${ig_id}/media`,
      { image_url: p.media_urls[0], caption: p.caption }, token);
    const { id: postId }  = await igPost(`/${ig_id}/media_publish`, { creation_id: container }, token);
    await patchPost(p.id, { post_id: postId });
    return;
  }

  /* carousel — create children in parallel; maintain order */
  const childIds = await runPool<string, string>(p.media_urls, CONCURRENCY, async (url) => {
    const { id } = await igPost(`/${ig_id}/media`, { image_url: url, is_carousel_item: true }, token);
    return id;
  });
  const { id: parent } = await igPost(`/${ig_id}/media`,
    { media_type: "CAROUSEL", children: childIds.join(","), caption: p.caption }, token);
  const { id: carouselId } = await igPost(`/${ig_id}/media_publish`,
    { creation_id: parent }, token);
  await patchPost(p.id, { post_id: carouselId });
}

/* ─────────────── cron entrypoint ─────────────── */
serve(wrapEdgeHandler(async () => {
  const nowISO = new Date().toISOString();

  const activeUsers = await fetch(
    `${SB_URL}/rest/v1/user_subscription_status?is_active_subscriber=eq.true&select=user_id`,
    withTimeout({ headers: SB_HEADERS }, T.SB),
  ).then(r => r.json()) as Array<{ user_id: string }>;

  if (!activeUsers.length) return new Response("No active subscribers.");

  const userFilter = `user_id=in.(${activeUsers.map(u => `"${u.user_id}"`).join(",")})`;

  const posts = await fetch(
    `${SB_URL}/rest/v1/scheduled_posts?status=in.(scheduled,failed)&scheduled_at=lte.${nowISO}&${userFilter}`,
    withTimeout({ headers: SB_HEADERS }, T.SB),
  ).then(r => r.json()) as any[];

  if (!posts.length) return new Response("No due posts.");

  // Process posts with bounded concurrency; preserves behavior per post.
  await runPool(posts, CONCURRENCY, async (post) => {
    try {
      switch (post.platform) {
        case "linkedin":  await handleLinkedIn(post);  break;
        case "facebook":  await handleFacebook(post);  break;
        case "instagram": await handleInstagram(post); break;
        default: throw new Error("Unsupported platform");
      }
      await patchPost(post.id, { status: "success", posted_at: new Date().toISOString() });
    } catch (err) {
      console.error(`❌ ${post.platform}`, err);
      await patchPost(post.id, { status: "failed" });
    }
  });

  return new Response("Auto-post run complete.", { headers: { "content-type": "text/plain" } });
}, {
  serverTiming: true,   // TTFB visibility
  requestId: true,      // trace across logs
  hardenHeaders: true,  // safe security headers
  etag: false,          // cron responses don’t need ETags
  cors: false,          // not a browser-facing endpoint
}));

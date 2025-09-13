import { serve } from "std/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import OpenAI from "https://esm.sh/openai@4";
import { wrapEdgeHandler, readJsonSafe, ensureIdempotency } from "../_shared/edge-core.ts";
import { createRedisKV } from "../_shared/kv_redis.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const {
  SUPABASE_URL,
  SUPABASE_SERVICE_ROLE_KEY,
  OPENAI_API_KEY,
} = Deno.env.toObject();

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  throw new Error("Missing Supabase env vars");
}
if (!OPENAI_API_KEY) {
  throw new Error("Missing OPENAI_API_KEY");
}

const supabase = createClient(
  SUPABASE_URL,
  SUPABASE_SERVICE_ROLE_KEY, {
  global: { headers: { "X-Client-Info": "edge-generate-bg" } },
});

const openai = new OpenAI({ apiKey: OPENAI_API_KEY });

const personaMap: Record<string, string> = {
  "solo-creator": "an independent creator speaking directly to their audience",
  "smb-founder": "a small-business owner showcasing their own brand or product",
  "agency-freelancer": "a service professional crafting work for diverse clients",
};

const categoryMap: Record<string, string> = {
  /* Solo Creator */
  "comedy": "comedy content focused on laughs and entertainment",
  "tech": "tech coverage spanning gadgets, software, and coding",
  "education": "instructional and knowledge-sharing education content",
  "lifestyle-vlogs": "personal vlogs about routines, habits, and daily life",
  "gaming": "video-game playthroughs, reviews, and commentary",
  "beauty-fashion": "style, cosmetics, and fashion inspiration",
  "fitness-wellness": "fitness routines and holistic wellness guidance",
  "finance-investing": "personal finance tips and investment insights",
  "travel-adventure": "travel explorations, guides, and hacks",
  "music-performance": "musical performances, covers, and tutorials",
  "food-cooking": "cooking how-tos, recipes, and food reviews",
  "art-diy": "creative art projects and do-it-yourself crafts",
  "personal-development": "productivity, mindset, and self-improvement topics",

  /* SMB Founder */
  "fashion-apparel": "businesses creating or selling clothing and accessories",
  "food-beverage": "ventures serving or packaging food and drink",
  "health-wellness": "products and services promoting physical health",
  "technology-saas": "software and tech product companies",
  "professional-services": "knowledge-based B2B service firms",
  "real-estate-property": "property sales, leasing, and management",
  "automotive": "vehicle sales, services, or parts",
  "education-training": "learning, coaching, and skills-development ventures",
  "creative-media": "media production and creative service businesses",
  "home-living": "home goods, interiors, and living solutions",
  "financial-services-fintech":
    "financial products and innovative fintech offerings",
  "logistics-supply-chain": "goods movement, warehousing, and delivery",
  "manufacturing-industrial": "industrial production and factory operations",
  "agriculture-agritech": "farming ventures and agricultural technology",
  "energy-utilities": "power generation, infrastructure, and utilities",

  /* Agency / Freelancer */
  "marketing-growth": "agencies driving brand growth and advertising",
  "design-services": "visual and product design offerings",
  "development-it": "software development and IT solutions",
  "video-animation": "video production and animation services",
  "writing-content": "professional writing and editorial work",
  "photography-creative-media": "photography and related creative shoots",
  "consulting-strategy": "strategic consulting and business advisory",
  "translation-localization": "language adaptation and localization services",
  "data-analytics": "data insight and optimization services",
  "virtual-assistance-admin": "remote administrative and VA support",
  "finance-legal-advisory": "financial and legal consulting services",
  "hr-talent-services": "recruitment and workforce management solutions",
  "product-cx-research": "user research and customer-experience studies",
  "audio-podcast-production": "audio engineering and podcast creation",
  "ar-vr-immersive-tech": "augmented and virtual-reality technology services",
};

const subcategoryMap: Record<string, string> = {
  "ai-tool-demos": "live demonstrations of AI apps and utilities",
  "animated-explainers": "concepts taught through engaging animation",
  "asmr-cooking": "soothing, sound-focused cooking sessions",
  "backpacking-guides": "budget travel itineraries for backpackers",
  "beat-making": "step-by-step creation of music beats",
  "book-summaries": "condensed key insights from popular books",
  "budgeting-tips": "advice on saving money and planning budgets",
  "city-walkthroughs": "guided tours through notable city spots",
  "coding-dev-logs": "developer diaries showing real coding progress",
  "cover-sessions": "renditions and covers of well-known songs",
  "crafts-hacks": "handmade craft projects and clever hacks",
  "crypto-breakdowns": "clear explanations of cryptocurrency topics",
  "daily-routines": "run-throughs of everyday schedules",
  "day-in-the-life": "vlogs showcasing a full typical day",
  "digital-drawing": "artwork created on digital tablets and apps",
  "diy-skincare": "homemade skincare tips and recipes",
  "drone-filming": "aerial footage captured via drones",
  "food-tours": "explorations of local culinary scenes",
  "game-reviews": "opinions and ratings of video-game releases",
  "hardware-unboxings": "first-look unboxing of new tech gear",
  "healthy-recipes": "tutorials for nutritious meals",
  "history-storytelling": "narratives recounting historical events",
  "home-makeovers": "room redesign and transformation projects",
  "home-workouts": "exercise routines doable without a gym",
  "instrument-tutorials": "lessons on how to play musical instruments",
  "international-cuisine": "recipes from cultures around the world",
  "lets-plays": "live gameplay with commentary",
  "live-looping": "real-time music looping performances",
  "meal-prep": "bulk cooking sessions for the week ahead",
  "memes": "viral trends and captioned images",
  "mental-health-chats": "open discussions on mental wellbeing",
  "minimalism": "content focused on simplifying possessions",
  "mindfulness": "techniques for present-moment awareness",
  "mutual-fund-deep-dives": "in-depth analysis of mutual-fund offerings",
  "original-songs": "performances of self-written music",
  "outfit-lookbooks": "curated outfit showcases and inspiration",
  "personal-development": "self-improvement strategies and motivation",
  "product-hauls": "shopping haul showcases and reviews",
  "product-reviews": "hands-on evaluations of gadgets or tools",
  "quick-recipes": "fast, easy-to-follow cooking tutorials",
  "reaction-videos": "live responses to other videos or events",
  "relatable-humor": "jokes that resonate with everyday life",
  "resin-art": "artistic creations using epoxy resin",
  "satire-parody": "mock or spoof comedic commentary",
  "science-experiments": "visual demonstrations of scientific principles",
  "skits": "scripted short comedy scenes",
  "speedruns": "record-attempt fast game completions",
  "stream-highlights": "best moments clipped from livestreams",
  "study-tips": "methods for more effective studying",
  "study-with-me": "real-time study sessions for accountability",
  "styling-hacks": "quick tips to improve personal style",
  "travel-hacks": "insider tricks for cheaper, easier travel",
  "transformation-journeys": "before-and-after fitness or lifestyle stories",
  "tutorials": "step-by-step instructional videos",
  "upcycling-projects": "turning waste into useful or artful items",
  "accounting-practice": "professional accounting and bookkeeping firm",
  "agri-input-supplier": "provider of seeds, fertilizers, and farm inputs",
  "architecture-studio": "firm specializing in building and space design",
  "auto-parts-e-commerce": "online storefront selling vehicle parts",
  "auto-repair-shop": "garage offering car maintenance and repairs",
  "b2b-saas": "subscription software serving other businesses",
  "bakery-desserts": "shop producing breads, pastries, and sweets",
  "bio-fuel-production": "facility manufacturing renewable biofuels",
  "car-rental": "service renting vehicles short-term",
  "cafe-coffee-bar": "casual establishment focusing on coffee drinks",
  "cloud-kitchen": "delivery-only food production facility",
  "cold-chain": "temperature-controlled logistics provider",
  "commercial-leasing": "leasing of office and retail properties",
  "consulting-agency": "business advisory and strategy consulting firm",
  "corporate-training": "employee upskilling and development programs",
  "custom-tailoring": "made-to-measure clothing services",
  "cybersecurity": "company providing cybersecurity solutions",
  "dealership": "showroom selling new or used vehicles",
  "d2c-e-commerce": "direct-to-consumer online retail brand",
  "edtech-platform": "digital platform delivering education content",
  "electronics-assembly": "facility assembling electronic devices",
  "ev-charging-network": "infrastructure providing EV charging stations",
  "event-management": "planning and executing live events",
  "fmcg-manufacturing": "factory producing fast-moving consumer goods",
  "freight-forwarding": "coordinating cargo movement across transport modes",
  "furniture-manufacturing": "production of household or office furniture",
  "gym-fitness-studio": "physical venue offering exercise classes",
  "hr-outsourcing": "external provider of HR processes",
  "hydroponics": "soil-less, water-based crop cultivation",
  "influencer-merch": "creator-branded merchandise ventures",
  "insurtech": "technology-driven insurance provider",
  "it-services": "managed IT and tech support company",
  "landscaping": "designing and maintaining outdoor spaces",
  "last-mile-delivery": "final-leg courier and delivery services",
  "legal-firm": "practice offering legal counsel and services",
  "mobile-app-startup": "company building smartphone applications",
  "nbfc-micro-finance": "non-bank lender offering micro-loans",
  "nutraceutical-brand": "company selling health supplements",
  "organic-farming": "agriculture avoiding synthetic chemicals",
  "packaged-fmcg": "retail packaged food or drink products",
  "payments-wallets": "digital payment or e-wallet service",
  "precision-engineering": "high-tolerance parts manufacturing",
  "printing-branding": "print shop offering branding materials",
  "production-house": "studio creating video or film content",
  "property-management": "service handling upkeep and tenants",
  "restaurant": "full-service dining establishment",
  "retail-boutique": "brick-and-mortar fashion store",
  "solar-epc": "engineering, procurement & construction for solar",
  "sustainable-fashion": "eco-friendly clothing business",
  "telehealth-clinic": "online platform for medical consultations",
  "test-prep-institute": "center preparing students for exams",
  "third-party-logistics": "outsourced logistics and warehousing",
  "vacation-rentals": "short-term holiday property rentals",
  "warehousing": "storage facility for goods",
  "wealth-advisory": "investment and financial planning counsel",
  "yoga-center": "facility dedicated to yoga practice",
  "a-b-testing": "running controlled experiments to compare variants",
  "advertising-studio": "creative agency designing ads and campaigns",
  "api-integrations": "connecting disparate software systems via APIs",
  "ar-filters": "augmented-reality face or world filters",
  "attribution-modeling": "assigning credit to marketing channels",
  "audiobook-production": "recording and mastering audiobooks",
  "brand-identity": "creating logos and visual brand systems",
  "brand-positioning": "defining a brand’s unique market stance",
  "calendar-management": "organizing and scheduling client calendars",
  "copywriting": "writing persuasive marketing text",
  "dashboard-building": "developing interactive data dashboards",
  "devops-cloud": "infrastructure automation and cloud ops",
  "email-marketing": "strategizing and sending engaging email campaigns",
  "explainer-videos": "informational animated or live-action explainers",
  "fractional-cfo": "providing part-time CFO services",
  "gtm-strategy": "planning a product’s go-to-market approach",
  "growth-hacking": "rapid experimentation to drive growth",
  "illustration": "bespoke artwork and illustrations",
  "influencer-collabs": "managing partnerships with influencers",
  "investor-pitch-decks": "designing fundraising presentations",
  "jingle-composition": "creating catchy musical jingles",
  "livestream-production": "setting up and producing live video streams",
  "motion-graphics": "animated graphic design assets",
  "podcast-editing": "editing and mixing podcast episodes",
  "post-production": "video editing, color grading, and VFX",
  "presentation-design": "crafting visually engaging slide decks",
  "pricing-optimization": "improving pricing models for revenue",
  "prototype-testing": "validating early product designs with users",
  "scriptwriting": "writing scripts for video or audio",
  "seo-analytics": "analyzing search-engine performance",
  "shopify-e-commerce": "building and optimizing Shopify stores",
  "social-media-management": "planning, posting, and analyzing social content",
  "subtitle-captioning": "creating subtitles and captions for videos",
  "ui-ux-design": "designing intuitive user interfaces",
  "user-interviews": "conducting qualitative interviews with users",
  "voice-acting": "providing character or narration voices",
  "web-development": "building websites and web applications",
  "language-learning": "interactive content for mastering new languages",
  "college-life": "experiences and tips from student campus routines",
  "let-s-plays": "gameplay walkthroughs with real-time commentary",
  "esports-commentary": "analysis and opinions on professional esports events",
  "makeup-tutorials": "step-by-step guides to cosmetic techniques and looks",
  "side-hustle-ideas": "practical ways to earn extra income alongside a main job",
  "cultural-immersion": "first-hand experiences exploring global cultures",
  "street-food-reviews": "authentic tastings and opinions on local street food",
  "3d-printing": "projects and tutorials using 3D printing tech",
  "productivity-systems": "methods and apps to boost daily efficiency",
  "goal-setting": "strategies to define, track, and achieve goals",
  "wholesale-supplier": "bulk goods providers for B2B resellers",
  "spa-wellness": "services offering relaxation, therapy, and self-care",
  "ai-solutions": "firms delivering custom AI-based automation or tools",
  "residential-brokerage": "agencies handling buy/sell of homes and apartments",
  "co-working-spaces": "shared office environments for remote professionals",
  "skill-bootcamp": "intensive short-term training in high-demand fields",
  "interior-design": "aesthetic planning and styling of indoor spaces",
  "home-decor-retail": "stores offering decorative products for living spaces",
  "smart-home-installers": "services setting up connected home tech",
  "mutual-fund-distributor": "registered agents offering mutual-fund plans",
  "textile-mill": "industrial-scale fabric production facilities",
  "packaging-plants": "factories that design and manufacture product packaging",
  "farm-to-table-brand": "brands offering fresh produce direct from farms",
  "crop-analytics-platform": "data tools optimizing agricultural yield and health",
  "ev-infrastructure": "providers building EV charging and maintenance networks",
  "power-distribution": "utilities managing electricity delivery to end-users",
  "smart-metering": "tech-enabled utilities for real-time usage tracking",
  "performance-ads": "targeted digital ads optimized for ROI metrics",
  "short-form-reels": "snackable, vertical video content for social platforms",
  "3-d-animation": "digitally animated scenes and characters in 3D",
  "blog-articles": "written content for online publications and blogs",
  "technical-writing": "clear documentation of complex products or systems",
  "ghostwriting": "behind-the-scenes writing for others under their name",
  "product-photography": "images showcasing products in compelling detail",
  "lifestyle-shoots": "staged photo shoots reflecting daily living aesthetics",
  "event-coverage": "visual documentation of public or private events",
  "stock-photo-sets": "collections of images licensed for reuse",
  "market-research": "gathering and analyzing industry and consumer data",
  "multilingual-copy": "content translated and localized across languages",
  "app-localization": "adapting software UI for different regions or languages",
  "voiceover-dubbing": "audio narration in sync with original video content",
  "cultural-adaptation": "content tailored for cultural norms and values",
  "cro-audits": "conversion rate audits to boost user actions",
  "crm-upkeep": "maintenance of customer relationship management systems",
  "invoicing-bookkeeping": "tracking payments and managing business finances",
  "customer-support": "handling user queries and issue resolution",
  "lead-prospecting": "identifying potential clients or buyers",
  "tax-advisory": "guidance on minimizing and managing taxes",
  "fundraising-support": "help with sourcing and pitching to investors",
  "compliance-filings": "ensuring legal submissions and regulatory documents",
  "m-a-due-diligence": "vetting companies during mergers or acquisitions",
  "recruitment-process-outsourcing": "external management of hiring workflows",
  "employer-branding": "promoting a company as a great place to work",
  "payroll-management": "handling salaries, benefits, and deductions",
  "l-d-programs": "learning and development plans for employees",
  "staff-augmentation": "temporary staffing for short-term capacity boosts",
  "customer-journey-mapping": "visualizing and optimizing user experiences",
  "nps-surveys": "Net Promoter Score surveys to measure satisfaction",
  "feature-prioritization": "ranking product features based on impact and demand",
  "sound-design": "creation of audio effects and ambiance for media",
  "vr-training-sims": "immersive VR tools for real-world skill training",
  "3d-asset-creation": "designing 3D objects for games or simulations",
  "metaverse-events": "virtual gatherings in digital environments",
  "virtual-showrooms": "interactive online product displays or walkthroughs",
  "mobile-apps": "development of mobile applications for iOS and Android",
  "yoga-meditation": "guided yoga flows and meditation techniques",
  "stock-picks": "curated recommendations for individual stocks",
  "coaching-center": "institutes offering academic or skill-based coaching",
};

const cardTypeMap: Record<string, string> = {
  Quote:
    "an inspirational quote that needs an uplifting yet unobtrusive backdrop",
  Fact:
    "a data-driven fact or statistic that demands a credible, authority-reinforcing backdrop",
  Tip: "an actionable tip that benefits from an energetic, motivating backdrop",
};

const visualStyleMap: Record<string, string> = {
  "photo":
    "a realistic photographic scene with natural lighting and shallow depth of field",
  "illustration": "clean digital illustration with vector shapes and clear outlines",
  "soft-gradient": "a smooth, multi-tone gradient with gentle color transitions",
  "grainy-film": "an analog film aesthetic with muted colors and visible grain",
  "3-d-render": "a crisp 3-D render with dramatic lighting and tangible depth",
  "memphis-pattern":
    "a playful Memphis-style pattern of geometric shapes and contrasting colors",
};

const moodToneMap: Record<string, string> = {
  "friendly-pastel": "soft pastel hues that feel approachable, calm, and optimistic",
  "bold-neon": "high-contrast neon colors that scream energy and modernity",
  "formal-minimal": "neutral, desaturated palette that conveys elegance and restraint",
  "high-energy-comic": "vibrant comic-book tones with dynamic halftone textures",
  "vintage-warm": "muted, warm colors that evoke nostalgia and retro charm",
  "dark-moody": "deep shadows and rich blacks for a dramatic, cinematic vibe",
};

const textureIntensityMap: Record<number, string> = {
  0: "glass-smooth surface with absolutely no visible texture",
  1: "barely perceptible texture-almost flat but not clinically sterile",
  2: "light texture that adds gentle tactility without distraction",
  3: "moderate texture-clearly visible brush or paper grain",
  4: "heavy texture with pronounced ridges, scratches, or fabric weave",
  5: "maximum, almost tactile roughness that dominates the surface",
};

const detailPlacementMap: Record<string, string> = {
  "center-focus":
    "placing the main visual interest dead-center while keeping edges soft",
  "edge-detail":
    "confining decorative elements to the borders, leaving the center clean",
  "uniform-blur":
    "applying an even soft blur so no zone visually competes with text",
};

const noiseGrainMap: Record<number, string> = {
  0: "crystal-clear image with zero grain",
  1: "barely-there grain, only visible at extreme zoom",
  2: "light grain with a touch of analog charm",
  3: "moderate grain that adds retro character",
  4: "strong grain with a bold film-like texture",
  5: "intense, gritty grain for a raw vintage look"
};

const safeZoneMap: Record<number, string> = {
  1: "a small safe zone (1–2 short lines of text) in the center",
  2: "balanced safe zone for medium quotes or single stats",
  3: "large quiet zone suitable for multiline tips or bullet lists",
};

// Optional distributed KV (Upstash). If env isn’t configured, we fall back gracefully.
let redis: ReturnType<typeof createRedisKV> | null = null;
try { redis = createRedisKV({ namespace: "bg" }); } catch { /* no-op */ }

// Same exact function signatures & names you already use
function phrase<T extends string | number>(
  map: Record<string, string> | Record<number, string>,
  key: T,
  label: string,
) {
  const k = key.toString();
  if (!(k in map)) throw new Error(`Invalid ${label}: ${key}`);
  return (map as any)[k] as string;
}

async function sha256(text: string) {
  const buf = new TextEncoder().encode(text);
  const hash = await crypto.subtle.digest("SHA-256", buf);
  return Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function b64ToUint8(b64: string) {
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function buildPrompt(params: Record<string, unknown>): string {
  const {
    main_prompt,
    card_type,
    visual_style,
    mood_tone,
    texture_intensity,
    detail_placement,
    noise_grain,
    safe_zone_pct,
    persona,
    category,
    subcategory,
    brand_palette_override,
    brand_primary,
    brand_secondary,
    brand_accent,
    brand_background,
    keyword_assist,
    negative_elements,
    aspect_ratio,
  } = params as Record<string, unknown>;

  const safeZonePhrase = phrase(safeZoneMap, safe_zone_pct as number, "safe_zone");
  const visualStylePhrase = phrase(visualStyleMap, visual_style as string, "visual_style");
  const moodTonePhrase = phrase(moodToneMap, mood_tone as string, "mood_tone");
  const cardTypePhrase = phrase(cardTypeMap, card_type as string, "card_type");
  const texturePhrase = phrase(textureIntensityMap, texture_intensity as number, "texture_intensity");
  const detailPhrase = phrase(detailPlacementMap, detail_placement as string, "detail_placement");
  const grainPhrase = phrase(noiseGrainMap, noise_grain as number, "noise_grain");
  const personaPhrase = phrase(personaMap, persona as string, "persona");
  const categoryPhrase = phrase(categoryMap, category as string, "category");
  const subcategoryPhrase = phrase(subcategoryMap, subcategory as string, "subcategory");

  const negativeStr = (negative_elements as string[] | undefined)?.join(", ") || "";

  const brandText = brand_palette_override
    ? `Blend brand hues Primary: ${brand_primary}, Secondary: ${brand_secondary}, Accent: ${brand_accent} across Background: ${brand_background}. `
    : "";

  const keywordText = keyword_assist
    ? `Subtly weave the motif “${keyword_assist}” without stealing focus. `
    : "";

  let promptCore: string;
  switch (card_type) {
    case "Quote":
      promptCore =
        `Focus the scene on: "${main_prompt}"` +
        `Create ${safeZonePhrase} over ${visualStylePhrase}, colored in ${moodTonePhrase}, designed for ${cardTypePhrase}. ` +
        `Apply ${detailPhrase}, with ${texturePhrase}-grain level ${grainPhrase}. ` +
        `Audience context: ${personaPhrase} working in ${categoryPhrase} / ${subcategoryPhrase}. `;
      break;

    case "Fact":
      promptCore =
        `Focus the scene on: "${main_prompt}"` +
        `Design ${safeZonePhrase} that reinforces credibility for ${cardTypePhrase}, built on ${visualStylePhrase} with ${moodTonePhrase} undertones. ` +
        `Maintain ${detailPhrase}; surface shows ${texturePhrase}, featuring ${grainPhrase} for subtle retro feel. ` +
        `Target viewer: ${personaPhrase} inside ${categoryPhrase} / ${subcategoryPhrase} sector. `;
      break;

    case "Tip":
      promptCore =
        `Focus the scene on: "${main_prompt}"` +
        `Craft ${safeZonePhrase} with momentum, ideal for ${cardTypePhrase}. ` +
        `Scene style: ${visualStylePhrase}, energised by ${moodTonePhrase} palette. ` +
        `Use ${detailPhrase} on a surface bearing ${texturePhrase}; overlay ${grainPhrase} to amplify dynamism. ` +
        `Tailor to ${personaPhrase} in the field of ${categoryPhrase} / ${subcategoryPhrase}. `;
      break;

    default:
      throw new Error(`Unsupported card_type: ${card_type}`);
  }

  const prompt =
    promptCore +
    brandText +
    keywordText +
    `No printed words, no watermarks, ${negativeStr}. --ar ${aspect_ratio}`;

  return prompt.trim().replace(/\s+/g, " ");
}

// Same-instance singleflight to stop duplicate generations on this worker
const inflight = new Map<string, Promise<Response>>();

// Serve with wrapper for timing/etag support (doesn’t change your payloads)
serve(
  wrapEdgeHandler(async (req) => {
    // Keep your OPTIONS path and CORS exactly as-is
    if (req.method === "OPTIONS") {
      return new Response("ok", { headers: corsHeaders });
    }

    // Idempotency around the whole op (short TTL) to avoid rework on retries
    return await ensureIdempotency(
      req,
      async () => {
        try {
          // Safer, capped JSON read (prevents large-body DoS)
          const body = (await readJsonSafe<Record<string, unknown>>(req, 64 * 1024)) as Record<string, unknown>;

          const jwt  = req.headers.get('Authorization')?.replace('Bearer ', '');
          const uid  = jwt ? (await supabase.auth.getUser(jwt)).data.user?.id : null;

          const required = [
            "main_prompt", "card_type", "visual_style", "mood_tone",
            "texture_intensity", "detail_placement", "noise_grain",
            "safe_zone_pct", "persona", "category", "subcategory",
            "aspect_ratio",
          ];
          for (const f of required) {
            if (!(f in body)) {
              return new Response(`Missing field: ${f}`, { status: 400, headers: corsHeaders });
            }
          }

          const prompt = buildPrompt(body);
          const promptHash = await sha256(prompt);
          const category = body.category as string;
          const aspectRatio = body.aspect_ratio as string;

          // Quick DB cache hit
          {
            const { data: cachedRow } = await supabase
              .from("prebuilt_backgrounds")
              .select("*")
              .eq("prompt_hash", promptHash)
              .single();

            if (cachedRow) {
              const { data: signed } = await supabase.storage
                .from("backgrounds")
                .createSignedUrl(cachedRow.path, 60 * 60);

              return new Response(JSON.stringify({ cached: true, url: signed.signedUrl }), { headers: corsHeaders });
            }
          }

          const lockKey = `gen:${promptHash}`;
          const doneKey = `done:${promptHash}`;

          // If we can't get the distributed lock, wait briefly for the other worker to finish
          let haveLock = false;
          try { haveLock = !!(await redis?.acquireLock?.(lockKey, 15)); } catch { /* no-op */ }

          if (!haveLock) {
            // Same-instance singleflight: coalesce concurrent calls on this worker
            if (inflight.has(promptHash)) return await inflight.get(promptHash)!;

            // No lock; poll fast path for a short window to see if another worker wrote the row
            const waitUntil = Date.now() + 12_000;
            while (Date.now() < waitUntil) {
              // First, check Redis "done" hint for path (cheap)
              try {
                const r = await redis?.get<{ path: string }>(doneKey);
                if (r?.value?.path) {
                  const { data: signed } = await supabase.storage
                    .from("backgrounds")
                    .createSignedUrl(r.value.path, 60 * 60);
                  return new Response(JSON.stringify({ cached: true, url: signed.signedUrl }), { headers: corsHeaders });
                }
              } catch { /* ignore */ }

              // Then, check DB once in a while
              const { data: row } = await supabase
                .from("prebuilt_backgrounds")
                .select("*")
                .eq("prompt_hash", promptHash)
                .maybeSingle();

              if (row?.path) {
                const { data: signed } = await supabase.storage
                  .from("backgrounds")
                  .createSignedUrl(row.path, 60 * 60);
                return new Response(JSON.stringify({ cached: true, url: signed.signedUrl }), { headers: corsHeaders });
              }

              await new Promise(r => setTimeout(r, 200));
            }
            // Fallback: continue without lock (we still have DB unique+ignoreDuplicates)
          }

          // Leader path (or fallback if no lock available)
          const p = (async (): Promise<Response> => {
            // OpenAI generate
            const res = await openai.images.generate({
              model: "gpt-image-1",
              prompt,
              n: 1,
              size: "1024x1024",
              quality: "low",
              background: "opaque",
            });

            if (!res || !Array.isArray(res.data) || !res.data[0]?.b64_json) {
              return new Response("Image generation failed", { status: 500, headers: corsHeaders });
            }
            const b64_json = res.data[0].b64_json;
            if (!b64_json) {
              return new Response("OpenAI returned no image", { status: 502, headers: corsHeaders });
            }

            // Upload to storage
            const filename = crypto.randomUUID() + ".png";
            const path = `${category}/${filename}`;
            const bytes = b64ToUint8(b64_json);

            const { error: upErr } = await supabase.storage
              .from("backgrounds")
              .upload(path, bytes, { contentType: "image/png" });

            if (upErr) {
              console.error("Upload error:", upErr);
              return new Response("Upload failed", { status: 500, headers: corsHeaders });
            }

            console.log('before inset');

            // aspect ratio parsing (defensive)
            const [w, h] = String(aspectRatio).split(':').map((n) => Number(n));
            const ar = (Number.isFinite(w) && Number.isFinite(h) && h !== 0) ? +(w / h).toFixed(4) : 1.0000;

            // Insert metadata (ignore duplicates)
            const { data: row, error: insErr } = await supabase
              .from('prebuilt_backgrounds')
              .insert([{
                category,
                path,
                aspect_ratio: ar,
                prompt,
                prompt_hash: promptHash,
                source_model: 'gpt-image-1',
                creator_id: uid
              }], { ignoreDuplicates: true })
              .select()
              .maybeSingle();

            if (insErr) {
              console.error('PostgrestError →',
                insErr.message, { code: insErr.code, details: insErr.details, hint: insErr.hint });
              // Even if insert failed (e.g., duplicate race), try to fetch the existing row
              const { data: existing } = await supabase
                .from('prebuilt_backgrounds')
                .select('*')
                .eq('prompt_hash', promptHash)
                .maybeSingle();

              const finalPath = existing?.path ?? path;

              // Hint followers via Redis
              try { await redis?.set?.(doneKey, { path: finalPath }, 300); } catch { /* no-op */ }

              const { data: signed2 } = await supabase.storage
                .from("backgrounds")
                .createSignedUrl(finalPath, 60 * 60);

              return new Response(JSON.stringify({ cached: false, url: signed2.signedUrl, row: existing ?? null }), { headers: corsHeaders });
            }

            console.log('after inset');

            // Hint followers via Redis that generation is done for this prompt
            try { await redis?.set?.(doneKey, { path }, 300); } catch { /* no-op */ }

            const { data: signed } = await supabase.storage
              .from("backgrounds")
              .createSignedUrl(path, 60 * 60);

            return new Response(JSON.stringify({ cached: false, url: signed.signedUrl, row }), { headers: corsHeaders });
          })();

          // Track same-instance flight to coalesce
          inflight.set(promptHash, p);
          try {
            const out = await p;
            return out;
          } finally {
            inflight.delete(promptHash);
            try { if (haveLock) await redis?.releaseLock?.(lockKey); } catch { /* no-op */ }
          }
        } catch (err) {
          console.error("generate-insight-cards-background error:", err);
          return new Response("Internal error", { status: 500, headers: corsHeaders });
        }
      },
      // Idempotency: short-lived to avoid stale signed URLs; mode=Replay keeps same payload
      { ttlSec: 300, mode: "replay", kv: redis ?? undefined },
    );
  })
);

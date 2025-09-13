// generate-caption.ts
import { serve } from "std/http/server.ts";
import OpenAI from "https://deno.land/x/openai@v4.69.0/mod.ts";
import {
  wrapEdgeHandler2, readJsonSafe, json, ensureIdempotency,
  aiCachedCall, defaultConfig, withHeader
} from "../_shared/edge-core.ts";
import { createRedisKV } from "../_shared/kv_redis.ts";

// ---- CORS ----
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, idempotency-key",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Max-Age": "86400",
  Vary: "Origin",
};

// ---- OpenAI ----
const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
if (!OPENAI_API_KEY) throw new Error("OPENAI_API_KEY environment variable is required");
const openai = new OpenAI({ apiKey: OPENAI_API_KEY, maxRetries: 2, timeout: 10_000 });

const HAS_UPSTASH =
  !!Deno.env.get("UPSTASH_REDIS_REST_URL") && !!Deno.env.get("UPSTASH_REDIS_REST_TOKEN");

let redis: ReturnType<typeof createRedisKV> | undefined = undefined;
if (HAS_UPSTASH) {
  redis = createRedisKV({ namespace: "blob" });
} else {
  // Dev-friendly: logs once and continues with in-memory cache (fast but not cross-instance)
  console.warn("[cache] UPSTASH env not found — using in-memory cache (dev only).");
}

// ---- Types (same as your original) ----
type Profile = {
  persona: string; subcategory: string; brand_name: string; category: string;
  primary_goal: string; voice_tags: string[];
};
type RequestBody = {
  prompt?: string; tone: string; platform: string; length: string; profile: Profile;
  generate_from_news?: boolean; news_age_window?: string;
  allow_emojis: boolean; allow_hashtags: boolean;
};

// ---- Your helpers (semantics preserved) ----
function getLengthConstraints(length: string) {
  switch (length) {
    case "Short": return { charLimit: 50, minChar: 0, maxTokens: 80 };
    case "Medium": return { charLimit: 200, minChar: 0, maxTokens: 300 };
    case "Long": return { charLimit: null, minChar: 500, maxTokens: 1000 };
    default: return { charLimit: null, minChar: 0, maxTokens: 500 };
  }
}
function getToneInstructions(tone: string) {
  switch (tone) {
    case "Professional": return "Write in a formal, precise, business-oriented tone. No slang, no humor.";
    case "Casual": return "Write in a friendly, relaxed, modern tone. Light humor allowed.";
    case "Playful": return "Write in a fun, witty, energetic tone. Use playful language.";
    default: return "Use a neutral tone.";
  }
}

export const personaPrompts = { 
  "Solo Creator":
    "You are writing as an independent creator building a personal brand. Prioritize authenticity, first-person voice, and story-driven hooks that feel like a friendly DM. Use conversational phrasing, light emojis where natural, and end with a simple question or call-to-action to spark comments. Every line should feel spontaneous yet purposeful, mirroring the creator’s unique vibe while aligning to the supplied brand_profile. Write in a first-person, casual, human voice. Sound like a creator sharing their story - honest, fun, or emotional. Avoid formal structure.",

  "SMB Founder":
    "You are writing on behalf of a founder-led small business. Emphasize expertise, reliability, and tangible value for customers. Anchor the copy in real outcomes (time saved, revenue gained, lifestyle improved) and weave in subtle social proof. Maintain a confident but approachable tone, and close with a results-oriented CTA that nudges readers toward the next step (demo, inquiry, website visit), all while matching the brand_profile voice cues. Write in a professional, confident tone. Use third-person brand perspective or founder voice. Be clear, outcome-driven, and polished.",

  "Agency / Freelancer":
    "You are writing for a creative service provider speaking to potential clients. Showcase strategic insight and past wins without jargon overload. Balance professional polish with friendly approachability, highlighting how the agency/freelancer partners with brands to achieve measurable growth. Finish with a CTA inviting discovery calls or proposal requests. Ensure voice, terminology, and examples stay consistent with the brand_profile. Adjust your tone based on the prompt. Be flexible - smart, fun, or sharp depending on the input."
};

export const subCategoryPrompts = {
  "Skits":
    "Craft a high-energy short-form comedic scenario with clear setup, punchline, and unexpected twist. Keep pacing snappy and dialogue relatable to Gen-Z & Millennial audiences. Finish with a playful CTA prompting viewers to recreate or duet the skit.",

  "Relatable Humor":
    "Write a caption that mirrors everyday struggles in a meme-like, self-deprecating tone. Use rhetorical questions and hyper-specific details that make readers say “literally me.” End with a wink emoji and a prompt to share their own story.",

  "Satire & Parody":
    "Compose a sharp, tongue-in-cheek take that exaggerates common industry tropes. Maintain clear comedic intent, avoiding real brand defamation. Include one over-the-top metaphor and close with a lighthearted disclaimer.",

  "Memes":
    "Deliver a caption that sets up a recognizable meme template in text form. Lean on cultural references no older than three months, keep lines short and punchy, and finish with a call for best caption replies.",

  "Reaction Videos":
    "Write an intro hook that tees up a genuine on-camera reaction. Convey anticipation, highlight the trigger content, and sprinkle emoji for emotional beats. Conclude with a CTA inviting followers to tag a friend who needs to see the reaction.",

  "Product Reviews":
    "Generate an unbiased yet enthusiastic review opener. Start with a problem statement, segue to key product benefits, and include one tangible stat or spec. Close with a verdict phrase (⭐️ rating) and a CTA to share personal experiences.",

  "Tutorials":
    "Structure a step-by-step mini-guide: Problem ➝ Supplies ➝ Steps ➝ Pro-Tip. Keep sentences concise and actionable. Insert a numbered list for clarity and finish with an invitation to drop questions in comments.",

  "Coding & Dev Logs":
    "Write in first-person, highlighting today’s coding challenge, the approach, and a key takeaway. Include one code-snippet inline (≤15 words). End with a CTA to fork/clone or share debugging tips.",

  "AI Tool Demos":
    "Explain how an AI tool solves a niche pain-point. Use a before-vs-after snapshot description, mention model or feature names, and quantify time or money saved. Close with a question about the viewer’s favorite AI shortcut.",

  "Hardware Unboxings":
    "Paint a sensory picture of unboxing: textures, sounds, first impressions. Call out standout spec or accessory, and tease a follow-up performance test. End with a poll CTA on what to test first.",

  "Study Tips":
    "Offer three evidence-based study hacks anchored in research (Pomodoro, spaced repetition, active recall). Keep language encouraging and student-friendly. Close with a motivational quote and CTA to bookmark.",

  "Animated Explainers":
    "Introduce the core concept in one crisp sentence, outline the animation flow (problem ➝ visualization ➝ solution), and emphasize clarity and color-coded cues. Conclude with a reminder to watch till the last frame for a hidden gem.",

  "Language Learning":
    "Share a micro-lesson: phrase of the day, pronunciation guide, usage example. Embed phonetic spelling and a relatable scenario. Finish with a CTA to comment in the target language.",

  "Science Experiments":
    "Set up a safe, home-friendly experiment with materials list, hypothesis, quick steps, and expected outcome. Insert a safety emoji ⚠️, and wrap with a question inviting hypothesis guesses.",

  "History Storytelling":
    "Open with an intrigue hook (“On this day in…”). Narrate the event in three vivid sentences, include an unexpected fact, and connect relevance to today. End with a prompt to share other little-known events.",

  "Daily Routines":
    "Break down a realistic day schedule using timestamps. Highlight one productivity hack and one self-care moment. Keep tone authentic, not braggy. Finish with a CTA asking for must-try routine tweaks.",

  "Minimalism":
    "Advocate for simplicity: describe one declutter win, quantify space/time saved, suggest a 5-minute task for followers. Use calm, spacious language and end with a minimalist emoji and reflective question.",

  "Home Makeovers":
    "Describe a room ‘before’ pain-point, the makeover concept, and a wow-factor detail (accent wall, smart lighting). Inject one cost-saving tip. Close inviting followers to rate the transformation 1-10.",

  "College Life":
    "Share a candid snapshot of campus life: lecture hacks, dorm meal, or club story. Keep tone humorous yet sincere. End with a CTA for fellow students to drop their relatable moment.",

  "Day-in-the-Life":
    "Provide a chronological log (6 AM → 10 PM) with micro-insights and emoji timestamps. Balance work and leisure scenes. Close with a prompt asking viewers about their busiest hour.",

  "Let’s Plays":
    "Kick off with game title and difficulty setting. Tease a pivotal challenge or boss fight and note player reaction style. Finish with a CTA to suggest next game or mod.",

  "Esports Commentary":
    "Break down a key match highlight in analyst tone: player move, tactical decision, impact. Add timestamp reference and one stat. End by asking predictions for the finals.",

  "Speedruns":
    "Announce category, target record, and biggest skip/glitch strategy. Maintain hype, include personal best time, and ask viewers for optimization tips.",

  "Game Reviews":
    "Deliver a concise verdict structure: Story ★, Gameplay ★, Graphics ★, Replay Value ★. Support each with one example. Finish with purchase recommendation score.",

  "Stream Highlights":
    "Summarize the clip context, quote a funny or clutch line, and tease link in bio. Close urging fans to clip favorite moments with a branded hashtag.",

  "Makeup Tutorials":
    "Lay out product line-up, step order, and finish look name. Include one texture or finish descriptor (dewy, matte). End with shade recommendations for different skin tones.",

  "Outfit Lookbooks":
    "Describe three outfits: vibe, key piece, occasion. Use vivid fabric adjectives. Conclude with a poll on favorite fit number.",

  "Styling Hacks":
    "Share one underrated wardrobe trick (e.g., belt layering) with a 3-step explanation and emoji arrows. Encourage viewers to try and tag brand.",

  "Product Hauls":
    "Reveal store or brand, total items, and biggest steal deal. List top three finds with price drops. End with CTA to vote best purchase.",

  "DIY Skincare":
    "Present a safe, dermatologist-backed recipe, list ingredients with measurements, and detail application timing. Include allergy disclaimer and CTA for patch-test feedback.",

  "Home Workouts":
    "Design a no-equipment circuit: exercise list, reps, sets, rest. Insert form tip. End challenging viewers to complete in under 15 min.",

  "Yoga & Meditation":
    "Guide through a themed flow (stress relief, flexibility). Mention breath count cues and pose names in Sanskrit. Close inviting users to share post-practice feeling emoji.",

  "Healthy Recipes":
    "Share macro-friendly meal: ingredient list, cook time, calorie count. Use quick step verbs and finish with storing tip.",

  "Transformation Journeys":
    "Frame a before-after timeline, stats (weight, reps, mood), and one mindset shift. Keep tone inspiring, not shaming. End with CTA for uplifting comments.",

  "Mental-Health Chats":
    "Open vulnerably with personal insight, deliver one practical coping tool, cite a credible source, and sign off with a supportive resources link.",

  "Mutual-Fund Deep-Dives":
    "Break down fund objective, sector allocation, historical CAGR, and fee structure. Use plain English, not financial jargon. Include risk disclaimer and CTA to DYOR.",

  "Stock Picks":
    "Present a clear thesis: company, catalyst, valuation metric. Provide one chart insight. End with question inviting bull/bear takes.",

  "Crypto Breakdowns":
    "Explain project utility, tokenomics, and roadmap in layman terms. Note volatility caution. Close with CTA on community sentiment.",

  "Budgeting Tips":
    "Offer a 50-30-20 style framework tweak, include a sample monthly table, and a motivational quote. Prompt users to share biggest expense leak.",

  "Side-Hustle Ideas":
    "Introduce one realistic gig, startup cost, earnings range, and first-week action plan. End with a challenge to start today.",

  "Backpacking Guides":
    "Outline route, daily budget, must-see spot, and packing essential. Use bullet points. Finish with CTA for secret local tips.",

  "City Walkthroughs":
    "Paint a walking itinerary: landmark ➝ cafe ➝ hidden alley. Include transit tip and estimated steps. End with CTA to save the map.",

  "Food Tours":
    "Curate a 5-stop tasting path, dish highlight at each, and total cost. Add sensory adjective for each bite. End with rating slider.",

  "Cultural Immersion":
    "Describe an authentic local experience (festival, craft). Provide etiquette note and phrase in native language. Finish with CTA encouraging cultural respect.",

  "Travel Hacks":
    "Share one lesser-known booking trick or gear hack. Include quantitative benefit (hours saved, % off). Old-school pro tip, modern spin. End with wink emoji.",

  "Original Songs":
    "Introduce genre, theme, and songwriting spark. Highlight chorus hook in quotes. Close with CTA to stream full track.",

  "Cover Sessions":
    "Reveal original artist, unique twist (tempo, genre switch). Credit composer and invite mash-up suggestions.",

  "Live Looping":
    "Explain loop layers (beatbox, chords, lead), BPM, and gear used. Close with CTA to request loop challenges.",

  "Instrument Tutorials":
    "Teach a riff in tab or fret numbers, tempo, and finger positions. Add practice tip and invite duet tags.",

  "Beat Making":
    "Detail DAW, BPM, sample source, and key plugin trick. Include 2-bar text pattern. CTA for remix challenge.",

  "Quick Recipes":
    "Deliver a ≤15-min meal: prep step list, cook method, plate suggestion. Include calorie badge and CTA to save reel.",

  "Street-Food Reviews":
    "Describe stall vibe, signature dish, price, hygiene note. Rate on taste/texture scale. CTA to tag next stall recommendation.",

  "Meal Prep":
    "Provide 3-day bulk recipe set, storage method, reheat tip. List macros per portion. CTA to screenshot menu.",

  "ASMR Cooking":
    "Write sensory-rich onomatopoeia, crisp formatting, minimal words. Prompt viewers to wear headphones. CTA for volume preference.",

  "International Cuisine":
    "Highlight dish origin story, key spice, authenticity tip. Include pronunciation guide. CTA for regional recipes.",

  "Digital Drawing":
    "Outline concept sketch, brush set, color palette (hex). Mention time-lapse length. CTA for PSD download request.",

  "Crafts & Hacks":
    "Present inexpensive DIY project, supply list, assembly steps, safety note. CTA to post finished pic.",

  "3D Printing":
    "Describe model idea, filament type, layer height, print time. Include one troubleshooting hint. CTA for STL link.",

  "Resin Art":
    "Explain mold shape, pigment mix ratios, cure time, demold reveal. Safety gloves reminder. CTA for color combo ideas.",

  "Upcycling Projects":
    "Introduce discarded item, transformation plan, eco-impact stat. Step summary. CTA for before-after photos.",

  "Study-With-Me":
    "Set ambience (lo-fi, timer), session length, goal line. Encourage followers to join live pomodoro and comment results.",

  "Productivity Systems":
    "Share framework (GT-D, PARA, etc.), tool stack, and weekly review ritual. CTA to download template.",

  "Book Summaries":
    "Present book title, author, 3 sentence key insights, and actionable takeaway. CTA for next book vote.",

  "Goal-Setting":
    "Teach SMART breakdown, example goal, and milestone tracking method. Motivational sign-off with rocket emoji.",

  "Mindfulness":
    "Guide a 60-second breathing exercise: inhale/exhale counts, visualization cue. CTA for journaling reflection.",

  "Retail Boutique":
    "Spotlight latest arrival, material detail, limited stock urgency. CTA to shop link in bio.",

  "Wholesale Supplier":
    "Announce MOQ, bulk pricing tier, lead time, and logistic support. CTA for RFQ link.",

  "D2C E-commerce":
    "Highlight hero product USP, customer testimonial snippet, free shipping threshold. CTA to swipe-up.",

  "Custom Tailoring":
    "Describe bespoke process, fabric swatch, measurement guarantee. CTA to book fitting.",

  "Sustainable Fashion":
    "Share eco-material fact, supply chain transparency, carbon offset stat. CTA to join green initiative.",

  "Restaurant":
    "Tease chef special, ingredient origin, plating style, limited-time availability. CTA to reserve table.",

  "Cafe / Coffee Bar":
    "Introduce seasonal drink, flavor notes, latte-art visual. CTA with pre-order link.",

  "Bakery & Desserts":
    "Showcase fresh-baked item aroma description, sweetness level, order cutoff. CTA to set aside slice.",

  "Cloud Kitchen":
    "Promote new menu launch, delivery radius, packaging eco-friendly note. CTA with discount code.",

  "Packaged FMCG":
    "Emphasize convenience benefit, nutrition key point, shelf life. CTA to find in local store aisle.",

  "Gym / Fitness Studio":
    "Advertise class type, trainer credential, membership promo. CTA for free trial pass.",

  "Yoga Center":
    "Highlight class schedule, ambiance, community vibe. CTA to book first session.",

  "Nutraceutical Brand":
    "Detail active ingredient, clinical claim, dosage guide. CTA for subscription deal.",

  "Spa & Wellness":
    "Describe treatment sensory journey, therapist expertise, intro offer. CTA to call for slot.",

  "Telehealth Clinic":
    "Ensure HIPAA-compliant reassurance, specialist availability, appointment flow. CTA to secure virtual consult.",

  "B2B SaaS":
    "Identify pain-point metric (hours, dollars), feature highlight, ROI case snippet. CTA to book demo.",

  "Mobile-App Startup":
    "Present core feature, user testimonial quote, app store rating. CTA to download.",

  "IT Services":
    "List service stack, SLA uptime, recent client win. CTA to schedule discovery call.",

  "Cybersecurity":
    "State threat statistic, solution module, compliance standard met. CTA for security audit.",

  "AI Solutions":
    "Outline model capability, deployment timeline, cost-saving stat. CTA to request POC access.",

  "Legal Firm":
    "Highlight specialization, success rate, free consult offer. CTA to book slot.",

  "Accounting Practice":
    "Mention tax season deadline, automation tool, error-free guarantee. CTA for bookkeeping package.",

  "Consulting Agency":
    "Reference industry benchmark gap, proprietary framework, client uplift %. CTA for strategy session.",

  "Architecture Studio":
    "Describe design philosophy, signature project, sustainability rating. CTA to view portfolio.",

  "HR Outsourcing":
    "Note compliance coverage, onboarding speed, cost per hire saving. CTA for talent audit.",

  "Residential Brokerage":
    "Showcase featured listing, neighborhood stat, virtual tour link. CTA to schedule viewing.",

  "Commercial Leasing":
    "Highlight floor plate flexibility, lease term, foot traffic data. CTA to download brochure.",

  "Property Management":
    "Present occupancy rate boost %, digital tenant portal feature, maintenance SLA. CTA for proposal.",

  "Co-Working Spaces":
    "Promote amenities, flexible membership tiers, community event snippet. CTA for free day pass.",

  "Vacation Rentals":
    "Paint immersive stay scene, nearby attraction, early-bird discount. CTA to check dates.",

  "Dealership":
    "Spotlight new model, horsepower stat, limited financing offer. CTA to book test drive.",

  "Auto-Repair Shop":
    "Mention diagnostic tech, warranty, same-day turnaround claim. CTA to schedule service.",

  "EV-Charging Network":
    "State charger count, fast-charge kW rating, app feature. CTA to download map.",

  "Car Rental":
    "Advertise fleet category, daily rate, loyalty perk. CTA to reserve now.",

  "Auto-Parts E-commerce":
    "List top OEM part, compatibility chart, shipping ETA. CTA for fit-ment tool.",

  "Coaching Center":
    "Highlight success rate %, curriculum outline, scholarship info. CTA for mock test slot.",

  "EdTech Platform":
    "Show personalized learning path, AI progress tracking, free trial. CTA to enroll.",

  "Skill Bootcamp":
    "State job placement stat, mentor ratio, project showcase. CTA for cohort waitlist.",

  "Corporate Training":
    "Detail competency framework, LMS integration, accreditation. CTA for pilot workshop.",

  "Test-Prep Institute":
    "Mention average score improvement, adaptive practice, guaranteed refund. CTA for diagnostic test.",

  "Production House":
    "Show reel highlight, turnaround time, multi-format capability. CTA for script brief.",

  "Printing & Branding":
    "Present print tech (UV, foil), MOQ, design support. CTA for quote.",

  "Event Management":
    "Describe past flagship event, 360-service list, vendor network size. CTA to book consultation.",

  "Advertising Studio":
    "Pitch creative concept, KPI forecast, cross-channel expertise. CTA to request proposal.",

  "Influencer Merch":
    "Highlight limited drop, fabric quality, supporter badge. CTA to cop before sell-out.",

  "Furniture Manufacturing":
    "Showcase hero piece, material sourcing, lead time. CTA to request catalog.",

  "Interior Design":
    "Tease mood board vibe, ROI on resale value, signature style. CTA for free site visit.",

  "Home-Decor Retail":
    "Display new collection theme, bundle discount, free shipping threshold. CTA to shop link.",

  "Smart-Home Installers":
    "Explain integration ecosystem, voice control demo, energy savings %. CTA for home audit.",

  "Landscaping":
    "Describe seasonal package, native plant selection, maintenance schedule. CTA for quote visit.",

  "Mutual-Fund Distributor":
    "Explain SIP advantage, fund shortlist criteria, onboarding KYC ease. CTA to start SIP.",

  "NBFC / Micro-Finance":
    "Outline loan product, interest rate, eligibility doc list. CTA for instant assessment.",

  "Wealth-Advisory":
    "Present asset allocation philosophy, performance track record, fiduciary pledge. CTA for portfolio review.",

  "Payments & Wallets":
    "Highlight zero-fee transfer, cashback perk, security feature. CTA to download app.",

  "InsurTech":
    "Explain claim approval speed, customized premium, digital KYC. CTA to get quote.",

  "Third-Party Logistics (3PL)":
    "Note fulfillment SLA, multi-channel integration, cost per order stat. CTA for free logistics audit.",

  "Last-Mile Delivery":
    "Share average delivery time, live tracking link, success rate. CTA for service demo.",

  "Cold-Chain":
    "Highlight temperature range, IoT monitoring, spoilage reduction %. CTA for consultation.",

  "Warehousing":
    "Describe multi-city capacity, WMS tech, flexible lease. CTA for inventory analysis.",

  "Freight Forwarding":
    "List lane coverage, customs clearance expertise, transit time. CTA for freight quote.",

  "FMCG Manufacturing":
    "Mention production volume, ISO certification, private label option. CTA to schedule plant tour.",

  "Electronics Assembly":
    "State SMT line speed, quality ppm, NDA assurance. CTA for production slot.",

  "Textile Mill":
    "Detail fabric GSM, eco dye process, lead time. CTA for sample swatch.",

  "Precision Engineering":
    "Highlight tolerance microns, CNC fleet, aerospace certs. CTA for RFQ.",

  "Packaging Plants":
    "Showcase material options, print finish, MOQ flexibility. CTA to request dieline.",

  "Organic Farming":
    "Share soil management method, certification, yield stat. CTA for farm visit.",

  "Farm-to-Table Brand":
    "Describe harvest-to-door timeline, farmer income pledge, recipe ideas. CTA to order box.",

  "Agri-Input Supplier":
    "List fertilizer grade, bulk discount, agronomist support. CTA for soil test.",

  "Hydroponics":
    "Explain system type, crop yield %, water saving stat. CTA to book demo farm tour.",

  "Crop-Analytics Platform":
    "Present precision metric (NDVI), ROI uplift %, dashboard screenshot. CTA for free trial.",

  "Solar EPC":
    "Highlight kW installed, payback period, financing option. CTA for site survey.",

  "EV Infrastructure":
    "State charger uptime, interoperability standard, network map. CTA for partnership inquiry.",

  "Bio-Fuel Production":
    "Note feedstock source, emission reduction %, capacity tonnage. CTA for offtake agreement.",

  "Power Distribution":
    "Mention grid reliability %, smart meter penetration, outage alert feature. CTA for stakeholder call.",

  "Smart-Metering":
    "Explain data interval, demand response saving %, retrofit ease. CTA to schedule pilot.",

  "Social-Media Management":
    "Highlight multi-platform scheduling, analytics insight, case study stat. CTA for free audit.",

  "Performance Ads":
    "Share ROAS figure, funnel optimization tactic, creative A/B snapshot. CTA to book ad review.",

  "Email Marketing":
    "Detail segmentation strategy, open rate lift %, automation flow teaser. CTA for template pack.",

  "Growth Hacking":
    "Present viral loop concept, user acquisition stat, low-cost channel tip. CTA to join mastermind.",

  "Influencer Collabs":
    "List niche fit, audience overlap %, branded content example. CTA to request media kit.",

  "UI/UX Design":
    "Show design system teaser, usability score, Figma prototype gif cue. CTA for design sprint slot.",

  "Brand Identity":
    "Describe core brand archetype, color tactic, logo system. CTA to book discovery call.",

  "Motion Graphics":
    "Tease kinetic typography snippet, frame rate, software stack. CTA for storyboard review.",

  "Illustration":
    "Showcase style (flat, line-art), palette hex codes, use-case examples. CTA to commission.",

  "Presentation Design":
    "Highlight storytelling arc, slide animation hint, before-after slide. CTA for deck revamp.",

  "Web Development":
    "List tech stack, performance score, CMS handoff. CTA for code audit.",

  "Mobile Apps":
    "Mention native or cross-platform, MAU uplift case, store rating. CTA to scope app idea.",

  "Shopify & E-commerce":
    "Show conversion rate stat, theme customization, app integration. CTA to boost store.",

  "API Integrations":
    "Describe system handshake, latency benchmark, monitoring dashboard. CTA for integration roadmap.",

  "DevOps & Cloud":
    "Reference CI/CD pipeline, uptime SLA, infra cost savings %. CTA for free health check.",

  "Explainer Videos":
    "Outline storyline hook, visual style, voiceover tone. CTA to see storyboard.",

  "Short-Form Reels":
    "Focus on snappy pacing, hook in first 1 s, bold overlay text. CTA to watch full series.",

  "3D Animation":
    "State render engine, frame length, photoreal style note. CTA for animation quote.",

  "Post-Production":
    "List color grade LUT, SFX note, turnaround time. CTA to share raw footage.",

  "Livestream Production":
    "Mention multi-cam setup, bitrate, engagement overlay. CTA to book live event.",

  "Blog Articles":
    "Present outline teaser, keyword intent, CTA to read full post link in bio.",

  "Copywriting":
    "Highlight hook-story-offer flow, brand voice alignment, conversion stat. CTA to request copy audit.",

  "Technical Writing":
    "Emphasize clarity, schematic diagrams, compliance standard. CTA to view sample doc set.",

  "Scriptwriting":
    "Describe narrative arc, audience emotion target, runtime. CTA for script treatment.",

  "Ghostwriting":
    "Ensure seamless voice match, confidentiality clause, milestone timeline. CTA to book intro call.",

  "Product Photography":
    "Reference lighting setup, hero angle, resolution, e-com compliance. CTA for shot list download.",

  "Lifestyle Shoots":
    "Describe mood board, location vibe, candid approach. CTA for availability.",

  "Event Coverage":
    "List deliverables (photos, highlight reel), turnaround within 24 h, sample gallery link. CTA to reserve date.",

  "Drone Filming":
    "State legal clearance, shot altitude, cinematic maneuver. CTA for reel preview.",

  "Stock-Photo Sets":
    "Highlight niche theme, resolution, licensing terms. CTA for bundle download.",

  "Brand Positioning":
    "Define market gap, unique value promise, emotional hook. CTA for strategy workshop.",

  "GTM Strategy":
    "Outline ICP, channel mix, launch milestone, metric target. CTA for playbook review.",

  "Market Research":
    "Mention survey methodology, sample size, data viz sneak peek. CTA to get report extract.",

  "Pricing Optimization":
    "Present elasticity insight, A/B framework, margin lift %. CTA for free pricing canvas.",

  "Investor Pitch Decks":
    "Highlight traction metric, TAM slide teaser, clean dataviz. CTA to request deck polish.",

  "Multilingual Copy":
    "Note language pairs, cultural nuance assurance, proofreading layer. CTA for sample translation.",

  "Subtitle & Captioning":
    "State accuracy rate %, turnaround hours, SRT/VTT formats. CTA for test file.",

  "App Localization":
    "Highlight string-key workflow, QA process, regional date/number rules. CTA for quote.",

  "Voiceover Dubbing":
    "Specify voice range options, studio chain-of-custody, lip-sync tech. CTA for voice sample pack.",

  "Cultural Adaptation":
    "Explain local idiom swap, festival alignment, design RTL/LTR. CTA for consult call.",

  "Dashboard Building":
    "Describe KPI list, data pipelines, real-time refresh rate. CTA for demo access.",

  "CRO Audits":
    "List friction points (speed, copy, flow), uplift potential %, quick-win sample. CTA for audit slot.",

  "SEO Analytics":
    "Mention keyword rank lift %, backlink health graph, competitor gap. CTA to start 7-day trial.",

  "Attribution Modeling":
    "Explain multi-touch model type, channel weight % variance, visualization snapshot. CTA for model workshop.",

  "A/B Testing":
    "Note hypothesis, sample size calc, stat-sig threshold. CTA for test roadmap.",

  "Calendar Management":
    "Highlight smart scheduling, buffer rules, timezone auto-detect. CTA to sync calendar.",

  "CRM Upkeep":
    "Name dedupe method, pipeline stage hygiene, alert system. CTA for free data check.",

  "Invoicing & Bookkeeping":
    "References GST compliance, automation rule, dashboard snippet. CTA for migration consult.",

  "Customer Support":
    "State SLA, omnichannel coverage, CSAT score. CTA to book demo.",

  "Lead Prospecting":
    "Mention ICP filter, email sequencing tool, reply rate. CTA for 50 free leads.",

  "Fractional CFO":
    "Outline services (forecast, burn rate, board deck), SaaS metrics lift %. CTA for finance call.",

  "Tax Advisory":
    "Note current FY deadlines, compliance update, deduction tip. CTA to book consult.",

  "Fundraising Support":
    "Highlight investor network size, pitch deck refinement, term sheet advisory. CTA to schedule strategy call.",

  "Compliance Filings":
    "List annual forms, e-filing speed, penalty avoidance stat. CTA for compliance calendar.",

  "M&A Due Diligence":
    "Mention red-flag checklist, data room setup, timeline. CTA for NDA & scope.",

  "Recruitment Process Outsourcing":
    "State time-to-hire reduction %, talent pool size, ATS integration. CTA for hiring audit.",

  "Employer Branding":
    "Describe EVP framework, Glassdoor rating bump %, culture video snippet. CTA for brand audit.",

  "Payroll Management":
    "Highlight on-time %, statutory compliance, self-service portal. CTA to migrate payroll.",

  "L&D Programs":
    "Outline competency map, blended learning, certification badge. CTA for needs analysis.",

  "Staff Augmentation":
    "Note skill bench, ramp-up time, cost comparison to full-time. CTA for talent deck.",

  "User Interviews":
    "State screener profile, session length, incentive. CTA for interview calendar.",

  "Prototype Testing":
    "Mention task scenarios, heatmap output, iteration loop. CTA for prototype link.",

  "Customer Journey Mapping":
    "Describe persona, touchpoint list, emotional graph. CTA for workshop signup.",

  "NPS Surveys":
    "Note benchmark score, follow-up automation, churn flag. CTA to launch survey.",

  "Feature Prioritization":
    "Present RICE score breakdown, roadmap snapshot, dev capacity fit. CTA for prioritization canvas.",

  "Podcast Editing":
    "List noise reduction db, cut rate %, intro/outro stinger. CTA for sample reel.",

  "Jingle Composition":
    "Mention genre, brand mood, length, instrumentation. CTA for demo track.",

  "Sound Design":
    "Describe atmosphere cue, foley layer, mastering standard. CTA for sound pack.",

  "Voice-acting":
    "Specify character archetype, accent, emotion range. CTA to hear voice reel.",

  "Audiobook Production":
    "State runtime hrs, narrator style, chapter QC. CTA for sample chapter.",

  "AR Filters":
    "Highlight face tracking, interactive element, brand color. CTA to preview lens.",

  "VR Training Sims":
    "Describe skill objective, scenario branch count, hardware support. CTA for demo build.",

  "3D Asset Creation":
    "Note poly count, PBR texture, rigging option. CTA for asset kit.",

  "Metaverse Events":
    "Specify platform, attendee capacity, sponsor booth feature. CTA for event deck.",

  "Virtual Showrooms":
    "Highlight 360° nav, product hotspot, analytics data. CTA to open showroom tour."
};



function buildSystemPrompt(platform: string, tone: string, length: string, personaPrompt: string, subcategoryPrompt: string, profile: Profile, userPrompt: string, allow_emojis: boolean, allow_hashtags: boolean) {
  const toneGuide = getToneInstructions(tone);
  const lengthRule = getLengthConstraints(length);
  let lengthInstruction = "";
  if (length === "Short" || length === "Medium") lengthInstruction = `Strictly keep total output under ${lengthRule.charLimit} characters.`;
  else if (length === "Long") lengthInstruction = `Ensure the caption is at least ${lengthRule.minChar} characters.`;

  return `
You are an elite social-media copywriter.

GOAL
Write ONE brand-authentic caption for ${platform}, targeting the "${profile.subcategory}" niche, based **strictly** on the user's intent and profile data.

This is the exact intent from the user:
“${userPrompt}”

IMPORTANT CLARIFICATION:
- You are writing social media posts for the user's audience.
- The user prompt is NOT a question to you.
- Never reply to the prompt as if you are answering it.
- Always generate a post speaking to the user's audience based on the prompt topic.
- If the prompt is phrased as a question, treat it as a question the user wants to ask their audience.
→ Do NOT override or change this intent.
→ Your job is to amplify this in the brand’s tone and content style - not to redirect it.
→ If the prompt is emotional, stay emotional.
→ If it’s funny or absurd, embrace the creativity.
→ Do NOT convert everything into a tutorial or how-to.

💡 Brand Voice Rules:
- Persona: ${profile.persona}
- ${personaPrompt}

Niche Style Context:
This brand usually posts in the “${profile.subcategory}” space.
This is their specific niche:
${subcategoryPrompt}
You may reflect some patterns (format, tone), but **never override the user's actual intent**.

Remove or reduce default suggestions like:
“Here’s a quick tip…”
“Try this tab…”
“Let’s jam…”
Unless it’s directly relevant to the user’s prompt

BRAND INFO
• Brand Name: ${profile.brand_name}
• Category: ${profile.category} → ${profile.subcategory}
• Goal: ${profile.primary_goal}
• Tone Tags: ${profile.voice_tags.join(", ")}
• Platform Focus: ${platform}

STRICT LENGTH:
${lengthInstruction}

STRICT TONE:
${toneGuide}

STRICT EMOJI:
${allow_emojis ? "You may use emojis where natural to the tone, but avoid overuse." : "Strictly DO NOT use any emojis in the caption."}

STRICT HASHTAG:
${allow_hashtags ? "Add 1–3 lowercase hashtags relevant to topic (space-separated)." : "Strictly DO NOT add any hashtags."}

END
• End with a soft CTA like “What do you think?”, “Let’s connect”, etc.
• Add 1–3 niche hashtags (lowercase, space-separated).

FORMAT
• Output ONLY the caption. No pretext or explanation.
`.trim();
}

function buildNewsPrompt(platform: string, tone: string, length: string, personaPrompt: string, subcategoryPrompt: string, profile: Profile, allow_emojis: boolean, allow_hashtags: boolean, news_age_window?: string) {
  const toneGuide = getToneInstructions(tone);
  const lengthRule = getLengthConstraints(length);
  let lengthInstruction = "";
  if (length === "Short" || length === "Medium") lengthInstruction = `Strictly keep total output under ${lengthRule.charLimit} characters.`;
  else if (length === "Long") lengthInstruction = `Ensure the caption is at least ${lengthRule.minChar} characters.`;

  return `
You are an elite social-media copywriter.

Your job is to find a **fresh trending news story** related to the "${profile.category}" category using web search.

🕰 Date constraint:
Only consider news articles from the last ${news_age_window}. Ignore older stories.

Then, turn that news into a brand-authentic caption for ${platform}, styled like the brand described below:

💡 Brand Voice Rules:
- Persona: ${profile.persona}
- ${personaPrompt}

Niche Context (for writing style only - do not change intent):
The brand primarily talks about "${profile.subcategory}". Use relevant wording, examples, and language common to this niche. DO NOT use default tutorial formats or structures for this subcategory unless directly relevant to the actual news topic.

BRAND INFO
• Brand Name: ${profile.brand_name}
• Category: ${profile.category} → ${profile.subcategory}
• Goal: ${profile.primary_goal}
• Tone Tags: ${profile.voice_tags.join(", ")}

INSTRUCTIONS
- Do NOT invent any news. Only use verifiable info.
- Reflect the brand’s persona in tone and perspective.

FORMAT
- 3–4 paragraphs
- 1 soft CTA at the end
- 1–3 lowercase hashtags
- Include the article link at the end of the caption

If you cannot find a natural CTA, use:
→ “What’s your take?”
→ “Let’s talk in comments.”

If no hashtags feel obvious, use 1–2 based on the news topic or brand theme.

If you cannot find any relevant news from the last ${news_age_window}, respond only with:
No Major News in the Selected Time Range

STRICT LENGTH:
${lengthInstruction}

STRICT TONE:
${toneGuide}

STRICT EMOJI:
${allow_emojis ? "You may use emojis where natural to the tone, but avoid overuse." : "Strictly DO NOT use any emojis in the caption."}

STRICT HASHTAG:
${allow_hashtags ? "Add 1–3 lowercase hashtags relevant to topic (space-separated)." : "Strictly DO NOT add any hashtags."}

RETURN ONLY the final caption.
`.trim();
}

// ---- Handler ----
const handler = wrapEdgeHandler2(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  return ensureIdempotency(
    req,
    async () => {
      const body = await readJsonSafe<RequestBody>(req);
      const { prompt, tone, platform, length, profile, generate_from_news, news_age_window, allow_emojis, allow_hashtags } = body || ({} as RequestBody);

      if (!tone || !platform || !length || !profile) return json({ error: "Missing required fields." }, 400, corsHeaders);

      const { maxTokens } = getLengthConstraints(length);
      const personaPrompt = (globalThis as any).personaPrompts?.[profile.persona] ?? "";
      const subcategoryPrompt = (globalThis as any).subCategoryPrompts?.[profile.subcategory] ??
        "Write an engaging caption aligned with the brand's niche.";

      const isNews = !!generate_from_news;
      const model = isNews ? "gpt-4o-mini-search-preview" : "gpt-4o-mini";

      const messages = isNews
        ? [{ role: "user", content: buildNewsPrompt(
              platform, tone, length, personaPrompt, subcategoryPrompt, profile,
              allow_emojis, allow_hashtags, news_age_window
            ) }]
        : (() => {
            if (!prompt) return null;
            const p = prompt.trim().replace(/\s+/g, " ").slice(0, 700);
            const system = buildSystemPrompt(
              platform, tone, length, personaPrompt, subcategoryPrompt, profile,
              p, allow_emojis, allow_hashtags
            );
            return [{ role: "system", content: system }, { role: "user", content: p }];
          })();

      if (!messages) return json({ error: "Prompt is required." }, 400, corsHeaders);

      // TTL policy: evergreen 7d, news 5m
      const aiCfg = {
        ...defaultConfig,
        ai: { ...defaultConfig.ai!, cacheTtlSec: isNews ? 300 : 60 * 60 * 24 * 7 },
        aiCache: redis,
        kv: redis,
      };

      const cacheKey = {
        model, platform, tone, length,
        persona: profile.persona, subcategory: profile.subcategory,
        allow_emojis, allow_hashtags,
        news: isNews ? { category: profile.category, window: news_age_window ?? "" } : null,
        prompt: isNews ? null : (messages[1]?.content ?? messages[0]?.content ?? ""),
        max_tokens: maxTokens,
      };

      const callAI = async () => {
        const response = await openai.chat.completions.create({
          model,
          max_tokens: maxTokens,
          messages,
          ...(!isNews ? { temperature: 0.7 } : {}),
          // The TS type may not include this; casting keeps Deno happy.
          ...(isNews ? { web_search_options: {} as Record<string, string> } : {}),
        });
        const caption = response.choices?.[0]?.message?.content ?? "";
        return json({ caption }, 200, { ...corsHeaders, "Cache-Control": "no-store" });
      };

      const res = await aiCachedCall(cacheKey, callAI, aiCfg);
      return withHeader(res, "x-model", model);
    },
    { kv: redis, ttlSec: 600, mode: "replay" },
  );
}, {
  // You can pass either routeName or name (both supported).
  name: "generate-caption",
  rateLimit: { capacity: 60, refillPerSec: 1 },
  requestTimeoutMs: 3000,
  aiTimeoutMs: 10_000,
  enableAutoCacheForGET: true,
  kv: redis,
  aiCache: redis,
});

serve(handler);
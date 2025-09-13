import { serve } from "std/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js';
import { OpenAI } from "https://deno.land/x/openai@v4.69.0/mod.ts";

const safe = (val?: string): boolean => typeof val === "string" && val.trim().length > 3;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "*",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  {
    global: {
      headers: {
        Authorization: `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!}`,
      },
    },
  }
);

const openai = new OpenAI(Deno.env.get("OPENAI_API_KEY")!);


export const ProfilePersona = {
    "Solo Creator": "Solo content creator who’s trying to grow an audience across platforms - one post, one video, one idea at a time. I handle everything myself: scripting, filming, editing, publishing, and engagement. There’s no team, no VA, no editor - just me and my ambition. I crave content that gives me viral angles, engagement hooks, or systems that help them stay consistent. My biggest challenges are idea fatigue, algorithm stress, and the pressure to stand out - so speak to me with clarity, momentum, and simplicity.",
    "SMB Founder": "I run a small business with a tiny team and a long to-do list. I wear every hat, founder, marketer, operator & every hour counts. I don’t have time for high-level theory or vague advice. I need proven tactics that save time, bring in revenue, or help me grow efficiently. Budget is always tight, so if I’m going to spend money or effort on something, it has to move the needle. Make it simple, make it actionable, and make it worth it.",
    "Agency / Freelancer": "I’m a freelancer or agency owner juggling multiple clients, deadlines, and deliverables, and I need to work smart to stay ahead. I care about client results, clear positioning, and scalable workflows. If your content helps me do better work, land better clients, or save time, I’m all in. But I’ve seen a lot of generic advice. If it doesn’t offer depth, proof, or a new angle, it’s noise to me. Give me something I can use or show."
};
export const ProfileCategory = {
    "Comedy": "Center the idea around the Comedy niche-highlighting prevalent challenges, current trends, and opportunities specific to comedy, with examples that speak the audience’s language.",
    "Tech": "Center the idea around the Tech niche-highlighting prevalent challenges, current trends, and opportunities specific to tech, with examples that speak the audience’s language.",
    "Education": "Center the idea around the Education niche-highlighting prevalent challenges, current trends, and opportunities specific to education, with examples that speak the audience’s language.",
    "Lifestyle & Vlogs": "Center the idea around the Lifestyle & Vlogs niche-highlighting prevalent challenges, current trends, and opportunities specific to lifestyle & vlogs, with examples that speak the audience’s language.",
    "Gaming": "Center the idea around the Gaming niche-highlighting prevalent challenges, current trends, and opportunities specific to gaming, with examples that speak the audience’s language.",
    "Beauty & Fashion": "Center the idea around the Beauty & Fashion niche-highlighting prevalent challenges, current trends, and opportunities specific to beauty & fashion, with examples that speak the audience’s language.",
    "Fitness & Wellness": "Center the idea around the Fitness & Wellness niche-highlighting prevalent challenges, current trends, and opportunities specific to fitness & wellness, with examples that speak the audience’s language.",
    "Finance & Investing": "Center the idea around the Finance & Investing niche-highlighting prevalent challenges, current trends, and opportunities specific to finance & investing, with examples that speak the audience’s language.",
    "Travel & Adventure": "Center the idea around the Travel & Adventure niche-highlighting prevalent challenges, current trends, and opportunities specific to travel & adventure, with examples that speak the audience’s language.",
    "Music & Performance": "Center the idea around the Music & Performance niche-highlighting prevalent challenges, current trends, and opportunities specific to music & performance, with examples that speak the audience’s language.",
    "Food & Cooking": "Center the idea around the Food & Cooking niche-highlighting prevalent challenges, current trends, and opportunities specific to food & cooking, with examples that speak the audience’s language.",
    "Art & DIY": "Center the idea around the Art & DIY niche-highlighting prevalent challenges, current trends, and opportunities specific to art & diy, with examples that speak the audience’s language.",
    "Personal Development": "Center the idea around the Personal Development niche-highlighting prevalent challenges, current trends, and opportunities specific to personal development, with examples that speak the audience’s language.",
    "Fashion & Apparel": "Center the idea around the Fashion & Apparel niche-highlighting prevalent challenges, current trends, and opportunities specific to fashion & apparel, with examples that speak the audience’s language.",
    "Food & Beverage": "Center the idea around the Food & Beverage niche-highlighting prevalent challenges, current trends, and opportunities specific to food & beverage, with examples that speak the audience’s language.",
    "Health & Wellness": "Center the idea around the Health & Wellness niche-highlighting prevalent challenges, current trends, and opportunities specific to health & wellness, with examples that speak the audience’s language.",
    "Technology & SaaS": "Center the idea around the Technology & SaaS niche-highlighting prevalent challenges, current trends, and opportunities specific to technology & saas, with examples that speak the audience’s language.",
    "Professional Services": "Center the idea around the Professional Services niche-highlighting prevalent challenges, current trends, and opportunities specific to professional services, with examples that speak the audience’s language.",
    "Real Estate & Property": "Center the idea around the Real Estate & Property niche-highlighting prevalent challenges, current trends, and opportunities specific to real estate & property, with examples that speak the audience’s language.",
    "Automotive": "Center the idea around the Automotive niche-highlighting prevalent challenges, current trends, and opportunities specific to automotive, with examples that speak the audience’s language.",
    "Education & Training": "Center the idea around the Education & Training niche-highlighting prevalent challenges, current trends, and opportunities specific to education & training, with examples that speak the audience’s language.",
    "Creative & Media": "Center the idea around the Creative & Media niche-highlighting prevalent challenges, current trends, and opportunities specific to creative & media, with examples that speak the audience’s language.",
    "Home & Living": "Center the idea around the Home & Living niche-highlighting prevalent challenges, current trends, and opportunities specific to home & living, with examples that speak the audience’s language.",
    "Financial Services & FinTech": "Center the idea around the Financial Services & FinTech niche-highlighting prevalent challenges, current trends, and opportunities specific to financial services & fintech, with examples that speak the audience’s language.",
    "Logistics & Supply Chain": "Center the idea around the Logistics & Supply Chain niche-highlighting prevalent challenges, current trends, and opportunities specific to logistics & supply chain, with examples that speak the audience’s language.",
    "Manufacturing & Industrial": "Center the idea around the Manufacturing & Industrial niche-highlighting prevalent challenges, current trends, and opportunities specific to manufacturing & industrial, with examples that speak the audience’s language.",
    "Agriculture & AgriTech": "Center the idea around the Agriculture & AgriTech niche-highlighting prevalent challenges, current trends, and opportunities specific to agriculture & agritech, with examples that speak the audience’s language.",
    "Energy & Utilities": "Center the idea around the Energy & Utilities niche-highlighting prevalent challenges, current trends, and opportunities specific to energy & utilities, with examples that speak the audience’s language.",
    "Marketing & Growth": "Center the idea around the Marketing & Growth niche-highlighting prevalent challenges, current trends, and opportunities specific to marketing & growth, with examples that speak the audience’s language.",
    "Design Services": "Center the idea around the Design Services niche-highlighting prevalent challenges, current trends, and opportunities specific to design services, with examples that speak the audience’s language.",
    "Development & IT": "Center the idea around the Development & IT niche-highlighting prevalent challenges, current trends, and opportunities specific to development & it, with examples that speak the audience’s language.",
    "Video & Animation": "Center the idea around the Video & Animation niche-highlighting prevalent challenges, current trends, and opportunities specific to video & animation, with examples that speak the audience’s language.",
    "Writing & Content": "Center the idea around the Writing & Content niche-highlighting prevalent challenges, current trends, and opportunities specific to writing & content, with examples that speak the audience’s language.",
    "Photography & Creative Media": "Center the idea around the Photography & Creative Media niche-highlighting prevalent challenges, current trends, and opportunities specific to photography & creative media, with examples that speak the audience’s language.",
    "Consulting & Strategy": "Center the idea around the Consulting & Strategy niche-highlighting prevalent challenges, current trends, and opportunities specific to consulting & strategy, with examples that speak the audience’s language.",
    "Translation & Localization": "Center the idea around the Translation & Localization niche-highlighting prevalent challenges, current trends, and opportunities specific to translation & localization, with examples that speak the audience’s language.",
    "Data & Analytics": "Center the idea around the Data & Analytics niche-highlighting prevalent challenges, current trends, and opportunities specific to data & analytics, with examples that speak the audience’s language.",
    "Virtual Assistance & Admin": "Center the idea around the Virtual Assistance & Admin niche-highlighting prevalent challenges, current trends, and opportunities specific to virtual assistance & admin, with examples that speak the audience’s language.",
    "Finance & Legal Advisory": "Center the idea around the Finance & Legal Advisory niche-highlighting prevalent challenges, current trends, and opportunities specific to finance & legal advisory, with examples that speak the audience’s language.",
    "HR & Talent Services": "Center the idea around the HR & Talent Services niche-highlighting prevalent challenges, current trends, and opportunities specific to hr & talent services, with examples that speak the audience’s language.",
    "Product & CX Research": "Center the idea around the Product & CX Research niche-highlighting prevalent challenges, current trends, and opportunities specific to product & cx research, with examples that speak the audience’s language.",
    "Audio & Podcast Production": "Center the idea around the Audio & Podcast Production niche-highlighting prevalent challenges, current trends, and opportunities specific to audio & podcast production, with examples that speak the audience’s language.",
    "AR/VR & Immersive Tech": "Center the idea around the AR/VR & Immersive Tech niche-highlighting prevalent challenges, current trends, and opportunities specific to ar/vr & immersive tech, with examples that speak the audience’s language.",
    "Podcasts & Audio Media": "Center the idea around the Podcasts & Audio Media niche-highlighting prevalent challenges, current trends, and opportunities specific to podcasts & audio media, with examples that speak the audience’s language.",
    "Content Production": "Center the idea around the Content Production niche-highlighting prevalent challenges, current trends, and opportunities specific to content production, with examples that speak the audience’s language."
};
export const ProfileSubcategory = {
    "Skits": "Dive deep into the Skits micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of skits will immediately recognize.",
    "Relatable Humor": "Dive deep into the Relatable Humor micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of relatable humor will immediately recognize.",
    "Satire & Parody": "Dive deep into the Satire & Parody micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of satire & parody will immediately recognize.",
    "Memes": "Dive deep into the Memes micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of memes will immediately recognize.",
    "Reaction Videos": "Dive deep into the Reaction Videos micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of reaction videos will immediately recognize.",
    "Product Reviews": "Dive deep into the Product Reviews micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of product reviews will immediately recognize.",
    "Tutorials": "Dive deep into the Tutorials micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of tutorials will immediately recognize.",
    "Coding & Dev Logs": "Dive deep into the Coding & Dev Logs micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of coding & dev logs will immediately recognize.",
    "AI Tool Demos": "Dive deep into the AI Tool Demos micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of ai tool demos will immediately recognize.",
    "Hardware Unboxings": "Dive deep into the Hardware Unboxings micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of hardware unboxings will immediately recognize.",
    "Study Tips": "Dive deep into the Study Tips micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of study tips will immediately recognize.",
    "Animated Explainers": "Dive deep into the Animated Explainers micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of animated explainers will immediately recognize.",
    "Language Learning": "Dive deep into the Language Learning micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of language learning will immediately recognize.",
    "Science Experiments": "Dive deep into the Science Experiments micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of science experiments will immediately recognize.",
    "History Storytelling": "Dive deep into the History Storytelling micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of history storytelling will immediately recognize.",
    "Daily Routines": "Dive deep into the Daily Routines micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of daily routines will immediately recognize.",
    "Minimalism": "Dive deep into the Minimalism micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of minimalism will immediately recognize.",
    "Home Makeovers": "Dive deep into the Home Makeovers micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of home makeovers will immediately recognize.",
    "College Life": "Dive deep into the College Life micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of college life will immediately recognize.",
    "Day-in-the-Life": "Dive deep into the Day-in-the-Life micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of day-in-the-life will immediately recognize.",
    "Let’s Plays": "Dive deep into the Let’s Plays micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of let’s plays will immediately recognize.",
    "Esports Commentary": "Dive deep into the Esports Commentary micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of esports commentary will immediately recognize.",
    "Speedruns": "Dive deep into the Speedruns micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of speedruns will immediately recognize.",
    "Game Reviews": "Dive deep into the Game Reviews micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of game reviews will immediately recognize.",
    "Stream Highlights": "Dive deep into the Stream Highlights micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of stream highlights will immediately recognize.",
    "Makeup Tutorials": "Dive deep into the Makeup Tutorials micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of makeup tutorials will immediately recognize.",
    "Outfit Lookbooks": "Dive deep into the Outfit Lookbooks micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of outfit lookbooks will immediately recognize.",
    "Styling Hacks": "Dive deep into the Styling Hacks micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of styling hacks will immediately recognize.",
    "Product Hauls": "Dive deep into the Product Hauls micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of product hauls will immediately recognize.",
    "DIY Skincare": "Dive deep into the DIY Skincare micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of diy skincare will immediately recognize.",
    "Home Workouts": "Dive deep into the Home Workouts micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of home workouts will immediately recognize.",
    "Yoga & Meditation": "Dive deep into the Yoga & Meditation micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of yoga & meditation will immediately recognize.",
    "Healthy Recipes": "Dive deep into the Healthy Recipes micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of healthy recipes will immediately recognize.",
    "Transformation Journeys": "Dive deep into the Transformation Journeys micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of transformation journeys will immediately recognize.",
    "Mental-Health Chats": "Dive deep into the Mental-Health Chats micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of mental-health chats will immediately recognize.",
    "Mutual-Fund Deep-Dives": "Dive deep into the Mutual-Fund Deep-Dives micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of mutual-fund deep-dives will immediately recognize.",
    "Stock Picks": "Dive deep into the Stock Picks micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of stock picks will immediately recognize.",
    "Crypto Breakdowns": "Dive deep into the Crypto Breakdowns micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of crypto breakdowns will immediately recognize.",
    "Budgeting Tips": "Dive deep into the Budgeting Tips micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of budgeting tips will immediately recognize.",
    "Side-Hustle Ideas": "Dive deep into the Side-Hustle Ideas micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of side-hustle ideas will immediately recognize.",
    "Backpacking Guides": "Dive deep into the Backpacking Guides micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of backpacking guides will immediately recognize.",
    "City Walkthroughs": "Dive deep into the City Walkthroughs micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of city walkthroughs will immediately recognize.",
    "Food Tours": "Dive deep into the Food Tours micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of food tours will immediately recognize.",
    "Cultural Immersion": "Dive deep into the Cultural Immersion micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of cultural immersion will immediately recognize.",
    "Travel Hacks": "Dive deep into the Travel Hacks micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of travel hacks will immediately recognize.",
    "Original Songs": "Dive deep into the Original Songs micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of original songs will immediately recognize.",
    "Cover Sessions": "Dive deep into the Cover Sessions micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of cover sessions will immediately recognize.",
    "Live Looping": "Dive deep into the Live Looping micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of live looping will immediately recognize.",
    "Instrument Tutorials": "Dive deep into the Instrument Tutorials micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of instrument tutorials will immediately recognize.",
    "Beat Making": "Dive deep into the Beat Making micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of beat making will immediately recognize.",
    "Quick Recipes": "Dive deep into the Quick Recipes micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of quick recipes will immediately recognize.",
    "Street-Food Reviews": "Dive deep into the Street-Food Reviews micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of street-food reviews will immediately recognize.",
    "Meal Prep": "Dive deep into the Meal Prep micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of meal prep will immediately recognize.",
    "ASMR Cooking": "Dive deep into the ASMR Cooking micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of asmr cooking will immediately recognize.",
    "International Cuisine": "Dive deep into the International Cuisine micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of international cuisine will immediately recognize.",
    "Digital Drawing": "Dive deep into the Digital Drawing micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of digital drawing will immediately recognize.",
    "Crafts & Hacks": "Dive deep into the Crafts & Hacks micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of crafts & hacks will immediately recognize.",
    "3D Printing": "Dive deep into the 3D Printing micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of 3d printing will immediately recognize.",
    "Resin Art": "Dive deep into the Resin Art micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of resin art will immediately recognize.",
    "Upcycling Projects": "Dive deep into the Upcycling Projects micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of upcycling projects will immediately recognize.",
    "Study-With-Me": "Dive deep into the Study-With-Me micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of study-with-me will immediately recognize.",
    "Productivity Systems": "Dive deep into the Productivity Systems micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of productivity systems will immediately recognize.",
    "Book Summaries": "Dive deep into the Book Summaries micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of book summaries will immediately recognize.",
    "Goal-Setting": "Dive deep into the Goal-Setting micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of goal-setting will immediately recognize.",
    "Mindfulness": "Dive deep into the Mindfulness micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of mindfulness will immediately recognize.",
    "Retail Boutique": "Dive deep into the Retail Boutique micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of retail boutique will immediately recognize.",
    "Wholesale Supplier": "Dive deep into the Wholesale Supplier micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of wholesale supplier will immediately recognize.",
    "D2C E-commerce": "Dive deep into the D2C E-commerce micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of d2c e-commerce will immediately recognize.",
    "Custom Tailoring": "Dive deep into the Custom Tailoring micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of custom tailoring will immediately recognize.",
    "Sustainable Fashion": "Dive deep into the Sustainable Fashion micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of sustainable fashion will immediately recognize.",
    "Restaurant": "Dive deep into the Restaurant micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of restaurant will immediately recognize.",
    "Café / Coffee Bar": "Dive deep into the Café / Coffee Bar micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of café / coffee bar will immediately recognize.",
    "Bakery & Desserts": "Dive deep into the Bakery & Desserts micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of bakery & desserts will immediately recognize.",
    "Cloud Kitchen": "Dive deep into the Cloud Kitchen micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of cloud kitchen will immediately recognize.",
    "Packaged FMCG": "Dive deep into the Packaged FMCG micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of packaged fmcg will immediately recognize.",
    "Gym / Fitness Studio": "Dive deep into the Gym / Fitness Studio micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of gym / fitness studio will immediately recognize.",
    "Yoga Center": "Dive deep into the Yoga Center micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of yoga center will immediately recognize.",
    "Nutraceutical Brand": "Dive deep into the Nutraceutical Brand micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of nutraceutical brand will immediately recognize.",
    "Spa & Wellness": "Dive deep into the Spa & Wellness micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of spa & wellness will immediately recognize.",
    "Telehealth Clinic": "Dive deep into the Telehealth Clinic micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of telehealth clinic will immediately recognize.",
    "B2B SaaS": "Dive deep into the B2B SaaS micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of b2b saas will immediately recognize.",
    "Mobile-App Startup": "Dive deep into the Mobile-App Startup micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of mobile-app startup will immediately recognize.",
    "IT Services": "Dive deep into the IT Services micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of it services will immediately recognize.",
    "Cybersecurity": "Dive deep into the Cybersecurity micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of cybersecurity will immediately recognize.",
    "AI Solutions": "Dive deep into the AI Solutions micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of ai solutions will immediately recognize.",
    "Legal Firm": "Dive deep into the Legal Firm micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of legal firm will immediately recognize.",
    "Accounting Practice": "Dive deep into the Accounting Practice micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of accounting practice will immediately recognize.",
    "Consulting Agency": "Dive deep into the Consulting Agency micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of consulting agency will immediately recognize.",
    "Architecture Studio": "Dive deep into the Architecture Studio micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of architecture studio will immediately recognize.",
    "HR Outsourcing": "Dive deep into the HR Outsourcing micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of hr outsourcing will immediately recognize.",
    "Residential Brokerage": "Dive deep into the Residential Brokerage micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of residential brokerage will immediately recognize.",
    "Commercial Leasing": "Dive deep into the Commercial Leasing micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of commercial leasing will immediately recognize.",
    "Property Management": "Dive deep into the Property Management micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of property management will immediately recognize.",
    "Co-Working Spaces": "Dive deep into the Co-Working Spaces micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of co-working spaces will immediately recognize.",
    "Vacation Rentals": "Dive deep into the Vacation Rentals micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of vacation rentals will immediately recognize.",
    "Dealership": "Dive deep into the Dealership micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of dealership will immediately recognize.",
    "Auto-Repair Shop": "Dive deep into the Auto-Repair Shop micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of auto-repair shop will immediately recognize.",
    "EV-Charging Network": "Dive deep into the EV-Charging Network micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of ev-charging network will immediately recognize.",
    "Car Rental": "Dive deep into the Car Rental micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of car rental will immediately recognize.",
    "Auto-Parts E-commerce": "Dive deep into the Auto-Parts E-commerce micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of auto-parts e-commerce will immediately recognize.",
    "Coaching Center": "Dive deep into the Coaching Center micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of coaching center will immediately recognize.",
    "EdTech Platform": "Dive deep into the EdTech Platform micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of edtech platform will immediately recognize.",
    "Skill Bootcamp": "Dive deep into the Skill Bootcamp micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of skill bootcamp will immediately recognize.",
    "Corporate Training": "Dive deep into the Corporate Training micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of corporate training will immediately recognize.",
    "Test-Prep Institute": "Dive deep into the Test-Prep Institute micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of test-prep institute will immediately recognize.",
    "Production House": "Dive deep into the Production House micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of production house will immediately recognize.",
    "Printing & Branding": "Dive deep into the Printing & Branding micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of printing & branding will immediately recognize.",
    "Event Management": "Dive deep into the Event Management micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of event management will immediately recognize.",
    "Advertising Studio": "Dive deep into the Advertising Studio micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of advertising studio will immediately recognize.",
    "Influencer Merch": "Dive deep into the Influencer Merch micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of influencer merch will immediately recognize.",
    "Furniture Manufacturing": "Dive deep into the Furniture Manufacturing micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of furniture manufacturing will immediately recognize.",
    "Interior Design": "Dive deep into the Interior Design micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of interior design will immediately recognize.",
    "Home-Décor Retail": "Dive deep into the Home-Décor Retail micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of home-décor retail will immediately recognize.",
    "Smart-Home Installers": "Dive deep into the Smart-Home Installers micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of smart-home installers will immediately recognize.",
    "Landscaping": "Dive deep into the Landscaping micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of landscaping will immediately recognize.",
    "Mutual-Fund Distributor": "Dive deep into the Mutual-Fund Distributor micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of mutual-fund distributor will immediately recognize.",
    "NBFC / Micro-Finance": "Dive deep into the NBFC / Micro-Finance micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of nbfc / micro-finance will immediately recognize.",
    "Wealth-Advisory": "Dive deep into the Wealth-Advisory micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of wealth-advisory will immediately recognize.",
    "Payments & Wallets": "Dive deep into the Payments & Wallets micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of payments & wallets will immediately recognize.",
    "InsurTech": "Dive deep into the InsurTech micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of insurtech will immediately recognize.",
    "Third-Party Logistics (3PL)": "Dive deep into the Third-Party Logistics (3PL) micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of third-party logistics (3pl) will immediately recognize.",
    "Last-Mile Delivery": "Dive deep into the Last-Mile Delivery micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of last-mile delivery will immediately recognize.",
    "Cold-Chain": "Dive deep into the Cold-Chain micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of cold-chain will immediately recognize.",
    "Warehousing": "Dive deep into the Warehousing micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of warehousing will immediately recognize.",
    "Freight Forwarding": "Dive deep into the Freight Forwarding micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of freight forwarding will immediately recognize.",
    "FMCG Manufacturing": "Dive deep into the FMCG Manufacturing micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of fmcg manufacturing will immediately recognize.",
    "Electronics Assembly": "Dive deep into the Electronics Assembly micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of electronics assembly will immediately recognize.",
    "Textile Mill": "Dive deep into the Textile Mill micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of textile mill will immediately recognize.",
    "Precision Engineering": "Dive deep into the Precision Engineering micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of precision engineering will immediately recognize.",
    "Packaging Plants": "Dive deep into the Packaging Plants micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of packaging plants will immediately recognize.",
    "Organic Farming": "Dive deep into the Organic Farming micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of organic farming will immediately recognize.",
    "Farm-to-Table Brand": "Dive deep into the Farm-to-Table Brand micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of farm-to-table brand will immediately recognize.",
    "Agri-Input Supplier": "Dive deep into the Agri-Input Supplier micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of agri-input supplier will immediately recognize.",
    "Hydroponics": "Dive deep into the Hydroponics micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of hydroponics will immediately recognize.",
    "Crop-Analytics Platform": "Dive deep into the Crop-Analytics Platform micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of crop-analytics platform will immediately recognize.",
    "Solar EPC": "Dive deep into the Solar EPC micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of solar epc will immediately recognize.",
    "EV Infrastructure": "Dive deep into the EV Infrastructure micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of ev infrastructure will immediately recognize.",
    "Bio-Fuel Production": "Dive deep into the Bio-Fuel Production micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of bio-fuel production will immediately recognize.",
    "Power Distribution": "Dive deep into the Power Distribution micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of power distribution will immediately recognize.",
    "Smart-Metering": "Dive deep into the Smart-Metering micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of smart-metering will immediately recognize.",
    "Social-Media Management": "Dive deep into the Social-Media Management micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of social-media management will immediately recognize.",
    "Performance Ads": "Dive deep into the Performance Ads micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of performance ads will immediately recognize.",
    "Email Marketing": "Dive deep into the Email Marketing micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of email marketing will immediately recognize.",
    "Growth Hacking": "Dive deep into the Growth Hacking micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of growth hacking will immediately recognize.",
    "Influencer Collabs": "Dive deep into the Influencer Collabs micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of influencer collabs will immediately recognize.",
    "UI/UX Design": "Dive deep into the UI/UX Design micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of ui/ux design will immediately recognize.",
    "Brand Identity": "Dive deep into the Brand Identity micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of brand identity will immediately recognize.",
    "Motion Graphics": "Dive deep into the Motion Graphics micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of motion graphics will immediately recognize.",
    "Illustration": "Dive deep into the Illustration micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of illustration will immediately recognize.",
    "Presentation Design": "Dive deep into the Presentation Design micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of presentation design will immediately recognize.",
    "Web Development": "Dive deep into the Web Development micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of web development will immediately recognize.",
    "Mobile Apps": "Dive deep into the Mobile Apps micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of mobile apps will immediately recognize.",
    "Shopify & E-commerce": "Dive deep into the Shopify & E-commerce micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of shopify & e-commerce will immediately recognize.",
    "API Integrations": "Dive deep into the API Integrations micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of api integrations will immediately recognize.",
    "DevOps & Cloud": "Dive deep into the DevOps & Cloud micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of devops & cloud will immediately recognize.",
    "Explainer Videos": "Dive deep into the Explainer Videos micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of explainer videos will immediately recognize.",
    "Short-Form Reels": "Dive deep into the Short-Form Reels micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of short-form reels will immediately recognize.",
    "3D Animation": "Dive deep into the 3D Animation micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of 3d animation will immediately recognize.",
    "Post-Production": "Dive deep into the Post-Production micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of post-production will immediately recognize.",
    "Livestream Production": "Dive deep into the Livestream Production micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of livestream production will immediately recognize.",
    "Blog Articles": "Dive deep into the Blog Articles micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of blog articles will immediately recognize.",
    "Copywriting": "Dive deep into the Copywriting micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of copywriting will immediately recognize.",
    "Technical Writing": "Dive deep into the Technical Writing micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of technical writing will immediately recognize.",
    "Scriptwriting": "Dive deep into the Scriptwriting micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of scriptwriting will immediately recognize.",
    "Ghostwriting": "Dive deep into the Ghostwriting micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of ghostwriting will immediately recognize.",
    "Product Photography": "Dive deep into the Product Photography micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of product photography will immediately recognize.",
    "Lifestyle Shoots": "Dive deep into the Lifestyle Shoots micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of lifestyle shoots will immediately recognize.",
    "Event Coverage": "Dive deep into the Event Coverage micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of event coverage will immediately recognize.",
    "Drone Filming": "Dive deep into the Drone Filming micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of drone filming will immediately recognize.",
    "Stock-Photo Sets": "Dive deep into the Stock-Photo Sets micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of stock-photo sets will immediately recognize.",
    "Brand Positioning": "Dive deep into the Brand Positioning micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of brand positioning will immediately recognize.",
    "GTM Strategy": "Dive deep into the GTM Strategy micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of gtm strategy will immediately recognize.",
    "Market Research": "Dive deep into the Market Research micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of market research will immediately recognize.",
    "Pricing Optimization": "Dive deep into the Pricing Optimization micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of pricing optimization will immediately recognize.",
    "Investor Pitch Decks": "Dive deep into the Investor Pitch Decks micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of investor pitch decks will immediately recognize.",
    "Multilingual Copy": "Dive deep into the Multilingual Copy micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of multilingual copy will immediately recognize.",
    "Subtitle & Captioning": "Dive deep into the Subtitle & Captioning micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of subtitle & captioning will immediately recognize.",
    "App Localization": "Dive deep into the App Localization micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of app localization will immediately recognize.",
    "Voiceover Dubbing": "Dive deep into the Voiceover Dubbing micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of voiceover dubbing will immediately recognize.",
    "Cultural Adaptation": "Dive deep into the Cultural Adaptation micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of cultural adaptation will immediately recognize.",
    "Dashboard Building": "Dive deep into the Dashboard Building micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of dashboard building will immediately recognize.",
    "CRO Audits": "Dive deep into the CRO Audits micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of cro audits will immediately recognize.",
    "SEO Analytics": "Dive deep into the SEO Analytics micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of seo analytics will immediately recognize.",
    "Attribution Modeling": "Dive deep into the Attribution Modeling micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of attribution modeling will immediately recognize.",
    "A/B Testing": "Dive deep into the A/B Testing micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of a/b testing will immediately recognize.",
    "Calendar Management": "Dive deep into the Calendar Management micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of calendar management will immediately recognize.",
    "CRM Upkeep": "Dive deep into the CRM Upkeep micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of crm upkeep will immediately recognize.",
    "Invoicing & Bookkeeping": "Dive deep into the Invoicing & Bookkeeping micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of invoicing & bookkeeping will immediately recognize.",
    "Customer Support": "Dive deep into the Customer Support micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of customer support will immediately recognize.",
    "Lead Prospecting": "Dive deep into the Lead Prospecting micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of lead prospecting will immediately recognize.",
    "Fractional CFO": "Dive deep into the Fractional CFO micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of fractional cfo will immediately recognize.",
    "Tax Advisory": "Dive deep into the Tax Advisory micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of tax advisory will immediately recognize.",
    "Fundraising Support": "Dive deep into the Fundraising Support micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of fundraising support will immediately recognize.",
    "Compliance Filings": "Dive deep into the Compliance Filings micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of compliance filings will immediately recognize.",
    "M&A Due Diligence": "Dive deep into the M&A Due Diligence micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of m&a due diligence will immediately recognize.",
    "Recruitment Process Outsourcing": "Dive deep into the Recruitment Process Outsourcing micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of recruitment process outsourcing will immediately recognize.",
    "Employer Branding": "Dive deep into the Employer Branding micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of employer branding will immediately recognize.",
    "Payroll Management": "Dive deep into the Payroll Management micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of payroll management will immediately recognize.",
    "L&D Programs": "Dive deep into the L&D Programs micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of l&d programs will immediately recognize.",
    "Staff Augmentation": "Dive deep into the Staff Augmentation micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of staff augmentation will immediately recognize.",
    "User Interviews": "Dive deep into the User Interviews micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of user interviews will immediately recognize.",
    "Prototype Testing": "Dive deep into the Prototype Testing micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of prototype testing will immediately recognize.",
    "Customer Journey Mapping": "Dive deep into the Customer Journey Mapping micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of customer journey mapping will immediately recognize.",
    "NPS Surveys": "Dive deep into the NPS Surveys micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of nps surveys will immediately recognize.",
    "Feature Prioritization": "Dive deep into the Feature Prioritization micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of feature prioritization will immediately recognize.",
    "Podcast Editing": "Dive deep into the Podcast Editing micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of podcast editing will immediately recognize.",
    "Jingle Composition": "Dive deep into the Jingle Composition micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of jingle composition will immediately recognize.",
    "Sound Design": "Dive deep into the Sound Design micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of sound design will immediately recognize.",
    "Voice-acting": "Dive deep into the Voice-acting micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of voice-acting will immediately recognize.",
    "Audiobook Production": "Dive deep into the Audiobook Production micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of audiobook production will immediately recognize.",
    "AR Filters": "Dive deep into the AR Filters micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of ar filters will immediately recognize.",
    "VR Training Sims": "Dive deep into the VR Training Sims micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of vr training sims will immediately recognize.",
    "3D Asset Creation": "Dive deep into the 3D Asset Creation micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of 3d asset creation will immediately recognize.",
    "Metaverse Events": "Dive deep into the Metaverse Events micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of metaverse events will immediately recognize.",
    "Virtual Showrooms": "Dive deep into the Virtual Showrooms micro-topic, surfacing nuanced insights, use-cases, and relatable scenarios that enthusiasts of virtual showrooms will immediately recognize."
};
export const Voice_Tags = {
    "Friendly": "Maintain an approachable, welcoming tone that feels like helpful advice from a trusted peer.",
    "Professional": "Adopt a polished, business-savvy tone that instills confidence and domain authority.",
    "Witty": "Infuse clever wordplay and light sarcasm to keep the reader amused while informed.",
    "Bold": "Speak with punchy confidence, unafraid to stake strong opinions and decisive calls to action.",
    "Empathetic": "Demonstrate emotional understanding, validating the reader’s challenges before offering solutions.",
    "Inspirational": "Elevate with uplifting language that sparks motivation and forward momentum.",
    "Data-driven": "Lead with statistics, research findings, and quantified evidence to build credibility.",
    "Story-teller": "Weave rich narratives and relatable vignettes that illustrate each key point.",
    "Analytical": "Deconstruct complex ideas logically, guiding the reader through clear, step-by-step reasoning.",
    "Conversational": "Write like an engaging dialogue-short sentences, direct questions, and interactive asides."
};
export const Format_Preference = {
    "Question": "Frame the concept as an open-ended question that invites readers to pause and reflect before engaging.",
    "Hot-take": "Present the idea as a provocative statement that challenges conventional wisdom and sparks debate.",
    "Story Prompt": "Kick off with a narrative seed that readers can imagine themselves in, encouraging imaginative continuations.",
    "List-starter": "Offer a numbered or bulleted opener that clearly signals multiple bite-sized takeaways to come.",
    "Mini-challenge": "Pose a compact actionable challenge the audience can attempt immediately to test the idea.",
    "Fill-in-the-blank": "Set up a partial sentence that the audience mentally completes, fostering interactive engagement."
};
export const Hook_Style = {
    "Statistic": "Lead with a surprising, specific data point to provide instant credibility and curiosity.",
    "Myth-bust": "Open by debunking a common misconception, repositioning the reader’s perspective instantly.",
    "Challenge": "Start with a direct dare that pushes readers outside their comfort zone.",
    "Personal Anecdote": "Begin with a concise first-person story that humanizes the topic and builds rapport.",
    "Bold Claim": "Launch with an assertive, sweeping statement that demands the reader’s attention.",
    "What If": "Spark imagination by posing a speculative scenario that reframes possibilities.",
    "Quote-lead": "Introduce with a resonant quote that encapsulates the essence of the forthcoming idea."
};
export const Emotion_Target = {
    "Inspire": "Select or craft a quote that evokes a strong sense of inspire, ensuring the wording triggers inspire in the audience’s mindset.",
    "Courage": "Select or craft a quote that evokes a strong sense of courage, ensuring the wording triggers courage in the audience’s mindset.",
    "Humor": "Select or craft a quote that evokes a strong sense of humor, ensuring the wording triggers humor in the audience’s mindset.",
    "Gratitude": "Select or craft a quote that evokes a strong sense of gratitude, ensuring the wording triggers gratitude in the audience’s mindset.",
    "Resilience": "Select or craft a quote that evokes a strong sense of resilience, ensuring the wording triggers resilience in the audience’s mindset.",
    "Curiosity": "Select or craft a quote that evokes a strong sense of curiosity, ensuring the wording triggers curiosity in the audience’s mindset.",
    "Empathy": "Select or craft a quote that evokes a strong sense of empathy, ensuring the wording triggers empathy in the audience’s mindset."
};
export const Author_Archetype = {
    "Visionary": "Attribute the quote to a forward-thinking visionary whose words spotlight future possibilities.",
    "Operator": "Channel a pragmatic operator offering grounded, execution-focused wisdom.",
    "Coach": "Present guidance with uplifting, instructional flair that empowers self-improvement.",
    "Story-teller": "Share a narrative-driven perspective that conveys meaning through anecdote.",
    "Rebel": "Highlight a contrarian voice that challenges norms and encourages bold action.",
    "Scientist": "Lean on empirical rigor-cite experimentation, evidence, and systematic inquiry.",
    "Philosopher": "Explore thought-provoking reflections that grapple with fundamental truths."
};
export const Metric = {
    "% Percentage": "Express the fact using a clear % Percentage format so readers grasp the magnitude instantly.",
    "$ Dollar-value": "Express the fact using a clear $ Dollar-value format so readers grasp the magnitude instantly.",
    "X-of-Y Ratio": "Express the fact using a clear X-of-Y Ratio format so readers grasp the magnitude instantly.",
    "Rank/Position": "Express the fact using a clear Rank/Position format so readers grasp the magnitude instantly.",
    "Time-based (# hrs, days)": "Express the fact using a clear Time-based (# hrs, days) format so readers grasp the magnitude instantly.",
    "Growth Rate (%)": "Express the fact using a clear Growth Rate (%) format so readers grasp the magnitude instantly."
};
export const Time_Horizon = {
    "Latest Month": "Ensure the fact explicitly references data within the latest month timeframe.",
    "Latest Year": "Ensure the fact explicitly references data within the latest year timeframe.",
    "Last 3 Years": "Ensure the fact explicitly references data within the last 3 years timeframe.",
    "Last 5 Years": "Ensure the fact explicitly references data within the last 5 years timeframe.",
    "Last 10 Years": "Ensure the fact explicitly references data within the last 10 years timeframe.",
    "Next Year": "Ensure the fact explicitly references data within the next year timeframe.",
    "Next 5 Years": "Ensure the fact explicitly references data within the next 5 years timeframe.",
    "All-Time Record": "Ensure the fact explicitly references data within the all-time record timeframe."
};
export const Credibility_Level = {
    "Casual Blog Post": "Source the fact from a casual blog post to reinforce trustworthiness.",
    "Company Report": "Source the fact from a company report to reinforce trustworthiness.",
    "Industry White-paper": "Source the fact from a industry white-paper to reinforce trustworthiness.",
    "Government Data": "Source the fact from a government data to reinforce trustworthiness.",
    "Academic Journal": "Source the fact from a academic journal to reinforce trustworthiness.",
    "Peer-reviewed Meta Analysis": "Source the fact from a peer-reviewed meta analysis to reinforce trustworthiness."
};
export const Skill_Level = {
    "Beginner": "Design the tip to cater to beginner practitioners, matching terminology and complexity to their proficiency.",
    "Intermediate": "Design the tip to cater to intermediate practitioners, matching terminology and complexity to their proficiency.",
    "Advanced": "Design the tip to cater to advanced practitioners, matching terminology and complexity to their proficiency.",
    "Pro/Expert": "Design the tip to cater to pro/expert practitioners, matching terminology and complexity to their proficiency.",
    "All Levels": "Design the tip to cater to all levels practitioners, matching terminology and complexity to their proficiency."
};
export const Implementation_Time = {
    "< 10 min": "Offer a tip that can be implemented in roughly < 10 min, detailing a compact, step-by-step action plan.",
    "30 min": "Offer a tip that can be implemented in roughly 30 min, detailing a compact, step-by-step action plan.",
    "1 hour": "Offer a tip that can be implemented in roughly 1 hour, detailing a compact, step-by-step action plan.",
    "Half-day": "Offer a tip that can be implemented in roughly Halfday, detailing a compact, step-by-step action plan.",
    "1 Day": "Offer a tip that can be implemented in roughly 1 Day, detailing a compact, step-by-step action plan.",
    "1 Week": "Offer a tip that can be implemented in roughly 1 Week, detailing a compact, step-by-step action plan.",
    "1 Year": "Offer a tip that can be implemented in roughly 1 Year, detailing a compact, step-by-step action plan."
};
export const Tone = {
  "friendly": "Keep the language warm and approachable, like chatting with a helpful friend who genuinely wants the reader to succeed.",
  "witty": "Sprinkle clever wordplay and quick comebacks to amuse while informing, making every line feel like a smart inside joke.",
  "empathetic": "Acknowledge the audience’s struggles with compassionate phrasing, validating their feelings before offering thoughtful guidance.",
  "dataDriven": "Lead with hard numbers, research citations, and logical proofs to establish unquestionable credibility from the first sentence.",
  "contrarian": "Challenge prevailing wisdom with well-reasoned counter-points that provoke fresh thinking and spark lively debate.",
  "bold": "Use punchy, assertive statements and decisive calls-to-action that convey supreme confidence and urgency.",
  "formal": "Adopt polished, professional diction-complete sentences, precise terminology, and zero slang-for a boardroom-ready tone.",
  "casual": "Write as if texting a peer: relaxed syntax, contractions, emojis optional, and plenty of friendly asides.",
  "inspirational": "Elevate the prose with vivid imagery and motivational language that sparks ambition and forward momentum.",
  "humorous": "Inject playful jokes, unexpected analogies, and lighthearted banter so the reader smiles while learning."
};
export const Primary_Goal = {
  "educate": "Deliver clear explanations, illustrative examples, and actionable steps that deepen the reader’s understanding.",
  "entertain": "Prioritize fun anecdotes, surprises, and upbeat pacing to keep the audience delightfully hooked.",
  "engage": "Pose thought-provoking questions and interactive prompts that invite replies, polls, or duets.",
  "generateLeads": "Provide high-value insights while nudging readers toward gated resources or sign-up forms.",
  "buildAuthority": "Showcase deep expertise through authoritative insights, case studies, and credible references.",
  "convert": "Drive the reader to a single decisive CTA-purchase, subscribe, or book-using persuasive language and urgency tactics.",
  "nurtureCommunity": "Foster a sense of belonging with inclusive language and invitations to share experiences and support peers."
};
export const Desired_KPI = {
  "signupRate": "Optimize every element to maximize free-trial or newsletter sign-ups.",
  "ctr": "Craft magnetic headlines and crystal-clear link cues that boost click-through rate.",
  "engagementRate": "Encourage reactions, comments, and shares to lift overall engagement percentage.",
  "comments": "Ask direct questions and spark debate to increase the number of thoughtful comments.",
  "shares": "Create concise, relatable nuggets of value that people will be eager to repost.",
  "saves": "Offer evergreen, reference-worthy insights that motivate users to save the post for later use.",
  "leadVolume": "Embed soft-sell offers and gated assets to grow the total count of qualified leads.",
  "conversionRate": "Streamline persuasive messaging and social proof to elevate the percentage of readers who take the desired action.",
  "aov": "Suggest bundles, upgrades, or add-ons aimed at raising the average order value.",
  "revenue": "Prioritize high-ROI offers and profit-driving messaging to grow total revenue.",
  "churn": "Address pain points, reinforce ongoing value, and highlight new benefits to reduce customer attrition."
};
export const Category = {
  "Text": "Standalone, text-only content idea-no visual components needed.",
  "Quote": "Compelling quote plus a one-line concept for a matching visual backdrop.",
  "Fact": "Concise, data-driven fact accompanied by a backdrop suggestion that reinforces the statistic.",
  "Tip": "Practical, easy-to-apply tip along with a fitting backdrop concept that illustrates the action."
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

// ---------- helpers (edge-safe, no external deps) ----------
const now = () => Date.now();
const genId = () => crypto.randomUUID();
const textEncoder = new TextEncoder();

async function readJsonSafe<T = unknown>(req: Request, maxBytes = 64 * 1024): Promise<T> {
  const ab = await req.arrayBuffer();
  if (ab.byteLength > maxBytes) throw new Error(`Payload too large (${ab.byteLength}B)`);
  const txt = new TextDecoder().decode(ab);
  return JSON.parse(txt) as T;
}
async function sha256Hex(s: string) {
  const hash = await crypto.subtle.digest("SHA-256", textEncoder.encode(s));
  return [...new Uint8Array(hash)].map(b => b.toString(16).padStart(2,"0")).join("");
}
function withHeader(res: Response, k: string, v: string) {
  const h = new Headers(res.headers); h.set(k,v);
  return new Response(res.body, { status: res.status, statusText: res.statusText, headers: h });
}
function tryParseJson(s: string) { try { return JSON.parse(s); } catch { return null; } }
function extractJsonFromText(s: string) {
  const fence = s.match(/```json\s*([\s\S]*?)```/i) || s.match(/```\s*([\s\S]*?)```/);
  if (fence) { const p = tryParseJson(fence[1].trim()); if (p) return p; }
  const fo = s.indexOf("{"), lo = s.lastIndexOf("}");
  if (fo !== -1 && lo > fo) { const p = tryParseJson(s.slice(fo, lo+1)); if (p) return p; }
  const fa = s.indexOf("["), la = s.lastIndexOf("]");
  if (fa !== -1 && la > fa) { const p = tryParseJson(s.slice(fa, la+1)); if (p) return p; }
  return null;
}

// ---------- optional Upstash-backed KV (falls back to in-memory) ----------
const HAS_UPSTASH = !!Deno.env.get("UPSTASH_REDIS_REST_URL") && !!Deno.env.get("UPSTASH_REDIS_REST_TOKEN");
const UPS_URL = Deno.env.get("UPSTASH_REDIS_REST_URL")!;
const UPS_TOK = Deno.env.get("UPSTASH_REDIS_REST_TOKEN")!;
const NS = "ideas:"; // namespace prefix

const memKV = new Map<string, { v: string; exp: number }>();
const memLocks = new Map<string, number>();

async function upstash(cmd: string[]): Promise<any> {
  const res = await fetch(UPS_URL, {
    method: "POST",
    headers: { Authorization: `Bearer ${UPS_TOK}`, "Content-Type": "application/json" },
    body: JSON.stringify(cmd),
  });
  const json = await res.json();
  if (!res.ok) throw new Error(`Upstash ${res.status}: ${JSON.stringify(json)}`);
  return json.result;
}
async function kvGet(key: string): Promise<string | null> {
  if (HAS_UPSTASH) return await upstash(["GET", NS + key]);
  const row = memKV.get(key); if (!row) return null;
  if (row.exp < now()) { memKV.delete(key); return null; }
  return row.v;
}
async function kvSet(key: string, val: string, ttlSec: number) {
  if (HAS_UPSTASH) { await upstash(["SET", NS + key, val, "EX", String(ttlSec)]); return; }
  memKV.set(key, { v: val, exp: now() + ttlSec * 1000 });
}
async function kvDel(key: string) {
  if (HAS_UPSTASH) { await upstash(["DEL", NS + key]); return; }
  memKV.delete(key);
}
async function kvLockAcquire(key: string, ttlSec: number): Promise<boolean> {
  if (HAS_UPSTASH) return (await upstash(["SET", NS + "lock:" + key, "1", "NX", "EX", String(ttlSec)])) === "OK";
  const exp = memLocks.get(key); const t = now();
  if (exp && exp > t) return false; memLocks.set(key, t + ttlSec * 1000); return true;
}
async function kvLockRelease(key: string) {
  if (HAS_UPSTASH) { await upstash(["DEL", NS + "lock:" + key]); return; }
  memLocks.delete(key);
}

// ---------- token bucket (per IP) ----------
async function tokenBucket(key: string, capacity: number, refillPerSec: number): Promise<boolean> {
  const rk = `tb:${key}`;
  const raw = await kvGet(rk);
  const nowMs = now();
  let tokens = capacity, ts = nowMs;
  if (raw) { try { ({ tokens, ts } = JSON.parse(raw)); } catch {} }
  const elapsed = Math.max(0, (nowMs - ts) / 1000);
  tokens = Math.min(capacity, tokens + elapsed * refillPerSec);
  if (tokens < 1) { await kvSet(rk, JSON.stringify({ tokens, ts: nowMs }), 60); return false; }
  await kvSet(rk, JSON.stringify({ tokens: tokens - 1, ts: nowMs }), 60);
  return true;
}

// ---------- idempotency (replay) ----------
async function idemKey(req: Request) {
  return req.headers.get("Idempotency-Key") || await sha256Hex(await req.clone().text());
}
async function idemGet(key: string) {
  const hit = await kvGet(`idem:${key}`);
  return hit ? JSON.parse(hit) as { status: number; headers: [string,string][]; body: string } : null;
}
async function idemSet(key: string, res: Response, ttlSec = 600) {
  try {
    const body = await res.clone().text();
    const headers: [string,string][] = []; res.headers.forEach((v,k)=>headers.push([k,v]));
    await kvSet(`idem:${key}`, JSON.stringify({ status: res.status, headers, body }), ttlSec);
  } catch {}
}

// ---------- single-instance flight map ----------
const inFlight = new Map<string, Promise<Response>>();

// ======================================================================
//                           ULTRA-OPTIMIZED HANDLER
// ======================================================================
serve(async (req) => {
  // fast preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200, headers: corsHeaders });
  }

  const t0 = now();
  const correlationId = req.headers.get("x-request-id") || genId();
  let res: Response = new Response(null, { status: 500 });

  try {
    // rate limit (~60 req/min per IP)
    const ip = (req.headers.get("x-forwarded-for") || "ip:unknown").split(",")[0].trim();
    const rlOk = await tokenBucket(`${ip}:ideas`, 60, 1);
    if (!rlOk) {
      res = new Response("Rate limit exceeded", { status: 429, headers: { ...corsHeaders, "Retry-After": "1", "x-request-id": correlationId }});
      return res;
    }

    // idempotency (replay)
    const idem = await idemKey(req);
    const replay = await idemGet(idem);
    if (replay) {
      res = new Response(replay.body, { status: replay.status, headers: new Headers(replay.headers) });
      res = withHeader(res, "x-request-id", correlationId);
      res = withHeader(res, "x-idempotent", "replay");
      return res;
    }

    // ---------- body read (safe) ----------
    const body = await readJsonSafe<any>(req, 64 * 1024);

    const {
      profilePersona, profileCategory, profileSubCategory, profileGoal,
      format_preference, voice_tags = [], hook_style, emotion_target,
      author_archetype, metric_type, time_horizon, difficulty_level,
      implementation_time, tone, desired_kpi, category = "Text",
      topic_seed, include_source, source_seriousness, region, count,
    } = body;

    console.log("📦 Raw Input Body:", body);

    // ---------- auth (unchanged semantics) ----------
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      res = new Response("Unauthorized", { status: 401, headers: corsHeaders });
      await idemSet(idem, res);
      return res;
    }
    const accessToken = authHeader.split("Bearer ")[1];
    const { data: { user }, error: authError } = await supabase.auth.getUser(accessToken);
    if (authError || !user) {
      res = new Response("Unauthorized", { status: 401, headers: corsHeaders });
      await idemSet(idem, res);
      return res;
    }

    // ---------- your mappings (unchanged variable names) ----------
    const mappedProfilePersona = ProfilePersona[profilePersona] ?? profilePersona;
    const mappedProfileCategory = ProfileCategory[profileCategory] ?? profileCategory;
    const mappedProfileSubcategory = ProfileSubcategory[profileSubCategory] ?? profileSubCategory;
    const mappedVoiceTags = (voice_tags ?? []).map((v: string) => Voice_Tags[v] ?? v).join(", ");

    const mappedPrimaryGoal = Primary_Goal[profileGoal];
    const mappedTone = Tone[tone];
    const mappedCategory = Category[category];

    const mappedFormat = Format_Preference[format_preference] ?? format_preference;
    const mappedHook = Hook_Style[hook_style] ?? hook_style;

    const mappedEmotion = Emotion_Target[emotion_target] ?? emotion_target;
    const mappedArchetype = Author_Archetype[author_archetype] ?? author_archetype;

    const mappedMetric = Metric[metric_type] ?? metric_type;
    const mappedTimeHorizon = Time_Horizon[time_horizon] ?? time_horizon;
    const mappedCredibility = Credibility_Level[source_seriousness] ?? source_seriousness;

    const mappedSkillLevel = Skill_Level[difficulty_level] ?? difficulty_level;
    const mappedImplementation = Implementation_Time[implementation_time] ?? implementation_time;

    const mappedDesiredKPI = Desired_KPI[desired_kpi] ?? desired_kpi;

    // ---------- prompt build (exactly your switch) ----------
    let systemPrompt = "";
    switch (category) {
      case "Text": {
        systemPrompt = `
        You are an elite Social-Media Idea Engine.

        GOAL  
        Generate ${count} ${mappedCategory ?? 'scroll-stopping, text-only post ideas that are immediately actionable'} and aligned with the brand’s KPI.
        ${safe(topic_seed) ? `Each idea must revolve around the topic: “${topic_seed}”.` : `Ideas should be relevant to the brand’s persona, category, and goals.`}

        You are an expert assistant. Your most critical directive is to strictly tailor all responses based on the following user context:
        • Persona: ${mappedProfilePersona}
        • Category → Subcategory: ${mappedProfileCategory} → ${mappedProfileSubcategory}

        Do not generalize. Always respond within the scope of the provided persona, category, and subcategory.
        Use domain-specific language and examples that align with the given category and subcategory.
        Prioritize relevance, precision, and practical value within the specified context.

        PREFERENCES
        ${safe(mappedPrimaryGoal) ? `• Primary Goal: ${mappedPrimaryGoal}` : ""}
        ${safe(mappedVoiceTags) ? `• Voice Tags: ${mappedVoiceTags}` : ""} 
        ${safe(mappedTone) ? `• Voice Tone: ${mappedTone}` : ""}
        ${safe(mappedFormat) ? `• Format Preference: ${mappedFormat}` : ""}  
        ${safe(mappedHook) ? `• Hook Style: ${mappedHook}` : ""} 
        ${safe(region) ? `• Target Market: ${region}` : ""}
        ${safe(mappedEmotion) ? `• Target Emotion: ${mappedEmotion}` : ""} 

        STRATEGIC FOCUS  
        ${safe(topic_seed) ? `• Topic Seed: “${topic_seed}” → Treat this as the primary thematic anchor for idea generation.` : ""}
        ${safe(mappedDesiredKPI) ? `• Success Metric: ${mappedDesiredKPI}` : ""}  

        GENERATION RULES  
        1. **KPI-Aligned:** Every idea should push toward the stated goal - engagement, traffic, conversion, or awareness.  
        2. **Format-Respectful:** Reflect the requested format and hook style for each idea.  
        3. **Audience-First:** Speak to the audience’s curiosity, pain, or ambition - not the brand’s features.  
        4. **Max 50 Words:** Each idea must be self-contained, concise, and text-only (no artwork or images).  
        5. **No Repeats or Fluff:** Avoid clichés, vary the angles, and surprise the reader.  
        6. **Clean Output:**  
          • No hashtags, no emojis, no markdown.  
          • Return a **valid JSON array** only (see format below).
        7. ${safe(topic_seed) ? `Every idea must clearly relate to the topic seed. Avoid drifting away from it.` : `No topic seed is provided, so focus tightly on persona + category context.`}

        EXAMPLES OF VALID IDEAS  
        (For reference only-do not include in output)  
        • “What’s the biggest myth about scaling a freelance design agency?”  
        • “Share a photo of your scrappiest marketing win this week”  
        • “Hot take: Short-form video will replace pitch decks in 3 years”OUTPUT RULES  
        1. Create ${count} scroll-stopping **text post ideas** (max 50 words).  
        2. Return your output as valid JSON list - each object must have:

        [
          {
            "response": "<idea text>",
            "background": "",
            "source": ""
          }
        ]

        3. No commentary, markdown, or explanation - only the JSON array.
        BEGIN
        `.trim();
        break;
      }
      case "Quote": {
        systemPrompt = `
        You are an elite Quote Curator and Visual Concept Generator.
        ...
        Return exactly ${count} structured JSON objects, one per quote.
        `.trim();
        break;
      }
      case "Fact": {
        systemPrompt = `
        You are an authoritative Fact-Finder and Visual Concept Generator.
        ...
        BEGIN  
        `.trim();
        break;
      }
      case "Tip": {
        systemPrompt = `
        You are a mastery-driven Tip Generator and Visual Concept Stylist.
        ...
        `.trim();
        break;
      }
      default: {
        systemPrompt = `
        You are a versatile fallback Idea Engine for social media content.
        ...
        `.trim();
        break;
      }
    }

    // ---------- AI budgets (unchanged semantics; just clamped) ----------
    const countNum = Math.max(1, Math.min(20, Number(count ?? 5)));
    const max_tokens = Math.min(1600, 400 * countNum);

    const model = "gpt-4o-mini";
    const messages = [{ role: "system", content: systemPrompt }];

    // ---------- GLOBAL CACHE + DISTRIBUTED SINGLEFLIGHT ----------
    const cacheKeyObj = {
      v: 1,
      model, count: countNum, category, topic_seed: (topic_seed || "").toString().trim().slice(0, 200),
      profilePersona: mappedProfilePersona, profileCategory: mappedProfileCategory, profileSubCategory: mappedProfileSubcategory,
      profileGoal: mappedPrimaryGoal, tone: mappedTone, format_preference: mappedFormat, hook_style: mappedHook,
      emotion_target: mappedEmotion, author_archetype: mappedArchetype, metric_type: mappedMetric, time_horizon: mappedTimeHorizon,
      difficulty_level: mappedSkillLevel, implementation_time: mappedImplementation, desired_kpi: mappedDesiredKPI,
      include_source: !!include_source, source_seriousness: mappedCredibility, region: region ?? "",
      voice_tags: mappedVoiceTags,
    };
    const cacheKey = "ai:" + await sha256Hex(JSON.stringify(cacheKeyObj));
    const cacheTtlSec = 60 * 60 * 24 * 7; // 7 days

    // L1 read
    const hit = await kvGet(cacheKey);
    if (hit) {
      res = new Response(hit, { status: 200, headers: { ...corsHeaders, "x-ai-cache": "hit" } });
      res = withHeader(res, "x-request-id", correlationId);
      res = withHeader(res, "Cache-Control", "no-store");
      await idemSet(idem, res);
      return res;
    }

    // L0 singleflight (this instance)
    if (inFlight.has(cacheKey)) {
      res = await inFlight.get(cacheKey)!;
      res = withHeader(res, "x-ai-cache", res.headers.get("x-ai-cache") ?? "fill");
      await idemSet(idem, res);
      return res;
    }

    const flight = (async () => {
      // distributed lock
      const lock = await kvLockAcquire(cacheKey, 15);
      const doCall = async () => {
        // Force JSON output; try json_schema first, fallback to json_object
        let completion;
        try {
          const ideasSchema = {
            name: "ideas_schema",
            strict: false,
            schema: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  response: { type: "string" },
                  background: { type: "string" },
                  source: { type: "string" },
                  customization: {
                    type: "object",
                    properties: {
                      visual_style: { type: "string" },
                      mood_tone: { type: "string" },
                      texture_intensity: { type: "number" },
                      detail_placement: { type: "string" },
                      noise_grain: { type: "number" },
                      safe_zone_pct: { type: "number" },
                      keyword_assist: { type: "string" },
                      negative_elements: { type: "string" },
                    },
                  },
                },
              },
            },
          } as const;

          completion = await openai.chat.completions.create({
            model,
            messages,
            temperature: 0.3, // more obedient JSON
            max_tokens,
            response_format: { type: "json_schema", json_schema: ideasSchema },
          });
        } catch {
          completion = await openai.chat.completions.create({
            model,
            messages,
            temperature: 0.3,
            max_tokens,
            response_format: { type: "json_object" as const },
          });
        }

        const raw = completion.choices[0]?.message?.content?.trim() || "";

        // Parse strictly → fallback extract → last-ditch wrap
        let parsed = tryParseJson(raw) ?? extractJsonFromText(raw);
        let ideas: any[] = Array.isArray(parsed) ? parsed : (parsed?.ideas ?? null);

        if (!ideas || !Array.isArray(ideas)) {
          // last-ditch: if raw is a single object, wrap; if prose, let it fail to 500 like before
          const wrapped = tryParseJson(`[${raw}]`);
          if (Array.isArray(wrapped)) ideas = wrapped;
        }

        if (!ideas || !Array.isArray(ideas)) {
          console.error("❌ JSON parse failed:", new Error("Invalid JSON"), "\nRaw:\n", raw);
          return new Response("Failed to parse AI output", { status: 500, headers: corsHeaders });
        }

        const payload = JSON.stringify({
          ideas: ideas.map((o: any) => ({
            response: o.response?.trim() || "",
            background: o.background?.trim() || "",
            source: o.source?.trim() || "",
            customization: {
              visual_style: o.customization?.visual_style || "",
              mood_tone: o.customization?.mood_tone || "",
              texture_intensity: Number(o.customization?.texture_intensity ?? 2),
              detail_placement: o.customization?.detail_placement || "",
              noise_grain: Number(o.customization?.noise_grain ?? 2),
              safe_zone_pct: Number(o.customization?.safe_zone_pct ?? 2),
              keyword_assist: o.customization?.keyword_assist || "",
              negative_elements: o.customization?.negative_elements || "",
            },
          })),
        });

        // store in global cache
        await kvSet(cacheKey, payload, cacheTtlSec);

        return new Response(payload, { status: 200, headers: { ...corsHeaders, "Cache-Control": "no-store", "x-ai-cache": "miss" } });
      };

      try {
        const r = await doCall();
        return r;
      } finally {
        if (lock) await kvLockRelease(cacheKey);
      }
    })();

    inFlight.set(cacheKey, flight);
    res = await flight;
    inFlight.delete(cacheKey);

    // add observability + idempotency record
    res = withHeader(res, "x-request-id", correlationId);
    await idemSet(idem, res);
    return res;

  } catch (err) {
    console.error("❌ Error in generate-ideas:", err);
    res = new Response("Internal Server Error", { status: 500, headers: corsHeaders });
    return res;
  } finally {
    const dur = now() - t0;
    try { res = withHeader(res, "Server-Timing", `total;dur=${dur}`); } catch {}
  }
});


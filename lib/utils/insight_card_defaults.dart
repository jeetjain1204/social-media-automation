// ---------------------------------------------------------------------------
// Data class holding the UI defaults communicated to the generator page.
// ---------------------------------------------------------------------------
class InsightCardDefaults {
  final String selectedAspectRatio; // '1:1' | '4:5' | '9:16' | '16:9'
  final String selectedStylePreset; // 'Photo' … 'Memphis Pattern'
  final String selectedTone; // 'Friendly Pastel' … 'Dark Moody'
  final bool useBrandPaletteColors; // toggle
  final int textureIntensity; // 0-100
  final String selectedDetailPlacement; // 'Center Focus' …
  final int noiseLevel; // 0-20
  final String keywordAssist; // optional visual cue (empty default)
  final List<String> negativeElements; // chip array (empty default)

  const InsightCardDefaults({
    required this.selectedAspectRatio,
    required this.selectedStylePreset,
    required this.selectedTone,
    required this.useBrandPaletteColors,
    required this.textureIntensity,
    required this.selectedDetailPlacement,
    required this.noiseLevel,
    this.keywordAssist = '',
    this.negativeElements = const [],
  });

  InsightCardDefaults copyWith({
    String? selectedAspectRatio,
    String? selectedStylePreset,
    String? selectedTone,
    bool? useBrandPaletteColors,
    int? textureIntensity,
    String? selectedDetailPlacement,
    int? noiseLevel,
    String? keywordAssist,
    List<String>? negativeElements,
  }) {
    return InsightCardDefaults(
      selectedAspectRatio: selectedAspectRatio ?? this.selectedAspectRatio,
      selectedStylePreset: selectedStylePreset ?? this.selectedStylePreset,
      selectedTone: selectedTone ?? this.selectedTone,
      useBrandPaletteColors:
          useBrandPaletteColors ?? this.useBrandPaletteColors,
      textureIntensity: textureIntensity ?? this.textureIntensity,
      selectedDetailPlacement:
          selectedDetailPlacement ?? this.selectedDetailPlacement,
      noiseLevel: noiseLevel ?? this.noiseLevel,
      keywordAssist: keywordAssist ?? this.keywordAssist,
      negativeElements: negativeElements ?? this.negativeElements,
    );
  }
}

extension _Overlay on InsightCardDefaults {
  // Overlay only when source has non-empty strings or non-zero ints; booleans are not overlaid here.
  InsightCardDefaults overlayFrom(InsightCardDefaults src) => copyWith(
        selectedAspectRatio:
            src.selectedAspectRatio.isNotEmpty ? src.selectedAspectRatio : null,
        selectedStylePreset:
            src.selectedStylePreset.isNotEmpty ? src.selectedStylePreset : null,
        selectedTone: src.selectedTone.isNotEmpty ? src.selectedTone : null,
        textureIntensity:
            src.textureIntensity != 0 ? src.textureIntensity : null,
        selectedDetailPlacement: src.selectedDetailPlacement.isNotEmpty
            ? src.selectedDetailPlacement
            : null,
        noiseLevel: src.noiseLevel != 0 ? src.noiseLevel : null,
        // keywordAssist/negativeElements intentionally not overlaid here; original logic didn't.
      );
}

const Map<String, InsightCardDefaults> _traitDefaults = {
  'playful': InsightCardDefaults(
    selectedAspectRatio: '1:1',
    selectedStylePreset: 'Memphis Pattern',
    selectedTone: 'Friendly Pastel',
    useBrandPaletteColors: true,
    textureIntensity: 40,
    selectedDetailPlacement: 'Edge Detail',
    noiseLevel: 5,
  ),
  'professional': InsightCardDefaults(
    selectedAspectRatio: '1:1',
    selectedStylePreset: 'Soft Gradient',
    selectedTone: 'Formal Minimal',
    useBrandPaletteColors: true,
    textureIntensity: 20,
    selectedDetailPlacement: 'Center Focus',
    noiseLevel: 0,
  ),
  'data-centric': InsightCardDefaults(
    selectedAspectRatio: '16:9',
    selectedStylePreset: 'Soft Gradient',
    selectedTone: 'Dark Moody',
    useBrandPaletteColors: true,
    textureIntensity: 20,
    selectedDetailPlacement: 'Center Focus',
    noiseLevel: 5,
  ),
  'high-energy': InsightCardDefaults(
    selectedAspectRatio: '9:16',
    selectedStylePreset: 'Grainy Film',
    selectedTone: 'Bold Neon',
    useBrandPaletteColors: true,
    textureIntensity: 60,
    selectedDetailPlacement: 'Center Focus',
    noiseLevel: 15,
  ),
  'calm': InsightCardDefaults(
    selectedAspectRatio: '4:5',
    selectedStylePreset: 'Photo',
    selectedTone: 'Vintage Warm',
    useBrandPaletteColors: true,
    textureIntensity: 20,
    selectedDetailPlacement: 'Uniform Blur',
    noiseLevel: 0,
  ),
};

// ---------------------------------------------------------------------------
// 2.  Card-type adjustments → overlay on trait default
// ---------------------------------------------------------------------------
const Map<String, InsightCardDefaults> _cardTypeAdj = {
  'Quote': InsightCardDefaults(
    selectedAspectRatio: '',
    selectedStylePreset: '',
    selectedTone: '',
    useBrandPaletteColors: true,
    textureIntensity: 3,
    selectedDetailPlacement: '',
    noiseLevel: 0,
  ),
  'Fact': InsightCardDefaults(
    selectedAspectRatio: '',
    selectedStylePreset: '',
    selectedTone: 'Formal Minimal',
    useBrandPaletteColors: true,
    textureIntensity: 2,
    selectedDetailPlacement: '',
    noiseLevel: 0,
  ),
  'Tip': InsightCardDefaults(
    selectedAspectRatio: '9:16',
    selectedStylePreset: '',
    selectedTone: '',
    useBrandPaletteColors: true,
    textureIntensity: 4,
    selectedDetailPlacement: '',
    noiseLevel: 10,
  ),
};

// ---------------------------------------------------------------------------
// 3.  Sub-category → meta-trait array  (ALL 215 keys included)
//     • Keys are kebab-case (match server schema)
// ---------------------------------------------------------------------------
const _subcategoryTraits = <String, List<String>>{
  /* ───────────────────── SOLO CREATOR ───────────────────── */
  // Comedy
  'skits': ['playful', 'high-energy'],
  'relatable-humor': ['playful'],
  'satire-parody': ['playful'],
  'memes': ['playful', 'high-energy'],
  'reaction-videos': ['playful'],

  // Tech
  'product-reviews': ['professional'],
  'tutorials': ['professional', 'calm'],
  'coding-dev-logs': ['professional', 'data-centric'],
  'ai-tool-demos': ['professional'],
  'hardware-unboxings': ['professional'],

  // Education
  'study-tips': ['calm'],
  'animated-explainers': ['playful'],
  'language-learning': ['calm'],
  'science-experiments': ['data-centric'],
  'history-storytelling': ['calm'],

  // Lifestyle & Vlogs
  'daily-routines': ['calm'],
  'minimalism': ['calm'],
  'home-makeovers': ['calm'],
  'college-life': ['playful'],
  'day-in-the-life': ['calm'],

  // Gaming
  'lets-plays': ['high-energy'],
  'esports-commentary': ['high-energy'],
  'speedruns': ['high-energy', 'data-centric'],
  'game-reviews': ['professional'],
  'stream-highlights': ['high-energy'],

  // Beauty & Fashion
  'makeup-tutorials': ['playful'],
  'outfit-lookbooks': ['playful'],
  'styling-hacks': ['playful'],
  'product-hauls': ['playful'],
  'diy-skincare': ['calm'],

  // Fitness & Wellness
  'home-workouts': ['high-energy'],
  'yoga-meditation': ['calm'],
  'healthy-recipes': ['calm'],
  'transformation-journeys': ['high-energy'],
  'mental-health-chats': ['calm'],

  // Finance & Investing
  'mutual-fund-deep-dives': ['professional', 'data-centric'],
  'stock-picks': ['professional', 'data-centric'],
  'crypto-breakdowns': ['professional', 'data-centric'],
  'budgeting-tips': ['professional'],
  'side-hustle-ideas': ['professional'],

  // Travel & Adventure
  'backpacking-guides': ['playful'],
  'city-walkthroughs': ['playful'],
  'food-tours': ['playful'],
  'cultural-immersion': ['calm'],
  'travel-hacks': ['playful'],

  // Music & Performance
  'original-songs': ['high-energy'],
  'cover-sessions': ['high-energy'],
  'live-looping': ['high-energy'],
  'instrument-tutorials': ['professional'],
  'beat-making': ['high-energy'],

  // Food & Cooking
  'quick-recipes': ['calm'],
  'street-food-reviews': ['playful'],
  'meal-prep': ['calm'],
  'asmr-cooking': ['calm'],
  'international-cuisine': ['calm'],

  // Art & DIY
  'digital-drawing': ['playful', 'calm'],
  'crafts-hacks': ['playful'],
  '3d-printing': ['professional'],
  'resin-art': ['playful', 'calm'],
  'upcycling-projects': ['playful'],

  // Personal Development
  'study-with-me': ['calm'],
  'productivity-systems': ['professional', 'calm'],
  'book-summaries': ['calm'],
  'goal-setting': ['professional', 'calm'],
  'mindfulness': ['calm'],

  /* ───────────────────── SMB FOUNDER ───────────────────── */
  // Fashion & Apparel
  'retail-boutique': ['professional'],
  'wholesale-supplier': ['professional', 'data-centric'],
  'd2c-e-commerce': ['professional'],
  'custom-tailoring': ['professional'],
  'sustainable-fashion': ['professional', 'calm'],

  // Food & Beverage
  'restaurant': ['playful', 'high-energy'],
  'cafe-coffee-bar': ['playful', 'calm'],
  'bakery-desserts': ['playful'],
  'cloud-kitchen': ['professional'],
  'packaged-fmcg': ['professional'],

  // Health & Wellness
  'gym-fitness-studio': ['high-energy'],
  'yoga-center': ['calm'],
  'nutraceutical-brand': ['professional'],
  'spa-wellness': ['calm'],
  'telehealth-clinic': ['professional'],

  // Technology & SaaS
  'b2b-saas': ['professional', 'data-centric'],
  'mobile-app-startup': ['professional'],
  'it-services': ['professional'],
  'cybersecurity': ['professional', 'data-centric'],
  'ai-solutions': ['professional', 'data-centric'],

  // Professional Services
  'legal-firm': ['professional'],
  'accounting-practice': ['professional', 'data-centric'],
  'consulting-agency': ['professional'],
  'architecture-studio': ['professional'],
  'hr-outsourcing': ['professional'],

  // Real Estate & Property
  'residential-brokerage': ['professional'],
  'commercial-leasing': ['professional'],
  'property-management': ['professional'],
  'co-working-spaces': ['professional', 'high-energy'],
  'vacation-rentals': ['professional', 'playful'],

  // Automotive
  'dealership': ['professional'],
  'auto-repair-shop': ['professional'],
  'ev-charging-network': ['professional'],
  'car-rental': ['professional'],
  'auto-parts-e-commerce': ['professional'],

  // Education & Training
  'coaching-center': ['professional', 'calm'],
  'edtech-platform': ['professional'],
  'skill-bootcamp': ['professional', 'high-energy'],
  'corporate-training': ['professional'],
  'test-prep-institute': ['professional'],

  // Creative & Media
  'production-house': ['professional', 'high-energy'],
  'printing-branding': ['professional'],
  'event-management': ['professional', 'high-energy'],
  'advertising-studio': ['professional', 'playful'],
  'influencer-merch': ['playful', 'professional'],

  // Home & Living
  'furniture-manufacturing': ['professional'],
  'interior-design': ['professional'],
  'home-décor-retail': ['professional', 'playful'],
  'smart-home-installers': ['professional'],
  'landscaping': ['calm', 'professional'],

  // Financial Services & FinTech
  'mutual-fund-distributor': ['professional', 'data-centric'],
  'nbfc-micro-finance': ['professional', 'data-centric'],
  'wealth-advisory': ['professional', 'data-centric'],
  'payments-wallets': ['professional', 'data-centric'],
  'insurtech': ['professional', 'data-centric'],

  // Logistics & Supply Chain
  'third-party-logistics': ['professional', 'data-centric'],
  'last-mile-delivery': ['professional', 'data-centric'],
  'cold-chain': ['professional', 'data-centric'],
  'warehousing': ['professional', 'data-centric'],
  'freight-forwarding': ['professional', 'data-centric'],

  // Manufacturing & Industrial
  'fmcg-manufacturing': ['professional'],
  'electronics-assembly': ['professional'],
  'textile-mill': ['professional'],
  'precision-engineering': ['professional'],
  'packaging-plants': ['professional'],

  // Agriculture & AgriTech
  'organic-farming': ['calm', 'professional'],
  'farm-to-table-brand': ['calm', 'professional'],
  'agri-input-supplier': ['professional'],
  'hydroponics': ['professional'],
  'crop-analytics-platform': ['professional', 'data-centric'],

  // Energy & Utilities
  'solar-epc': ['professional', 'data-centric'],
  'ev-infrastructure': ['professional', 'data-centric'],
  'bio-fuel-production': ['professional'],
  'power-distribution': ['professional'],
  'smart-metering': ['professional', 'data-centric'],

  /* ───────────────────── AGENCY / FREELANCER ─────────────── */
  // Marketing & Growth
  'social-media-management': ['professional', 'high-energy'],
  'performance-ads': ['professional', 'data-centric'],
  'email-marketing': ['professional'],
  'growth-hacking': ['professional', 'high-energy'],
  'influencer-collabs': ['playful', 'high-energy'],

  // Design Services
  'ui-ux-design': ['professional', 'calm'],
  'brand-identity': ['professional', 'calm'],
  'motion-graphics': ['playful', 'high-energy'],
  'illustration': ['playful', 'calm'],
  'presentation-design': ['professional', 'calm'],

  // Development & IT
  'web-development': ['professional'],
  'mobile-apps': ['professional'],
  'shopify-e-commerce': ['professional'],
  'api-integrations': ['professional'],
  'devops-cloud': ['professional'],

  // Video & Animation
  'explainer-videos': ['professional', 'playful'],
  'short-form-reels': ['playful', 'high-energy'],
  '3d-animation': ['professional', 'playful'],
  'post-production': ['professional'],
  'livestream-production': ['high-energy'],

  // Writing & Content
  'blog-articles': ['professional', 'calm'],
  'copywriting': ['professional'],
  'technical-writing': ['professional', 'data-centric'],
  'scriptwriting': ['professional', 'playful'],
  'ghostwriting': ['professional', 'calm'],

  // Photography & Creative Media
  'product-photography': ['professional'],
  'lifestyle-shoots': ['playful'],
  'event-coverage': ['high-energy', 'professional'],
  'drone-filming': ['high-energy', 'professional'],
  'stock-photo-sets': ['professional'],

  // Consulting & Strategy
  'brand-positioning': ['professional'],
  'gtm-strategy': ['professional'],
  'market-research': ['professional', 'data-centric'],
  'pricing-optimization': ['professional', 'data-centric'],
  'investor-pitch-decks': ['professional'],

  // Translation & Localization
  'multilingual-copy': ['professional'],
  'subtitle-captioning': ['professional'],
  'app-localization': ['professional'],
  'voiceover-dubbing': ['professional'],
  'cultural-adaptation': ['professional'],

  // Data & Analytics
  'dashboard-building': ['professional', 'data-centric'],
  'cro-audits': ['professional', 'data-centric'],
  'seo-analytics': ['professional', 'data-centric'],
  'attribution-modeling': ['professional', 'data-centric'],
  'a-b-testing': ['professional', 'data-centric'],

  // Virtual Assistance
  'calendar-management': ['professional', 'calm'],
  'crm-upkeep': ['professional', 'calm'],
  'invoicing-bookkeeping': ['professional', 'calm'],
  'customer-support': ['professional', 'calm'],
  'lead-prospecting': ['professional', 'high-energy'],

  // Finance & Legal Advisory
  'fractional-cfo': ['professional', 'data-centric'],
  'tax-advisory': ['professional', 'data-centric'],
  'fundraising-support': ['professional'],
  'compliance-filings': ['professional'],
  'm-a-due-diligence': ['professional', 'data-centric'],

  // HR & Talent Services
  'recruitment-process-outsourcing': ['professional'],
  'employer-branding': ['professional'],
  'payroll-management': ['professional', 'data-centric'],
  'l-d-programs': ['professional', 'calm'],
  'staff-augmentation': ['professional'],

  // Product & CX Research
  'user-interviews': ['professional', 'calm'],
  'prototype-testing': ['professional', 'data-centric'],
  'customer-journey-mapping': ['professional', 'calm'],
  'nps-surveys': ['professional', 'data-centric'],
  'feature-prioritization': ['professional', 'data-centric'],

  // Audio & Podcast Production
  'podcast-editing': ['professional', 'calm'],
  'jingle-composition': ['playful'],
  'sound-design': ['professional'],
  'voice-acting': ['playful'],
  'audiobook-production': ['professional', 'calm'],

  // AR/VR & Immersive Tech
  'ar-filters': ['playful', 'high-energy'],
  'vr-training-sims': ['professional', 'data-centric'],
  '3d-asset-creation': ['professional'],
  'metaverse-events': ['professional', 'high-energy'],
  'virtual-showrooms': ['professional'],
};

final Map<String, InsightCardDefaults> _subcategoryBaseCache = {};

InsightCardDefaults _baseForSubcategory(String subcategory) {
  final cached = _subcategoryBaseCache[subcategory];
  if (cached != null) return cached;

  // Trait matching (default to professional)
  final traits = _subcategoryTraits[subcategory] ?? const ['professional'];
  // Primary trait is guaranteed (after default above)
  final primary = _traitDefaults[traits.first]!;

  InsightCardDefaults merged = primary;
  if (traits.length > 1) {
    final secondary = _traitDefaults[traits[1]]!;
    // Apply secondary only where primary did not define (empty/zero), matching original logic.
    merged = merged.overlayFrom(secondary);
  }

  _subcategoryBaseCache[subcategory] = merged;
  return merged;
}

// ---------------------------------------------------------------------------
// 4.  Resolver
// ---------------------------------------------------------------------------
InsightCardDefaults resolveInsightCardDefaults({
  required String subcategory, // kebab-case   e.g. 'crypto-breakdowns'
  required String cardType, // 'Quote' | 'Fact' | 'Tip'
  bool useBrandPalette = true, // user toggle
}) {
  // Base from traits (possibly cached)
  final base = _baseForSubcategory(subcategory);

  // Card-type adjustments (non-empty/non-zero overlays only)
  final adj = _cardTypeAdj[cardType] ??
      const InsightCardDefaults(
        selectedAspectRatio: '',
        selectedStylePreset: '',
        selectedTone: '',
        useBrandPaletteColors: true,
        textureIntensity: 0,
        selectedDetailPlacement: '',
        noiseLevel: 0,
      );

  final withCardType = base.overlayFrom(adj);

  // Brand palette toggle last (explicit user choice)
  return withCardType.copyWith(useBrandPaletteColors: useBrandPalette);
}

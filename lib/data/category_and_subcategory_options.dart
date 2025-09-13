List<String> getCategoryOptions(String persona) {
  switch (persona.toLowerCase()) {
    case 'solo creator':
      return [
        'Comedy',
        'Tech',
        'Education',
        'Lifestyle & Vlogs',
        'Gaming',
        'Beauty & Fashion',
        'Fitness & Wellness',
        'Finance & Investing',
        'Travel & Adventure',
        'Music & Performance',
        'Food & Cooking',
        'Art & DIY',
        'Personal Development',
      ];
    case 'smb founder':
      return [
        'Fashion & Apparel',
        'Food & Beverage',
        'Health & Wellness',
        'Technology & SaaS',
        'Professional Services',
        'Real Estate & Property',
        'Automotive',
        'Education & Training',
        'Creative & Media',
        'Home & Living',
        'Financial Services & FinTech',
        'Logistics & Supply Chain',
        'Manufacturing & Industrial',
        'Agriculture & AgriTech',
        'Energy & Utilities',
      ];
    case 'agency freelancer':
      return [
        'Marketing & Growth',
        'Design Services',
        'Development & IT',
        'Video & Animation',
        'Writing & Content',
        'Photography & Creative Media',
        'Consulting & Strategy',
        'Translation & Localization',
        'Data & Analytics',
        'Virtual Assistance & Admin',
        'Finance & Legal Advisory',
        'HR & Talent Services',
        'Product & CX Research',
        'Audio & Podcast Production',
        'AR/VR & Immersive Tech',
      ];
    default:
      return [];
  }
}

List<String> getSubcategoryOptions(String category) {
  switch (category.toLowerCase()) {
    // Solo Creator
    case 'comedy':
      return [
        'Skits',
        'Relatable Humor',
        'Satire & Parody',
        'Memes',
        'Reaction Videos'
      ];
    case 'tech':
      return [
        'Product Reviews',
        'Tutorials',
        'Coding & Dev Logs',
        'AI Tool Demos',
        'Hardware Unboxings'
      ];
    case 'education':
      return [
        'Study Tips',
        'Animated Explainers',
        'Language Learning',
        'Science Experiments',
        'History Storytelling'
      ];
    case 'lifestyle & vlogs':
      return [
        'Daily Routines',
        'Minimalism',
        'Home Makeovers',
        'College Life',
        'Day-in-the-Life'
      ];
    case 'gaming':
      return [
        'Let’s Plays',
        'Esports Commentary',
        'Speedruns',
        'Game Reviews',
        'Stream Highlights'
      ];
    case 'beauty & fashion':
      return [
        'Makeup Tutorials',
        'Outfit Lookbooks',
        'Styling Hacks',
        'Product Hauls',
        'DIY Skincare'
      ];
    case 'fitness & wellness':
      return [
        'Home Workouts',
        'Yoga & Meditation',
        'Healthy Recipes',
        'Transformation Journeys',
        'Mental-Health Chats'
      ];
    case 'finance & investing':
      return [
        'Mutual-Fund Deep-Dives',
        'Stock Picks',
        'Crypto Breakdowns',
        'Budgeting Tips',
        'Side-Hustle Ideas'
      ];
    case 'travel & adventure':
      return [
        'Backpacking Guides',
        'City Walkthroughs',
        'Food Tours',
        'Cultural Immersion',
        'Travel Hacks'
      ];
    case 'music & performance':
      return [
        'Original Songs',
        'Cover Sessions',
        'Live Looping',
        'Instrument Tutorials',
        'Beat Making'
      ];
    case 'food & cooking':
      return [
        'Quick Recipes',
        'Street-Food Reviews',
        'Meal Prep',
        'ASMR Cooking',
        'International Cuisine'
      ];
    case 'art & diy':
      return [
        'Digital Drawing',
        'Crafts & Hacks',
        '3-D Printing',
        'Resin Art',
        'Up-cycling Projects'
      ];
    case 'personal development':
      return [
        'Study-With-Me',
        'Productivity Systems',
        'Book Summaries',
        'Goal-Setting',
        'Mindfulness'
      ];

    // SMB Founder
    case 'fashion & apparel':
      return [
        'Retail Boutique',
        'Wholesale Supplier',
        'D2C E-commerce',
        'Custom Tailoring',
        'Sustainable Fashion'
      ];
    case 'food & beverage':
      return [
        'Restaurant',
        'Cafe',
        'Bakery & Desserts',
        'Cloud Kitchen',
        'Packaged FMCG'
      ];
    case 'health & wellness':
      return [
        'Gym / Fitness Studio',
        'Yoga Center',
        'Nutraceutical Brand',
        'Spa & Wellness',
        'Telehealth Clinic'
      ];
    case 'technology & saas':
      return [
        'B2B SaaS',
        'Mobile-App Startup',
        'IT Services',
        'Cybersecurity',
        'AI Solutions'
      ];
    case 'professional services':
      return [
        'Legal Firm',
        'Accounting Practice',
        'Consulting Agency',
        'Architecture Studio',
        'HR Outsourcing'
      ];
    case 'real estate & property':
      return [
        'Residential Brokerage',
        'Commercial Leasing',
        'Property Management',
        'Co-Working Spaces',
        'Vacation Rentals'
      ];
    case 'automotive':
      return [
        'Dealership',
        'Auto-Repair Shop',
        'EV-Charging Network',
        'Car Rental',
        'Auto-Parts E-commerce'
      ];
    case 'education & training':
      return [
        'Coaching Center',
        'EdTech Platform',
        'Skill Bootcamp',
        'Corporate Training',
        'Test-Prep Institute'
      ];
    case 'creative & media':
      return [
        'Production House',
        'Printing & Branding',
        'Event Management',
        'Advertising Studio',
        'Influencer Merch'
      ];
    case 'home & living':
      return [
        'Furniture Manufacturing',
        'Interior Design',
        'Home-Decor Retail',
        'Smart-Home Installers',
        'Landscaping'
      ];
    case 'financial services & fintech':
      return [
        'Mutual-Fund Distributor',
        'NBFC / Micro-Finance',
        'Wealth-Advisory',
        'Payments & Wallets',
        'InsurTech'
      ];
    case 'logistics & supply chain':
      return [
        'Third-Party Logistics (3PL)',
        'Last-Mile Delivery',
        'Cold-Chain',
        'Warehousing',
        'Freight Forwarding'
      ];
    case 'manufacturing & industrial':
      return [
        'FMCG Manufacturing',
        'Electronics Assembly',
        'Textile Mill',
        'Precision Engineering',
        'Packaging Plants'
      ];
    case 'agriculture & agritech':
      return [
        'Organic Farming',
        'Farm-to-Table Brand',
        'Agri-Input Supplier',
        'Hydroponics',
        'Crop-Analytics Platform'
      ];
    case 'energy & utilities':
      return [
        'Solar EPC',
        'EV Infrastructure',
        'Bio-Fuel Production',
        'Power Distribution',
        'Smart-Metering'
      ];

    // Agency / Freelancer
    case 'marketing & growth':
      return [
        'Social-Media Management',
        'Performance Ads',
        'Email Marketing',
        'Growth Hacking',
        'Influencer Collabs'
      ];
    case 'design services':
      return [
        'UI/UX Design',
        'Brand Identity',
        'Motion Graphics',
        'Illustration',
        'Presentation Design'
      ];
    case 'development & it':
      return [
        'Web Development',
        'Mobile Apps',
        'Shopify & E-commerce',
        'API Integrations',
        'DevOps & Cloud'
      ];
    case 'video & animation':
      return [
        'Explainer Videos',
        'Short-Form Reels',
        '3-D Animation',
        'Post-Production',
        'Livestream Production'
      ];
    case 'writing & content':
      return [
        'Blog Articles',
        'Copywriting',
        'Technical Writing',
        'Scriptwriting',
        'Ghostwriting'
      ];
    case 'photography & creative media':
      return [
        'Product Photography',
        'Lifestyle Shoots',
        'Event Coverage',
        'Drone Filming',
        'Stock-Photo Sets'
      ];
    case 'consulting & strategy':
      return [
        'Brand Positioning',
        'GTM Strategy',
        'Market Research',
        'Pricing Optimization',
        'Investor Pitch Decks'
      ];
    case 'translation & localization':
      return [
        'Multilingual Copy',
        'Subtitle & Captioning',
        'App Localization',
        'Voice-over Dubbing',
        'Cultural Adaptation'
      ];
    case 'data & analytics':
      return [
        'Dashboard Building',
        'CRO Audits',
        'SEO Analytics',
        'Attribution Modeling',
        'A/B Testing'
      ];
    case 'virtual assistance & admin':
      return [
        'Calendar Management',
        'CRM Upkeep',
        'Invoicing & Bookkeeping',
        'Customer Support',
        'Lead Prospecting'
      ];
    case 'finance & legal advisory':
      return [
        'Fractional CFO',
        'Tax Advisory',
        'Fundraising Support',
        'Compliance Filings',
        'M&A Due Diligence'
      ];
    case 'hr & talent services':
      return [
        'Recruitment Process Outsourcing',
        'Employer Branding',
        'Payroll Management',
        'L&D Programs',
        'Staff Augmentation'
      ];
    case 'product & cx research':
      return [
        'User Interviews',
        'Prototype Testing',
        'Customer Journey Mapping',
        'NPS Surveys',
        'Feature Prioritization'
      ];
    case 'audio & podcast production':
      return [
        'Podcast Editing',
        'Jingle Composition',
        'Sound Design',
        'Voice-acting',
        'Audiobook Production'
      ];
    case 'ar/vr & immersive tech':
      return [
        'AR Filters',
        'VR Training Sims',
        '3-D Asset Creation',
        'Metaverse Events',
        'Virtual Showrooms'
      ];

    default:
      return ['General'];
  }
}

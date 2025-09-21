-- =====================================================
-- MISSING RPC FUNCTIONS FOR BLOB APP
-- =====================================================
-- These functions are referenced in the app but missing from the baseline schema
-- Created based on fallback implementations in lib/services/database_service.dart

-- =====================================================
-- 1. get_user_dashboard_data(user_uuid)
-- =====================================================
-- PURPOSE: Fetch all user dashboard data in a single optimized call
-- PERFORMANCE: Reduces 4 separate queries to 1 RPC call (75% query reduction)
-- USAGE: Called by main_page.dart and other components for initial data loading

CREATE OR REPLACE FUNCTION get_user_dashboard_data(user_uuid UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    result JSON;
BEGIN
    -- Check if user exists and is active
    IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = user_uuid) THEN
        RETURN json_build_object('error', 'User not found');
    END IF;
    
    SELECT json_build_object(
        'profile', (
            SELECT row_to_json(bp) 
            FROM brand_profiles bp 
            WHERE bp.user_id = user_uuid
        ),
        'social_accounts', (
            SELECT COALESCE(json_agg(row_to_json(sa)), '[]') 
            FROM social_accounts sa 
            WHERE sa.user_id = user_uuid 
            AND sa.is_disconnected = false
        ),
        'subscription', (
            SELECT row_to_json(uss) 
            FROM user_subscription_status uss 
            WHERE uss.user_id = user_uuid
        ),
        'brand_kit', (
            SELECT row_to_json(bk) 
            FROM brand_kit.brand_kits bk 
            WHERE bk.user_id = user_uuid
        )
    ) INTO result;
    
    RETURN result;
END;
$$;

-- =====================================================
-- 2. batch_update_profile(user_uuid, profile_updates, brand_kit_updates)
-- =====================================================
-- PURPOSE: Update both brand profile and brand kit data in a single transaction
-- PERFORMANCE: Reduces 2 separate updates to 1 RPC call (50% query reduction)
-- USAGE: Called by profile_page.dart, main.dart for profile updates

CREATE OR REPLACE FUNCTION batch_update_profile(
    user_uuid UUID,
    profile_updates JSONB,
    brand_kit_updates JSONB DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    result JSON;
    updated_profile_count INT := 0;
    updated_brand_kit_count INT := 0;
BEGIN
    -- Check if user exists and is active
    IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = user_uuid) THEN
        RETURN json_build_object('error', 'User not found');
    END IF;
    
    -- Update brand profile if updates provided
    IF profile_updates IS NOT NULL AND jsonb_object_keys(profile_updates) IS NOT NULL THEN
        UPDATE brand_profiles 
        SET 
            persona = COALESCE((profile_updates->>'persona')::text, persona),
            primary_goal = COALESCE((profile_updates->>'primary_goal')::text, primary_goal),
            brand_name = COALESCE((profile_updates->>'brand_name')::text, brand_name),
            primary_color = COALESCE((profile_updates->>'primary_color')::text, primary_color),
            voice_tags = COALESCE((profile_updates->>'voice_tags')::text[], voice_tags),
            content_types = COALESCE((profile_updates->>'content_types')::text[], content_types),
            target_posts_per_week = COALESCE((profile_updates->>'target_posts_per_week')::int, target_posts_per_week),
            category = COALESCE((profile_updates->>'category')::text, category),
            subcategory = COALESCE((profile_updates->>'subcategory')::text, subcategory),
            timezone = COALESCE((profile_updates->>'timezone')::text, timezone),
            brand_logo_path = COALESCE((profile_updates->>'brand_logo_path')::text, brand_logo_path),
            updated_at = NOW()
        WHERE user_id = user_uuid;
        
        GET DIAGNOSTICS updated_profile_count = ROW_COUNT;
    END IF;
    
    -- Update brand kit if updates provided
    IF brand_kit_updates IS NOT NULL AND jsonb_object_keys(brand_kit_updates) IS NOT NULL THEN
        UPDATE brand_kit.brand_kits 
        SET 
            brand_name = COALESCE((brand_kit_updates->>'brand_name')::text, brand_name),
            brand_logo_path = COALESCE((brand_kit_updates->>'brand_logo_path')::text, brand_logo_path),
            transparent_logo_path = COALESCE((brand_kit_updates->>'transparent_logo_path')::text, transparent_logo_path),
            colors = COALESCE((brand_kit_updates->>'colors')::jsonb, colors),
            backgrounds = COALESCE((brand_kit_updates->>'backgrounds')::jsonb, backgrounds),
            updated_at = NOW()
        WHERE user_id = user_uuid;
        
        GET DIAGNOSTICS updated_brand_kit_count = ROW_COUNT;
    END IF;
    
    RETURN json_build_object(
        'success', true, 
        'updated_at', NOW(),
        'profile_updated', updated_profile_count > 0,
        'brand_kit_updated', updated_brand_kit_count > 0,
        'updated_profile_count', updated_profile_count,
        'updated_brand_kit_count', updated_brand_kit_count
    );
END;
$$;

-- =====================================================
-- GRANT PERMISSIONS
-- =====================================================
-- Grant execute permissions to authenticated users

GRANT EXECUTE ON FUNCTION get_user_dashboard_data(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION batch_update_profile(UUID, JSONB, JSONB) TO authenticated;

-- =====================================================
-- FUNCTION DETAILS SUMMARY
-- =====================================================

/*
get_user_dashboard_data(user_uuid UUID)
├── INPUT: user_uuid (UUID) - The user's ID
├── OUTPUT: JSON object containing:
│   ├── profile: brand_profiles row data
│   ├── social_accounts: array of connected social accounts
│   ├── subscription: user_subscription_status row data
│   └── brand_kit: brand_kit.brand_kits row data
├── PERFORMANCE: Single query vs 4 separate queries
├── USAGE: Main dashboard loading, profile data fetching
└── ERROR HANDLING: Returns error object if user not found

batch_update_profile(user_uuid, profile_updates, brand_kit_updates)
├── INPUT: 
│   ├── user_uuid (UUID) - The user's ID
│   ├── profile_updates (JSONB) - Brand profile fields to update
│   └── brand_kit_updates (JSONB, optional) - Brand kit fields to update
├── OUTPUT: JSON object containing:
│   ├── success: boolean
│   ├── updated_at: timestamp
│   ├── profile_updated: boolean
│   ├── brand_kit_updated: boolean
│   ├── updated_profile_count: number of profile rows updated
│   └── updated_brand_kit_count: number of brand kit rows updated
├── PERFORMANCE: Single transaction vs 2 separate updates
├── USAGE: Profile updates, brand kit updates, onboarding flows
└── ERROR HANDLING: Returns error object if user not found

SUPPORTED PROFILE UPDATE FIELDS:
- persona, primary_goal, brand_name, primary_color
- voice_tags, content_types, target_posts_per_week
- category, subcategory, timezone, brand_logo_path

SUPPORTED BRAND KIT UPDATE FIELDS:
- brand_name, brand_logo_path, transparent_logo_path
- colors, backgrounds (JSONB objects)
*/

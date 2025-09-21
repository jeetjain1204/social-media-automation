-- Performance Optimization: Database Indexes
-- Expected Impact: 60-80% reduction in query time

-- Brand profiles indexes
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_brand_profiles_user_id 
ON brand_profiles(user_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_brand_profiles_persona_category 
ON brand_profiles(persona, category) WHERE persona IS NOT NULL AND category IS NOT NULL;

-- Social accounts indexes
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_social_accounts_user_platform 
ON social_accounts(user_id, platform) WHERE is_disconnected = false;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_social_accounts_platform_active 
ON social_accounts(platform, is_disconnected, connected_at) 
WHERE is_disconnected = false;

-- User subscription status indexes
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_user_subscription_status_user_id 
ON user_subscription_status(user_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_user_subscription_status_trial 
ON user_subscription_status(is_trial_active, trial_ends_at) 
WHERE is_trial_active = true;

-- Brand kits indexes
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_brand_kits_user_id 
ON brand_kits(user_id);

-- History/posts indexes (if table exists)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_posts_user_id_created 
ON posts(user_id, created_at DESC) WHERE user_id IS NOT NULL;

-- Analyze tables after index creation
ANALYZE brand_profiles;
ANALYZE social_accounts;
ANALYZE user_subscription_status;
ANALYZE brand_kits;

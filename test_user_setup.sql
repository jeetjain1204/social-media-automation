-- =====================================================
-- TEST USER SETUP FOR BLOB APP
-- =====================================================
-- Run this in your Supabase Dashboard → SQL Editor to create a test user

-- Create a test user (this will also create the auth.users entry)
INSERT INTO auth.users (
  id,
  email,
  encrypted_password,
  email_confirmed_at,
  created_at,
  updated_at,
  raw_app_meta_data,
  raw_user_meta_data,
  is_super_admin,
  role,
  aud
) VALUES (
  gen_random_uuid(),
  'test@example.com',
  crypt('password123', gen_salt('bf')),
  NOW(),
  NOW(),
  NOW(),
  '{"provider": "email", "providers": ["email"]}',
  '{}',
  false,
  'authenticated',
  'authenticated'
);

-- Get the user ID for the test user
DO $$
DECLARE
    test_user_id UUID;
BEGIN
    -- Get the user ID
    SELECT id INTO test_user_id FROM auth.users WHERE email = 'test@example.com';
    
    -- Create user profile
    INSERT INTO public.users (
        id,
        full_name,
        email,
        created_at
    ) VALUES (
        test_user_id,
        'Test User',
        'test@example.com',
        NOW()
    );
    
    -- Create brand profile
    INSERT INTO public.brand_profiles (
        user_id,
        brand_name,
        persona,
        primary_goal,
        primary_color,
        created_at,
        updated_at
    ) VALUES (
        test_user_id,
        'Test Brand',
        'Professional',
        'Brand Awareness',
        '#004aad',
        NOW(),
        NOW()
    );
    
    -- Create brand kit
    INSERT INTO brand_kit.brand_kits (
        user_id,
        brand_name,
        created_at,
        updated_at
    ) VALUES (
        test_user_id,
        'Test Brand',
        NOW(),
        NOW()
    );
    
    -- Create subscription status
    INSERT INTO public.user_subscription_status (
        user_id,
        is_trial_active,
        is_active_subscriber,
        trial_ends_at,
        created_at,
        updated_at
    ) VALUES (
        test_user_id,
        true,
        false,
        NOW() + INTERVAL '14 days',
        NOW(),
        NOW()
    );
    
    RAISE NOTICE 'Test user created successfully with ID: %', test_user_id;
END $$;

-- =====================================================
-- TEST CREDENTIALS
-- =====================================================
-- Email: test@example.com
-- Password: password123
-- 
-- You can now use these credentials to log into your app
-- =====================================================


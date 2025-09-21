-- =====================================================
-- QUICK TEST USER SETUP
-- =====================================================
-- Run this in Supabase Dashboard → SQL Editor

-- Step 1: Create the auth user
INSERT INTO auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  recovery_sent_at,
  last_sign_in_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at,
  confirmation_token,
  email_change,
  email_change_token_new,
  recovery_token
) VALUES (
  '00000000-0000-0000-0000-000000000000',
  gen_random_uuid(),
  'authenticated',
  'authenticated',
  'test@example.com',
  crypt('password123', gen_salt('bf')),
  NOW(),
  NULL,
  NULL,
  '{"provider": "email", "providers": ["email"]}',
  '{}',
  NOW(),
  NOW(),
  '',
  '',
  '',
  ''
);

-- Step 2: Get the user ID and create related records
DO $$
DECLARE
    test_user_id UUID;
BEGIN
    -- Get the user ID we just created
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
    ) ON CONFLICT (id) DO NOTHING;
    
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
        'Solo Creator',
        'Brand Awareness',
        '#004aad',
        NOW(),
        NOW()
    ) ON CONFLICT (user_id) DO NOTHING;
    
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
    ) ON CONFLICT (user_id) DO NOTHING;
    
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
    ) ON CONFLICT (user_id) DO NOTHING;
    
    RAISE NOTICE 'Test user created successfully!';
    RAISE NOTICE 'Email: test@example.com';
    RAISE NOTICE 'Password: password123';
    RAISE NOTICE 'User ID: %', test_user_id;
END $$;


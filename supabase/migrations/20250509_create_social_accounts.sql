-- Create social_accounts table if it doesn't exist
CREATE TABLE IF NOT EXISTS social_accounts (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  platform TEXT NOT NULL CHECK (platform IN ('instagram', 'facebook', 'twitter', 'linkedin'),),,
  access_token TEXT NOT NULL,
  refresh_token TEXT,
  token_expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, platform)
);

-- Add RLS policies
ALTER TABLE social_accounts ENABLE ROW LEVEL SECURITY;

-- Allow users to view their own accounts
CREATE POLICY "Users can view their own social accounts" 
  ON social_accounts FOR SELECT 
  USING (auth.uid() = user_id);

-- Allow users to insert their own accounts
CREATE POLICY "Users can insert their own social accounts" 
  ON social_accounts FOR INSERT 
  WITH CHECK (auth.uid() = user_id);

-- Allow users to update their own accounts
CREATE POLICY "Users can update their own social accounts" 
  ON social_accounts FOR UPDATE 
  USING (auth.uid() = user_id);

-- Allow users to delete their own accounts
CREATE POLICY "Users can delete their own social accounts" 
  ON social_accounts FOR DELETE 
  USING (auth.uid() = user_id);

-- Make sure we have the error_message column in scheduled_posts
ALTER TABLE scheduled_posts ADD COLUMN IF NOT EXISTS error_message TEXT; 
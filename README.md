# Blob

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Database Setup

### Scheduled Posts Table
To set up the `scheduled_posts` table in Supabase:

1. Log in to your Supabase dashboard
2. Go to the SQL Editor
3. Run the following SQL query:

```sql
CREATE TABLE IF NOT EXISTS scheduled_posts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES auth.users(id) NOT NULL,
  content_text TEXT NOT NULL,
  media_url TEXT,
  platform TEXT NOT NULL,
  scheduled_at TIMESTAMP WITH TIME ZONE NOT NULL,
  status TEXT DEFAULT 'scheduled' CHECK (status IN ('scheduled', 'published', 'failed')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Set up RLS (Row Level Security)
ALTER TABLE scheduled_posts ENABLE ROW LEVEL SECURITY;

-- Create policy to allow users to see only their own scheduled posts
CREATE POLICY "Users can view their own scheduled posts" 
  ON scheduled_posts
  FOR SELECT
  USING (auth.uid() = user_id);

-- Create policy to allow users to insert their own scheduled posts
CREATE POLICY "Users can insert their own scheduled posts" 
  ON scheduled_posts
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Create policy to allow users to update their own scheduled posts
CREATE POLICY "Users can update their own scheduled posts" 
  ON scheduled_posts
  FOR UPDATE
  USING (auth.uid() = user_id);

-- Create policy to allow users to delete their own scheduled posts
CREATE POLICY "Users can delete their own scheduled posts" 
  ON scheduled_posts
  FOR DELETE
  USING (auth.uid() = user_id);
```

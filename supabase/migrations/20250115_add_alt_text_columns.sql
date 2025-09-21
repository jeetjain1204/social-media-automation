-- Add alt_text columns to support accessibility requirements
-- Migration: 20250115_add_alt_text_columns.sql

-- Add alt_text column to scheduled_posts table
ALTER TABLE scheduled_posts ADD COLUMN IF NOT EXISTS alt_texts TEXT[] DEFAULT '{}';

-- Add alt_text column to prebuilt_backgrounds table (for generated assets)
ALTER TABLE prebuilt_backgrounds ADD COLUMN IF NOT EXISTS alt_text TEXT NOT NULL DEFAULT '';

-- Backfill existing records with empty alt_text
UPDATE scheduled_posts SET alt_texts = '{}' WHERE alt_texts IS NULL;
UPDATE prebuilt_backgrounds SET alt_text = '' WHERE alt_text IS NULL OR alt_text = '';

-- Add constraint to ensure alt_texts array is not null
ALTER TABLE scheduled_posts ALTER COLUMN alt_texts SET NOT NULL;

-- Add check constraint for alt_text length (5-250 characters)
ALTER TABLE prebuilt_backgrounds ADD CONSTRAINT check_alt_text_length 
  CHECK (LENGTH(alt_text) >= 5 AND LENGTH(alt_text) <= 250);

-- Add check constraint for alt_texts array elements length
ALTER TABLE scheduled_posts ADD CONSTRAINT check_alt_texts_length 
  CHECK (array_length(alt_texts, 1) IS NULL OR 
         (array_length(alt_texts, 1) > 0 AND 
          ALL(LENGTH(alt_text) >= 5 AND LENGTH(alt_text) <= 250) IN (SELECT unnest(alt_texts))));

-- Create index for better query performance on alt_text
CREATE INDEX IF NOT EXISTS idx_prebuilt_backgrounds_alt_text 
  ON prebuilt_backgrounds(alt_text) WHERE alt_text != '';

-- Create index for better query performance on alt_texts array
CREATE INDEX IF NOT EXISTS idx_scheduled_posts_alt_texts 
  ON scheduled_posts USING GIN(alt_texts) WHERE array_length(alt_texts, 1) > 0;

-- Update RLS policies to include alt_text columns (they should already work since we're not changing access patterns)
-- The existing policies should continue to work as alt_text/alt_texts are just additional columns


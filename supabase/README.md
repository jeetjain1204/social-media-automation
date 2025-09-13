# Blob Supabase Integration

This directory contains files related to the Supabase integration for the Blob social media scheduling application.

## Structure

- **functions/** - Supabase Edge Functions
  - **post_scheduler/** - 15-minute scheduled function that processes posts
- **migrations/** - SQL migration files for setting up database tables

## Edge Functions

### post_scheduler

A scheduled Edge Function that runs every 15 minutes to check for posts that are due to be published. It:

1. Queries for posts scheduled in the past 15 minutes
2. Retrieves the user's social media access tokens
3. Attempts to post the content to the appropriate platforms
4. Updates the post status and logs the result

## Database Schema

The application uses the following tables:

1. **scheduled_posts** - Contains all scheduled posts with their status
2. **social_accounts** - Stores social media platform access tokens
3. **history** - Records published posts and their engagement metrics

## Deployment

To deploy the Edge Functions:

1. Install the Supabase CLI
2. Set up your Supabase credentials
3. Run: `supabase functions deploy post_scheduler --project-ref YOUR_PROJECT_REF`

For database migrations:

1. Run: `supabase migrations list --project-ref YOUR_PROJECT_REF`
2. To apply: `supabase db push --project-ref YOUR_PROJECT_REF`

## Environment Variables

The Edge Functions require the following environment variables:

- `SUPABASE_URL` - Your Supabase project URL
- `SUPABASE_SERVICE_ROLE_KEY` - Your Supabase service role key 
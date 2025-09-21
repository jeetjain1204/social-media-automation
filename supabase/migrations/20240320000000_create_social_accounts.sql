-- Create social_accounts table
create table if not exists public.social_accounts (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references auth.users(id) on delete cascade not null,
  platform text not null check (platform = 'linkedin'),
  access_token text not null,
  refresh_token text,
  account_name text,
  connected_at timestamp with time zone default timezone('utc'::text, now()) not null,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null,
  unique(user_id, platform)
);

-- Enable RLS
alter table public.social_accounts enable row level security;

-- Create policies (drop first if they exist)
drop policy if exists "Users can view their own social accounts" on public.social_accounts;
drop policy if exists "Users can insert their own social accounts" on public.social_accounts;
drop policy if exists "Users can update their own social accounts" on public.social_accounts;
drop policy if exists "Users can delete their own social accounts" on public.social_accounts;

create policy "Users can view their own social accounts"
  on public.social_accounts for select
  using (auth.uid() = user_id);

create policy "Users can insert their own social accounts"
  on public.social_accounts for insert
  with check (auth.uid() = user_id);

create policy "Users can update their own social accounts"
  on public.social_accounts for update
  using (auth.uid() = user_id);

create policy "Users can delete their own social accounts"
  on public.social_accounts for delete
  using (auth.uid() = user_id);

-- Create function to update updated_at
create or replace function public.handle_updated_at()
returns trigger as $$
begin
  new.updated_at = timezone('utc'::text, now());
  return new;
end;
$$ language plpgsql;

-- Create trigger for updated_at
create trigger handle_updated_at
  before update on public.social_accounts
  for each row
  execute function public.handle_updated_at(); 
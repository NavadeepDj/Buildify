-- Shared identity belongs to Supabase Auth. Local SQLite credentials are not imported.
begin;
create schema if not exists buildify_private;
revoke all on schema buildify_private from public, anon, authenticated;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(btrim(display_name)) between 1 and 80),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
revoke all on table public.profiles from public, anon, authenticated;
grant select on table public.profiles to authenticated;
grant update (display_name) on table public.profiles to authenticated;
grant all on table public.profiles to service_role;

create policy profiles_select_owner on public.profiles
  for select to authenticated using ((select auth.uid()) = id);
create policy profiles_update_owner on public.profiles
  for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

create function buildify_private.create_profile()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(nullif(left(btrim(new.raw_user_meta_data ->> 'display_name'), 80), ''), 'Buildify user'))
  on conflict (id) do nothing;
  return new;
end;
$$;
revoke all on function buildify_private.create_profile() from public, anon, authenticated;

create trigger on_buildify_account_created
  after insert on auth.users
  for each row execute function buildify_private.create_profile();

create function buildify_private.touch_profile()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at = now();
  return new;
end;
$$;
revoke all on function buildify_private.touch_profile() from public, anon, authenticated;
create trigger on_buildify_profile_updated
  before update on public.profiles
  for each row execute function buildify_private.touch_profile();

-- Handle identities created before this migration without changing their identity.
insert into public.profiles (id, display_name)
select id, coalesce(nullif(left(btrim(raw_user_meta_data ->> 'display_name'), 80), ''), 'Buildify user')
from auth.users on conflict (id) do nothing;

comment on table public.profiles is 'Owner-readable cloud profile. No passwords, verification codes, billing state, or device secrets.';
commit;

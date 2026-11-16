begin;

create table public.account_devices (
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id uuid not null,
  device_name text not null check (btrim(device_name) <> ''),
  platform text not null check (platform in ('android', 'ios')),
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  primary key (user_id, device_id)
);

create table public.account_projects (
  user_id uuid not null,
  device_id uuid not null,
  project_id uuid not null,
  project_name text not null,
  primary key (user_id, device_id, project_id),
  foreign key (user_id, device_id)
    references public.account_devices(user_id, device_id) on delete cascade
);

alter table public.account_devices enable row level security;
alter table public.account_projects enable row level security;
revoke all on public.account_devices, public.account_projects from public, anon, authenticated;
grant select, insert, update on public.account_devices to authenticated;
grant select, insert, update, delete on public.account_projects to authenticated;
grant all on public.account_devices, public.account_projects to service_role;

create policy account_devices_owner on public.account_devices
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy account_projects_owner on public.account_projects
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create function public.sync_mobile_catalog(
  account_id uuid,
  installation_id uuid,
  mobile_name text,
  mobile_platform text,
  projects jsonb
)
returns void language plpgsql security invoker set search_path = '' as $$
begin
  if account_id is null or account_id is distinct from auth.uid() then
    raise exception 'Account changed before catalog sync' using errcode = '42501';
  end if;

  -- This upsert locks the device row for the rest of the transaction.
  insert into public.account_devices (user_id, device_id, device_name, platform)
  values (account_id, installation_id, mobile_name, mobile_platform)
  on conflict (user_id, device_id) do update
    set device_name = excluded.device_name, platform = excluded.platform,
        last_seen_at = now();

  if projects is null then
    return;
  end if;

  insert into public.account_projects (user_id, device_id, project_id, project_name)
  select account_id, installation_id, incoming.project_id, incoming.project_name
  from jsonb_to_recordset(projects) as incoming(project_id uuid, project_name text)
  on conflict (user_id, device_id, project_id) do update
    set project_name = excluded.project_name;

  delete from public.account_projects as stored
  where stored.user_id = account_id and stored.device_id = installation_id
    and not exists (
      select 1 from jsonb_to_recordset(projects) as incoming(project_id uuid)
      where incoming.project_id = stored.project_id
    );
end;
$$;
revoke all on function public.sync_mobile_catalog(uuid, uuid, text, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.sync_mobile_catalog(uuid, uuid, text, text, jsonb)
  to authenticated;

notify pgrst, 'reload schema';
commit;
